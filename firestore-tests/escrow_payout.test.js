/**
 * Firestore Security Rules regression tests — payment/escrow/payout P0
 * remediation (design/P0_REMEDIATION_PLAN.md §7).
 *
 * Runs entirely against the local Firestore emulator. Never touches
 * production Firestore, never calls Paystack, never uses live credentials.
 *
 * Run with: npm test  (from this directory)
 *   — requires the Firestore emulator running on 127.0.0.1:8090 (see
 *     firebase.json's emulators.firestore.port), e.g. from the repo root:
 *     firebase emulators:exec --only firestore "cd firestore-tests && npm test"
 */
const { test, before, after, beforeEach, describe } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const { serverTimestamp } = require('firebase/firestore');

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'handytrust-rules-test',
    firestore: {
      rules: fs.readFileSync(path.resolve(__dirname, '../firestore.rules'), 'utf8'),
      host: '127.0.0.1',
      port: 8090,
    },
  });
});

after(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

// ─── Helpers ────────────────────────────────────────────────────────────────

// A real (non-anonymous) signed-in Firestore client for `uid`. Mirrors
// firestore.rules' isSignedIn(), which specifically checks
// token.firebase.sign_in_provider != 'anonymous'.
function ctxFor(uid) {
  return testEnv
    .authenticatedContext(uid, { firebase: { sign_in_provider: 'password' } })
    .firestore();
}

async function seed(fn) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await fn(context.firestore());
  });
}

async function seedJob(jobId, overrides = {}) {
  await seed((db) =>
    db.collection('jobs').doc(jobId).set({
      customerId: 'cust1',
      artisanId: 'art1',
      status: 'requested',
      ...overrides,
    })
  );
}

async function seedArtisan(uid, overrides = {}) {
  await seed((db) =>
    db.collection('artisans').doc(uid).set({
      uid,
      approvalStatus: 'approved',
      verificationStatus: 'id_verified',
      ...overrides,
    })
  );
}

async function seedAdmin(uid) {
  await seed((db) => db.collection('admins').doc(uid).set({ grantedAt: Date.now() }));
}

async function seedPayment(paymentId, overrides = {}) {
  await seed((db) =>
    db.collection('payments').doc(paymentId).set({
      payerId: 'cust1',
      artisanId: 'art1',
      jobId: 'job1',
      amount: 50000,
      status: 'escrowHeld',
      ...overrides,
    })
  );
}

async function seedRelease(jobId, overrides = {}) {
  await seed((db) =>
    db.collection('escrow_releases').doc(jobId).set({
      jobId,
      status: 'pending',
      requestedAt: Date.now(),
      requestedBy: 'cust1',
      ...overrides,
    })
  );
}

// ─── §7.1 Negative tests — a malicious customer must NOT be able to... ──────

describe('P0-1: payments collection is server-only (§4.3)', () => {
  test('1. fabricate a payment for a job that is not theirs', async () => {
    await seedJob('job1', { customerId: 'cust1' });
    const attacker = ctxFor('mallory');
    await assertFails(
      attacker.collection('payments').add({
        payerId: 'mallory',
        jobId: 'job1',
        artisanId: 'art1',
        amount: 999999,
        status: 'escrowHeld',
      })
    );
  });

  test('2. fabricate a payment even as the job\'s real customer (create is server-only, full stop)', async () => {
    await seedJob('job1', { customerId: 'cust1' });
    const customer = ctxFor('cust1');
    await assertFails(
      customer.collection('payments').add({
        payerId: 'cust1',
        jobId: 'job1',
        artisanId: 'art1',
        amount: 999999,
        status: 'escrowHeld',
      })
    );
  });

  test('3. mark an existing payment as verified/escrowHeld via a direct update', async () => {
    await seedPayment('pay1', { status: 'pending' });
    const payer = ctxFor('cust1');
    await assertFails(
      payer.collection('payments').doc('pay1').update({ status: 'escrowHeld' })
    );
  });

  test('8. modify or read another user\'s payment', async () => {
    await seedPayment('pay1', { payerId: 'cust1', artisanId: 'art1' });
    const stranger = ctxFor('mallory');
    await assertFails(stranger.collection('payments').doc('pay1').get());
    await assertFails(
      stranger.collection('payments').doc('pay1').update({ amount: 1 })
    );
  });
});

