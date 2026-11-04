/**
 * HandyTrust Cloud Functions
 *
 * Handles:
 *  1. Paystack webhook → escrow lock
 *  2. Auto-release escrow 14 days after the artisan submits completed
 *     work (no customer action) — see design/ESCROW_TIMING_AUDIT.md.
 *     Stage 2: autoReleaseAt/disputeWindowEndsAt are server-owned — set by
 *     onJobCompleted from the server-stamped submittedAt, and _releaseEscrow
 *     re-checks submittedAt + 14 days before releasing.
 *  3. Artisan stats update on job completion
 *  4. FCM push notifications on job state changes
 *  5. Dispute escalation alerts to admin
 */

const { onRequest, onCall, HttpsError } = require('firebase-functions/v2/https');
const { onDocumentUpdated, onDocumentCreated, onDocumentDeleted, onDocumentWritten } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const admin = require('firebase-admin');
const crypto = require('crypto');
const axios = require('axios');
const { GoogleGenerativeAI } = require('@google/generative-ai');

admin.initializeApp();
const db = admin.firestore();
const messaging = admin.messaging();

// Phase 10B remediation (design/PHASE_10_AUTHENTICATED_PAYMENT_QA.md) —
// pure, dependency-free HMAC check extracted so it can be unit-tested
// directly (functions/test/webhook_signature.test.js) against Paystack's
// documented requirement: HMAC-SHA512 of the RAW request body bytes, keyed
// with the account secret, compared against the x-paystack-signature
// header. https://paystack.com/docs/payments/webhooks/ (confirmed current
// as of this change) is explicit that hashing a re-serialized/parsed body
// (JSON.stringify(req.body), the previous implementation here) is "the
// single most common webhook bug" — key order/whitespace/number formatting
// are not guaranteed to round-trip identically to what Paystack actually
// sent and signed.
function _computePaystackSignature(rawBody, secretKey) {
  return crypto.createHmac('sha512', secretKey).update(rawBody).digest('hex');
}

exports._computePaystackSignature = _computePaystackSignature;

// Stage 7.1: constant-time comparison (a plain !== leaks timing).
function _signaturesMatch(expectedHex, headerValue) {
  if (typeof headerValue !== 'string' || headerValue.length !== expectedHex.length) return false;
  return crypto.timingSafeEqual(Buffer.from(expectedHex, 'utf8'), Buffer.from(headerValue, 'utf8'));
}
exports._signaturesMatch = _signaturesMatch;

// ─── Paystack Webhook ─────────────────────────────────────────────────────────
exports.paystackWebhook = onRequest(
  { secrets: ['PAYSTACK_SECRET_KEY'] },
  async (req, res) => {
    // Phase 10B fix: verify against req.rawBody (the Buffer Firebase
    // Functions v2's onRequest automatically populates ahead of JSON
    // parsing, specifically for this class of use case — no extra
    // middleware needed, unlike vanilla Express), not a re-serialized
    // JSON.stringify(req.body). See _computePaystackSignature's comment.
    const signatureHeader = req.headers['x-paystack-signature'];
    if (!signatureHeader) {
      console.error('Paystack webhook: missing x-paystack-signature header');
      return res.status(400).send('Missing signature');
    }
    if (!req.rawBody) {
      // Should be unreachable in the real deployed environment — Functions
      // v2 always populates this for onRequest. Fail closed rather than
      // silently falling back to a re-serialization that reintroduces the
      // exact bug this fix closes.
      console.error('Paystack webhook: req.rawBody unavailable — refusing to verify against a re-serialized body');
      return res.status(400).send('Cannot verify signature');
    }
    const hash = _computePaystackSignature(req.rawBody, process.env.PAYSTACK_SECRET_KEY);

    if (!_signaturesMatch(hash, signatureHeader)) {
      console.error('Invalid Paystack signature');
      return res.status(400).send('Invalid signature');
    }

    const event = req.body;

    if (event.event === 'charge.success') {
      const { reference, metadata } = event.data;
      const jobId = metadata?.jobId;

      if (!jobId || !reference) {
        console.error('charge.success without jobId/reference in metadata', metadata);
        return res.status(200).send('OK'); // Don't retry
      }

      try {
        // Stage 3: event.data is Paystack's signature-verified transaction
        // object; _lockEscrow checks its amount/currency/reference against
        // the server-created payment record. Every anomaly (late payment
        // after cancellation, duplicate charge, mismatch) is now RECORDED
        // as requires_refund + admin alert and answered 200 — previously it
        // threw, returned 500 and Paystack retried it for days. Only
        // genuine transient failures (Firestore unavailable) still 500.
        const outcome = await _lockEscrow(jobId, reference, event.data);
        console.log(`Escrow lock outcome for job ${jobId} ref ${reference}: ${outcome}`);
      } catch (err) {
        console.error('lockEscrow failed', err);
        return res.status(500).send('Internal error');
      }
    }

    // Async confirmation for processEscrowRelease's transfer — same
    // "webhook is authoritative, the synchronous API response is not"
    // pattern as charge.success above. reference is the escrow_releases
    // document ID (set as `reference` at transfer-initiation time in
    // processEscrowRelease specifically so this lookup needs no query).
    if (event.event === 'transfer.success' || event.event === 'transfer.failed' ||
        event.event === 'transfer.reversed') {
      const { reference } = event.data;
      if (!reference) {
        console.error('Transfer webhook missing reference', event.data);
        return res.status(200).send('OK');
      }

      try {
        // Stage 4: a retried payout uses reference "{jobId}-p{n}" (Paystack
        // rejects a reused transfer reference); the release doc stays {jobId}.
        const jobId = reference.replace(/-p\d+$/, '');
        const releaseSnap = await db.collection('escrow_releases').doc(jobId).get();
        if (!releaseSnap.exists) {
          console.error(`Transfer webhook: no escrow_releases doc for reference ${reference}`);
          return res.status(200).send('OK');
        }
        if (event.event === 'transfer.success') {
          // Idempotent: a redelivered success is a no-op (no duplicate
          // notification); a success for a superseded attempt is ignored.
          await _onTransferSucceeded(jobId, reference);
        } else if (!releaseSnap.data().transferReference ||
                   releaseSnap.data().transferReference === reference) {
          await _onTransferFailed(jobId, `paystack_${event.event}`, { processedAt: admin.firestore.Timestamp.now() });
        }
      } catch (err) {
        console.error('Transfer webhook handling failed', err);
        return res.status(500).send('Internal error');
      }
    }

    // Stage 4: refund lifecycle (refund.pending / processing / processed /
    // failed / needs-attention). Treated as a prompt to verify, never as
    // proof on its own — see _onRefundWebhook.
    if (typeof event.event === 'string' && event.event.startsWith('refund.')) {
      try {
        await _onRefundWebhook({ ...event.data, status: event.data?.status || event.event.slice('refund.'.length) });
      } catch (err) {
        console.error('Refund webhook handling failed', err);
        return res.status(500).send('Internal error');
      }
    }

    // Stage 7.1 (F-1): chargebacks. Signature already verified above.
    if (typeof event.event === 'string' && event.event.startsWith('charge.dispute.')) {
      try {
        if (CHARGEBACK_EVENTS.includes(event.event)) {
          await _onDisputeWebhook(event.event, event.data);
        } else {
          await db.collection('admin_alerts').doc(`chargeback_unsupported_${event.event}_${event.data?.id ?? 'unknown'}`).set({
            type: 'chargeback_event_unsupported', event: event.event, disputeId: event.data?.id ?? null,
            createdAt: admin.firestore.Timestamp.now(), resolved: false,
          }, { merge: true });
        }
      } catch (err) {
        console.error('Dispute webhook handling failed', err);
        return res.status(500).send('Internal error');
      }
    }

    return res.status(200).send('OK');
  }
);

// ─── Stage 3 — payment integrity ────────────────────────────────────────────
//
// Platform fee (policy D1): 5% of the artisan's agreed price, charged to the
// customer ON TOP of that price; the artisan is paid the full agreed price;
// HandyTrust absorbs Paystack processing/transfer/stamp-duty costs. The
// optional floor (minPlatformFeeNgn) and minimum job value are backend
// settings in config/platform (Admin-SDK/console write only — see
// firestore.rules `config`), defaulting to exactly the approved policy.
// Recommended floor values are in design/REMEDIATION_STAGE3_REPORT_*.md.
const PLATFORM_CONFIG_DEFAULTS = Object.freeze({
  platformFeePercent: 5,
  minPlatformFeeNgn: 0,
  // Policy D1 (Stage 4 decision): no job below ₦3,212 — the exact break-even
  // under official Paystack pricing (functions/test/stage3_payments.test.js).
  minJobValueNgn: 3212,
  abandonedPaymentHours: 24,   // policy D5
  // Stage 5 (policy D5) marketplace deadlines — integers (also read by
  // firestore.rules via cfgNum(), which needs whole hours).
  openJobDays: 7,
  quoteValidityHours: 48,
  bookingConfirmationHours: 24,
  // Stage 6 (policy D8): artisan service radius (km). firestore.rules bounds
  // the artisan's chosen radius by maxServiceRadiusKm.
  defaultServiceRadiusKm: 10,
  maxServiceRadiusKm: 25,
  // Stage 7.2 (policy decision 3): proportional partial-chargeback accounting
  // is used ONLY after Paystack test mode has confirmed how a partially
  // accepted dispute reports refund_amount. Until the owner sets this to true
  // in config/platform, every customer-refunded chargeback is treated as a
  // full reversal (the conservative full hold).
  partialChargebackAccountingVerified: false,
});

// Unknown/invalid values fall back to the default for that key — never to
// zero or to an unbounded number — so a malformed config can't zero the fee.
function _normalizePlatformConfig(raw) {
  const out = { ...PLATFORM_CONFIG_DEFAULTS };
  const src = raw || {};
  const okNum = (v, min, max) => typeof v === 'number' && Number.isFinite(v) && v >= min && v <= max;
  if (okNum(src.platformFeePercent, 0, 50)) out.platformFeePercent = src.platformFeePercent;
  if (okNum(src.minPlatformFeeNgn, 0, 100000)) out.minPlatformFeeNgn = src.minPlatformFeeNgn;
  if (okNum(src.minJobValueNgn, 1, 100000000)) out.minJobValueNgn = src.minJobValueNgn;
  if (okNum(src.abandonedPaymentHours, 1, 24 * 14)) out.abandonedPaymentHours = src.abandonedPaymentHours;
  const okInt = (v, min, max) => Number.isInteger(v) && v >= min && v <= max;
  if (okInt(src.openJobDays, 1, 90)) out.openJobDays = src.openJobDays;
  if (okInt(src.quoteValidityHours, 1, 24 * 30)) out.quoteValidityHours = src.quoteValidityHours;
  if (okInt(src.bookingConfirmationHours, 1, 24 * 14)) out.bookingConfirmationHours = src.bookingConfirmationHours;
  if (okNum(src.defaultServiceRadiusKm, 1, 200)) out.defaultServiceRadiusKm = src.defaultServiceRadiusKm;
  if (okNum(src.maxServiceRadiusKm, 1, 200)) out.maxServiceRadiusKm = src.maxServiceRadiusKm;
  // Only an explicit boolean true enables it; anything else stays conservative.
  out.partialChargebackAccountingVerified = src.partialChargebackAccountingVerified === true;
  return out;
}

async function _loadPlatformConfig() {
  try {
    const snap = await db.collection('config').doc('platform').get();
    return _normalizePlatformConfig(snap.exists ? snap.data() : null);
  } catch (err) {
    console.error('_loadPlatformConfig: falling back to defaults', err.message);
    return { ...PLATFORM_CONFIG_DEFAULTS };
  }
}

// Integer-kobo arithmetic throughout — never float naira — so the amount
// stored, charged and later compared are the same integer.
function _computeCharge(agreedAmountNgn, cfg) {
  if (typeof agreedAmountNgn !== 'number' || !Number.isFinite(agreedAmountNgn) || agreedAmountNgn <= 0) {
    return { ok: false, reason: 'invalid_agreed_amount' };
  }
  if (agreedAmountNgn < cfg.minJobValueNgn) {
    return { ok: false, reason: 'below_minimum_job_value' };
  }
  const serviceAmountKobo = Math.round(agreedAmountNgn * 100);
  const percentFeeKobo = Math.round((serviceAmountKobo * cfg.platformFeePercent) / 100);
  const platformFeeKobo = Math.max(percentFeeKobo, Math.round(cfg.minPlatformFeeNgn * 100));
  const totalKobo = serviceAmountKobo + platformFeeKobo;
  return {
    ok: true,
    serviceAmountKobo,
    platformFeeKobo,
    totalKobo,
    serviceAmount: serviceAmountKobo / 100,
    platformFee: platformFeeKobo / 100,
    totalCharged: totalKobo / 100,
    platformFeePercent: cfg.platformFeePercent,
    minPlatformFeeNgn: cfg.minPlatformFeeNgn,
  };
}

// The amount Paystack must have charged for this payment record. Pre-Stage-3
// records have no amountKobo and no fee (charged == amount).
function _expectedChargeKobo(payment) {
  if (Number.isInteger(payment?.amountKobo)) return payment.amountKobo;
  return typeof payment?.amount === 'number' ? Math.round(payment.amount * 100) : null;
}

// Stage 7.2: what is still held for this payment after any card-issuer
// reversal (a partial chargeback returned part of the charge to the customer).
function _availableKobo(payment) {
  const total = _expectedChargeKobo(payment);
  if (!Number.isInteger(total)) return total;
  const reversed = Number.isInteger(payment?.chargebackRefundedKobo) ? payment.chargebackRefundedKobo : 0;
  return Math.max(0, total - reversed);
}

// What the artisan is paid: the agreed service price only — never the
// platform fee. Legacy records (no serviceAmount) charged exactly `amount`.
function _payoutAmountNgn(payment) {
  if (typeof payment?.serviceAmount === 'number') return payment.serviceAmount;
  return payment?.amount;
}

// Single decision point for "a successful charge arrived — what do we do?",
// shared by the webhook, verifyPayment and the stale-payment sweep. Pure.
//
//   lock          — the job's current pending payment, exact match → escrowLocked
//   recover_lock  — the sweep had timed this payment out and reverted the job to
//                   inChat, then the charge succeeded after all; nothing newer
//                   is pending, so honour the customer's payment
//   already_locked— redelivery / webhook+verify race for the same charge
//   already_recorded / already_flagged_for_refund — redelivery after the
//                   charge was already applied, or already flagged
//   requires_refund — money was captured but must NOT fund this job: amount,
//                   currency or job mismatch; job cancelled; a different
//                   payment already funded it (duplicate); a newer payment is
//                   pending. Never silently dropped — recorded + admin alert.
//   not_successful — Paystack does not report success; nothing to do
function _decideChargeOutcome({ job, payment, charge, reference }) {
  if (!charge || charge.status !== 'success') return { outcome: 'not_successful' };
  if (!payment) return { outcome: 'requires_refund', reason: 'unknown_reference' };
  // Already-decided charges first, so a redelivery never re-decides them.
  if (payment.status === 'requiresRefund' || payment.status === 'refunded') {
    return { outcome: 'already_flagged_for_refund' };
  }
  if (charge.currency !== 'NGN') return { outcome: 'requires_refund', reason: 'currency_mismatch' };
  if (charge.amount !== _expectedChargeKobo(payment)) {
    return { outcome: 'requires_refund', reason: 'amount_mismatch' };
  }
  const metaJobId = charge.metadata?.jobId;
  if (!job || metaJobId !== payment.jobId) return { outcome: 'requires_refund', reason: 'job_mismatch' };

  if (job.status === 'escrowLocked' && job.paymentReference === reference) {
    return { outcome: 'already_locked' };
  }
  if (payment.status === 'escrowHeld' || payment.status === 'released') {
    return { outcome: 'already_recorded' };
  }
  if (job.status === 'paymentPending' && payment.status === 'pending' &&
      (!job.pendingPaymentReference || job.pendingPaymentReference === reference)) {
    return { outcome: 'lock' };
  }
  if (job.status === 'inChat' && payment.status === 'abandoned' &&
      payment.abandonReason === 'stale_timeout' &&
      job.agreementStatus === 'confirmed' && !job.pendingPaymentReference) {
    return { outcome: 'recover_lock' };
  }
  const reason = job.status === 'cancelled' ? 'paid_after_cancellation'
    : (job.status === 'paymentPending' ? 'superseded_by_newer_payment' : 'duplicate_or_late_payment');
  return { outcome: 'requires_refund', reason };
}

exports._normalizePlatformConfig = _normalizePlatformConfig;
exports._computeCharge = _computeCharge;
exports._expectedChargeKobo = _expectedChargeKobo;
exports._payoutAmountNgn = _payoutAmountNgn;
exports._decideChargeOutcome = _decideChargeOutcome;
exports.PLATFORM_CONFIG_DEFAULTS = PLATFORM_CONFIG_DEFAULTS;

// Applies a successful (or claimed-successful) Paystack charge. `charge` is
// Paystack's transaction object — from the signature-verified webhook body
// or from GET /transaction/verify — never from the client. Idempotent under
// redelivery: every write is decided inside one transaction from current
// state, and refund-required/alert records use deterministic IDs.
async function _lockEscrow(jobId, reference, charge) {
  const jobRef = db.collection('jobs').doc(jobId);
  const paymentQuery = await db
    .collection('payments')
    .where('paystackReference', '==', reference)
    .limit(1)
    .get();
  const paymentRef = paymentQuery.empty ? null : paymentQuery.docs[0].ref;

  const result = await db.runTransaction(async (tx) => {
    const [jobSnap, paySnap] = await Promise.all([
      tx.get(jobRef),
      paymentRef ? tx.get(paymentRef) : Promise.resolve(null),
    ]);
    const job = jobSnap.exists ? jobSnap.data() : null;
    const payment = paySnap?.exists ? paySnap.data() : null;
    const decision = _decideChargeOutcome({ job, payment, charge, reference });
    const now = admin.firestore.Timestamp.now();
    const chargeFacts = {
      paidAt: now,
      chargedAmountKobo: Number.isInteger(charge?.amount) ? charge.amount : null,
      paystackFeesKobo: Number.isInteger(charge?.fees) ? charge.fees : null,
      paystackChannel: charge?.channel || null,
      cardCountry: charge?.authorization?.country_code || null,
    };

    if (decision.outcome === 'lock' || decision.outcome === 'recover_lock') {
      tx.update(jobRef, {
        status: 'escrowLocked',
        paymentReference: reference,
        escrowLockedAt: now,
        pendingPaymentReference: admin.firestore.FieldValue.delete(),
      });
      tx.update(paymentRef, { status: 'escrowHeld', ...chargeFacts });
    } else if (decision.outcome === 'requires_refund') {
      if (paymentRef) {
        tx.update(paymentRef, { status: 'requiresRefund', refundReason: decision.reason, ...chargeFacts });
      } else {
        // A successful charge with no payment record at all (e.g. created
        // outside initializePaystackTransaction). Admin-SDK-only collection
        // (no rules match → client default-deny).
        tx.set(db.collection('orphan_charges').doc(reference), {
          reference,
          jobId,
          amountKobo: charge?.amount ?? null,
          currency: charge?.currency ?? null,
          reason: decision.reason,
          ...chargeFacts,
        }, { merge: true });
      }
      tx.set(db.collection('admin_alerts').doc(`charge_refund_${reference}`), {
        type: 'charge_requires_refund',
        jobId,
        reference,
        reason: decision.reason,
        createdAt: now,
        resolved: false,
      });
    }
    return { ...decision, cardCountry: chargeFacts.cardCountry };
  });

  if (result.outcome === 'lock' || result.outcome === 'recover_lock') {
    await _sendNotification(jobId, 'escrowLocked');
    // Policy D1: domestic (NGN, Nigerian-card) payments only until the
    // international economics are validated. The money is already captured,
    // so it funds the job rather than stranding the customer — but every
    // non-domestic card is surfaced to admins (the real control is keeping
    // international payments disabled on the Paystack account).
    if (result.cardCountry && result.cardCountry !== 'NG') {
      await db.collection('admin_alerts').doc(`intl_card_${reference}`).set({
        type: 'non_domestic_card_payment',
        jobId,
        reference,
        cardCountry: result.cardCountry,
        createdAt: admin.firestore.Timestamp.now(),
        resolved: false,
      });
    }
  }
  if (result.outcome === 'requires_refund') {
    console.error(`_lockEscrow: charge ${reference} for job ${jobId} requires refund — ${result.reason}`);
  }
  return result.outcome;
}

exports._lockEscrow = _lockEscrow;

// ─── Auto-release Escrow (runs every hour) ────────────────────────────────────
exports.autoReleaseEscrow = onSchedule('every 1 hours', async () => {
  const now = admin.firestore.Timestamp.now();

  const snap = await db
    .collection('jobs')
    .where('status', '==', 'submitted')
    .where('autoReleaseAt', '<=', now)
    .get();

  const releases = snap.docs.map((doc) =>
    _releaseEscrow(doc.id, 'auto-release: customer did not respond within 14 days of submission')
  );

  await Promise.allSettled(releases);
  console.log(`Auto-released ${releases.length} jobs`);
});

// Payout idempotency (design/PAYOUT_RACE_CONDITION_AUDIT.md): the release
// document ID is the jobId itself — same fixed-ID scheme JobService.
// confirmComplete (Dart, customer-manual path) uses — so one job can
// structurally have at most one escrow_releases document, ever, no matter
// which of the two release paths gets there first. Previously this
// function read the job and wrote both the job-status update and the
// escrow_releases doc with NO transaction and NO precondition check —
// unlike _lockEscrow above, which already gets this right. A customer
// manually confirming in the same window this function ran for the same
// job could create a second escrow_releases document (auto-ID, no
// existence check), and processEscrowRelease fires unconditionally on
// every new document — two documents meant two real Paystack transfers
// for one job. This transaction closes that race the same way
// _lockEscrow's already does: read-check-write, atomically, with
// Firestore's optimistic-concurrency retry protecting against a
// concurrent writer (transactional or not) touching either document
// this function read.
async function _releaseEscrow(jobId, reason) {
  const jobRef = db.collection('jobs').doc(jobId);
  const releaseRef = db.collection('escrow_releases').doc(jobId);

  const outcome = await db.runTransaction(async (tx) => {
    const [jobSnap, releaseSnap] = await Promise.all([tx.get(jobRef), tx.get(releaseRef)]);
    if (!jobSnap.exists) return { skipped: 'job_not_found' };

    const jobData = jobSnap.data();
    if (jobData.status !== 'submitted') {
      // Already completed (e.g. the customer manually confirmed first,
      // or a prior run of this same job already released it) — nothing
      // to do. Not an error; this is the race being caught safely.
      return { skipped: 'not_submitted', status: jobData.status };
    }
    if (releaseSnap.exists) {
      // Same job, release doc already exists — the other path won the
      // race. Do not touch the job or create a second release.
      return { skipped: 'already_released' };
    }
    // Stage 2 remediation (HT-005): autoReleaseAt is only the query hint.
    // The authoritative check is the server-stamped submittedAt + 14 days,
    // so a client-written or legacy autoReleaseAt can never shorten the
    // customer's review window. Missing submittedAt fails closed.
    const submittedAtMs = jobData.submittedAt?.toMillis?.();
    if (!_isReviewWindowElapsed(submittedAtMs, Date.now())) {
      return { skipped: 'review_window_not_elapsed', submittedAtMs };
    }
    // Stage 4: authorization is evaluated NOW, from current documents — not
    // from the artisan's status when the 14-day timer started. A fraud/
    // safety/security freeze holds the job in 'submitted' (funds stay in
    // escrow; the customer can still confirm or dispute) and alerts admins.
    const [artisanUserSnap, artisanSnap, settlementSnap] = await Promise.all([
      tx.get(db.collection('users').doc(jobData.artisanId || '_none')),
      tx.get(db.collection('artisans').doc(jobData.artisanId || '_none')),
      tx.get(db.collection('settlements').doc(jobId)),
    ]);
    if (settlementSnap.exists) return { skipped: 'settled' };
    const blockReason = _payoutBlockReason({
      job: jobData,
      artisanUser: artisanUserSnap.exists ? artisanUserSnap.data() : null,
      artisan: artisanSnap.exists ? artisanSnap.data() : null,
    });
    if (blockReason) return { skipped: 'payout_blocked', blockReason };

    const now = admin.firestore.Timestamp.now();
    tx.update(jobRef, {
      status: 'completed',
      completedAt: now,
      autoReleaseReason: reason,
    });
    tx.set(releaseRef, {
      jobId,
      requestedAt: now,
      status: 'pending',
      requestedBy: 'system',
      reason,
    });

    return { skipped: null, artisanId: jobData.artisanId, paymentReference: jobData.paymentReference };
  });

  if (outcome.skipped) {
    if (outcome.skipped === 'payout_blocked') {
      await db.collection('admin_alerts').doc(`autorelease_blocked_${jobId}`).set({
        type: 'autorelease_blocked', jobId, reason: outcome.blockReason,
        createdAt: admin.firestore.Timestamp.now(), resolved: false,
      }, { merge: true });
    }
    console.log(`_releaseEscrow: skipped job ${jobId} (${outcome.skipped}${outcome.blockReason ? `: ${outcome.blockReason}` : ''})`);
    return outcome;
  }

  // The payment is NOT marked 'released' here any more (Stage 4): the payout
  // path claims it (escrowHeld → releasing) and only the transfer webhook
  // marks it released — previously it read "released" before any money moved.

  // Artisan stats + trust score are NOT updated here (Stage 3, HT-017):
  // the status write above fires onJobCompleted, which already calls
  // _recordJobOutcome(…, 'completed'). Calling it here too counted every
  // auto-released job twice.

  console.log(`Released escrow for job ${jobId}: ${reason}`);
}

