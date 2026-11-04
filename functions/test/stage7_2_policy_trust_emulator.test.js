/**
 * Stage 7.2 — chargeback accounting policies and the trust-score response
 * time (design/REMEDIATION_STAGE7_2_REPORT_2026-11-04.md). LOCAL Firestore
 * emulator only; Paystack is a fake.
 */
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8090';
process.env.GCLOUD_PROJECT = 'handytrust-stage72-test';

const { test, describe, beforeEach, after } = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
const fns = require('../index.js');

const db = admin.firestore();
const PROJECT = process.env.GCLOUD_PROJECT;
const ts = (ms) => admin.firestore.Timestamp.fromMillis(ms);
const get = async (p) => (await db.doc(p).get()).data();
const MIN = 60 * 1000;
const HOUR = 60 * MIN;
const DAY = 24 * HOUR;
const alerts = async (type) => (await db.collection('admin_alerts').where('type', '==', type).get()).docs.map((d) => d.data());

// ₦50,000 service + 5 % fee = ₦52,500 charged → 5,250,000 kobo (fee 250,000).
const SERVICE = 5000000;
const CHARGED = 5250000;

let disputes; let transfers; let refunds;
beforeEach(async () => {
  await fetch(`http://127.0.0.1:8090/emulator/v1/projects/${PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  disputes = {}; transfers = []; refunds = [];
  fns._setPaystackFakes({
    paystack: {
      createRefund: async ({ amountKobo }) => { refunds.push(amountKobo); return { status: 'pending', id: `rf${refunds.length}` }; },
      fetchRefund: async () => ({}), listRefunds: async () => [],
      fetchDispute: async (id) => { if (!disputes[id]) throw new Error('nf'); return disputes[id]; },
    },
    transferHttp: { post: async (_url, body) => { transfers.push(body.amount); return { data: { data: { status: 'pending', transfer_code: 'T' } } }; } },
  });
});
after(() => fns._setPaystackFakes({}));

async function seed({ jobId = 'j1', artisan = 'art1', jobStatus = 'completed', payStatus = 'escrowHeld', extraJob = {} } = {}) {
  await db.doc(`users/${artisan}`).set({ accountStatus: 'active' }, { merge: true });
  await db.doc(`artisans/${artisan}`).set({ uid: artisan }, { merge: true });
  await db.doc(`artisan_private/${artisan}`).set({ accountNumber: '0123456789', bankName: 'Access Bank', accountName: 'A', paystackRecipientCode: 'RCP' });
  await db.doc(`jobs/${jobId}`).set({ customerId: 'cust1', artisanId: artisan, status: jobStatus, agreedAmount: 50000, ...extraJob });
  await db.doc(`payments/ref_${jobId}`).set({
    jobId, payerId: 'cust1', status: payStatus, amount: 50000, serviceAmount: 50000,
    amountKobo: CHARGED, chargedAmountKobo: CHARGED, paystackReference: `ref_${jobId}`,
  });
}
const dispute = (id, ref, extra = {}) => ({ id: Number(id), status: 'awaiting-merchant-feedback', resolution: null,
  refund_amount: null, currency: 'NGN', transaction: { reference: ref }, ...extra });
async function openCb(id = '9001', ref = 'ref_j1') {
  disputes[id] = dispute(id, ref);
  await fns._onDisputeWebhook('charge.dispute.create', disputes[id]);
}
async function resolveCb(id, ref, extra) {
  disputes[id] = dispute(id, ref, { status: 'resolved', ...extra });
}
const close = (id, outcome) => fns._closeChargeback({ chargebackId: id, outcome, reason: 'Paystack resolution reviewed by finance', adminId: 'adm' });
const enablePartial = () => db.doc('config/platform').set({ partialChargebackAccountingVerified: true });
const releasePending = (jobId = 'j1') => db.doc(`escrow_releases/${jobId}`).set({ jobId, status: 'pending', requestedBy: 'cust1' });
const pay = (jobId = 'j1') => fns._processEscrowRelease(db.doc(`escrow_releases/${jobId}`), jobId, { post: async (_u, b) => { transfers.push(b.amount); return { data: { data: { status: 'pending' } } }; } });

describe('Chargeback accounting (pure)', () => {
  const payment = { chargedAmountKobo: CHARGED, serviceAmount: 50000, amount: 50000 };
  const fetched = { status: 'resolved', resolution: 'merchant-accepted', refund_amount: 200000, currency: 'NGN' };

  test('verification switch OFF: a partial amount is ignored — full conservative reversal', () => {
    const a = fns._chargebackAccounting({ payment, fetched, outcome: 'customer_refunded', partialVerified: false });
    assert.deepEqual([a.basis, a.reversedKobo, a.partial, a.undisputedKobo], ['assumed_full', CHARGED, false, 0]);
  });

  test('switch ON + resolved + merchant-accepted + valid kobo amount → disputed and undisputed balances', () => {
    const a = fns._chargebackAccounting({ payment, fetched, outcome: 'customer_refunded', partialVerified: true });
    assert.deepEqual([a.basis, a.reversedKobo, a.undisputedKobo, a.partial, a.shortfallKobo], ['paystack_verified', 200000, CHARGED - 200000, true, 0]);
  });

  test('anything not established falls back to the full hold', () => {
    for (const bad of [
      { ...fetched, resolution: 'declined' }, { ...fetched, status: 'pending' }, { ...fetched, refund_amount: 2000.5 },
      { ...fetched, refund_amount: '200000' }, { ...fetched, refund_amount: 0 }, { ...fetched, refund_amount: CHARGED + 1 },
      { ...fetched, currency: 'USD' }, { ...fetched, refund_amount: null },
    ]) {
      const a = fns._chargebackAccounting({ payment, fetched: bad, outcome: 'customer_refunded', partialVerified: true });
      assert.equal(a.basis, 'assumed_full', JSON.stringify(bad));
      assert.equal(a.reversedKobo, CHARGED);
    }
  });

  test('a partial above the 5 % fee leaves an artisan-entitlement shortfall', () => {
    const a = fns._chargebackAccounting({ payment, fetched: { ...fetched, refund_amount: 1000000 }, outcome: 'customer_refunded', partialVerified: true });
    assert.equal(a.undisputedKobo, 4250000);
    assert.equal(a.shortfallKobo, SERVICE - 4250000);
  });

  test('merchant won: nothing reversed; unknown payment amount is flagged', () => {
    assert.equal(fns._chargebackAccounting({ payment, fetched, outcome: 'merchant_won', partialVerified: true }).reversedKobo, 0);
    assert.equal(fns._chargebackAccounting({ payment: {}, fetched, outcome: 'customer_refunded', partialVerified: true }).basis, 'amount_unknown');
  });

  test('settlement validation uses the undisputed balance (5 % fee and entitlement rules unchanged)', () => {
    const v = (o) => fns._validateSettlement({ serviceKobo: SERVICE, totalKobo: CHARGED, reason: 'Admin decision after review', ...o });
    assert.equal(v({ outcome: 'release', artisanKobo: SERVICE, refundKobo: 0 }), null); // no chargeback: as before
    assert.equal(v({ outcome: 'release', artisanKobo: SERVICE, refundKobo: 0, availableKobo: 4250000 }), 'release_exceeds_undisputed_balance');
    assert.equal(v({ outcome: 'full_refund', artisanKobo: 0, refundKobo: 4250000, availableKobo: 4250000 }), null);
    assert.equal(v({ outcome: 'full_refund', artisanKobo: 0, refundKobo: CHARGED, availableKobo: 4250000 }), 'full_refund_must_return_full_charge');
    assert.equal(v({ outcome: 'split', artisanKobo: 4000000, refundKobo: 300000, availableKobo: 4250000 }), 'split_exceeds_amount_paid');
    assert.equal(v({ outcome: 'split', artisanKobo: SERVICE + 1, refundKobo: 1, availableKobo: CHARGED }), 'artisan_amount_exceeds_service_price');
  });
});

describe('Partial-accounting switch cannot be bypassed (Stage 7.3)', () => {
  test('only a literal boolean true enables it; truthy look-alikes and a missing config stay OFF', () => {
    assert.equal(fns._normalizePlatformConfig(null).partialChargebackAccountingVerified, false);
    for (const v of ['true', 1, 'yes', {}, [], 'TRUE', null, undefined]) {
      assert.equal(fns._normalizePlatformConfig({ partialChargebackAccountingVerified: v }).partialChargebackAccountingVerified, false, String(v));
    }
    assert.equal(fns._normalizePlatformConfig({ partialChargebackAccountingVerified: true }).partialChargebackAccountingVerified, true);
  });

  test('end to end: config holding the string "true" still produces the conservative full reversal', async () => {
    await db.doc('config/platform').set({ partialChargebackAccountingVerified: 'true' });
    await seed();
    await openCb();
    await resolveCb('9001', 'ref_j1', { resolution: 'merchant-accepted', refund_amount: 200000 });
    const r = await close('9001', 'customer_refunded');
    assert.deepEqual([r.basis, r.partial], ['assumed_full', false]);
    assert.equal((await get('payments/ref_j1')).status, 'chargedBack');
  });
});

describe('Chargeback AFTER payout (decision 2: HandyTrust absorbs)', () => {
  test('loss recorded against HandyTrust; transfer not reversed; artisan\'s next payout is NOT reduced', async () => {
    await seed({ payStatus: 'released' });
    await openCb();
    await resolveCb('9001', 'ref_j1', { resolution: 'merchant-accepted', refund_amount: CHARGED });
    await close('9001', 'customer_refunded');
    const loss = await get('platform_losses/9001');
    assert.equal(loss.absorbedBy, 'handytrust');
    assert.equal(loss.artisanDeduction, false);
    assert.equal(loss.recoveryStatus, 'not_pursued');
    assert.equal(loss.amountKobo, CHARGED);
    assert.equal(loss.amountBasis, 'assumed_full');
    assert.equal((await db.collection('financial_events').where('type', '==', 'platform_loss_recorded').get()).size, 1);
    const p = await get('payments/ref_j1');
    assert.equal(p.status, 'released'); // completed transfer untouched
    assert.equal(p.chargebackLoss, true);
    assert.equal(transfers.length, 0);
    // Evidence and history preserved.
    assert.equal((await db.collection('chargebacks/9001/events').get()).size, 1);
    assert.equal((await get('chargebacks/9001')).history.at(-1).action, 'closed');

    // The same artisan's next job is paid in full.
    await seed({ jobId: 'j2', payStatus: 'escrowHeld' });
    await releasePending('j2');
    await pay('j2');
    assert.deepEqual(transfers, [SERVICE]);
  });

  test('with verified partial data, the loss is the verified reversed amount', async () => {
    await enablePartial();
    await seed({ payStatus: 'released' });
    await openCb();
    await resolveCb('9001', 'ref_j1', { resolution: 'merchant-accepted', refund_amount: 700000 });
    await close('9001', 'customer_refunded');
    const loss = await get('platform_losses/9001');
    assert.deepEqual([loss.amountKobo, loss.amountBasis], [700000, 'paystack_verified']);
  });

  test('fraud investigation is recorded (no money moves); a fraud suspension then freezes the artisan\'s other payouts', async () => {
    await seed({ payStatus: 'released' });
    await openCb();
    const r = await fns._setChargebackInvestigation({ chargebackId: '9001', status: 'fraud_confirmed', notes: 'Same card used on 4 accounts', adminId: 'adm' });
    assert.equal(r.artisanId, 'art1');
    assert.equal((await get('chargebacks/9001')).investigation.status, 'fraud_confirmed');
    assert.equal((await alerts('chargeback_fraud_confirmed')).length, 1);
    assert.equal((await db.collection('admin_audit_logs').where('action', '==', 'chargebackInvestigation').get()).size, 1);
    assert.equal(transfers.length + refunds.length, 0);
    await assert.rejects(fns._setChargebackInvestigation({ chargebackId: '9001', status: 'guilty', notes: 'xxxxxxxxxxxx', adminId: 'adm' }), /invalid_status/);
    // Suspension is the existing admin action (not automatic):
    await db.doc('users/art1').set({ accountStatus: 'suspended', suspensionType: 'fraud' }, { merge: true });
    await seed({ jobId: 'j3', payStatus: 'escrowHeld' });
    await db.doc('users/art1').set({ accountStatus: 'suspended', suspensionType: 'fraud' }, { merge: true });
    await releasePending('j3');
    assert.deepEqual(await pay('j3'), { frozen: 'artisan_suspended_freeze' });
    assert.equal(transfers.length, 0);
  });
});

describe('Partial chargebacks while funds are in escrow', () => {
  test('switch OFF (default): conservative full hold — the whole held payment is charged back', async () => {
    await seed();
    await openCb();
    await resolveCb('9001', 'ref_j1', { resolution: 'merchant-accepted', refund_amount: 200000 });
    const r = await close('9001', 'customer_refunded');
    assert.equal(r.basis, 'assumed_full');
    assert.equal((await get('payments/ref_j1')).status, 'chargedBack');
  });

  test('switch ON, reversal within the fee: artisan still receives the full entitlement (after an explicit retry)', async () => {
    await enablePartial();
    await seed();
    await openCb();
    await releasePending();
    assert.deepEqual(await pay(), { frozen: 'chargeback_open' });
    await resolveCb('9001', 'ref_j1', { resolution: 'merchant-accepted', refund_amount: 200000 });
    const r = await close('9001', 'customer_refunded');
    assert.deepEqual([r.basis, r.partial, r.nextStep], ['paystack_verified', true, 'retry_payout_undisputed_balance_covers_entitlement']);
    const p = await get('payments/ref_j1');
    assert.deepEqual([p.status, p.chargebackRefundedKobo, p.chargebackHold], ['escrowHeld', 200000, false]);
    assert.equal(transfers.length, 0); // nothing automatic
    await fns._retryPayout({ jobId: 'j1', adminId: 'adm', reason: 'partial chargeback closed' });
    assert.deepEqual(transfers, [SERVICE]);
    const cb = await get('chargebacks/9001');
    assert.equal(cb.accounting.undisputedKobo, CHARGED - 200000);
  });

  test('switch ON, reversal above the fee: payout frozen (shortfall); settlement uses the undisputed balance', async () => {
    await enablePartial();
    await seed({ jobStatus: 'disputed' });
    await db.doc('disputes/d1').set({ jobId: 'j1', status: 'open', raisedBy: 'cust1' });
    await openCb();
    await resolveCb('9001', 'ref_j1', { resolution: 'merchant-accepted', refund_amount: 1000000 });
    const r = await close('9001', 'customer_refunded');
    assert.equal(r.nextStep, 'settle_undisputed_balance_artisan_entitlement_not_covered');
    await assert.rejects(fns._settleJob({ jobId: 'j1', kind: 'dispute', disputeId: 'd1', outcome: 'release', reason: 'Admin decision after review', adminId: 'adm' }),
      /release_exceeds_undisputed_balance/);
    await fns._settleJob({ jobId: 'j1', kind: 'dispute', disputeId: 'd1', outcome: 'split', artisanAmountNgn: 40000, refundAmountNgn: 2500,
      reason: 'Admin decision after review', adminId: 'adm' });
    const st = await get('settlements/j1');
    assert.deepEqual([st.availableKobo, st.chargebackRefundedKobo, st.platformRetainedKobo], [4250000, 1000000, 0]);
    assert.deepEqual(transfers, [4000000]);
    assert.deepEqual(refunds, [250000]);
  });

  test('switch ON, shortfall: an automatic/retried payout of the full entitlement is frozen, never paid from other funds', async () => {
    await enablePartial();
    await seed();
    await openCb();
    await releasePending();
    await pay(); // frozen by the open chargeback
    await resolveCb('9001', 'ref_j1', { resolution: 'merchant-accepted', refund_amount: 1000000 });
    await close('9001', 'customer_refunded');
    assert.equal((await get('payments/ref_j1')).chargebackHold, false);
    assert.deepEqual(await fns._retryPayout({ jobId: 'j1', adminId: 'adm', reason: 'retry' }), { frozen: 'chargeback_partial_shortfall' });
    assert.equal(transfers.length, 0);
    assert.equal((await get('payments/ref_j1')).status, 'escrowHeld');
  });

  test('switch ON: a refund still owed shrinks by what the issuer returned (no double refund)', async () => {
    await enablePartial();
    await seed({ jobStatus: 'cancelled', payStatus: 'requiresRefund' });
    await openCb('9001', 'ref_j1');
    await fns._refundCharge({ reference: 'ref_j1', adminId: 'adm', reason: 'Late charge after cancel' });
    assert.equal((await get('refunds/ref_j1')).status, 'held');
    await resolveCb('9001', 'ref_j1', { resolution: 'merchant-accepted', refund_amount: 3000000 });
    await close('9001', 'customer_refunded');
    assert.equal((await get('refunds/ref_j1')).amountKobo, CHARGED - 3000000);
    await fns._retryRefund({ refundId: 'ref_j1', adminId: 'adm', reason: 'chargeback closed' });
    assert.deepEqual(refunds, [CHARGED - 3000000]);
  });

  test('switch ON: a partial during an executing settlement is refused; case and hold stay', async () => {
    await enablePartial();
    await seed({ payStatus: 'settling' });
    await openCb();
    await resolveCb('9001', 'ref_j1', { resolution: 'merchant-accepted', refund_amount: 200000 });
    await assert.rejects(close('9001', 'customer_refunded'), /partial_chargeback_during_settlement/);
    assert.equal((await get('chargebacks/9001')).status, 'open');
    assert.equal((await get('payments/ref_j1')).chargebackHold, true);
  });
});

describe('Concurrency and duplicates', () => {
  test('two admins close the same chargeback at once: one close, one loss record, one financial entry', async () => {
    await seed({ payStatus: 'released' });
    await openCb();
    await resolveCb('9001', 'ref_j1', { resolution: 'merchant-accepted', refund_amount: CHARGED });
    const results = await Promise.allSettled([close('9001', 'customer_refunded'), close('9001', 'customer_refunded')]);
    assert.equal(results.filter((x) => x.status === 'fulfilled').length, 2);
    assert.equal(results.filter((x) => x.value?.duplicate).length, 1);
    assert.equal((await db.collection('financial_events').where('type', '==', 'platform_loss_recorded').get()).size, 1);
    assert.equal((await db.collection('admin_audit_logs').where('action', '==', 'chargebackClosed').get()).size, 1);
  });

  test('concurrent settlement attempts after a partial chargeback: exactly one settlement, one payout, one refund', async () => {
    await enablePartial();
    await seed({ jobStatus: 'disputed' });
    await db.doc('disputes/d1').set({ jobId: 'j1', status: 'open', raisedBy: 'cust1' });
    await openCb();
    await resolveCb('9001', 'ref_j1', { resolution: 'merchant-accepted', refund_amount: 1000000 });
    await close('9001', 'customer_refunded');
    const args = { jobId: 'j1', kind: 'dispute', disputeId: 'd1', outcome: 'split', artisanAmountNgn: 40000, refundAmountNgn: 2500, reason: 'Admin decision after review', adminId: 'adm' };
    const other = { ...args, outcome: 'full_refund' };
    const out = await Promise.allSettled([fns._settleJob(args), fns._settleJob(args), fns._settleJob(other)]);
    assert.ok(out.filter((x) => x.status === 'fulfilled').length >= 1);
    assert.equal(transfers.length + refunds.length <= 2, true);
    assert.ok(transfers.length <= 1 && refunds.length <= 1, `transfers=${transfers} refunds=${refunds}`);
    assert.equal((await db.collection('settlements').get()).size, 1);
  });

  test('duplicate and late dispute events after a partial close change nothing', async () => {
    await enablePartial();
    await seed();
    await openCb();
    await resolveCb('9001', 'ref_j1', { resolution: 'merchant-accepted', refund_amount: 200000 });
    await close('9001', 'customer_refunded');
    const before = await get('payments/ref_j1');
    await fns._onDisputeWebhook('charge.dispute.resolve', disputes['9001']);
    await fns._onDisputeWebhook('charge.dispute.resolve', disputes['9001']);
    assert.deepEqual(await get('payments/ref_j1'), before);
    assert.equal((await get('chargebacks/9001')).status, 'closed');
  });
});

describe('Response time — pure rules (approved definition)', () => {
  const now = Date.UTC(2026, 10, 4);
  const rec = (agoMs, minutes) => ({ respondedAtMs: now - agoMs, minutes });

  test('minutes: confirmation/decline are actual minutes; expired is 1,440; clamped to [0, 1440]', () => {
    assert.equal(fns._responseMinutes('confirmed', 0, 30 * MIN), 30);
    assert.equal(fns._responseMinutes('declined', 0, 90.04 * MIN), 90);
    assert.equal(fns._responseMinutes('expired', 0, 5 * MIN), 1440);
    assert.equal(fns._responseMinutes('confirmed', 10 * MIN, 0), 0);
    assert.equal(fns._responseMinutes('confirmed', 0, 3 * DAY), 1440);
  });

  test('fewer than 3 qualifying responses → neutral 30; 3 → median', () => {
    assert.deepEqual(fns._medianResponseMinutes([rec(MIN, 5), rec(2 * MIN, 600)], now), { minutes: 30, sampleSize: 2 });
    assert.deepEqual(fns._medianResponseMinutes([rec(MIN, 5), rec(2 * MIN, 600), rec(3 * MIN, 20)], now), { minutes: 20, sampleSize: 3 });
  });

  test('even count → mean of the two middle values', () => {
    assert.equal(fns._medianResponseMinutes([rec(1, 10), rec(2, 20), rec(3, 30), rec(4, 1440)], now).minutes, 25);
  });

  test('90-day window boundary: exactly 90 days counts, 90 days + 1 ms does not; future records ignored', () => {
    const base = [rec(MIN, 10), rec(2 * MIN, 10)];
    assert.equal(fns._medianResponseMinutes([...base, rec(90 * DAY, 1440)], now).sampleSize, 3);
    assert.equal(fns._medianResponseMinutes([...base, rec(90 * DAY + 1, 1440)], now).sampleSize, 2);
    assert.equal(fns._medianResponseMinutes([...base, rec(-MIN, 1440)], now).sampleSize, 2);
  });

  test('only the latest 20 count', () => {
    const recent = Array.from({ length: 20 }, (_, i) => rec((i + 1) * MIN, 10));
    const old = Array.from({ length: 10 }, (_, i) => rec((30 + i) * DAY, 1440));
    assert.deepEqual(fns._medianResponseMinutes([...old, ...recent], now), { minutes: 10, sampleSize: 20 });
  });
});

describe('Response time — immutable booking response records', () => {
  const T0 = Date.now() - 2 * HOUR;
  const matched = (extra = {}) => ({ customerId: 'cust1', artisanId: 'art9', status: 'matched', bookingStatus: 'awaitingArtisan',
    bookingRequestedAt: ts(T0), matchedAt: ts(T0), ...extra });
  const recId = (jobId) => `${jobId}_art9_${T0}`;
  beforeEach(async () => { await db.doc('artisans/art9').set({ uid: 'art9', rating: 4.5, totalRatings: 10, completedJobs: 20, verificationStatus: 'id_verified' }); });

  test('request record, then confirmation: minutes from server-stamped times; first response is immutable', async () => {
    await db.doc('jobs/b1').set(matched());
    await fns._recordBookingRequest('b1', matched(), ts(T0));
    assert.equal((await get(`booking_responses/${recId('b1')}`)).responseType, null);
    await fns._recordBookingResponse('b1', matched(), { type: 'confirmed', respondedAt: ts(T0 + 30 * MIN), source: 'test' });
    await fns._recordBookingResponse('b1', matched(), { type: 'confirmed', respondedAt: ts(T0 + 999 * MIN), source: 'dup' });
    await fns._recordBookingRequest('b1', matched(), ts(T0)); // late duplicate request event
    const r = await get(`booking_responses/${recId('b1')}`);
    assert.deepEqual([r.responseType, r.responseMinutes, r.qualifying, r.source], ['confirmed', 30, true, 'test']);
  });

  test('decline: actual decline time, recorded in the reopen transaction before the booking fields are cleared', async () => {
    await db.doc('jobs/b2').set(matched());
    await fns._reopenJob('b2', { reason: 'artisan_declined_booking', expectStatuses: ['matched'], requireArtisanId: 'art9', nowMs: T0 + 45 * MIN });
    assert.equal((await get('jobs/b2')).bookingRequestedAt, undefined); // job fields gone…
    const r = await get(`booking_responses/${recId('b2')}`);   // …history kept
    assert.deepEqual([r.responseType, r.responseMinutes], ['declined', 45]);
  });

  test('expiry (hourly sweep): counted as 1,440 minutes', async () => {
    await db.doc('jobs/b3').set(matched());
    await fns._expireMarketplaceDeadlines(T0 + 25 * HOUR);
    const r = await get(`booking_responses/${recId('b3')}`);
    assert.deepEqual([r.responseType, r.responseMinutes], ['expired', 1440]);
  });

  test('withdrawal AFTER confirming keeps the original confirmation time (whether or not the trigger recorded it)', async () => {
    const confirmed = matched({ status: 'inChat', bookingStatus: 'confirmed', bookingConfirmedAt: ts(T0 + 10 * MIN) });
    await db.doc('jobs/b4').set(confirmed);
    await fns._reopenJob('b4', { reason: 'artisan_withdrew', expectStatuses: ['inChat'], requireArtisanId: 'art9', nowMs: T0 + 5 * HOUR });
    let r = await get(`booking_responses/${recId('b4')}`);
    assert.deepEqual([r.responseType, r.responseMinutes], ['confirmed', 10]);

    await db.doc('jobs/b5').set(confirmed);
    await fns._recordBookingResponse('b5', confirmed, { type: 'confirmed', respondedAt: ts(T0 + 10 * MIN), source: 'trigger' });
    await fns._reopenJob('b5', { reason: 'artisan_withdrew', expectStatuses: ['inChat'], requireArtisanId: 'art9', nowMs: T0 + 5 * HOUR });
    r = await get(`booking_responses/${recId('b5')}`);
    assert.deepEqual([r.responseType, r.responseMinutes, r.source], ['confirmed', 10, 'trigger']);
  });

  test('a request the customer cancels before any answer is kept but does not qualify', async () => {
    await fns._recordBookingResponse('b6', matched(), { type: 'cancelled_by_customer', respondedAt: ts(T0 + MIN), source: 'test' });
    const r = await get(`booking_responses/${recId('b6')}`);
    assert.deepEqual([r.qualifying, r.responseMinutes], [false, null]);
  });
});

describe('Response time — score recalculation and history', () => {
  beforeEach(async () => { await db.doc('artisans/art7').set({ uid: 'art7', rating: 5, totalRatings: 3, completedJobs: 10, verificationStatus: 'id_verified' }); });
  async function addRecord(id, respondedAtMs, minutes, qualifying = true) {
    await db.doc(`booking_responses/${id}`).set({ artisanId: 'art7', qualifying, respondedAt: ts(respondedAtMs), responseMinutes: minutes, responseType: 'confirmed' });
  }

  test('artisan responseTimeMinutes and trustScore follow the median; < 3 stays neutral', async () => {
    const now = Date.now();
    await addRecord('r1', now - HOUR, 5);
    await addRecord('r2', now - 2 * HOUR, 300);
    let out = await fns._recomputeResponseTime('art7', now);
    assert.deepEqual([out.minutes, out.sampleSize], [30, 2]);
    await addRecord('r3', now - 3 * HOUR, 12);
    await addRecord('x', now - 4 * HOUR, 1, false); // non-qualifying ignored
    out = await fns._recomputeResponseTime('art7', now);
    const a = await get('artisans/art7');
    assert.deepEqual([a.responseTimeMinutes, a.responseTimeSampleSize], [12, 3]);
    assert.equal(a.trustScore, fns._computeTrustScore({ ...a }));
  });

  test('historical records age out of the 90-day window via the hourly sweep (back to neutral)', async () => {
    const now = Date.now();
    for (let i = 0; i < 3; i++) await addRecord(`h${i}`, now - 89 * DAY, 1440);
    await fns._recomputeResponseTime('art7', now);
    assert.equal((await get('artisans/art7')).responseTimeMinutes, 1440);
    const later = now + 2 * DAY; // the records are now 91 days old
    const s = await fns._expireMarketplaceDeadlines(later);
    assert.ok(s.responseTimesRefreshed >= 1);
    const a = await get('artisans/art7');
    assert.deepEqual([a.responseTimeMinutes, a.responseTimeSampleSize], [30, 0]);
  });

  test('an artisan with no records (pre-Stage-7.2 history) keeps the neutral default', async () => {
    const out = await fns._recomputeResponseTime('art7', Date.now());
    assert.deepEqual([out.minutes, out.sampleSize], [30, 0]);
  });
});
