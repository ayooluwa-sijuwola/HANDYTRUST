/**
 * Stage 4 — pure decision functions: payout freezes, settlement validation,
 * refund status machine. No Firestore, no Paystack.
 */
const { test, describe } = require('node:test');
const assert = require('node:assert/strict');
const fns = require('../index.js');

describe('_payoutBlockReason (D9 + fraud-freeze requirement)', () => {
  const block = (o) => fns._payoutBlockReason({ job: { status: 'completed' }, ...o });
  test('active artisan, normal job → payout allowed', () => assert.equal(block({}), null));
  for (const type of ['fraud', 'safety', 'security']) {
    test(`${type} suspension freezes payouts`, () =>
      assert.equal(block({ artisanUser: { accountStatus: 'suspended', suspensionType: type } }), 'artisan_suspended_freeze'));
  }
  test('administrative / verification suspensions do NOT freeze existing-job payouts', () => {
    assert.equal(block({ artisanUser: { accountStatus: 'suspended', suspensionType: 'administrative' } }), null);
    assert.equal(block({ artisanUser: { accountStatus: 'suspended', suspensionType: 'verification' } }), null);
  });
  test('unclassified suspension fails closed', () =>
    assert.equal(block({ artisanUser: { accountStatus: 'suspended' } }), 'artisan_suspended_freeze'));
  test('suspension recorded only on the artisans mirror still freezes', () =>
    assert.equal(block({ artisan: { accountStatus: 'suspended', suspensionType: 'fraud' } }), 'artisan_suspended_freeze'));
  test('explicit freezes on artisan or job', () => {
    assert.equal(block({ artisan: { payoutFrozen: true } }), 'artisan_payout_frozen');
    assert.equal(block({ artisanUser: { payoutFrozen: true } }), 'artisan_payout_frozen');
    assert.equal(block({ job: { status: 'completed', payoutFrozen: true } }), 'job_payout_frozen');
  });
  test('a dispute or pending cancellation request blocks a normal payout but not the settlement that resolves it', () => {
    assert.equal(block({ job: { status: 'disputed' } }), 'job_disputed');
    assert.equal(block({ job: { status: 'inProgress', cancellationRequestStatus: 'pending' } }), 'cancellation_request_pending');
    assert.equal(block({ job: { status: 'resolved' }, isSettlement: true }), null);
  });
  test('a fraud freeze blocks even an admin settlement payout', () =>
    assert.equal(block({ isSettlement: true, artisanUser: { accountStatus: 'suspended', suspensionType: 'fraud' } }), 'artisan_suspended_freeze'));
});

describe('_validateSettlement (D2/D3)', () => {
  const S = 5_000_000; const T = 5_250_000; const R = 'Evidence reviewed in full.';
  const v = (o) => fns._validateSettlement({ serviceKobo: S, totalKobo: T, reason: R, ...o });
  test('release pays exactly the service price', () => {
    assert.equal(v({ outcome: 'release', artisanKobo: S, refundKobo: 0 }), null);
    assert.equal(v({ outcome: 'release', artisanKobo: T, refundKobo: 0 }), 'release_must_pay_full_service_price');
  });
  test('full refund returns exactly the full charge (incl. platform fee)', () => {
    assert.equal(v({ outcome: 'full_refund', artisanKobo: 0, refundKobo: T }), null);
    assert.equal(v({ outcome: 'full_refund', artisanKobo: 0, refundKobo: S }), 'full_refund_must_return_full_charge');
  });
  test('split bounds', () => {
    assert.equal(v({ outcome: 'split', artisanKobo: 2_000_000, refundKobo: 3_250_000 }), null);
    assert.equal(v({ outcome: 'split', artisanKobo: S + 1, refundKobo: 1 }), 'artisan_amount_exceeds_service_price');
    assert.equal(v({ outcome: 'split', artisanKobo: 3_000_000, refundKobo: 2_250_001 }), 'split_exceeds_amount_paid');
    assert.equal(v({ outcome: 'split', artisanKobo: 0, refundKobo: 1 }), 'split_requires_both_parts');
  });
  test('mandatory reason, valid outcome, integer non-negative kobo', () => {
    assert.equal(v({ outcome: 'release', artisanKobo: S, refundKobo: 0, reason: '  ok ' }), 'reason_required');
    assert.equal(v({ outcome: 'confiscate', artisanKobo: 0, refundKobo: 0 }), 'invalid_outcome');
    assert.equal(v({ outcome: 'split', artisanKobo: 1.5, refundKobo: 1 }), 'invalid_amount');
    assert.equal(v({ outcome: 'split', artisanKobo: -1, refundKobo: 1 }), 'invalid_amount');
  });
});

describe('Refund status machine (Paystack-reported only)', () => {
  test('Paystack statuses map to ours; unknown statuses map to nothing', () => {
    assert.equal(fns._mapRefundStatus('pending'), 'submitted');
    assert.equal(fns._mapRefundStatus('processing'), 'processing');
    assert.equal(fns._mapRefundStatus('processed'), 'processed');
    assert.equal(fns._mapRefundStatus('failed'), 'failed');
    assert.equal(fns._mapRefundStatus('needs-attention'), 'needs_attention');
    assert.equal(fns._mapRefundStatus('success'), null);
    assert.equal(fns._mapRefundStatus(undefined), null);
  });
  test('processed is terminal; unknown input never changes state', () => {
    assert.equal(fns._nextRefundStatus('processed', 'failed'), 'processed');
    assert.equal(fns._nextRefundStatus('processed', 'processing'), 'processed');
    assert.equal(fns._nextRefundStatus('submitted', null), 'submitted');
    assert.equal(fns._nextRefundStatus('submitted', 'processed'), 'processed');
    assert.equal(fns._nextRefundStatus('failed', 'submitted'), 'submitted'); // a new attempt
  });
});
