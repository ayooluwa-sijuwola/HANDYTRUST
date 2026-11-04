/**
 * Stage 3 remediation — end-to-end payment/escrow behaviour against the
 * LOCAL Firestore emulator (Admin SDK, as in production). Paystack is never
 * called: verification and transfers are injected fakes.
 *
 * Requires the Firestore emulator on 127.0.0.1:8090, e.g.:
 *   firebase emulators:exec --only firestore "cd functions && npm test"
 */
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8090';
process.env.GCLOUD_PROJECT = 'handytrust-stage3-test';

const { test, describe, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
const fns = require('../index.js');

const db = admin.firestore();
const PROJECT = process.env.GCLOUD_PROJECT;
const H = 60 * 60 * 1000;
const DAY = 24 * H;

async function clearAll() {
  await fetch(`http://127.0.0.1:8090/emulator/v1/projects/${PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
}
beforeEach(clearAll);

const ts = (ms) => admin.firestore.Timestamp.fromMillis(ms);
const get = async (path) => (await db.doc(path).get()).data();
const count = async (col, field, val) => (await db.collection(col).where(field, '==', val).get()).size;

async function seedPayable({ job = {}, payment = {}, ref = 'pay_1' } = {}) {
  await db.doc('jobs/job1').set({
    customerId: 'cust1', artisanId: 'art1', status: 'paymentPending', agreedAmount: 50000,
    agreementStatus: 'confirmed', pendingPaymentReference: ref, updateVersion: 5, ...job,
  });
  await db.doc(`payments/${ref}`).set({
    id: ref, jobId: 'job1', payerId: 'cust1', artisanId: 'art1',
    amount: 50000, serviceAmount: 50000, platformFee: 2500, totalCharged: 52500, amountKobo: 5_250_000,
    currency: 'NGN', status: 'pending', paystackReference: ref, createdAt: ts(Date.now() - 2 * H), ...payment,
  });
}
const charge = (o = {}) => ({
  status: 'success', reference: 'pay_1', amount: 5_250_000, currency: 'NGN', fees: 88750,
  channel: 'card', authorization: { country_code: 'NG' }, metadata: { jobId: 'job1' }, ...o,
});

describe('_lockEscrow (webhook / verifyPayment path)', () => {
  test('exact charge locks escrow and records Paystack facts', async () => {
    await seedPayable();
    assert.equal(await fns._lockEscrow('job1', 'pay_1', charge()), 'lock');
    const job = await get('jobs/job1');
    assert.equal(job.status, 'escrowLocked');
    assert.equal(job.paymentReference, 'pay_1');
    assert.equal(job.pendingPaymentReference, undefined);
    const pay = await get('payments/pay_1');
    assert.equal(pay.status, 'escrowHeld');
    assert.equal(pay.paystackFeesKobo, 88750);
    assert.equal(pay.cardCountry, 'NG');
  });

  test('duplicate webhook delivery is a no-op', async () => {
    await seedPayable();
    await fns._lockEscrow('job1', 'pay_1', charge());
    assert.equal(await fns._lockEscrow('job1', 'pay_1', charge()), 'already_locked');
    await db.doc('jobs/job1').update({ status: 'inProgress' });
    assert.equal(await fns._lockEscrow('job1', 'pay_1', charge()), 'already_recorded');
    assert.equal((await get('jobs/job1')).status, 'inProgress');
  });

  test('underpayment does NOT lock; flagged for refund once, even if redelivered', async () => {
    await seedPayable();
    assert.equal(await fns._lockEscrow('job1', 'pay_1', charge({ amount: 100 })), 'requires_refund');
    assert.equal((await get('jobs/job1')).status, 'paymentPending');
    assert.equal((await get('payments/pay_1')).status, 'requiresRefund');
    assert.equal(await fns._lockEscrow('job1', 'pay_1', charge({ amount: 100 })), 'already_flagged_for_refund');
    assert.equal(await count('admin_alerts', 'type', 'charge_requires_refund'), 1);
  });

  test('late payment after cancellation: recorded for refund, job stays cancelled', async () => {
    await seedPayable({ job: { status: 'cancelled' } });
    await fns._abandonPaymentsForCancelledJob('job1');
    assert.equal((await get('payments/pay_1')).abandonReason, 'job_cancelled');
    assert.equal(await fns._lockEscrow('job1', 'pay_1', charge()), 'requires_refund');
    assert.equal((await get('jobs/job1')).status, 'cancelled');
    assert.equal((await get('payments/pay_1')).refundReason, 'paid_after_cancellation');
  });

  test('second charge after the job is funded by another reference → refund, no double lock', async () => {
    await seedPayable();
    await fns._lockEscrow('job1', 'pay_1', charge());
    await db.doc('payments/pay_2').set({
      id: 'pay_2', jobId: 'job1', payerId: 'cust1', amount: 50000, amountKobo: 5_250_000,
      status: 'abandoned', abandonReason: 'superseded_by_retry', paystackReference: 'pay_2',
    });
    assert.equal(await fns._lockEscrow('job1', 'pay_2', charge({ reference: 'pay_2' })), 'requires_refund');
    assert.equal((await get('jobs/job1')).paymentReference, 'pay_1');
  });

  test('charge with no payment record → orphan_charges + alert', async () => {
    await seedPayable();
    assert.equal(await fns._lockEscrow('job1', 'ghost', charge({ reference: 'ghost' })), 'requires_refund');
    assert.equal((await get('orphan_charges/ghost')).reason, 'unknown_reference');
    assert.equal((await get('jobs/job1')).status, 'paymentPending');
  });

  test('non-Nigerian card still funds the paid job but alerts admins (D1)', async () => {
    await seedPayable();
    assert.equal(await fns._lockEscrow('job1', 'pay_1', charge({ authorization: { country_code: 'GB' } })), 'lock');
    assert.equal((await get('admin_alerts/intl_card_pay_1')).cardCountry, 'GB');
  });
});

describe('_sweepAbandonedPayments (expireAbandonedPayments, D5 24 h)', () => {
  const now = Date.now();
  const stale = { job: { paymentInitializedAt: ts(now - 25 * H) } };

  test('definitely unpaid after 24 h → back to inChat, payment expired, audit + notification', async () => {
    await seedPayable(stale);
    await db.doc('payment_init_locks/job1').set({ status: 'done', updatedAtMs: now });
    const s = await fns._sweepAbandonedPayments(now, async () => ({ status: 'abandoned' }));
    assert.equal(s.reverted, 1);
    const job = await get('jobs/job1');
    assert.equal(job.status, 'inChat');
    assert.equal(job.agreementStatus, 'confirmed');   // agreement kept — customer can pay again
    assert.equal(job.pendingPaymentReference, undefined);
    assert.equal(job.updateVersion, 6);
    assert.equal((await get('payments/pay_1')).abandonReason, 'stale_timeout');
    assert.equal((await db.doc('payment_init_locks/job1').get()).exists, false);
    assert.equal((await db.collection('jobs/job1/auditLogs').get()).size, 1);
    assert.equal(await count('notifications', 'userId', 'cust1'), 1);
  });

  test('…and if that charge then succeeds after all, it is honoured (recover_lock)', async () => {
    await seedPayable(stale);
    await fns._sweepAbandonedPayments(now, async () => ({ status: 'abandoned' }));
    assert.equal(await fns._lockEscrow('job1', 'pay_1', charge()), 'recover_lock');
    assert.equal((await get('jobs/job1')).status, 'escrowLocked');
  });

  test('a missed webhook is recovered: Paystack says success → escrow locked', async () => {
    await seedPayable(stale);
    const s = await fns._sweepAbandonedPayments(now, async (ref) => charge({ reference: ref }));
    assert.equal(s.locked, 1);
    assert.equal((await get('jobs/job1')).status, 'escrowLocked');
  });

  test('in-flight, unverifiable or young payments are left alone', async () => {
    await seedPayable(stale);
    await fns._sweepAbandonedPayments(now, async () => ({ status: 'ongoing' }));
    await fns._sweepAbandonedPayments(now, async () => { throw new Error('network'); });
    assert.equal((await get('jobs/job1')).status, 'paymentPending');
    await clearAll();
    await seedPayable({ job: { paymentInitializedAt: ts(now - 2 * H) } });
    await fns._sweepAbandonedPayments(now, async () => ({ status: 'abandoned' }));
    assert.equal((await get('jobs/job1')).status, 'paymentPending');
  });

  test('configurable: config/platform abandonedPaymentHours = 48 keeps a 25 h checkout open', async () => {
    await db.doc('config/platform').set({ abandonedPaymentHours: 48 });
    await seedPayable(stale);
    await fns._sweepAbandonedPayments(now, async () => ({ status: 'abandoned' }));
    assert.equal((await get('jobs/job1')).status, 'paymentPending');
  });
});

describe('_releaseEscrow (auto-release) — HT-005 window + HT-017 single count', () => {
  async function seedSubmitted(submittedAgoMs) {
    await db.doc('artisans/art1').set({ completedJobs: 3, totalJobs: 4 });
    await db.doc('jobs/job1').set({
      customerId: 'cust1', artisanId: 'art1', status: 'submitted', paymentReference: 'pay_1',
      submittedAt: ts(Date.now() - submittedAgoMs), autoReleaseAt: ts(0), // client-backdated
    });
    await db.doc('payments/pay_1').set({ jobId: 'job1', status: 'escrowHeld', amount: 50000 });
  }

  test('a backdated autoReleaseAt cannot release before submittedAt + 14 days', async () => {
    await seedSubmitted(1 * H);
    await fns._releaseEscrow('job1', 'test');
    assert.equal((await get('jobs/job1')).status, 'submitted');
    assert.equal((await db.doc('escrow_releases/job1').get()).exists, false);
  });

  test('after 14 days it releases once, and does not touch artisan stats itself', async () => {
    await seedSubmitted(15 * DAY);
    await fns._releaseEscrow('job1', 'test');
    assert.equal((await get('jobs/job1')).status, 'completed');
    assert.equal((await get('escrow_releases/job1')).requestedBy, 'system');
    // onJobCompleted (the trigger) is the single place that counts the job.
    assert.deepEqual(await get('artisans/art1'), { completedJobs: 3, totalJobs: 4 });
  });
});

describe('_processEscrowRelease (payout) — D1 amount + HT-002 identity', () => {
  async function seedRelease({ requestedBy = 'cust1', customerId = 'cust1' } = {}) {
    await db.doc('jobs/job1').set({ customerId, artisanId: 'art1', status: 'completed', agreedAmount: 50000 });
    await db.doc('payments/pay_1').set({
      jobId: 'job1', payerId: 'cust1', status: 'escrowHeld',
      amount: 50000, serviceAmount: 50000, platformFee: 2500, totalCharged: 52500, amountKobo: 5_250_000,
    });
    await db.doc('artisan_private/art1').set({
      accountNumber: '0123456789', bankName: 'Access Bank', accountName: 'Art One', paystackRecipientCode: 'RCP_x',
    });
    await db.doc('escrow_releases/job1').set({ jobId: 'job1', status: 'pending', requestedBy });
  }
  const fakeHttp = () => {
    const calls = [];
    return { calls, post: async (url, body) => { calls.push({ url, body }); return { data: { data: { transfer_code: 'TRF_1', status: 'pending' } } }; } };
  };

  test('artisan receives the agreed price only — the platform fee is never paid out', async () => {
    await seedRelease();
    const http = fakeHttp();
    await fns._processEscrowRelease(db.doc('escrow_releases/job1'), 'job1', http);
    assert.equal(http.calls.length, 1);
    assert.equal(http.calls[0].body.amount, 5_000_000); // ₦50,000, not ₦52,500
    assert.equal(http.calls[0].body.reference, 'job1');
  });

  test('a release not requested by the payer is refused with an alert, no transfer', async () => {
    await seedRelease({ requestedBy: 'art1' });
    const http = fakeHttp();
    await fns._processEscrowRelease(db.doc('escrow_releases/job1'), 'job1', http);
    assert.equal(http.calls.length, 0);
    assert.equal((await get('escrow_releases/job1')).failureReason, 'release_requester_not_payer');
    assert.equal(await count('admin_alerts', 'type', 'payout_authorization_failed'), 1);
  });

  test('a job whose customer no longer matches the payer is refused', async () => {
    await seedRelease({ requestedBy: 'art1', customerId: 'art1' });
    const http = fakeHttp();
    await fns._processEscrowRelease(db.doc('escrow_releases/job1'), 'job1', http);
    assert.equal(http.calls.length, 0);
    assert.equal((await get('escrow_releases/job1')).failureReason, 'job_customer_payer_mismatch');
  });

  test('a second invocation for the same release does not pay twice', async () => {
    await seedRelease();
    const http = fakeHttp();
    await fns._processEscrowRelease(db.doc('escrow_releases/job1'), 'job1', http);
    await fns._processEscrowRelease(db.doc('escrow_releases/job1'), 'job1', http);
    assert.equal(http.calls.length, 1);
  });
});

describe('Paid-cancellation request alert (Stage 2 gap, fixed here)', () => {
  test('redelivered trigger creates one alert and one notification', async () => {
    const job = {
      customerId: 'cust1', artisanId: 'art1', status: 'inProgress',
      cancellationRequestedBy: 'cust1', cancellationRequestReason: 'Other', cancellationRequestedAt: ts(1_700_000_000_000),
    };
    await fns._handlePaidCancellationRequest('job1', job);
    await fns._handlePaidCancellationRequest('job1', job);
    assert.equal(await count('admin_alerts', 'type', 'paid_cancellation_request'), 1);
    assert.equal(await count('notifications', 'userId', 'art1'), 1);
  });
});
