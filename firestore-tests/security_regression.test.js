/**
 * Firestore Security Rules regression tests — Stage 2 remediation
 * (design/HANDYTRUST_WORKFLOW_FUNCTIONAL_AUDIT_2026-11-03.md Appendix A,
 * design/REMEDIATION_STAGE1_VERIFICATION_2026-11-03.md §3/§6).
 *
 * Emulator only. Never touches production Firestore or Paystack.
 * Run from the repo root:
 *   firebase emulators:exec --only firestore "cd firestore-tests && npm test"
 *
 * Two kinds of test live here:
 *   - SECURITY: a malicious write that must be rejected (assertFails).
 *   - LEGITIMATE: the exact payload the shipped Flutter client writes
 *     (lib/core/services/job_service.dart etc.) — must keep succeeding, so a
 *     rule tightening can never silently break a real customer/artisan flow.
 */
const { test, before, after, beforeEach, describe } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const { serverTimestamp, Timestamp } = require('firebase/firestore');

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'handytrust-security-regression',
    firestore: {
      rules: fs.readFileSync(path.resolve(__dirname, '../firestore.rules'), 'utf8'),
      host: '127.0.0.1',
      port: 8090,
    },
  });
});
after(async () => env.cleanup());
beforeEach(async () => env.clearFirestore());

// ─── Helpers ────────────────────────────────────────────────────────────────

const C = 'cust1';      // the job's customer
const A = 'art1';       // the job's matched artisan
const A2 = 'art2';      // another eligible artisan
const X = 'stranger1';  // signed-in, unrelated

const db = (uid) =>
  env.authenticatedContext(uid, { firebase: { sign_in_provider: 'password' } }).firestore();
const seed = (fn) => env.withSecurityRulesDisabled(async (c) => fn(c.firestore()));

// JobService._consistencyFields — sent on every client job mutation.
const consistency = (actor, version = 1) => ({
  lastUpdatedAt: serverTimestamp(),
  lastUpdatedBy: actor,
  updateVersion: version,
});

const eligibleArtisan = (uid, extra = {}) => ({
  uid, approvalStatus: 'approved', verificationStatus: 'id_verified',
  responseTimeMinutes: 30, ...extra,
});

async function seedWorld(job, { users = {}, artisans = {} } = {}) {
  await seed(async (f) => {
    await f.doc(`users/${C}`).set({ uid: C, name: 'Cust', accountStatus: 'active', ...(users[C] || {}) });
    await f.doc(`users/${A}`).set({ uid: A, name: 'Art', accountStatus: 'active', ...(users[A] || {}) });
    await f.doc(`users/${A2}`).set({ uid: A2, name: 'Art2', accountStatus: 'active', ...(users[A2] || {}) });
    await f.doc(`artisans/${A}`).set(eligibleArtisan(A, artisans[A]));
    await f.doc(`artisans/${A2}`).set(eligibleArtisan(A2, artisans[A2]));
    if (job) {
      await f.doc('jobs/j1').set({
        id: 'j1', customerId: C, artisanId: A, category: 'Plumbing', description: 'Fix sink',
        updateVersion: 0, ...job,
      });
    }
  });
}
const jobRef = (uid) => db(uid).doc('jobs/j1');

// ════════════════════════════════════════════════════════════════════════════
// SECURITY — Appendix A probes, inverted into must-fail regressions
// ════════════════════════════════════════════════════════════════════════════

describe('Appendix A regressions (HT-001..HT-023)', () => {
  test('P-A artisan cannot rewrite customerId on escrowLocked->inProgress (HT-002)', async () => {
    await seedWorld({ status: 'escrowLocked', agreedAmount: 50000 });
    await assertFails(jobRef(A).update({
      status: 'inProgress', customerId: A, startedAt: serverTimestamp(), ...consistency('artisan:art1'),
    }));
  });

  test('P-A2 artisan cannot create an escrow release even on a submitted job (HT-002)', async () => {
    await seedWorld({ status: 'submitted' });
    await assertFails(db(A).doc('escrow_releases/j1').set({
      jobId: 'j1', status: 'pending', requestedAt: serverTimestamp(), requestedBy: A,
    }));
  });

  test('P-A3 customer cannot create a release claiming to be someone else (HT-002)', async () => {
    await seedWorld({ status: 'submitted' });
    await assertFails(db(C).doc('escrow_releases/j1').set({
      jobId: 'j1', status: 'pending', requestedAt: serverTimestamp(), requestedBy: 'system',
    }));
  });

  test('P-B customer cannot self-confirm the agreement on matched->inChat (HT-003)', async () => {
    await seedWorld({ status: 'matched', agreedAmount: 50000 });
    await assertFails(jobRef(C).update({
      status: 'inChat', agreementStatus: 'confirmed', agreedAmount: 100, ...consistency('customer:cust1'),
    }));
  });

  test('P-B2 customer cannot set agreementStatus or price during requested->matched (HT-003)', async () => {
    await seedWorld({ status: 'requested', artisanId: '' });
    await assertFails(jobRef(C).update({
      status: 'matched', artisanId: A, matchedAt: serverTimestamp(),
      agreementStatus: 'confirmed', agreedAmount: 1, ...consistency('customer:cust1'),
    }));
  });

  test('P-C artisan cannot set autoReleaseAt in the past on submit (HT-005)', async () => {
    await seedWorld({ status: 'inProgress' });
    await assertFails(jobRef(A).update({
      status: 'submitted', completionImageUrls: ['https://x/y.jpg'], submittedAt: serverTimestamp(),
      autoReleaseAt: Timestamp.fromMillis(0), disputeWindowEndsAt: Timestamp.fromMillis(0),
      ...consistency('artisan:art1'),
    }));
  });

  test('P-C2 artisan cannot backdate submittedAt with a client timestamp (HT-005)', async () => {
    await seedWorld({ status: 'inProgress' });
    await assertFails(jobRef(A).update({
      status: 'submitted', completionImageUrls: ['https://x/y.jpg'],
      submittedAt: Timestamp.fromMillis(0), ...consistency('artisan:art1'),
    }));
  });

  test('P-D customer cannot change the accepted price on inChat->paymentPending (HT-004)', async () => {
    await seedWorld({ status: 'inChat', agreementStatus: 'confirmed', agreedAmount: 50000 });
    await assertFails(jobRef(C).update({
      status: 'paymentPending', agreedAmount: 100, ...consistency('customer:cust1'),
    }));
  });

  test('P-E artisan cannot cancel a funded job (HT-006, policy D2)', async () => {
    await seedWorld({ status: 'escrowLocked' });
    await assertFails(jobRef(A).update({
      status: 'cancelled', cancelledBy: A, cancelledAt: serverTimestamp(), ...consistency('artisan:art1'),
    }));
  });

  test('P-E2 customer cannot cancel a funded job (HT-006, policy D2)', async () => {
    await seedWorld({ status: 'escrowLocked' });
    await assertFails(jobRef(C).update({
      status: 'cancelled', cancelledBy: C, cancelledAt: serverTimestamp(), ...consistency('customer:cust1'),
    }));
  });

  test('P-F customer cannot cancel inProgress (unchanged; UI now offers a request instead)', async () => {
    await seedWorld({ status: 'inProgress' });
    await assertFails(jobRef(C).update({
      status: 'cancelled', cancelledBy: C, cancelledAt: serverTimestamp(), ...consistency('customer:cust1'),
    }));
  });

  test('P-G second review for the same job is rejected (HT-014)', async () => {
    await seedWorld({ status: 'completed' });
    const r = { id: 'j1', jobId: 'j1', customerId: C, artisanId: A, rating: 5, comment: '', createdAt: Timestamp.now() };
    await assertSucceeds(db(C).doc('reviews/j1').set(r));
    await assertFails(db(C).doc('reviews/r2').set({ ...r, id: 'r2' }));
  });

  test('P-G2 review must target the job\'s actual artisan (HT-014)', async () => {
    await seedWorld({ status: 'completed' });
    await assertFails(db(C).doc('reviews/j1').set({
      id: 'j1', jobId: 'j1', customerId: C, artisanId: A2, rating: 1, comment: '', createdAt: Timestamp.now(),
    }));
  });

  test('P-H stranger cannot notify an arbitrary user (HT-015)', async () => {
    await seedWorld({ status: 'inChat' });
    await assertFails(db(X).doc('notifications/n1').set({
      id: 'n1', userId: C, type: 'job_status_update', title: 'Payment Released', body: 'Click here',
      isRead: false, createdAt: serverTimestamp(), jobId: 'j1',
    }));
  });

  test('P-H2 clients can no longer send server-only notification types (HT-015)', async () => {
    await seedWorld({ status: 'inChat' });
    for (const type of ['job_status_update', 'verification_approved', 'verification_rejected', 'job_assigned', 'appointment_scheduled']) {
      await assertFails(db(A).doc(`notifications/n-${type}`).set({
        id: `n-${type}`, userId: C, type, title: 't', body: 'b', isRead: false, createdAt: serverTimestamp(), jobId: 'j1',
      }));
    }
  });

  test('P-H3 notification without a real job relationship is rejected (HT-015)', async () => {
    await seedWorld({ status: 'inChat' });
    await assertFails(db(A2).doc('notifications/n1').set({
      id: 'n1', userId: C, type: 'message_received', title: 'New Message', body: 'hi',
      isRead: false, createdAt: serverTimestamp(), jobId: 'j1',
    }));
  });

  test('P-I artisan cannot lower own responseTimeMinutes (HT-019)', async () => {
    await seedWorld(null);
    await assertFails(db(A).doc(`artisans/${A}`).update({ responseTimeMinutes: 0 }));
  });

  test('P-I2 artisan cannot claim id_submitted without a pending verification record (HT-019)', async () => {
    await seedWorld(null, { artisans: { [A]: { verificationStatus: 'unverified' } } });
    await assertFails(db(A).doc(`artisans/${A}`).update({ verificationStatus: 'id_submitted' }));
  });

  test('P-J artisan cannot create own verification record as approved (HT-020)', async () => {
    await assertFails(db(A).doc(`verifications/${A}`).set({ uid: A, status: 'approved' }));
  });

  test('P-J2 artisan cannot flip a rejected verification to approved (HT-020)', async () => {
    await seed(async (f) => f.doc(`verifications/${A}`).set({ uid: A, status: 'rejected', reviewerId: 'adm' }));
    await assertFails(db(A).doc(`verifications/${A}`).update({ status: 'approved' }));
  });
});