exports._releaseEscrow = _releaseEscrow;

// ─── Escrow payout — actually pays the artisan (Critical Finding 1.1) ───────
//
// Consumes escrow_releases documents created by either release path above
// (JobService.confirmComplete on the Dart side, or _releaseEscrow here) and
// triggers a real Paystack Transfer to the artisan's bank account. Without
// this function, "released" was only ever a Firestore status flip — no
// money moved. This is a Firestore-triggered function (fires on document
// creation), not a callable, so there is no client-side way to skip or
// fake it.
//
// KNOWN GAP, stated plainly: bank codes below are not verified against a
// live Paystack API call from this environment — see the comment on
// BANK_CODES. Do not treat a successful deploy of this function as proof
// the codes are correct; verify against Paystack's GET /bank list (or the
// resolve-account safety check below, which will itself catch a wrong
// code by failing to resolve a matching account name) before relying on
// this with real artisan payouts.

// Maps bank_details_screen.dart's exact 20 dropdown strings to Paystack's
// numeric bank codes. These are the standard, long-published NIBSS codes
// for the traditional banks (GTBank/Zenith/UBA/Access/First Bank/etc. have
// been stable for years and are widely used across Nigerian fintech
// integrations) — confidence is lower on the newer fintech entries (Kuda,
// Moniepoint, Opay, PalmPay use 6-digit NIP codes that are more recently
// assigned). VERIFY THIS TABLE against Paystack's GET /bank?country=nigeria
// before this function processes a real payout — it was not possible to
// call that endpoint or otherwise confirm these values from this
// environment.
const BANK_CODES = {
  'Access Bank': '044',
  'Ecobank Nigeria': '050',
  'Fidelity Bank': '070',
  'First Bank of Nigeria': '011',
  'First City Monument Bank (FCMB)': '214',
  'Guaranty Trust Bank (GTBank)': '058',
  'Heritage Bank': '030',
  'Keystone Bank': '082',
  'Kuda Bank': '50211',
  'Moniepoint MFB': '50515',
  'Opay': '999992',
  'PalmPay': '999991',
  'Polaris Bank': '076',
  'Providus Bank': '101',
  'Stanbic IBTC Bank': '221',
  'Sterling Bank': '232',
  'Union Bank': '032',
  'United Bank for Africa (UBA)': '033',
  'Wema Bank': '035',
  'Zenith Bank': '057',
};

// Resolves an account number + bank code to the bank's own record of the
// account holder's name, and compares it against what the artisan typed
// into bank_details_screen.dart. This is the real safety net for a wrong
// BANK_CODES entry (or a typo'd account number): if the code is wrong,
// resolution will either fail outright or return a name that doesn't
// match, and either way this function aborts rather than sending money
// based on an unverified guess. Paystack's own integration guidance
// recommends this exact check before initiating a transfer.
async function _resolveAndVerifyAccount(accountNumber, bankCode, expectedName) {
  const resp = await axios.get('https://api.paystack.co/bank/resolve', {
    params: { account_number: accountNumber, bank_code: bankCode },
    headers: { Authorization: `Bearer ${process.env.PAYSTACK_SECRET_KEY}` },
  });
  const resolvedName = (resp.data?.data?.account_name || '').trim().toLowerCase();
  const typedName = (expectedName || '').trim().toLowerCase();
  // Loose match (contains, either direction) rather than exact-equals —
  // "Chidi Okafor" vs "Okafor Chidi" or a middle name/initial difference
  // is common and legitimate; a completely different name is not.
  const namesOverlap =
    resolvedName.length > 0 &&
    typedName.length > 0 &&
    (resolvedName.includes(typedName) || typedName.includes(resolvedName) ||
      resolvedName.split(' ').some((part) => part.length > 2 && typedName.includes(part)));
  return { verified: namesOverlap, resolvedName };
}

// Creates a Paystack Transfer Recipient for this artisan, or reuses one
// already stored on artisan_private (avoids re-creating a recipient, and
// therefore re-resolving the account, on every single payout).
async function _getOrCreateTransferRecipient(artisanId, bankDetails) {
  const privateRef = db.collection('artisan_private').doc(artisanId);
  const privateSnap = await privateRef.get();
  const existing = privateSnap.data()?.paystackRecipientCode;
  if (existing) return existing;

  const bankCode = BANK_CODES[bankDetails.bankName];
  if (!bankCode) {
    throw new Error(`unknown_bank:${bankDetails.bankName}`);
  }

  const { verified, resolvedName } = await _resolveAndVerifyAccount(
    bankDetails.accountNumber,
    bankCode,
    bankDetails.accountName
  );
  if (!verified) {
    throw new Error(
      `account_verification_failed: typed "${bankDetails.accountName}", bank resolved "${resolvedName}"`
    );
  }

  const resp = await axios.post(
    'https://api.paystack.co/transferrecipient',
    {
      type: 'nuban',
      name: bankDetails.accountName,
      account_number: bankDetails.accountNumber,
      bank_code: bankCode,
      currency: 'NGN',
    },
    { headers: { Authorization: `Bearer ${process.env.PAYSTACK_SECRET_KEY}` } }
  );

  const recipientCode = resp.data.data.recipient_code;
  // Stored for reuse — artisan_private is already owner/admin-only per
  // firestore.rules, and this write is Admin SDK (bypasses rules anyway).
  await privateRef.set({ paystackRecipientCode: recipientCode }, { merge: true });
  return recipientCode;
}

// P0 remediation (design/P0_REMEDIATION_PLAN.md §3.4/§4.6) — pure,
// dependency-free predicates extracted out of processEscrowRelease so the
// exact fail-closed boundary conditions can be unit-tested directly,
// without needing to mock Firestore/Paystack (see
// functions/test/escrow_release_guards.test.js). Exported for that reason;
// not part of the public HTTP/callable surface.
function _isJobPayable(jobStatus) {
  return jobStatus === 'submitted' || jobStatus === 'completed';
}

function _amountsMatch(agreedAmount, paidAmount) {
  return Math.abs(agreedAmount - paidAmount) <= 0.01;
}

// Stage 2 remediation (HT-002): who asked for the release must be the
// person who actually paid — payments.payerId is written server-side by
// initializePaystackTransaction after checking job.customerId — or the
// auto-release cron ('system'). Independent of the job document, so a
// tampered customerId on the job (the self-payout exploit) cannot satisfy it.
function _isReleaseRequesterAuthorized(requestedBy, payerId) {
  if (requestedBy === 'system') return true;
  return typeof payerId === 'string' && payerId.length > 0 && requestedBy === payerId;
}

// Stage 2 remediation (HT-005): the customer's review window is measured
// from the server-stamped submittedAt (firestore.rules require
// submittedAt == request.time), never from a client-computed timestamp.
const REVIEW_WINDOW_MS = 14 * 24 * 60 * 60 * 1000;

function _reviewWindowEndMs(submittedAtMs) {
  return submittedAtMs + REVIEW_WINDOW_MS;
}

function _isReviewWindowElapsed(submittedAtMs, nowMs) {
  return typeof submittedAtMs === 'number' && nowMs >= _reviewWindowEndMs(submittedAtMs);
}

exports._isJobPayable = _isJobPayable;
exports._amountsMatch = _amountsMatch;
exports._isReleaseRequesterAuthorized = _isReleaseRequesterAuthorized;
exports._reviewWindowEndMs = _reviewWindowEndMs;
exports._isReviewWindowElapsed = _isReviewWindowElapsed;
exports.REVIEW_WINDOW_MS = REVIEW_WINDOW_MS;

// Body of processEscrowRelease, extracted (Stage 3) so the payout amount
// and authorization guards can be exercised against the Firestore emulator
// with a mocked Paystack client. `http` defaults to axios in production.
//
// Stage 4: two kinds of release share this path —
//   • normal: customer confirmation or 14-day auto-release; pays the
//     service price from an escrowHeld payment.
//   • settlement: an admin dispute/cancellation decision (release.settlementId
//     set); pays settlement.payoutLeg.amountKobo from a 'settling' payment.
// Either way, the LAST step before the transfer is one transaction that
// re-reads the artisan's suspension/freeze state, the job, the payment and
// any settlement, and only then claims the funds — so a fraud freeze applied
// at any point before that moment (including while this function runs)
// stops the money. `hooks.beforeFinalCheck` exists only for tests.
async function _processEscrowRelease(releaseRef, releaseId, http = axios, hooks = {}) {
  // Idempotency claim (design/PAYOUT_RACE_CONDITION_AUDIT.md) — only the
  // invocation that wins this atomic pending -> processing flip proceeds.
  const claimed = await db.runTransaction(async (tx) => {
    const snap = await tx.get(releaseRef);
    if (!snap.exists || snap.data().status !== 'pending') return null;
    tx.update(releaseRef, { status: 'processing' });
    return snap.data();
  });
  if (!claimed) {
    console.log(`processEscrowRelease: ${releaseRef.id} not pending — skipping (already claimed)`);
    return { skipped: 'not_pending' };
  }
  const jobId = claimed.jobId;
  const isSettlement = typeof claimed.settlementId === 'string' && claimed.settlementId.length > 0;
  const fail = async (failureReason, extra = {}) => {
    await releaseRef.update({ status: 'failed', failureReason, ...extra });
    return { failed: failureReason };
  };

  // Release/job identity invariant (releaseId == jobId), defense in depth.
  if (releaseId !== jobId) {
    console.error(`processEscrowRelease: release doc id ${releaseId} does not match its own jobId ${jobId}`);
    return fail('release_job_id_mismatch');
  }

  const jobRef = db.collection('jobs').doc(jobId);
  const jobSnap = await jobRef.get();
  if (!jobSnap.exists) return fail('job_not_found');
  const job = jobSnap.data();
  const artisanId = job.artisanId;
  if (!artisanId) return fail('no_artisan_on_job');

  let paymentRef;
  let payment;
  let amountKobo;
  const settlementRef = db.collection('settlements').doc(jobId);

  if (isSettlement) {
    const settlementSnap = await settlementRef.get();
    const settlement = settlementSnap.exists ? settlementSnap.data() : null;
    if (!settlement || claimed.settlementId !== jobId || !settlement.paymentId ||
        settlement.payoutLeg?.status !== 'pending' || !(settlement.payoutLeg?.amountKobo > 0)) {
      return fail('settlement_not_payable');
    }
    paymentRef = db.collection('payments').doc(settlement.paymentId);
    const ps = await paymentRef.get();
    payment = ps.exists ? ps.data() : null;
    if (!payment || payment.status !== 'settling') return fail('settlement_payment_not_settling');
    amountKobo = settlement.payoutLeg.amountKobo;
  } else {
    // The job must be in a state where a normal payout is legitimate.
    if (!_isJobPayable(job.status)) {
      console.error(`processEscrowRelease: job ${jobId} is in status "${job.status}" — refusing to pay out`);
      return fail('job_not_in_payable_state');
    }
    // Server-created, Paystack-verified payment record only — never a
    // client-writable amount (P0 remediation).
    const paySnap = await db.collection('payments')
      .where('jobId', '==', jobId).where('status', '==', 'escrowHeld').limit(1).get();
    if (paySnap.empty) {
      await _sendInAppNotification(artisanId, 'payout_blocked', 'Payout Blocked — No Verified Payment',
        'We could not find a verified payment for this job. Our team has been notified.', jobId);
      console.error(`processEscrowRelease: no escrowHeld payment for job ${jobId}`);
      return fail('no_verified_payment_on_record');
    }
    paymentRef = paySnap.docs[0].ref;
    payment = paySnap.docs[0].data();
    // Stage 2 (HT-002): requester must be the payer (or the cron).
    if (!_isReleaseRequesterAuthorized(claimed.requestedBy, payment.payerId) ||
        job.customerId !== payment.payerId) {
      const failureReason = job.customerId !== payment.payerId
        ? 'job_customer_payer_mismatch' : 'release_requester_not_payer';
      await db.collection('admin_alerts').doc(`payout_auth_${jobId}`).set({
        type: 'payout_authorization_failed', releaseId: releaseRef.id, jobId, reason: failureReason,
        createdAt: admin.firestore.Timestamp.now(), resolved: false,
      });
      console.error(`processEscrowRelease: ${failureReason} for job ${jobId} — refusing to pay out`);
      return fail(failureReason);
    }
    // Stage 3 (D1): the agreed SERVICE price only, never the platform fee.
    const amount = _payoutAmountNgn(payment);
    if (typeof amount !== 'number' || amount <= 0) return fail('invalid_payment_amount');
    if (typeof job.agreedAmount === 'number' && !_amountsMatch(job.agreedAmount, amount)) {
      console.error(`processEscrowRelease: job ${jobId} agreedAmount ${job.agreedAmount} != payment ${amount}`);
      return fail('payment_amount_mismatch');
    }
    amountKobo = Math.round(amount * 100);
  }

  const privateSnap = await db.collection('artisan_private').doc(artisanId).get();
  const bankDetails = privateSnap.data();
  if (!bankDetails?.accountNumber || !bankDetails?.bankName || !bankDetails?.accountName) {
    await _sendInAppNotification(artisanId, 'payout_blocked', 'Payout Blocked — Add Your Bank Details',
      'A job payment is ready to be released to you, but we need your bank details first.', jobId);
    await _mirrorPayoutStatus(jobId, 'delayed');
    return fail('no_bank_details', { retryCount: 0 });
  }

  let recipientCode;
  try {
    recipientCode = await _getOrCreateTransferRecipient(artisanId, bankDetails);
  } catch (err) {
    console.error(`processEscrowRelease: recipient creation failed for ${jobId}`, err.message);
    await _sendInAppNotification(artisanId, 'payout_blocked', 'Payout Blocked — Check Your Bank Details',
      'We could not verify your bank account details. Please review them and contact support if this persists.', jobId);
    return fail(err.message.startsWith('unknown_bank') || err.message.startsWith('account_verification_failed')
      ? err.message : 'recipient_creation_failed');
  }

  if (hooks.beforeFinalCheck) await hooks.beforeFinalCheck();

  // ── Final authorization + funds claim, immediately before the transfer ──
  const attempt = claimed.payoutAttempts || 1;
  const transferReference = attempt > 1 ? `${jobId}-p${attempt}` : jobId;
  const final = await db.runTransaction(async (tx) => {
    const [j, ps, u, a, st] = await Promise.all([
      tx.get(jobRef),
      tx.get(paymentRef),
      tx.get(db.collection('users').doc(artisanId)),
      tx.get(db.collection('artisans').doc(artisanId)),
      tx.get(settlementRef),
    ]);
    const pay = ps.data();
    const blockReason = _payoutBlockReason({
      job: j.data(), artisanUser: u.exists ? u.data() : null, artisan: a.exists ? a.data() : null,
      payment: pay, isSettlement,
    });
    if (blockReason) return { frozen: blockReason };
    if (isSettlement) {
      if (!st.exists || st.data().payoutLeg?.status !== 'pending' || pay?.status !== 'settling') {
        return { abort: 'settlement_changed' };
      }
      tx.update(settlementRef, { 'payoutLeg.status': 'processing', 'payoutLeg.transferReference': transferReference });
    } else {
      // A settlement (refund) created concurrently owns these funds now.
      if (st.exists) return { abort: 'superseded_by_settlement' };
      if (pay?.status !== 'escrowHeld') return { abort: 'funds_not_available' };
      // Stage 7.2: after a partial chargeback the artisan's full entitlement
      // may exceed what is still held — an admin settlement decides, never
      // an automatic payout.
      if (amountKobo > _availableKobo(pay)) return { frozen: 'chargeback_partial_shortfall' };
      tx.update(paymentRef, { status: 'releasing', releasingAt: admin.firestore.Timestamp.now() });
    }
    tx.update(releaseRef, { transferReference, payoutAttempts: attempt });
    _recordFinancialEvent(tx, {
      type: 'payout_authorized', jobId, paymentId: paymentRef.id, amountKobo,
      actor: claimed.requestedBy || 'system', details: { isSettlement, transferReference },
    });
    return { ok: true };
  });

  if (final.frozen) {
    await releaseRef.update({ status: 'frozen', frozenReason: final.frozen, frozenAt: admin.firestore.Timestamp.now() });
    await db.collection('admin_alerts').doc(`payout_frozen_${jobId}_${attempt}`).set({
      type: 'payout_frozen', jobId, reason: final.frozen, amountKobo,
      createdAt: admin.firestore.Timestamp.now(), resolved: false,
    });
    await _recordFinancialEvent(null, {
      type: 'payout_frozen', jobId, paymentId: paymentRef.id, amountKobo, actor: 'system',
      details: { reason: final.frozen },
    });
    console.warn(`processEscrowRelease: payout for job ${jobId} frozen — ${final.frozen}`);
    await _mirrorPayoutStatus(jobId, 'on_hold');
    return { frozen: final.frozen };
  }
  if (final.abort) return fail(final.abort);

  let transferData;
  try {
    const resp = await http.post(
      'https://api.paystack.co/transfer',
      {
        source: 'balance',
        amount: amountKobo,
        recipient: recipientCode,
        reason: `HandyTrust job payout — ${jobId}`,
        reference: transferReference,
      },
      { headers: { Authorization: `Bearer ${process.env.PAYSTACK_SECRET_KEY}` } }
    );
    transferData = resp?.data?.data || {};
  } catch (err) {
    // Only an error from the transfer request itself lands here.
    console.error(`processEscrowRelease: transfer failed for ${jobId}`, err.message);
    await _onTransferFailed(jobId, 'paystack_transfer_failed', { paystackRecipientCode: recipientCode });
    await _sendInAppNotification(artisanId, 'payout_blocked', 'Payout Failed',
      'Your payment transfer could not be completed. Our team has been notified.', jobId);
    return { failed: 'paystack_transfer_failed' };
  }

  // Stage 3 fix: once claimed, a release never returns to 'pending';
  // Paystack's raw status is kept separately. The transfer webhook is the
  // authoritative completion signal. Stage 4: this bookkeeping is OUTSIDE the
  // try above — a bookkeeping error after Paystack accepted the transfer
  // must never be recorded as a failed transfer (an admin retry would then
  // pay twice). Missing response fields are stored as null, not undefined.
  const paystackStatus = transferData.status || null;
  if (paystackStatus === 'failed') {
    await _onTransferFailed(jobId, 'paystack_reported_failed');
    return { failed: 'paystack_reported_failed' };
  }
  await releaseRef.update({
    paystackRecipientCode: recipientCode,
    paystackTransferCode: transferData.transfer_code ?? null,
    paystackTransferReference: transferReference,
    paystackTransferStatus: paystackStatus,
    status: 'processing',
  });
  await _mirrorPayoutStatus(jobId, 'processing');
  return { transferred: amountKobo };
}

exports._processEscrowRelease = _processEscrowRelease;

exports.processEscrowRelease = onDocumentCreated(
  { document: 'escrow_releases/{releaseId}', secrets: ['PAYSTACK_SECRET_KEY'] },
  (event) => _processEscrowRelease(event.data.ref, event.params.releaseId, _transferHttp)
);

// Writes an in-app notification document directly (Admin SDK — bypasses
// firestore.rules' client type-whitelist, which only constrains client
// writes; these two types are server-only events with no client write
// path, matching how job-status pushes already work in _sendNotification).
// Stage 6: the ONLY notification writer for the app (clients can no longer
// create notifications). Every notification carries a deep-link `route`
// (HT-026). `dedupeKey` (trigger event id + recipient) makes a redelivered
// trigger overwrite the same document instead of pushing twice.
async function _sendInAppNotification(userId, type, title, body, jobId, opts = {}) {
  if (!userId) return;
  const ref = opts.dedupeKey
    ? db.collection('notifications').doc(String(opts.dedupeKey).replace(/[^A-Za-z0-9_-]/g, '_').slice(0, 900))
    : db.collection('notifications').doc();
  const doc = {
    id: ref.id,
    userId,
    type,
    title,
    body,
    isRead: false,
    createdAt: admin.firestore.Timestamp.now(),
    jobId: jobId || null,
    route: opts.route || (jobId ? `/job/${jobId}` : '/notifications'),
  };
  if (opts.dedupeKey) {
    try {
      await ref.create(doc);
    } catch (err) {
      if (err.code !== 6 /* ALREADY_EXISTS */) throw err;
    }
    return;
  }
  await ref.set(doc);
}

// Single, unified push-delivery mechanism for every notification source —
// see design/STITCH_NOTIFICATION_AUDIT.md. Fires on ANY new
// notifications/{id} document, regardless of whether it was written by
// _sendInAppNotification above, this file's _sendNotification (job-status
// events, below), or the Dart client's NotificationService.send()
// (quotes/disputes/verification/agreement — see
// lib/core/services/notification_service.dart). Previously each of those
// wrote the in-app doc but never pushed, while _sendNotification pushed
// but never wrote the in-app doc — two non-overlapping pipelines. This
// closes both gaps at once, from one place, instead of duplicating
// messaging.send() calls at every write site.
exports.onNotificationCreated = onDocumentCreated(
  'notifications/{notifId}',
  async (event) => {
    const notif = event.data.data();
    if (!notif?.userId) return;

    try {
      const tokenDoc = await db.collection('fcm_tokens').doc(notif.userId).get();
      const token = tokenDoc.data()?.token;
      if (!token) return; // no push registered for this user — in-app entry still exists

      await messaging.send({
        token,
        notification: { title: notif.title, body: notif.body },
        data: {
          type: notif.type || '',
          jobId: notif.jobId || '',
          // Stage 6 (HT-026): the app navigates to this on tap.
          route: notif.route || (notif.jobId ? `/job/${notif.jobId}` : '/notifications'),
        },
        android: { priority: 'high' },
        apns: { payload: { aps: { sound: 'default' } } },
      });
    } catch (err) {
      console.error(`onNotificationCreated: FCM send failed for ${notif.userId}:`, err.message);
    }
  }
);

// ─── Reconciliation sweep — catches any release stuck in pending/processing ──
// Runs daily. Does not retry automatically (a stuck transfer usually means
// something needs a human look, e.g. Paystack balance, a flaky recipient
// record) — writes an admin_alerts entry, reusing the same collection
// disputes already alert into, rather than silently doing nothing.
exports.reconcileStuckEscrowReleases = onSchedule('every 24 hours', async () => {
  const cutoff = admin.firestore.Timestamp.fromDate(new Date(Date.now() - 2 * 60 * 60 * 1000));
  const snap = await db
    .collection('escrow_releases')
    .where('status', 'in', ['pending', 'processing'])
    .where('requestedAt', '<=', cutoff)
    .get();

  for (const doc of snap.docs) {
    await db.collection('admin_alerts').add({
      type: 'stuck_escrow_release',
      releaseId: doc.id,
      jobId: doc.data().jobId,
      status: doc.data().status,
      createdAt: admin.firestore.Timestamp.now(),
      resolved: false,
    });
  }
  console.log(`reconcileStuckEscrowReleases: flagged ${snap.docs.length} stuck release(s)`);
});

// ═══ Stage 4 — refunds, settlements, payout freezes ═════════════════════════
//
// Money can leave escrow in exactly three ways, each claimed atomically on
// the payment document so two of them can never both happen:
//   payout   escrowHeld → releasing → released     (_processEscrowRelease)
//   refund   requiresRefund → refundPending → refunded (_refundCharge)
//   settle   escrowHeld → settling → released | refunded | settled
//            (_settleJob: admin dispute / paid-cancellation decision)
// A refund is never "done" because we asked for it: only a Paystack-reported
// status (create response, refund webhook re-verified by fetch, or the
// reconciliation sweep) advances it, and 'processed' is terminal.

// ── Paystack client (injectable for tests — fakes only, never real calls) ──
function _paystackAuth() {
  return { headers: { Authorization: `Bearer ${process.env.PAYSTACK_SECRET_KEY}` } };
}
const _defaultPaystack = {
  // NOTE: amount is sent in kobo, Paystack's subunit convention for every
  // other endpoint used here. Confirm in Paystack test mode before go-live
  // (the refund docs page doesn't state the unit explicitly).
  createRefund: async ({ transaction, amountKobo }) =>
    (await axios.post('https://api.paystack.co/refund', { transaction, amount: amountKobo }, _paystackAuth())).data.data,
  fetchRefund: async (id) =>
    (await axios.get(`https://api.paystack.co/refund/${encodeURIComponent(id)}`, _paystackAuth())).data.data,
  listRefunds: async (transaction) =>
    (await axios.get('https://api.paystack.co/refund', { ..._paystackAuth(), params: { transaction } })).data.data,
  // Stage 7.1: GET /dispute/:id (Paystack Disputes API). The webhook
  // payload shape is not documented; the fetched dispute is authoritative.
  fetchDispute: async (id) =>
    (await axios.get(`https://api.paystack.co/dispute/${encodeURIComponent(id)}`, _paystackAuth())).data.data,
};
let _paystack = _defaultPaystack;
let _transferHttp = axios;
exports._setPaystackFakes = ({ paystack, transferHttp } = {}) => {
  _paystack = paystack || _defaultPaystack;
  _transferHttp = transferHttp || axios;
};

