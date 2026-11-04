/**
 * Stage 3 remediation — fee model, charge validation, late/duplicate
 * payment decisions, abandoned-payment decisions
 * (design/REMEDIATION_STAGE3_REPORT_2026-11-03.md). Pure functions only:
 * no Firestore, no Paystack, no network.
 */
const { test, describe } = require('node:test');
const assert = require('node:assert/strict');
const fns = require('../index.js');

const DEFAULTS = fns.PLATFORM_CONFIG_DEFAULTS;
// Stage 3 policy (₦100 minimum) — kept to document the original loss bands
// and to exercise rounding on small amounts. Stage 4 default is ₦3,212.
const MIN100 = { ...DEFAULTS, minJobValueNgn: 100 };

describe('D1 platform fee — _computeCharge (integer kobo)', () => {
  test('approved policy: 5% on top, artisan price untouched', () => {
    const c = fns._computeCharge(50000, DEFAULTS);
    assert.equal(c.ok, true);
    assert.equal(c.serviceAmountKobo, 5_000_000);
    assert.equal(c.platformFeeKobo, 250_000);
    assert.equal(c.totalKobo, 5_250_000);
    assert.equal(c.totalCharged, 52500);
  });

  test('rounds the fee to the nearest kobo, never float drift', () => {
    const c = fns._computeCharge(1234.57, MIN100);
    assert.equal(c.serviceAmountKobo, 123457);
    assert.equal(c.platformFeeKobo, 6173); // 6172.85 → 6173
    assert.equal(c.totalKobo, 123457 + 6173);
    assert.ok(Number.isInteger(c.totalKobo));
  });

  test('minimum platform fee floor applies only when configured', () => {
    const cfg = { ...MIN100, minPlatformFeeNgn: 200 };
    assert.equal(fns._computeCharge(2000, cfg).platformFee, 200);   // 5% = 100 → floor 200
    assert.equal(fns._computeCharge(10000, cfg).platformFee, 500);  // 5% = 500 > floor
    assert.equal(fns._computeCharge(2000, MIN100).platformFee, 100);
  });

  test('below the minimum job value is refused', () => {
    assert.deepEqual(fns._computeCharge(99, DEFAULTS), { ok: false, reason: 'below_minimum_job_value' });
  });

  test('invalid agreed amounts are refused', () => {
    for (const v of [0, -5, NaN, Infinity, '5000', null, undefined]) {
      assert.equal(fns._computeCharge(v, DEFAULTS).ok, false, String(v));
    }
  });
});

describe('config/platform normalization — a bad config can never zero the fee', () => {
  test('missing doc → approved defaults', () => {
    assert.deepEqual(fns._normalizePlatformConfig(null), { ...DEFAULTS });
  });
  test('invalid or out-of-range values fall back per key', () => {
    const c = fns._normalizePlatformConfig({
      platformFeePercent: 'five', minPlatformFeeNgn: -1, minJobValueNgn: 0, abandonedPaymentHours: 10000,
    });
    assert.deepEqual(c, { ...DEFAULTS });
  });
  test('valid overrides are honoured', () => {
    const c = fns._normalizePlatformConfig({ platformFeePercent: 5, minPlatformFeeNgn: 200, minJobValueNgn: 1000, abandonedPaymentHours: 24 });
    assert.equal(c.minPlatformFeeNgn, 200);
    assert.equal(c.minJobValueNgn, 1000);
  });
});

describe('payout and expected-charge amounts', () => {
  test('payout is the service price, never the platform fee', () => {
    assert.equal(fns._payoutAmountNgn({ amount: 50000, serviceAmount: 50000, totalCharged: 52500 }), 50000);
  });
  test('legacy payments (pre-fee) pay out amount', () => {
    assert.equal(fns._payoutAmountNgn({ amount: 30000 }), 30000);
  });
  test('expected charge uses amountKobo, or legacy amount × 100', () => {
    assert.equal(fns._expectedChargeKobo({ amountKobo: 5_250_000, amount: 50000 }), 5_250_000);
    assert.equal(fns._expectedChargeKobo({ amount: 30000 }), 3_000_000);
    assert.equal(fns._expectedChargeKobo({}), null);
  });
});

