/**
 * Stage 7 — END-TO-END trigger harness. Runs the REAL deployed-shape Cloud
 * Functions inside the Functions emulator and drives them with ordinary
 * Firestore writes (exactly what a client write causes), then waits for the
 * triggers' effects. Covers the wiring previously only code-reviewed
 * (Stage 4 R-7, Stage 5 R-1, Stage 6 R-2).
 *
 * Never contacts Paystack or FCM: payout scenarios run without bank details
 * (the function stops before any Paystack call) and no FCM tokens exist.
 *
 * Not part of `npm test` (needs the Functions emulator). Run e.g.:
 *   firebase emulators:exec --only functions,firestore \
 *     "node --test functions/test/e2e_triggers.functions-emulator.test.js"
 * with E2E_FIRESTORE_PORT / GCLOUD_PROJECT matching the emulator config.
 */
const PORT = process.env.E2E_FIRESTORE_PORT || '8090';
process.env.FIRESTORE_EMULATOR_HOST = `127.0.0.1:${PORT}`;
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-handytrust-e2e';

const { test, describe, before } = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');

admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();
const ts = (ms) => admin.firestore.Timestamp.fromMillis(ms);
const DAY = 24 * 60 * 60 * 1000;
let seq = 0;
const id = (p) => `${p}_${Date.now()}_${++seq}`;
const get = async (p) => (await db.doc(p).get()).data();

async function waitFor(fn, label, timeoutMs = 60000) {
  const start = Date.now();
  let last;
  while (Date.now() - start < timeoutMs) {
    try {
      last = await fn();
      if (last) return last;
    } catch (e) { last = e; }
    await new Promise((r) => setTimeout(r, 300));
  }
  throw new Error(`timed out waiting for: ${label} (last: ${JSON.stringify(last)})`);
}
const notif = (uid, pred = () => true) => waitFor(async () => {
  const s = await db.collection('notifications').where('userId', '==', uid).get();
  return s.docs.map((d) => d.data()).find(pred);
}, `notification for ${uid}`);

before(async () => {
  // Warm-up: the first trigger invocation includes the emulator cold start.
  const j = id('warm');
  await db.doc(`jobs/${j}`).set({ customerId: 'w', status: 'requested', customerAddress: 'a, b, c' });
  await waitFor(async () => (await get(`jobs/${j}`))?.customerAddress === undefined, 'warm-up', 90000);
});

describe('Location privacy trigger (Stage 6)', () => {
  test('a job created with an exact location (older app build) is stripped and moved', async () => {
    const j = id('loc');
    await db.doc(`jobs/${j}`).set({
      customerId: 'c1', status: 'requested', customerLat: 6.52437, customerLng: 3.37921,
      customerAddress: '12 Home Street, Ikeja, Lagos',
    });
    const job = await waitFor(async () => {
      const d = await get(`jobs/${j}`);
      return d && d.customerAddress === undefined && d.areaLabel ? d : null;
    }, 'location stripped');
    assert.equal(job.customerLat, undefined);
    assert.equal(job.areaLabel, 'Ikeja, Lagos');
    assert.equal(job.areaLat, 6.52);
    const priv = await get(`jobs/${j}/private/location`);
    assert.equal(priv.customerAddress, '12 Home Street, Ikeja, Lagos');
    assert.equal(priv.customerLng, 3.37921);
  });
});

describe('Booking lifecycle triggers (Stage 5)', () => {
  test('old-build match is normalized to a booking request; artisan notified with a deep link', async () => {
    const j = id('book');
    await db.doc(`jobs/${j}`).set({ customerId: 'c2', artisanId: '', status: 'requested' });
    await db.doc(`jobs/${j}`).update({ status: 'matched', artisanId: 'a2', matchedAt: admin.firestore.FieldValue.serverTimestamp() });
    const job = await waitFor(async () => {
      const d = await get(`jobs/${j}`);
      return d?.bookingStatus === 'awaitingArtisan' && d.bookingRequestedAt ? d : null;
    }, 'booking normalized');
    assert.ok(job.bookingRequestedAt.toMillis() > 0);
    const n = await notif('a2', (x) => x.jobId === j && x.type === 'job_assigned');
    assert.equal(n.route, `/job/${j}`);

    await db.doc(`jobs/${j}`).update({ status: 'inChat', bookingStatus: 'confirmed' });
    await notif('c2', (x) => x.jobId === j && x.title === 'Booking Confirmed');
  });

  test('agreement steps notify the other party (previously client-written)', async () => {
    const j = id('agr');
    await db.doc(`jobs/${j}`).set({ customerId: 'c3', artisanId: 'a3', status: 'inChat', agreementStatus: 'negotiating' });
    await db.doc(`jobs/${j}`).update({ agreementStatus: 'pendingArtisanConfirmation' });
    await notif('a3', (x) => x.jobId === j && x.type === 'agreement_pending');
    await db.doc(`jobs/${j}`).update({ agreementStatus: 'confirmed' });
    await notif('c3', (x) => x.jobId === j && x.type === 'agreement_accepted');
  });
});

