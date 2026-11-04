/**
 * Stage 2 remediation — payout authorization, server-owned review window,
 * one-review-per-job (design/REMEDIATION_STAGE1_VERIFICATION_2026-11-03.md).
 *
 * Pure-function tests: no Firestore, no Paystack, no network. The trigger
 * wiring that calls these (processEscrowRelease, _releaseEscrow,
 * onJobCompleted, onReviewCreated) is covered by code review in the Stage 2
 * report; an emulator-driven trigger harness is planned for Stage 7.
 */
const { test, describe } = require('node:test');
const assert = require('node:assert/strict');
const fns = require('../index.js');

describe('HT-002 payout requester authorization', () => {
  test('the paying customer may request the release', () => {
    assert.equal(fns._isReleaseRequesterAuthorized('cust1', 'cust1'), true);
  });

  test('the auto-release cron may request the release', () => {
    assert.equal(fns._isReleaseRequesterAuthorized('system', 'cust1'), true);
  });

  test('the artisan (self-payout attempt) may not', () => {
    assert.equal(fns._isReleaseRequesterAuthorized('art1', 'cust1'), false);
  });

  test('a rewritten customer identity that differs from the payer may not', () => {
    assert.equal(fns._isReleaseRequesterAuthorized('attacker', 'cust1'), false);
  });

  test('fails closed when the payment has no payerId', () => {
    assert.equal(fns._isReleaseRequesterAuthorized('cust1', undefined), false);
    assert.equal(fns._isReleaseRequesterAuthorized('cust1', ''), false);
    assert.equal(fns._isReleaseRequesterAuthorized(undefined, undefined), false);
  });
});

describe('HT-005 server-owned review window', () => {
  const DAY = 24 * 60 * 60 * 1000;
  const submitted = Date.UTC(2026, 10, 1, 12, 0, 0);

  test('window is exactly 14 days', () => {
    assert.equal(fns.REVIEW_WINDOW_MS, 14 * DAY);
    assert.equal(fns._reviewWindowEndMs(submitted), submitted + 14 * DAY);
  });

  test('not elapsed one millisecond before 14 days', () => {
    assert.equal(fns._isReviewWindowElapsed(submitted, submitted + 14 * DAY - 1), false);
  });

  test('elapsed at exactly 14 days', () => {
    assert.equal(fns._isReviewWindowElapsed(submitted, submitted + 14 * DAY), true);
  });

  test('a client-backdated autoReleaseAt cannot shorten it — only submittedAt counts', () => {
    // Simulates P-C: autoReleaseAt in the past, but the job was submitted an hour ago.
    const now = submitted + 60 * 60 * 1000;
    assert.equal(fns._isReviewWindowElapsed(submitted, now), false);
  });

  test('missing submittedAt fails closed (never auto-releases)', () => {
    assert.equal(fns._isReviewWindowElapsed(undefined, Date.now()), false);
    assert.equal(fns._isReviewWindowElapsed(null, Date.now()), false);
  });
});

describe('HT-014 one review per job (server-side defense)', () => {
  const job = { artisanId: 'art1', customerId: 'cust1', status: 'completed' };
  const review = { jobId: 'job1', artisanId: 'art1', customerId: 'cust1', rating: 5 };

  test('review stored under its jobId is applied', () => {
    assert.equal(fns._computeReviewApplication(review, job, 'job1'), null);
  });

  test('review stored under any other ID is refused', () => {
    assert.equal(fns._computeReviewApplication(review, job, 'r2'), 'review_id_not_job_id');
  });

  test('existing two-argument callers are unaffected', () => {
    assert.equal(fns._computeReviewApplication(review, job), null);
  });
});
