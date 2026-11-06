// RumptyCloud staging media — TIER 2 (LIVE) tests T2-01 … T2-10 (+ T2-11/12)
// (design/RUMPTYCLOUD_STAGING_INTEGRATION_PHASE2_PLAN.md §12, §14).
//
// Talks to the REAL staging bucket. Skipped (with the reasons, never values)
// unless ALL of these hold:
//   RUMPTY_LIVE=1
//   RUMPTY_LIVE_OWNER_CONFIRMED=balance-checked-auto-topup-off
//       (the owner checked the prepaid balance is ≤ $5 and auto top-up is off)
//   GCLOUD_PROJECT starts with "demo-" (Firestore emulator only)
//   functions/.secret.local holds the four RumptyCloud key variables
//   functions/.env.local holds the allow-listed bucket/endpoint/region
//
// Limits per run: ≤ 30 objects, ≤ 25 MB uploaded, synthetic fixtures only,
// every object under staging/livetest/<runId>/, and the run must END WITH
// ZERO objects under that prefix. Nothing outside the prefix is touched.
process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8090';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-handytrust-media-live';

const { test, describe, before, after } = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const FN = path.resolve(__dirname, '..');
const FIX = path.join(__dirname, 'fixtures', 'media');
const fixture = (n) => fs.readFileSync(path.join(FIX, n));
const sha = (b) => crypto.createHash('sha256').update(b).digest('hex');