describe('New Stage 1/2 findings', () => {
  test('HT-045 artisan cannot create own profile pre-verified / with fake stats', async () => {
    const d = db('a9');
    const base = { uid: 'a9', approvalStatus: 'pending', verificationStatus: 'unverified' };
    await assertFails(d.doc('artisans/a9').set({ ...base, verificationStatus: 'trusted' }));
    await assertFails(d.doc('artisans/a9').set({ ...base, rating: 5, totalRatings: 900 }));
    await assertFails(d.doc('artisans/a9').set({ ...base, trustScore: 100 }));
    await assertFails(d.doc('artisans/a9').set({ ...base, betaTester: true }));
    await assertFails(d.doc('artisans/a9').set({ ...base, completedJobs: 500 }));
  });

  test('HT-046 customer cannot create a job pre-assigned or pre-agreed', async () => {
    await seedWorld(null);
    const base = {
      id: 'j9', customerId: C, artisanId: '', category: 'Plumbing', description: 'x', imageUrls: [],
      completionImageUrls: [], status: 'requested', urgency: 'asap', createdAt: Timestamp.now(),
      agreementConfirmedByCustomer: false, agreementConfirmedByArtisan: false, updateVersion: 0,
    };
    await assertFails(db(C).doc('jobs/j9').set({ ...base, artisanId: A }));
    await assertFails(db(C).doc('jobs/j9').set({ ...base, agreementStatus: 'confirmed', agreedAmount: 1 }));
    await assertFails(db(C).doc('jobs/j9').set({ ...base, agreementConfirmedByArtisan: true }));
    await assertFails(db(C).doc('jobs/j9').set({ ...base, autoReleaseAt: Timestamp.fromMillis(0) }));
  });

  test('self-hire: a dual-role user cannot match their own artisan profile', async () => {
    await seedWorld({ status: 'requested', artisanId: '' });
    await seed(async (f) => f.doc(`artisans/${C}`).set(eligibleArtisan(C)));
    await assertFails(jobRef(C).update({
      status: 'matched', artisanId: C, matchedAt: serverTimestamp(), ...consistency('customer:cust1'),
    }));
  });

  test('slot confirmation must be one the artisan proposed (HT-031)', async () => {
    const slot = Timestamp.fromMillis(Date.UTC(2026, 11, 1, 10));
    await seedWorld({ status: 'inChat', appointmentSlots: [slot] });
    await assertFails(jobRef(C).update({
      confirmedAppointment: Timestamp.fromMillis(Date.UTC(2026, 11, 5, 10)),
      schedulingStatus: 'scheduled', schedulingUpdatedAt: serverTimestamp(), ...consistency('customer:cust1'),
    }));
  });

  test('paid cancellation request cannot change status or be filed by a stranger (D2)', async () => {
    await seedWorld({ status: 'escrowLocked' });
    const req = {
      cancellationRequestStatus: 'pending', cancellationRequestedBy: C,
      cancellationRequestReason: 'No longer needed', cancellationRequestedAt: serverTimestamp(),
      ...consistency('customer:cust1'),
    };
    await assertFails(jobRef(C).update({ ...req, status: 'cancelled' }));
    await assertFails(jobRef(X).update({ ...req, cancellationRequestedBy: X }));
    await assertFails(jobRef(C).update({ ...req, cancellationRequestedBy: A }));
  });

  test('Stage 3: clients cannot write server-owned payment fields on the job', async () => {
    await seedWorld({ status: 'paymentPending', pendingPaymentReference: 'pay_1' });
    for (const [actor, field, value] of [
      [C, 'pendingPaymentReference', 'pay_fake'],
      [C, 'paymentInitializedAt', Timestamp.fromMillis(0)],
      [A, 'paymentReference', 'pay_fake'],
      [C, 'paymentExpiredAt', Timestamp.now()],
    ]) {
      await assertFails(jobRef(actor).update({ [field]: value, ...consistency('x') }));
    }
  });

  test('Stage 3: clients cannot read or write config, orphan charges or payment init locks', async () => {
    await seedWorld(null);
    await assertFails(db(C).doc('config/platform').set({ platformFeePercent: 0 }));
    await assertFails(db(C).doc('orphan_charges/r1').get());
    await assertFails(db(C).doc('payment_init_locks/j1').set({ status: 'done' }));
  });

  test('Stage 4 D1: quotes and agreements below the minimum job value (₦3,212) are refused', async () => {
    await seedWorld({ status: 'requested', artisanId: '' });
    const q = (amount) => db(A2).doc(`jobs/j1/quotes/${A2}`).set({
      id: A2, jobId: 'j1', artisanId: A2, laborCost: amount, materialsCost: 0, amount,
      durationDays: 1, status: 'pending', artisanVerified: true, updatedAt: serverTimestamp(),
    });
    await assertFails(q(3211));
    await assertSucceeds(q(3212));
    await env.clearFirestore();
    await seedWorld({ status: 'inChat', agreementStatus: 'negotiating', agreedAmount: 3000 });
    await assertFails(jobRef(C).update({
      agreementStatus: 'pendingArtisanConfirmation', agreementScope: 'x', agreementConfirmedByCustomer: true,
      agreementCustomerConfirmedAt: serverTimestamp(), agreementUpdatedAt: serverTimestamp(), ...consistency('customer:cust1'),
    }));
  });

  test('Stage 4 D1: the minimum follows trusted backend config', async () => {
    await seedWorld({ status: 'requested', artisanId: '' });
    await seed(async (f) => f.doc('config/platform').set({ minJobValueNgn: 5000 }));
    const q = (amount) => db(A2).doc(`jobs/j1/quotes/${A2}`).set({
      id: A2, jobId: 'j1', artisanId: A2, laborCost: amount, materialsCost: 0, amount,
      durationDays: 1, status: 'pending', artisanVerified: true, updatedAt: serverTimestamp(),
    });
    await assertFails(q(4999));
    await assertSucceeds(q(5000));
  });

  test('Stage 4: an admin CLIENT cannot move money states or rewrite funded jobs', async () => {
    await seedWorld({ status: 'disputed', agreedAmount: 50000 });
    await seed(async (f) => f.doc('admins/adm').set({ grantedAt: 1 }));
    const adm = db('adm');
    await assertFails(adm.doc('jobs/j1').update({ status: 'resolved', ...consistency('admin:adm') }));
    await assertFails(adm.doc('jobs/j1').update({ status: 'cancelled', ...consistency('admin:adm') }));
    await assertFails(adm.doc('jobs/j1').update({ agreedAmount: 1, ...consistency('admin:adm') }));
    await assertFails(adm.doc('jobs/j1').update({ payoutFrozen: false, ...consistency('admin:adm') }));
    await assertFails(adm.doc('jobs/j1').delete());
    await env.clearFirestore();
    await seedWorld({ status: 'paymentPending' });
    await seed(async (f) => f.doc('admins/adm').set({ grantedAt: 1 }));
    await assertFails(db('adm').doc('jobs/j1').update({ status: 'escrowLocked', ...consistency('admin:adm') }));
  });

  test('Stage 4: an admin client may still force-cancel or delete an UNFUNDED job', async () => {
    await seedWorld({ status: 'inChat' });
    await seed(async (f) => f.doc('admins/adm').set({ grantedAt: 1 }));
    await assertSucceeds(db('adm').doc('jobs/j1').update({ status: 'cancelled', adminOverrideReason: 'spam', ...consistency('admin:adm') }));
    await assertSucceeds(db('adm').doc('jobs/j1').delete());
  });

  test('Stage 4: users cannot write their own suspension type or payout freeze', async () => {
    await seedWorld(null, { users: { [A]: { accountStatus: 'suspended', suspensionType: 'fraud', payoutFrozen: true } } });
    await assertFails(db(A).doc(`users/${A}`).update({ suspensionType: 'administrative' }));
    await assertFails(db(A).doc(`users/${A}`).update({ payoutFrozen: false }));
    await assertFails(db(A).doc(`artisans/${A}`).update({ payoutFrozen: false }));
  });

  test('Stage 4: refunds, settlements and financial events are server-only', async () => {
    await seedWorld({ status: 'completed' });
    await seed(async (f) => {
      await f.doc('refunds/pay_1').set({ jobId: 'j1', status: 'submitted' });
      await f.doc('settlements/j1').set({ jobId: 'j1' });
      await f.doc('financial_events/e1').set({ jobId: 'j1' });
    });
    for (const p of ['refunds/pay_1', 'settlements/j1', 'financial_events/e1']) {
      await assertFails(db(C).doc(p).get());
      await assertFails(db(C).doc(p).set({ hacked: true }));
    }
  });

  test('Stage 4: a customer cannot create a release once the job has been settled', async () => {
    await seedWorld({ status: 'submitted' });
    await seed(async (f) => f.doc('settlements/j1').set({ jobId: 'j1', outcome: 'full_refund' }));
    await assertFails(db(C).doc('escrow_releases/j1').set({
      jobId: 'j1', status: 'pending', requestedAt: serverTimestamp(), requestedBy: C,
    }));
  });

  test('P-L CONTROL customer cannot lock escrow directly', async () => {
    await seedWorld({ status: 'paymentPending' });
    await assertFails(jobRef(C).update({ status: 'escrowLocked', paymentReference: 'x', ...consistency('customer:cust1') }));
  });
});