// ── Payout freezes (policy D9 + Stage 4 critical requirement) ──
const FREEZING_SUSPENSION_TYPES = ['fraud', 'safety', 'security'];

function _isFreezingSuspension(u) {
  if (!u || u.accountStatus !== 'suspended') return false;
  // An unclassified (legacy) suspension fails closed until an admin
  // classifies it; administrative/verification suspensions don't freeze.
  return !u.suspensionType || FREEZING_SUSPENSION_TYPES.includes(u.suspensionType);
}

// Pure. Evaluated from freshly-read documents inside the transaction that
// claims the funds, immediately before every transfer, and by auto-release.
// Stage 7.1: an open chargeback blocks every payout, settlements included.
function _payoutBlockReason({ job, artisanUser, artisan, payment = null, isSettlement = false }) {
  if (job?.chargebackHold === true || payment?.chargebackHold === true) return 'chargeback_open';
  if (job?.payoutFrozen === true) return 'job_payout_frozen';
  if (artisanUser?.payoutFrozen === true || artisan?.payoutFrozen === true) return 'artisan_payout_frozen';
  if (_isFreezingSuspension(artisanUser) || _isFreezingSuspension(artisan)) return 'artisan_suspended_freeze';
  if (!isSettlement) {
    if (job?.status === 'disputed') return 'job_disputed';
    if (job?.cancellationRequestStatus === 'pending') return 'cancellation_request_pending';
  }
  return null;
}

// Append-only financial audit trail (Admin-SDK only; clients denied by rules).
function _recordFinancialEvent(tx, ev) {
  const ref = db.collection('financial_events').doc();
  const doc = { id: ref.id, at: admin.firestore.Timestamp.now(), ...ev };
  if (tx) {
    tx.set(ref, doc);
    return Promise.resolve();
  }
  return ref.set(doc);
}

// ── Transfer outcomes (webhook or synchronous failure) ──
async function _onTransferFailed(jobId, reason, extra = {}) {
  const releaseRef = db.collection('escrow_releases').doc(jobId);
  const settlementRef = db.collection('settlements').doc(jobId);
  const changed = await db.runTransaction(async (tx) => {
    const [r, st, releasing] = await Promise.all([
      tx.get(releaseRef),
      tx.get(settlementRef),
      tx.get(db.collection('payments').where('jobId', '==', jobId).where('status', '==', 'releasing')),
    ]);
    if (!r.exists || r.data().status === 'completed') return false; // never undo a confirmed payout
    const rel = r.data();
    tx.update(releaseRef, { status: 'failed', failureReason: reason, ...extra });
    if (rel.settlementId && st.exists) {
      tx.update(settlementRef, { 'payoutLeg.status': 'failed', 'payoutLeg.failureReason': reason });
    } else {
      // Give the funds claim back so an admin can retry the payout.
      releasing.docs.forEach((d) => tx.update(d.ref, { status: 'escrowHeld' }));
    }
    _recordFinancialEvent(tx, { type: 'payout_failed', jobId, actor: 'paystack', details: { reason, attempt: rel.payoutAttempts || 1 } });
    return rel.payoutAttempts || 1;
  });
  if (changed) {
    await _mirrorPayoutStatus(jobId, 'delayed');
    await db.collection('admin_alerts').doc(`transfer_failed_${jobId}_${changed}`).set({
      type: 'transfer_failed', jobId, reason, createdAt: admin.firestore.Timestamp.now(), resolved: false,
    });
  }
}

async function _onTransferSucceeded(jobId, transferReference) {
  const releaseRef = db.collection('escrow_releases').doc(jobId);
  const settlementRef = db.collection('settlements').doc(jobId);
  const out = await db.runTransaction(async (tx) => {
    const [r, st, releasing] = await Promise.all([
      tx.get(releaseRef),
      tx.get(settlementRef),
      // 'escrowHeld' too: a transfer initiated by pre-Stage-4 code never
      // claimed the payment. Its success must still mark the payment
      // released, or a later settlement could refund funds already paid out.
      tx.get(db.collection('payments').where('jobId', '==', jobId).where('status', 'in', ['releasing', 'escrowHeld'])),
    ]);
    if (!r.exists) return { missing: true };
    const rel = r.data();
    if (rel.status === 'completed') return { duplicate: true };
    if (rel.transferReference && rel.transferReference !== transferReference) return { staleAttempt: true };
    const now = admin.firestore.Timestamp.now();
    tx.update(releaseRef, { status: 'completed', processedAt: now });
    if (rel.settlementId && st.exists) {
      tx.update(settlementRef, { 'payoutLeg.status': 'completed', 'payoutLeg.completedAt': now });
    } else {
      releasing.docs.forEach((d) => tx.update(d.ref, { status: 'released', releasedAt: now }));
    }
    _recordFinancialEvent(tx, { type: 'payout_completed', jobId, actor: 'paystack', details: { transferReference } });
    const chargebackOpen = releasing.docs.some((d) => d.data().chargebackHold === true);
    return { ok: true, settlement: !!rel.settlementId, chargebackOpen };
  });
  if (out.ok) {
    // Stage 7.1: a transfer initiated before a chargeback arrived cannot be
    // recalled; make the completed payout visible on the chargeback case.
    if (out.chargebackOpen) {
      await db.collection('admin_alerts').doc(`chargeback_payout_completed_${jobId}`).set({
        type: 'chargeback_payout_completed', jobId, transferReference,
        createdAt: admin.firestore.Timestamp.now(), resolved: false,
      }, { merge: true });
    }
    await _mirrorPayoutStatus(jobId, 'paid');
    if (out.settlement) await _finalizeSettlementIfDone(jobId);
    const job = (await db.collection('jobs').doc(jobId).get()).data();
    if (job?.artisanId) {
      await _sendInAppNotification(job.artisanId, 'payout_completed', 'Payment Sent',
        'Your payout has been sent to your bank account.', jobId);
    }
  }
  return out;
}

// ── Refund state machine ──
const REFUND_STATUS_FROM_PAYSTACK = Object.freeze({
  pending: 'submitted',
  processing: 'processing',
  processed: 'processed',
  failed: 'failed',
  'needs-attention': 'needs_attention',
});

function _mapRefundStatus(paystackStatus) {
  return REFUND_STATUS_FROM_PAYSTACK[paystackStatus] || null;
}

// Pure. 'processed' is terminal; an unknown Paystack status changes nothing.
function _nextRefundStatus(current, incoming) {
  if (!incoming || current === 'processed') return current;
  return incoming;
}

async function _applyRefundStatus(refundId, paystackStatus, info = {}) {
  const incoming = _mapRefundStatus(paystackStatus);
  const ref = db.collection('refunds').doc(refundId);
  const out = await db.runTransaction(async (tx) => {
    const s = await tx.get(ref);
    if (!s.exists) return null;
    const r = s.data();
    const payRef = r.paymentId ? db.collection('payments').doc(r.paymentId) : null;
    const jobRef = r.jobId ? db.collection('jobs').doc(r.jobId) : null;
    const stRef = r.settlementId ? db.collection('settlements').doc(r.settlementId) : null;
    const [ps, js, st] = await Promise.all([
      payRef ? tx.get(payRef) : null, jobRef ? tx.get(jobRef) : null, stRef ? tx.get(stRef) : null,
    ]);
    const now = admin.firestore.Timestamp.now();
    const next = _nextRefundStatus(r.status, incoming);
    const update = { paystackStatus: paystackStatus || r.paystackStatus || null, updatedAt: now };
    if (info.paystackRefundId) update.paystackRefundId = String(info.paystackRefundId);
    if (info.failureReason) update.failureReason = info.failureReason;
    if (next === r.status) {
      tx.update(ref, update);
      return { changed: false, status: next, r };
    }
    update.status = next;
    if (next === 'processed') update.processedAt = now;
    tx.update(ref, update);
    if (ps?.exists) {
      tx.update(payRef, {
        refundStatus: next,
        ...(next === 'processed' && !r.settlementId ? { status: 'refunded', refundedAt: now } : {}),
      });
    }
    if (js?.exists) tx.update(jobRef, { refundStatus: next });
    if (st?.exists) tx.update(stRef, { 'refundLeg.status': next === 'processed' ? 'completed' : next });
    _recordFinancialEvent(tx, {
      type: `refund_${next}`, jobId: r.jobId || null, paymentId: r.paymentId || null, refundId,
      settlementId: r.settlementId || null, amountKobo: r.amountKobo, actor: 'paystack',
      details: { paystackStatus: paystackStatus || null, source: info.source || null, attempt: r.attempts || 0 },
    });
    return { changed: true, status: next, r };
  });
  if (!out) return null;
  if (out.changed && (out.status === 'failed' || out.status === 'needs_attention')) {
    await db.collection('admin_alerts').doc(`refund_${out.status}_${refundId}_${out.r.attempts || 0}`).set({
      type: out.status === 'failed' ? 'refund_failed' : 'refund_needs_attention',
      refundId, jobId: out.r.jobId || null, reason: info.failureReason || out.status,
      createdAt: admin.firestore.Timestamp.now(), resolved: false,
    });
  }
  if (out.changed && out.status === 'processed') {
    if (out.r.settlementId) await _finalizeSettlementIfDone(out.r.settlementId);
    if (out.r.customerId) {
      await _sendInAppNotification(out.r.customerId, 'job_status_update', 'Refund Processed',
        'Your refund has been processed by our payment provider. It can take up to 10 business days to reach your account.',
        out.r.jobId || null);
    }
  }
  return out.status;
}

async function _submitRefund(refundId) {
  const ref = db.collection('refunds').doc(refundId);
  const claim = await db.runTransaction(async (tx) => {
    const s = await tx.get(ref);
    if (!s.exists || s.data().status !== 'requested') return null;
    // Stage 7.1: never refund a charge the customer's bank may also reverse.
    const openCb = await tx.get(db.collection('chargebacks')
      .where('reference', '==', s.data().paystackReference || refundId)
      .where('status', 'in', CHARGEBACK_OPEN_STATUSES).limit(1));
    if (!openCb.empty) {
      tx.update(ref, { status: 'held', heldReason: 'chargeback_open', heldAt: admin.firestore.Timestamp.now() });
      return { held: openCb.docs[0].id, jobId: s.data().jobId || null };
    }
    const attempts = (s.data().attempts || 0) + 1;
    tx.update(ref, { status: 'submitting', attempts, lastSubmittedAt: admin.firestore.Timestamp.now() });
    return { ...s.data(), attempts };
  });
  if (!claim) return { skipped: true };
  if (claim.held) {
    await db.collection('admin_alerts').doc(`refund_held_chargeback_${refundId}`).set({
      type: 'refund_held_chargeback', refundId, chargebackId: claim.held, jobId: claim.jobId,
      createdAt: admin.firestore.Timestamp.now(), resolved: false,
    }, { merge: true });
    return { held: 'chargeback_open' };
  }
  try {
    const data = await _paystack.createRefund({ transaction: claim.paystackReference, amountKobo: claim.amountKobo });
    // Status comes from Paystack's own response — 'pending' stays pending.
    await _applyRefundStatus(refundId, data?.status, { paystackRefundId: data?.id, source: 'create_response' });
    return { submitted: true, paystackStatus: data?.status ?? null };
  } catch (err) {
    const httpStatus = err.response?.status;
    if (httpStatus >= 400 && httpStatus < 500) {
      // Paystack refused the request outright — no refund exists.
      await _applyRefundStatus(refundId, 'failed', {
        failureReason: `paystack_rejected_${httpStatus}${err.response?.data?.message ? `: ${err.response.data.message}` : ''}`,
        source: 'create_rejected',
      });
      return { rejected: true };
    }
    // Network error / 5xx / timeout: a refund MAY have been created. Never
    // assume either way and never resubmit blindly — reconciliation decides.
    await ref.update({ status: 'submit_unknown', submitError: err.message, updatedAt: admin.firestore.Timestamp.now() });
    await db.collection('admin_alerts').doc(`refund_unknown_${refundId}_${claim.attempts}`).set({
      type: 'refund_submit_unknown', refundId, jobId: claim.jobId || null,
      createdAt: admin.firestore.Timestamp.now(), resolved: false,
    });
    return { unknown: true };
  }
}

// Refund webhooks carry no refund id — only transaction_reference, which is
// our refund document id. The webhook is treated as a prompt to verify:
// when the refund id is known, the authoritative status is fetched.
async function _onRefundWebhook(data) {
  const refundId = data?.transaction_reference;
  if (!refundId) return 'ignored';
  const snap = await db.collection('refunds').doc(refundId).get();
  if (!snap.exists) {
    await db.collection('admin_alerts').doc(`refund_unmatched_${refundId}_${data.status}`).set({
      type: 'refund_webhook_unmatched', reference: refundId, status: data.status || null,
      createdAt: admin.firestore.Timestamp.now(), resolved: false,
    });
    return 'unmatched';
  }
  const r = snap.data();
  let status = data.status;
  if (r.paystackRefundId) {
    try {
      status = (await _paystack.fetchRefund(r.paystackRefundId))?.status ?? status;
    } catch (err) {
      // Can't confirm which attempt a 'failed' belongs to — let reconciliation decide.
      if (status === 'failed' && (r.attempts || 0) > 1) return 'deferred';
    }
  }
  if (data.amount !== undefined && Number(data.amount) !== r.amountKobo) {
    await db.collection('admin_alerts').doc(`refund_amount_${refundId}`).set({
      type: 'refund_amount_mismatch', refundId, reportedAmount: String(data.amount), expectedKobo: r.amountKobo,
      createdAt: admin.firestore.Timestamp.now(), resolved: false,
    });
  }
  return _applyRefundStatus(refundId, status, { source: 'webhook' });
}

async function _reconcileRefunds(nowMs = Date.now()) {
  const snap = await db.collection('refunds')
    .where('status', 'in', ['submitted', 'processing', 'submit_unknown', 'needs_attention']).limit(200).get();
  const summary = { examined: 0, updated: 0 };
  for (const d of snap.docs) {
    summary.examined++;
    const r = d.data();
    const ageMs = nowMs - (r.lastSubmittedAt?.toMillis?.() ?? r.updatedAt?.toMillis?.() ?? 0);
    if (ageMs < 30 * 60 * 1000) continue;
    try {
      if (r.paystackRefundId) {
        const fetched = await _paystack.fetchRefund(r.paystackRefundId);
        if ((await _applyRefundStatus(d.id, fetched?.status, { source: 'reconcile_fetch' })) !== r.status) summary.updated++;
        continue;
      }
      if (r.status === 'submit_unknown') {
        const list = await _paystack.listRefunds(r.paystackReference);
        const match = (Array.isArray(list) ? list : []).find((x) =>
          Number(x.amount) === r.amountKobo && x.status !== 'failed');
        if (match) {
          await _applyRefundStatus(d.id, match.status, { paystackRefundId: match.id, source: 'reconcile_list' });
          summary.updated++;
        } else if (ageMs > 24 * 60 * 60 * 1000) {
          // A full day with no refund visible at Paystack: it was not created.
          await _applyRefundStatus(d.id, 'failed', { failureReason: 'not_found_after_unknown_submit', source: 'reconcile_list' });
          summary.updated++;
        }
      }
    } catch (err) {
      console.error(`_reconcileRefunds: ${d.id}`, err.message);
    }
  }
  return summary;
}

// ── Chargebacks / card disputes (Stage 7.1, F-1) ──
//
// Paystack sends charge.dispute.create when a dispute is logged,
// charge.dispute.remind every 4 hours while unresolved, and
// charge.dispute.resolve once resolved; unanswered disputes are auto-accepted
// after 16 hours and refunded from the Paystack balance (Paystack "Manage
// Disputes"). The webhook payload is NOT documented, so every event is a
// prompt to fetch the dispute (GET /dispute/:id) and use that.
//
// Case status (ours):  open → paystack_resolved → closed (admin)
//   - Any webhook for an unknown dispute creates the case and places a HOLD
//     on the payment and job. A hold only stops money moving; no webhook ever
//     releases, refunds or confiscates funds.
//   - Paystack status only moves forward (open-type → resolved/archived), so
//     delayed or out-of-order events never reopen or regress a case.
//   - Only an admin closes a case (adminCloseChargeback), after Paystack
//     reports it resolved; that is the only way a hold is lifted. Resuming a
//     payout or refund is then a separate, explicit admin retry.
const CHARGEBACK_EVENTS = ['charge.dispute.create', 'charge.dispute.remind', 'charge.dispute.resolve'];
const CHARGEBACK_OPEN_STATUSES = ['open', 'paystack_resolved'];
const CHARGEBACK_OUTCOMES = ['merchant_won', 'customer_refunded'];
const DISPUTE_STATUS_RANK = Object.freeze({
  'awaiting-merchant-feedback': 1, 'awaiting-bank-feedback': 1, pending: 1, resolved: 2, archived: 2,
});

// Pure. Unknown statuses never replace a known one; known ones never regress.
function _nextDisputeStatus(current, incoming) {
  const rIn = DISPUTE_STATUS_RANK[incoming];
  if (!rIn) return current || null;
  const rCur = DISPUTE_STATUS_RANK[current] || 0;
  return rIn >= rCur ? incoming : current;
}

// Pure. Both shapes appear in Paystack's dispute objects.
function _disputeReference(d) {
  const r = d?.transaction?.reference ?? d?.transaction_reference ?? null;
  return typeof r === 'string' && r ? r : null;
}

// Pure. Where the funds were when the chargeback arrived.
function _payoutStateAtChargeback(payment, release) {
  if (!payment) return 'no_payment_record';
  if (payment.status === 'escrowHeld') return release && ['processing'].includes(release.status) ? 'payout_initiated' : 'in_escrow';
  if (payment.status === 'releasing') return 'payout_initiated';
  if (payment.status === 'released') return 'paid_out';
  if (payment.status === 'settling') return 'settlement_in_progress';
  if (['settled', 'refunded', 'refundPending'].includes(payment.status)) return `already_${payment.status}`;
  return `payment_${payment.status}`;
}

async function _findPaymentByReference(reference) {
  if (!reference) return null;
  const direct = await db.collection('payments').doc(reference).get();
  if (direct.exists) return direct.ref;
  const q = await db.collection('payments').where('paystackReference', '==', reference).limit(1).get();
  return q.empty ? null : q.docs[0].ref;
}

async function _onDisputeWebhook(eventName, data) {
  const disputeId = data?.id !== undefined && data?.id !== null ? String(data.id) : null;
  const now = () => admin.firestore.Timestamp.now();
  if (!disputeId) {
    const key = crypto.createHash('sha256').update(JSON.stringify(data ?? null)).digest('hex').slice(0, 24);
    await db.collection('admin_alerts').doc(`chargeback_invalid_${key}`).set({
      type: 'chargeback_webhook_invalid', event: eventName, createdAt: now(), resolved: false,
    }, { merge: true });
    return { ignored: 'no_dispute_id' };
  }

  let dispute = data;
  let verified = false;
  try {
    const fetched = await _paystack.fetchDispute(disputeId);
    if (fetched && String(fetched.id ?? disputeId) === disputeId) {
      dispute = fetched;
      verified = true;
    }
  } catch (err) {
    console.warn(`_onDisputeWebhook: fetch dispute ${disputeId} failed — using the signed webhook payload`, err.message);
  }
  const webhookRef = _disputeReference(data);
  const reference = _disputeReference(dispute) || webhookRef;
  const paymentRef = await _findPaymentByReference(reference);
  const cbRef = db.collection('chargebacks').doc(disputeId);
  const incomingStatus = typeof dispute?.status === 'string' ? dispute.status : null;
  const eventKey = crypto.createHash('sha256').update(JSON.stringify([
    eventName, incomingStatus, dispute?.resolution ?? null, dispute?.updatedAt ?? dispute?.updated_at ?? null,
    dispute?.resolvedAt ?? null,
  ])).digest('hex').slice(0, 32);

  const out = await db.runTransaction(async (tx) => {
    const [cbSnap, evSnap, paySnap] = await Promise.all([
      tx.get(cbRef), tx.get(cbRef.collection('events').doc(eventKey)),
      paymentRef ? tx.get(paymentRef) : Promise.resolve(null),
    ]);
    if (evSnap.exists) return { duplicate: true };
    const payment = paySnap?.exists ? paySnap.data() : null;
    const jobId = payment?.jobId || null;
    const jobRef = jobId ? db.collection('jobs').doc(jobId) : null;
    const [jobSnap, relSnap] = await Promise.all([
      jobRef ? tx.get(jobRef) : Promise.resolve(null),
      jobId ? tx.get(db.collection('escrow_releases').doc(jobId)) : Promise.resolve(null),
    ]);
    const job = jobSnap?.exists ? jobSnap.data() : null;
    const t = now();
    const cb = cbSnap.exists ? cbSnap.data() : null;
    const paystackStatus = _nextDisputeStatus(cb?.paystackStatus, incomingStatus);
    const paystackResolved = DISPUTE_STATUS_RANK[paystackStatus] === 2;
    const facts = {
      paystackStatus,
      paystackResolution: dispute?.resolution ?? cb?.paystackResolution ?? null,
      // Unit of refund_amount is not documented — stored as reported, never used to move money.
      paystackRefundAmountRaw: dispute?.refund_amount ?? cb?.paystackRefundAmountRaw ?? null,
      currency: dispute?.currency ?? cb?.currency ?? null,
      dueAt: dispute?.dueAt ?? dispute?.due_at ?? cb?.dueAt ?? null,
      lastEvent: eventName, lastEventAt: t, verified: verified || cb?.verified === true,
    };
    let created = false;
    let afterClose = false;
    if (!cb) {
      created = true;
      tx.set(cbRef, {
        disputeId, reference, paymentId: paymentRef?.id || null, jobId,
        customerId: payment?.payerId || null, artisanId: job?.artisanId || null,
        status: paystackResolved ? 'paystack_resolved' : 'open',
        payoutStateAtOpen: _payoutStateAtChargeback(payment, relSnap?.exists ? relSnap.data() : null),
        chargedAmountKobo: payment?.chargedAmountKobo ?? null,
        remindCount: eventName === 'charge.dispute.remind' ? 1 : 0,
        createdAt: t, ...facts,
      });
      if (paySnap?.exists) {
        tx.update(paymentRef, {
          chargebackHold: true, openChargebackIds: admin.firestore.FieldValue.arrayUnion(disputeId),
          chargebackAt: t,
        });
      }
      if (job) tx.update(jobRef, { chargebackHold: true, chargebackStatus: 'open' });
    } else if (cb.status === 'closed') {
      afterClose = true;
      tx.update(cbRef, { lastEvent: eventName, lastEventAt: t, eventsAfterClose: admin.firestore.FieldValue.increment(1) });
    } else {
      tx.update(cbRef, {
        ...facts,
        ...(paystackResolved && cb.status === 'open' ? { status: 'paystack_resolved', paystackResolvedAt: t } : {}),
        ...(eventName === 'charge.dispute.remind' ? { remindCount: admin.firestore.FieldValue.increment(1) } : {}),
      });
    }
    tx.set(cbRef.collection('events').doc(eventKey), {
      event: eventName, receivedAt: t, verified, paystackStatus: incomingStatus,
      resolution: dispute?.resolution ?? null, webhookReference: webhookRef, fetchedReference: verified ? _disputeReference(dispute) : null,
    });
    _recordFinancialEvent(tx, {
      type: `chargeback_${eventName.slice('charge.dispute.'.length)}`, jobId, paymentId: paymentRef?.id || null,
      actor: 'paystack', details: { disputeId, paystackStatus: incomingStatus, verified, created, afterClose },
    });
    return {
      created, afterClose, jobId, paystackResolved, artisanId: job?.artisanId || null,
      payoutState: cb?.payoutStateAtOpen || _payoutStateAtChargeback(payment, relSnap?.exists ? relSnap.data() : null),
      matched: !!paySnap?.exists,
    };
  });
  if (out.duplicate) return { duplicate: true };

  const alert = (id, body) => db.collection('admin_alerts').doc(id).set({
    disputeId, jobId: out.jobId, reference, createdAt: now(), resolved: false, ...body,
  }, { merge: true });
  if (!out.matched) await alert(`chargeback_unmatched_${disputeId}`, { type: 'chargeback_unmatched' });
  if (!verified) await alert(`chargeback_unverified_${disputeId}`, { type: 'chargeback_unverified', event: eventName });
  if (verified && webhookRef && webhookRef !== reference) {
    await alert(`chargeback_reference_mismatch_${disputeId}`, { type: 'chargeback_reference_mismatch', webhookReference: webhookRef });
  }
  if (out.created) {
    const afterPayout = ['payout_initiated', 'paid_out'].includes(out.payoutState);
    await alert(`chargeback_open_${disputeId}`, {
      type: afterPayout ? 'chargeback_after_payout' : 'chargeback_opened', payoutState: out.payoutState,
      dueAt: dispute?.dueAt ?? dispute?.due_at ?? null,
    });
    if (out.jobId && ['in_escrow', 'settlement_in_progress'].includes(out.payoutState)) {
      await _mirrorPayoutStatus(out.jobId, 'on_hold');
    }
  } else if (out.afterClose) {
    await alert(`chargeback_event_after_close_${disputeId}`, { type: 'chargeback_event_after_close', event: eventName });
  } else if (eventName === 'charge.dispute.remind') {
    await alert(`chargeback_open_${disputeId}`, { lastRemindAt: now(), resolved: false });
  }
  if (out.paystackResolved && !out.afterClose) {
    await alert(`chargeback_resolved_${disputeId}`, { type: 'chargeback_paystack_resolved', resolution: dispute?.resolution ?? null });
  }
  return { created: out.created, verified, matched: out.matched };
}