function readEnvFile(file) {
  const out = {};
  if (!fs.existsSync(file)) return null;
  for (const raw of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    const i = line.indexOf('=');
    if (i < 1) continue;
    out[line.slice(0, i).trim()] = line.slice(i + 1).trim().replace(/^(['"])(.*)\1$/, '$2');
  }
  return out;
}

// ─── Gate ───────────────────────────────────────────────────────────────────
const reasons = [];
if (process.env.RUMPTY_LIVE !== '1') reasons.push('RUMPTY_LIVE is not 1');
if (process.env.RUMPTY_LIVE_OWNER_CONFIRMED !== 'balance-checked-auto-topup-off') reasons.push('owner balance/top-up confirmation missing');
if (!process.env.GCLOUD_PROJECT.startsWith('demo-')) reasons.push('project is not a demo- project');
const secrets = readEnvFile(path.join(FN, '.secret.local'));
const localEnv = readEnvFile(path.join(FN, '.env.local'));
if (!secrets) reasons.push('functions/.secret.local missing');
if (!localEnv) reasons.push('functions/.env.local missing');
let media;
let cfg;
const runId = `${Date.now().toString(36)}-${crypto.randomBytes(3).toString('hex')}`;
const PREFIX = `staging/livetest/${runId}`;
if (!reasons.length) {
  for (const k of ['RUMPTY_ENDPOINT', 'RUMPTY_REGION', 'RUMPTY_BUCKET']) process.env[k] = localEnv[k] || '';
  for (const k of ['RUMPTY_ACCESS_KEY_ID', 'RUMPTY_SECRET_ACCESS_KEY', 'RUMPTY_CLEANUP_ACCESS_KEY_ID', 'RUMPTY_CLEANUP_SECRET_ACCESS_KEY']) process.env[k] = secrets[k] || '';
  process.env.RUMPTY_KEY_PREFIX = PREFIX;
  delete process.env.RUMPTY_UPLOAD_MODE; // handler flows use the proxy path
  media = require('../media.js');
  cfg = media._config();
  if (cfg.problems.length) reasons.push(`configuration incomplete: ${cfg.problems.join(',')}`);
}
const LIVE = reasons.length === 0;
const skip = LIVE ? false : `live tests skipped: ${reasons.join('; ')}`;

// ─── Budget, evidence, helpers ──────────────────────────────────────────────
const BUDGET = { objects: 30, bytes: 25 * 1024 * 1024 };
const used = { objects: 0, bytes: 0 };
function spend(bytes) {
  used.objects += 1;
  used.bytes += bytes;
  if (used.objects > BUDGET.objects || used.bytes > BUDGET.bytes) throw new Error('LIVE BUDGET EXCEEDED — stopping');
}
const results = [];
const record = (r) => results.push({ at: new Date().toISOString(), ...r });
const keyFor = (name) => `${PREFIX}/${name}`;
const objectUrl = (key) => `${cfg.endpoint}/${cfg.bucket}/${key.split('/').map(encodeURIComponent).join('/')}`;
const wait = (ms) => new Promise((r) => setTimeout(r, ms));

let admin;
let db;
let H;
let store;
let s3; // raw SDK clients for vendor-behaviour probes
let janitor;
let sdk;

const req = (uid, data) => ({ auth: { uid, token: { email_verified: true, firebase: { sign_in_provider: 'password' } } }, data });

async function headStatus(key) {
  const h = await store.head(key, { role: 'janitor' });
  return h.exists ? 'present' : 'absent';
}
async function removeIfPresent(key) {
  if (!key.startsWith(`${PREFIX}/`)) throw new Error('refusing to delete outside the run prefix');
  if ((await headStatus(key)) === 'present') await store.remove(key);
  return headStatus(key);
}

before(async () => {
  if (!LIVE) return;
  admin = require('firebase-admin');
  db = admin.firestore();
  H = media.handlers;
  store = media._rumptyStore(cfg);
  sdk = require('@aws-sdk/client-s3');
  const mk = (c) => new sdk.S3Client({ endpoint: cfg.endpoint, region: cfg.region, forcePathStyle: true, credentials: c,
    requestChecksumCalculation: 'WHEN_REQUIRED', responseChecksumValidation: 'WHEN_REQUIRED', maxAttempts: 1 });
  s3 = mk(cfg.signer);
  janitor = mk(cfg.janitor);
  await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  await db.doc('users/live-owner').set({ name: 'Live owner (synthetic)' });
  await db.doc('users/live-other').set({ name: 'Other (synthetic)' });
});

after(async () => {
  if (!LIVE) return;
  // T2-10: remove everything under THIS run's prefix only, then prove zero.
  const listed = await store.list({ prefix: `${PREFIX}/`, maxKeys: 1000 });
  const failures = [];
  for (const o of listed) {
    try { await removeIfPresent(o.key); } catch (e) { failures.push(o.key); }
  }
  const left = await store.list({ prefix: `${PREFIX}/`, maxKeys: 1000 });
  record({ id: 'T2-10', objective: 'Run ends with zero objects under its prefix', operation: `list + delete under ${PREFIX}/`,
    expected: '0 objects', actual: `${left.length} objects`, evidence: { cleanedUp: listed.length, remainingKeys: left.map((o) => o.key), failures }, cleanup: left.length === 0 ? 'complete' : 'INCOMPLETE' });
  const report = path.join(process.env.RUMPTY_LIVE_REPORT_DIR || os.tmpdir(), `rumpty-live-${runId}.json`);
  fs.writeFileSync(report, JSON.stringify({ runId, prefix: PREFIX, budget: BUDGET, used, results }, null, 2));
  console.log(`live report: ${report}`); // contains keys and outcomes, never credentials
  assert.equal(left.length, 0, `objects left under ${PREFIX}/: ${left.map((o) => o.key).join(', ')}`);
});

describe('RumptyCloud live staging (T2)', { skip }, () => {
  let verifiedId;
  let verifiedKey;
  const png = fixture('synthetic_64x48.png');

  test('T2-01 full proxy upload → confirm → verified (real bucket)', async () => {
    const r = await H.requestMediaUpload(req('live-owner', { kind: 'test-portfolio', mimeType: 'image/png', sizeBytes: png.length, sha256: sha(png) }));
    spend(png.length);
    await H.uploadMediaContent(req('live-owner', { mediaId: r.mediaId, dataBase64: png.toString('base64') }));
    const c = await H.confirmMediaUpload(req('live-owner', { mediaId: r.mediaId }));
    verifiedId = r.mediaId;
    verifiedKey = (await db.doc(`media/${r.mediaId}`).get()).data().objectKey;
    record({ id: 'T2-01', objective: 'Upload through the Function and verify', operation: 'requestMediaUpload → uploadMediaContent → confirmMediaUpload',
      expected: 'verified', actual: c.status, evidence: { mediaId: r.mediaId, objectKey: verifiedKey }, cleanup: 'deleted in T2-11' });
    assert.equal(c.status, 'verified');
  });

  test('T2-02 signed GET works for the owner only; anonymous GET, anonymous listing and expired URLs are refused', async () => {
    const u = await H.getMediaUrl(req('live-owner', { mediaId: verifiedId }));
    const got = await fetch(u.url);
    const body = Buffer.from(await got.arrayBuffer());
    let otherDenied = false;
    await H.getMediaUrl(req('live-other', { mediaId: verifiedId })).catch((e) => { otherDenied = e.code === 'not-found'; });
    const anonGet = await fetch(objectUrl(verifiedKey));
    const anonList = await fetch(`${cfg.endpoint}/${cfg.bucket}?list-type=2&prefix=${encodeURIComponent(PREFIX + '/')}`);
    const short = await store.presignGet({ key: verifiedKey, expiresIn: 1 });
    await wait(2500);
    const expired = await fetch(short);
    record({ id: 'T2-02', objective: 'Read access only through short-lived signed URLs', operation: 'signed GET; non-owner getMediaUrl; unsigned GET; unsigned list; 1-second URL after 2.5 s',
      expected: 'owner 200 + same SHA-256; others refused; anonymous 403; expired 403',
      actual: `owner ${got.status} sha-match=${sha(body) === sha(png)}; non-owner denied=${otherDenied}; anonymous GET ${anonGet.status}; anonymous list ${anonList.status}; expired ${expired.status}`,
      evidence: {}, cleanup: 'n/a (no object created)' });
    assert.equal(got.status, 200);
    assert.equal(sha(body), sha(png));
    assert.ok(otherDenied);
    assert.ok([401, 403].includes(anonGet.status), `anonymous GET returned ${anonGet.status}`);
    assert.ok([401, 403].includes(anonList.status), `anonymous list returned ${anonList.status}`);
    assert.ok([401, 403].includes(expired.status), `expired URL returned ${expired.status}`);
  });

  test('T2-03 presigned PUT: a body that differs from the signed Content-Length is refused BY THE STORE', async () => {
    const outcomes = {};
    for (const [label, body] of [['larger', Buffer.concat([png, Buffer.from([0])])], ['smaller', png.subarray(0, png.length - 1)], ['chunked', null]]) {
      const key = keyFor(`t2-03-${label}.png`);
      const url = await store.presignPut({ key, contentType: 'image/png', contentLength: png.length, expiresIn: 60 });
      spend(body ? body.length : png.length);
      const init = body
        ? { method: 'PUT', body, headers: { 'Content-Type': 'image/png' } }
        : { method: 'PUT', body: new ReadableStream({ start(c) { c.enqueue(png); c.close(); } }), duplex: 'half', headers: { 'Content-Type': 'image/png' } };
      const res = await fetch(url, init).catch((e) => ({ status: `client-error:${e.name}` }));
      const present = await headStatus(key);
      outcomes[label] = { status: res.status, objectAfter: present, cleanup: present === 'present' ? await removeIfPresent(key) : 'none needed' };
    }
    const enforced = Object.values(outcomes).every((o) => o.objectAfter === 'absent' && !(o.status >= 200 && o.status < 300));
    record({ id: 'T2-03', objective: 'Size enforced before/during upload by the store (Q2)', operation: 'PUT larger, smaller and chunked bodies to a URL signed for the exact length',
      expected: 'every attempt refused and no object created', actual: enforced ? 'enforced' : 'NOT ENFORCED — presigned PUT must stay disabled', evidence: outcomes, cleanup: 'see evidence' });
    assert.ok(enforced, `size not enforced: ${JSON.stringify(outcomes)}`);
  });

  test('T2-04 presigned POST content-length-range', { skip: 'not implemented: only needed if T2-03 fails; the proxy path already enforces size independently of the vendor' }, () => {});

  test('T2-05 wrong x-amz-checksum-sha256 is rejected (or documented as ignored)', async () => {
    const key = keyFor('t2-05.png');
    spend(png.length);
    let outcome;
    try {
      await s3.send(new sdk.PutObjectCommand({ Bucket: cfg.bucket, Key: key, Body: png, ContentType: 'image/png', ChecksumSHA256: crypto.createHash('sha256').update('other').digest('base64') }));
      outcome = 'ACCEPTED (checksum header ignored)';
    } catch (e) {
      outcome = `rejected: ${e.name} ${e.$metadata && e.$metadata.httpStatusCode}`;
    }
    const cleanup = await removeIfPresent(key);
    record({ id: 'T2-05', objective: 'Does the store verify a supplied SHA-256 (Q4)?', operation: 'PutObject with a checksum of different bytes',
      expected: 'BadDigest-style rejection (informational: verification never relies on it)', actual: outcome, evidence: {}, cleanup });
    assert.equal(cleanup, 'absent');
  });

  test('T2-06 response-header overrides on signed GET (informational)', async () => {
    const { getSignedUrl } = require('@aws-sdk/s3-request-presigner');
    const url = await getSignedUrl(s3, new sdk.GetObjectCommand({ Bucket: cfg.bucket, Key: verifiedKey, ResponseContentType: 'text/plain' }), { expiresIn: 60 });
    const r = await fetch(url);
    record({ id: 'T2-06', objective: 'Are response-content-type overrides honoured (Q5)?', operation: 'signed GET with response-content-type=text/plain',
      expected: 'informational', actual: `status ${r.status}, content-type ${r.headers.get('content-type')}`, evidence: {}, cleanup: 'n/a' });
    assert.ok(r.status === 200 || r.status === 400 || r.status === 403);
  });

  test('T2-07 DeleteObject on a missing key (informational)', async () => {
    let outcome;
    try {
      const r = await janitor.send(new sdk.DeleteObjectCommand({ Bucket: cfg.bucket, Key: keyFor('t2-07-never-created.png') }));
      outcome = `success (HTTP ${r.$metadata.httpStatusCode})`;
    } catch (e) {
      outcome = `error ${e.name} (HTTP ${e.$metadata && e.$metadata.httpStatusCode})`;
    }
    record({ id: 'T2-07', objective: 'Idempotent delete behaviour (Q6)', operation: 'DeleteObject on a key never created', expected: 'success (S3 semantics); code treats 404 as success either way', actual: outcome, evidence: {}, cleanup: 'n/a' });
  });

  test('T2-08 ACL: unsigned x-amz-acl on a presigned PUT, and a public-read ACL set with K1, must not expose an object', async () => {
    const evidence = {};
    const k1 = keyFor('t2-08-header.png');
    const url = await store.presignPut({ key: k1, contentType: 'image/png', contentLength: png.length, expiresIn: 60 });
    spend(png.length);
    const put = await fetch(url, { method: 'PUT', body: png, headers: { 'Content-Type': 'image/png', 'x-amz-acl': 'public-read' } });
    evidence.unsignedAclPut = put.status;
    evidence.anonGetAfterHeader = (await headStatus(k1)) === 'present' ? (await fetch(objectUrl(k1))).status : 'no object';
    evidence.cleanupHeader = await removeIfPresent(k1);

    const k2 = keyFor('t2-08-acl.png');
    spend(png.length);
    await s3.send(new sdk.PutObjectCommand({ Bucket: cfg.bucket, Key: k2, Body: png, ContentType: 'image/png' }));
    try {
      await s3.send(new sdk.PutObjectAclCommand({ Bucket: cfg.bucket, Key: k2, ACL: 'public-read' }));
      evidence.putObjectAcl = 'accepted';
    } catch (e) {
      evidence.putObjectAcl = `rejected: ${e.name} ${e.$metadata && e.$metadata.httpStatusCode}`;
    }
    evidence.anonGetAfterAcl = (await fetch(objectUrl(k2))).status;
    evidence.cleanupAcl = await removeIfPresent(k2);
    const exposed = evidence.anonGetAfterHeader === 200 || evidence.anonGetAfterAcl === 200;
    record({ id: 'T2-08', objective: 'Can K1 or a presigned PUT make an object public (Q7)?', operation: 'presigned PUT + unsigned x-amz-acl; PutObjectAcl public-read; anonymous GET after each',
      expected: 'anonymous GET 401/403 in both cases', actual: exposed ? 'EXPOSED — stop: K1 can publish objects' : 'not exposed', evidence, cleanup: `${evidence.cleanupHeader}/${evidence.cleanupAcl}` });
    assert.ok(!exposed, `object exposed publicly: ${JSON.stringify(evidence)}`);
  });

  test('T2-09 presigned PUT: wrong Content-Type and expired URL are refused', async () => {
    const k1 = keyFor('t2-09-type.png');
    const u1 = await store.presignPut({ key: k1, contentType: 'image/png', contentLength: png.length, expiresIn: 60 });
    spend(png.length);
    const wrongType = await fetch(u1, { method: 'PUT', body: png, headers: { 'Content-Type': 'text/html' } });
    const typeObj = await headStatus(k1);
    const c1 = await removeIfPresent(k1);
    const k2 = keyFor('t2-09-expired.png');
    const u2 = await store.presignPut({ key: k2, contentType: 'image/png', contentLength: png.length, expiresIn: 1 });
    await wait(2500);
    spend(png.length);
    const expired = await fetch(u2, { method: 'PUT', body: png, headers: { 'Content-Type': 'image/png' } });
    const expObj = await headStatus(k2);
    const c2 = await removeIfPresent(k2);
    record({ id: 'T2-09', objective: 'Signed type and expiry are enforced', operation: 'PUT with text/html to an image/png URL; PUT after a 1-second URL expired',
      expected: '403 and no object, both', actual: `wrong type ${wrongType.status} (object ${typeObj}); expired ${expired.status} (object ${expObj})`, evidence: {}, cleanup: `${c1}/${c2}` });
    assert.ok(wrongType.status >= 400 && typeObj === 'absent');
    assert.ok(expired.status >= 400 && expObj === 'absent');
  });

  test('T2-11 (addition) authorised deletion, repeat deletion, object really gone', async () => {
    const d1 = await H.deleteMedia(req('live-owner', { mediaId: verifiedId }));
    const d2 = await H.deleteMedia(req('live-owner', { mediaId: verifiedId }));
    const gone = await headStatus(verifiedKey);
    record({ id: 'T2-11', objective: 'Delete through the backend; idempotent', operation: 'deleteMedia twice, then HEAD', expected: 'deleted, deleted, object absent',
      actual: `${d1.status}, ${d2.status}, object ${gone}`, evidence: { mediaId: verifiedId }, cleanup: gone });
    assert.deepEqual([d1.status, d2.status, gone], ['deleted', 'deleted', 'absent']);
  });

  test('T2-12 (addition) an object altered after upload is rejected at confirmation and removed', async () => {
    const r = await H.requestMediaUpload(req('live-owner', { kind: 'test-portfolio', mimeType: 'image/png', sizeBytes: png.length, sha256: sha(png) }));
    spend(png.length);
    await H.uploadMediaContent(req('live-owner', { mediaId: r.mediaId, dataBase64: png.toString('base64') }));
    const key = (await db.doc(`media/${r.mediaId}`).get()).data().objectKey;
    const tampered = Buffer.from(png);
    tampered[40] ^= 0x01;
    spend(tampered.length);
    await s3.send(new sdk.PutObjectCommand({ Bucket: cfg.bucket, Key: key, Body: tampered, ContentType: 'image/png' }));
    let reason = null;
    await H.confirmMediaUpload(req('live-owner', { mediaId: r.mediaId })).catch((e) => { reason = e.details && e.details.reason; });
    const after = await headStatus(key);
    const status = (await db.doc(`media/${r.mediaId}`).get()).data().status;
    record({ id: 'T2-12', objective: 'Server-side SHA-256 on the stored bytes; invalid object cleaned up', operation: 'proxy upload, overwrite with altered bytes, confirm',
      expected: 'checksum_mismatch, object removed, status rejected', actual: `${reason}, object ${after}, ${status}`, evidence: { mediaId: r.mediaId }, cleanup: after });
    assert.deepEqual([reason, after, status], ['checksum_mismatch', 'absent', 'rejected']);
  });
});