describe('Suspension (policy D9) — blocks new activity, protects existing jobs', () => {
  test('suspended customer cannot post a job', async () => {
    await seedWorld(null, { users: { [C]: { accountStatus: 'suspended' } } });
    await assertFails(db(C).doc('jobs/j9').set({
      id: 'j9', customerId: C, artisanId: '', category: 'Plumbing', description: 'x', imageUrls: [],
      completionImageUrls: [], status: 'requested', urgency: 'asap', createdAt: Timestamp.now(),
      agreementConfirmedByCustomer: false, agreementConfirmedByArtisan: false, updateVersion: 0,
    }));
  });

  test('suspended artisan cannot quote', async () => {
    await seedWorld({ status: 'requested', artisanId: '' }, { users: { [A2]: { accountStatus: 'suspended' } } });
    await assertFails(db(A2).doc(`jobs/j1/quotes/${A2}`).set({
      id: A2, jobId: 'j1', artisanId: A2, amount: 1000, laborCost: 1000, materialsCost: 0,
      durationDays: 1, status: 'pending', artisanVerified: true,
    }));
  });

  test('suspended artisan cannot be hired', async () => {
    await seedWorld({ status: 'requested', artisanId: '' }, { artisans: { [A]: { accountStatus: 'suspended' } } });
    await assertFails(jobRef(C).update({
      status: 'matched', artisanId: A, matchedAt: serverTimestamp(), ...consistency('customer:cust1'),
    }));
  });

  test('administratively suspended artisan CAN still progress an existing funded job (D9 restricted mode)', async () => {
    await seedWorld({ status: 'escrowLocked' }, { users: { [A]: { accountStatus: 'suspended', suspensionType: 'administrative' } } });
    await assertSucceeds(jobRef(A).update({
      status: 'inProgress', startedAt: serverTimestamp(), ...consistency('artisan:art1'),
    }));
  });

  test('Stage 5: unclassified or fraud suspension freezes existing-job progress (fails closed)', async () => {
    for (const extra of [{}, { suspensionType: 'fraud' }, { suspensionType: 'safety' }]) {
      await env.clearFirestore();
      await seedWorld({ status: 'escrowLocked' }, { users: { [A]: { accountStatus: 'suspended', ...extra } } });
      await assertFails(jobRef(A).update({
        status: 'inProgress', startedAt: serverTimestamp(), ...consistency('artisan:art1'),
      }));
    }
  });
});

// ════════════════════════════════════════════════════════════════════════════
// RULE COST — production job docs carry ~50 fields; diff() cost scales with
// document size and the 1000-expression budget is shared across every
// `allow update` statement evaluated. Legitimate writes against a realistic,
// full-size document must still be allowed (not silently budget-denied).
// ════════════════════════════════════════════════════════════════════════════

function fullSizeJob(overrides = {}) {
  const t = Timestamp.fromMillis(Date.UTC(2026, 9, 1));
  return {
    id: 'j1', customerId: C, artisanId: A, category: 'Plumbing', description: 'Fix sink '.repeat(20),
    imageUrls: ['https://x/1.jpg', 'https://x/2.jpg', 'https://x/3.jpg'], completionImageUrls: [],
    beforePhotoUrls: [], status: 'inChat', agreedAmount: 50000, paymentReference: null,
    disputeReason: null, disputeResolution: null, artisanNotes: null,
    customerLat: 6.5244, customerLng: 3.3792, customerAddress: '12 Home Street, Ikeja, Lagos',
    budgetMin: 40000, budgetMax: 60000, urgency: 'scheduled', scheduledDate: t, createdAt: t,
    matchedAt: t, escrowLockedAt: t, startedAt: t, appointmentSlots: [t, t, t], confirmedAppointment: t,
    progressStage: 'accepted', progressUpdatedAt: t, agreementStatus: 'confirmed', agreementScope: 'Scope '.repeat(30),
    agreementConfirmedByCustomer: true, agreementConfirmedByArtisan: true,
    agreementCustomerConfirmedAt: t, agreementArtisanConfirmedAt: t, agreementChangesRequestedReason: null,
    agreementUpdatedAt: t, schedulingStatus: 'scheduled', schedulingUpdatedAt: t,
    aiSuggestion: { category: 'Plumbing', confidence: 0.92, enhancedDescription: 'x '.repeat(50) },
    escrow: { status: 'none' }, payment: { method: 'card', reference: 'r' },
    lastUpdatedAt: t, lastUpdatedBy: 'customer:cust1', updateVersion: 12,
    ...overrides,
  };
}

describe('Rule evaluation cost on full-size documents', () => {
  const seedFull = (o) => seed(async (f) => {
    await f.doc(`users/${C}`).set({ uid: C, accountStatus: 'active' });
    await f.doc(`users/${A}`).set({ uid: A, accountStatus: 'active' });
    await f.doc(`artisans/${A}`).set(eligibleArtisan(A));
    await f.doc('jobs/j1').set(fullSizeJob(o));
  });

  test('paid cancellation request (last-evaluated rule) on a full-size funded job', async () => {
    await seedFull({ status: 'inProgress' });
    await assertSucceeds(jobRef(C).update({
      cancellationRequestStatus: 'pending', cancellationRequestedBy: C,
      cancellationRequestReason: 'Artisan stopped responding', cancellationRequestedAt: serverTimestamp(),
      ...consistency('customer:cust1', 13),
    }));
  });

  test('submission, start, confirm, payment and progress on a full-size job', async () => {
    await seedFull({ status: 'inProgress' });
    await assertSucceeds(jobRef(A).update({
      status: 'submitted', completionImageUrls: ['https://x/a.jpg'], beforePhotoUrls: ['https://x/b.jpg'],
      artisanNotes: 'Done', submittedAt: serverTimestamp(), ...consistency('artisan:art1', 13),
    }));
    await env.clearFirestore(); await seedFull({ status: 'inProgress' });
    await assertSucceeds(jobRef(A).update({ progressStage: 'halfDone', progressUpdatedAt: serverTimestamp(), ...consistency('artisan:art1', 13) }));
    await env.clearFirestore(); await seedFull({ status: 'escrowLocked' });
    await assertSucceeds(jobRef(A).update({ status: 'inProgress', startedAt: serverTimestamp(), ...consistency('artisan:art1', 13) }));
    await env.clearFirestore(); await seedFull({ status: 'submitted' });
    await assertSucceeds(jobRef(C).update({ status: 'completed', completedAt: serverTimestamp(), ...consistency('customer:cust1', 13) }));
    await env.clearFirestore(); await seedFull({ status: 'inChat' });
    await assertSucceeds(jobRef(C).update({ status: 'paymentPending', ...consistency('customer:cust1', 13) }));
  });

  test('agreement and scheduling sub-state writes on a full-size job', async () => {
    const t = Timestamp.fromMillis(Date.UTC(2026, 9, 1));
    await seedFull({ status: 'inChat', agreementStatus: 'negotiating', appointmentSlots: [t] });
    await assertSucceeds(jobRef(C).update({
      confirmedAppointment: t, schedulingStatus: 'scheduled', schedulingUpdatedAt: serverTimestamp(),
      ...consistency('customer:cust1', 13),
    }));
    await assertSucceeds(jobRef(C).update({
      agreementStatus: 'pendingArtisanConfirmation', agreementScope: 'x', agreementConfirmedByCustomer: true,
      agreementCustomerConfirmedAt: serverTimestamp(), agreementUpdatedAt: serverTimestamp(),
      ...consistency('customer:cust1', 14),
    }));
    await assertSucceeds(jobRef(A).update({
      agreementStatus: 'changesRequested', agreementChangesRequestedReason: 'price', agreementConfirmedByArtisan: false,
      agreementUpdatedAt: serverTimestamp(), ...consistency('artisan:art1', 15),
    }));
  });
});

