/**
 * Unit tests for the Paystack webhook signature verification fix
 * (design/PHASE_10_AUTHENTICATED_PAYMENT_QA.md Phase 10B-2).
 *
 * _computePaystackSignature is a pure function (no Firestore/network
 * dependency) — tested directly here. Confirms the exact algorithm
 * Paystack documents: HMAC-SHA512 of the raw body, keyed with the account
 * secret. https://paystack.com/docs/payments/webhooks/ (verified current
 * during Phase 10B) — "the single most common webhook bug" is hashing a
 * re-serialized/parsed body instead of the exact raw bytes; these tests
 * specifically cover that distinction.
 *
 * Run with: node --test functions/test/webhook_signature.test.js
 */
const { test, describe } = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { _computePaystackSignature } = require('../index.js');

const SECRET = 'sk_test_fake_secret_for_unit_tests_only';

describe('_computePaystackSignature', () => {
  test('matches a manually-computed HMAC-SHA512 of the exact same bytes', () => {
    const rawBody = Buffer.from('{"event":"charge.success","data":{"reference":"abc123"}}');
    const expected = crypto.createHmac('sha512', SECRET).update(rawBody).digest('hex');
    assert.equal(_computePaystackSignature(rawBody, SECRET), expected);
  });

  test('a single byte of difference produces a completely different signature (tamper-evident)', () => {
    const original = Buffer.from('{"event":"charge.success","data":{"amount":50000}}');
    const tampered = Buffer.from('{"event":"charge.success","data":{"amount":99999}}');
    assert.notEqual(
      _computePaystackSignature(original, SECRET),
      _computePaystackSignature(tampered, SECRET)
    );
  });

  test('re-serializing through JSON.parse/JSON.stringify can change the signature — the exact bug this fix closes', () => {
    // A raw body with a specific key order / spacing, as Paystack might
    // actually send it.
    const rawBody = Buffer.from('{"event":"charge.success","data":{"reference":"ref1","amount":50000}}');
    const reSerialized = Buffer.from(JSON.stringify(JSON.parse(rawBody.toString())));
    // These two byte sequences are NOT guaranteed identical in general
    // (different key order, whitespace, or number formatting would
    // diverge) — this specific input happens to already be in
    // JSON.stringify's canonical form, so demonstrate the point
    // differently: confirm the function is sensitive to exactly which
    // bytes it's given, which is what makes hashing the wrong ones a bug.
    const differentlyFormatted = Buffer.from(
      JSON.stringify(JSON.parse(rawBody.toString()), null, 1) // pretty-printed — same data, different bytes
    );
    assert.notEqual(
      _computePaystackSignature(rawBody, SECRET),
      _computePaystackSignature(differentlyFormatted, SECRET),
      'same logical event, different byte representation — must produce different signatures, ' +
        'proving why hashing anything other than the exact raw bytes Paystack sent is unsafe'
    );
  });

  test('uses SHA-512 specifically (not SHA-256) — Paystack is explicit this is the non-default choice', () => {
    const rawBody = Buffer.from('{"event":"ping"}');
    const sha512 = crypto.createHmac('sha512', SECRET).update(rawBody).digest('hex');
    const sha256 = crypto.createHmac('sha256', SECRET).update(rawBody).digest('hex');
    assert.equal(_computePaystackSignature(rawBody, SECRET), sha512);
    assert.notEqual(_computePaystackSignature(rawBody, SECRET), sha256);
  });

  test('a different secret key produces a different signature for the same body', () => {
    const rawBody = Buffer.from('{"event":"charge.success"}');
    assert.notEqual(
      _computePaystackSignature(rawBody, SECRET),
      _computePaystackSignature(rawBody, 'a_completely_different_secret')
    );
  });
});
