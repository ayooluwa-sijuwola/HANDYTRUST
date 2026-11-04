/**
 * Stage 7.1 — scheduled functions, END TO END (report §9). Cloud Scheduler
 * invokes a v2 scheduled function with an HTTP POST carrying
 * X-CloudScheduler-* headers; this harness sends that request to the
 * Functions emulator, so the real deployed-shape functions run. The Pub/Sub
 * emulator must be running (without it the emulator skips scheduled
 * functions), but its own delivery path rejects v2 schedules ("Unsupported
 * trigger signature: http", firebase-tools 15.22.0). The emulator never fires
 * on a timer: the cron cadence itself can only be observed in staging.
 *
 * Never contacts Paystack: the Paystack-bound schedules run with no eligible
 * data, and payouts have no bank details.
 *
 * Run (not part of npm test):
 *   firebase emulators:exec --only functions,firestore,pubsub \
 *     "node --test functions/test/e2e_schedules.functions-emulator.test.js"
 * with E2E_FIRESTORE_PORT / E2E_FUNCTIONS_PORT / GCLOUD_PROJECT set.
 */
const PORT = process.env.E2E_FIRESTORE_PORT || '8090';
process.env.FIRESTORE_EMULATOR_HOST = `127.0.0.1:${PORT}`;
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-handytrust-e2e';
const PROJECT = process.env.GCLOUD_PROJECT;

const { test, describe } = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');

admin.initializeApp({ projectId: PROJECT });
const db = admin.firestore();
const ts = (ms) => admin.firestore.Timestamp.fromMillis(ms);
const HOUR = 60 * 60 * 1000;
const DAY = 24 * HOUR;
const get = async (p) => (await db.doc(p).get()).data();

async function waitFor(fn, label, timeoutMs = 90000) {
  const start = Date.now();
  let last;
  while (Date.now() - start < timeoutMs) {
    try { last = await fn(); if (last) return last; } catch (e) { last = e.message; }
    await new Promise((r) => setTimeout(r, 400));
  }
  throw new Error(`timed out waiting for: ${label} (last: ${JSON.stringify(last)})`);
}

// What Cloud Scheduler does for a v2 scheduled function: an HTTP POST to the
// function with X-CloudScheduler-* headers. (The Pub/Sub emulator path
// rejects v2 schedules — "Unsupported trigger signature: http" in
// firebase-tools 15.22.0 — so the request is sent directly, as in production.)
const FUNCTIONS = process.env.E2E_FUNCTIONS_PORT || '5001';
async function fireSchedule(name) {
  const res = await fetch(`http://127.0.0.1:${FUNCTIONS}/${PROJECT}/us-central1/${name}-0`, { // emulator trigger key
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'X-CloudScheduler': 'true',
      'X-CloudScheduler-JobName': `firebase-schedule-${name}-us-central1`,
      'X-CloudScheduler-ScheduleTime': new Date().toISOString(),
    },
    body: '{}',
  });
  if (!res.ok) throw new Error(`scheduler request to ${name} failed: ${res.status} ${await res.text()}`);
}

describe('Scheduled functions fire end to end (Cloud Scheduler request → function)', () => {
  test('expireMarketplaceDeadlines: an unconfirmed booking older than 24 h is reopened', async () => {
    await db.doc('jobs/sb1').set({
      customerId: 'c1', artisanId: 'a1', status: 'matched', bookingStatus: 'awaitingArtisan',
      bookingRequestedAt: ts(Date.now() - 25 * HOUR),
    });
    await db.doc('jobs/sb2').set({ // within 24 h → untouched
      customerId: 'c2', artisanId: 'a2', status: 'matched', bookingStatus: 'awaitingArtisan',
      bookingRequestedAt: ts(Date.now() - 2 * HOUR),
    });
    await fireSchedule('expireMarketplaceDeadlines');
    await waitFor(async () => (await get('jobs/sb1'))?.status === 'requested', 'booking reopened');
    assert.equal((await get('jobs/sb1')).artisanId, '');
    assert.equal((await get('jobs/sb2')).status, 'matched');
  });

  test('autoReleaseEscrow: due job is released (fails closed without bank details); a chargeback-held job is NOT', async () => {
    const due = ts(Date.now() - 15 * DAY);
    await db.doc('users/a3').set({ accountStatus: 'active' });
    await db.doc('artisans/a3').set({ uid: 'a3' });
    for (const [id, hold] of [['ar1', false], ['ar2', true]]) {
      await db.doc(`jobs/${id}`).set({
        customerId: 'c3', artisanId: 'a3', status: 'submitted', agreedAmount: 50000,
        submittedAt: due, autoReleaseAt: due, ...(hold ? { chargebackHold: true } : {}),
      });
      await db.doc(`payments/p_${id}`).set({
        jobId: id, payerId: 'c3', status: 'escrowHeld', amount: 50000, serviceAmount: 50000,
        ...(hold ? { chargebackHold: true } : {}),
      });
    }
    await fireSchedule('autoReleaseEscrow');
    await waitFor(async () => (await get('escrow_releases/ar1'))?.status === 'failed', 'release processed');
    assert.equal((await get('escrow_releases/ar1')).failureReason, 'no_bank_details');
    assert.equal((await get('jobs/ar1')).status, 'completed');
    await waitFor(async () => (await db.doc('admin_alerts/autorelease_blocked_ar2').get()).exists, 'hold alert');
    assert.equal((await get('admin_alerts/autorelease_blocked_ar2')).reason, 'chargeback_open');
    assert.equal((await db.doc('escrow_releases/ar2').get()).exists, false);
    assert.equal((await get('jobs/ar2')).status, 'submitted');
    assert.equal((await get('payments/p_ar2')).status, 'escrowHeld');
  });

  test('reconcileStuckEscrowReleases: a release stuck > 2 h is flagged to admins', async () => {
    await db.doc('escrow_releases/st1').set({ jobId: 'st1', status: 'processing', requestedAt: ts(Date.now() - 3 * HOUR) });
    await fireSchedule('reconcileStuckEscrowReleases');
    await waitFor(async () => {
      const s = await db.collection('admin_alerts').where('type', '==', 'stuck_escrow_release').where('releaseId', '==', 'st1').get();
      return s.size > 0;
    }, 'stuck alert');
  });

  test('Paystack-bound schedules (reconcileRefunds, expireAbandonedPayments) load with their secret and run (no eligible data → no Paystack call)', async () => {
    const before = (await db.collection('financial_events').get()).size;
    await fireSchedule('reconcileRefunds');
    await fireSchedule('expireAbandonedPayments');
    // Effects are "nothing to do"; success is asserted from the emulator log by the runner script.
    await new Promise((r) => setTimeout(r, 20000));
    assert.equal((await db.collection('financial_events').get()).size, before);
  });
});