// ════════════════════════════════════════════════════════════════════════════
// LEGITIMATE — exact payloads the shipped client writes must keep working
// ════════════════════════════════════════════════════════════════════════════

describe('Legitimate client payloads (no regression)', () => {
  test('customer posts a job (JobModel.toJson + FirestoreRepository.createJob)', async () => {
    await seedWorld(null);
    await assertSucceeds(db(C).doc('jobs/j9').set({
      id: 'j9', customerId: C, artisanId: '', category: 'Plumbing', description: 'Leaking pipe under sink',
      imageUrls: [], completionImageUrls: [], status: 'requested', customerLat: 6.5, customerLng: 3.4,
      customerAddress: '12 Home St', budgetMin: 5000, budgetMax: 10000, urgency: 'scheduled',
      scheduledDate: Timestamp.now(), createdAt: Timestamp.now(),
      agreementConfirmedByCustomer: false, agreementConfirmedByArtisan: false,
      aiSuggestion: { category: 'Plumbing', confidence: 0.9, enhancedDescription: 'x' },
      updateVersion: 0, lastUpdatedAt: serverTimestamp(), lastUpdatedBy: 'customer',
    }));
  });

  test('artisan submits a quote (QuoteService.submitQuote)', async () => {
    await seedWorld({ status: 'requested', artisanId: '' });
    await assertSucceeds(db(A2).doc(`jobs/j1/quotes/${A2}`).set({
      id: A2, jobId: 'j1', artisanId: A2, laborCost: 8000, materialsCost: 2000, amount: 10000,
      durationDays: 2, status: 'pending', createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
      artisanName: 'Art2', artisanRating: 0, artisanTrustTier: 'New', artisanVerified: true, artisanTrustScore: 0,
    }));
  });

  test('customer accepts a quote: requested->matched + quote updates in one transaction (JobService.acceptQuote)', async () => {
    await seedWorld({ status: 'requested', artisanId: '' });
    await seed(async (f) => {
      await f.doc(`jobs/j1/quotes/${A}`).set({ artisanId: A, status: 'pending', amount: 10000, updatedAt: Timestamp.now() });
      await f.doc(`jobs/j1/quotes/${A2}`).set({ artisanId: A2, status: 'pending', amount: 12000, updatedAt: Timestamp.now() });
    });
    const d = db(C);
    await assertSucceeds(d.runTransaction(async (tx) => {
      const j = d.doc('jobs/j1');
      await tx.get(j);
      tx.update(j, { status: 'matched', artisanId: A, matchedAt: serverTimestamp(), bookingStatus: 'awaitingArtisan', ...consistency('customer:cust1') });
      tx.update(d.doc(`jobs/j1/quotes/${A}`), { status: 'accepted' });
      tx.update(d.doc(`jobs/j1/quotes/${A2}`), { status: 'closed' });
      tx.set(d.doc('jobs/j1/auditLogs/l1'), { id: 'l1', jobId: 'j1', actorId: C, timestamp: serverTimestamp(), isAdminOverride: false });
    }));
  });

  test('Stage 5 D7: artisan confirms the booking (matched->inChat) within 24 h; customer cannot skip it', async () => {
    await seedWorld({ status: 'matched', matchedAt: Timestamp.now(), bookingStatus: 'awaitingArtisan' });
    await assertFails(jobRef(C).update({ status: 'inChat', ...consistency('customer:cust1') }));
    await assertSucceeds(jobRef(A).update({
      status: 'inChat', bookingStatus: 'confirmed', bookingConfirmedAt: serverTimestamp(), ...consistency('artisan:art1'),
    }));
  });

  test('Stage 5 D7: customer may open chat on an already-confirmed (migrated legacy) booking', async () => {
    await seedWorld({ status: 'matched', bookingStatus: 'confirmed' });
    await assertSucceeds(jobRef(C).update({ status: 'inChat', ...consistency('customer:cust1') }));
  });

  test('either party proposes a price while negotiating (JobService.sendNegotiation)', async () => {
    await seedWorld({ status: 'inChat', agreementStatus: 'negotiating' });
    await assertSucceeds(jobRef(A).update({ agreedAmount: 45000, ...consistency('artisan:art1') }));
  });

  test('customer confirms, artisan accepts the agreement (confirmAgreementAsCustomer / acceptAgreementAsArtisan)', async () => {
    await seedWorld({ status: 'inChat', agreementStatus: 'negotiating', agreedAmount: 45000 });
    await assertSucceeds(jobRef(C).update({
      agreementStatus: 'pendingArtisanConfirmation', agreementScope: 'Fix sink', agreementConfirmedByCustomer: true,
      agreementCustomerConfirmedAt: serverTimestamp(), agreementUpdatedAt: serverTimestamp(),
      agreedAmount: 50000, ...consistency('customer:cust1'),
    }));
    await assertSucceeds(jobRef(A).update({
      agreementStatus: 'confirmed', agreementConfirmedByArtisan: true, agreementArtisanConfirmedAt: serverTimestamp(),
      agreementUpdatedAt: serverTimestamp(), ...consistency('artisan:art1', 2),
    }));
  });

  test('price is frozen once the agreement is confirmed', async () => {
    await seedWorld({ status: 'inChat', agreementStatus: 'confirmed', agreedAmount: 50000 });
    await assertFails(jobRef(C).update({ agreedAmount: 100, ...consistency('customer:cust1') }));
  });

  test('artisan proposes slots, customer confirms one of them (HT-031 legit path)', async () => {
    const slot = Timestamp.fromMillis(Date.UTC(2026, 11, 1, 10));
    await seedWorld({ status: 'inChat' });
    await assertSucceeds(jobRef(A).update({ appointmentSlots: [slot], ...consistency('artisan:art1') }));
    await assertSucceeds(jobRef(C).update({
      confirmedAppointment: slot, schedulingStatus: 'scheduled', schedulingUpdatedAt: serverTimestamp(),
      ...consistency('customer:cust1', 2),
    }));
  });

  test('NEW client: inChat->paymentPending writes status only (JobService.initPayment, Stage 2)', async () => {
    await seedWorld({ status: 'inChat', agreementStatus: 'confirmed', agreedAmount: 50000, urgency: 'asap' });
    await assertSucceeds(jobRef(C).update({ status: 'paymentPending', ...consistency('customer:cust1') }));
  });

  test('OLD client: inChat->paymentPending re-sending the SAME agreedAmount still works (compat B-1)', async () => {
    await seedWorld({ status: 'inChat', agreementStatus: 'confirmed', agreedAmount: 50000, urgency: 'asap' });
    await assertSucceeds(jobRef(C).update({ status: 'paymentPending', agreedAmount: 50000, ...consistency('customer:cust1') }));
  });

  test('artisan starts work escrowLocked->inProgress (JobService.startWork)', async () => {
    await seedWorld({ status: 'escrowLocked' });
    await assertSucceeds(jobRef(A).update({ status: 'inProgress', startedAt: serverTimestamp(), ...consistency('artisan:art1') }));
  });

  test('NEW client: artisan submits completion without timers (JobService.submitCompletion, Stage 2)', async () => {
    await seedWorld({ status: 'inProgress' });
    await assertSucceeds(jobRef(A).update({
      status: 'submitted', completionImageUrls: ['https://x/after.jpg'], beforePhotoUrls: ['https://x/before.jpg'],
      artisanNotes: 'Done', submittedAt: serverTimestamp(), ...consistency('artisan:art1'),
    }));
  });

  test('OLD client: submission with device-computed now+14d timers still works (compat B-2)', async () => {
    await seedWorld({ status: 'inProgress' });
    const in14d = Timestamp.fromMillis(Date.now() + 14 * 24 * 3600 * 1000);
    await assertSucceeds(jobRef(A).update({
      status: 'submitted', completionImageUrls: ['https://x/after.jpg'], submittedAt: serverTimestamp(),
      disputeWindowEndsAt: in14d, autoReleaseAt: in14d, ...consistency('artisan:art1'),
    }));
  });

  test('customer confirms completion + creates release atomically (JobService.confirmComplete)', async () => {
    await seedWorld({ status: 'submitted' });
    const d = db(C);
    await assertSucceeds(d.runTransaction(async (tx) => {
      const j = d.doc('jobs/j1');
      await tx.get(j);
      tx.update(j, { status: 'completed', completedAt: serverTimestamp(), ...consistency('customer:cust1') });
      tx.set(d.doc('escrow_releases/j1'), { jobId: 'j1', requestedAt: serverTimestamp(), status: 'pending', requestedBy: C });
      tx.set(d.doc('jobs/j1/auditLogs/l1'), { id: 'l1', jobId: 'j1', actorId: C, timestamp: serverTimestamp(), isAdminOverride: false });
    }));
  });

  test('customer raises a dispute + record atomically (JobService.raiseDisputeWithRecord)', async () => {
    await seedWorld({ status: 'submitted' });
    const d = db(C);
    await assertSucceeds(d.runTransaction(async (tx) => {
      const j = d.doc('jobs/j1');
      await tx.get(j);
      tx.update(j, { status: 'disputed', disputeReason: 'Leak not fixed', ...consistency('customer:cust1') });
      tx.set(d.doc('disputes/d1'), {
        id: 'd1', jobId: 'j1', raisedBy: C, againstUserId: A, reason: 'Leak not fixed',
        evidenceImageUrls: [], status: 'open', createdAt: serverTimestamp(),
      });
    }));
  });

  test('either party cancels before payment (JobService.cancelJob)', async () => {
    for (const [status, actor, role] of [['requested', C, 'customer'], ['matched', C, 'customer'], ['inChat', C, 'customer'], ['paymentPending', C, 'customer']]) {
      await env.clearFirestore();
      await seedWorld({ status, artisanId: status === 'requested' ? '' : A });
      await assertSucceeds(jobRef(actor).update({
        status: 'cancelled', cancelledBy: actor, cancellationReason: 'Other', cancelledAt: serverTimestamp(),
        ...consistency(`${role}:${actor}`),
      }));
    }
  });

  test('Stage 5 D6: an artisan cannot cancel (kill) a job before payment — withdrawal reopens it server-side', async () => {
    for (const status of ['matched', 'inChat', 'paymentPending']) {
      await env.clearFirestore();
      await seedWorld({ status });
      await assertFails(jobRef(A).update({
        status: 'cancelled', cancelledBy: A, cancelledAt: serverTimestamp(), ...consistency('artisan:art1'),
      }));
    }
  });

  test('party requests cancellation of a funded job for admin review (D2, JobService.requestPaidCancellation)', async () => {
    for (const [status, actor] of [['escrowLocked', C], ['inProgress', A]]) {
      await env.clearFirestore();
      await seedWorld({ status });
      await assertSucceeds(jobRef(actor).update({
        cancellationRequestStatus: 'pending', cancellationRequestedBy: actor,
        cancellationRequestReason: 'Other', cancellationRequestedAt: serverTimestamp(),
        ...consistency(`x:${actor}`),
      }));
      // A second request while one is pending is rejected (no overwrite of the first).
      await assertFails(jobRef(actor === C ? A : C).update({
        cancellationRequestStatus: 'pending', cancellationRequestedBy: actor === C ? A : C,
        cancellationRequestReason: 'Other', cancellationRequestedAt: serverTimestamp(),
        ...consistency('x', 2),
      }));
    }
  });

  test('customer leaves one review (review_screen.dart)', async () => {
    await seedWorld({ status: 'completed' });
    await assertSucceeds(db(C).doc('reviews/j1').set({
      id: 'j1', jobId: 'j1', customerId: C, artisanId: A, rating: 4, comment: 'Good', createdAt: Timestamp.now(),
    }));
  });

  test('artisan registers (artisan_registration_screen.dart create payload)', async () => {
    await assertSucceeds(db('a9').doc('artisans/a9').set({
      bio: 'b', skills: 's', location: 'Lagos', category: 'Plumbing', approvalStatus: 'pending',
      verificationStatus: 'unverified', isAvailable: false, rating: 0.0, totalRatings: 0, totalJobs: 0,
      completedJobs: 0, responseTimeMinutes: 30.0, trustScore: 0.0, portfolioImageUrls: [],
      uid: 'a9', name: 'A9', email: 'a9@x.com', roles: ['artisan'], activeRole: 'artisan',
      isVerified: false, createdAt: serverTimestamp(),
    }));
  });

  test('artisan submits verification (VerificationService.submit batch)', async () => {
    await seedWorld(null, { artisans: { [A]: { verificationStatus: 'unverified' } } });
    const d = db(A);
    const b = d.batch();
    b.set(d.doc(`verifications/${A}`), {
      uid: A, selfieUrl: 's', governmentIdUrl: 'g', submittedAt: serverTimestamp(),
      reviewedAt: null, reviewerId: null, rejectionReason: null, status: 'pending',
    });
    b.set(d.doc(`artisans/${A}`), { verificationStatus: 'id_submitted' }, { merge: true });
    b.set(d.doc(`users/${A}`), { verificationStatus: 'id_submitted' }, { merge: true });
    await assertSucceeds(b.commit());
  });

  test('artisan resubmits after rejection, and defers verification (VerificationService)', async () => {
    await seedWorld(null, { artisans: { [A]: { verificationStatus: 'unverified' } } });
    await seed(async (f) => f.doc(`verifications/${A}`).set({ uid: A, status: 'rejected', reviewerId: 'adm', rejectionReason: 'blurry' }));
    const d = db(A);
    const b = d.batch();
    b.set(d.doc(`verifications/${A}`), { uid: A, status: 'pending_later' }, { merge: true });
    b.set(d.doc(`artisans/${A}`), { verificationStatus: 'pending_later' }, { merge: true });
    await assertSucceeds(b.commit());
  });

  test('Stage 6: even the two job parties can no longer create notifications (server-generated only)', async () => {
    await seedWorld({ status: 'inChat' });
    const n = (id, from, to, type) => db(from).doc(`notifications/${id}`).set({
      id, userId: to, type, title: 't', body: 'b', isRead: false, createdAt: serverTimestamp(), jobId: 'j1',
    });
    await assertFails(n('n1', C, A, 'agreement_pending'));
    await assertFails(n('n2', A, C, 'agreement_accepted'));
    await assertFails(n('n3', A, C, 'message_received'));
    await assertFails(n('n4', C, A, 'dispute_raised'));
  });

  test('Stage 6: pre-match quote/chat notifications are server-generated only', async () => {
    await seedWorld({ status: 'requested', artisanId: '' });
    await seed(async (f) => f.doc(`jobs/j1/quotes/${A2}`).set({ artisanId: A2, status: 'pending', amount: 1 }));
    const n = (id, from, to, type) => db(from).doc(`notifications/${id}`).set({
      id, userId: to, type, title: 't', body: 'b', isRead: false, createdAt: serverTimestamp(), jobId: 'j1',
    });
    await assertFails(n('n1', A2, C, 'quote_received'));
    await assertFails(n('n2', A2, C, 'quote_withdrawn'));
    await assertFails(n('n3', C, A2, 'quote_rejected'));
    await assertFails(n('n4', A2, C, 'message_received'));
    await assertFails(n('n5', C, A2, 'message_received'));
  });

  test('Stage 6: quote_accepted can no longer be client-written', async () => {
    await seedWorld({ status: 'matched' });
    await assertFails(db(C).doc('notifications/n1').set({
      id: 'n1', userId: A, type: 'quote_accepted', title: 't', body: 'b', isRead: false,
      createdAt: serverTimestamp(), jobId: 'j1',
    }));
  });

  test('pre-match interested-artisan chat message still works', async () => {
    await seedWorld({ status: 'requested', artisanId: '' });
    await assertSucceeds(db(A2).doc('jobs/j1/messages/m1').set({
      id: 'm1', jobId: 'j1', senderId: A2, receiverId: C, text: 'hi', type: 'text', isRead: false, createdAt: serverTimestamp(),
    }));
  });
});