// Pure (Stage 7.2). How much of the charge the card issuer returned to the
// customer, and on what basis. Paystack documents refund_amount as an
// integer "in the subunit of the supported currency" (kobo for NGN) and
// allows a full or partial amount when a dispute is accepted; what the
// fetched dispute reports for issuer-decided outcomes is not documented.
// So a partial amount is used only when the owner has verified it in test
// mode (config/platform.partialChargebackAccountingVerified) AND Paystack
// reports resolved + merchant-accepted with a valid amount. Anything else is
// treated as a full reversal of whatever was still held (conservative).
function _chargebackAccounting({ payment, fetched, outcome, partialVerified }) {
  const chargedKobo = Number.isInteger(payment?.chargedAmountKobo) ? payment.chargedAmountKobo : _expectedChargeKobo(payment);
  const priorKobo = Number.isInteger(payment?.chargebackRefundedKobo) ? payment.chargebackRefundedKobo : 0;
  const heldKobo = Number.isInteger(chargedKobo) ? Math.max(0, chargedKobo - priorKobo) : null;
  const serviceNgn = _payoutAmountNgn(payment);
  const serviceKobo = typeof serviceNgn === 'number' ? Math.round(serviceNgn * 100) : null;
  const base = { chargedKobo: chargedKobo ?? null, priorReversedKobo: priorKobo, heldBeforeKobo: heldKobo, serviceKobo };
  if (outcome === 'merchant_won') {
    return { ...base, basis: 'merchant_won', reversedKobo: 0, undisputedKobo: heldKobo, partial: false, shortfallKobo: 0 };
  }
  const amt = fetched?.refund_amount;
  const currency = fetched?.currency ?? fetched?.transaction?.currency ?? null;
  const established = partialVerified === true && fetched?.status === 'resolved' &&
    fetched?.resolution === 'merchant-accepted' && Number.isInteger(amt) && amt > 0 &&
    heldKobo !== null && amt <= heldKobo && (currency === null || currency === 'NGN');
  const reversedKobo = established ? amt : heldKobo;
  const undisputedKobo = heldKobo === null ? null : heldKobo - reversedKobo;
  return {
    ...base,
    basis: heldKobo === null ? 'amount_unknown' : (established ? 'paystack_verified' : 'assumed_full'),
    reversedKobo, undisputedKobo, partial: established && amt < heldKobo,
    // Artisan entitlement (agreed service price) not covered by what is left.
    shortfallKobo: serviceKobo !== null && undisputedKobo !== null ? Math.max(0, serviceKobo - undisputedKobo) : null,
  };
}

const PAID_OUT_STATUSES = ['releasing', 'released', 'settled', 'refundPending', 'refunded'];

// Admin-only. The single way a chargeback hold is lifted. Paystack must
// report the dispute resolved (fetched now, not taken from a webhook).
// Stage 7.2 policies: a chargeback after payout is a HandyTrust loss —
// recorded in platform_losses, never deducted from the artisan's future
// payouts, and no completed transfer is reopened or reversed.
async function _closeChargeback({ chargebackId, outcome, reason, adminId }) {
  if (!CHARGEBACK_OUTCOMES.includes(outcome)) throw new HttpsError('invalid-argument', 'invalid_outcome');
  if (typeof reason !== 'string' || reason.trim().length < 10) throw new HttpsError('invalid-argument', 'reason_required');
  const cbRef = db.collection('chargebacks').doc(chargebackId);
  const pre = await cbRef.get();
  if (!pre.exists) throw new HttpsError('not-found', 'Chargeback not found.');
  if (pre.data().status === 'closed') {
    if (pre.data().outcome === outcome) return { duplicate: true };
    throw new HttpsError('already-exists', 'This chargeback was already closed with a different outcome.');
  }
  let fetched;
  try {
    fetched = await _paystack.fetchDispute(chargebackId);
  } catch (err) {
    throw new HttpsError('unavailable', 'Could not confirm the dispute with Paystack. Try again later.');
  }
  if (DISPUTE_STATUS_RANK[fetched?.status] !== 2) {
    throw new HttpsError('failed-precondition', `Paystack has not resolved this dispute (status: ${fetched?.status ?? 'unknown'}).`);
  }
  if (outcome === 'merchant_won' && fetched?.resolution === 'merchant-accepted') {
    throw new HttpsError('failed-precondition', 'Paystack reports the dispute was accepted (customer refunded).');
  }
  const cfg = await _loadPlatformConfig();

  const res = await db.runTransaction(async (tx) => {
    const cbSnap = await tx.get(cbRef);
    const cb = cbSnap.data();
    if (cb.status === 'closed') return { duplicate: cb.outcome === outcome, conflict: cb.outcome !== outcome };
    const payRef = cb.paymentId ? db.collection('payments').doc(cb.paymentId) : null;
    const jobRef = cb.jobId ? db.collection('jobs').doc(cb.jobId) : null;
    const stRef = cb.jobId ? db.collection('settlements').doc(cb.jobId) : null;
    const lossRef = db.collection('platform_losses').doc(chargebackId);
    const [ps, js, st, refundQ] = await Promise.all([
      payRef ? tx.get(payRef) : null, jobRef ? tx.get(jobRef) : null, stRef ? tx.get(stRef) : null,
      tx.get(db.collection('refunds').where('paystackReference', '==', cb.reference || '_none')),
    ]);
    const pay = ps?.exists ? ps.data() : null;
    const acct = _chargebackAccounting({ payment: pay, fetched, outcome, partialVerified: cfg.partialChargebackAccountingVerified });
    // A partial reversal while a settlement is executing can't be reconciled
    // automatically: leave the case open and the hold in place.
    if (outcome === 'customer_refunded' && acct.partial && pay?.status === 'settling') {
      throw new HttpsError('failed-precondition',
        'partial_chargeback_during_settlement: reconcile manually; the hold stays in place.');
    }
    const t = admin.firestore.Timestamp.now();
    const remaining = (pay?.openChargebackIds || []).filter((id) => id !== chargebackId);
    const stillHeld = remaining.length > 0;
    let paymentStatusAfter = pay?.status ?? null;
    const paidOut = !!pay && PAID_OUT_STATUSES.includes(pay.status);
    let lossKobo = null;
    if (pay) {
      const upd = { openChargebackIds: remaining, chargebackHold: stillHeld, chargebackOutcome: outcome };
      if (outcome === 'customer_refunded') {
        if (Number.isInteger(acct.reversedKobo)) upd.chargebackRefundedKobo = acct.priorReversedKobo + acct.reversedKobo;
        if (paidOut) {
          // Funds had already left escrow: HandyTrust absorbs the reversal.
          upd.chargebackLoss = true;
          lossKobo = acct.reversedKobo;
        } else if (['escrowHeld', 'settling', 'requiresRefund'].includes(pay.status) && !acct.partial) {
          // The issuer returned everything that was still held.
          paymentStatusAfter = 'chargedBack';
        }
        // Partial in escrow: status unchanged; the undisputed balance stays
        // held for the artisan's entitlement and fee (see _availableKobo).
        upd.status = paymentStatusAfter;
      }
      tx.update(payRef, upd);
    }
    if (js?.exists) tx.update(jobRef, { chargebackHold: stillHeld, chargebackStatus: `closed_${outcome}` });
    if (outcome === 'customer_refunded' && !acct.partial) {
      // Legs that never moved money must not move it now (double refund / unfunded payout).
      if (st?.exists) {
        const s = st.data();
        const cancel = (leg) => (['pending', 'held', 'failed'].includes(leg?.status) ? 'cancelled_chargeback' : leg?.status);
        tx.update(stRef, {
          'payoutLeg.status': cancel(s.payoutLeg), 'refundLeg.status': cancel(s.refundLeg), status: 'chargeback',
        });
      }
      refundQ.docs.forEach((d) => {
        if (['requested', 'held', 'failed'].includes(d.data().status)) tx.update(d.ref, { status: 'cancelled_chargeback', updatedAt: t });
      });
    } else if (outcome === 'customer_refunded' && acct.partial) {
      // A refund we still owe must shrink by what the issuer already returned.
      refundQ.docs.forEach((d) => {
        const r = d.data();
        if (!['requested', 'held', 'failed'].includes(r.status) || !Number.isInteger(r.amountKobo)) return;
        const left = r.amountKobo - acct.reversedKobo;
        tx.update(d.ref, left > 0
          ? { amountKobo: left, amountReducedByChargebackKobo: acct.reversedKobo, updatedAt: t }
          : { status: 'cancelled_chargeback', updatedAt: t });
      });
    }
    if (outcome === 'customer_refunded' && paidOut) {
      tx.set(lossRef, {
        chargebackId, jobId: cb.jobId || null, paymentId: cb.paymentId || null,
        artisanId: cb.artisanId || null, customerId: cb.customerId || null,
        amountKobo: lossKobo ?? null, amountBasis: acct.basis, paymentStatusAtClose: pay?.status ?? null,
        payoutStateAtOpen: cb.payoutStateAtOpen || null,
        absorbedBy: 'handytrust', artisanDeduction: false, recoveryStatus: 'not_pursued',
        recordedBy: adminId, recordedAt: t,
      });
      _recordFinancialEvent(tx, {
        type: 'platform_loss_recorded', jobId: cb.jobId || null, paymentId: cb.paymentId || null,
        amountKobo: lossKobo ?? null, actor: `admin:${adminId}`, details: { disputeId: chargebackId, basis: acct.basis },
      });
    }
    tx.update(cbRef, {
      status: 'closed', outcome, closeReason: reason.trim(), closedBy: adminId, closedAt: t,
      paystackStatusAtClose: fetched.status, paystackResolutionAtClose: fetched.resolution ?? null,
      paystackRefundAmountAtClose: fetched.refund_amount ?? null,
      accounting: { ...acct, platformLossKobo: lossKobo ?? null },
      history: admin.firestore.FieldValue.arrayUnion({ action: 'closed', outcome, by: adminId, at: t, basis: acct.basis }),
    });
    const logRef = db.collection('admin_audit_logs').doc();
    tx.set(logRef, {
      id: logRef.id, action: 'chargebackClosed', adminId, targetId: chargebackId, targetType: 'chargeback', timestamp: t,
      metadata: { outcome, reason: reason.trim(), jobId: cb.jobId || null, paymentStatusAfter, holdRemains: stillHeld,
        paystackStatus: fetched.status, paystackResolution: fetched.resolution ?? null,
        accountingBasis: acct.basis, reversedKobo: acct.reversedKobo ?? null, platformLossKobo: lossKobo ?? null },
    });
    _recordFinancialEvent(tx, {
      type: 'chargeback_closed', jobId: cb.jobId || null, paymentId: cb.paymentId || null, actor: `admin:${adminId}`,
      details: { disputeId: chargebackId, outcome, paymentStatusAfter, holdRemains: stillHeld, basis: acct.basis,
        reversedKobo: acct.reversedKobo ?? null, undisputedKobo: acct.undisputedKobo ?? null },
    });
    return {
      closed: true, jobId: cb.jobId || null, stillHeld, paidOut, acct, artisanId: cb.artisanId || null,
    };
  });
  if (res.conflict) throw new HttpsError('already-exists', 'This chargeback was already closed with a different outcome.');
  if (res.duplicate) return { duplicate: true };
  let nextStep;
  if (outcome === 'merchant_won') nextStep = 'retry_frozen_payout_or_held_refund_if_appropriate';
  else if (res.paidOut) nextStep = 'loss_absorbed_review_artisan_for_fraud_if_warranted';
  else if (res.acct.partial && res.acct.shortfallKobo > 0) nextStep = 'settle_undisputed_balance_artisan_entitlement_not_covered';
  else if (res.acct.partial) nextStep = 'retry_payout_undisputed_balance_covers_entitlement';
  else nextStep = 'cancel_or_close_job';
  await db.collection('admin_alerts').doc(`chargeback_closed_${chargebackId}`).set({
    type: 'chargeback_closed', disputeId: chargebackId, jobId: res.jobId, artisanId: res.artisanId, outcome,
    holdRemains: res.stillHeld, accountingBasis: res.acct.basis,
    // Nothing resumes automatically: a frozen payout or held refund needs an explicit admin retry.
    nextStep, createdAt: admin.firestore.Timestamp.now(), resolved: false,
  }, { merge: true });
  return { closed: true, holdRemains: res.stillHeld, basis: res.acct.basis, partial: res.acct.partial, nextStep };
}

// Admin-only, no money moves. Records a fraud investigation on the case;
// any suspension is applied separately through the existing admin
// suspension tooling (a 'fraud' suspension already freezes payouts).
const CHARGEBACK_INVESTIGATION_STATUSES = ['investigating', 'cleared', 'fraud_confirmed'];
async function _setChargebackInvestigation({ chargebackId, status, notes, adminId }) {
  if (!CHARGEBACK_INVESTIGATION_STATUSES.includes(status)) throw new HttpsError('invalid-argument', 'invalid_status');
  if (typeof notes !== 'string' || notes.trim().length < 10) throw new HttpsError('invalid-argument', 'notes_required');
  const cbRef = db.collection('chargebacks').doc(chargebackId);
  const out = await db.runTransaction(async (tx) => {
    const s = await tx.get(cbRef);
    if (!s.exists) throw new HttpsError('not-found', 'Chargeback not found.');
    const t = admin.firestore.Timestamp.now();
    const entry = { status, notes: notes.trim(), by: adminId, at: t };
    tx.update(cbRef, {
      investigation: entry,
      history: admin.firestore.FieldValue.arrayUnion({ action: 'investigation', ...entry }),
    });
    const logRef = db.collection('admin_audit_logs').doc();
    tx.set(logRef, {
      id: logRef.id, action: 'chargebackInvestigation', adminId, targetId: chargebackId, targetType: 'chargeback',
      timestamp: t, metadata: { status, notes: notes.trim(), artisanId: s.data().artisanId || null },
    });
    return { artisanId: s.data().artisanId || null, jobId: s.data().jobId || null };
  });
  if (status === 'fraud_confirmed') {
    await db.collection('admin_alerts').doc(`chargeback_fraud_confirmed_${chargebackId}`).set({
      type: 'chargeback_fraud_confirmed', disputeId: chargebackId, jobId: out.jobId, artisanId: out.artisanId,
      nextStep: 'consider_fraud_suspension_of_artisan', createdAt: admin.firestore.Timestamp.now(), resolved: false,
    }, { merge: true });
  }
  return { status, artisanId: out.artisanId };
}

exports._onDisputeWebhook = _onDisputeWebhook;
exports._closeChargeback = _closeChargeback;
exports._chargebackAccounting = _chargebackAccounting;
exports._setChargebackInvestigation = _setChargebackInvestigation;
exports._availableKobo = _availableKobo;
exports._nextDisputeStatus = _nextDisputeStatus;
exports._disputeReference = _disputeReference;
exports._payoutStateAtChargeback = _payoutStateAtChargeback;
exports.CHARGEBACK_EVENTS = CHARGEBACK_EVENTS;

// ── Settlements: admin dispute / paid-cancellation outcomes ──
const SETTLEMENT_OUTCOMES = ['release', 'full_refund', 'split'];

// Pure. Amounts in kobo. A split pays the artisan at most the agreed service
// price and returns at most what the customer actually paid in total; any
// remainder is retained by HandyTrust and recorded explicitly.
// Stage 7.2: availableKobo is the undisputed balance still held (the charge
// minus any partial chargeback the issuer returned to the customer). It
// defaults to the full charge, so settlements without a chargeback are
// validated exactly as before.
function _validateSettlement({ outcome, artisanKobo, refundKobo, serviceKobo, totalKobo, availableKobo = totalKobo, reason }) {
  if (!SETTLEMENT_OUTCOMES.includes(outcome)) return 'invalid_outcome';
  if (typeof reason !== 'string' || reason.trim().length < 10) return 'reason_required';
  const okInt = (v) => Number.isInteger(v) && v >= 0;
  if (!okInt(artisanKobo) || !okInt(refundKobo)) return 'invalid_amount';
  if (!(serviceKobo > 0) || !(totalKobo >= serviceKobo)) return 'invalid_payment_record';
  if (!okInt(availableKobo) || availableKobo > totalKobo) return 'invalid_payment_record';
  if (outcome === 'release' && !(artisanKobo === serviceKobo && refundKobo === 0)) {
    return 'release_must_pay_full_service_price';
  }
  if (outcome === 'release' && artisanKobo > availableKobo) return 'release_exceeds_undisputed_balance';
  if (outcome === 'full_refund' && !(refundKobo === availableKobo && artisanKobo === 0)) {
    return 'full_refund_must_return_full_charge';
  }
  if (outcome === 'full_refund' && refundKobo === 0) return 'nothing_left_to_refund';
  if (outcome === 'split') {
    if (!(artisanKobo > 0 && refundKobo > 0)) return 'split_requires_both_parts';
    if (artisanKobo > serviceKobo) return 'artisan_amount_exceeds_service_price';
    if (artisanKobo + refundKobo > availableKobo) return 'split_exceeds_amount_paid';
  }
  return null;
}

function _settlementAmounts(outcome, payment, artisanAmountNgn, refundAmountNgn) {
  const serviceKobo = Math.round(_payoutAmountNgn(payment) * 100);
  const totalKobo = _expectedChargeKobo(payment);
  const availableKobo = _availableKobo(payment);
  const toKobo = (v) => (typeof v === 'number' && Number.isFinite(v) ? Math.round(v * 100) : NaN);
  if (outcome === 'release') return { serviceKobo, totalKobo, availableKobo, artisanKobo: serviceKobo, refundKobo: 0 };
  // A full refund returns what is still held — the issuer already returned the rest.
  if (outcome === 'full_refund') return { serviceKobo, totalKobo, availableKobo, artisanKobo: 0, refundKobo: availableKobo };
  return { serviceKobo, totalKobo, availableKobo, artisanKobo: toKobo(artisanAmountNgn), refundKobo: toKobo(refundAmountNgn) };
}

async function _settleJob({ jobId, kind, outcome, artisanAmountNgn, refundAmountNgn, reason, adminId, disputeId }) {
  const jobRef = db.collection('jobs').doc(jobId);
  const settlementRef = db.collection('settlements').doc(jobId);
  const releaseRef = db.collection('escrow_releases').doc(jobId);
  const pays = await db.collection('payments').where('jobId', '==', jobId).get();
  const held = pays.docs.find((d) => ['escrowHeld', 'settling'].includes(d.data().status));
  if (!held) throw new HttpsError('failed-precondition', 'No funds are held in escrow for this job.');
  const paymentRef = held.ref;
  const disputeRef = disputeId ? db.collection('disputes').doc(disputeId) : null;

  const res = await db.runTransaction(async (tx) => {
    const [js, st, rs, ps, ds] = await Promise.all([
      tx.get(jobRef), tx.get(settlementRef), tx.get(releaseRef), tx.get(paymentRef),
      disputeRef ? tx.get(disputeRef) : Promise.resolve(null),
    ]);
    if (!js.exists) throw new HttpsError('not-found', 'Job not found.');
    const job = js.data();
    const pay = ps.data();
    const amounts = _settlementAmounts(outcome, pay, artisanAmountNgn, refundAmountNgn);
    if (st.exists) {
      const s = st.data();
      // Duplicate admin action (double click, retry): same decision → no-op.
      if (s.outcome === outcome && s.payoutLeg?.amountKobo === amounts.artisanKobo &&
          s.refundLeg?.amountKobo === amounts.refundKobo) {
        return { duplicate: true };
      }
      throw new HttpsError('already-exists', 'This job has already been settled with a different decision.');
    }
    const invalid = _validateSettlement({ outcome, reason, ...amounts });
    if (invalid) throw new HttpsError('invalid-argument', invalid);
    // Stage 7.1: the card issuer is deciding who keeps these funds.
    if (pay.chargebackHold === true || job.chargebackHold === true) {
      throw new HttpsError('failed-precondition', 'chargeback_open: this payment has an unresolved chargeback.');
    }
    if (pay.status !== 'escrowHeld') {
      throw new HttpsError('failed-precondition', `funds_not_available (${pay.status})`);
    }
    if (rs.exists && !['frozen', 'failed'].includes(rs.data().status)) {
      throw new HttpsError('failed-precondition', 'A payout for this job is already in progress or completed.');
    }
    if (kind === 'dispute') {
      if (job.status !== 'disputed') throw new HttpsError('failed-precondition', 'Job is not disputed.');
      if (!ds?.exists || ['resolved', 'dismissed'].includes(ds.data().status) || ds.data().jobId !== jobId) {
        throw new HttpsError('failed-precondition', 'Dispute is not open for this job.');
      }
    } else if (kind === 'cancellation') {
      // Policy D2: a paid cancellation is a full refund or a documented
      // partial/split — never a straight release to the artisan.
      if (outcome === 'release') throw new HttpsError('invalid-argument', 'cancellation_cannot_release');
      if (job.cancellationRequestStatus !== 'pending' || !['escrowLocked', 'inProgress'].includes(job.status)) {
        throw new HttpsError('failed-precondition', 'There is no pending cancellation request for a funded job.');
      }
    } else {
      throw new HttpsError('invalid-argument', 'invalid_kind');
    }

    const now = admin.firestore.Timestamp.now();
    const { artisanKobo, refundKobo, serviceKobo, totalKobo, availableKobo } = amounts;
    tx.set(settlementRef, {
      jobId, kind, outcome, reason: reason.trim(), adminId, disputeId: disputeId || null,
      paymentId: paymentRef.id, paystackReference: pay.paystackReference || paymentRef.id,
      serviceKobo, totalKobo, availableKobo, chargebackRefundedKobo: totalKobo - availableKobo,
      platformRetainedKobo: availableKobo - artisanKobo - refundKobo,
      payoutLeg: { status: artisanKobo > 0 ? 'pending' : 'none', amountKobo: artisanKobo },
      refundLeg: { status: refundKobo > 0 ? 'pending' : 'none', amountKobo: refundKobo },
      status: 'executing', createdAt: now,
    });
    tx.update(paymentRef, { status: 'settling', settlementId: jobId });
    if (rs.exists) tx.update(releaseRef, { status: 'superseded', supersededAt: now });
    const jobUpdate = {
      settlementOutcome: outcome, settlementStatus: 'executing',
      lastUpdatedAt: now, lastUpdatedBy: `admin:${adminId}`, updateVersion: (job.updateVersion || 0) + 1,
      ...(refundKobo > 0 ? { refundStatus: 'requested' } : {}),
    };
    if (kind === 'dispute') {
      Object.assign(jobUpdate, { status: 'resolved', disputeResolution: reason.trim(), completedAt: now });
      tx.update(disputeRef, { status: 'resolved', resolution: reason.trim(), outcome, resolvedAt: now, resolvedBy: adminId });
    } else {
      Object.assign(jobUpdate, {
        status: 'cancelled', cancellationRequestStatus: 'approved', cancelledBy: adminId,
        cancellationReason: reason.trim(), cancelledAt: now,
      });
    }
    tx.update(jobRef, jobUpdate);
    if (refundKobo > 0) {
      const refundId = pay.paystackReference || paymentRef.id;
      tx.set(db.collection('refunds').doc(refundId), {
        refundId, paystackReference: refundId, paymentId: paymentRef.id, jobId, customerId: pay.payerId,
        settlementId: jobId, kind, amountKobo: refundKobo, reason: reason.trim(), requestedBy: adminId,
        status: 'requested', attempts: 0, createdAt: now, updatedAt: now,
      });
    }
    const auditRef = jobRef.collection('auditLogs').doc();
    tx.set(auditRef, {
      id: auditRef.id, jobId, transactionId: auditRef.id, actionType: kind === 'dispute' ? 'disputeResolved' : 'adminEscrowRefund',
      actorId: adminId, actorRole: 'admin', timestamp: now, jobStatusBefore: job.status,
      jobStatusAfter: jobUpdate.status, jobVersionBefore: job.updateVersion || 0, jobVersionAfter: jobUpdate.updateVersion,
      delta: { outcome, artisanKobo, refundKobo }, reason: reason.trim(), isAdminOverride: false,
    });
    const adminLogRef = db.collection('admin_audit_logs').doc();
    tx.set(adminLogRef, {
      id: adminLogRef.id, action: kind === 'dispute' ? 'disputeSettled' : 'paidCancellationSettled',
      adminId, targetId: jobId, targetType: 'job', timestamp: now,
      metadata: { outcome, artisanKobo, refundKobo, platformRetainedKobo: availableKobo - artisanKobo - refundKobo, reason: reason.trim() },
    });
    _recordFinancialEvent(tx, {
      type: 'settlement_created', jobId, paymentId: paymentRef.id, settlementId: jobId, actor: `admin:${adminId}`,
      details: { kind, outcome, artisanKobo, refundKobo, totalKobo },
    });
    return { created: true, customerId: job.customerId, artisanId: job.artisanId };
  });

  if (res.duplicate) return { duplicate: true };
  await _executeSettlement(jobId);
  const msg = kind === 'dispute' ? 'The dispute on this job has been resolved by HandyTrust.'
    : 'Your cancellation request for this paid job was approved by HandyTrust.';
  for (const uid of [res.customerId, res.artisanId]) {
    if (uid) await _sendInAppNotification(uid, 'job_status_update', 'Decision Made', msg, jobId);
  }
  return { settled: true };
}