describe('P0-1: escrowLocked cannot be forced by a client (§4.2)', () => {
  test('4. force paymentPending -> escrowLocked directly', async () => {
    await seedJob('job1', { customerId: 'cust1', artisanId: 'art1', status: 'paymentPending' });
    const customer = ctxFor('cust1');
    await assertFails(
      customer.collection('jobs').doc('job1').update({
        status: 'escrowLocked',
        paymentReference: 'FAKE-REF',
      })
    );
  });
});

describe('P0-1: escrow_releases requires job.status == submitted (§4.1)', () => {
  const nonSubmittedStatuses = ['requested', 'matched', 'inChat', 'paymentPending', 'escrowLocked', 'inProgress'];

  for (const status of nonSubmittedStatuses) {
    test(`5. release escrow while job.status == "${status}" (not submitted)`, async () => {
      await seedJob('job1', { customerId: 'cust1', artisanId: 'art1', status });
      const customer = ctxFor('cust1');
      await assertFails(
        customer.collection('escrow_releases').doc('job1').set({
          jobId: 'job1',
          status: 'pending',
          requestedAt: Date.now(),
          requestedBy: 'cust1',
        })
      );
    });
  }

  test('6. duplicate an escrow release under a different auto-generated ID', async () => {
    await seedJob('job1', { customerId: 'cust1', artisanId: 'art1', status: 'submitted' });
    const customer = ctxFor('cust1');

    // (a) the legitimate, jobId-keyed release succeeds once.
    await assertSucceeds(
      customer.collection('escrow_releases').doc('job1').set({
        jobId: 'job1',
        status: 'pending',
        requestedAt: Date.now(),
        requestedBy: 'cust1',
      })
    );

    // (b) a second release for the SAME job under a different (non-jobId) ID must fail —
    // this is the amplification the duplicate rule block used to allow.
    await assertFails(
      customer.collection('escrow_releases').add({
        jobId: 'job1',
        status: 'pending',
        requestedAt: Date.now(),
        requestedBy: 'cust1',
      })
    );
  });

  test('7. modify or delete an existing escrow release', async () => {
    await seedJob('job1', { customerId: 'cust1', artisanId: 'art1', status: 'submitted' });
    await seedRelease('job1');
    const customer = ctxFor('cust1');
    await assertFails(
      customer.collection('escrow_releases').doc('job1').update({ status: 'completed' })
    );
    await assertFails(customer.collection('escrow_releases').doc('job1').delete());
  });

  test('release for a job ID that does not match the release document ID', async () => {
    await seedJob('job1', { customerId: 'cust1', artisanId: 'art1', status: 'submitted' });
    const customer = ctxFor('cust1');
    // doc ID 'not-job1' != jobId 'job1' — must fail even though status/ownership are otherwise valid.
    await assertFails(
      customer.collection('escrow_releases').doc('not-job1').set({
        jobId: 'job1',
        status: 'pending',
        requestedAt: Date.now(),
        requestedBy: 'cust1',
      })
    );
  });
});