// ════════════════════════════════════════════════════════════════════════════
// STAGE 5 — lifecycle completion (bookings, quotes, rework, disputes,
// suspension modes). design/REMEDIATION_STAGE5_REPORT_2026-11-03.md
// ════════════════════════════════════════════════════════════════════════════
const H = 60 * 60 * 1000;
const ago = (ms) => Timestamp.fromMillis(Date.now() - ms);

describe('Stage 5 — booking confirmation (D7, D5 24 h)', () => {
  const confirm = (uid) => jobRef(uid).update({
    status: 'inChat', bookingStatus: 'confirmed', bookingConfirmedAt: serverTimestamp(), ...consistency(`artisan:${uid}`),
  });

  test('artisan confirms within 24 h of the server-stamped match', async () => {
    await seedWorld({ status: 'matched', matchedAt: ago(23 * H), bookingStatus: 'awaitingArtisan' });
    await assertSucceeds(confirm(A));
  });

  test('confirmation after the 24 h window is refused', async () => {
    await seedWorld({ status: 'matched', matchedAt: ago(25 * H), bookingStatus: 'awaitingArtisan' });
    await assertFails(confirm(A));
  });

  test('the window follows trusted config (bookingConfirmationHours = 48)', async () => {
    await seedWorld({ status: 'matched', matchedAt: ago(25 * H), bookingStatus: 'awaitingArtisan' });
    await seed(async (f) => f.doc('config/platform').set({ bookingConfirmationHours: 48 }));
    await assertSucceeds(confirm(A));
  });

  test('only the matched artisan can confirm; the customer cannot self-confirm', async () => {
    await seedWorld({ status: 'matched', matchedAt: ago(H), bookingStatus: 'awaitingArtisan' });
    await assertFails(confirm(A2));
    await assertFails(jobRef(C).update({
      status: 'inChat', bookingStatus: 'confirmed', bookingConfirmedAt: serverTimestamp(), ...consistency('customer:cust1'),
    }));
  });

  test('a customer cannot create a match that is already confirmed', async () => {
    await seedWorld({ status: 'requested', artisanId: '' });
    await assertFails(jobRef(C).update({
      status: 'matched', artisanId: A, matchedAt: serverTimestamp(), bookingStatus: 'confirmed', ...consistency('customer:cust1'),
    }));
  });

  test('client-time bookingConfirmedAt is refused', async () => {
    await seedWorld({ status: 'matched', matchedAt: ago(H), bookingStatus: 'awaitingArtisan' });
    await assertFails(jobRef(A).update({
      status: 'inChat', bookingStatus: 'confirmed', bookingConfirmedAt: Timestamp.fromMillis(0), ...consistency('artisan:art1'),
    }));
  });
});