// Runs (or re-runs) whatever legs of a settlement are still pending.
async function _executeSettlement(jobId) {
  const st = (await db.collection('settlements').doc(jobId).get()).data();
  if (!st) return;
  if (st.payoutLeg?.status === 'pending') {
    const releaseRef = db.collection('escrow_releases').doc(jobId);
    const attempt = await db.runTransaction(async (tx) => {
      const r = await tx.get(releaseRef);
      const n = r.exists ? (r.data().payoutAttempts || 1) + 1 : 1;
      if (r.exists && !['superseded', 'frozen', 'failed'].includes(r.data().status)) return null;
      tx.set(releaseRef, {
        jobId, status: 'pending', requestedBy: 'system', settlementId: jobId, payoutAttempts: n,
        requestedAt: admin.firestore.Timestamp.now(),
      }, { merge: true });
      return n;
    });
    if (attempt) await _processEscrowRelease(releaseRef, jobId, _transferHttp);
  }
  if (st.refundLeg?.status === 'pending') {
    await _submitRefund(st.paystackReference);
  }
  await _finalizeSettlementIfDone(jobId);
}

async function _finalizeSettlementIfDone(jobId) {
  const settlementRef = db.collection('settlements').doc(jobId);
  return db.runTransaction(async (tx) => {
    const s = await tx.get(settlementRef);
    if (!s.exists) return false;
    const st = s.data();
    const done = (leg) => leg?.status === 'none' || leg?.status === 'completed';
    if (st.status === 'completed' || !done(st.payoutLeg) || !done(st.refundLeg)) return false;
    const now = admin.firestore.Timestamp.now();
    const finalPaymentStatus = st.outcome === 'release' ? 'released'
      : st.outcome === 'full_refund' ? 'refunded' : 'settled';
    tx.update(settlementRef, { status: 'completed', completedAt: now });
    tx.update(db.collection('payments').doc(st.paymentId), { status: finalPaymentStatus, settledAt: now });
    tx.update(db.collection('jobs').doc(jobId), { settlementStatus: 'completed' });
    _recordFinancialEvent(tx, {
      type: 'settlement_completed', jobId, paymentId: st.paymentId, settlementId: jobId, actor: 'system',
      details: { outcome: st.outcome, finalPaymentStatus },
    });
    return true;
  });
}

async function _declineCancellationRequest({ jobId, adminId, reason }) {
  if (typeof reason !== 'string' || reason.trim().length < 10) throw new HttpsError('invalid-argument', 'reason_required');
  const jobRef = db.collection('jobs').doc(jobId);
  const job = await db.runTransaction(async (tx) => {
    const js = await tx.get(jobRef);
    if (!js.exists) throw new HttpsError('not-found', 'Job not found.');
    const j = js.data();
    if (j.cancellationRequestStatus !== 'pending') return null; // already decided — no-op
    const now = admin.firestore.Timestamp.now();
    tx.update(jobRef, {
      cancellationRequestStatus: 'declined', cancellationDecisionReason: reason.trim(),
      cancellationDecidedBy: adminId, cancellationDecidedAt: now,
    });
    const adminLogRef = db.collection('admin_audit_logs').doc();
    tx.set(adminLogRef, {
      id: adminLogRef.id, action: 'paidCancellationDeclined', adminId, targetId: jobId, targetType: 'job',
      timestamp: now, metadata: { reason: reason.trim() },
    });
    return j;
  });
  if (!job) return { duplicate: true };
  for (const uid of [job.customerId, job.artisanId]) {
    if (uid) {
      await _sendInAppNotification(uid, 'job_status_update', 'Cancellation Request Declined',
        `HandyTrust reviewed the cancellation request and the job continues. Reason: ${reason.trim()}`, jobId);
    }
  }
  return { declined: true };
}

// Refunds a captured charge that must not fund a job (requires_refund
// payments from Stage 3, or orphan charges with no payment record).
async function _refundCharge({ reference, adminId, reason }) {
  if (typeof reason !== 'string' || reason.trim().length < 10) throw new HttpsError('invalid-argument', 'reason_required');
  const refundRef = db.collection('refunds').doc(reference);
  const payRef = db.collection('payments').doc(reference);
  const orphanRef = db.collection('orphan_charges').doc(reference);
  const res = await db.runTransaction(async (tx) => {
    const [rf, ps, os] = await Promise.all([tx.get(refundRef), tx.get(payRef), tx.get(orphanRef)]);
    if (rf.exists) return { duplicate: true };
    const now = admin.firestore.Timestamp.now();
    let amountKobo; let jobId = null; let customerId = null; let paymentId = null;
    if (ps.exists) {
      const p = ps.data();
      if (p.status !== 'requiresRefund') throw new HttpsError('failed-precondition', `Payment is ${p.status}, not awaiting refund.`);
      amountKobo = Number.isInteger(p.chargedAmountKobo) ? p.chargedAmountKobo : _expectedChargeKobo(p);
      // Stage 7.2: never refund what the card issuer already returned.
      if (Number.isInteger(p.chargebackRefundedKobo)) amountKobo -= p.chargebackRefundedKobo;
      jobId = p.jobId || null; customerId = p.payerId || null; paymentId = reference;
      tx.update(payRef, { status: 'refundPending', refundStatus: 'requested' });
    } else if (os.exists) {
      amountKobo = os.data().amountKobo; jobId = os.data().jobId || null;
      tx.update(orphanRef, { refundId: reference });
    } else {
      throw new HttpsError('not-found', 'No charge awaiting refund for this reference.');
    }
    if (!Number.isInteger(amountKobo) || amountKobo <= 0) throw new HttpsError('failed-precondition', 'Charge amount unknown.');
    tx.set(refundRef, {
      refundId: reference, paystackReference: reference, paymentId, jobId, customerId, settlementId: null,
      kind: 'charge_refund', amountKobo, reason: reason.trim(), requestedBy: adminId,
      status: 'requested', attempts: 0, createdAt: now, updatedAt: now,
    });
    const adminLogRef = db.collection('admin_audit_logs').doc();
    tx.set(adminLogRef, {
      id: adminLogRef.id, action: 'chargeRefunded', adminId, targetId: reference, targetType: 'payment',
      timestamp: now, metadata: { amountKobo, reason: reason.trim() },
    });
    _recordFinancialEvent(tx, { type: 'refund_requested', jobId, paymentId, refundId: reference, amountKobo, actor: `admin:${adminId}`, details: { kind: 'charge_refund' } });
    return { created: true };
  });
  if (res.duplicate) return { duplicate: true };
  await _submitRefund(reference);
  return { requested: true };
}

async function _retryRefund({ refundId, adminId, reason }) {
  const ref = db.collection('refunds').doc(refundId);
  const ok = await db.runTransaction(async (tx) => {
    const s = await tx.get(ref);
    if (!s.exists) throw new HttpsError('not-found', 'Refund not found.');
    const r = s.data();
    // Only a refund Paystack itself reported as failed may be retried; an
    // unknown submission is resolved by reconciliation, never resubmitted.
    // Stage 7.1: a refund held for a chargeback (never submitted) may be
    // resubmitted once the chargeback is closed — _submitRefund re-checks.
    if (r.status !== 'failed' && r.status !== 'held') return false;
    tx.update(ref, {
      status: 'requested',
      attemptHistory: admin.firestore.FieldValue.arrayUnion({
        attempt: r.attempts || 0, failureReason: r.failureReason || null, retriedBy: adminId,
        retryReason: reason || null, at: admin.firestore.Timestamp.now(),
      }),
    });
    return true;
  });
  if (!ok) return { skipped: 'not_failed' };
  return _submitRefund(refundId);
}

// Re-runs a frozen or failed payout. The freeze check runs again inside
// _processEscrowRelease, so this cannot bypass an active freeze.
async function _retryPayout({ jobId, adminId, reason }) {
  const releaseRef = db.collection('escrow_releases').doc(jobId);
  const settlementRef = db.collection('settlements').doc(jobId);
  const ok = await db.runTransaction(async (tx) => {
    const [r, st] = await Promise.all([tx.get(releaseRef), tx.get(settlementRef)]);
    if (!r.exists || !['frozen', 'failed'].includes(r.data().status)) return false;
    const rel = r.data();
    if (rel.settlementId && st.exists) {
      if (!['pending', 'failed'].includes(st.data().payoutLeg?.status)) return false;
      tx.update(settlementRef, { 'payoutLeg.status': 'pending' });
    } else if (st.exists) {
      return false; // funds belong to a settlement now
    }
    tx.update(releaseRef, {
      status: 'pending', payoutAttempts: (rel.payoutAttempts || 1) + 1,
      retryHistory: admin.firestore.FieldValue.arrayUnion({
        previousStatus: rel.status, previousReason: rel.frozenReason || rel.failureReason || null,
        retriedBy: adminId, reason: reason || null, at: admin.firestore.Timestamp.now(),
      }),
    });
    return true;
  });
  if (!ok) return { skipped: 'not_retryable' };
  return _processEscrowRelease(releaseRef, jobId, _transferHttp);
}

async function _setPayoutFreeze({ targetType, targetId, frozen, reason, adminId }) {
  if (!['artisan', 'job'].includes(targetType) || typeof targetId !== 'string' || !targetId) {
    throw new HttpsError('invalid-argument', 'targetType must be artisan or job, with a targetId.');
  }
  if (typeof reason !== 'string' || reason.trim().length < 10) throw new HttpsError('invalid-argument', 'reason_required');
  const now = admin.firestore.Timestamp.now();
  const fields = {
    payoutFrozen: frozen === true, payoutFreezeReason: reason.trim(), payoutFreezeBy: adminId, payoutFreezeAt: now,
  };
  const batch = db.batch();
  if (targetType === 'artisan') {
    batch.set(db.collection('artisans').doc(targetId), fields, { merge: true });
    batch.set(db.collection('users').doc(targetId), fields, { merge: true });
  } else {
    batch.update(db.collection('jobs').doc(targetId), fields);
  }
  const adminLogRef = db.collection('admin_audit_logs').doc();
  batch.set(adminLogRef, {
    id: adminLogRef.id, action: frozen ? 'payoutFrozen' : 'payoutUnfrozen', adminId, targetId,
    targetType, timestamp: now, metadata: { reason: reason.trim() },
  });
  batch.set(db.collection('financial_events').doc(), {
    type: frozen ? 'freeze_set' : 'freeze_lifted', targetType, targetId, actor: `admin:${adminId}`,
    at: now, details: { reason: reason.trim() },
  });
  await batch.commit();
  return { frozen: frozen === true };
}

exports._payoutBlockReason = _payoutBlockReason;
exports._isFreezingSuspension = _isFreezingSuspension;
exports._mapRefundStatus = _mapRefundStatus;
exports._nextRefundStatus = _nextRefundStatus;
exports._validateSettlement = _validateSettlement;
exports._applyRefundStatus = _applyRefundStatus;
exports._submitRefund = _submitRefund;
exports._onRefundWebhook = _onRefundWebhook;
exports._reconcileRefunds = _reconcileRefunds;
exports._settleJob = _settleJob;
exports._executeSettlement = _executeSettlement;
exports._declineCancellationRequest = _declineCancellationRequest;
exports._refundCharge = _refundCharge;
exports._retryRefund = _retryRefund;
exports._retryPayout = _retryPayout;
exports._setPayoutFreeze = _setPayoutFreeze;
exports._onTransferSucceeded = _onTransferSucceeded;
exports._onTransferFailed = _onTransferFailed;

// ── Admin callables (all money decisions are server-side, admin-checked) ──
async function _requireAdmin(request) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
  const adminDoc = await db.collection('admins').doc(request.auth.uid).get();
  if (!adminDoc.exists) throw new HttpsError('permission-denied', 'Admin privileges required.');
  return request.auth.uid;
}
const _str = (v) => (typeof v === 'string' ? v : '');
const ADMIN_FINANCE_OPTS = { secrets: ['PAYSTACK_SECRET_KEY'] };

exports.adminResolveDispute = onCall(ADMIN_FINANCE_OPTS, async (request) => {
  const adminId = await _requireAdmin(request);
  const d = request.data || {};
  return _settleJob({
    jobId: _str(d.jobId), kind: 'dispute', disputeId: _str(d.disputeId), outcome: _str(d.outcome),
    artisanAmountNgn: d.artisanAmount, refundAmountNgn: d.refundAmount, reason: _str(d.reason), adminId,
  });
});

exports.adminResolveCancellation = onCall(ADMIN_FINANCE_OPTS, async (request) => {
  const adminId = await _requireAdmin(request);
  const d = request.data || {};
  if (d.decision === 'decline') {
    return _declineCancellationRequest({ jobId: _str(d.jobId), adminId, reason: _str(d.reason) });
  }
  return _settleJob({
    jobId: _str(d.jobId), kind: 'cancellation', outcome: _str(d.decision),
    artisanAmountNgn: d.artisanAmount, refundAmountNgn: d.refundAmount, reason: _str(d.reason), adminId,
  });
});

exports.adminRefundCharge = onCall(ADMIN_FINANCE_OPTS, async (request) => {
  const adminId = await _requireAdmin(request);
  return _refundCharge({ reference: _str(request.data?.reference), adminId, reason: _str(request.data?.reason) });
});

exports.adminRetryRefund = onCall(ADMIN_FINANCE_OPTS, async (request) => {
  const adminId = await _requireAdmin(request);
  return _retryRefund({ refundId: _str(request.data?.refundId), adminId, reason: _str(request.data?.reason) });
});

exports.adminRetryPayout = onCall(ADMIN_FINANCE_OPTS, async (request) => {
  const adminId = await _requireAdmin(request);
  return _retryPayout({ jobId: _str(request.data?.jobId), adminId, reason: _str(request.data?.reason) });
});

exports.adminCloseChargeback = onCall(ADMIN_FINANCE_OPTS, async (request) => {
  const adminId = await _requireAdmin(request);
  const d = request.data || {};
  return _closeChargeback({ chargebackId: _str(d.chargebackId), outcome: _str(d.outcome), reason: _str(d.reason), adminId });
});

exports.adminSetChargebackInvestigation = onCall(async (request) => {
  const adminId = await _requireAdmin(request);
  const d = request.data || {};
  return _setChargebackInvestigation({ chargebackId: _str(d.chargebackId), status: _str(d.status), notes: _str(d.notes), adminId });
});

exports.adminSetPayoutFreeze = onCall(async (request) => {
  const adminId = await _requireAdmin(request);
  const d = request.data || {};
  return _setPayoutFreeze({
    targetType: _str(d.targetType), targetId: _str(d.targetId), frozen: d.frozen === true, reason: _str(d.reason), adminId,
  });
});

exports.reconcileRefunds = onSchedule(
  { schedule: 'every 3 hours', secrets: ['PAYSTACK_SECRET_KEY'] },
  async () => {
    console.log('reconcileRefunds', await _reconcileRefunds());
  }
);

// ═══ Stage 6 — server-generated notifications, location privacy ═══════════
//
// Notifications (HT-015 final, HT-025, HT-044): every notification is now
// written HERE, from the document change that caused it — clients can no
// longer create notifications at all (firestore.rules). Trigger deliveries
// are at-least-once, so each notification uses a deterministic id derived
// from the triggering event (event.id + recipient): a redelivery overwrites
// the same document instead of creating a duplicate push.
//
// Location privacy (P-K, policy D9): the exact customer address and
// coordinates live only in jobs/{id}/private/location, readable by the
// customer, admins and the assigned artisan once the booking is confirmed.
// The job document carries only a coarse area (~1 km) for distance matching.

// ── Pure helpers (exported for tests) ──────────────────────────────────────
const GEOHASH32 = '0123456789bcdefghjkmnpqrstuvwxyz';

function _geohashEncode(lat, lng, precision) {
  let latMin = -90; let latMax = 90; let lngMin = -180; let lngMax = 180;
  let hash = ''; let idx = 0; let bit = 0; let evenBit = true;
  while (hash.length < precision) {
    if (evenBit) {
      const mid = (lngMin + lngMax) / 2;
      if (lng >= mid) { idx = idx * 2 + 1; lngMin = mid; } else { idx *= 2; lngMax = mid; }
    } else {
      const mid = (latMin + latMax) / 2;
      if (lat >= mid) { idx = idx * 2 + 1; latMin = mid; } else { idx *= 2; latMax = mid; }
    }
    evenBit = !evenBit;
    if (++bit === 5) { hash += GEOHASH32[idx]; bit = 0; idx = 0; }
  }
  return hash;
}

// "12 Home Street, Ikeja, Lagos" → "Ikeja, Lagos". Only the last two
// components, and only when there are at least three — so a short address
// never leaks its street line.
function _areaLabel(address) {
  if (typeof address !== 'string') return null;
  const parts = address.split(',').map((s) => s.trim()).filter(Boolean);
  return parts.length >= 3 ? parts.slice(-2).join(', ') : null;
}

function _coarseArea(lat, lng, address) {
  const ok = (v, lim) => typeof v === 'number' && Number.isFinite(v) && Math.abs(v) <= lim;
  if (!ok(lat, 90) || !ok(lng, 180)) return null;
  return {
    areaLat: Math.round(lat * 100) / 100,
    areaLng: Math.round(lng * 100) / 100,
    areaGeohash3: _geohashEncode(lat, lng, 3),
    areaGeohash4: _geohashEncode(lat, lng, 4),
    areaLabel: _areaLabel(address),
  };
}

// Who to tell when the agreement sub-state changes (pure).
function _agreementNotification(before, after) {
  if ((before?.agreementStatus || 'negotiating') === (after?.agreementStatus || 'negotiating')) return null;
  switch (after.agreementStatus) {
    case 'pendingArtisanConfirmation':
      return { to: after.artisanId, type: 'agreement_pending', title: 'Customer Confirmed the Agreement',
        body: 'Review the agreed terms and accept or request changes.' };
    case 'confirmed':
      return { to: after.customerId, type: 'agreement_accepted', title: 'Agreement Accepted',
        body: 'The artisan accepted the agreed terms. You can proceed to payment.' };
    case 'changesRequested':
      return { to: after.customerId, type: 'agreement_changes_requested', title: 'Artisan Requested Changes',
        body: String(after.agreementChangesRequestedReason || 'The artisan asked to change the terms.').slice(0, 300) };
    default:
      return null;
  }
}

// Status-change notifications not already sent elsewhere (pure). escrow
// lock / submission / completion keep using _buildMessages; matched /
// inChat / rework / reopen / expiry are sent by their own code paths.
function _statusChangeNotifications(before, after) {
  const out = [];
  if (before.status === 'escrowLocked' && after.status === 'inProgress' && after.customerId) {
    out.push({ to: after.customerId, type: 'job_status_update', title: 'Work Started',
      body: 'The artisan has started work on your job.' });
  }
  if (after.status === 'cancelled' && before.status !== 'cancelled') {
    const by = after.cancelledBy;
    const others = [after.customerId, after.artisanId].filter((u) => u && u !== by);
    for (const to of others) {
      out.push({ to, type: 'job_status_update', title: 'Job Cancelled',
        body: after.cancellationReason ? `The job was cancelled: ${String(after.cancellationReason).slice(0, 200)}` : 'The job was cancelled.' });
    }
  }
  return out;
}

// Quote events → notifications (pure).
function _quoteNotification(before, after, job) {
  if (!after || !job) return null;
  const was = before?.status;
  const now = after.status;
  const fmt = (n) => `₦${Math.round(Number(n) || 0).toLocaleString('en-NG')}`;
  if (now === 'pending' && (!before || was === 'expired')) {
    return { to: job.customerId, type: 'quote_received', title: 'New Quote Received',
      body: `${after.artisanName || 'An artisan'} sent a quote for ${fmt(after.amount)}.` };
  }
  if (was === 'pending' && now === 'withdrawn' && !after.withdrawnReason) {
    return { to: job.customerId, type: 'quote_withdrawn', title: 'Quote Withdrawn',
      body: 'An artisan withdrew their quote for your job.' };
  }
  if (was === 'pending' && now === 'rejected') {
    return { to: after.artisanId, type: 'quote_rejected', title: 'Quote Declined', body: 'Your quote was declined for a job.' };
  }
  if (was === 'pending' && now === 'closed') {
    return { to: after.artisanId, type: 'quote_rejected', title: 'Another Quote Was Chosen',
      body: 'The customer booked another artisan for this job.' };
  }
  // 'accepted' is announced by the booking-request notification (job_assigned).
  return null;
}

function _messagePreview(msg) {
  if (msg.type === 'image') return 'Sent a photo';
  if (msg.type === 'negotiation') return String(msg.text || 'Sent a price proposal').slice(0, 120);
  return String(msg.text || '').slice(0, 120);
}

exports._geohashEncode = _geohashEncode;
exports._areaLabel = _areaLabel;
exports._coarseArea = _coarseArea;
exports._agreementNotification = _agreementNotification;
exports._statusChangeNotifications = _statusChangeNotifications;
exports._quoteNotification = _quoteNotification;
exports._messagePreview = _messagePreview;

// ── Trigger handlers (exported for emulator tests) ─────────────────────────
async function _handleQuoteWrite(jobId, before, after, eventId) {
  if (!after) return null;
  const job = (await db.collection('jobs').doc(jobId).get()).data();
  const n = _quoteNotification(before, after, job);
  if (!n || !n.to) return null;
  await _sendInAppNotification(n.to, n.type, n.title, n.body, jobId, { dedupeKey: `${eventId}_${n.to}` });
  return n.type;
}

async function _handleMessageCreated(jobId, msg, eventId) {
  if (!msg?.receiverId || msg.receiverId === msg.senderId || msg.type === 'system') return null;
  await _sendInAppNotification(msg.receiverId, 'message_received', 'New Message', _messagePreview(msg), jobId,
    { dedupeKey: `${eventId}_${msg.receiverId}` });
  return 'message_received';
}

async function _handleDisputeCreated(disputeId, dispute, eventId) {
  await db.collection('admin_alerts').doc(`dispute_${disputeId}`).set({
    type: 'dispute', disputeId, jobId: dispute.jobId, raisedBy: dispute.raisedBy, reason: dispute.reason,
    createdAt: admin.firestore.Timestamp.now(), resolved: false,
  }, { merge: true });
  if (dispute.againstUserId) {
    await _sendInAppNotification(dispute.againstUserId, 'dispute_raised', 'A Dispute Was Raised',
      'A dispute was raised on one of your jobs. Respond with your side and any evidence.', dispute.jobId,
      { dedupeKey: `${eventId}_${dispute.againstUserId}` });
  }
}

// Stage 7.1 (F-3): rules only accept exact fields on the job document at
// creation, while jobs/{id}/private/location can be written at or after
// creation — so an existing private location is never older than the
// job-document copy and always wins. The private document is read inside
// this transaction: a concurrent private write makes the transaction retry
// and see it (conditional update), so a stale copy can never overwrite it.
async function _protectJobLocation(jobRef) {
  return db.runTransaction(async (tx) => {
    const privRef = jobRef.collection('private').doc('location');
    const [snap, privSnap] = await Promise.all([tx.get(jobRef), tx.get(privRef)]);
    if (!snap.exists) return false;
    const d = snap.data();
    const keys = ['customerLat', 'customerLng', 'customerAddress'];
    if (!keys.some((k) => d[k] !== undefined)) return false;
    const exact = {};
    for (const k of keys) if (d[k] !== undefined && d[k] !== null) exact[k] = d[k];
    const now = admin.firestore.Timestamp.now();
    const priv = privSnap.exists ? privSnap.data() : null;
    const keepPrivate = !!priv && keys.some((k) => priv[k] !== undefined && priv[k] !== null);
    // Kept private location: the stale job-document copy is simply deleted below.
    if (!keepPrivate) tx.set(privRef, { ...exact, movedAt: now }, { merge: true });
    const src = keepPrivate ? priv : d;
    const area = d.areaGeohash4 ? {} : (_coarseArea(src.customerLat, src.customerLng, src.customerAddress) || {});
    const del = admin.firestore.FieldValue.delete();
    tx.update(jobRef, { customerLat: del, customerLng: del, customerAddress: del, ...area });
    return true;
  });
}

