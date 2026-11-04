/**
 * Stage 7.1 — chargebacks (F-1). LOCAL Firestore emulator only; Paystack is
 * a fake (design/REMEDIATION_STAGE7_1_REPORT_2026-11-04.md §3–4).
 */
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8090';
process.env.GCLOUD_PROJECT = 'handytrust-stage71-chargeback';
process.env.PAYSTACK_SECRET_KEY = 'sk_test_FAKE_STAGE71_UNIT_ONLY';

const { test, describe, beforeEach, after } = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const admin = require('firebase-admin');
const fns = require('../index.js');

const db = admin.firestore();
const PROJECT = process.env.GCLOUD_PROJECT;
const get = async (p) => (await db.doc(p).get()).data();
const DAY = 24 * 60 * 60 * 1000;
const alerts = async (type) => (await db.collection('admin_alerts').where('type', '==', type).get()).docs.map((d) => d.data());

let disputes; let transfers; let refundsCreated; let fetchFails;
function installFakes() {
  fns._setPaystackFakes({
    paystack: {
      createRefund: async () => { refundsCreated++; return { status: 'pending', id: `rf${refundsCreated}` }; },
      fetchRefund: async () => ({}),
      listRefunds: async () => [],
      fetchDispute: async (id) => {
        if (fetchFails) throw new Error('network down');
        if (!disputes[id]) throw Object.assign(new Error('not found'), { response: { status: 404 } });
        return disputes[id];
      },
    },
    transferHttp: { post: async () => { transfers++; return { data: { data: { status: 'pending', transfer_code: 'TRF' } } }; } },
  });
}