describe('_decideChargeOutcome — every way a successful charge can arrive', () => {
  const REF = 'pay_1';
  const payment = { jobId: 'job1', status: 'pending', amountKobo: 5_250_000, amount: 50000 };
  const job = { status: 'paymentPending', pendingPaymentReference: REF, agreementStatus: 'confirmed' };
  const charge = { status: 'success', amount: 5_250_000, currency: 'NGN', reference: REF, metadata: { jobId: 'job1' } };
  const decide = (o = {}) => fns._decideChargeOutcome({
    job: { ...job, ...o.job }, payment: o.payment === null ? null : { ...payment, ...o.payment },
    charge: { ...charge, ...o.charge }, reference: REF,
  }).outcome;
  const reason = (o) => fns._decideChargeOutcome({
    job: { ...job, ...o.job }, payment: o.payment === null ? null : { ...payment, ...o.payment },
    charge: { ...charge, ...o.charge }, reference: REF,
  }).reason;

  test('exact match on the current pending payment → lock', () => assert.equal(decide(), 'lock'));
  test('legacy job without pendingPaymentReference → lock', () =>
    assert.equal(decide({ job: { pendingPaymentReference: undefined } }), 'lock'));
  test('not a success → nothing', () => assert.equal(decide({ charge: { status: 'abandoned' } }), 'not_successful'));
  test('underpaid → requires refund (amount mismatch)', () => {
    assert.equal(decide({ charge: { amount: 100 } }), 'requires_refund');
    assert.equal(reason({ charge: { amount: 100 } }), 'amount_mismatch');
  });
  test('charged without the platform fee → requires refund', () =>
    assert.equal(reason({ charge: { amount: 5_000_000 } }), 'amount_mismatch'));
  test('non-NGN currency → requires refund', () => assert.equal(reason({ charge: { currency: 'USD' } }), 'currency_mismatch'));
  test('metadata points at another job → requires refund', () =>
    assert.equal(reason({ charge: { metadata: { jobId: 'other' } } }), 'job_mismatch'));
  test('no payment record at all → requires refund (unknown reference)', () =>
    assert.equal(reason({ payment: null }), 'unknown_reference'));
  test('redelivery for the locked job → already_locked', () =>
    assert.equal(decide({ job: { status: 'escrowLocked', paymentReference: REF }, payment: { status: 'escrowHeld' } }), 'already_locked'));
  test('redelivery after work started → already_recorded (no 500, no retry storm)', () =>
    assert.equal(decide({ job: { status: 'inProgress', paymentReference: REF }, payment: { status: 'escrowHeld' } }), 'already_recorded'));
  test('redelivery of a charge already flagged → already_flagged_for_refund', () =>
    assert.equal(decide({ job: { status: 'cancelled' }, payment: { status: 'requiresRefund' } }), 'already_flagged_for_refund'));
  test('late payment after cancellation → requires refund', () =>
    assert.equal(reason({ job: { status: 'cancelled' }, payment: { status: 'abandoned', abandonReason: 'job_cancelled' } }), 'paid_after_cancellation'));
  test('old reference paid while a newer one is pending → requires refund', () =>
    assert.equal(reason({ job: { pendingPaymentReference: 'pay_2' }, payment: { status: 'abandoned', abandonReason: 'superseded_by_retry' } }), 'superseded_by_newer_payment'));
  test('second charge after the job was already funded by another → requires refund', () =>
    assert.equal(reason({ job: { status: 'escrowLocked', paymentReference: 'pay_other' } }), 'duplicate_or_late_payment'));
  test('paid just after the 24 h expiry, nothing newer pending → recover_lock', () =>
    assert.equal(decide({ job: { status: 'inChat', pendingPaymentReference: undefined }, payment: { status: 'abandoned', abandonReason: 'stale_timeout' } }), 'recover_lock'));
  test('paid after expiry but the customer started a new payment → requires refund', () =>
    assert.equal(decide({ job: { status: 'paymentPending', pendingPaymentReference: 'pay_2' }, payment: { status: 'abandoned', abandonReason: 'stale_timeout' } }), 'requires_refund'));
});