describe('P0-1: agreedAmount is bounded and ownership-scoped (§4.4)', () => {
  test('9. bypass ownership to set agreedAmount as a stranger', async () => {
    await seedJob('job1', { customerId: 'cust1', artisanId: 'art1', status: 'inChat' });
    const stranger = ctxFor('mallory');
    await assertFails(
      stranger.collection('jobs').doc('job1').update({
        agreedAmount: 100,
        lastUpdatedAt: Date.now(),
        lastUpdatedBy: 'customer:mallory',
        updateVersion: 1,
      })
    );
  });

  test('10a. set a negative agreedAmount', async () => {
    await seedJob('job1', { customerId: 'cust1', artisanId: 'art1', status: 'inChat' });
    const customer = ctxFor('cust1');
    await assertFails(
      customer.collection('jobs').doc('job1').update({
        agreedAmount: -500,
        lastUpdatedAt: Date.now(),
        lastUpdatedBy: 'customer:cust1',
        updateVersion: 1,
      })
    );
  });

  test('10b. set agreedAmount to zero', async () => {
    await seedJob('job1', { customerId: 'cust1', artisanId: 'art1', status: 'inChat' });
    const customer = ctxFor('cust1');
    await assertFails(
      customer.collection('jobs').doc('job1').update({
        agreedAmount: 0,
        lastUpdatedAt: Date.now(),
        lastUpdatedBy: 'customer:cust1',
        updateVersion: 1,
      })
    );
  });

  test('10c. set a non-numeric agreedAmount', async () => {
    await seedJob('job1', { customerId: 'cust1', artisanId: 'art1', status: 'inChat' });
    const customer = ctxFor('cust1');
    await assertFails(
      customer.collection('jobs').doc('job1').update({
        agreedAmount: 'a lot of money',
        lastUpdatedAt: Date.now(),
        lastUpdatedBy: 'customer:cust1',
        updateVersion: 1,
      })
    );
  });
});

describe('P0-1: role/admin bypass', () => {
  test('11. self-grant admin by writing to admins/{ownUid}', async () => {
    const stranger = ctxFor('mallory');
    await assertFails(stranger.collection('admins').doc('mallory').set({ grantedAt: Date.now() }));
  });
});

describe('P0-1: the documented end-to-end exploit chain must fail closed (§2.4)', () => {
  test('12. customer + colluding artisan, job only at inChat, no real payment — the exploit from the audit', async () => {
    // Attacker setup: customer account, a real approved+verified artisan
    // account (could be a colluding second account, or an unwitting real
    // artisan — the rules gap doesn't care which), job matched to that
    // artisan, moved to inChat. No payment has ever occurred.
    await seedArtisan('art1');
    await seedJob('job1', { customerId: 'cust1', artisanId: 'art1', status: 'inChat' });
    const customer = ctxFor('cust1');

    // Step 1: attacker sets an arbitrarily large agreedAmount.
    // This alone is legal (bounded, positive number, own job, inChat) —
    // the fix does not forbid legitimate negotiation.
    await assertSucceeds(
      customer.collection('jobs').doc('job1').update({
        agreedAmount: 5_000_000,
        lastUpdatedAt: Date.now(),
        lastUpdatedBy: 'customer:cust1',
        updateVersion: 1,
      })
    );

    // Step 2: attacker attempts to create the escrow_releases document that
    // would trigger a real payout — this MUST fail, because job.status is
    // still 'inChat', not 'submitted'. This is the exact chain from
    // design/P0_REMEDIATION_PLAN.md §2.4 and it must break here.
    await assertFails(
      customer.collection('escrow_releases').doc('job1').set({
        jobId: 'job1',
        status: 'pending',
        requestedAt: Date.now(),
        requestedBy: 'cust1',
      })
    );

    // Belt-and-suspenders: even if that had somehow succeeded, there is no
    // payments document with status 'escrowHeld' for this job at all —
    // processEscrowRelease (functions/index.js) would independently refuse
    // to pay out (failureReason: 'no_verified_payment_on_record'). This is
    // exercised directly in the Cloud Functions unit tests, not here, since
    // this emulator instance has no Functions runtime attached — see
    // design/P0_REMEDIATION_PLAN.md §7's own scoping note on this.
  });

  test('forged payment document does not help — attacker plants a fake escrowHeld payment, chain still fails', async () => {
    await seedArtisan('art1');
    await seedJob('job1', { customerId: 'cust1', artisanId: 'art1', status: 'inChat' });
    const customer = ctxFor('cust1');

    // Attempting to plant a fake payments doc fails outright (§4.3) —
    // regardless of what the attacker intended to do with it next.
    await assertFails(
      customer.collection('payments').add({
        payerId: 'cust1',
        jobId: 'job1',
        artisanId: 'art1',
        amount: 5_000_000,
        status: 'escrowHeld',
      })
    );
  });

  test('incorrect job ID on the release document fails even with a genuinely submitted job elsewhere', async () => {
    await seedJob('job1', { customerId: 'cust1', artisanId: 'art1', status: 'submitted' });
    await seedJob('job2', { customerId: 'cust1', artisanId: 'art1', status: 'inChat' });
    const customer = ctxFor('cust1');
    // Try to release job2 (still inChat) by pointing a release doc's jobId
    // field at job1 (which IS submitted) while keying the doc ID to job2.
    await assertFails(
      customer.collection('escrow_releases').doc('job2').set({
        jobId: 'job1', // mismatched — doc ID must equal jobId
        status: 'pending',
        requestedAt: Date.now(),
        requestedBy: 'cust1',
      })
    );
  });

  test('concurrent release attempts for the same job: only the first create can ever succeed', async () => {
    await seedJob('job1', { customerId: 'cust1', artisanId: 'art1', status: 'submitted' });
    const customer = ctxFor('cust1');
    await assertSucceeds(
      customer.collection('escrow_releases').doc('job1').set({
        jobId: 'job1',
        status: 'pending',
        requestedAt: Date.now(),
        requestedBy: 'cust1',
      })
    );
    // A second "concurrent" attempt at the same document ID is evaluated by
    // rules as an UPDATE (the document already exists), and update is
    // `if false` unconditionally — this is what makes the fixed-ID scheme
    // structurally immune to a duplicate release for the same job, whether
    // the second attempt is truly concurrent or sequential.
    await assertFails(
      customer.collection('escrow_releases').doc('job1').set({
        jobId: 'job1',
        status: 'pending',
        requestedAt: Date.now(),
        requestedBy: 'cust1',
      })
    );
  });
});