exports._handleQuoteWrite = _handleQuoteWrite;
exports._handleMessageCreated = _handleMessageCreated;
exports._handleDisputeCreated = _handleDisputeCreated;
exports._protectJobLocation = _protectJobLocation;

exports.onQuoteWritten = onDocumentWritten('jobs/{jobId}/quotes/{artisanId}', (event) =>
  _handleQuoteWrite(
    event.params.jobId,
    event.data.before.exists ? event.data.before.data() : null,
    event.data.after.exists ? event.data.after.data() : null,
    event.id,
  ));

exports.onMessageCreated = onDocumentCreated('jobs/{jobId}/messages/{msgId}', (event) =>
  _handleMessageCreated(event.params.jobId, event.data.data(), event.id));

// Older app builds still write the exact location into the job document;
// this moves it to the private sub-document within seconds of creation.
exports.onJobCreatedProtectLocation = onDocumentCreated('jobs/{jobId}', (event) =>
  _protectJobLocation(event.data.ref));

// One-off, paged migration for existing jobs (admin only). Returns a cursor.
async function _backfillJobLocationPrivacy({ startAfter = null, pageSize = 300 } = {}) {
  let q = db.collection('jobs').orderBy(admin.firestore.FieldPath.documentId()).limit(pageSize);
  if (startAfter) q = q.startAfter(startAfter);
  const page = await q.get();
  let moved = 0;
  for (const d of page.docs) if (await _protectJobLocation(d.ref)) moved++;
  return { examined: page.size, moved, nextCursor: page.size === pageSize ? page.docs[page.size - 1].id : null };
}
exports._backfillJobLocationPrivacy = _backfillJobLocationPrivacy;

exports.adminBackfillJobLocationPrivacy = onCall(async (request) => {
  await _requireAdmin(request);
  const startAfter = typeof request.data?.startAfter === 'string' ? request.data.startAfter : null;
  return _backfillJobLocationPrivacy({ startAfter });
});

// Payout status mirrored onto the job so both parties see the truth
// ("processing" until Paystack confirms the transfer) — HT-024.
async function _mirrorPayoutStatus(jobId, payoutStatus) {
  try {
    await db.collection('jobs').doc(jobId).update({ payoutStatus });
  } catch (err) {
    console.warn(`_mirrorPayoutStatus(${jobId}, ${payoutStatus}) failed`, err.message);
  }
}
exports._mirrorPayoutStatus = _mirrorPayoutStatus;

// ═══ Stage 5 — marketplace lifecycle: bookings, reopening, deadlines ══════
//
// Deadlines (policy D5) come from config/platform via _loadPlatformConfig and
// are measured from server timestamps only: Firestore document createTime,
// rule-enforced request.time fields (matchedAt / quote updatedAt), or
// timestamps written here by the Admin SDK.
const HOUR_MS = 60 * 60 * 1000;

// A job back in 'requested' after an artisan withdrawal, a declined booking
// or an expired booking (policy D6/D7). Clears every per-artisan field
// (agreement, schedule, booking, payment attempt), revives competing quotes
// that are still within their validity, and records why. Runs from a
// transaction on current state, so a concurrent payment lock / cancellation
// / second reopen is detected and the reopen is skipped.
async function _reopenJob(jobId, { reason, expectStatuses, requireArtisanId = null, nowMs = Date.now() }) {
  const jobRef = db.collection('jobs').doc(jobId);
  const cfg = await _loadPlatformConfig();
  const quoteDocs = (await jobRef.collection('quotes').get()).docs;
  const del = admin.firestore.FieldValue.delete();

  const res = await db.runTransaction(async (tx) => {
    const js = await tx.get(jobRef);
    if (!js.exists) throw new HttpsError('not-found', 'Job not found.');
    const job = js.data();
    if (requireArtisanId !== null && job.artisanId !== requireArtisanId) {
      throw new HttpsError('permission-denied', 'You are not the artisan on this job.');
    }
    if (!expectStatuses.includes(job.status)) return { skipped: 'state_changed', status: job.status };
    const quoteSnaps = await Promise.all(quoteDocs.map((d) => tx.get(d.ref)));
    const now = admin.firestore.Timestamp.fromMillis(nowMs);
    const previousArtisan = job.artisanId || '';
    // Stage 7.2: keep the booking-response history before the fields go.
    const responseOf = reason === 'booking_expired' ? { type: 'expired', respondedAt: now }
      : reason === 'artisan_declined_booking' ? { type: 'declined', respondedAt: now }
      : (reason === 'artisan_withdrew' && job.bookingConfirmedAt?.toMillis)
        ? { type: 'confirmed', respondedAt: job.bookingConfirmedAt } // first response stands
        : null;
    const writeResponse = responseOf
      ? await _prepareBookingResponse(tx, jobId, job, { ...responseOf, source: `reopen:${reason}` })
      : null;

    const respondedArtisan = writeResponse ? writeResponse() : null;
    tx.update(jobRef, {
      status: 'requested',
      artisanId: '',
      matchedAt: del, bookingStatus: del, bookingRequestedAt: del, bookingConfirmedAt: del,
      agreementStatus: del, agreementScope: del, agreedAmount: del,
      agreementConfirmedByCustomer: false, agreementConfirmedByArtisan: false,
      agreementCustomerConfirmedAt: del, agreementArtisanConfirmedAt: del,
      agreementUpdatedAt: del, agreementChangesRequestedReason: del,
      appointmentSlots: del, confirmedAppointment: del, schedulingStatus: del, schedulingUpdatedAt: del,
      pendingPaymentReference: del, paymentInitializedAt: del,
      reopenedAt: now,
      reopenReason: reason,
      reopenCount: admin.firestore.FieldValue.increment(1),
      ...(previousArtisan ? { previousArtisanIds: admin.firestore.FieldValue.arrayUnion(previousArtisan) } : {}),
      lastUpdatedAt: now,
      lastUpdatedBy: `system:${reason}`,
      updateVersion: (job.updateVersion || 0) + 1,
    });

    const revived = [];
    for (const q of quoteSnaps) {
      if (!q.exists) continue;
      const quote = q.data();
      if (q.id === previousArtisan) {
        tx.update(q.ref, { status: 'withdrawn', withdrawnReason: reason });
        continue;
      }
      if (quote.status !== 'closed') continue;
      const atMs = quote.updatedAt?.toMillis?.() ?? quote.createdAt?.toMillis?.() ?? 0;
      if (nowMs < atMs + cfg.quoteValidityHours * HOUR_MS) {
        tx.update(q.ref, { status: 'pending' });
        revived.push(q.id);
      } else {
        tx.update(q.ref, { status: 'expired', expiredAt: now });
      }
    }

    const auditRef = jobRef.collection('auditLogs').doc();
    tx.set(auditRef, {
      id: auditRef.id, jobId, transactionId: auditRef.id, actionType: 'statusTransition',
      actorId: reason === 'artisan_withdrew' || reason === 'artisan_declined_booking' ? previousArtisan : 'system',
      actorRole: reason === 'artisan_withdrew' || reason === 'artisan_declined_booking' ? 'artisan' : 'system',
      timestamp: now, jobStatusBefore: job.status, jobStatusAfter: 'requested',
      jobVersionBefore: job.updateVersion || 0, jobVersionAfter: (job.updateVersion || 0) + 1,
      delta: { reason, previousArtisan, revivedQuotes: revived.length }, isAdminOverride: false,
    });
    return { respondedArtisan, fromStatus: job.status, previousArtisan, customerId: job.customerId, revived, bookingWasConfirmed: job.bookingStatus === 'confirmed' || job.status !== 'matched' };
  });

  if (res.skipped) return res;
  if (res.respondedArtisan) await _recomputeResponseTime(res.respondedArtisan, nowMs);
  if (res.fromStatus === 'paymentPending') {
    // An open checkout must not be able to fund a job the artisan left; a
    // charge that still succeeds is refunded (Stage 3 _decideChargeOutcome).
    await _abandonPaymentsForCancelledJob(jobId);
  }
  if (reason === 'artisan_withdrew' && res.bookingWasConfirmed && res.previousArtisan) {
    // Backing out of a confirmed booking counts against the artisan's
    // cancellation rate; declining or letting a booking request lapse does not.
    await _recordJobOutcome(res.previousArtisan, 'cancelled');
  }
  const why = {
    artisan_withdrew: 'The artisan withdrew from your job.',
    artisan_declined_booking: 'The artisan declined your booking request.',
    booking_expired: "The artisan didn't confirm your booking in time.",
  }[reason] || 'Your job was reopened.';
  await _sendInAppNotification(res.customerId, 'job_status_update', 'Job Reopened',
    `${why} It's open for quotes again${res.revived.length ? ` — ${res.revived.length} earlier quote(s) are active again` : ''}.`, jobId);
  for (const artisanId of res.revived) {
    await _sendInAppNotification(artisanId, 'job_status_update', 'Your Quote Is Active Again',
      'A job you quoted on has reopened — the customer can now accept your quote.', jobId);
  }
  return { reopened: true, ...res };
}

// Callable: the artisan declines a booking request or withdraws before
// payment (policy D6/D7). After payment the funded-job rules apply instead
// (paid-cancellation request, Stage 2/4).
exports.artisanWithdrawFromJob = onCall(async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
  const jobId = typeof request.data?.jobId === 'string' ? request.data.jobId : '';
  const reasonText = typeof request.data?.reason === 'string' ? request.data.reason.trim() : '';
  if (!jobId) throw new HttpsError('invalid-argument', 'jobId is required.');
  if (reasonText.length < 3 || reasonText.length > 500) throw new HttpsError('invalid-argument', 'A reason is required.');
  const snap = await db.collection('jobs').doc(jobId).get();
  if (!snap.exists) throw new HttpsError('not-found', 'Job not found.');
  const job = snap.data();
  if (job.artisanId !== request.auth.uid) throw new HttpsError('permission-denied', 'You are not the artisan on this job.');
  if (['escrowLocked', 'inProgress', 'submitted'].includes(job.status)) {
    throw new HttpsError('failed-precondition', 'This job is already paid — request a cancellation for HandyTrust to review instead.');
  }
  const reason = job.status === 'matched' && job.bookingStatus !== 'confirmed' ? 'artisan_declined_booking' : 'artisan_withdrew';
  const out = await _reopenJob(jobId, {
    reason, expectStatuses: ['matched', 'inChat', 'paymentPending'], requireArtisanId: request.auth.uid,
  });
  if (out.skipped) throw new HttpsError('failed-precondition', `The job changed meanwhile (now ${out.status}).`);
  await db.collection('jobs').doc(jobId).update({ withdrawalNote: reasonText });
  return { reopened: true, reason };
});

// Hourly. Every step re-reads state inside a transaction, so it is safe
// against concurrent customer/artisan actions and against itself.
async function _expireMarketplaceDeadlines(nowMs = Date.now()) {
  const cfg = await _loadPlatformConfig();
  const summary = { bookingsExpired: 0, quotesExpired: 0, jobsExpired: 0 };

  // 1. Booking requests the artisan didn't confirm in time (D5: 24 h).
  const matched = await db.collection('jobs').where('status', '==', 'matched').limit(500).get();
  for (const d of matched.docs) {
    const job = d.data();
    if (job.bookingStatus === 'confirmed') continue;
    const atMs = job.bookingRequestedAt?.toMillis?.() ?? job.matchedAt?.toMillis?.() ?? d.updateTime.toMillis();
    if (nowMs < atMs + cfg.bookingConfirmationHours * HOUR_MS) continue;
    const out = await _reopenJob(d.id, { reason: 'booking_expired', expectStatuses: ['matched'], nowMs });
    if (out.reopened) summary.bookingsExpired++;
  }

  // 2. Open jobs: expire stale quotes (D5: 48 h) and stale jobs (D5: 7 days).
  const open = await db.collection('jobs').where('status', '==', 'requested').limit(500).get();
  for (const d of open.docs) {
    const job = d.data();
    const quotes = (await d.ref.collection('quotes').where('status', '==', 'pending').get()).docs;
    const postedMs = job.reopenedAt?.toMillis?.() ?? d.createTime.toMillis();
    const jobStale = nowMs >= postedMs + cfg.openJobDays * 24 * HOUR_MS;
    const staleQuotes = quotes.filter((q) => {
      const atMs = q.data().updatedAt?.toMillis?.() ?? q.data().createdAt?.toMillis?.() ?? 0;
      return jobStale || nowMs >= atMs + cfg.quoteValidityHours * HOUR_MS;
    });
    if (!jobStale && staleQuotes.length === 0) continue;

    const res = await db.runTransaction(async (tx) => {
      const js = await tx.get(d.ref);
      if (!js.exists || js.data().status !== 'requested') return null;
      const qs = await Promise.all(staleQuotes.map((q) => tx.get(q.ref)));
      const now = admin.firestore.Timestamp.fromMillis(nowMs);
      const expiredQuotes = [];
      for (const q of qs) {
        if (q.exists && q.data().status === 'pending') {
          tx.update(q.ref, { status: 'expired', expiredAt: now });
          expiredQuotes.push(q.id);
        }
      }
      if (jobStale) {
        tx.update(d.ref, {
          status: 'expired', expiredAt: now, lastUpdatedAt: now, lastUpdatedBy: 'system:open_job_expired',
          updateVersion: (js.data().updateVersion || 0) + 1,
        });
        const auditRef = d.ref.collection('auditLogs').doc();
        tx.set(auditRef, {
          id: auditRef.id, jobId: d.id, transactionId: auditRef.id, actionType: 'statusTransition',
          actorId: 'system', actorRole: 'system', timestamp: now, jobStatusBefore: 'requested', jobStatusAfter: 'expired',
          jobVersionBefore: js.data().updateVersion || 0, jobVersionAfter: (js.data().updateVersion || 0) + 1,
          delta: { reason: 'open_job_expired', days: cfg.openJobDays }, isAdminOverride: false,
        });
      }
      return { expiredQuotes, jobExpired: jobStale, customerId: js.data().customerId };
    });
    if (!res) continue;
    summary.quotesExpired += res.expiredQuotes.length;
    for (const artisanId of res.expiredQuotes) {
      await _sendInAppNotification(artisanId, 'job_status_update', 'Quote Expired',
        res.jobExpired ? 'The job you quoted on has closed without a booking.' : 'Your quote expired before the customer accepted it. You can submit a fresh quote while the job is open.', d.id);
    }
    if (res.jobExpired) {
      summary.jobsExpired++;
      await _sendInAppNotification(res.customerId, 'job_status_update', 'Job Expired',
        `Your job received no booking within ${cfg.openJobDays} days and has closed. You can post it again any time.`, d.id);
    }
  }
  // 3. Stage 7.2: let the 90-day response-time window age out for artisans
  //    with no new booking activity (bounded per run; idempotent).
  summary.responseTimesRefreshed = 0;
  const stale = await db.collection('artisans')
    .where('responseTimeUpdatedAt', '<=', admin.firestore.Timestamp.fromMillis(nowMs - 24 * HOUR_MS)).limit(100).get();
  for (const d of stale.docs) {
    await _recomputeResponseTime(d.id, nowMs);
    summary.responseTimesRefreshed++;
  }
  return summary;
}

exports._reopenJob = _reopenJob;
exports._computeTrustScore = _computeTrustScore;
exports._expireMarketplaceDeadlines = _expireMarketplaceDeadlines;

exports.expireMarketplaceDeadlines = onSchedule('every 1 hours', async () => {
  console.log('expireMarketplaceDeadlines', await _expireMarketplaceDeadlines());
});

// ─── Abandoned payments (policy D5: 24 h, config/platform) ──────────────────
const PAYSTACK_IN_FLIGHT = ['ongoing', 'pending', 'processing', 'queued'];

// Pure. `verifications` = Paystack transaction objects for every reference
// involved (or null where verification itself failed).
function _decideStalePaymentAction({ ageMs, thresholdMs, verifications }) {
  if (ageMs < thresholdMs) return { action: 'skip_young' };
  const paid = verifications.find((v) => v && v.status === 'success');
  if (paid) return { action: 'lock', reference: paid.reference };
  if (verifications.some((v) => v === null)) return { action: 'wait_unverifiable' };
  if (verifications.some((v) => PAYSTACK_IN_FLIGHT.includes(v.status))) return { action: 'wait_in_flight' };
  return { action: 'revert' };
}

exports._decideStalePaymentAction = _decideStalePaymentAction;

async function _sweepAbandonedPayments(nowMs = Date.now(), verifyFn = _paystackVerify) {
  const cfg = await _loadPlatformConfig();
  const thresholdMs = cfg.abandonedPaymentHours * 60 * 60 * 1000;
  const summary = { examined: 0, reverted: 0, locked: 0, waiting: 0 };

  const jobs = await db.collection('jobs').where('status', '==', 'paymentPending').limit(500).get();
  for (const jobDoc of jobs.docs) {
    summary.examined++;
    const job = jobDoc.data();
    const startedMs = job.paymentInitializedAt?.toMillis?.() ?? job.lastUpdatedAt?.toMillis?.() ?? 0;

    const pendingPays = await db.collection('payments')
      .where('jobId', '==', jobDoc.id).where('status', '==', 'pending').get();
    const references = new Set(pendingPays.docs.map((d) => d.data().paystackReference).filter(Boolean));
    if (job.pendingPaymentReference) references.add(job.pendingPaymentReference);

    const ageMs = nowMs - startedMs;
    if (ageMs < thresholdMs) continue;

    const verifications = [];
    for (const ref of references) {
      try {
        const v = await verifyFn(ref);
        verifications.push({ ...v, reference: v?.reference || ref });
      } catch (err) {
        console.error(`_sweepAbandonedPayments: verify failed for ${ref}`, err.message);
        verifications.push(null);
      }
    }

    const decision = _decideStalePaymentAction({ ageMs, thresholdMs, verifications });
    if (decision.action === 'lock') {
      const charge = verifications.find((v) => v && v.reference === decision.reference);
      const outcome = await _lockEscrow(jobDoc.id, decision.reference, charge);
      if (outcome === 'lock' || outcome === 'recover_lock') summary.locked++;
      continue;
    }
    if (decision.action !== 'revert') { summary.waiting++; continue; }

    const reverted = await db.runTransaction(async (tx) => {
      const fresh = await tx.get(jobDoc.ref);
      const f = fresh.data();
      // Something else moved the job meanwhile (webhook lock, cancel, a new
      // init) — leave it alone; the next run re-evaluates.
      if (!fresh.exists || f.status !== 'paymentPending' ||
          (f.pendingPaymentReference || null) !== (job.pendingPaymentReference || null)) {
        return false;
      }
      const payRefs = pendingPays.docs.map((d) => d.ref);
      const paySnaps = await Promise.all(payRefs.map((r) => tx.get(r)));
      const now = admin.firestore.Timestamp.fromMillis(nowMs);
      tx.update(jobDoc.ref, {
        status: 'inChat',
        pendingPaymentReference: admin.firestore.FieldValue.delete(),
        paymentInitializedAt: admin.firestore.FieldValue.delete(),
        paymentExpiredAt: now,
        lastUpdatedAt: now,
        lastUpdatedBy: 'system:payment_expiry',
        updateVersion: (f.updateVersion || 0) + 1,
      });
      paySnaps.forEach((ps) => {
        if (ps.exists && ps.data().status === 'pending') {
          tx.update(ps.ref, { status: 'abandoned', abandonReason: 'stale_timeout' });
        }
      });
      const auditRef = jobDoc.ref.collection('auditLogs').doc();
      tx.set(auditRef, {
        id: auditRef.id, jobId: jobDoc.id, transactionId: auditRef.id,
        actionType: 'statusTransition', actorId: 'system', actorRole: 'system',
        timestamp: now, jobStatusBefore: 'paymentPending', jobStatusAfter: 'inChat',
        jobVersionBefore: f.updateVersion || 0, jobVersionAfter: (f.updateVersion || 0) + 1,
        delta: { reason: 'abandoned_payment_expired', hours: cfg.abandonedPaymentHours },
        isAdminOverride: false,
      });
      return true;
    });
    if (reverted) {
      summary.reverted++;
      await _releasePaymentInitializationClaim(jobDoc.id);
      await _sendInAppNotification(
        job.customerId,
        'job_status_update',
        'Payment Expired',
        'Your payment was not completed, so it has expired. Your agreement is still in place — you can pay again from the job page.',
        jobDoc.id
      );
    }
  }
  return summary;
}

exports._sweepAbandonedPayments = _sweepAbandonedPayments;

exports.expireAbandonedPayments = onSchedule(
  { schedule: 'every 1 hours', secrets: ['PAYSTACK_SECRET_KEY'] },
  async () => {
    const summary = await _sweepAbandonedPayments();
    console.log('expireAbandonedPayments', summary);
  }
);

// ─── Payment breakdown (callable) — what the payment screen displays ────────
// The UI shows only server-computed numbers (Stage 3, HT-013), from the same
// _computeCharge that initializePaystackTransaction charges with.
exports.getPaymentBreakdown = onCall(async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
  const jobId = request.data?.jobId;
  if (typeof jobId !== 'string' || !jobId) throw new HttpsError('invalid-argument', 'jobId is required.');
  const jobSnap = await db.collection('jobs').doc(jobId).get();
  if (!jobSnap.exists) throw new HttpsError('not-found', 'Job not found.');
  const job = jobSnap.data();
  if (job.customerId !== request.auth.uid) {
    const adminDoc = await db.collection('admins').doc(request.auth.uid).get();
    if (!adminDoc.exists) throw new HttpsError('permission-denied', 'You are not the customer for this job.');
  }
  const charge = _computeCharge(job.agreedAmount, await _loadPlatformConfig());
  if (!charge.ok) {
    throw new HttpsError('failed-precondition',
      charge.reason === 'below_minimum_job_value'
        ? 'This job is below the minimum job value for online payment.'
        : 'This job has no valid agreed amount.');
  }
  return {
    serviceAmount: charge.serviceAmount,
    platformFee: charge.platformFee,
    totalCharged: charge.totalCharged,
    platformFeePercent: charge.platformFeePercent,
    minPlatformFeeNgn: charge.minPlatformFeeNgn,
    currency: 'NGN',
  };
});