describe('Review window and rework triggers (Stages 2, 5)', () => {
  test('submission sets BOTH timers to server submittedAt + 14 days; rework clears them', async () => {
    const j = id('sub');
    await db.doc(`jobs/${j}`).set({ customerId: 'c4', artisanId: 'a4', status: 'inProgress' });
    const submittedAt = Date.now() - 1000;
    // Client tries to backdate (would be rejected by rules; here the trigger must still overwrite).
    await db.doc(`jobs/${j}`).update({ status: 'submitted', submittedAt: ts(submittedAt), autoReleaseAt: ts(0) });
    const job = await waitFor(async () => {
      const d = await get(`jobs/${j}`);
      return d?.autoReleaseAt?.toMillis() === submittedAt + 14 * DAY ? d : null;
    }, 'server timers');
    assert.equal(job.disputeWindowEndsAt.toMillis(), submittedAt + 14 * DAY);
    await notif('c4', (x) => x.jobId === j && /Work Submitted/.test(x.title));

    await db.doc(`jobs/${j}`).update({ status: 'inProgress', reworkCount: 1, reworkReason: 'Tap still drips under load' });
    await waitFor(async () => {
      const d = await get(`jobs/${j}`);
      return d && d.autoReleaseAt === undefined && d.disputeWindowEndsAt === undefined;
    }, 'timers cleared on rework');
    await notif('a4', (x) => x.jobId === j && x.title === 'Rework Requested');
  });
});

describe('Server-generated notifications (Stage 6)', () => {
  test('a new quote notifies the customer; a chat message notifies the receiver', async () => {
    const j = id('q');
    await db.doc(`jobs/${j}`).set({ customerId: 'c5', artisanId: '', status: 'requested' });
    await db.doc(`jobs/${j}/quotes/a5`).set({ artisanId: 'a5', artisanName: 'Ada', amount: 12000, status: 'pending' });
    const n = await notif('c5', (x) => x.jobId === j && x.type === 'quote_received');
    assert.match(n.body, /Ada/);
    await db.doc(`jobs/${j}/messages/m1`).set({ senderId: 'a5', receiverId: 'c5', type: 'text', text: 'Can I come Tuesday?' });
    await notif('c5', (x) => x.jobId === j && x.type === 'message_received' && x.body === 'Can I come Tuesday?');
  });

  test('a dispute raised by the artisan alerts admins and notifies the customer', async () => {
    const j = id('dsp');
    await db.doc(`artisans/a6`).set({ uid: 'a6', openDisputeCount: 0 });
    await db.doc(`jobs/${j}`).set({ customerId: 'c6', artisanId: 'a6', status: 'inProgress' });
    const d = id('d');
    await db.doc(`disputes/${d}`).set({ id: d, jobId: j, raisedBy: 'a6', againstUserId: 'c6', reason: 'unreachable', status: 'open' });
    await db.doc(`jobs/${j}`).update({ status: 'disputed', disputeReason: 'unreachable' });
    await notif('c6', (x) => x.jobId === j && x.type === 'dispute_raised');
    await waitFor(async () => (await db.doc(`admin_alerts/dispute_${d}`).get()).exists, 'dispute alert');
    await waitFor(async () => (await db.doc(`admin_alerts/dispute_job_${j}`).get()).exists, 'job dispute alert');
    await waitFor(async () => (await get('artisans/a6'))?.openDisputeCount === 1, 'dispute count');
  });

  test('a review updates the artisan rating once and notifies them', async () => {
    const j = id('rev');
    await db.doc('artisans/a7').set({ uid: 'a7', rating: 4, totalRatings: 1 });
    await db.doc(`jobs/${j}`).set({ customerId: 'c7', artisanId: 'a7', status: 'completed' });
    await db.doc(`reviews/${j}`).set({ id: j, jobId: j, customerId: 'c7', artisanId: 'a7', rating: 5, comment: '' });
    await waitFor(async () => (await get('artisans/a7'))?.totalRatings === 2, 'rating aggregated');
    assert.equal((await get('artisans/a7')).rating, 4.5);
    await notif('a7', (x) => x.type === 'review_received');
  });
});