// ─── §7.2 Positive tests — the legitimate workflow must still work ─────────

describe('Legitimate flow still works after remediation', () => {
  test('13. full happy path: job -> matched -> inChat -> paymentPending -> (server) escrowLocked -> inProgress -> submitted -> release', async () => {
    await seedArtisan('art1');
    const customer = ctxFor('cust1');
    const artisan = ctxFor('art1');

    // Customer creates the job.
    await assertSucceeds(
      customer.collection('jobs').doc('job1').set({
        customerId: 'cust1',
        status: 'requested',
      })
    );

    // requested -> matched (customer, naming an eligible artisan).
    await assertSucceeds(
      customer.collection('jobs').doc('job1').update({
        status: 'matched', artisanId: 'art1', matchedAt: serverTimestamp(), bookingStatus: 'awaitingArtisan',
      })
    );

    // matched -> inChat. Stage 5 (D7): the ARTISAN confirms the booking
    // (within 24 h of the server-stamped match); the customer can't skip it.
    await assertFails(customer.collection('jobs').doc('job1').update({ status: 'inChat' }));
    await assertSucceeds(
      artisan.collection('jobs').doc('job1').update({
        status: 'inChat', bookingStatus: 'confirmed', bookingConfirmedAt: serverTimestamp(),
      })
    );

    // Negotiate a valid amount.
    await assertSucceeds(
      customer.collection('jobs').doc('job1').update({
        agreedAmount: 50000,
        lastUpdatedAt: Date.now(),
        lastUpdatedBy: 'customer:cust1',
        updateVersion: 1,
      })
    );

    // Agreement confirmation checkpoint: customer confirms...
    await assertSucceeds(
      customer.collection('jobs').doc('job1').update({
        agreementStatus: 'pendingArtisanConfirmation',
        agreementConfirmedByCustomer: true,
        agreementScope: 'Full kitchen repair',
        agreedAmount: 50000,
        agreementUpdatedAt: Date.now(),
        lastUpdatedAt: Date.now(),
        lastUpdatedBy: 'customer:cust1',
        updateVersion: 2,
      })
    );
    // ...then artisan accepts.
    await assertSucceeds(
      artisan.collection('jobs').doc('job1').update({
        agreementStatus: 'confirmed',
        agreementConfirmedByArtisan: true,
        agreementArtisanConfirmedAt: Date.now(),
        agreementUpdatedAt: Date.now(),
        lastUpdatedAt: Date.now(),
        lastUpdatedBy: 'artisan:art1',
        updateVersion: 3,
      })
    );

    // inChat -> paymentPending (agreement confirmed, asap job so no scheduling gate).
    await assertSucceeds(
      customer.collection('jobs').doc('job1').update({ status: 'paymentPending' })
    );

    // --- Server-side steps (would be Cloud Functions under the Admin SDK
    // in production — initializePaystackTransaction creates the payment
    // doc, _lockEscrow flips the job to escrowLocked after a verified
    // charge). Simulated here with rules disabled, exactly as
    // design/P0_REMEDIATION_PLAN.md §7.2 anticipated for a Firestore-only
    // emulator with no Functions runtime attached. ---
    await seedPayment('pay1', { jobId: 'job1', payerId: 'cust1', artisanId: 'art1', amount: 50000, status: 'escrowHeld' });
    await seed((db) => db.collection('jobs').doc('job1').update({ status: 'escrowLocked' }));

    // escrowLocked -> inProgress (artisan starts work).
    await assertSucceeds(
      artisan.collection('jobs').doc('job1').update({ status: 'inProgress' })
    );

    // inProgress -> submitted (artisan submits completed work).
    // Stage 2 (HT-005): a bare {status:'submitted'} is now rejected — the
    // review window is anchored to a server-stamped submittedAt, and at
    // least one completion photo is required (job_completion_screen.dart
    // already enforces this in the UI). The payload below is exactly what
    // JobService.submitCompletion sends.
    await assertFails(
      artisan.collection('jobs').doc('job1').update({ status: 'submitted' })
    );
    await assertSucceeds(
      artisan.collection('jobs').doc('job1').update({
        status: 'submitted',
        completionImageUrls: ['https://example.com/after.jpg'],
        submittedAt: serverTimestamp(),
      })
    );

    // 14. Customer manually confirms completion -> creates the release doc.
    // This is the legitimate client-write path §4.1 preserves.
    await assertSucceeds(
      customer.collection('escrow_releases').doc('job1').set({
        jobId: 'job1',
        status: 'pending',
        requestedAt: Date.now(),
        requestedBy: 'cust1',
      })
    );
  });

  test('15. valid positive agreedAmount negotiation succeeds for both parties', async () => {
    await seedJob('job1', { customerId: 'cust1', artisanId: 'art1', status: 'inChat' });
    const customer = ctxFor('cust1');
    const artisan = ctxFor('art1');

    await assertSucceeds(
      customer.collection('jobs').doc('job1').update({
        agreedAmount: 20000,
        lastUpdatedAt: Date.now(),
        lastUpdatedBy: 'customer:cust1',
        updateVersion: 1,
      })
    );
    await assertSucceeds(
      artisan.collection('jobs').doc('job1').update({
        agreedAmount: 25000,
        lastUpdatedAt: Date.now(),
        lastUpdatedBy: 'artisan:art1',
        updateVersion: 2,
      })
    );
  });

  test('admin can still read escrow_releases and payments for ops visibility', async () => {
    await seedAdmin('admin1');
    await seedJob('job1', { customerId: 'cust1', artisanId: 'art1', status: 'submitted' });
    await seedRelease('job1');
    await seedPayment('pay1');
    const admin = ctxFor('admin1');
    await assertSucceeds(admin.collection('escrow_releases').doc('job1').get());
    await assertSucceeds(admin.collection('payments').doc('pay1').get());
  });
});
