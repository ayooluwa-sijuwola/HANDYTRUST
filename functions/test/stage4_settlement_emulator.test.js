/**
 * Stage 4 remediation — refunds, dispute/cancellation settlements, fraud
 * payout freezes, concurrency (design/REMEDIATION_STAGE4_REPORT_2026-11-03.md).
 *
 * LOCAL Firestore emulator only (Admin SDK, as in production). Paystack is
 * NEVER called: refunds and transfers go to injected fakes.
 *   firebase emulators:exec --only firestore "cd functions && npm test"
 */
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8090';
process.env.GCLOUD_PROJECT = 'handytrust-stage4-test';

const { test, describe, beforeEach, after } = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
const fns = require('../index.js');

const db = admin.firestore();
const PROJECT = process.env.GCLOUD_PROJECT;
const DAY = 24 * 60 * 60 * 1000;
const REASON = 'Evidence reviewed: photos show the work was not started.';

// ── Fakes ────────────────────────────────────────────────────────────────
let refundCalls; let transferCalls; let refundBehaviour; let fetchStatus; let listResult;
function installFakes() {
  refundCalls = []; transferCalls = [];
  refundBehaviour = () => ({ id: `rf_${refundCalls.length}`, status: 'pending' });
  fetchStatus = null; listResult = [];
  fns._setPaystackFakes({
    paystack: {
      createRefund: async (args) => { refundCalls.push(args); return refundBehaviour(args); },
      fetchRefund: async (id) => ({ id, status: fetchStatus }),
      listRefunds: async () => listResult,
    },
    transferHttp: {
      post: async (url, body) => {
        transferCalls.push(body);
        return { data: { data: { transfer_code: `TRF_${transferCalls.length}`, status: 'pending' } } };
      },
    },
  });
}
after(() => fns._setPaystackFakes({}));