describe('Money-adjacent triggers (Stages 2–4)', () => {
  test('paid cancellation request → one admin alert + the other party is told', async () => {
    const j = id('pcr');
    await db.doc(`jobs/${j}`).set({ customerId: 'c8', artisanId: 'a8', status: 'escrowLocked' });
    await db.doc(`jobs/${j}`).update({
      cancellationRequestStatus: 'pending', cancellationRequestedBy: 'c8', cancellationRequestReason: 'No longer needed',
      cancellationRequestedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    await notif('a8', (x) => x.jobId === j && x.title === 'Cancellation Requested');
    const alerts = await waitFor(async () => {
      const s = await db.collection('admin_alerts').where('jobId', '==', j).where('type', '==', 'paid_cancellation_request').get();
      return s.size ? s : null;
    }, 'cancellation alert');
    assert.equal(alerts.size, 1);
  });

  test('cancelling during checkout abandons the pending payment (late charge → refund queue)', async () => {
    const j = id('pp');
    const p = id('pay');
    await db.doc(`jobs/${j}`).set({ customerId: 'c9', artisanId: 'a9', status: 'paymentPending' });
    await db.doc(`payments/${p}`).set({ id: p, jobId: j, payerId: 'c9', status: 'pending', paystackReference: p, amount: 50000 });
    await db.doc(`jobs/${j}`).update({ status: 'cancelled', cancelledBy: 'c9' });
    await waitFor(async () => (await get(`payments/${p}`))?.status === 'abandoned', 'payment abandoned');
    assert.equal((await get(`payments/${p}`)).abandonReason, 'job_cancelled');
  });

  test('payout without bank details: release fails closed, job shows "delayed", artisan told — no Paystack call', async () => {
    const j = id('po');
    await db.doc('users/a10').set({ accountStatus: 'active' });
    await db.doc('artisans/a10').set({ uid: 'a10' });
    await db.doc(`jobs/${j}`).set({ customerId: 'c10', artisanId: 'a10', status: 'completed', agreedAmount: 50000 });
    await db.doc(`payments/${id('p')}`).set({ jobId: j, payerId: 'c10', status: 'escrowHeld', amount: 50000, serviceAmount: 50000 });
    await db.doc(`escrow_releases/${j}`).set({ jobId: j, status: 'pending', requestedBy: 'c10' });
    const rel = await waitFor(async () => {
      const r = await get(`escrow_releases/${j}`);
      return r?.status === 'failed' ? r : null;
    }, 'release failed');
    assert.equal(rel.failureReason, 'no_bank_details');
    await waitFor(async () => (await get(`jobs/${j}`))?.payoutStatus === 'delayed', 'payout mirrored');
    await notif('a10', (x) => x.jobId === j && x.type === 'payout_blocked');
  });

  test('a release requested by someone other than the payer is refused end-to-end', async () => {
    const j = id('po2');
    await db.doc('artisans/a11').set({ uid: 'a11' });
    await db.doc(`jobs/${j}`).set({ customerId: 'c11', artisanId: 'a11', status: 'completed', agreedAmount: 50000 });
    await db.doc(`payments/${id('p')}`).set({ jobId: j, payerId: 'c11', status: 'escrowHeld', amount: 50000, serviceAmount: 50000 });
    await db.doc(`escrow_releases/${j}`).set({ jobId: j, status: 'pending', requestedBy: 'a11' });
    const rel = await waitFor(async () => {
      const r = await get(`escrow_releases/${j}`);
      return r?.status === 'failed' ? r : null;
    }, 'release refused');
    assert.equal(rel.failureReason, 'release_requester_not_payer');
  });

  test('confirming completion counts the job exactly once in artisan stats', async () => {
    const j = id('cmp');
    await db.doc('artisans/a12').set({ uid: 'a12', totalJobs: 2, completedJobs: 2 });
    await db.doc(`jobs/${j}`).set({ customerId: 'c12', artisanId: 'a12', status: 'submitted' });
    await db.doc(`jobs/${j}`).update({ status: 'completed' });
    await waitFor(async () => (await get('artisans/a12'))?.completedJobs === 3, 'stats');
    await new Promise((r) => setTimeout(r, 3000)); // give any duplicate path time to run
    assert.equal((await get('artisans/a12')).completedJobs, 3);
  });
});
