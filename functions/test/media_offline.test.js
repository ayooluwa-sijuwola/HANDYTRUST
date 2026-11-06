// RumptyCloud staging media — TIER 1 (offline) tests T1-01 … T1-12
// (design/RUMPTYCLOUD_STAGING_INTEGRATION_PHASE2_PLAN.md §14).
// Firestore emulator only; the object store is an in-memory fake, so no
// network call and no credential is involved. T1-13 (rules) lives in
// firestore-tests/media_rules.test.js.
process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8090';
process.env.GCLOUD_PROJECT = 'demo-handytrust-media-offline';
// One project id for everything: `firebase emulators:exec` also sets
// FIREBASE_CONFIG (another project), which the Admin SDK would follow.
delete process.env.FIREBASE_CONFIG;

const { test, describe, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { Readable } = require('node:stream');
const { spawnSync } = require('node:child_process');

const media = require('../media.js');
const admin = require('firebase-admin');

const db = admin.firestore();
const H = media.handlers;
const PROJECT = process.env.GCLOUD_PROJECT;
const ROOT = path.resolve(__dirname, '..', '..');
const FIX = path.join(__dirname, 'fixtures', 'media');
const fixture = (name) => fs.readFileSync(path.join(FIX, name));
const sha = (b) => crypto.createHash('sha256').update(b).digest('hex');

// Dummy configuration. Values are assembled at run time so this file never
// contains a credential-looking literal (tool/check_no_secrets.js).
const fake = (...parts) => parts.join('-');
const SECRET_VALUES = [fake('test', 'signer', 'secret', 'value', 'do', 'not', 'log'), fake('test', 'cleanup', 'secret', 'value', 'do', 'not', 'log')];
const KEY_IDS = [fake('TESTSIGNER', 'ID'), fake('TESTCLEANUP', 'ID')];
const BASE_ENV = Object.fromEntries([
  ['RUMPTY_ENDPOINT', 'https://s3.rumptycloud.com'],
  ['RUMPTY_REGION', 'olas-closet'],
  ['RUMPTY_BUCKET', 'assets-handytrust-01a0f99e-5d6ffa'],
  ['RUMPTY_ACCESS_KEY_ID', KEY_IDS[0]],
  ['RUMPTY_SECRET_ACCESS_KEY', SECRET_VALUES[0]],
  ['RUMPTY_CLEANUP_ACCESS_KEY_ID', KEY_IDS[1]],
  ['RUMPTY_CLEANUP_SECRET_ACCESS_KEY', SECRET_VALUES[1]],
]);
const ENV_NAMES = [...Object.keys(BASE_ENV), 'RUMPTY_UPLOAD_MODE', 'RUMPTY_PRESIGNED_PUT_VERIFIED', 'RUMPTY_KEY_PREFIX'];

class FakeStore {
  constructor() {
    this.objects = new Map();
    this.calls = [];
    this.failRemove = 0;
    this.failPut = 0;
  }
  _err(status) { return Object.assign(new Error(`fake ${status} with secret ${SECRET_VALUES[0]}`), { name: 'ServiceUnavailable', $metadata: { httpStatusCode: status } }); }
  async put({ key, body, contentType }) {
    this.calls.push(['put', key]);
    if (this.failPut > 0) { this.failPut--; throw this._err(503); }
    this.objects.set(key, { body: Buffer.from(body), contentType });
  }
  async head(key) {
    const o = this.objects.get(key);
    return o ? { exists: true, size: o.body.length, contentType: o.contentType } : { exists: false };
  }
  async openRead(key) {
    const o = this.objects.get(key);
    if (!o) throw Object.assign(new Error('nf'), { name: 'NoSuchKey', $metadata: { httpStatusCode: 404 } });
    const half = Math.floor(o.body.length / 2);
    return Readable.from([o.body.subarray(0, half), o.body.subarray(half)]);
  }
  async presignPut({ key, contentType, contentLength, expiresIn }) {
    this.calls.push(['presignPut', key, contentType, contentLength, expiresIn]);
    return `https://s3.rumptycloud.com/assets-handytrust-01a0f99e-5d6ffa/${key}?X-Amz-Expires=${expiresIn}&X-Amz-Signature=fake`;
  }
  async presignGet({ key, expiresIn }) {
    this.calls.push(['presignGet', key, expiresIn]);
    return `https://s3.rumptycloud.com/assets-handytrust-01a0f99e-5d6ffa/${key}?X-Amz-Expires=${expiresIn}&X-Amz-Signature=fake`;
  }
  async remove(key) {
    this.calls.push(['remove', key]);
    if (this.failRemove > 0) { this.failRemove--; throw this._err(503); }
    this.objects.delete(key);
  }
  async list({ prefix, maxKeys }) {
    return [...this.objects.keys()].filter((k) => k.startsWith(prefix)).slice(0, maxKeys).map((key) => ({ key, size: this.objects.get(key).body.length }));
  }
}

let store;
let now;
let logs;
const origLog = console.log;
const origErr = console.error;

beforeEach(async () => {
  await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  for (const k of ENV_NAMES) delete process.env[k];
  Object.assign(process.env, BASE_ENV);
  store = new FakeStore();
  media._setMediaStore(store);
  now = Date.UTC(2026, 10, 6, 10, 0, 0);
  media._setMediaClock(() => now);
  logs = [];
  console.log = (...a) => logs.push(a.join(' '));
  console.error = (...a) => logs.push(a.join(' '));
  await db.doc('users/u1').set({ name: 'U1', accountStatus: 'active' });
  await db.doc('users/u2').set({ name: 'U2', accountStatus: 'active' });
  await db.doc('users/adm').set({ name: 'Admin' });
  await db.doc('admins/adm').set({ role: 'admin' });
});
afterEach(() => {
  console.log = origLog;
  console.error = origErr;
  media._setMediaStore(null);
  media._setMediaClock(null);
});

const req = (uid, data, { verified = true, provider = 'password' } = {}) => ({
  auth: uid ? { uid, token: { email_verified: verified, firebase: { sign_in_provider: provider } } } : undefined,
  data,
});
const code = (c) => (e) => { assert.equal(e.code, c, `${e.code}: ${e.message}`); return true; };
const reason = (c, r) => (e) => { assert.equal(e.code, c, `${e.code}: ${e.message}`); assert.equal(e.details && e.details.reason, r); return true; };
const upload = { png: ['synthetic_64x48.png', 'image/png'], jpg: ['synthetic_64x48.jpg', 'image/jpeg'], webp: ['synthetic_1x1.webp', 'image/webp'] };

async function request(uid, file = 'synthetic_64x48.png', mimeType = 'image/png', extra = {}) {
  const buf = fixture(file);
  return H.requestMediaUpload(req(uid, { kind: 'test-portfolio', mimeType, sizeBytes: buf.length, sha256: sha(buf), ...extra }));
}
async function uploadAndConfirm(uid, [file, mime] = upload.png, kind = 'test-portfolio') {
  const buf = fixture(file);
  const r = await H.requestMediaUpload(req(uid, { kind, mimeType: mime, sizeBytes: buf.length, sha256: sha(buf) }));
  await H.uploadMediaContent(req(uid, { mediaId: r.mediaId, dataBase64: buf.toString('base64') }));
  const c = await H.confirmMediaUpload(req(uid, { mediaId: r.mediaId }));
  assert.equal(c.status, 'verified');
  return r.mediaId;
}
const doc = async (id) => (await db.doc(`media/${id}`).get()).data();
const quota = async (uid) => (await db.doc(`media_quotas/${uid}`).get()).data() || {};
const global = async () => (await db.doc('media_system/limits').get()).data() || {};

describe('T1-01 authentication', () => {
  test('unauthenticated callers are rejected by every operation', async () => {
    for (const h of ['requestMediaUpload', 'uploadMediaContent', 'confirmMediaUpload', 'getMediaUrl', 'deleteMedia', 'runMediaSweep']) {
      await assert.rejects(H[h](req(null, {})), code('unauthenticated'), h);
    }
  });
  test('anonymous, unverified-email and suspended accounts cannot upload', async () => {
    await assert.rejects(H.requestMediaUpload(req('u1', { kind: 'test-portfolio' }, { provider: 'anonymous' })), code('permission-denied'));
    await assert.rejects(H.requestMediaUpload(req('u1', { kind: 'test-portfolio' }, { verified: false })), code('permission-denied'));
    await db.doc('users/u1').update({ accountStatus: 'suspended' });
    await assert.rejects(request('u1'), code('permission-denied'));
  });
  test('only admins can run the sweep', async () => {
    await assert.rejects(H.runMediaSweep(req('u1', {})), code('permission-denied'));
    const r = await H.runMediaSweep(req('adm', {}));
    assert.equal(r.expired, 0);
  });
});

describe('T1-02 input validation before anything is signed or stored', () => {
  test('unknown, real-category, video and identity kinds are refused', async () => {
    for (const kind of ['test-video', 'avatar', 'job-photo', 'dispute-evidence', 'identity-document', 'verification', '', 'TEST-AVATAR']) {
      const buf = fixture('synthetic_64x48.png');
      await assert.rejects(H.requestMediaUpload(req('u1', { kind, mimeType: 'image/png', sizeBytes: buf.length, sha256: sha(buf) })), code('invalid-argument'), kind);
    }
  });
  test('types other than JPEG/PNG/WebP are refused, and the extension must match', async () => {
    for (const mimeType of ['image/gif', 'image/svg+xml', 'application/pdf', 'video/mp4', 'text/html', '']) {
      await assert.rejects(request('u1', 'synthetic_64x48.png', mimeType), code('invalid-argument'), mimeType);
    }
    await assert.rejects(request('u1', 'synthetic_64x48.png', 'image/png', { fileExtension: 'jpg' }), code('invalid-argument'));
    await request('u1', 'synthetic_64x48.png', 'image/png', { fileExtension: '.PNG' }); // accepted
  });
  test('declared size and checksum are validated', async () => {
    const base = { kind: 'test-portfolio', mimeType: 'image/png', sha256: 'a'.repeat(64) };
    for (const sizeBytes of [0, -1, 1.5, '100', 5 * 1024 * 1024 + 1, undefined]) {
      await assert.rejects(H.requestMediaUpload(req('u1', { ...base, sizeBytes })), code('invalid-argument'), String(sizeBytes));
    }
    await assert.rejects(H.requestMediaUpload(req('u1', { ...base, kind: 'test-thumb', sizeBytes: 1024 * 1024 + 1 })), code('invalid-argument'));
    for (const sha256 of ['', 'xyz', 'A'.repeat(63), 'g'.repeat(64)]) {
      await assert.rejects(H.requestMediaUpload(req('u1', { ...base, sizeBytes: 100, sha256 })), code('invalid-argument'));
    }
    assert.equal(store.calls.length, 0); // nothing signed or stored
  });
  test('proxy mode by default: no URL, no object key, no bucket in the response', async () => {
    const r = await request('u1');
    assert.equal(r.mode, 'proxy');
    assert.deepEqual(Object.keys(r).sort(), ['expiresAt', 'maxBytes', 'mediaId', 'mode']);
    const m = await doc(r.mediaId);
    assert.match(m.objectKey, /^staging\/media\/test-portfolio\/2026\/11\/[0-9a-f-]{36}\.png$/);
    assert.equal(m.status, 'pending');
    assert.equal(m.visibility, 'private');
  });
  test('presigned PUT stays off unless explicitly verified; when on it binds type and exact length', async () => {
    process.env.RUMPTY_UPLOAD_MODE = 'presigned';
    assert.equal((await request('u1')).mode, 'proxy'); // not verified → never presigned
    process.env.RUMPTY_PRESIGNED_PUT_VERIFIED = 'true';
    const buf = fixture('synthetic_64x48.png');
    const r = await request('u1');
    assert.equal(r.mode, 'presigned');
    assert.equal(r.upload.method, 'PUT');
    assert.deepEqual(r.upload.headers, { 'Content-Type': 'image/png', 'Content-Length': String(buf.length) });
    const call = store.calls.find((c) => c[0] === 'presignPut');
    assert.deepEqual(call.slice(2), ['image/png', buf.length, 300]);
  });
  test('the real SDK presigner (offline, dummy keys) signs Content-Type and Content-Length and adds no checksum parameters', async () => {
    media._setMediaStore(null);
    const real = media._rumptyStore(media._config());
    const put = new URL(await real.presignPut({ key: 'staging/media/x.png', contentType: 'image/png', contentLength: 168, expiresIn: 300 }));
    assert.equal(put.searchParams.get('X-Amz-SignedHeaders'), 'content-length;content-type;host');
    assert.equal(put.searchParams.get('X-Amz-Expires'), '300');
    assert.equal(put.pathname, '/assets-handytrust-01a0f99e-5d6ffa/staging/media/x.png'); // path-style
    assert.ok(![...put.searchParams.keys()].some((k) => /checksum/i.test(k)));
    const get = new URL(await real.presignGet({ key: 'staging/media/x.png', expiresIn: 300 }));
    assert.equal(get.searchParams.get('X-Amz-SignedHeaders'), 'host');
    assert.ok(!put.href.includes(SECRET_VALUES[0]) && !get.href.includes(SECRET_VALUES[0]));
  });
});

describe('T1-03 rate limits and storage quotas (backend-enforced)', () => {
  test('10 requests per 10 minutes per user, then refused; the window resets', async () => {
    for (let i = 0; i < 10; i++) {
      const r = await request('u1');
      await H.deleteMedia(req('u1', { mediaId: r.mediaId })); // keep pending slots free
    }
    await assert.rejects(request('u1'), reason('resource-exhausted', 'user_rate'));
    now += 10 * 60 * 1000 + 1;
    await request('u1');
  });
  test('daily cap, per-user storage, global storage, pending caps', async () => {
    await db.doc('media_quotas/u1').set({ dayCount: 50, dayStart: admin.firestore.Timestamp.fromMillis(now - 1000) });
    await assert.rejects(request('u1'), reason('resource-exhausted', 'user_daily'));
    await db.doc('media_quotas/u2').set({ usedBytes: 100 * 1024 * 1024 - 100 });
    await assert.rejects(request('u2'), reason('resource-exhausted', 'user_storage'));
    await db.doc('media_quotas/u2').delete();
    await db.doc('media_system/limits').set({ usedBytes: 1024 * 1024 * 1024 - 100 });
    await assert.rejects(request('u2'), reason('resource-exhausted', 'global_storage'));
    await db.doc('media_system/limits').set({ pendingCount: 30 });
    await assert.rejects(request('u2'), reason('resource-exhausted', 'global_pending'));
  });
  test('global limit of 120 upload operations per minute across all users', async () => {
    await db.doc('media_system/limits').set({ minute: Math.floor(now / 60000), minuteCount: 120 });
    await assert.rejects(request('u1'), reason('resource-exhausted', 'global_rate'));
    now += 60 * 1000;
    await request('u1');
  });
  test('quota counters follow the lifecycle exactly', async () => {
    const size = fixture('synthetic_64x48.png').length;
    const id = await uploadAndConfirm('u1');
    assert.deepEqual([(await quota('u1')).usedBytes, (await quota('u1')).reservedBytes, (await quota('u1')).pendingCount], [size, 0, 0]);
    const p = await request('u1');
    assert.deepEqual([(await quota('u1')).reservedBytes, (await quota('u1')).pendingCount], [size, 1]);
    await H.deleteMedia(req('u1', { mediaId: p.mediaId }));
    await H.deleteMedia(req('u1', { mediaId: id }));
    const q = await quota('u1');
    const g = await global();
    assert.deepEqual([q.usedBytes, q.reservedBytes, q.pendingCount], [0, 0, 0]);
    assert.deepEqual([g.usedBytes, g.reservedBytes, g.pendingCount], [0, 0, 0]);
  });
});

describe('T1-04 pending uploads: caps, expiry and own clean-up', () => {
  test('at most 3 pending per user; expired ones are cleared before refusing', async () => {
    for (let i = 0; i < 3; i++) await request('u1');
    await assert.rejects(request('u1'), reason('resource-exhausted', 'user_pending'));
    now += 16 * 60 * 1000; // past the 15-minute pending lifetime
    await request('u1');
    const all = (await db.collection('media').where('ownerUid', '==', 'u1').get()).docs.map((d) => d.data().status).sort();
    assert.deepEqual(all, ['expired', 'expired', 'expired', 'pending']);
    assert.equal((await quota('u1')).pendingCount, 1);
  });
});

describe('T1-05 ownership and lifecycle order', () => {
  test("another user can neither upload into, confirm, view nor delete someone else's media", async () => {
    const buf = fixture('synthetic_64x48.png');
    const r = await request('u1');
    await assert.rejects(H.uploadMediaContent(req('u2', { mediaId: r.mediaId, dataBase64: buf.toString('base64') })), code('not-found'));
    await H.uploadMediaContent(req('u1', { mediaId: r.mediaId, dataBase64: buf.toString('base64') }));
    await assert.rejects(H.confirmMediaUpload(req('u2', { mediaId: r.mediaId })), code('not-found'));
    await H.confirmMediaUpload(req('u1', { mediaId: r.mediaId }));
    await assert.rejects(H.getMediaUrl(req('u2', { mediaId: r.mediaId })), code('not-found'));
    await assert.rejects(H.deleteMedia(req('u2', { mediaId: r.mediaId })), code('not-found'));
    assert.equal((await doc(r.mediaId)).status, 'verified');
  });
  test('confirm before upload is refused; an expired upload cannot be uploaded or confirmed', async () => {
    const r = await request('u1');
    await assert.rejects(H.confirmMediaUpload(req('u1', { mediaId: r.mediaId })), code('failed-precondition'));
    now += 16 * 60 * 1000;
    const buf = fixture('synthetic_64x48.png');
    await assert.rejects(H.uploadMediaContent(req('u1', { mediaId: r.mediaId, dataBase64: buf.toString('base64') })), code('failed-precondition'));
    assert.equal((await doc(r.mediaId)).status, 'expired');
    assert.equal(store.objects.size, 0);
  });
  test('malformed media ids are rejected without a lookup', async () => {
    for (const mediaId of ['', '../x', 'a/b', 'x'.repeat(21), null]) {
      await assert.rejects(H.getMediaUrl(req('u1', { mediaId })), code('invalid-argument'));
    }
  });
});

describe('T1-06 SHA-256 verified against the actual bytes', () => {
  test('a body that does not match the declared checksum is never stored', async () => {
    const r = await request('u1');
    const other = Buffer.from(fixture('synthetic_64x48.png'));
    other[other.length - 20] ^= 0xff; // same size, different content
    await assert.rejects(H.uploadMediaContent(req('u1', { mediaId: r.mediaId, dataBase64: other.toString('base64') })), reason('invalid-argument', 'checksum_mismatch'));
    assert.equal(store.objects.size, 0);
    assert.equal((await doc(r.mediaId)).status, 'rejected');
    assert.equal((await quota('u1')).pendingCount, 0);
  });
  test('confirm re-reads the stored object; tampering after upload is caught and the object removed', async () => {
    const buf = fixture('synthetic_64x48.png');
    const r = await request('u1');
    await H.uploadMediaContent(req('u1', { mediaId: r.mediaId, dataBase64: buf.toString('base64') }));
    const key = (await doc(r.mediaId)).objectKey;
    const tampered = Buffer.from(buf);
    tampered[40] ^= 0x01;
    store.objects.get(key).body = tampered;
    await assert.rejects(H.confirmMediaUpload(req('u1', { mediaId: r.mediaId })), reason('invalid-argument', 'checksum_mismatch'));
    assert.equal(store.objects.has(key), false);
    const m = await doc(r.mediaId);
    assert.deepEqual([m.status, m.rejectedReason], ['rejected', 'checksum_mismatch']);
  });
  test('presigned mode: confirm verifies what actually arrived (missing, wrong size, wrong bytes)', async () => {
    Object.assign(process.env, { RUMPTY_UPLOAD_MODE: 'presigned', RUMPTY_PRESIGNED_PUT_VERIFIED: 'true' });
    const buf = fixture('synthetic_64x48.png');
    const r = await request('u1');
    await assert.rejects(H.confirmMediaUpload(req('u1', { mediaId: r.mediaId })), code('failed-precondition')); // not arrived
    assert.equal((await doc(r.mediaId)).status, 'pending');
    const key = (await doc(r.mediaId)).objectKey;
    store.objects.set(key, { body: Buffer.concat([buf, Buffer.alloc(10)]), contentType: 'image/png' }); // oversized arrival
    await assert.rejects(H.confirmMediaUpload(req('u1', { mediaId: r.mediaId })), reason('invalid-argument', 'size_mismatch'));
    assert.equal(store.objects.has(key), false);
  });
});

describe('T1-07 content validation (bytes, not the declared type)', () => {
  test('genuine PNG, JPEG and WebP images are verified with their dimensions', async () => {
    for (const [k, dims] of [['png', [64, 48]], ['jpg', [64, 48]], ['webp', [1, 1]]]) {
      const id = await uploadAndConfirm('u1', upload[k]);
      const m = await doc(id);
      assert.deepEqual([m.status, m.width, m.height], ['verified', ...dims], k);
      assert.equal(m.verifiedSha256, m.sha256);
      await H.deleteMedia(req('u1', { mediaId: id }));
    }
  });
  const rejectWith = async (buf, mimeType, why, kind = 'test-portfolio') => {
    const r = await H.requestMediaUpload(req('u1', { kind, mimeType, sizeBytes: buf.length, sha256: sha(buf) }));
    await assert.rejects(H.uploadMediaContent(req('u1', { mediaId: r.mediaId, dataBase64: buf.toString('base64') })), reason('invalid-argument', why));
    assert.equal(store.objects.size, 0, why);
  };
  test('renamed, polyglot, truncated, oversized-dimension, oversized-thumbnail and random files are rejected', async () => {
    const png = fixture('synthetic_64x48.png');
    await rejectWith(png, 'image/jpeg', 'type_mismatch'); // PNG bytes declared as JPEG
    await rejectWith(Buffer.concat([fixture('synthetic_64x48.jpg'), Buffer.from('<html><script>alert(1)</script></html>')]), 'image/jpeg', 'truncated_or_trailing_data');
    await rejectWith(png.subarray(0, png.length - 20), 'image/png', 'truncated_or_trailing_data');
    const huge = Buffer.from(png);
    huge.writeUInt32BE(9000, 16);
    huge.writeUInt32BE(9000, 20);
    await rejectWith(huge, 'image/png', 'dimensions_too_large');
    await rejectWith(fixture('synthetic_600x400.png'), 'image/png', 'thumbnail_too_large', 'test-thumb');
    await rejectWith(crypto.randomBytes(500), 'image/png', 'unrecognised_format');
  });
  test('the received size must equal the declared size', async () => {
    const buf = fixture('synthetic_64x48.png');
    const r = await H.requestMediaUpload(req('u1', { kind: 'test-portfolio', mimeType: 'image/png', sizeBytes: buf.length + 5, sha256: sha(buf) }));
    await assert.rejects(H.uploadMediaContent(req('u1', { mediaId: r.mediaId, dataBase64: buf.toString('base64') })), reason('invalid-argument', 'size_mismatch'));
  });
  test('an over-limit body is refused before decoding', async () => {
    const r = await request('u1');
    const big = 'A'.repeat(Math.ceil((5 * 1024 * 1024) / 3) * 4 + 8);
    await assert.rejects(H.uploadMediaContent(req('u1', { mediaId: r.mediaId, dataBase64: big })), code('invalid-argument'));
  });
});

describe('T1-08 temporary read URLs', () => {
  test('owner and admin get a 300-second URL; others and unverified media are refused', async () => {
    const id = await uploadAndConfirm('u1');
    const r = await H.getMediaUrl(req('u1', { mediaId: id }));
    assert.equal(r.expiresAt, now + 300 * 1000);
    assert.deepEqual(store.calls.filter((c) => c[0] === 'presignGet').pop().slice(2), [300]);
    await H.getMediaUrl(req('adm', { mediaId: id }));
    await assert.rejects(H.getMediaUrl(req('u2', { mediaId: id })), code('not-found'));
    const p = await request('u1');
    await assert.rejects(H.getMediaUrl(req('u1', { mediaId: p.mediaId })), code('failed-precondition'));
  });
  test('no signed URL (or any URL) is ever written to Firestore', async () => {
    const id = await uploadAndConfirm('u1');
    await H.getMediaUrl(req('u1', { mediaId: id }));
    for (const col of ['media', 'media_quotas', 'media_system', 'admin_alerts']) {
      for (const d of (await db.collection(col).get()).docs) {
        const json = JSON.stringify(d.data());
        assert.ok(!/https?:\/\/|X-Amz-Signature/i.test(json), `${col}/${d.id}`);
      }
    }
  });
});

describe('T1-09 deletion: revoke first, verify gone, retry safely', () => {
  test('owner deletes; repeat is idempotent; admin may delete; the object is gone', async () => {
    const id = await uploadAndConfirm('u1');
    const key = (await doc(id)).objectKey;
    assert.deepEqual(await H.deleteMedia(req('u1', { mediaId: id })), { mediaId: id, status: 'deleted', retryScheduled: false });
    assert.equal(store.objects.has(key), false);
    assert.equal((await H.deleteMedia(req('u1', { mediaId: id }))).status, 'deleted');
    const id2 = await uploadAndConfirm('u1');
    assert.equal((await H.deleteMedia(req('adm', { mediaId: id2 }))).status, 'deleted');
    const m = await doc(id2);
    assert.equal(m.deleteRequestedBy, 'adm'); // audit
  });
  test('a failed delete is not reported as success, access is revoked, and the sweep finishes it later', async () => {
    const id = await uploadAndConfirm('u1');
    store.failRemove = 1;
    const r = await H.deleteMedia(req('u1', { mediaId: id }));
    assert.deepEqual([r.status, r.retryScheduled], ['deleting', true]);
    const m = await doc(id);
    assert.equal(m.deleteAttempts, 1);
    assert.deepEqual(Object.keys(m.lastDeleteError).sort(), ['errorName', 'httpStatus']);
    await assert.rejects(H.getMediaUrl(req('u1', { mediaId: id })), code('failed-precondition')); // revoked first
    now += 61 * 1000;
    const s = await media._sweepMedia(media._config());
    assert.equal(s.deleteRetried, 1);
    assert.equal((await doc(id)).status, 'deleted');
  });
  test('after 8 failed attempts the record is marked delete_failed and an admin alert is raised', async () => {
    const id = await uploadAndConfirm('u1');
    store.failRemove = 100;
    await H.deleteMedia(req('u1', { mediaId: id }));
    for (let i = 0; i < 10; i++) {
      now += 25 * 3600e3;
      await media._sweepMedia(media._config());
    }
    assert.equal((await doc(id)).status, 'delete_failed');
    assert.equal((await doc(id)).deleteAttempts, 8);
    const alert = (await db.doc(`admin_alerts/media_delete_failed_${id}`).get()).data();
    assert.equal(alert.type, 'media_delete_failed');
    assert.equal((await H.deleteMedia(req('u1', { mediaId: id }))).status, 'delete_failed'); // no false success
  });
  test('deleting a pending upload (nothing stored) completes and releases the reservation', async () => {
    const r = await request('u1');
    assert.equal((await H.deleteMedia(req('u1', { mediaId: r.mediaId }))).status, 'deleted');
    assert.equal((await quota('u1')).pendingCount, 0);
  });
});

describe('T1-10 sweeps', () => {
  test('abandoned uploads expire; interrupted verification is rejected and cleaned up', async () => {
    const a = await request('u1');
    const b = await request('u1');
    const buf = fixture('synthetic_64x48.png');
    await H.uploadMediaContent(req('u1', { mediaId: b.mediaId, dataBase64: buf.toString('base64') }));
    await db.doc(`media/${b.mediaId}`).update({ status: 'verifying', verifyingSince: admin.firestore.Timestamp.fromMillis(now) });
    now += 16 * 60 * 1000;
    const s = await media._sweepMedia(media._config());
    assert.deepEqual([s.expired, s.interrupted], [1, 1]);
    assert.equal((await doc(a.mediaId)).status, 'expired');
    const mb = await doc(b.mediaId);
    assert.deepEqual([mb.status, mb.rejectedReason], ['rejected', 'verification_interrupted']);
    assert.equal(store.objects.size, 0);
  });
  test('reconciliation only REPORTS untracked objects; it never deletes them', async () => {
    store.objects.set('staging/media/test-portfolio/2026/11/orphan.png', { body: Buffer.from('x'), contentType: 'image/png' });
    const s = await media._sweepMedia(media._config(), { reconcile: true });
    assert.deepEqual(s.orphans, ['staging/media/test-portfolio/2026/11/orphan.png']);
    assert.equal(store.objects.size, 1);
  });
});

describe('T1-11 missing or invalid configuration, and nothing secret in logs or errors', () => {
  test('missing keys or a non-allow-listed bucket/endpoint/prefix fail closed with a fixed message', async () => {
    for (const [k, v] of [['RUMPTY_SECRET_ACCESS_KEY', ''], ['RUMPTY_CLEANUP_ACCESS_KEY_ID', ''], ['RUMPTY_BUCKET', 'some-production-bucket'], ['RUMPTY_ENDPOINT', 'https://s3.amazonaws.com'], ['RUMPTY_KEY_PREFIX', 'prod/media'], ['RUMPTY_KEY_PREFIX', 'staging/../x']]) {
      Object.assign(process.env, BASE_ENV);
      delete process.env.RUMPTY_KEY_PREFIX;
      process.env[k] = v;
      const buf = fixture('synthetic_64x48.png');
      await assert.rejects(H.requestMediaUpload(req('u1', { kind: 'test-portfolio', mimeType: 'image/png', sizeBytes: buf.length, sha256: sha(buf) })), (e) => {
        assert.equal(e.code, 'failed-precondition', k);
        assert.equal(e.message, 'Media storage is not configured.');
        return true;
      });
    }
  });
  test('no secret or key id appears in any log line or error, even when the store error text contains one', async () => {
    const errors = [];
    const id = await uploadAndConfirm('u1');
    store.failRemove = 1;
    await H.deleteMedia(req('u1', { mediaId: id }));
    store.failPut = 1;
    const r = await request('u1');
    await H.uploadMediaContent(req('u1', { mediaId: r.mediaId, dataBase64: fixture('synthetic_64x48.png').toString('base64') })).catch((e) => errors.push(`${e.message} ${JSON.stringify(e.details || {})}`));
    process.env.RUMPTY_SECRET_ACCESS_KEY = '';
    await request('u1').catch((e) => errors.push(`${e.message} ${JSON.stringify(e.details || {})}`));
    const text = logs.concat(errors).join('\n');
    assert.ok(logs.length > 3);
    for (const s of [...SECRET_VALUES, ...KEY_IDS]) assert.ok(!text.includes(s), 'leaked value');
    assert.ok(text.includes('"errorName":"ServiceUnavailable"'));
  });
});

describe('T1-11b key roles and environment', () => {
  const buf = () => fixture('synthetic_64x48.png');
  const ask = () => H.requestMediaUpload(req('u1', { kind: 'test-portfolio', mimeType: 'image/png', sizeBytes: buf().length, sha256: sha(buf()) }));
  const problems = (env) => media._config({ ...process.env, ...env }).problems;
  test('refuses to run for the production project (or any non-demo, non-staging project)', async () => {
    for (const projectId of ['handytrust', 'other-project', '']) {
      assert.ok(problems({ GCLOUD_PROJECT: projectId, FIREBASE_CONFIG: JSON.stringify({ projectId }) }).includes('project'), projectId);
    }
    assert.deepEqual(problems({ GCLOUD_PROJECT: 'handytrust-staging', FIREBASE_CONFIG: '' }), []);
    const saved = process.env.GCLOUD_PROJECT;
    process.env.GCLOUD_PROJECT = 'handytrust';
    try {
      await assert.rejects(ask(), code('failed-precondition'));
    } finally {
      process.env.GCLOUD_PROJECT = saved;
    }
  });
  test('the cleanup key may not silently be the app key; one key only by explicit owner choice', () => {
    const same = Object.fromEntries([['RUMPTY_CLEANUP_ACCESS_KEY_ID', KEY_IDS[0]], ['RUMPTY_CLEANUP_SECRET_ACCESS_KEY', SECRET_VALUES[0]]]);
    assert.ok(problems(same).includes('cleanup_key_same_as_signer'));
    assert.ok(problems({ RUMPTY_CLEANUP_ACCESS_KEY_ID: '', RUMPTY_CLEANUP_SECRET_ACCESS_KEY: '' }).includes('cleanup_key'));
    assert.deepEqual(problems({ ...same, RUMPTY_SINGLE_KEY_ACCEPTED: 'true' }), []);
    assert.deepEqual(problems({ RUMPTY_CLEANUP_ACCESS_KEY_ID: '', RUMPTY_CLEANUP_SECRET_ACCESS_KEY: '', RUMPTY_SINGLE_KEY_ACCEPTED: 'true' }), []);
  });
  test('reconciliation without list permission reports "unavailable" and still completes the sweep', async () => {
    store.list = async () => { throw Object.assign(new Error('denied'), { name: 'AccessDenied', $metadata: { httpStatusCode: 403 } }); };
    const s = await media._sweepMedia(media._config(), { reconcile: true });
    assert.equal(s.reconcile, 'unavailable');
    assert.deepEqual(s.orphans, []);
  });
});

describe('T1-12 credentials cannot enter Git', () => {
  const git = (...a) => spawnSync('git', a, { cwd: ROOT, encoding: 'utf8' });
  test('the credential and local-config files are ignored and untracked', () => {
    for (const f of ['functions/.secret.local', 'functions/.env.local', 'tool/.secret-prefix.local']) {
      assert.equal(git('check-ignore', '--no-index', '-q', f).status, 0, f);
      assert.equal(git('ls-files', '--error-unmatch', f).status !== 0, true, `${f} is tracked`);
    }
  });
  test('the pre-commit scan blocks a fake credential and passes clean code (scans text; nothing is staged)', () => {
    const scan = (text) => spawnSync(process.execPath, [path.join(ROOT, 'tool', 'check_no_secrets.js'), '--stdin'], { input: text, encoding: 'utf8' });
    const value = ['ABCD', 'EFGH', 'IJKL', 'MNOP'].join('');
    const bad = `+++ b/functions/config.js\n+RUMPTY_SECRET_ACCESS_KEY=${value}${value}\n`;
    const r1 = scan(bad);
    assert.equal(r1.status, 1);
    assert.ok(!r1.stderr.includes(value)); // the report never repeats the value
    assert.equal(scan('+++ b/functions/.secret.local\n+x\n').status, 1);
    const clean = scan(`+++ b/functions/media.js\n+  signer: { accessKeyId: env.RUMPTY_ACCESS_KEY_ID || '' },\n+const h = '${'a'.repeat(64)}';\n`);
    assert.equal(clean.status, 0, clean.stderr);
  });
});