describe('Stage 5 — quotation validity (D5 48 h)', () => {
  const acceptTx = async () => {
    const d = db(C);
    return d.runTransaction(async (tx) => {
      const j = d.doc('jobs/j1');
      await tx.get(j);
      tx.update(j, { status: 'matched', artisanId: A, matchedAt: serverTimestamp(), bookingStatus: 'awaitingArtisan', ...consistency('customer:cust1') });
      tx.update(d.doc(`jobs/j1/quotes/${A}`), { status: 'accepted' });
    });
  };

  test('an expired quote (49 h) cannot be accepted', async () => {
    await seedWorld({ status: 'requested', artisanId: '' });
    await seed(async (f) => f.doc(`jobs/j1/quotes/${A}`).set({ artisanId: A, status: 'pending', amount: 10000, updatedAt: ago(49 * H) }));
    await assertFails(acceptTx());
  });

  test('a quote inside its validity can be accepted', async () => {
    await seedWorld({ status: 'requested', artisanId: '' });
    await seed(async (f) => f.doc(`jobs/j1/quotes/${A}`).set({ artisanId: A, status: 'pending', amount: 10000, updatedAt: ago(47 * H) }));
    await assertSucceeds(acceptTx());
  });

  test('a quote without a server-stamped submission time is refused', async () => {
    await seedWorld({ status: 'requested', artisanId: '' });
    await assertFails(db(A2).doc(`jobs/j1/quotes/${A2}`).set({
      id: A2, jobId: 'j1', artisanId: A2, laborCost: 10000, materialsCost: 0, amount: 10000,
      durationDays: 1, status: 'pending', artisanVerified: true, updatedAt: Timestamp.fromMillis(Date.now() + 99 * H),
    }));
  });

  test('an artisan may resubmit an expired quote (restarts validity)', async () => {
    await seedWorld({ status: 'requested', artisanId: '' });
    await seed(async (f) => f.doc(`jobs/j1/quotes/${A2}`).set({
      id: A2, jobId: 'j1', artisanId: A2, laborCost: 10000, materialsCost: 0, amount: 10000,
      durationDays: 1, status: 'expired', artisanVerified: true, updatedAt: ago(60 * H),
    }));
    await assertSucceeds(db(A2).doc(`jobs/j1/quotes/${A2}`).update({ status: 'pending', updatedAt: serverTimestamp() }));
  });
});

describe('Stage 5 — rework (D4: one request, reason, server time)', () => {
  const rework = (uid, o = {}) => jobRef(uid).update({
    status: 'inProgress', reworkCount: 1, reworkReason: 'The tap still drips under load.',
    reworkRequestedAt: serverTimestamp(), ...consistency('customer:cust1'), ...o,
  });

  test('customer requests rework once with a reason', async () => {
    await seedWorld({ status: 'submitted' });
    await assertSucceeds(rework(C));
  });

  test('a second rework request is refused', async () => {
    await seedWorld({ status: 'submitted', reworkCount: 1 });
    await assertFails(rework(C, { reworkCount: 2 }));
    await assertFails(rework(C));
  });

  test('reason required, server time required, customer only', async () => {
    await seedWorld({ status: 'submitted' });
    await assertFails(rework(C, { reworkReason: 'bad' }));
    await assertFails(rework(C, { reworkRequestedAt: Timestamp.fromMillis(0) }));
    await assertFails(rework(A));
  });

  test('a completed job can never be reopened by a client', async () => {
    await seedWorld({ status: 'completed' });
    await assertFails(rework(C));
    await assertFails(jobRef(C).update({ status: 'submitted', ...consistency('customer:cust1') }));
    await assertFails(jobRef(A).update({ status: 'inProgress', ...consistency('artisan:art1') }));
  });

  test('rework cannot carry payout or timer fields', async () => {
    await seedWorld({ status: 'submitted' });
    await assertFails(rework(C, { autoReleaseAt: Timestamp.fromMillis(0) }));
    await assertFails(rework(C, { agreedAmount: 1 }));
  });

  test('artisan responds once; resubmission is the normal submit', async () => {
    await seedWorld({ status: 'inProgress', reworkCount: 1, reworkReason: 'fix it properly please' });
    await assertSucceeds(jobRef(A).update({ reworkResponse: 'Coming Tuesday', reworkRespondedAt: serverTimestamp(), ...consistency('artisan:art1') }));
    await env.clearFirestore();
    await seedWorld({ status: 'inProgress', reworkCount: 1, reworkResponse: 'already replied' });
    await assertFails(jobRef(A).update({ reworkResponse: 'again', reworkRespondedAt: serverTimestamp(), ...consistency('artisan:art1') }));
    await assertSucceeds(jobRef(A).update({
      status: 'submitted', completionImageUrls: ['https://x/after2.jpg'], submittedAt: serverTimestamp(), ...consistency('artisan:art1'),
    }));
  });
});

describe('Stage 5 — disputes from either party (D3)', () => {
  const raise = (uid, against) => {
    const d = db(uid);
    return d.runTransaction(async (tx) => {
      const j = d.doc('jobs/j1');
      await tx.get(j);
      tx.update(j, { status: 'disputed', disputeReason: 'Customer is unreachable', ...consistency(`x:${uid}`) });
      tx.set(d.doc('disputes/d1'), {
        id: 'd1', jobId: 'j1', raisedBy: uid, againstUserId: against, reason: 'x', evidenceImageUrls: [], status: 'open', createdAt: serverTimestamp(),
      });
    });
  };
  test('the artisan can raise a dispute against the customer', async () => {
    await seedWorld({ status: 'inProgress' });
    await assertSucceeds(raise(A, C));
  });
  test('a dispute must be against the other party', async () => {
    await seedWorld({ status: 'inProgress' });
    await assertFails(raise(A, A2));
    await assertFails(raise(X, C));
  });
});

