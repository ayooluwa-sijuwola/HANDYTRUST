/**
 * Tests for initializePaystackTransaction's idempotency claim mechanism
 * (design/PHASE_10_AUTHENTICATED_PAYMENT_QA.md Phase 10B-1).
 *
 * These exercise real Firestore transactions against the LOCAL EMULATOR
 * ONLY — FIRESTORE_EMULATOR_HOST is set before requiring functions/index.js,
 * so the Admin SDK inside it connects to 127.0.0.1:8090, never production.
 * No Paystack call is made by these tests (they test the claim/resolve/
 * release primitives directly, not the full callable, which would require
 * a real or mocked Paystack API call).
 *
 * Requires the Firestore emulator running on 127.0.0.1:8090, e.g.:
 *   firebase emulators:exec --only firestore \
 *     "node --test functions/test/payment_init_idempotency.test.js"
 */
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8090';
process.env.GCLOUD_PROJECT = 'handytrust-rules-test';

const { test, describe, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
const {
  _claimOrAwaitPaymentInitialization,
  _resolvePaymentInitialization,
  _releasePaymentInitializationClaim,
} = require('../index.js');

const db = admin.firestore();

async function clearLocks() {
  const snap = await db.collection('payment_init_locks').get();
  await Promise.all(snap.docs.map((d) => d.ref.delete()));
}

beforeEach(async () => {
  await clearLocks();
});

describe('Payment initialization idempotency', () => {
  test('first caller claims the lock', async () => {
    const claim = await _claimOrAwaitPaymentInitialization('job-a');
    assert.equal(claim.claimed, true);
  });

  test('a second caller while the first is still "initializing" waits, then reuses the result once resolved', async () => {
    const jobId = 'job-b';
    const first = await _claimOrAwaitPaymentInitialization(jobId);
    assert.equal(first.claimed, true);

    // Simulate the first caller finishing its (fake) Paystack call shortly
    // after — resolve the claim concurrently with the second caller's poll.
    const fakeResult = { paymentId: 'pay1', reference: 'ref1', accessCode: 'code1', authorizationUrl: 'https://paystack.test/pay1' };
    const resolvePromise = new Promise((resolve) => {
      setTimeout(async () => {
        await _resolvePaymentInitialization(jobId, fakeResult);
        resolve();
      }, 700); // after the second caller's first ~500ms poll tick, before its 5s budget expires
    });

    const second = await _claimOrAwaitPaymentInitialization(jobId);
    await resolvePromise;

    assert.equal(second.claimed, false);
    assert.deepEqual(second.result, fakeResult);
  });

  test('a caller after a recently-completed initialization reuses that result without waiting', async () => {
    const jobId = 'job-c';
    const first = await _claimOrAwaitPaymentInitialization(jobId);
    assert.equal(first.claimed, true);
    const fakeResult = { paymentId: 'pay2', reference: 'ref2', accessCode: 'code2', authorizationUrl: 'https://paystack.test/pay2' };
    await _resolvePaymentInitialization(jobId, fakeResult);

    const second = await _claimOrAwaitPaymentInitialization(jobId);
    assert.equal(second.claimed, false);
    assert.deepEqual(second.result, fakeResult);
  });

  test('releasing a claim (failure path) lets the very next call reclaim immediately, not wait out the stale window', async () => {
    const jobId = 'job-d';
    const first = await _claimOrAwaitPaymentInitialization(jobId);
    assert.equal(first.claimed, true);

    await _releasePaymentInitializationClaim(jobId);

    const retry = await _claimOrAwaitPaymentInitialization(jobId);
    assert.equal(retry.claimed, true, 'a released claim must be immediately reclaimable — this is the retry-after-failure path');
  });

  test('two different jobs never contend with each other', async () => {
    const a = await _claimOrAwaitPaymentInitialization('job-e1');
    const b = await _claimOrAwaitPaymentInitialization('job-e2');
    assert.equal(a.claimed, true);
    assert.equal(b.claimed, true);
  });
});