// ─── On Job Completed — update artisan stats + trust score ───────────────────
exports.onJobCompleted = onDocumentUpdated('jobs/{jobId}', async (event) => {
  const before = event.data.before.data();
  const after  = event.data.after.data();

  // Paid-job cancellation request (policy D2) — no status change, so this
  // must run before the status-equality guard below. Admins review it; the
  // other party is told it was filed. Nothing here moves or redirects funds.
  if (after.cancellationRequestStatus === 'pending' &&
      before.cancellationRequestStatus !== 'pending') {
    await _handlePaidCancellationRequest(event.params.jobId, after);
  }

  // Stage 6: agreement sub-state notifications (previously client-written).
  const agreementNote = _agreementNotification(before, after);
  if (agreementNote?.to) {
    await _sendInAppNotification(agreementNote.to, agreementNote.type, agreementNote.title, agreementNote.body,
      event.params.jobId, { dedupeKey: `${event.id}_${agreementNote.to}` });
  }

  if (before.status === after.status) return;

  // Stage 6 (HT-025): work started, cancellation (to the other party).
  for (const n of _statusChangeNotifications(before, after)) {
    await _sendInAppNotification(n.to, n.type, n.title, n.body, event.params.jobId,
      { dedupeKey: `${event.id}_${n.to}` });
  }

  // Stage 5 (D7): a new match is a booking REQUEST the artisan must confirm.
  // Older app builds don't write bookingStatus — normalize it here; the
  // rules only let the artisan confirm (matched -> inChat) from
  // 'awaitingArtisan', within bookingConfirmationHours of the match.
  if (after.status === 'matched' && before.status === 'requested') {
    const fix = {};
    if (!after.bookingStatus) fix.bookingStatus = 'awaitingArtisan';
    if (!after.bookingRequestedAt) fix.bookingRequestedAt = after.matchedAt || admin.firestore.Timestamp.now();
    if (Object.keys(fix).length) await event.data.after.ref.update(fix);
    // Stage 7.2: immutable request record (same server time the 24 h window uses).
    await _recordBookingRequest(event.params.jobId, after, after.bookingRequestedAt || fix.bookingRequestedAt);
    if (after.artisanId) {
      const cfg = await _loadPlatformConfig();
      await _sendInAppNotification(after.artisanId, 'job_assigned', 'New Booking Request',
        `A customer wants to book you. Confirm or decline within ${cfg.bookingConfirmationHours} hours.`, event.params.jobId);
    }
  }
  // Stage 7.2: the artisan's confirmation is their booking response.
  if (after.status === 'inChat' && before.status === 'matched' && after.bookingConfirmedAt?.toMillis) {
    await _recordBookingResponse(event.params.jobId, { ...before, ...after },
      { type: 'confirmed', respondedAt: after.bookingConfirmedAt, source: 'trigger:confirmed' });
  }
  // A request the customer cancels before the artisan answers doesn't qualify.
  if (after.status === 'cancelled' && before.status === 'matched' && before.bookingStatus !== 'confirmed') {
    await _recordBookingResponse(event.params.jobId, before,
      { type: 'cancelled_by_customer', respondedAt: admin.firestore.Timestamp.now(), source: 'trigger:cancelled' });
  }
  if (after.status === 'inChat' && before.status === 'matched' && after.customerId) {
    await _sendInAppNotification(after.customerId, 'job_status_update', 'Booking Confirmed',
      'The artisan confirmed your booking. Agree the final terms in chat.', event.params.jobId);
  }
  // Stage 5 (D4): rework — the job is back in progress, so the old review
  // window no longer applies; a resubmission sets a fresh one.
  if (after.status === 'inProgress' && before.status === 'submitted') {
    await event.data.after.ref.update({
      autoReleaseAt: admin.firestore.FieldValue.delete(),
      disputeWindowEndsAt: admin.firestore.FieldValue.delete(),
    });
    if (after.artisanId) {
      await _sendInAppNotification(after.artisanId, 'job_status_update', 'Rework Requested',
        `The customer asked for changes: ${(after.reworkReason || '').slice(0, 300)}`, event.params.jobId);
    }
  }

  // Stage 2 remediation (HT-005): the review window is server-owned. Both
  // fields are (re)written from the server-stamped submittedAt on every
  // entry into 'submitted' (so a future rework → resubmit, policy D4,
  // naturally restarts it). This update doesn't change status, so the guard
  // above stops it re-triggering this branch.
  if (after.status === 'submitted') {
    const submittedAtMs = after.submittedAt?.toMillis?.() ?? Date.now();
    const windowEnd = admin.firestore.Timestamp.fromMillis(_reviewWindowEndMs(submittedAtMs));
    await event.data.after.ref.update({
      autoReleaseAt: windowEnd,
      disputeWindowEndsAt: windowEnd,
    });
  }

  if (after.status === 'completed' && after.artisanId) {
    await _recordJobOutcome(after.artisanId, 'completed');
    await _sendNotification(event.params.jobId, 'completed');
  }

  if (after.status === 'cancelled' && before.status === 'paymentPending') {
    await _abandonPaymentsForCancelledJob(event.params.jobId);
  }

  // Stage 5: only an ARTISAN's own cancellation counts against their
  // cancellation rate. Customers cancel, and admins settle paid
  // cancellations, without penalising the artisan; an artisan backing out
  // now withdraws via artisanWithdrawFromJob (counted in _reopenJob). The
  // cancelledBy check keeps legacy artisan cancellations counted.
  if (after.status === 'cancelled' && after.artisanId && after.cancelledBy === after.artisanId) {
    await _recordJobOutcome(after.artisanId, 'cancelled');
  }

  if (after.status === 'disputed') {
    if (after.artisanId) await _adjustDisputeCount(after.artisanId, 1);
    await _alertAdminDispute(event.params.jobId, after);
    // Stage 6: the "dispute raised" notification now comes from
    // onDisputeCreated, addressed to whichever party it is against (either
    // side can raise since Stage 5) — this used to always notify the artisan.
  }

  if (after.status === 'resolved' && after.artisanId) {
    await _adjustDisputeCount(after.artisanId, -1);
  }

  if (after.status === 'escrowLocked') {
    await _sendNotification(event.params.jobId, 'escrowLocked');
  }

  if (after.status === 'submitted') {
    await _sendNotification(event.params.jobId, 'submitted');
  }
});

// ─── Trust score computation ──────────────────────────────────────────────────
// Composite score 0-100, 5 weighted components. New artisans (no ratings
// yet) start at a neutral rating component so a single early job can't
// swing the score to extremes.
//
// 30% Completed jobs     — absolute volume, 0 jobs = 0, 50+ jobs = full marks.
//                           (Not a ratio — a brand-new artisan with 2/2 jobs
//                           shouldn't outrank a proven one with 40/45.)
// 25% Customer rating    — 5.0 stars = 100, no ratings yet = neutral 12.5/25.
// 20% Verification       — unverified=0, id_submitted=50, id_verified/trusted=100.
// 15% Response time      — <=15min=100, <=30min=80, <=60min=60, decaying further.
// 10% Dispute history    — no open disputes=100, each one -25.
const TRUST_VERIFICATION_POINTS = {
  unverified: 0,
  id_submitted: 50,
  id_verified: 100,
  trusted: 100,
};

function _trustResponseTimePoints(minutes) {
  if (minutes <= 15) return 100;
  if (minutes <= 30) return 80;
  if (minutes <= 60) return 60;
  if (minutes <= 120) return 40;
  return 20;
}

function _computeTrustScore(stats) {
  const rating = stats.rating || 0;
  const totalRatings = stats.totalRatings || 0;
  const completedJobs = stats.completedJobs || 0;
  const verificationStatus = stats.verificationStatus || 'unverified';
  const responseTimeMinutes = stats.responseTimeMinutes ?? 30;
  const openDisputeCount = stats.openDisputeCount || 0;

  const jobsScore = (Math.min(completedJobs, 50) / 50) * 100 * 0.30;
  const ratingScore = (totalRatings > 0 ? (rating / 5) * 100 : 50) * 0.25;
  const verificationScore =
    (TRUST_VERIFICATION_POINTS[verificationStatus] ?? 0) * 0.20;
  const responseScore = _trustResponseTimePoints(responseTimeMinutes) * 0.15;
  const disputeScore = Math.max(0, 100 - openDisputeCount * 25) * 0.10;

  const score = jobsScore + ratingScore + verificationScore + responseScore + disputeScore;
  return Math.max(0, Math.min(100, Math.round(score * 10) / 10));
}

// ═══ Stage 7.2 — booking response time (15% of the trust score) ═══════════
//
// Approved definition: the median of an artisan's last 20 qualifying booking
// responses within 90 days. A response is the FIRST of:
//   confirmed  — bookingConfirmedAt (rules force request.time)
//   declined   — artisan declines / withdraws before confirming (server now)
//   expired    — no answer within the booking window: counted as 1,440 min
// A withdrawal AFTER confirming keeps the original confirmation (first
// response wins). Fewer than 3 qualifying responses → neutral 30 min.
// A request the customer cancels before the artisan answers is recorded
// but does not qualify.
//
// Records live in booking_responses/{jobId}_{artisanId}_{requestedAtMs}:
// server-written only (rules), one per booking request, the response set
// once and never changed. Times come only from server-stamped fields
// (bookingRequestedAt / matchedAt / bookingConfirmedAt are all forced to
// request.time by the rules) or the server clock, so no client timestamp can
// move the metric. They are written in the same transaction that reopens a
// job, so expiry and withdrawal can no longer erase the history.
const RESPONSE_WINDOW_MS = 90 * 24 * 60 * 60 * 1000;
const RESPONSE_SAMPLE_SIZE = 20;
const RESPONSE_MIN_SAMPLES = 3;
const RESPONSE_NEUTRAL_MINUTES = 30;
const RESPONSE_EXPIRED_MINUTES = 1440;
const QUALIFYING_RESPONSES = ['confirmed', 'declined', 'expired'];

function _bookingRequestTime(job) {
  const t = job?.bookingRequestedAt ?? job?.matchedAt ?? null;
  return t && typeof t.toMillis === 'function' ? t : null;
}

function _bookingResponseRef(jobId, artisanId, requestedAt) {
  return db.collection('booking_responses').doc(`${jobId}_${artisanId}_${requestedAt.toMillis()}`);
}

// Pure. Minutes for one response; expired is always the 1,440 cap.
function _responseMinutes(type, requestedAtMs, respondedAtMs) {
  if (type === 'expired') return RESPONSE_EXPIRED_MINUTES;
  if (!Number.isFinite(requestedAtMs) || !Number.isFinite(respondedAtMs)) return null;
  const m = (respondedAtMs - requestedAtMs) / 60000;
  return Math.round(Math.min(RESPONSE_EXPIRED_MINUTES, Math.max(0, m)) * 10) / 10;
}

// Pure. records: [{ respondedAtMs, minutes }] (qualifying only).
function _medianResponseMinutes(records, nowMs) {
  const recent = records
    .filter((r) => Number.isFinite(r.respondedAtMs) && Number.isFinite(r.minutes) &&
      r.respondedAtMs <= nowMs && r.respondedAtMs >= nowMs - RESPONSE_WINDOW_MS)
    .sort((a, b) => b.respondedAtMs - a.respondedAtMs)
    .slice(0, RESPONSE_SAMPLE_SIZE);
  if (recent.length < RESPONSE_MIN_SAMPLES) return { minutes: RESPONSE_NEUTRAL_MINUTES, sampleSize: recent.length };
  const v = recent.map((r) => r.minutes).sort((a, b) => a - b);
  const mid = Math.floor(v.length / 2);
  const median = v.length % 2 ? v[mid] : (v[mid - 1] + v[mid]) / 2;
  return { minutes: Math.round(median * 10) / 10, sampleSize: recent.length };
}

// Reads (inside tx) whatever is needed to record a response; call BEFORE any
// tx write. Returns a writer to call after the reads, or null.
async function _prepareBookingResponse(tx, jobId, job, { type, respondedAt, source }) {
  const requestedAt = _bookingRequestTime(job);
  if (!job?.artisanId || !requestedAt) return null;
  const ref = _bookingResponseRef(jobId, job.artisanId, requestedAt);
  const snap = await tx.get(ref);
  if (snap.exists && snap.data().responseType) return null; // first response wins; immutable
  return () => {
    const qualifying = QUALIFYING_RESPONSES.includes(type);
    tx.set(ref, {
      jobId, artisanId: job.artisanId, customerId: job.customerId || null, requestedAt,
      responseType: type, respondedAt, source, qualifying,
      responseMinutes: qualifying ? _responseMinutes(type, requestedAt.toMillis(), respondedAt.toMillis()) : null,
      ...(snap.exists ? {} : { createdAt: admin.firestore.Timestamp.now() }),
    }, { merge: true });
    return qualifying ? job.artisanId : null;
  };
}

// Outside any transaction (triggers): record a response in its own transaction.
async function _recordBookingResponse(jobId, job, response) {
  const artisanId = await db.runTransaction(async (tx) => {
    const write = await _prepareBookingResponse(tx, jobId, job, response);
    return write ? write() : null;
  });
  if (artisanId) await _recomputeResponseTime(artisanId);
  return artisanId;
}

// Create-once record of the request itself (so a request is on file even
// before any response).
async function _recordBookingRequest(jobId, job, requestedAt) {
  if (!job?.artisanId || !requestedAt) return;
  const ref = _bookingResponseRef(jobId, job.artisanId, requestedAt);
  await db.runTransaction(async (tx) => {
    const s = await tx.get(ref);
    if (s.exists) return;
    tx.set(ref, {
      jobId, artisanId: job.artisanId, customerId: job.customerId || null, requestedAt,
      responseType: null, qualifying: false, createdAt: admin.firestore.Timestamp.now(),
    });
  });
}

async function _recomputeResponseTime(artisanId, nowMs = Date.now()) {
  const artRef = db.collection('artisans').doc(artisanId);
  return db.runTransaction(async (tx) => {
    const [a, q] = await Promise.all([
      tx.get(artRef),
      tx.get(db.collection('booking_responses')
        .where('artisanId', '==', artisanId).where('qualifying', '==', true)
        .where('respondedAt', '>=', admin.firestore.Timestamp.fromMillis(nowMs - RESPONSE_WINDOW_MS))
        .orderBy('respondedAt', 'desc').limit(RESPONSE_SAMPLE_SIZE)),
    ]);
    if (!a.exists) return null;
    const records = q.docs.map((d) => ({ respondedAtMs: d.data().respondedAt.toMillis(), minutes: d.data().responseMinutes }));
    const { minutes, sampleSize } = _medianResponseMinutes(records, nowMs);
    const trustScore = _computeTrustScore({ ...a.data(), responseTimeMinutes: minutes });
    tx.update(artRef, {
      responseTimeMinutes: minutes, responseTimeSampleSize: sampleSize,
      responseTimeUpdatedAt: admin.firestore.Timestamp.fromMillis(nowMs), trustScore,
    });
    return { minutes, sampleSize, trustScore };
  });
}

exports._responseMinutes = _responseMinutes;
exports._medianResponseMinutes = _medianResponseMinutes;
exports._recomputeResponseTime = _recomputeResponseTime;
exports._recordBookingResponse = _recordBookingResponse;
exports._recordBookingRequest = _recordBookingRequest;

// Records a completed/cancelled job against an artisan's lifetime stats and
// recomputes their trust score in the same transaction — single source of
// truth for both job-outcome counters and the derived score.
async function _recordJobOutcome(artisanId, outcome) {
  const artRef = db.collection('artisans').doc(artisanId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(artRef);
    if (!snap.exists) return;
    const data = snap.data();

    const totalJobs = (data.totalJobs || 0) + 1;
    const completedJobs = (data.completedJobs || 0) + (outcome === 'completed' ? 1 : 0);
    const cancelledJobsCount = (data.cancelledJobsCount || 0) + (outcome === 'cancelled' ? 1 : 0);
    const cancellationRatePercent =
      totalJobs > 0 ? Math.round((cancelledJobsCount / totalJobs) * 1000) / 10 : 0;

    const trustScore = _computeTrustScore({
      ...data,
      totalJobs,
      completedJobs,
      cancellationRatePercent,
    });

    tx.update(artRef, {
      totalJobs,
      completedJobs,
      cancelledJobsCount,
      cancellationRatePercent,
      trustScore,
    });
  });
}

// Adjusts open-dispute count (+1 when raised, -1 when resolved) and
// recomputes trust score in the same transaction.
async function _adjustDisputeCount(artisanId, delta) {
  const artRef = db.collection('artisans').doc(artisanId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(artRef);
    if (!snap.exists) return;
    const data = snap.data();

    const openDisputeCount = Math.max(0, (data.openDisputeCount || 0) + delta);
    const trustScore = _computeTrustScore({ ...data, openDisputeCount });

    tx.update(artRef, { openDisputeCount, trustScore });
  });
}

// ─── On Artisan Rating Changed — keep trust score in sync with reviews ───────
// ReviewScreen writes rating/totalRatings directly to /artisans (existing,
// pre-dating this Cloud Function). This trigger recomputes trustScore so it
// reflects every new review without adding a parallel write path — the only
// thing it ever writes is trustScore itself, and the guard below stops it
// from re-triggering on its own update.
// ─── On Review Created — the missing half of the rating pipeline ───────────
// Root cause (design/HANDYTRUST_V1_V2_MASTER_GAP_ANALYSIS.md §16.2 / V2_IOS_
// SAFARI_RELIABILITY_REPORT.md): review_screen.dart used to attempt a
// DIRECT client-side transaction updating artisans/{artisanId}.rating —
// but the writer is the reviewing customer, whose uid can never equal the
// artisan document's own id, so firestore.rules' isOwner(uid)||isAdmin()
// gate on that collection's update rule rejected it on every attempt,
// silently (wrapped in an empty-ish catch with a comment claiming a Cloud
// Function handled it in production — no such function existed until now).
// Net effect: a review document was created, but the artisan's rating/
// totalRatings/trustScore never moved, for any review, ever.
//
// This function is that missing piece: it aggregates rating/totalRatings
// server-side (Admin SDK, bypasses rules by design — this is exactly the
// kind of aggregation that must not live entirely on an untrusted client),
// then onArtisanRatingChanged (below, unmodified) picks up the resulting
// rating/totalRatings change and recomputes trustScore exactly as it
// already does for every other rating-affecting event.
exports._computeReviewApplication = function _computeReviewApplication(review, job, reviewId) {
  // Pure, unit-testable validation — returns a reason string if the review
  // must be rejected (never applied to the aggregate), or null if it's
  // safe to apply. Exported for functions/test/review_rating_pipeline.test.js.
  if (!review || typeof review.rating !== 'number' || review.rating < 1 || review.rating > 5) {
    return 'invalid_rating';
  }
  // Stage 2 remediation (HT-014): one review per job — the rules now
  // require reviews/{jobId}; this rejects legacy or Admin-written
  // documents under any other ID so they can't be aggregated a second time.
  if (reviewId !== undefined && reviewId !== review.jobId) {
    return 'review_id_not_job_id';
  }
  if (typeof review.artisanId !== 'string' || !review.artisanId) {
    return 'missing_artisan_id';
  }
  if (!job) {
    return 'job_not_found';
  }
  // Defense-in-depth against a separate, documented gap: firestore.rules'
  // reviews create rule never checks request.resource.data.artisanId ==
  // getJob(jobId).artisanId, so a customer could otherwise attribute a
  // review to an artisan uninvolved in the job. This is the actual point
  // such a fabricated review would cause real harm (rating manipulation),
  // so it is re-verified here rather than trusting the review document.
  if (job.artisanId !== review.artisanId) {
    return 'artisan_mismatch';
  }
  if (job.customerId !== review.customerId) {
    return 'customer_mismatch';
  }
  if (job.status !== 'completed') {
    return 'job_not_completed';
  }
  return null;
};

exports.onReviewCreated = onDocumentCreated('reviews/{reviewId}', async (event) => {
  const reviewId = event.params.reviewId; // == jobId, by client convention (review_screen.dart)
  const review = event.data.data();

  const jobSnap = await db.collection('jobs').doc(review?.jobId || reviewId).get();
  const job = jobSnap.exists ? jobSnap.data() : null;

  const rejection = exports._computeReviewApplication(review, job, reviewId);
  if (rejection) {
    console.error(`onReviewCreated: refusing to apply review ${reviewId} to artisan aggregate — ${rejection}`);
    return;
  }

  const artisanId = review.artisanId;
  const artisanRef = db.collection('artisans').doc(artisanId);
  // Idempotency marker — Cloud Functions triggers are at-least-once
  // delivery; without this, a redelivered trigger for the same review
  // would double-count it into the rating average. Same fixed-ID
  // transactional-guard pattern already used by escrow_releases/
  // payment_init_locks elsewhere in this file.
  const appliedMarkerRef = artisanRef.collection('appliedReviews').doc(reviewId);

  await db.runTransaction(async (tx) => {
    const [artisanSnap, markerSnap] = await Promise.all([tx.get(artisanRef), tx.get(appliedMarkerRef)]);
    if (!artisanSnap.exists) {
      console.error(`onReviewCreated: artisan ${artisanId} not found for review ${reviewId}`);
      return;
    }
    if (markerSnap.exists) {
      console.log(`onReviewCreated: review ${reviewId} already applied to artisan ${artisanId} — skipping redelivered trigger`);
      return;
    }
    const data = artisanSnap.data();
    const oldRating = typeof data.rating === 'number' ? data.rating : 0;
    const oldCount = typeof data.totalRatings === 'number' ? data.totalRatings : 0;
    const newCount = oldCount + 1;
    const newRating = ((oldRating * oldCount) + review.rating) / newCount;
    tx.update(artisanRef, {
      rating: Math.round(newRating * 100) / 100,
      totalRatings: newCount,
    });
    tx.set(appliedMarkerRef, { reviewId, appliedAt: admin.firestore.Timestamp.now() });
  });
  // Stage 6: server-generated (clients can no longer write notifications).
  await _sendInAppNotification(artisanId, 'review_received', 'New Review Received',
    `You received a ${review.rating}-star review on a completed job.`, review.jobId || reviewId,
    { dedupeKey: `review_${reviewId}` });
});

exports.onArtisanRatingChanged = onDocumentUpdated('artisans/{artisanId}', async (event) => {
  const before = event.data.before.data();
  const after  = event.data.after.data();

  if (before.rating === after.rating && before.totalRatings === after.totalRatings) {
    return;
  }

  const trustScore = _computeTrustScore(after);
  if (trustScore === after.trustScore) return;

  await db.collection('artisans').doc(event.params.artisanId).update({ trustScore });
});

// ─── On Artisan Verification Changed — keep trust score in sync ─────────────
// VerificationService.approve()/reject() writes verificationStatus directly
// to /artisans (existing). This trigger recomputes trustScore the same way
// onArtisanRatingChanged does for reviews — same guard against re-triggering
// on its own write.
exports.onArtisanVerificationChanged = onDocumentUpdated('artisans/{artisanId}', async (event) => {
  const before = event.data.before.data();
  const after  = event.data.after.data();

  if (before.verificationStatus === after.verificationStatus) return;

  const trustScore = _computeTrustScore(after);
  if (trustScore === after.trustScore) return;

  await db.collection('artisans').doc(event.params.artisanId).update({ trustScore });
});

// ─── Keep admin custom claim in sync with the /admins registry ──────────────
// firestore.rules' isAdmin() checks for an /admins/{uid} doc; storage.rules'
// isAdmin() checks the custom auth claim `admin: true`. Previously these
// were two independent, manually-coordinated mechanisms — granting one
// without the other left an account with partial admin access (e.g.
// dashboard access but Storage reads denied). These triggers make the
// Firestore doc the single source of truth: creating/deleting it is now
// the only step needed, and the claim follows automatically.
//
// Note: a custom claim change only takes effect on the client after that
// user's ID token is refreshed (re-auth, or up to ~1h for automatic
// refresh) — this is a Firebase Auth constraint, not something a Cloud
// Function can force immediately.
exports.onAdminGranted = onDocumentCreated('admins/{uid}', async (event) => {
  const uid = event.params.uid;
  try {
    await admin.auth().setCustomUserClaims(uid, { admin: true });
    console.log(`Admin claim granted for ${uid}`);
  } catch (err) {
    console.error(`Failed to grant admin claim for ${uid}:`, err.message);
  }
});

exports.onAdminRevoked = onDocumentDeleted('admins/{uid}', async (event) => {
  const uid = event.params.uid;
  try {
    await admin.auth().setCustomUserClaims(uid, { admin: false });
    console.log(`Admin claim revoked for ${uid}`);
  } catch (err) {
    console.error(`Failed to revoke admin claim for ${uid}:`, err.message);
  }
});

// ─── On Dispute Created — alert admin ────────────────────────────────────────
// Stage 6: deterministic admin alert (redelivery-safe, Stage 4 R-8) and the
// "dispute raised" notification to the other party.
exports.onDisputeCreated = onDocumentCreated('disputes/{disputeId}', (event) =>
  _handleDisputeCreated(event.params.disputeId, event.data.data(), event.id));

async function _handlePaidCancellationRequest(jobId, jobData) {
  const requestedBy = jobData.cancellationRequestedBy;
  // Idempotent under trigger redelivery (Stage 3 fix of a Stage 2 gap):
  // one alert per request, keyed by job + request time. create() fails on
  // redelivery, and the notification below only follows a first create.
  const requestedAtMs = jobData.cancellationRequestedAt?.toMillis?.() ?? 0;
  const alertRef = db.collection('admin_alerts').doc(`paidcancel_${jobId}_${requestedAtMs}`);
  try {
    await alertRef.create({
      type: 'paid_cancellation_request',
      jobId,
      requestedBy,
      reason: jobData.cancellationRequestReason || null,
      jobStatus: jobData.status,
      createdAt: admin.firestore.Timestamp.now(),
      resolved: false,
    });
  } catch (err) {
    if (err.code === 6 /* ALREADY_EXISTS */) return;
    throw err;
  }
  const otherParty = requestedBy === jobData.customerId ? jobData.artisanId : jobData.customerId;
  if (otherParty) {
    await _sendInAppNotification(
      otherParty,
      'job_status_update',
      'Cancellation Requested',
      'The other party asked to cancel this paid job. HandyTrust will review it — funds stay protected in escrow meanwhile.',
      jobId
    );
  }
}

exports._handlePaidCancellationRequest = _handlePaidCancellationRequest;

// A job cancelled while paymentPending (still client-permitted: nothing has
// been paid yet) may have an open Paystack checkout. Mark its pending
// payments abandoned and drop the init lock so no reused authorization URL
// can be handed out; any charge that still succeeds afterwards is decided
// by _decideChargeOutcome as 'paid_after_cancellation' → requires_refund.
async function _abandonPaymentsForCancelledJob(jobId) {
  const pending = await db.collection('payments')
    .where('jobId', '==', jobId).where('status', '==', 'pending').get();
  await Promise.all(pending.docs.map((d) =>
    d.ref.update({ status: 'abandoned', abandonReason: 'job_cancelled' })));
  await _releasePaymentInitializationClaim(jobId);
}

exports._abandonPaymentsForCancelledJob = _abandonPaymentsForCancelledJob;

async function _alertAdminDispute(jobId, jobData) {
  // Deterministic id: one alert per disputed job even if the trigger is
  // redelivered (Stage 4 R-8). A job can only be disputed once.
  await db.collection('admin_alerts').doc(`dispute_job_${jobId}`).set({
    type: 'dispute_from_job',
    jobId,
    customerId: jobData.customerId,
    artisanId: jobData.artisanId,
    reason: jobData.disputeReason,
    createdAt: admin.firestore.Timestamp.now(),
    resolved: false,
  });
}