describe('Stage 5 — suspension modes on existing jobs (D9)', () => {
  const frozenCustomer = { users: { [C]: { accountStatus: 'suspended', suspensionType: 'fraud' } } };
  const adminCustomer = { users: { [C]: { accountStatus: 'suspended', suspensionType: 'administrative' } } };

  test('fraud-suspended customer cannot confirm completion, pay, rework or chat', async () => {
    await seedWorld({ status: 'submitted' }, frozenCustomer);
    await assertFails(jobRef(C).update({ status: 'completed', completedAt: serverTimestamp(), ...consistency('customer:cust1') }));
    await assertFails(jobRef(C).update({
      status: 'inProgress', reworkCount: 1, reworkReason: 'needs fixing badly', reworkRequestedAt: serverTimestamp(), ...consistency('customer:cust1'),
    }));
    await assertFails(db(C).doc('jobs/j1/messages/m1').set({
      id: 'm1', jobId: 'j1', senderId: C, receiverId: A, text: 'hi', type: 'text', isRead: false, createdAt: serverTimestamp(),
    }));
    await env.clearFirestore();
    await seedWorld({ status: 'inChat', agreementStatus: 'confirmed', agreedAmount: 50000, urgency: 'asap' }, frozenCustomer);
    await assertFails(jobRef(C).update({ status: 'paymentPending', ...consistency('customer:cust1') }));
  });

  test('fraud-suspended customer CAN still exit unfunded work and open a dispute', async () => {
    await seedWorld({ status: 'inChat' }, frozenCustomer);
    await assertSucceeds(jobRef(C).update({ status: 'cancelled', cancelledBy: C, cancelledAt: serverTimestamp(), ...consistency('customer:cust1') }));
    await env.clearFirestore();
    await seedWorld({ status: 'submitted' }, frozenCustomer);
    await assertSucceeds(jobRef(C).update({ status: 'disputed', disputeReason: 'problem', ...consistency('customer:cust1') }));
  });

  test('administratively suspended customer can complete an existing job and chat (restricted mode)', async () => {
    await seedWorld({ status: 'submitted' }, adminCustomer);
    await assertSucceeds(db(C).doc('jobs/j1/messages/m1').set({
      id: 'm1', jobId: 'j1', senderId: C, receiverId: A, text: 'thanks', type: 'text', isRead: false, createdAt: serverTimestamp(),
    }));
    await assertSucceeds(jobRef(C).update({ status: 'completed', completedAt: serverTimestamp(), ...consistency('customer:cust1') }));
  });

  test('verification-suspended artisan can progress existing work but not take new work', async () => {
    const verif = { users: { [A]: { accountStatus: 'suspended', suspensionType: 'verification' } } };
    await seedWorld({ status: 'inProgress' }, verif);
    await assertSucceeds(jobRef(A).update({
      status: 'submitted', completionImageUrls: ['https://x/a.jpg'], submittedAt: serverTimestamp(), ...consistency('artisan:art1'),
    }));
    await env.clearFirestore();
    await seedWorld({ status: 'requested', artisanId: '' }, { users: { [A2]: { accountStatus: 'suspended', suspensionType: 'verification' } } });
    await assertFails(db(A2).doc(`jobs/j1/quotes/${A2}`).set({
      id: A2, jobId: 'j1', artisanId: A2, laborCost: 10000, materialsCost: 0, amount: 10000,
      durationDays: 1, status: 'pending', artisanVerified: true, updatedAt: serverTimestamp(),
    }));
  });

  test('fraud-suspended artisan cannot confirm a booking or agreement', async () => {
    const frozenArtisan = { users: { [A]: { accountStatus: 'suspended', suspensionType: 'security' } } };
    await seedWorld({ status: 'matched', matchedAt: ago(H), bookingStatus: 'awaitingArtisan' }, frozenArtisan);
    await assertFails(jobRef(A).update({
      status: 'inChat', bookingStatus: 'confirmed', bookingConfirmedAt: serverTimestamp(), ...consistency('artisan:art1'),
    }));
    await env.clearFirestore();
    await seedWorld({ status: 'inChat', agreementStatus: 'pendingArtisanConfirmation', agreedAmount: 50000 }, frozenArtisan);
    await assertFails(jobRef(A).update({
      agreementStatus: 'confirmed', agreementConfirmedByArtisan: true, agreementArtisanConfirmedAt: serverTimestamp(),
      agreementUpdatedAt: serverTimestamp(), ...consistency('artisan:art1'),
    }));
  });
});

describe('Stage 5 — server-only lifecycle fields and review eligibility', () => {
  test('clients cannot expire, reopen or re-assign a job', async () => {
    await seedWorld({ status: 'requested', artisanId: '' });
    await assertFails(jobRef(C).update({ status: 'expired', ...consistency('customer:cust1') }));
    await assertFails(jobRef(C).update({ reopenedAt: serverTimestamp(), ...consistency('customer:cust1') }));
    await env.clearFirestore();
    await seedWorld({ status: 'inChat' });
    await assertFails(jobRef(C).update({ status: 'requested', artisanId: '', ...consistency('customer:cust1') }));
  });

  test('no review before the job is completed', async () => {
    for (const status of ['submitted', 'inProgress', 'disputed']) {
      await env.clearFirestore();
      await seedWorld({ status });
      await assertFails(db(C).doc('reviews/j1').set({
        id: 'j1', jobId: 'j1', customerId: C, artisanId: A, rating: 5, comment: '', createdAt: Timestamp.now(),
      }));
    }
  });
});

// ════════════════════════════════════════════════════════════════════════════
// STAGE 6 — location privacy, service area, audit-log integrity
// ════════════════════════════════════════════════════════════════════════════
describe('Stage 6 — private job location (P-K, D9)', () => {
  const seedPrivate = (job) => seed(async (f) => {
    await f.doc('jobs/j1/private/location').set({ customerAddress: '12 Home Street, Ikeja, Lagos', customerLat: 6.52, customerLng: 3.38 });
    await f.doc(`artisans/${A2}`).set(eligibleArtisan(A2));
  }).then(() => job);

  test('open job: an artisan account cannot read the exact location (closes P-K)', async () => {
    await seedWorld({ status: 'requested', artisanId: '', areaLat: 6.52, areaLng: 3.38, areaLabel: 'Ikeja, Lagos' });
    await seedPrivate();
    await assertFails(db(A2).doc('jobs/j1/private/location').get());
    await assertSucceeds(db(A2).doc('jobs/j1').get()); // the coarse area stays visible
  });

  test('booking requested but not confirmed: the matched artisan still cannot read it', async () => {
    await seedWorld({ status: 'matched', bookingStatus: 'awaitingArtisan' });
    await seedPrivate();
    await assertFails(db(A).doc('jobs/j1/private/location').get());
  });

  test('after confirmation the assigned artisan can; the customer always can; others never', async () => {
    await seedWorld({ status: 'inChat', bookingStatus: 'confirmed' });
    await seedPrivate();
    await assertSucceeds(db(A).doc('jobs/j1/private/location').get());
    await assertSucceeds(db(C).doc('jobs/j1/private/location').get());
    await assertFails(db(A2).doc('jobs/j1/private/location').get());
    await assertFails(db(X).doc('jobs/j1/private/location').get());
  });

  test('NEW client: job (coarse area) + private location created together (FirestoreRepository.createJob)', async () => {
    await seedWorld(null);
    const d = db(C);
    const b = d.batch();
    b.set(d.doc('jobs/j9'), {
      id: 'j9', customerId: C, artisanId: '', category: 'Plumbing', description: 'x', imageUrls: [],
      completionImageUrls: [], status: 'requested', urgency: 'asap', createdAt: Timestamp.now(),
      agreementConfirmedByCustomer: false, agreementConfirmedByArtisan: false, updateVersion: 0,
      lastUpdatedAt: serverTimestamp(), lastUpdatedBy: 'customer',
      areaLat: 6.52, areaLng: 3.38, areaGeohash3: 's14', areaGeohash4: 's14j', areaLabel: 'Ikeja, Lagos',
    });
    b.set(d.doc('jobs/j9/private/location'), { customerAddress: '12 Home Street, Ikeja, Lagos', customerLat: 6.524, customerLng: 3.379 });
    await assertSucceeds(b.commit());
  });

  test('only the customer can write the private location, and only while the job is open', async () => {
    await seedWorld({ status: 'requested', artisanId: '' });
    await assertFails(db(A2).doc('jobs/j1/private/location').set({ customerAddress: 'fake' }));
    await assertSucceeds(db(C).doc('jobs/j1/private/location').set({ customerAddress: 'new address' }));
    await env.clearFirestore();
    await seedWorld({ status: 'inChat' });
    await assertFails(db(C).doc('jobs/j1/private/location').set({ customerAddress: 'moved after booking' }));
  });
});