describe('_decideStalePaymentAction — abandoned payments (D5)', () => {
  const H = 60 * 60 * 1000;
  const d = (ageH, verifications) => fns._decideStalePaymentAction({ ageMs: ageH * H, thresholdMs: 24 * H, verifications }).action;
  test('younger than 24 h → skip', () => assert.equal(d(23.9, [{ status: 'abandoned' }]), 'skip_young'));
  test('any successful charge → lock (missed-webhook recovery)', () =>
    assert.equal(d(30, [{ status: 'abandoned' }, { status: 'success', reference: 'r' }]), 'lock'));
  test('still in flight → wait', () => assert.equal(d(30, [{ status: 'ongoing' }]), 'wait_in_flight'));
  test('cannot verify → wait (never assume unpaid)', () => assert.equal(d(30, [null]), 'wait_unverifiable'));
  test('definitely unpaid → revert', () => {
    assert.equal(d(30, [{ status: 'abandoned' }]), 'revert');
    assert.equal(d(30, [{ status: 'failed' }, { status: 'not_found' }]), 'revert');
    assert.equal(d(30, []), 'revert'); // paymentPending with no checkout ever created
  });
});

// D1: recompute the loss thresholds from the exact formulas (official
// Paystack NG pricing, Nov 2026 — see the Stage 3 report for sources).
describe('D1 economics — exact loss thresholds under the approved policy', () => {
  const proc = (k) => Math.min(Math.round(k * 0.015) + (k >= 250000 ? 10000 : 0), 200000); // kobo
  const transfer = (k) => (k <= 500000 ? 1000 : k <= 5000000 ? 2500 : 5000);
  const stamp = (k) => (k >= 1000000 ? 5000 : 0);
  const net = (ngn, cfg) => {
    const c = fns._computeCharge(ngn, cfg);
    return c.platformFeeKobo - proc(c.totalKobo) - transfer(c.serviceAmountKobo) - stamp(c.serviceAmountKobo);
  };
  const lossBands = (cfg) => {
    const bands = []; let start = null;
    for (let p = cfg.minJobValueNgn; p <= 200000; p++) {
      const loss = net(p, cfg) < 0;
      if (loss && start === null) start = p;
      if (!loss && start !== null) { bands.push([start, p - 1]); start = null; }
    }
    if (start !== null) bands.push([start, 200000]);
    return bands;
  };

  test('Stage 3 policy (5%, ₦100 minimum) lost money in two bands', () => {
    assert.deepEqual(lossBands(MIN100), [[100, 291], [2381, 3211]]);
  });

  test('a ₦200 minimum platform fee removes every loss band from ₦100 up', () => {
    assert.deepEqual(lossBands({ ...MIN100, minPlatformFeeNgn: 200 }), []);
  });

  test('a ₦3,212 minimum job value alone also removes them (no fee floor)', () => {
    assert.deepEqual(lossBands({ ...MIN100, minJobValueNgn: 3212 }), []);
  });

  test('D1 (Stage 4): the shipped default IS the ₦3,212 minimum, with no loss band up to ₦200,000', () => {
    assert.equal(DEFAULTS.minJobValueNgn, 3212);
    assert.equal(DEFAULTS.minPlatformFeeNgn, 0);
    assert.equal(DEFAULTS.platformFeePercent, 5);
    assert.deepEqual(lossBands(DEFAULTS), []);
  });

  test('D1 (Stage 4): ₦3,211 is refused, ₦3,212 is accepted and nets ≥ 0', () => {
    assert.equal(fns._computeCharge(3211, DEFAULTS).reason, 'below_minimum_job_value');
    assert.equal(fns._computeCharge(3212, DEFAULTS).ok, true);
    assert.ok(net(3212, DEFAULTS) >= 0);
  });

  test('refund before work costs HandyTrust the whole processing fee', () => {
    const c = fns._computeCharge(10000, DEFAULTS);
    assert.equal(proc(c.totalKobo), 25750); // ₦257.50 on a ₦10,000 job
  });
});
