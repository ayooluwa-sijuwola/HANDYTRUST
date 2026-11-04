/**
 * Stage 5 remediation — booking confirmation, withdrawal/reopen, deadline
 * expiry, rework review window, suspension restrictions
 * (design/REMEDIATION_STAGE5_REPORT_2026-11-03.md).
 *
 * LOCAL Firestore emulator only. Paystack is never called (fakes).
 *   firebase emulators:exec --only firestore "cd functions && npm test"
 */
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8090';
process.env.GCLOUD_PROJECT = 'handytrust-stage5-test';

const { test, describe, beforeEach, after } = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
const fns = require('../index.js');

const db = admin.firestore();
const PROJECT = process.env.GCLOUD_PROJECT;
const H = 60 * 60 * 1000;
const DAY = 24 * H;
const ts = (ms) => admin.firestore.Timestamp.fromMillis(ms);
const ago = (ms) => ts(Date.now() - ms);
const get = async (p) => (await db.doc(p).get()).data();
const count = async (col, field, val) => (await db.collection(col).where(field, '==', val).get()).size;

let refundCalls; let transferCalls;
beforeEach(async () => {
  await fetch(`http://127.0.0.1:8090/emulator/v1/projects/${PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  refundCalls = []; transferCalls = [];
  fns._setPaystackFakes({
    paystack: {
      createRefund: async (a) => { refundCalls.push(a); return { id: 'rf', status: 'pending' }; },
      fetchRefund: async () => ({ status: 'pending' }), listRefunds: async () => [],
    },
    transferHttp: { post: async (u, b) => { transferCalls.push(b); return { data: { data: { status: 'pending' } } }; } },
  });
});
after(() => fns._setPaystackFakes({}));

async function seedJob(job, { quotes = {}, users = {} } = {}) {
  await db.doc('users/cust1').set({ uid: 'cust1', accountStatus: 'active', ...(users.cust1 || {}) });
  await db.doc('users/art1').set({ uid: 'art1', accountStatus: 'active', ...(users.art1 || {}) });
  await db.doc('artisans/art1').set({ uid: 'art1', totalJobs: 4, completedJobs: 4, cancelledJobsCount: 0 });
  await db.doc('jobs/job1').set({ customerId: 'cust1', artisanId: 'art1', category: 'Plumbing', updateVersion: 3, ...job });
  for (const [id, q] of Object.entries(quotes)) await db.doc(`jobs/job1/quotes/${id}`).set({ artisanId: id, amount: 10000, ...q });
}
const withdraw = (uid, reason = 'Unavailable on requested date') =>
  fns.artisanWithdrawFromJob.run({ auth: { uid }, data: { jobId: 'job1', reason } });

describe('Artisan withdrawal / booking decline reopens the job (D6/D7)', () => {
  test('withdrawal after confirmation: job reopens, terms cleared, valid quotes revived, counts as a cancellation', async () => {
    await seedJob(
      { status: 'inChat', bookingStatus: 'confirmed', agreementStatus: 'confirmed', agreedAmount: 50000, appointmentSlots: [ts(1)] },
      { quotes: {
        art1: { status: 'accepted', updatedAt: ago(5 * H) },
        art2: { status: 'closed', updatedAt: ago(10 * H) },
        art3: { status: 'closed', updatedAt: ago(60 * H) },
      } },
    );
    assert.deepEqual(await withdraw('art1'), { reopened: true, reason: 'artisan_withdrew' });
    const job = await get('jobs/job1');
    assert.equal(job.status, 'requested');
    assert.equal(job.artisanId, '');
    assert.equal(job.agreementStatus, undefined);
    assert.equal(job.agreedAmount, undefined);
    assert.equal(job.appointmentSlots, undefined);
    assert.equal(job.reopenCount, 1);
    assert.deepEqual(job.previousArtisanIds, ['art1']);
    assert.equal((await get('jobs/job1/quotes/art1')).status, 'withdrawn');
    assert.equal((await get('jobs/job1/quotes/art2')).status, 'pending');   // still within 48 h
    assert.equal((await get('jobs/job1/quotes/art3')).status, 'expired');   // past validity
    assert.equal((await get('artisans/art1')).cancelledJobsCount, 1);
    assert.equal(await count('notifications', 'userId', 'cust1'), 1);
    assert.equal(await count('notifications', 'userId', 'art2'), 1);
  });

  test('declining a booking request reopens the job without a cancellation penalty', async () => {
    await seedJob({ status: 'matched', bookingStatus: 'awaitingArtisan', matchedAt: ago(H) });
    assert.equal((await withdraw('art1')).reason, 'artisan_declined_booking');
    assert.equal((await get('jobs/job1')).status, 'requested');
    assert.equal((await get('artisans/art1')).cancelledJobsCount, 0);
  });

  test('withdrawal is refused on funded jobs, for other users, and when repeated', async () => {
    await seedJob({ status: 'escrowLocked' });
    await assert.rejects(withdraw('art1'), /already paid/);
    await db.doc('jobs/job1').update({ status: 'inChat' });
    await assert.rejects(withdraw('cust1'), /not the artisan/);
    await assert.rejects(fns.artisanWithdrawFromJob.run({ data: { jobId: 'job1', reason: 'x y z' } }), /Sign in required/);
    await withdraw('art1');
    await assert.rejects(withdraw('art1'), /not the artisan/); // artisanId cleared — duplicate refused
  });

  test('withdrawal during an open checkout: payment abandoned; a late charge is refunded, never applied', async () => {
    await seedJob({ status: 'paymentPending', bookingStatus: 'confirmed', agreementStatus: 'confirmed', agreedAmount: 50000, pendingPaymentReference: 'pay_1' });
    await db.doc('payments/pay_1').set({
      id: 'pay_1', jobId: 'job1', payerId: 'cust1', paystackReference: 'pay_1', amount: 50000, amountKobo: 5_250_000, status: 'pending',
    });
    await withdraw('art1');
    assert.equal((await get('payments/pay_1')).status, 'abandoned');
    const outcome = await fns._lockEscrow('job1', 'pay_1', {
      status: 'success', reference: 'pay_1', amount: 5_250_000, currency: 'NGN', metadata: { jobId: 'job1' },
    });
    assert.equal(outcome, 'requires_refund');
    assert.equal((await get('jobs/job1')).status, 'requested');
  });

  test('a payment locking first wins: the withdrawal then refuses (funded)', async () => {
    await seedJob({ status: 'paymentPending', pendingPaymentReference: 'pay_1' });
    await db.doc('payments/pay_1').set({ id: 'pay_1', jobId: 'job1', payerId: 'cust1', paystackReference: 'pay_1', amount: 50000, amountKobo: 5_250_000, status: 'pending' });
    await fns._lockEscrow('job1', 'pay_1', { status: 'success', reference: 'pay_1', amount: 5_250_000, currency: 'NGN', metadata: { jobId: 'job1' } });
    await assert.rejects(withdraw('art1'), /already paid/);
    assert.equal((await get('jobs/job1')).status, 'escrowLocked');
  });
});

describe('Deadline sweep — expireMarketplaceDeadlines (D5, server time, configurable)', () => {
  test('a booking request unanswered for 24 h reopens the job; younger or confirmed ones are untouched', async () => {
    await seedJob({ status: 'matched', bookingStatus: 'awaitingArtisan', matchedAt: ago(25 * H) });
    const s = await fns._expireMarketplaceDeadlines();
    assert.equal(s.bookingsExpired, 1);
    assert.equal((await get('jobs/job1')).reopenReason, 'booking_expired');

    await seedJob({ status: 'matched', bookingStatus: 'awaitingArtisan', matchedAt: ago(23 * H) });
    await fns._expireMarketplaceDeadlines();
    assert.equal((await get('jobs/job1')).status, 'matched');

    await seedJob({ status: 'matched', bookingStatus: 'confirmed', matchedAt: ago(50 * H) });
    await fns._expireMarketplaceDeadlines();
    assert.equal((await get('jobs/job1')).status, 'matched');
  });

  test('the artisan confirming just before the sweep wins (no reopen)', async () => {
    await seedJob({ status: 'matched', bookingStatus: 'awaitingArtisan', matchedAt: ago(25 * H) });
    await db.doc('jobs/job1').update({ status: 'inChat', bookingStatus: 'confirmed' });
    const s = await fns._expireMarketplaceDeadlines();
    assert.equal(s.bookingsExpired, 0);
    assert.equal((await get('jobs/job1')).status, 'inChat');
  });

  test('quotes expire 48 h after their server-stamped submission', async () => {
    await seedJob({ status: 'requested', artisanId: '' }, { quotes: {
      artA: { status: 'pending', updatedAt: ago(49 * H) },
      artB: { status: 'pending', updatedAt: ago(10 * H) },
    } });
    const s = await fns._expireMarketplaceDeadlines();
    assert.equal(s.quotesExpired, 1);
    assert.equal((await get('jobs/job1/quotes/artA')).status, 'expired');
    assert.equal((await get('jobs/job1/quotes/artB')).status, 'pending');
    assert.equal((await get('jobs/job1')).status, 'requested');
  });

  test('an open job expires after 7 days with all its pending quotes; idempotent on re-run', async () => {
    await seedJob({ status: 'requested', artisanId: '', reopenedAt: ago(8 * DAY) }, { quotes: { artB: { status: 'pending', updatedAt: ago(H) } } });
    const s = await fns._expireMarketplaceDeadlines();
    assert.equal(s.jobsExpired, 1);
    const job = await get('jobs/job1');
    assert.equal(job.status, 'expired');
    assert.equal((await get('jobs/job1/quotes/artB')).status, 'expired');
    assert.equal((await db.collection('jobs/job1/auditLogs').get()).size, 1);
    const again = await fns._expireMarketplaceDeadlines();
    assert.equal(again.jobsExpired, 0);
  });

  test('deadlines follow trusted config (openJobDays = 14)', async () => {
    await db.doc('config/platform').set({ openJobDays: 14 });
    await seedJob({ status: 'requested', artisanId: '', reopenedAt: ago(8 * DAY) });
    await fns._expireMarketplaceDeadlines();
    assert.equal((await get('jobs/job1')).status, 'requested');
  });

  test('a fresh job (real createTime) is not expired', async () => {
    await seedJob({ status: 'requested', artisanId: '' });
    await fns._expireMarketplaceDeadlines();
    assert.equal((await get('jobs/job1')).status, 'requested');
  });
});

describe('Rework and the renewed review window (D4) — Stage 4 compatible', () => {
  async function seedResubmitted(submittedAgoMs) {
    await seedJob({
      status: 'submitted', reworkCount: 1, paymentReference: 'pay_1', agreedAmount: 50000,
      submittedAt: ago(submittedAgoMs), autoReleaseAt: ago(20 * DAY), // stale window from the first submission
    });
    await db.doc('payments/pay_1').set({ jobId: 'job1', payerId: 'cust1', status: 'escrowHeld', amount: 50000, serviceAmount: 50000 });
  }

  test('after resubmission, auto-release waits a full 14 days from the NEW submission', async () => {
    await seedResubmitted(2 * DAY);
    await fns._releaseEscrow('job1', 'test');
    assert.equal((await get('jobs/job1')).status, 'submitted');
    assert.equal((await db.doc('escrow_releases/job1').get()).exists, false);
  });

  test('14 days after resubmission it releases exactly once (no duplicate payout)', async () => {
    await seedResubmitted(15 * DAY);
    await fns._releaseEscrow('job1', 'test');
    await fns._releaseEscrow('job1', 'test');
    assert.equal((await get('jobs/job1')).status, 'completed');
    assert.equal((await db.collection('escrow_releases').get()).size, 1);
  });

  test('the server review window helper restarts from each submission', () => {
    const t1 = Date.UTC(2026, 10, 1); const t2 = t1 + 5 * DAY;
    assert.equal(fns._reviewWindowEndMs(t2) - fns._reviewWindowEndMs(t1), 5 * DAY);
  });
});

describe('Suspension restrictions in Cloud Functions (D9)', () => {
  const init = (uid) => fns.initializePaystackTransaction.run({ auth: { uid }, data: { jobId: 'job1' } });

  test('fraud-suspended payer cannot start a payment, even for an existing job', async () => {
    await seedJob({ status: 'paymentPending', agreedAmount: 50000 }, { users: { cust1: { accountStatus: 'suspended', suspensionType: 'fraud' } } });
    await assert.rejects(init('cust1'), /payments are paused/);
  });

  test('administratively suspended payer passes the suspension check (restricted mode)', async () => {
    // Job deliberately not payable, so the call stops at the status check
    // AFTER the suspension check — proving suspension didn't block it, and
    // never reaching Paystack.
    await seedJob({ status: 'inChat', agreedAmount: 50000 }, { users: { cust1: { accountStatus: 'suspended', suspensionType: 'administrative' } } });
    await assert.rejects(init('cust1'), /not ready for payment/);
  });

  test('fraud-frozen artisan still cannot be paid (Stage 4 protection intact)', async () => {
    await seedJob({ status: 'completed', agreedAmount: 50000 }, { users: { art1: { accountStatus: 'suspended', suspensionType: 'fraud' } } });
    await db.doc('payments/pay_1').set({ jobId: 'job1', payerId: 'cust1', status: 'escrowHeld', amount: 50000, serviceAmount: 50000 });
    await db.doc('artisan_private/art1').set({ accountNumber: '1', bankName: 'Access Bank', accountName: 'A', paystackRecipientCode: 'R' });
    await db.doc('escrow_releases/job1').set({ jobId: 'job1', status: 'pending', requestedBy: 'cust1' });
    const out = await fns._processEscrowRelease(db.doc('escrow_releases/job1'), 'job1', { post: async (u, b) => { transferCalls.push(b); return { data: { data: {} } }; } });
    assert.equal(out.frozen, 'artisan_suspended_freeze');
    assert.equal(transferCalls.length, 0);
  });
});

describe('Config normalization for Stage 5 deadlines', () => {
  test('defaults and integer-only overrides', () => {
    const d = fns._normalizePlatformConfig(null);
    assert.equal(d.openJobDays, 7);
    assert.equal(d.quoteValidityHours, 48);
    assert.equal(d.bookingConfirmationHours, 24);
    const bad = fns._normalizePlatformConfig({ openJobDays: 2.5, quoteValidityHours: -1, bookingConfirmationHours: '24' });
    assert.equal(bad.openJobDays, 7);
    assert.equal(bad.quoteValidityHours, 48);
    assert.equal(bad.bookingConfirmationHours, 24);
  });
});