describe('Stage 6 — artisan service area (D8)', () => {
  test('artisan sets location, address and a radius within the configured maximum', async () => {
    await seedWorld(null);
    await assertSucceeds(db(A).doc(`artisans/${A}`).update({
      latitude: 6.52, longitude: 3.38, serviceGeohash3: 's14', serviceGeohash4: 's14j',
      serviceAddress: 'Ikeja, Lagos', serviceRadiusKm: 15, serviceLocationUpdatedAt: serverTimestamp(),
    }));
  });

  test('radius above the configured maximum, bad coordinates or a client timestamp are refused', async () => {
    await seedWorld(null);
    await assertFails(db(A).doc(`artisans/${A}`).update({ serviceRadiusKm: 26 }));
    await assertFails(db(A).doc(`artisans/${A}`).update({ latitude: 95 }));
    await assertFails(db(A).doc(`artisans/${A}`).update({ serviceLocationUpdatedAt: Timestamp.fromMillis(0) }));
    await seed(async (f) => f.doc('config/platform').set({ maxServiceRadiusKm: 40 }));
    await assertSucceeds(db(A).doc(`artisans/${A}`).update({ serviceRadiusKm: 30 }));
  });
});

describe('Stage 6 — audit-log integrity (HT-028)', () => {
  const entry = (o = {}) => ({ id: 'l1', jobId: 'j1', actorId: C, timestamp: serverTimestamp(), isAdminOverride: false, ...o });
  test('a party writes an entry in its own name with server time', async () => {
    await seedWorld({ status: 'inChat' });
    await assertSucceeds(db(C).doc('jobs/j1/auditLogs/l1').set(entry()));
  });
  test('forged actor, foreign job id, backdated time or a fake admin override are refused', async () => {
    await seedWorld({ status: 'inChat' });
    await assertFails(db(C).doc('jobs/j1/auditLogs/l1').set(entry({ actorId: A })));
    await assertFails(db(C).doc('jobs/j1/auditLogs/l1').set(entry({ jobId: 'other' })));
    await assertFails(db(C).doc('jobs/j1/auditLogs/l1').set(entry({ timestamp: Timestamp.fromMillis(0) })));
    await assertFails(db(C).doc('jobs/j1/auditLogs/l1').set(entry({ isAdminOverride: true })));
    await assertFails(db(X).doc('jobs/j1/auditLogs/l1').set(entry({ actorId: X })));
  });
});

describe('Stage 7.1 — chargebacks (F-1): server-only case records and hold flags', () => {
  beforeEach(async () => {
    await seedWorld({ status: 'escrowLocked', chargebackHold: true, chargebackStatus: 'open' });
    await seed(async (f) => {
      await f.doc('admins/adm').set({ grantedAt: 1 });
      await f.doc('chargebacks/9001').set({ disputeId: '9001', jobId: 'j1', status: 'open' });
      await f.doc('chargebacks/9001/events/e1').set({ event: 'charge.dispute.create' });
    });
  });

  test('only admins can read chargeback cases and their event log', async () => {
    for (const uid of [C, A, X]) {
      await assertFails(db(uid).doc('chargebacks/9001').get());
      await assertFails(db(uid).doc('chargebacks/9001/events/e1').get());
    }
    await assertSucceeds(db('adm').doc('chargebacks/9001').get());
    await assertSucceeds(db('adm').doc('chargebacks/9001/events/e1').get());
  });

  test('nobody — not even an admin client — can create, edit or close a case directly', async () => {
    for (const uid of [C, A, 'adm']) {
      await assertFails(db(uid).doc('chargebacks/9001').update({ status: 'closed' }));
      await assertFails(db(uid).doc('chargebacks/9002').set({ status: 'open' }));
      await assertFails(db(uid).doc('chargebacks/9001/events/e2').set({ event: 'x' }));
    }
  });

  test('neither party can lift or alter the hold on the job', async () => {
    for (const uid of [C, A]) {
      await assertFails(jobRef(uid).update({ chargebackHold: false, ...consistency(uid) }));
      await assertFails(jobRef(uid).update({ chargebackStatus: 'closed_merchant_won', ...consistency(uid) }));
    }
  });
});

describe('Stage 7.2 — loss records, booking-response history and response-time fields are server-only', () => {
  beforeEach(async () => {
    await seedWorld({ status: 'matched' });
    await seed(async (f) => {
      await f.doc('admins/adm').set({ grantedAt: 1 });
      await f.doc('platform_losses/9001').set({ amountKobo: 100, absorbedBy: 'handytrust' });
      await f.doc('booking_responses/j1_art1_1').set({ artisanId: A, responseMinutes: 600, qualifying: true });
    });
  });

  test('only admins read platform losses and booking-response records; nobody writes them', async () => {
    for (const uid of [C, A, X]) {
      await assertFails(db(uid).doc('platform_losses/9001').get());
      await assertFails(db(uid).doc('booking_responses/j1_art1_1').get());
    }
    await assertSucceeds(db('adm').doc('platform_losses/9001').get());
    await assertSucceeds(db('adm').doc('booking_responses/j1_art1_1').get());
    for (const uid of [A, 'adm']) {
      await assertFails(db(uid).doc('booking_responses/j1_art1_1').update({ responseMinutes: 1 }));
      await assertFails(db(uid).doc('booking_responses/j1_art1_2').set({ artisanId: A, responseMinutes: 1, qualifying: true }));
      await assertFails(db(uid).doc('booking_responses/j1_art1_1').delete());
      await assertFails(db(uid).doc('platform_losses/9001').update({ amountKobo: 0 }));
    }
  });

  test('an artisan cannot write their own response-time inputs', async () => {
    await assertFails(db(A).doc(`artisans/${A}`).update({ responseTimeMinutes: 1 }));
    await assertFails(db(A).doc(`artisans/${A}`).update({ responseTimeSampleSize: 20 }));
    await assertFails(db(A).doc(`artisans/${A}`).update({ responseTimeUpdatedAt: Timestamp.fromMillis(Date.now() + 1e10) }));
  });

  test('a new artisan profile cannot be created with response-time inputs', async () => {
    const base = { uid: 'newart', approvalStatus: 'pending' };
    await assertSucceeds(db('newart').doc('artisans/newart').set(base));
    await seed(async (f) => f.doc('artisans/newart').delete());
    await assertFails(db('newart').doc('artisans/newart').set({ ...base, responseTimeSampleSize: 20 }));
    await assertFails(db('newart').doc('artisans/newart').set({ ...base, responseTimeUpdatedAt: Timestamp.fromMillis(1) }));
  });

  test('booking timestamps that feed the metric must be server time (client backdating refused)', async () => {
    await seedWorld({ status: 'matched', bookingStatus: 'awaitingArtisan', bookingRequestedAt: Timestamp.fromMillis(Date.now() - 60000) });
    await assertFails(jobRef(A).update({
      status: 'inChat', bookingStatus: 'confirmed', bookingConfirmedAt: Timestamp.fromMillis(Date.now() - 50000), ...consistency(A),
    }));
    await assertSucceeds(jobRef(A).update({
      status: 'inChat', bookingStatus: 'confirmed', bookingConfirmedAt: serverTimestamp(), ...consistency(A),
    }));
  });
});

describe('Stage 7.3 — partial-chargeback switch is console/Admin-SDK only', () => {
  test('no client — customer, artisan or admin — can enable partial-chargeback accounting', async () => {
    await seedWorld(null);
    await seed(async (f) => f.doc('admins/adm').set({ grantedAt: 1 }));
    for (const uid of [C, A, 'adm']) {
      await assertFails(db(uid).doc('config/platform').set({ partialChargebackAccountingVerified: true }, { merge: true }));
      await assertFails(db(uid).doc('config/platform').update({ partialChargebackAccountingVerified: true }));
    }
  });
});

describe('Stage 7.3 — debug "demo escrow" path cannot touch money state', () => {
  test('neither party can write escrow/payment state on the job (demo_escrow_service write)', async () => {
    await seedWorld({ status: 'paymentPending', agreedAmount: 50000 });
    for (const uid of [C, A]) {
      await assertFails(jobRef(uid).update({ 'escrow.status': 'processing', ...consistency(uid) }));
      await assertFails(jobRef(uid).update({ 'escrow.status': 'locked', status: 'escrowLocked', ...consistency(uid) }));
      await assertFails(jobRef(uid).update({ 'payment.reference': 'fake', ...consistency(uid) }));
    }
  });
});