// ─── Push Notifications ───────────────────────────────────────────────────────
// Writes the in-app notification doc for each recipient of a job-status
// event; onNotificationCreated above picks up the write and sends the
// push. No direct messaging.send() call here anymore — see
// design/STITCH_NOTIFICATION_AUDIT.md for why that used to be a bug (this
// path pushed but never appeared in the in-app Notification Center).
async function _sendNotification(jobId, eventType) {
  const job = await db.collection('jobs').doc(jobId).get();
  if (!job.exists) return;

  const { customerId, artisanId } = job.data();
  const messages = _buildMessages(eventType, jobId, customerId, artisanId);

  for (const msg of messages) {
    try {
      await _sendInAppNotification(msg.userId, msg.type, msg.title, msg.body, jobId);
    } catch (err) {
      console.error(`_sendNotification: write failed for ${msg.userId}:`, err.message);
    }
  }
}

function _buildMessages(eventType, jobId, customerId, artisanId) {
  // type values are existing, already-whitelisted notification types (see
  // firestore.rules and lib/screens/notifications/notifications_screen.dart's
  // icon mapping) — no new types invented for this fix.
  const msgs = {
    escrowLocked: [
      {
        userId: artisanId,
        type: 'job_status_update',
        title: '💰 Payment Secured',
        body: 'Escrow is locked. You can now start work on the job.',
      },
      {
        userId: customerId,
        type: 'job_status_update',
        title: '🔒 Funds Locked in Escrow',
        body: 'Your payment is safe. The artisan will begin work shortly.',
      },
    ],
    submitted: [
      {
        userId: customerId,
        type: 'job_status_update',
        title: '✅ Work Submitted',
        body: 'The artisan has submitted completion. Please review and confirm.',
      },
    ],
    completed: [
      {
        userId: artisanId,
        type: 'job_status_update',
        title: '🎉 Job Confirmed',
        body: 'The customer confirmed your work. Your payout is being processed — we will notify you when it is sent.',
      },
    ],
    disputed: [
      {
        userId: artisanId,
        type: 'dispute_raised',
        title: '⚠️ Dispute Raised',
        body: 'The customer has raised a dispute. Our team will review within 48h.',
      },
    ],
  };
  return msgs[eventType] ?? [];
}

// ─── Initialize Paystack Transaction (callable from client) ──────────────────
// Replaces the old client-side PaystackService.initializeTransaction, which
// read the Paystack SECRET key directly from a Firestore doc
// (/config/paystack) that any signed-in user could read. The secret now
// never leaves this function — it's a Functions secret, not Firestore data.
// Phase 10B remediation (design/PHASE_10_AUTHENTICATED_PAYMENT_QA.md) —
// initializePaystackTransaction idempotency. Previously every call created
// a brand-new payments doc + Paystack transaction reference with no check
// for an existing in-flight or recently-completed attempt for the same
// job — a double-click, a client retry after a slow/ambiguous response, a
// browser refresh-and-resubmit, or two genuinely concurrent requests could
// each create a separate real Paystack transaction for the same job.
//
// A per-job "lock" document (collection has no client-facing Firestore
// rule at all — it is written/read exclusively by this Cloud Function
// under the Admin SDK, so Firestore's default-deny is correct and
// sufficient, no rule needed) provides the coalescing:
//   - First caller for a job claims the lock (status:'initializing') and
//     proceeds normally.
//   - A caller that arrives while a claim is in flight waits briefly
//     (bounded, up to 5s total) for it to resolve, then reuses the SAME
//     result — no second Paystack call, no client-visible error for the
//     ordinary double-click/retry case.
//   - A caller that arrives after a completed initialization (within the
//     reuse window, matching Paystack's own authorization-URL lifetime)
//     reuses that same result outright.
//   - A stale claim (the prior attempt crashed mid-flight, never
//     resolved) is treated as abandoned and reclaimed rather than
//     blocking the job forever.
const PAYMENT_INIT_LOCK_STALE_MS = 60 * 1000;
const PAYMENT_INIT_RESULT_REUSE_MS = 30 * 60 * 1000;

async function _claimOrAwaitPaymentInitialization(jobId) {
  const lockRef = db.collection('payment_init_locks').doc(jobId);

  for (let attempt = 0; attempt < 10; attempt++) {
    const outcome = await db.runTransaction(async (tx) => {
      const snap = await tx.get(lockRef);
      const now = Date.now();
      if (snap.exists) {
        const lock = snap.data();
        const ageMs = now - (lock.updatedAtMs || 0);
        if (lock.status === 'done' && ageMs < PAYMENT_INIT_RESULT_REUSE_MS) {
          return { state: 'done', result: lock.result };
        }
        if (lock.status === 'initializing' && ageMs < PAYMENT_INIT_LOCK_STALE_MS) {
          return { state: 'waiting' };
        }
        // Stale (either an abandoned in-flight claim or an old completed
        // result outside the reuse window) — fall through and reclaim.
      }
      tx.set(lockRef, { status: 'initializing', updatedAtMs: now });
      return { state: 'claimed' };
    });

    if (outcome.state === 'claimed') return { claimed: true };
    if (outcome.state === 'done') return { claimed: false, result: outcome.result };
    // 'waiting' — another invocation's claim is genuinely in flight; give
    // it a moment to finish rather than racing a second Paystack call.
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  throw new HttpsError(
    'deadline-exceeded',
    'Payment initialization is taking longer than expected — please try again.'
  );
}

async function _resolvePaymentInitialization(jobId, result) {
  await db
    .collection('payment_init_locks')
    .doc(jobId)
    .set({ status: 'done', updatedAtMs: Date.now(), result }, { merge: true });
}

async function _releasePaymentInitializationClaim(jobId) {
  // Best-effort — if this fails, the claim simply expires naturally after
  // PAYMENT_INIT_LOCK_STALE_MS instead of being released immediately.
  await db.collection('payment_init_locks').doc(jobId).delete().catch(() => {});
}

// Exported for functions/test/payment_init_idempotency.test.js — these run
// real Firestore transactions, so that test targets the local emulator,
// never production (see the test file's own header).
exports._claimOrAwaitPaymentInitialization = _claimOrAwaitPaymentInitialization;
exports._resolvePaymentInitialization = _resolvePaymentInitialization;
exports._releasePaymentInitializationClaim = _releasePaymentInitializationClaim;

exports.initializePaystackTransaction = onCall(
  { secrets: ['PAYSTACK_SECRET_KEY'] },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign in required.');
    }
    const { jobId, email } = request.data || {};
    if (typeof jobId !== 'string' || jobId.length === 0) {
      throw new HttpsError('invalid-argument', 'jobId is required.');
    }
    const payerId = request.auth.uid;

    // Stage 5 (D9): administrative/verification suspensions may still pay
    // for an existing job (restricted mode); fraud/safety/security — or an
    // unclassified suspension — may not move new money in.
    const payerSnap = await db.collection('users').doc(payerId).get();
    if (_isFreezingSuspension(payerSnap.exists ? payerSnap.data() : null)) {
      throw new HttpsError('permission-denied', 'Your account is suspended pending review; payments are paused.');
    }

    // P0 remediation (design/P0_REMEDIATION_PLAN.md, amount-consistency
    // requirement): the client used to supply `amount` and `artisanId`
    // directly, with no server-side check that either matched the job at
    // all — a customer could charge (and later have released to an
    // artisan) an amount with no relationship to what was actually
    // negotiated. The job document is now the sole source of truth for
    // both: this function reads it directly and ignores any client-
    // supplied amount/artisanId entirely, rather than merely validating
    // them, since a validate-only approach still trusts the client to
    // supply the field being validated against itself in some other flow.
    const jobSnap = await db.collection('jobs').doc(jobId).get();
    if (!jobSnap.exists) {
      throw new HttpsError('not-found', 'Job not found.');
    }
    const job = jobSnap.data();
    if (job.customerId !== payerId) {
      throw new HttpsError('permission-denied', 'You are not the customer for this job.');
    }
    if (job.status !== 'paymentPending') {
      throw new HttpsError(
        'failed-precondition',
        `This job is not ready for payment (status: ${job.status}).`
      );
    }
    const amount = job.agreedAmount;
    if (typeof amount !== 'number' || !(amount > 0)) {
      throw new HttpsError('failed-precondition', 'This job has no valid agreed amount to charge.');
    }
    // Stage 3 (D1): the charge is the frozen agreed service price plus the
    // platform fee, computed here from backend config — never from the client.
    const charge = _computeCharge(amount, await _loadPlatformConfig());
    if (!charge.ok) {
      throw new HttpsError('failed-precondition',
        charge.reason === 'below_minimum_job_value'
          ? 'This job is below the minimum job value for online payment.'
          : 'This job has no valid agreed amount to charge.');
    }
    const artisanId = job.artisanId || '';

    const customerEmail =
      typeof email === 'string' && email.includes('@') ? email : `${payerId}@handytrust.ng`;

    // Idempotency claim — see the block comment above
    // _claimOrAwaitPaymentInitialization. Must happen after the
    // ownership/status/amount checks above (those should fail fast and
    // cheaply on every call, claimed or not) but before any Paystack call.
    const claim = await _claimOrAwaitPaymentInitialization(jobId);
    if (!claim.claimed) {
      // Either we reused a completed prior result, or another invocation's
      // claim resolved to 'done' while we were polling for it above — both
      // return the SAME shape as a fresh initialization would.
      return claim.result;
    }

    // Stage 3 retry safety: if an earlier attempt for this job is still the
    // active one, ask Paystack before opening a second transaction. If it
    // actually succeeded (e.g. the webhook is delayed), apply it and tell the
    // client — never create a second charge for an already-paid job.
    if (job.pendingPaymentReference) {
      let previous = null;
      try {
        previous = await _paystackVerify(job.pendingPaymentReference);
      } catch (err) {
        console.warn(`initializePaystackTransaction: could not verify previous reference ${job.pendingPaymentReference}`, err.message);
      }
      if (previous?.status === 'success') {
        await _releasePaymentInitializationClaim(jobId);
        const outcome = await _lockEscrow(jobId, job.pendingPaymentReference, previous);
        return { alreadyPaid: true, outcome };
      }
      if (!previous || ['ongoing', 'pending', 'processing', 'queued'].includes(previous.status)) {
        // Can't rule out an in-flight payment — refuse rather than risk a
        // double charge. The client can retry shortly.
        await _releasePaymentInitializationClaim(jobId);
        throw new HttpsError('aborted',
          'Your previous payment attempt is still being processed. Please wait a moment and try again.');
      }
      const prevSnap = await db.collection('payments')
        .where('paystackReference', '==', job.pendingPaymentReference).limit(1).get();
      if (!prevSnap.empty && prevSnap.docs[0].data().status === 'pending') {
        await prevSnap.docs[0].ref.update({ status: 'abandoned', abandonReason: 'superseded_by_retry' });
      }
    }

    const paymentRef = db.collection('payments').doc();
    const amountKobo = charge.totalKobo;

    let data;
    try {
      const resp = await axios.post(
        'https://api.paystack.co/transaction/initialize',
        {
          email: customerEmail,
          amount: amountKobo,
          currency: 'NGN',
          reference: paymentRef.id,
          metadata: {
            jobId,
            payerId,
            artisanId,
            custom_fields: [
              { display_name: 'Job ID', variable_name: 'job_id', value: jobId },
            ],
          },
          channels: ['card', 'bank', 'ussd', 'bank_transfer'],
        },
        { headers: { Authorization: `Bearer ${process.env.PAYSTACK_SECRET_KEY}` } }
      );
      data = resp.data.data;

      // `amount` stays the artisan's service price (what payout, wallet and
      // admin GMV have always read); the fee and the true customer charge
      // are recorded alongside it. amountKobo is what Paystack must report.
      const now = admin.firestore.Timestamp.now();
      await paymentRef.set({
        id: paymentRef.id,
        jobId,
        payerId,
        artisanId,
        amount: charge.serviceAmount,
        serviceAmount: charge.serviceAmount,
        platformFee: charge.platformFee,
        totalCharged: charge.totalCharged,
        amountKobo: charge.totalKobo,
        currency: 'NGN',
        feePolicy: { platformFeePercent: charge.platformFeePercent, minPlatformFeeNgn: charge.minPlatformFeeNgn },
        status: 'pending',
        paystackReference: data.reference,
        paystackAccessCode: data.access_code,
        authorizationUrl: data.authorization_url,
        createdAt: now,
      });
      await jobSnap.ref.update({
        pendingPaymentReference: data.reference,
        paymentInitializedAt: now,
      });
    } catch (err) {
      // Release the claim on failure so a genuine retry isn't blocked for
      // up to a minute — a failed Paystack call or Firestore write means
      // no transaction was actually created, so there's nothing to dedupe
      // against yet.
      await _releasePaymentInitializationClaim(jobId);
      throw err;
    }

    const result = {
      paymentId: paymentRef.id,
      reference: data.reference,
      accessCode: data.access_code,
      authorizationUrl: data.authorization_url,
      serviceAmount: charge.serviceAmount,
      platformFee: charge.platformFee,
      totalCharged: charge.totalCharged,
    };
    await _resolvePaymentInitialization(jobId, result);
    return result;
  }
);

// ─── Verify Paystack Transaction (callable from client) ───────────────────────
// Paystack GET /transaction/verify. A 400/404 ("reference not found") is a
// definite non-payment and maps to status 'not_found'; network/5xx errors
// still throw, so callers treat them as "unknown — don't assume unpaid".
async function _paystackVerify(reference) {
  try {
    const resp = await axios.get(
      `https://api.paystack.co/transaction/verify/${encodeURIComponent(reference)}`,
      { headers: { Authorization: `Bearer ${process.env.PAYSTACK_SECRET_KEY}` } }
    );
    return resp.data.data;
  } catch (err) {
    const code = err.response?.status;
    if (code === 400 || code === 404) return { status: 'not_found', reference };
    throw err;
  }
}

exports.verifyPayment = onCall(
  { secrets: ['PAYSTACK_SECRET_KEY'] },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign in required.');
    }
    const { reference, jobId } = request.data || {};
    if (typeof reference !== 'string' || !reference || typeof jobId !== 'string' || !jobId) {
      throw new HttpsError('invalid-argument', 'reference and jobId are required.');
    }

    // Stage 3: only the job's own customer (or an admin) may trigger a
    // verification for it.
    const jobSnap = await db.collection('jobs').doc(jobId).get();
    if (!jobSnap.exists) throw new HttpsError('not-found', 'Job not found.');
    if (jobSnap.data().customerId !== request.auth.uid) {
      const adminDoc = await db.collection('admins').doc(request.auth.uid).get();
      if (!adminDoc.exists) {
        throw new HttpsError('permission-denied', 'You are not the customer for this job.');
      }
    }

    const data = await _paystackVerify(reference);

    // Trust Paystack's own metadata (set at initializePaystackTransaction
    // time), not the client-supplied jobId. Without this check, a caller
    // could pass a jobId they don't own alongside a reference from an
    // unrelated, genuinely-successful transaction and fraudulently lock
    // escrow on someone else's job.
    if (data.metadata?.jobId !== jobId) {
      throw new HttpsError('failed-precondition', 'This payment reference does not match the specified job.');
    }

    if (data.status === 'success') {
      const outcome = await _lockEscrow(jobId, reference, data);
      // Only a charge that actually funds this job reports success to the
      // UI; a captured-but-refund-required charge must not read as "paid".
      const funded = outcome === 'lock' || outcome === 'recover_lock' ||
        outcome === 'already_locked' || outcome === 'already_recorded';
      return funded
        ? { success: true, outcome }
        : { success: false, outcome, gateway_response: 'Payment received but could not be applied to this job — our team will refund it.' };
    }
    return { success: false, gateway_response: data.gateway_response };
  }
);

// ─── AI Job Assistant (V1 — job-improvement only, callable from client) ──────
// Scope is deliberately narrow: classify category + tighten the description.
// Not a chatbot, not stateful, nothing persisted here — the client decides
// whether to save the suggestion onto the job doc at creation time.
const JOB_CATEGORIES = [
  'Plumbing', 'Electrical', 'Carpentry', 'Painting', 'Cleaning',
  'HVAC / AC Repair', 'Welding', 'Tiling', 'Generator Repair',
  'Home Renovation', 'Security Systems', 'Landscaping', 'Other',
];

const ANALYZE_JOB_PROMPT = `You are a job-classification assistant for HandyTrust, a home-services marketplace in Nigeria.
A customer wrote the job description below, optionally with photos of the problem.

Your task:
1. Pick the single best-matching category from this exact list (return the string exactly as written): ${JOB_CATEGORIES.join(', ')}.
2. Rewrite the description so it is clearer and more complete for an artisan to quote accurately. Only use facts the customer stated or that are visibly true in the photos — never invent measurements, quantities, brands, or causes that weren't given.
3. Give a confidence score from 0.0 to 1.0 for the category match. If the description is vague, ambiguous, or could fit more than one category, lower the confidence instead of guessing.

Respond with JSON only, matching this exact shape:
{"suggestedCategory": string, "confidence": number, "enhancedDescription": string}

Customer's description:
"""`;

exports.analyzeJob = onCall(
  { secrets: ['GEMINI_API_KEY'] },
  async (request) => {
    if (!request.auth) {
      throw new Error('Sign in required.');
    }

    const description = typeof request.data?.description === 'string'
      ? request.data.description.trim()
      : '';
    if (description.length < 10) {
      throw new Error('description must be at least 10 characters.');
    }
    if (description.length > 2000) {
      throw new Error('description is too long (max 2000 characters).');
    }

    // Images arrive as raw base64 — job photos aren't uploaded to Storage
    // until the customer actually submits the job, so there are no
    // imageUrls yet to hand to Gemini at preview time.
    const rawImages = Array.isArray(request.data?.images) ? request.data.images : [];
    const images = rawImages
      .filter((b64) => typeof b64 === 'string' && b64.length > 0 && b64.length < 2_000_000)
      .slice(0, 3);

    const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
    const model = genAI.getGenerativeModel({
      model: 'gemini-2.0-flash',
      generationConfig: {
        responseMimeType: 'application/json',
        responseSchema: {
          type: 'object',
          properties: {
            suggestedCategory: { type: 'string', enum: JOB_CATEGORIES },
            confidence: { type: 'number' },
            enhancedDescription: { type: 'string' },
          },
          required: ['suggestedCategory', 'confidence', 'enhancedDescription'],
        },
      },
    });

    const parts = [
      { text: `${ANALYZE_JOB_PROMPT}${description}"""` },
      ...images.map((data) => ({ inlineData: { mimeType: 'image/jpeg', data } })),
    ];

    let parsed;
    try {
      const result = await model.generateContent(parts);
      parsed = JSON.parse(result.response.text());
    } catch (err) {
      console.error('analyzeJob: Gemini call failed', err);
      throw new Error('AI analysis is unavailable right now. Please try again.');
    }

    // Sanitize before returning — never trust the model's output shape blindly.
    const suggestedCategory = JOB_CATEGORIES.includes(parsed.suggestedCategory)
      ? parsed.suggestedCategory
      : 'Other';
    const confidence = Math.max(0, Math.min(1, Number(parsed.confidence) || 0));
    const enhancedDescription = typeof parsed.enhancedDescription === 'string'
      ? parsed.enhancedDescription.trim().slice(0, 2000)
      : description;

    return { suggestedCategory, confidence, enhancedDescription };
  }
);

// ─── Admin: disable a deleted user's Auth account ──────────────────────────
// The admin dashboard's "Delete User" action removes the Firestore docs
// directly (covered by firestore.rules' isAdmin() delete rule), but the
// client SDK cannot touch another user's Auth account — only the Admin SDK
// can. This callable does only that narrow step. Authorization mirrors
// firestore.rules' isAdmin(): existence of an /admins/{uid} doc, the same
// source of truth the rest of the app already relies on.
// ─── Admin: Permanently Delete User (admin-deletion audit) ──────────────────
//
// Previously: this function only DISABLED the Auth account
// (updateUser({disabled:true})) despite its name — the account, email, and
// phone number were never actually removable, and could never be re-
// registered. Meanwhile ALL Firestore deletion happened client-side (a
// batch touching only users/{uid} and artisans/{uid}), with no audit log
// ever written for the deletion itself (AdminAction.userDeleted existed in
// the enum but nothing used it), no Storage cleanup at all (profile photo,
// verification documents, portfolio images all orphaned forever), and no
// cleanup of verifications/{uid}, artisan_private/{uid}, favorites, or
// notifications. "Delete User" did not delete most of what a user is.
//
// Rewritten to be the single, authoritative, server-side deletion path.
// firestore.rules now denies client-side delete on users/{uid} and
// artisans/{uid} entirely — Admin SDK calls (this function) bypass rules
// regardless, so this is now the ONLY way an account can be removed. No
// partial, unaudited delete is possible from the client anymore.
//
// Deliberately does NOT touch: jobs, quotes, chat messages, payments,
// reviews, disputes, escrow_releases, admin_audit_logs. Those are the
// OTHER party's transaction/financial/reputation history too (a customer's
// job record with a since-deleted artisan, a payment ledger entry, a
// review) and must never be deleted just because one side's account was.
// They keep referencing the deleted uid; screens that look up a profile by
// uid already handle a missing document (safeDocStream returns null) and
// should render a "Deleted User" fallback rather than assume the uid
// always resolves.
exports.adminDeleteUser = onCall(async (request) => {
  if (!request.auth) {
    throw new Error('Sign in required.');
  }
  const adminDoc = await db.collection('admins').doc(request.auth.uid).get();
  if (!adminDoc.exists) {
    throw new Error('Admin privileges required.');
  }

  const uid = request.data?.uid;
  if (typeof uid !== 'string' || uid.length === 0) {
    throw new Error('uid is required.');
  }
  // An admin deleting their own account through this action is almost
  // certainly a mistake (wrong row selected) rather than intent — self-
  // deletion has no legitimate admin-tool use case and risks locking the
  // caller out mid-operation.
  if (uid === request.auth.uid) {
    throw new Error('You cannot delete your own admin account through this action.');
  }

  const [userSnap, artisanSnap] = await Promise.all([
    db.collection('users').doc(uid).get(),
    db.collection('artisans').doc(uid).get(),
  ]);
  const userData = userSnap.data();
  const wasArtisan = artisanSnap.exists;

  // Audit log FIRST, before any destructive action — a snapshot of what's
  // about to be deleted, written even if downstream steps partially fail,
  // so there is always a record that this was attempted and by whom.
  const auditRef = db.collection('admin_audit_logs').doc();
  await auditRef.set({
    id: auditRef.id,
    action: 'userDeleted',
    adminId: request.auth.uid,
    targetId: uid,
    targetType: 'user',
    timestamp: admin.firestore.Timestamp.now(),
    metadata: {
      name: userData?.name || null,
      email: userData?.email || null,
      wasArtisan,
    },
  });

  // 1. Firebase Auth — real deletion, not disable.
  try {
    await admin.auth().deleteUser(uid);
  } catch (err) {
    // already deleted / never existed in Auth (e.g. legacy Firestore-only
    // row) — not a failure from the caller's point of view.
    if (err.code !== 'auth/user-not-found') {
      throw err;
    }
  }

  // 2. Storage — profile photo, verification documents, portfolio images.
  // deleteFiles() on a prefix with no matching objects is a no-op, not an
  // error, so no existence check is needed first. Best-effort per prefix:
  // one failing must not abort Firestore cleanup below.
  const bucket = admin.storage().bucket();
  const storagePrefixes = [
    `users/${uid}/`,
    `verifications/${uid}/`,
    `artisan_portfolio/${uid}/`,
  ];
  for (const prefix of storagePrefixes) {
    try {
      await bucket.deleteFiles({ prefix });
    } catch (err) {
      console.error(`adminDeleteUser: Storage cleanup failed for prefix ${prefix}`, err.message);
    }
  }

  // 3. Firestore — the deleted account's own personal-data documents.
  const batch = db.batch();
  batch.delete(db.collection('users').doc(uid));
  if (wasArtisan) {
    batch.delete(db.collection('artisans').doc(uid));
  }
  batch.delete(db.collection('verifications').doc(uid));
  batch.delete(db.collection('artisan_private').doc(uid));
  await batch.commit();

  // Subcollections and fan-out references need individual queries — a
  // batch can't glob-delete by prefix.
  const [ownFavorites, portfolioProjects, ownNotifications, favoritedByOthers] = await Promise.all([
    db.collection('users').doc(uid).collection('favorites').get(),
    db.collection('portfolio_projects').where('artisanId', '==', uid).get(),
    db.collection('notifications').where('userId', '==', uid).get(),
    // Other customers' favorite entries pointing AT this artisan — a
    // collection-group query, since favorites live under
    // users/{otherUid}/favorites, not under this uid's own document tree.
    wasArtisan
      ? db.collectionGroup('favorites').where('artisanId', '==', uid).get()
      : Promise.resolve({ docs: [] }),
  ]);

  const cleanupDocs = [
    ...ownFavorites.docs,
    ...portfolioProjects.docs,
    ...ownNotifications.docs,
    ...favoritedByOthers.docs,
  ];
  // Firestore batches cap at 500 writes — chunk defensively even though
  // this volume is very unlikely for one user's fan-out.
  for (let i = 0; i < cleanupDocs.length; i += 450) {
    const chunk = db.batch();
    for (const doc of cleanupDocs.slice(i, i + 450)) {
      chunk.delete(doc.ref);
    }
    await chunk.commit();
  }

  return { success: true };
});