beforeEach(async () => {
  await fetch(`http://127.0.0.1:8090/emulator/v1/projects/${PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  disputes = {}; transfers = 0; refundsCreated = 0; fetchFails = false;
  installFakes();
});
after(() => fns._setPaystackFakes({}));

async function seedFunded({ jobStatus = 'escrowLocked', payStatus = 'escrowHeld', extraJob = {} } = {}) {
  await db.doc('users/art1').set({ accountStatus: 'active' });
  await db.doc('artisans/art1').set({ uid: 'art1' });
  await db.doc('artisan_private/art1').set({ accountNumber: '0123456789', bankName: 'Access Bank', accountName: 'A', paystackRecipientCode: 'RCP' });
  await db.doc('jobs/j1').set({ customerId: 'cust1', artisanId: 'art1', status: jobStatus, agreedAmount: 50000, ...extraJob });
  await db.doc('payments/ref1').set({
    jobId: 'j1', payerId: 'cust1', status: payStatus, amount: 50000, serviceAmount: 50000,
    amountKobo: 5250000, chargedAmountKobo: 5250000, paystackReference: 'ref1',
  });
}
const dispute = (status = 'awaiting-merchant-feedback', extra = {}) =>
  ({ id: 9001, status, resolution: null, refund_amount: 5250000, currency: 'NGN', transaction: { reference: 'ref1' }, dueAt: '2026-11-05T10:00:00Z', ...extra });
async function openChargeback(status) {
  disputes['9001'] = dispute(status);
  return fns._onDisputeWebhook('charge.dispute.create', dispute(status));
}

describe('Chargeback intake (webhook)', () => {
  test('create: case recorded, payment AND job held, admin alerted, artisan sees "on hold" — no money moves', async () => {
    await seedFunded();
    const r = await openChargeback();
    assert.deepEqual(r, { created: true, verified: true, matched: true });
    const cb = await get('chargebacks/9001');
    assert.equal(cb.status, 'open');
    assert.equal(cb.jobId, 'j1');
    assert.equal(cb.customerId, 'cust1');
    assert.equal(cb.payoutStateAtOpen, 'in_escrow');
    assert.equal((await get('payments/ref1')).chargebackHold, true);
    assert.equal((await get('payments/ref1')).status, 'escrowHeld'); // not confiscated
    assert.equal((await get('jobs/j1')).chargebackHold, true);
    assert.equal((await get('jobs/j1')).payoutStatus, 'on_hold');
    assert.equal((await alerts('chargeback_opened')).length, 1);
    assert.equal(transfers + refundsCreated, 0);
  });

  test('duplicate webhook is a no-op (one event, one financial record, one alert)', async () => {
    await seedFunded();
    await openChargeback();
    assert.deepEqual(await fns._onDisputeWebhook('charge.dispute.create', dispute()), { duplicate: true });
    assert.equal((await db.collection('chargebacks/9001/events').get()).size, 1);
    assert.equal((await db.collection('financial_events').where('type', '==', 'chargeback_create').get()).size, 1);
    assert.equal((await alerts('chargeback_opened')).length, 1);
  });

  test('remind events count up and re-surface the alert; status never regresses', async () => {
    await seedFunded();
    await openChargeback();
    await db.doc('admin_alerts/chargeback_open_9001').update({ resolved: true });
    disputes['9001'] = dispute('awaiting-bank-feedback', { updatedAt: 't2' });
    await fns._onDisputeWebhook('charge.dispute.remind', disputes['9001']);
    const cb = await get('chargebacks/9001');
    assert.equal(cb.remindCount, 1);
    assert.equal(cb.paystackStatus, 'awaiting-bank-feedback');
    assert.equal((await get('admin_alerts/chargeback_open_9001')).resolved, false);
  });

  test('out of order: resolve before create → case held (not released); a delayed create cannot reopen it', async () => {
    await seedFunded();
    disputes['9001'] = dispute('resolved', { resolution: 'declined' });
    await fns._onDisputeWebhook('charge.dispute.resolve', disputes['9001']);
    let cb = await get('chargebacks/9001');
    assert.equal(cb.status, 'paystack_resolved');
    assert.equal((await get('payments/ref1')).chargebackHold, true); // still held until an admin closes it
    fetchFails = true; // the late create can't be verified; its stale status must not win
    await fns._onDisputeWebhook('charge.dispute.create', dispute('awaiting-merchant-feedback'));
    cb = await get('chargebacks/9001');
    assert.equal(cb.paystackStatus, 'resolved');
    assert.equal(cb.status, 'paystack_resolved');
  });

  test('unverifiable (Paystack fetch fails): hold is still placed from the signed payload; admin told', async () => {
    await seedFunded();
    fetchFails = true;
    const r = await fns._onDisputeWebhook('charge.dispute.create', dispute());
    assert.equal(r.verified, false);
    assert.equal((await get('payments/ref1')).chargebackHold, true);
    assert.equal((await alerts('chargeback_unverified')).length, 1);
  });

  test('unmatched transaction reference: case recorded, admin alerted, nothing else touched', async () => {
    disputes['9002'] = { id: 9002, status: 'pending', transaction: { reference: 'nope' } };
    const r = await fns._onDisputeWebhook('charge.dispute.create', disputes['9002']);
    assert.equal(r.matched, false);
    assert.equal((await get('chargebacks/9002')).paymentId, null);
    assert.equal((await alerts('chargeback_unmatched')).length, 1);
  });

  test('fetched reference wins over a conflicting webhook reference (mismatch alerted)', async () => {
    await seedFunded();
    disputes['9001'] = dispute();
    await fns._onDisputeWebhook('charge.dispute.create', dispute('pending', { transaction: { reference: 'someone-else' } }));
    assert.equal((await get('chargebacks/9001')).reference, 'ref1');
    assert.equal((await alerts('chargeback_reference_mismatch')).length, 1);
  });

  test('missing dispute id is rejected safely', async () => {
    assert.deepEqual(await fns._onDisputeWebhook('charge.dispute.create', { status: 'pending' }), { ignored: 'no_dispute_id' });
    assert.equal((await db.collection('chargebacks').get()).size, 0);
  });
});

describe('Escrow and payout protection while a chargeback is open', () => {
  test('auto-release (14-day timer) is blocked', async () => {
    await seedFunded({ jobStatus: 'submitted', extraJob: { submittedAt: admin.firestore.Timestamp.fromMillis(Date.now() - 15 * DAY) } });
    await openChargeback();
    const r = await fns._releaseEscrow('j1', 'auto');
    assert.equal(r.skipped, 'payout_blocked');
    assert.equal(r.blockReason, 'chargeback_open');
    assert.equal((await db.doc('escrow_releases/j1').get()).exists, false);
    assert.equal((await get('jobs/j1')).status, 'submitted');
  });

  test('customer-confirmed payout is frozen — no transfer', async () => {
    await seedFunded({ jobStatus: 'completed' });
    await openChargeback();
    await db.doc('escrow_releases/j1').set({ jobId: 'j1', status: 'pending', requestedBy: 'cust1' });
    const r = await fns._processEscrowRelease(db.doc('escrow_releases/j1'), 'j1', { post: async () => { transfers++; } });
    assert.deepEqual(r, { frozen: 'chargeback_open' });
    assert.equal(transfers, 0);
    assert.equal((await get('payments/ref1')).status, 'escrowHeld');
    assert.equal((await get('escrow_releases/j1')).status, 'frozen');
  });

  test('chargeback arriving DURING payout processing (just before the final check) still stops the transfer', async () => {
    await seedFunded({ jobStatus: 'completed' });
    disputes['9001'] = dispute();
    await db.doc('escrow_releases/j1').set({ jobId: 'j1', status: 'pending', requestedBy: 'cust1' });
    const r = await fns._processEscrowRelease(db.doc('escrow_releases/j1'), 'j1', { post: async () => { transfers++; } }, {
      beforeFinalCheck: () => fns._onDisputeWebhook('charge.dispute.create', dispute()),
    });
    assert.deepEqual(r, { frozen: 'chargeback_open' });
    assert.equal(transfers, 0);
  });

  test('admin retry of the frozen payout cannot bypass the hold', async () => {
    await seedFunded({ jobStatus: 'completed' });
    await openChargeback();
    await db.doc('escrow_releases/j1').set({ jobId: 'j1', status: 'pending', requestedBy: 'cust1' });
    await fns._processEscrowRelease(db.doc('escrow_releases/j1'), 'j1', { post: async () => { transfers++; } });
    const r = await fns._retryPayout({ jobId: 'j1', adminId: 'adm', reason: 'try again' });
    assert.deepEqual(r, { frozen: 'chargeback_open' });
    assert.equal(transfers, 0);
  });

  test('admin dispute settlement (release / refund / split) is refused', async () => {
    await seedFunded({ jobStatus: 'disputed' });
    await db.doc('disputes/d1').set({ jobId: 'j1', status: 'open', raisedBy: 'cust1' });
    await openChargeback();
    for (const outcome of ['release', 'full_refund']) {
      await assert.rejects(
        fns._settleJob({ jobId: 'j1', kind: 'dispute', disputeId: 'd1', outcome, reason: 'Admin decision after review', adminId: 'adm' }),
        /chargeback_open/);
    }
    assert.equal((await db.doc('settlements/j1').get()).exists, false);
    assert.equal(transfers + refundsCreated, 0);
  });

  test('settlement created BEFORE the chargeback: its unexecuted payout leg and refund leg cannot run while it is open', async () => {
    await seedFunded({ jobStatus: 'disputed' });
    await db.doc('disputes/d1').set({ jobId: 'j1', status: 'open', raisedBy: 'cust1' });
    // Leave both legs unexecuted: artisan freeze stops the payout leg; Paystack rejects the first refund.
    await db.doc('artisans/art1').update({ payoutFrozen: true });
    let refundAttempts = 0;
    fns._setPaystackFakes({
      paystack: {
        createRefund: async () => { refundAttempts++; throw Object.assign(new Error('bad'), { response: { status: 400 } }); },
        fetchRefund: async () => ({}), listRefunds: async () => [],
        fetchDispute: async (id) => disputes[id],
      },
      transferHttp: { post: async () => { transfers++; return { data: { data: { status: 'pending' } } }; } },
    });
    await fns._settleJob({ jobId: 'j1', kind: 'dispute', disputeId: 'd1', outcome: 'split',
      artisanAmountNgn: 30000, refundAmountNgn: 22500, reason: 'Admin decision after review', adminId: 'adm' });
    assert.equal((await get('escrow_releases/j1')).status, 'frozen');
    assert.equal((await get('refunds/ref1')).status, 'failed');
    assert.equal(refundAttempts, 1);

    await openChargeback();
    await db.doc('artisans/art1').update({ payoutFrozen: false }); // the artisan freeze is lifted…
    assert.deepEqual(await fns._retryPayout({ jobId: 'j1', adminId: 'adm', reason: 'unfrozen' }), { frozen: 'chargeback_open' });
    assert.deepEqual(await fns._retryRefund({ refundId: 'ref1', adminId: 'adm', reason: 'retry' }), { held: 'chargeback_open' });
    assert.equal(transfers, 0);
    assert.equal(refundAttempts, 1); // …but neither leg moved money

    disputes['9001'] = dispute('resolved', { resolution: 'merchant-accepted' });
    await fns._closeChargeback({ chargebackId: '9001', outcome: 'customer_refunded', reason: 'Issuer refunded the customer', adminId: 'adm' });
    const st = await get('settlements/j1');
    assert.equal(st.payoutLeg.status, 'cancelled_chargeback');
    assert.equal(st.refundLeg.status, 'cancelled_chargeback');
    assert.equal((await get('refunds/ref1')).status, 'cancelled_chargeback');
    assert.equal((await get('payments/ref1')).status, 'chargedBack');
    assert.deepEqual(await fns._retryRefund({ refundId: 'ref1', adminId: 'adm', reason: 'again' }), { skipped: 'not_failed' });
  });

  test('refund of a non-funding charge is HELD (would double-refund the customer); resubmitted only after close', async () => {
    await seedFunded({ jobStatus: 'cancelled', payStatus: 'requiresRefund' });
    await openChargeback();
    const r = await fns._refundCharge({ reference: 'ref1', adminId: 'adm', reason: 'Late charge after cancel' });
    assert.deepEqual(r, { requested: true });
    assert.equal((await get('refunds/ref1')).status, 'held');
    assert.equal(refundsCreated, 0);
    assert.equal((await alerts('refund_held_chargeback')).length, 1);
    // still held → retry re-checks and holds again
    await fns._retryRefund({ refundId: 'ref1', adminId: 'adm', reason: 'retry' });
    assert.equal(refundsCreated, 0);
    disputes['9001'] = dispute('resolved', { resolution: 'declined' });
    await fns._closeChargeback({ chargebackId: '9001', outcome: 'merchant_won', reason: 'Bank ruled for merchant', adminId: 'adm' });
    await fns._retryRefund({ refundId: 'ref1', adminId: 'adm', reason: 'chargeback closed' });
    assert.equal(refundsCreated, 1);
  });

  test('after close (merchant won) the frozen payout stays frozen until an admin explicitly retries it — then pays once', async () => {
    await seedFunded({ jobStatus: 'completed' });
    await openChargeback();
    await db.doc('escrow_releases/j1').set({ jobId: 'j1', status: 'pending', requestedBy: 'cust1' });
    await fns._processEscrowRelease(db.doc('escrow_releases/j1'), 'j1', { post: async () => { transfers++; } });
    disputes['9001'] = dispute('resolved', { resolution: 'declined' });
    const c = await fns._closeChargeback({ chargebackId: '9001', outcome: 'merchant_won', reason: 'Bank ruled for merchant', adminId: 'adm' });
    assert.equal(c.closed, true);
    assert.equal(c.holdRemains, false);
    assert.equal(c.basis, 'merchant_won');
    assert.equal((await get('escrow_releases/j1')).status, 'frozen'); // nothing resumed automatically
    assert.equal(transfers, 0);
    const r = await fns._retryPayout({ jobId: 'j1', adminId: 'adm', reason: 'chargeback won' });
    assert.ok(r.transferred > 0);
    assert.equal(transfers, 1);
  });
});

describe('Chargeback after the payout started or finished', () => {
  test('already paid out: recorded as "after payout", high-priority alert, payment untouched', async () => {
    await seedFunded({ jobStatus: 'completed', payStatus: 'released' });
    await openChargeback();
    assert.equal((await get('chargebacks/9001')).payoutStateAtOpen, 'paid_out');
    assert.equal((await alerts('chargeback_after_payout')).length, 1);
    assert.equal((await get('payments/ref1')).status, 'released');
  });

  test('transfer in flight: if it fails, funds return to escrow and stay held; if it succeeds, admins are told', async () => {
    await seedFunded({ jobStatus: 'completed', payStatus: 'releasing' });
    await db.doc('escrow_releases/j1').set({ jobId: 'j1', status: 'processing', requestedBy: 'cust1', transferReference: 'j1', payoutAttempts: 1 });
    await openChargeback();
    assert.equal((await get('chargebacks/9001')).payoutStateAtOpen, 'payout_initiated');
    await fns._onTransferFailed('j1', 'paystack_transfer.failed');
    assert.equal((await get('payments/ref1')).status, 'escrowHeld');
    const r = await fns._retryPayout({ jobId: 'j1', adminId: 'adm', reason: 'retry' });
    assert.deepEqual(r, { frozen: 'chargeback_open' });

    // second scenario: the in-flight transfer succeeds
    await db.doc('payments/ref1').update({ status: 'releasing' });
    await db.doc('escrow_releases/j1').set({ jobId: 'j1', status: 'processing', transferReference: 'j1-p9' }, { merge: true });
    await fns._onTransferSucceeded('j1', 'j1-p9');
    assert.equal((await alerts('chargeback_payout_completed')).length, 1);
  });
});

describe('Admin close (the only way a hold is lifted)', () => {
  test('refused while Paystack has not resolved the dispute', async () => {
    await seedFunded();
    await openChargeback();
    await assert.rejects(fns._closeChargeback({ chargebackId: '9001', outcome: 'merchant_won', reason: 'Bank ruled for merchant', adminId: 'adm' }), /not resolved/);
    assert.equal((await get('payments/ref1')).chargebackHold, true);
  });

  test('refused when Paystack is unreachable (no close on stale data)', async () => {
    await seedFunded();
    await openChargeback();
    fetchFails = true;
    await assert.rejects(fns._closeChargeback({ chargebackId: '9001', outcome: 'customer_refunded', reason: 'Issuer refunded customer', adminId: 'adm' }), /Could not confirm/);
  });

  test('"merchant won" contradicting Paystack\'s "merchant-accepted" resolution is refused', async () => {
    await seedFunded();
    await openChargeback();
    disputes['9001'] = dispute('resolved', { resolution: 'merchant-accepted' });
    await assert.rejects(fns._closeChargeback({ chargebackId: '9001', outcome: 'merchant_won', reason: 'Bank ruled for merchant', adminId: 'adm' }), /accepted/);
  });

  test('customer refunded by the issuer: escrow funds marked chargedBack; nothing can pay or refund them again', async () => {
    await seedFunded({ jobStatus: 'completed' });
    await openChargeback();
    disputes['9001'] = dispute('resolved', { resolution: 'merchant-accepted' });
    await fns._closeChargeback({ chargebackId: '9001', outcome: 'customer_refunded', reason: 'Issuer refunded the customer', adminId: 'adm' });
    const pay = await get('payments/ref1');
    assert.equal(pay.status, 'chargedBack');
    assert.equal(pay.chargebackHold, false);
    await db.doc('escrow_releases/j1').set({ jobId: 'j1', status: 'pending', requestedBy: 'cust1' });
    const r = await fns._processEscrowRelease(db.doc('escrow_releases/j1'), 'j1', { post: async () => { transfers++; } });
    assert.equal(r.failed, 'no_verified_payment_on_record');
    assert.equal(transfers, 0);
    const log = (await db.collection('admin_audit_logs').where('action', '==', 'chargebackClosed').get()).docs[0].data();
    assert.equal(log.metadata.paymentStatusAfter, 'chargedBack');
    assert.equal((await get('admin_alerts/chargeback_closed_9001')).nextStep, 'cancel_or_close_job');
  });

  test('customer refunded after payout: payment keeps its status and is flagged as a platform loss', async () => {
    await seedFunded({ jobStatus: 'completed', payStatus: 'released' });
    await openChargeback();
    disputes['9001'] = dispute('resolved', { resolution: 'merchant-accepted' });
    await fns._closeChargeback({ chargebackId: '9001', outcome: 'customer_refunded', reason: 'Issuer refunded the customer', adminId: 'adm' });
    const pay = await get('payments/ref1');
    assert.equal(pay.status, 'released');
    assert.equal(pay.chargebackLoss, true);
    assert.equal((await get('admin_alerts/chargeback_closed_9001')).nextStep, 'loss_absorbed_review_artisan_for_fraud_if_warranted');
  });

  test('close is idempotent; a conflicting second decision is refused; later events are logged, not applied', async () => {
    await seedFunded();
    await openChargeback();
    disputes['9001'] = dispute('resolved', { resolution: 'declined' });
    const args = { chargebackId: '9001', outcome: 'merchant_won', reason: 'Bank ruled for merchant', adminId: 'adm' };
    await fns._closeChargeback(args);
    assert.deepEqual(await fns._closeChargeback(args), { duplicate: true });
    await assert.rejects(fns._closeChargeback({ ...args, outcome: 'customer_refunded' }), /different outcome/);
    await fns._onDisputeWebhook('charge.dispute.remind', dispute('pending', { updatedAt: 'late' }));
    assert.equal((await get('chargebacks/9001')).status, 'closed');
    assert.equal((await get('payments/ref1')).chargebackHold, false);
    assert.equal((await alerts('chargeback_event_after_close')).length, 1);
  });

  test('two chargebacks on one payment: closing one keeps the hold', async () => {
    await seedFunded();
    await openChargeback();
    disputes['9003'] = dispute('pending', { id: 9003 });
    await fns._onDisputeWebhook('charge.dispute.create', disputes['9003']);
    disputes['9001'] = dispute('resolved', { resolution: 'declined' });
    const r = await fns._closeChargeback({ chargebackId: '9001', outcome: 'merchant_won', reason: 'Bank ruled for merchant', adminId: 'adm' });
    assert.equal(r.holdRemains, true);
    assert.equal((await get('payments/ref1')).chargebackHold, true);
    assert.equal((await get('jobs/j1')).chargebackHold, true);
  });
});

describe('Webhook HTTP handler (signature + routing)', () => {
  function call(body, { sign = true, tamper = false } = {}) {
    const raw = Buffer.from(JSON.stringify(body));
    const sig = crypto.createHmac('sha512', process.env.PAYSTACK_SECRET_KEY).update(raw).digest('hex');
    const req = { headers: sign ? { 'x-paystack-signature': tamper ? sig.replace(/^./, sig[0] === 'a' ? 'b' : 'a') : sig } : {}, rawBody: raw, body };
    return new Promise((resolve) => {
      const res = { statusCode: 200, status(c) { this.statusCode = c; return this; }, send(m) { resolve({ code: this.statusCode, body: m }); } };
      fns.paystackWebhook(req, res);
    });
  }

  test('valid signature → handled; forged or missing signature → 400 and nothing recorded', async () => {
    await seedFunded();
    disputes['9001'] = dispute();
    assert.equal((await call({ event: 'charge.dispute.create', data: dispute() }, { tamper: true })).code, 400);
    assert.equal((await call({ event: 'charge.dispute.create', data: dispute() }, { sign: false })).code, 400);
    assert.equal((await db.collection('chargebacks').get()).size, 0);
    assert.equal((await call({ event: 'charge.dispute.create', data: dispute() })).code, 200);
    assert.equal((await get('chargebacks/9001')).status, 'open');
  });

  test('unsupported charge.dispute.* event → acknowledged and surfaced to admins, no state change', async () => {
    const r = await call({ event: 'charge.dispute.mystery', data: { id: 77 } });
    assert.equal(r.code, 200);
    assert.equal((await alerts('chargeback_event_unsupported')).length, 1);
    assert.equal((await db.collection('chargebacks').get()).size, 0);
  });
});

describe('Pure helpers', () => {
  test('Paystack dispute status only moves forward; unknown statuses are ignored', () => {
    assert.equal(fns._nextDisputeStatus(null, 'pending'), 'pending');
    assert.equal(fns._nextDisputeStatus('resolved', 'awaiting-merchant-feedback'), 'resolved');
    assert.equal(fns._nextDisputeStatus('pending', 'resolved'), 'resolved');
    assert.equal(fns._nextDisputeStatus('pending', 'weird-new-status'), 'pending');
  });

  test('reference is read from either documented shape', () => {
    assert.equal(fns._disputeReference({ transaction: { reference: 'a' } }), 'a');
    assert.equal(fns._disputeReference({ transaction_reference: 'b' }), 'b');
    assert.equal(fns._disputeReference({}), null);
  });

  test('constant-time signature comparison', () => {
    assert.equal(fns._signaturesMatch('abcd', 'abcd'), true);
    assert.equal(fns._signaturesMatch('abcd', 'abce'), false);
    assert.equal(fns._signaturesMatch('abcd', 'abc'), false);
    assert.equal(fns._signaturesMatch('abcd', undefined), false);
  });
});
