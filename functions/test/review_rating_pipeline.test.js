/**
 * Regression tests for the review->rating pipeline fix
 * (design/HANDYTRUST_V1_V2_MASTER_GAP_ANALYSIS.md §16.2,
 * design/V2_IOS_SAFARI_RELIABILITY_REPORT.md §9).
 *
 * _computeReviewApplication is a pure, dependency-free validation function
 * extracted from onReviewCreated — tested directly here, no Firestore/
 * emulator needed (the transactional aggregation + idempotency-marker
 * behavior it gates is exercised indirectly by this validation layer;
 * the transaction logic itself mirrors the already-tested escrow_releases/
 * payment_init_locks idempotency patterns in this same file).
 *
 * Run with: node --test functions/test/review_rating_pipeline.test.js
 */
const { test, describe } = require('node:test');
const assert = require('node:assert/strict');
const { _computeReviewApplication } = require('../index.js');

const job = {
  customerId: 'cust1',
  artisanId: 'artisan1',
  status: 'completed',
};

const validReview = {
  jobId: 'job1',
  customerId: 'cust1',
  artisanId: 'artisan1',
  rating: 5,
};

describe('_computeReviewApplication', () => {
  test('a legitimate review on a completed job with matching parties is accepted (returns null)', () => {
    assert.equal(_computeReviewApplication(validReview, job), null);
  });

  test('rejects a rating outside 1-5', () => {
    assert.equal(_computeReviewApplication({ ...validReview, rating: 0 }, job), 'invalid_rating');
    assert.equal(_computeReviewApplication({ ...validReview, rating: 6 }, job), 'invalid_rating');
  });

  test('rejects a non-numeric rating', () => {
    assert.equal(_computeReviewApplication({ ...validReview, rating: 'five' }, job), 'invalid_rating');
    assert.equal(_computeReviewApplication({ ...validReview, rating: undefined }, job), 'invalid_rating');
  });

  test('rejects a review with no artisanId', () => {
    assert.equal(_computeReviewApplication({ ...validReview, artisanId: undefined }, job), 'missing_artisan_id');
  });

  test('rejects when the job cannot be found', () => {
    assert.equal(_computeReviewApplication(validReview, null), 'job_not_found');
  });

  test(
    'CRITICAL — rejects a review whose artisanId does not match the job\'s actual artisan ' +
      '(this is the server-side re-verification that closes the fabricated-review vector documented in ' +
      'the gap analysis §16.3 — firestore.rules\' reviews create rule does not itself check this)',
    () => {
      const fabricated = { ...validReview, artisanId: 'someone-else-entirely' };
      assert.equal(_computeReviewApplication(fabricated, job), 'artisan_mismatch');
    }
  );

  test('rejects a review whose customerId does not match the job\'s actual customer', () => {
    const fabricated = { ...validReview, customerId: 'someone-else' };
    assert.equal(_computeReviewApplication(fabricated, job), 'customer_mismatch');
  });

  test('rejects a review on a job that is not actually completed (defense-in-depth beyond the rules check)', () => {
    const inProgressJob = { ...job, status: 'inProgress' };
    assert.equal(_computeReviewApplication(validReview, inProgressJob), 'job_not_completed');
  });
});
