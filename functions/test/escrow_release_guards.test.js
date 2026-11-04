/**
 * Unit tests for the pure fail-closed guard functions inside
 * processEscrowRelease (design/P0_REMEDIATION_PLAN.md §3.4/§4.6, §9's
 * "absolute requirement": never fall back to a client-controlled amount
 * when no authoritative payment exists — fail closed instead).
 *
 * These are pure functions with no Firestore/Paystack/network dependency,
 * so they're tested directly with Node's built-in test runner — no
 * emulator, no mocking, no credentials, nothing that could touch
 * production or real money.
 *
 * Run with: node --test functions/test/escrow_release_guards.test.js
 * (from the repo root), or `npm test` from functions/.
 */
const { test, describe } = require('node:test');
const assert = require('node:assert/strict');
const { _isJobPayable, _amountsMatch } = require('../index.js');

describe('_isJobPayable — the exact set of job statuses a payout may fire from', () => {
  test('submitted is payable (the normal path)', () => {
    assert.equal(_isJobPayable('submitted'), true);
  });

  test('completed is payable (idempotent re-check / already-completed edge case)', () => {
    assert.equal(_isJobPayable('completed'), true);
  });

  const notPayable = [
    'requested',
    'matched',
    'inChat',
    'paymentPending',
    'escrowLocked',
    'inProgress',
    'disputed',
    'resolved',
    'cancelled',
    '',
    undefined,
    null,
  ];

  for (const status of notPayable) {
    test(`"${status}" is NOT payable — this is the exact exploit chain's earliest failure point`, () => {
      assert.equal(_isJobPayable(status), false);
    });
  }
});

describe('_amountsMatch — the payments.amount vs job.agreedAmount cross-check', () => {
  test('exact match', () => {
    assert.equal(_amountsMatch(50000, 50000), true);
  });

  test('within floating-point tolerance (0.01)', () => {
    assert.equal(_amountsMatch(50000, 50000.005), true);
  });

  test('a real mismatch fails — e.g. a legacy or tampered payment record', () => {
    assert.equal(_amountsMatch(50000, 5000), false);
  });

  test('a small but real difference (1 naira) still fails — no loose tolerance', () => {
    assert.equal(_amountsMatch(50000, 50001), false);
  });

  test('zero vs nonzero fails', () => {
    assert.equal(_amountsMatch(0, 50000), false);
  });
});