async function clearAll() {
  await fetch(`http://127.0.0.1:8090/emulator/v1/projects/${PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
}
beforeEach(async () => { await clearAll(); installFakes(); });

const ts = (ms) => admin.firestore.Timestamp.fromMillis(ms);
const get = async (p) => (await db.doc(p).get()).data();
const count = async (col, field, val) => (await db.collection(col).where(field, '==', val).get()).size;
const SERVICE = 5_000_000; const TOTAL = 5_250_000;

async function seedFunded(job = {}, { artisanUser = {} } = {}) {
  await db.doc('users/cust1').set({ uid: 'cust1', accountStatus: 'active' });
  await db.doc('users/art1').set({ uid: 'art1', accountStatus: 'active', ...artisanUser });
  await db.doc('artisans/art1').set({ uid: 'art1', approvalStatus: 'approved' });
  await db.doc('artisan_private/art1').set({
    accountNumber: '0123456789', bankName: 'Access Bank', accountName: 'Art One', paystackRecipientCode: 'RCP_1',
  });
  await db.doc('jobs/job1').set({
    customerId: 'cust1', artisanId: 'art1', status: 'escrowLocked', agreedAmount: 50000,
    paymentReference: 'pay_1', updateVersion: 7, ...job,
  });
  await db.doc('payments/pay_1').set({
    id: 'pay_1', jobId: 'job1', payerId: 'cust1', artisanId: 'art1', paystackReference: 'pay_1',
    amount: 50000, serviceAmount: 50000, platformFee: 2500, totalCharged: 52500, amountKobo: TOTAL,
    currency: 'NGN', status: 'escrowHeld',
  });
}
async function seedDispute() {
  await seedFunded({ status: 'disputed' });
  await db.doc('disputes/d1').set({ id: 'd1', jobId: 'job1', raisedBy: 'cust1', againstUserId: 'art1', status: 'open' });
}
const cancelReq = { status: 'escrowLocked', cancellationRequestStatus: 'pending', cancellationRequestedBy: 'cust1' };

// ═════════════════════════════════════════════════════════════════════════
describe('Full refund (D2: eligible cancellation before work → 100% incl. fee)', () => {
  test('refund is NOT marked refunded until Paystack reports processed', async () => {
    await seedFunded(cancelReq);
    await fns._settleJob({ jobId: 'job1', kind: 'cancellation', outcome: 'full_refund', reason: REASON, adminId: 'adm' });
    assert.deepEqual(refundCalls, [{ transaction: 'pay_1', amountKobo: TOTAL }]);
    const job = await get('jobs/job1');
    assert.equal(job.status, 'cancelled');
    assert.equal(job.cancellationRequestStatus, 'approved');
    assert.equal(job.refundStatus, 'submitted');          // Paystack said 'pending'
    assert.equal((await get('payments/pay_1')).status, 'settling');
    assert.equal((await get('refunds/pay_1')).status, 'submitted');
    assert.equal(transferCalls.length, 0);

    fetchStatus = 'processed';
    await fns._onRefundWebhook({ transaction_reference: 'pay_1', status: 'processed', amount: String(TOTAL) });
    assert.equal((await get('refunds/pay_1')).status, 'processed');
    assert.equal((await get('payments/pay_1')).status, 'refunded');
    assert.equal((await get('settlements/job1')).status, 'completed');
    assert.equal((await get('jobs/job1')).refundStatus, 'processed');
  });

  test('duplicate and out-of-order refund webhooks never regress a processed refund', async () => {
    await seedFunded(cancelReq);
    await fns._settleJob({ jobId: 'job1', kind: 'cancellation', outcome: 'full_refund', reason: REASON, adminId: 'adm' });
    fetchStatus = 'processed';
    await fns._onRefundWebhook({ transaction_reference: 'pay_1', status: 'processed' });
    const events1 = await count('financial_events', 'refundId', 'pay_1');
    await fns._onRefundWebhook({ transaction_reference: 'pay_1', status: 'processed' });
    fetchStatus = 'processing';
    await fns._onRefundWebhook({ transaction_reference: 'pay_1', status: 'processing' });
    assert.equal((await get('refunds/pay_1')).status, 'processed');
    assert.equal(await count('financial_events', 'refundId', 'pay_1'), events1);
  });

  test('needs-attention is surfaced to admins, not treated as success', async () => {
    await seedFunded(cancelReq);
    await fns._settleJob({ jobId: 'job1', kind: 'cancellation', outcome: 'full_refund', reason: REASON, adminId: 'adm' });
    fetchStatus = 'needs-attention';
    await fns._onRefundWebhook({ transaction_reference: 'pay_1', status: 'needs-attention' });
    assert.equal((await get('refunds/pay_1')).status, 'needs_attention');
    assert.equal(await count('admin_alerts', 'type', 'refund_needs_attention'), 1);
    assert.equal((await get('payments/pay_1')).status, 'settling');
  });
});

describe('Partial refund / split settlement (D2 partial work, D3)', () => {
  test('artisan gets the agreed part, customer the refund part, remainder retained and recorded', async () => {
    await seedFunded({ ...cancelReq, status: 'inProgress' });
    await fns._settleJob({
      jobId: 'job1', kind: 'cancellation', outcome: 'split', artisanAmountNgn: 20000, refundAmountNgn: 30000,
      reason: REASON, adminId: 'adm',
    });
    assert.equal(transferCalls.length, 1);
    assert.equal(transferCalls[0].amount, 2_000_000);
    assert.deepEqual(refundCalls, [{ transaction: 'pay_1', amountKobo: 3_000_000 }]);
    const st = await get('settlements/job1');
    assert.equal(st.platformRetainedKobo, TOTAL - 2_000_000 - 3_000_000);
    assert.equal(st.status, 'executing');

    await fns._onTransferSucceeded('job1', 'job1');
    assert.equal((await get('settlements/job1')).status, 'executing'); // refund leg still open
    fetchStatus = 'processed';
    await fns._onRefundWebhook({ transaction_reference: 'pay_1', status: 'processed' });
    assert.equal((await get('settlements/job1')).status, 'completed');
    assert.equal((await get('payments/pay_1')).status, 'settled');
  });

  test('a paid cancellation can never be settled as a straight release (D2)', async () => {
    await seedFunded(cancelReq);
    await assert.rejects(
      fns._settleJob({ jobId: 'job1', kind: 'cancellation', outcome: 'release', reason: REASON, adminId: 'adm' }),
      /cancellation_cannot_release/);
    assert.equal(transferCalls.length, 0);
  });

  test('invalid splits are refused before any money moves', async () => {
    await seedFunded({ ...cancelReq, status: 'inProgress' });
    const settle = (a, r, reason = REASON) => fns._settleJob({
      jobId: 'job1', kind: 'cancellation', outcome: 'split', artisanAmountNgn: a, refundAmountNgn: r, reason, adminId: 'adm',
    });
    await assert.rejects(settle(50001, 1), /artisan_amount_exceeds_service_price/);
    await assert.rejects(settle(30000, 22501), /split_exceeds_amount_paid/);
    await assert.rejects(settle(0, 1000), /split_requires_both_parts/);
    await assert.rejects(settle(20000, 30000, 'short'), /reason_required/);
    assert.equal(refundCalls.length + transferCalls.length, 0);
    assert.equal((await get('payments/pay_1')).status, 'escrowHeld');
  });
});

describe('Failed and retried refunds', () => {
  test('Paystack-reported failure → failed + alert; admin retry → processed', async () => {
    await seedFunded(cancelReq);
    await fns._settleJob({ jobId: 'job1', kind: 'cancellation', outcome: 'full_refund', reason: REASON, adminId: 'adm' });
    fetchStatus = 'failed';
    await fns._onRefundWebhook({ transaction_reference: 'pay_1', status: 'failed' });
    assert.equal((await get('refunds/pay_1')).status, 'failed');
    assert.equal(await count('admin_alerts', 'type', 'refund_failed'), 1);
    assert.equal((await get('payments/pay_1')).status, 'settling');  // not refunded

    refundBehaviour = () => ({ id: 'rf_retry', status: 'processed' });
    await fns._retryRefund({ refundId: 'pay_1', adminId: 'adm', reason: 'retry after failure' });
    assert.equal(refundCalls.length, 2);
    const r = await get('refunds/pay_1');
    assert.equal(r.status, 'processed');
    assert.equal(r.attempts, 2);
    assert.equal(r.attemptHistory.length, 1);
    assert.equal((await get('payments/pay_1')).status, 'refunded');
  });

  test('retry is refused unless Paystack actually reported failure', async () => {
    await seedFunded(cancelReq);
    await fns._settleJob({ jobId: 'job1', kind: 'cancellation', outcome: 'full_refund', reason: REASON, adminId: 'adm' });
    assert.deepEqual(await fns._retryRefund({ refundId: 'pay_1', adminId: 'adm' }), { skipped: 'not_failed' });
    assert.equal(refundCalls.length, 1);
  });

  test('Paystack 4xx rejection → failed immediately (nothing was created)', async () => {
    await seedFunded(cancelReq);
    refundBehaviour = () => { const e = new Error('bad'); e.response = { status: 400, data: { message: 'Transaction has been fully reversed' } }; throw e; };
    await fns._settleJob({ jobId: 'job1', kind: 'cancellation', outcome: 'full_refund', reason: REASON, adminId: 'adm' });
    const r = await get('refunds/pay_1');
    assert.equal(r.status, 'failed');
    assert.match(r.failureReason, /paystack_rejected_400/);
  });

  test('network error → submit_unknown (never resubmitted blindly); reconciliation finds it at Paystack', async () => {
    await seedFunded(cancelReq);
    refundBehaviour = () => { throw new Error('ETIMEDOUT'); };
    await fns._settleJob({ jobId: 'job1', kind: 'cancellation', outcome: 'full_refund', reason: REASON, adminId: 'adm' });
    assert.equal((await get('refunds/pay_1')).status, 'submit_unknown');
    assert.deepEqual(await fns._retryRefund({ refundId: 'pay_1', adminId: 'adm' }), { skipped: 'not_failed' });
    listResult = [{ id: 'rf_found', amount: String(TOTAL), status: 'processed' }];
    await fns._reconcileRefunds(Date.now() + 60 * 60 * 1000);
    assert.equal((await get('refunds/pay_1')).status, 'processed');
    assert.equal(refundCalls.length, 1);
  });

  test('unknown submission with nothing at Paystack after 24 h → failed (then retryable)', async () => {
    await seedFunded(cancelReq);
    refundBehaviour = () => { throw new Error('ECONNRESET'); };
    await fns._settleJob({ jobId: 'job1', kind: 'cancellation', outcome: 'full_refund', reason: REASON, adminId: 'adm' });
    listResult = [];
    await fns._reconcileRefunds(Date.now() + 2 * 60 * 60 * 1000);
    assert.equal((await get('refunds/pay_1')).status, 'submit_unknown');  // too early to conclude
    await fns._reconcileRefunds(Date.now() + 25 * 60 * 60 * 1000);
    assert.equal((await get('refunds/pay_1')).status, 'failed');
  });
});

describe('Dispute outcomes move real money (HT-007, D3)', () => {
  test('release → artisan paid the service price, dispute + job resolved, no refund', async () => {
    await seedDispute();
    await fns._settleJob({ jobId: 'job1', kind: 'dispute', disputeId: 'd1', outcome: 'release', reason: REASON, adminId: 'adm' });
    assert.equal(transferCalls.length, 1);
    assert.equal(transferCalls[0].amount, SERVICE);
    assert.equal(refundCalls.length, 0);
    assert.equal((await get('jobs/job1')).status, 'resolved');
    assert.equal((await get('disputes/d1')).status, 'resolved');
    await fns._onTransferSucceeded('job1', 'job1');
    assert.equal((await get('payments/pay_1')).status, 'released');
  });

  test('full refund → customer gets everything they paid', async () => {
    await seedDispute();
    await fns._settleJob({ jobId: 'job1', kind: 'dispute', disputeId: 'd1', outcome: 'full_refund', reason: REASON, adminId: 'adm' });
    assert.deepEqual(refundCalls, [{ transaction: 'pay_1', amountKobo: TOTAL }]);
    assert.equal(transferCalls.length, 0);
  });

  test('split → both legs; settlement completes only when both are confirmed', async () => {
    await seedDispute();
    await fns._settleJob({
      jobId: 'job1', kind: 'dispute', disputeId: 'd1', outcome: 'split', artisanAmountNgn: 25000, refundAmountNgn: 27500,
      reason: REASON, adminId: 'adm',
    });
    assert.equal(transferCalls[0].amount, 2_500_000);
    assert.equal(refundCalls[0].amountKobo, 2_750_000);
    fetchStatus = 'processed';
    await fns._onRefundWebhook({ transaction_reference: 'pay_1', status: 'processed' });
    assert.equal((await get('settlements/job1')).status, 'executing');
    await fns._onTransferSucceeded('job1', 'job1');
    assert.equal((await get('settlements/job1')).status, 'completed');
    assert.equal((await get('payments/pay_1')).status, 'settled');
  });

  test('audit trail: admin log, job audit entry and financial events are written', async () => {
    await seedDispute();
    await fns._settleJob({ jobId: 'job1', kind: 'dispute', disputeId: 'd1', outcome: 'release', reason: REASON, adminId: 'adm' });
    assert.equal(await count('admin_audit_logs', 'action', 'disputeSettled'), 1);
    assert.equal((await db.collection('jobs/job1/auditLogs').get()).size, 1);
    assert.ok(await count('financial_events', 'jobId', 'job1') >= 2);
  });
});

describe('Fraud freeze — auto-release and payouts (critical requirement)', () => {
  async function seedSubmitted(artisanUser) {
    await seedFunded({ status: 'submitted', submittedAt: ts(Date.now() - 15 * DAY) }, { artisanUser });
  }

  test('fraud suspension BEFORE auto-release → no release, funds stay, admin alerted', async () => {
    await seedSubmitted({ accountStatus: 'suspended', suspensionType: 'fraud' });
    const out = await fns._releaseEscrow('job1', 'test');
    assert.equal(out.blockReason, 'artisan_suspended_freeze');
    assert.equal((await get('jobs/job1')).status, 'submitted');
    assert.equal((await db.doc('escrow_releases/job1').get()).exists, false);
    assert.equal((await get('payments/pay_1')).status, 'escrowHeld');
    assert.equal(await count('admin_alerts', 'type', 'autorelease_blocked'), 1);
  });

  test('unclassified (legacy) suspension also fails closed', async () => {
    await seedSubmitted({ accountStatus: 'suspended' });
    assert.equal((await fns._releaseEscrow('job1', 'test')).blockReason, 'artisan_suspended_freeze');
  });

  test('administrative suspension does NOT freeze existing-job payouts (D9)', async () => {
    await seedSubmitted({ accountStatus: 'suspended', suspensionType: 'administrative' });
    await fns._releaseEscrow('job1', 'test');
    assert.equal((await get('jobs/job1')).status, 'completed');
    await fns._processEscrowRelease(db.doc('escrow_releases/job1'), 'job1', { post: async (u, b) => { transferCalls.push(b); return { data: { data: { status: 'pending' } } }; } });
    assert.equal(transferCalls.length, 1);
  });

  async function seedConfirmedRelease(artisanUser = {}) {
    await seedFunded({ status: 'completed' }, { artisanUser });
    await db.doc('escrow_releases/job1').set({ jobId: 'job1', status: 'pending', requestedBy: 'cust1' });
  }
  const fakeHttp = () => ({ post: async (u, b) => { transferCalls.push(b); return { data: { data: { transfer_code: 'T', status: 'pending' } } }; } });

  test('fraud suspension before a customer-confirmed payout → frozen, no transfer', async () => {
    await seedConfirmedRelease({ accountStatus: 'suspended', suspensionType: 'fraud' });
    const out = await fns._processEscrowRelease(db.doc('escrow_releases/job1'), 'job1', fakeHttp());
    assert.equal(out.frozen, 'artisan_suspended_freeze');
    assert.equal(transferCalls.length, 0);
    assert.equal((await get('escrow_releases/job1')).status, 'frozen');
    assert.equal((await get('payments/pay_1')).status, 'escrowHeld');
    assert.equal(await count('admin_alerts', 'type', 'payout_frozen'), 1);
  });

  test('fraud suspension applied DURING payout processing → frozen at the final check', async () => {
    await seedConfirmedRelease();
    const out = await fns._processEscrowRelease(db.doc('escrow_releases/job1'), 'job1', fakeHttp(), {
      beforeFinalCheck: () => db.doc('users/art1').update({ accountStatus: 'suspended', suspensionType: 'security' }),
    });
    assert.equal(out.frozen, 'artisan_suspended_freeze');
    assert.equal(transferCalls.length, 0);
  });

  test('admin payout freeze on the artisan or the job also blocks', async () => {
    await seedConfirmedRelease();
    await fns._setPayoutFreeze({ targetType: 'job', targetId: 'job1', frozen: true, reason: 'Chargeback investigation', adminId: 'adm' });
    assert.equal((await fns._processEscrowRelease(db.doc('escrow_releases/job1'), 'job1', fakeHttp())).frozen, 'job_payout_frozen');
  });

  test('frozen settlement payouts are blocked too (fraud freeze beats an admin decision)', async () => {
    await seedDispute();
    await db.doc('users/art1').update({ accountStatus: 'suspended', suspensionType: 'fraud' });
    await fns._settleJob({ jobId: 'job1', kind: 'dispute', disputeId: 'd1', outcome: 'release', reason: REASON, adminId: 'adm' });
    assert.equal(transferCalls.length, 0);
    assert.equal((await get('escrow_releases/job1')).status, 'frozen');
  });

  test('retry while still frozen stays frozen; after lifting the freeze it pays once with a new reference', async () => {
    await seedConfirmedRelease({ accountStatus: 'suspended', suspensionType: 'fraud' });
    await fns._processEscrowRelease(db.doc('escrow_releases/job1'), 'job1', fakeHttp());
    fns._setPaystackFakes({ transferHttp: fakeHttp() });
    assert.equal((await fns._retryPayout({ jobId: 'job1', adminId: 'adm', reason: 'retry' })).frozen, 'artisan_suspended_freeze');
    await db.doc('users/art1').update({ accountStatus: 'active', suspensionType: admin.firestore.FieldValue.delete() });
    await fns._retryPayout({ jobId: 'job1', adminId: 'adm', reason: 'cleared after review' });
    assert.equal(transferCalls.length, 1);
    assert.equal(transferCalls[0].reference, 'job1-p3');
    assert.equal(transferCalls[0].amount, SERVICE);
  });
});

describe('Duplicate admin actions and concurrency', () => {
  test('the same settlement twice → one refund call; a different decision → refused', async () => {
    await seedFunded(cancelReq);
    const args = { jobId: 'job1', kind: 'cancellation', outcome: 'full_refund', reason: REASON, adminId: 'adm' };
    await fns._settleJob(args);
    assert.deepEqual(await fns._settleJob(args), { duplicate: true });
    assert.equal(refundCalls.length, 1);
    await assert.rejects(fns._settleJob({ ...args, outcome: 'release' }), /already been settled/);
  });

  test('two concurrent, different settlements → exactly one wins', async () => {
    await seedDispute();
    const results = await Promise.allSettled([
      fns._settleJob({ jobId: 'job1', kind: 'dispute', disputeId: 'd1', outcome: 'release', reason: REASON, adminId: 'a1' }),
      fns._settleJob({ jobId: 'job1', kind: 'dispute', disputeId: 'd1', outcome: 'full_refund', reason: REASON, adminId: 'a2' }),
    ]);
    assert.equal(results.filter((r) => r.status === 'fulfilled').length, 1);
    assert.equal(transferCalls.length + refundCalls.length, 1);
  });

  test('a refund settlement landing while a payout is being processed → the payout aborts, money moves once', async () => {
    await seedFunded({ status: 'completed' });
    await db.doc('escrow_releases/job1').set({ jobId: 'job1', status: 'pending', requestedBy: 'cust1' });
    const out = await fns._processEscrowRelease(db.doc('escrow_releases/job1'), 'job1', {
      post: async (u, b) => { transferCalls.push(b); return { data: { data: { status: 'pending' } } }; },
    }, {
      beforeFinalCheck: async () => {
        // An admin settles a dispute on the same funds at that instant.
        await db.doc('jobs/job1').update({ status: 'disputed' });
        await db.doc('disputes/d1').set({ id: 'd1', jobId: 'job1', status: 'open' });
        await db.doc('escrow_releases/job1').update({ status: 'failed' }); // lets the settlement supersede it
        await fns._settleJob({ jobId: 'job1', kind: 'dispute', disputeId: 'd1', outcome: 'full_refund', reason: REASON, adminId: 'adm' });
      },
    });
    assert.ok(out.failed === 'superseded_by_settlement' || out.frozen);
    assert.equal(transferCalls.length, 0);
    assert.equal(refundCalls.length, 1);
  });

  test('once a payout has claimed the funds, a refund settlement is refused', async () => {
    await seedFunded({ status: 'disputed' });
    await db.doc('disputes/d1').set({ id: 'd1', jobId: 'job1', status: 'open' });
    await db.doc('payments/pay_1').update({ status: 'releasing' });
    await assert.rejects(
      fns._settleJob({ jobId: 'job1', kind: 'dispute', disputeId: 'd1', outcome: 'full_refund', reason: REASON, adminId: 'adm' }),
      /No funds are held/);
    assert.equal(refundCalls.length, 0);
  });
});

describe('Transfers, charge refunds, declines', () => {
  test('transfer failure webhook → release failed, funds claim returned, admin can retry', async () => {
    await seedFunded({ status: 'completed' });
    await db.doc('escrow_releases/job1').set({ jobId: 'job1', status: 'pending', requestedBy: 'cust1' });
    await fns._processEscrowRelease(db.doc('escrow_releases/job1'), 'job1', {
      post: async (u, b) => { transferCalls.push(b); return { data: { data: { status: 'pending' } } }; },
    });
    assert.equal((await get('payments/pay_1')).status, 'releasing');
    await fns._onTransferFailed('job1', 'paystack_transfer.failed');
    assert.equal((await get('payments/pay_1')).status, 'escrowHeld');
    assert.equal((await get('escrow_releases/job1')).status, 'failed');
    fns._setPaystackFakes({ transferHttp: { post: async (u, b) => { transferCalls.push(b); return { data: { data: { status: 'pending' } } }; } } });
    await fns._retryPayout({ jobId: 'job1', adminId: 'adm', reason: 'bank fixed' });
    assert.equal(transferCalls.length, 2);
    assert.equal(transferCalls[1].reference, 'job1-p2');
  });

  test('a stale success for an older attempt is ignored; the duplicate success is a no-op', async () => {
    await seedFunded({ status: 'completed' });
    await db.doc('escrow_releases/job1').set({ jobId: 'job1', status: 'processing', transferReference: 'job1-p2' });
    assert.equal((await fns._onTransferSucceeded('job1', 'job1')).staleAttempt, true);
    await db.doc('payments/pay_1').update({ status: 'releasing' });
    await fns._onTransferSucceeded('job1', 'job1-p2');
    assert.equal((await fns._onTransferSucceeded('job1', 'job1-p2')).duplicate, true);
    assert.equal(await count('notifications', 'userId', 'art1'), 1);
  });

  test('migration: success for a pre-Stage-4 transfer (payment never claimed) still marks it released', async () => {
    await seedFunded({ status: 'completed' });
    await db.doc('escrow_releases/job1').set({ jobId: 'job1', status: 'processing', paystackTransferCode: 'OLD' });
    await fns._onTransferSucceeded('job1', 'job1');
    assert.equal((await get('payments/pay_1')).status, 'released');
    await db.doc('jobs/job1').update({ status: 'disputed' });
    await db.doc('disputes/d1').set({ id: 'd1', jobId: 'job1', status: 'open' });
    await assert.rejects(
      fns._settleJob({ jobId: 'job1', kind: 'dispute', disputeId: 'd1', outcome: 'full_refund', reason: REASON, adminId: 'adm' }),
      /No funds are held/);
  });

  test('refund of a captured charge that must not fund a job (Stage 3 queue)', async () => {
    await db.doc('payments/pay_x').set({
      id: 'pay_x', jobId: 'job1', payerId: 'cust1', paystackReference: 'pay_x', amount: 50000,
      amountKobo: TOTAL, chargedAmountKobo: 100, status: 'requiresRefund',
    });
    await fns._refundCharge({ reference: 'pay_x', adminId: 'adm', reason: 'Underpaid charge, refund in full.' });
    assert.deepEqual(refundCalls, [{ transaction: 'pay_x', amountKobo: 100 }]); // what was actually taken
    assert.equal((await get('payments/pay_x')).status, 'refundPending');
    assert.deepEqual(await fns._refundCharge({ reference: 'pay_x', adminId: 'adm', reason: 'Underpaid charge, refund in full.' }), { duplicate: true });
    fetchStatus = 'processed';
    await fns._onRefundWebhook({ transaction_reference: 'pay_x', status: 'processed' });
    assert.equal((await get('payments/pay_x')).status, 'refunded');
  });

  test('declining a cancellation request keeps escrow untouched and is idempotent', async () => {
    await seedFunded(cancelReq);
    await fns._declineCancellationRequest({ jobId: 'job1', adminId: 'adm', reason: 'Work is progressing as agreed.' });
    assert.deepEqual(await fns._declineCancellationRequest({ jobId: 'job1', adminId: 'adm', reason: 'Work is progressing as agreed.' }), { duplicate: true });
    const job = await get('jobs/job1');
    assert.equal(job.cancellationRequestStatus, 'declined');
    assert.equal(job.status, 'escrowLocked');
    assert.equal((await get('payments/pay_1')).status, 'escrowHeld');
    assert.equal(refundCalls.length + transferCalls.length, 0);
  });
});

describe('Admin callables require an admin', () => {
  const callables = ['adminResolveDispute', 'adminResolveCancellation', 'adminRefundCharge', 'adminRetryRefund', 'adminRetryPayout', 'adminSetPayoutFreeze'];
  test('unauthenticated and non-admin callers are refused', async () => {
    for (const name of callables) {
      await assert.rejects(fns[name].run({ data: {} }), /Sign in required/, name);
      await assert.rejects(fns[name].run({ auth: { uid: 'cust1' }, data: {} }), /Admin privileges required/, name);
    }
  });

  test('an admin call reaches the settlement engine', async () => {
    await db.doc('admins/adm').set({ grantedAt: 1 });
    await seedFunded(cancelReq);
    const out = await fns.adminResolveCancellation.run({
      auth: { uid: 'adm' }, data: { jobId: 'job1', decision: 'full_refund', reason: REASON },
    });
    assert.deepEqual(out, { settled: true });
    assert.equal(refundCalls.length, 1);
  });
});
