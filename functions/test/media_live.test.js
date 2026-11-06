// RumptyCloud staging media — TIER 2 (LIVE) tests against the REAL staging
// bucket (design/RUMPTYCLOUD_STAGING_INTEGRATION_PHASE2_PLAN.md §12, §14 and
// design/RUMPTYCLOUD_LIVE_STAGING_TEST_GUIDE.md).
//
// Skipped (with reasons, never values) unless ALL of these hold:
//   RUMPTY_LIVE=1
//   RUMPTY_LIVE_OWNER_CONFIRMED=balance-checked-auto-topup-off
//       (owner confirmed: prepaid balance ≤ $5, auto top-up OFF, checked now)
//   GCLOUD_PROJECT starts with "demo-" (Firestore emulator only)
//   functions/.secret.local holds the RumptyCloud key variables
//   functions/.env.local holds the allow-listed bucket/endpoint/region
//
// Limits per run: ≤ 30 objects, ≤ 25 MB, synthetic fixtures only, every
// object under staging/livetest/<runId>/, every created key recorded and its
// deletion verified BY KEY. Nothing outside the run prefix is ever deleted.
// No credential and no signed URL is ever printed or recorded.
process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8090';
// One project id for the Admin SDK, the reset and the gate: under
// `firebase emulators:exec` FIREBASE_CONFIG names the emulator's project.
try { process.env.GCLOUD_PROJECT = JSON.parse(process.env.FIREBASE_CONFIG || '{}').projectId || process.env.GCLOUD_PROJECT || 'demo-handytrust-media-live'; } catch (_) { process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-handytrust-media-live'; }
process.env.FIREBASE_CONFIG = JSON.stringify({ projectId: process.env.GCLOUD_PROJECT });

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
  if (!fs.existsSync(file)) return null;
  const out = {};
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
  for (const k of ['RUMPTY_ENDPOINT', 'RUMPTY_REGION', 'RUMPTY_BUCKET', 'RUMPTY_SINGLE_KEY_ACCEPTED']) process.env[k] = localEnv[k] || '';
  for (const k of ['RUMPTY_ACCESS_KEY_ID', 'RUMPTY_SECRET_ACCESS_KEY', 'RUMPTY_CLEANUP_ACCESS_KEY_ID', 'RUMPTY_CLEANUP_SECRET_ACCESS_KEY']) process.env[k] = secrets[k] || '';
  process.env.RUMPTY_KEY_PREFIX = PREFIX;
  delete process.env.RUMPTY_UPLOAD_MODE; // handler flows start on the proxy path
  delete process.env.RUMPTY_PRESIGNED_PUT_VERIFIED;
  media = require('../media.js');
  cfg = media._config();
  if (cfg.problems.length) reasons.push(`configuration incomplete: ${cfg.problems.join(',')}`);
}
const LIVE = reasons.length === 0;
const skip = LIVE ? false : `live tests skipped: ${reasons.join('; ')}`;

// ─── Budget, evidence, helpers ──────────────────────────────────────────────
const BUDGET = { objects: 30, bytes: 25 * 1024 * 1024 };
const used = { objects: 0, bytes: 0 };
const created = new Map(); // key -> { bytes, by }
function willCreate(key, bytes, by) {
  if (!key.startsWith(`${PREFIX}/`) && !key.startsWith(`${cfg.keyPrefix}/`)) throw new Error('refusing to write outside the run prefix');
  used.objects += 1;
  used.bytes += bytes;
  if (used.objects > BUDGET.objects || used.bytes > BUDGET.bytes) throw new Error('LIVE BUDGET EXCEEDED — stopping');
  created.set(key, { bytes, by });
}
const results = [];
const record = (r) => results.push({ at: new Date().toISOString(), ...r });
const keyFor = (name) => `${PREFIX}/${name}`;
const objectUrl = (key) => `${cfg.endpoint}/${cfg.bucket}/${key.split('/').map(encodeURIComponent).join('/')}`;
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
const errInfo = (e) => `${e && e.name} (HTTP ${e && e.$metadata && e.$metadata.httpStatusCode})`;

let admin;
let db;
let H;
let store;
let s3k1; // raw SDK clients, for vendor-behaviour probes only
let s3k2;
let sdk;
let permissionsOk = false;
let presignedSafe = { length: false, acl: false };

const req = (uid, data) => ({ auth: { uid, token: { email_verified: true, firebase: { sign_in_provider: 'password' } } }, data });
async function k1Head(key) {
  const h = await store.head(key);
  return h.exists ? 'present' : 'absent';
}
async function removeOwn(key) {
  if (!created.has(key)) throw new Error(`refusing to delete a key this run did not create: ${key}`);
  if ((await k1Head(key)) === 'present') await store.remove(key);
  return k1Head(key);
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
  s3k1 = mk(cfg.signer);
  s3k2 = mk(cfg.janitor);
  await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  await db.doc('users/live-owner').set({ name: 'Live owner (synthetic)' });
  await db.doc('users/live-other').set({ name: 'Other (synthetic)' });
});

after(async () => {
  if (!LIVE) return;
  // T2-10: every key this run created must be gone (checked one by one).
  const remaining = [];
  for (const key of created.keys()) {
    try {
      if ((await k1Head(key)) === 'present') {
        await store.remove(key);
        if ((await k1Head(key)) === 'present') remaining.push(key);
      }
    } catch (_) {
      remaining.push(key);
    }
  }
  let prefixListing = 'not permitted';
  try {
    prefixListing = `${(await store.list({ prefix: `${PREFIX}/`, maxKeys: 1000 })).length} objects under the run prefix`;
  } catch (_) { /* list is optional */ }
  record({ id: 'T2-10', objective: 'Run ends with every created object removed', operation: 'HEAD each recorded key (and list the run prefix if permitted)',
    expected: '0 remaining', actual: `${remaining.length} remaining; ${prefixListing}`, evidence: { createdKeys: [...created.keys()], remaining }, cleanup: remaining.length ? 'INCOMPLETE' : 'complete' });
  const report = path.join(process.env.RUMPTY_LIVE_REPORT_DIR || os.tmpdir(), `rumpty-live-${runId}.json`);
  fs.writeFileSync(report, JSON.stringify({ runId, prefix: PREFIX, bucket: cfg.bucket, endpoint: cfg.endpoint, budget: BUDGET, used, createdKeys: [...created.keys()], results }, null, 2));
  console.log(`live evidence: ${report}`); // keys and outcomes only; no credentials, no URLs
  assert.equal(remaining.length, 0, `objects left behind: ${remaining.join(', ')}`);
});

describe('RumptyCloud live staging', { skip }, () => {
  test('T2-00 key permissions (the required ones must work; the others are recorded)', async () => {
    const probe = Buffer.from(`HandyTrust permission probe ${runId}`);
    const key = keyFor('t2-00-permission-probe.txt');
    const ev = { mode: cfg.singleKey ? 'single key (accepted by owner)' : 'two keys' };
    let initialCount = 'not permitted (list is optional)';
    try {
      const all = await store.list({ prefix: '', maxKeys: 1000 });
      initialCount = `${all.length}${all.length === 1000 ? '+' : ''} objects in the bucket before this run`;
    } catch (e) { ev.k2List = `denied ${errInfo(e)}`; }
    if (!ev.k2List) ev.k2List = 'allowed';
    willCreate(key, probe.length, 'T2-00');
    try {
      await s3k1.send(new sdk.PutObjectCommand({ Bucket: cfg.bucket, Key: key, Body: probe, ContentType: 'text/plain' }));
      ev.k1Write = 'allowed';
    } catch (e) { ev.k1Write = `DENIED ${errInfo(e)}`; }
    try { await s3k1.send(new sdk.HeadObjectCommand({ Bucket: cfg.bucket, Key: key })); ev.k1Head = 'allowed'; } catch (e) { ev.k1Head = `DENIED ${errInfo(e)}`; }
    try {
      const g = await s3k1.send(new sdk.GetObjectCommand({ Bucket: cfg.bucket, Key: key }));
      ev.k1Read = Buffer.from(await g.Body.transformToByteArray()).equals(probe) ? 'allowed (content matches)' : 'allowed (CONTENT MISMATCH)';
    } catch (e) { ev.k1Read = `DENIED ${errInfo(e)}`; }
    if (!cfg.singleKey) {
      try {
        await s3k2.send(new sdk.PutObjectCommand({ Bucket: cfg.bucket, Key: keyFor('t2-00-k2-write-probe.txt'), Body: Buffer.from('x'), ContentType: 'text/plain' }));
        created.set(keyFor('t2-00-k2-write-probe.txt'), { bytes: 1, by: 'T2-00' });
        used.objects += 1;
        ev.k2Write = 'allowed (broader than needed)';
      } catch (e) { ev.k2Write = `denied (as intended) ${errInfo(e)}`; }
    }
    try {
      await s3k2.send(new sdk.DeleteObjectCommand({ Bucket: cfg.bucket, Key: key }));
      ev.cleanupDelete = 'allowed';
    } catch (e) { ev.cleanupDelete = `DENIED ${errInfo(e)}`; }
    ev.goneAfterDelete = await k1Head(key);
    const required = [ev.k1Write, ev.k1Head, ev.k1Read].every((v) => v.startsWith('allowed')) && ev.cleanupDelete === 'allowed' && ev.goneAfterDelete === 'absent';
    permissionsOk = required;
    record({ id: 'T2-00', objective: 'Verify key permissions before any other live operation', operation: 'K1 put/head/get; K2 delete (+ list, + write attempt)',
      expected: 'K1 read+write allowed; cleanup delete allowed', actual: required ? 'required permissions verified' : 'REQUIRED PERMISSION MISSING — stop', evidence: { ...ev, initialCount }, cleanup: ev.goneAfterDelete });
    assert.ok(required, `required permission missing: ${JSON.stringify(ev)}`);
  });

  const formats = [['JPEG', 'synthetic_64x48.jpg', 'image/jpeg', [64, 48]], ['PNG', 'synthetic_64x48.png', 'image/png', [64, 48]], ['WebP', 'synthetic_1x1.webp', 'image/webp', [1, 1]]];
  const uploaded = {};

  for (const [label, file, mime, dims] of formats) {
    test(`T2-01 ${label}: upload → confirm → verified; HEAD metadata and Firestore record correct`, async (t) => {
      if (!permissionsOk) return t.skip('permissions not verified');
      const buf = fixture(file);
      const r = await H.requestMediaUpload(req('live-owner', { kind: 'test-portfolio', mimeType: mime, sizeBytes: buf.length, sha256: sha(buf) }));
      const key = (await db.doc(`media/${r.mediaId}`).get()).data().objectKey;
      willCreate(key, buf.length, `T2-01 ${label}`);
      await H.uploadMediaContent(req('live-owner', { mediaId: r.mediaId, dataBase64: buf.toString('base64') }));
      const c = await H.confirmMediaUpload(req('live-owner', { mediaId: r.mediaId }));
      const head = await store.head(key);
      const doc = (await db.doc(`media/${r.mediaId}`).get()).data();
      uploaded[label] = { id: r.mediaId, key, buf };
      const docOk = doc.status === 'verified' && doc.ownerUid === 'live-owner' && doc.objectKey === key && doc.verifiedSha256 === sha(buf)
        && doc.width === dims[0] && doc.height === dims[1] && doc.quota === 'used' && !/https?:\/\//.test(JSON.stringify(doc));
      record({ id: `T2-01-${label}`, objective: `${label} upload stored and verified`, operation: 'requestMediaUpload → uploadMediaContent → confirmMediaUpload; HEAD; Firestore read',
        expected: `verified; HEAD ${buf.length} B ${mime}; record consistent`, actual: `${c.status}; HEAD ${head.size} B ${head.contentType}; record ${docOk ? 'consistent' : 'INCONSISTENT'}`,
        evidence: { mediaId: r.mediaId, objectKey: key }, cleanup: 'deleted in T2-11' });
      assert.equal(c.status, 'verified');
      assert.deepEqual([head.exists, head.size, head.contentType], [true, buf.length, mime]);
      assert.ok(docOk, JSON.stringify({ ...doc, createdAt: undefined }));
    });
  }

  test('T2-02 signed GET for the owner (twice, fresh link each time); non-owner, anonymous GET and anonymous listing refused; expired link refused', async (t) => {
    if (!uploaded.JPEG) return t.skip('no uploaded image');
    const { id, key, buf } = uploaded.JPEG;
    const first = await H.getMediaUrl(req('live-owner', { mediaId: id }));
    const r1 = await fetch(first.url);
    const b1 = Buffer.from(await r1.arrayBuffer());
    const second = await H.getMediaUrl(req('live-owner', { mediaId: id }));
    const r2 = await fetch(second.url);
    const b2 = Buffer.from(await r2.arrayBuffer());
    let otherDenied = false;
    await H.getMediaUrl(req('live-other', { mediaId: id })).catch((e) => { otherDenied = e.code === 'not-found'; });
    const anonGet = await fetch(objectUrl(key));
    const anonList = await fetch(`${cfg.endpoint}/${cfg.bucket}?list-type=2&prefix=${encodeURIComponent(PREFIX + '/')}`);
    const short = await store.presignGet({ key, expiresIn: 1 });
    await wait(2500);
    const expired = await fetch(short);
    record({ id: 'T2-02', objective: 'Private reads only through short-lived signed links', operation: 'owner signed GET ×2; non-owner getMediaUrl; unsigned GET; unsigned list; 1-second link after 2.5 s',
      expected: 'owner 200 + same SHA-256 (twice); others refused; anonymous 401/403; expired 401/403',
      actual: `owner ${r1.status}/${r2.status} sha-match=${sha(b1) === sha(buf)}/${sha(b2) === sha(buf)}; non-owner denied=${otherDenied}; anonymous GET ${anonGet.status}; anonymous list ${anonList.status}; expired ${expired.status}`,
      evidence: {}, cleanup: 'n/a' });
    assert.deepEqual([r1.status, r2.status], [200, 200]);
    assert.equal(sha(b1), sha(buf));
    assert.equal(sha(b2), sha(buf));
    assert.ok(otherDenied);
    assert.ok([401, 403].includes(anonGet.status), `anonymous GET returned ${anonGet.status}`);
    assert.ok([401, 403].includes(anonList.status), `anonymous list returned ${anonList.status}`);
    assert.ok([401, 403].includes(expired.status), `expired link returned ${expired.status}`);
  });

  test('T2-14 invalid uploads are rejected before anything is stored', async (t) => {
    if (!permissionsOk) return t.skip('permissions not verified');
    const png = fixture('synthetic_64x48.png');
    const cases = [['PNG declared as JPEG', png, 'image/jpeg', 'type_mismatch'], ['truncated PNG', png.subarray(0, png.length - 20), 'image/png', 'truncated_or_trailing_data'],
      ['random bytes', crypto.randomBytes(300), 'image/png', 'unrecognised_format']];
    const outcomes = {};
    for (const [label, buf, mime, why] of cases) {
      const r = await H.requestMediaUpload(req('live-owner', { kind: 'test-portfolio', mimeType: mime, sizeBytes: buf.length, sha256: sha(buf) }));
      const key = (await db.doc(`media/${r.mediaId}`).get()).data().objectKey;
      let reason = null;
      await H.uploadMediaContent(req('live-owner', { mediaId: r.mediaId, dataBase64: buf.toString('base64') })).catch((e) => { reason = e.details && e.details.reason; });
      outcomes[label] = { reason, object: await k1Head(key), status: (await db.doc(`media/${r.mediaId}`).get()).data().status };
      assert.deepEqual([reason, outcomes[label].object, outcomes[label].status], [why, 'absent', 'rejected'], label);
    }
    record({ id: 'T2-14', objective: 'Invalid files never reach the bucket', operation: 'proxy upload of a mismatched type, a truncated PNG and random bytes',
      expected: 'rejected with reason; no object; record rejected', actual: 'as expected', evidence: outcomes, cleanup: 'nothing stored' });
  });

  test('T2-03 presigned PUT: a body that differs from the signed Content-Length is refused BY THE STORE', async (t) => {
    if (!permissionsOk) return t.skip('permissions not verified');
    const png = fixture('synthetic_64x48.png');
    const outcomes = {};
    for (const [label, body] of [['larger', Buffer.concat([png, Buffer.from([0])])], ['smaller', png.subarray(0, png.length - 1)], ['chunked', null]]) {
      const key = keyFor(`t2-03-${label}.png`);
      const url = await store.presignPut({ key, contentType: 'image/png', contentLength: png.length, expiresIn: 60 });
      willCreate(key, body ? body.length : png.length, 'T2-03');
      const init = body
        ? { method: 'PUT', body, headers: { 'Content-Type': 'image/png' } }
        : { method: 'PUT', body: new ReadableStream({ start(c) { c.enqueue(png); c.close(); } }), duplex: 'half', headers: { 'Content-Type': 'image/png' } };
      const res = await fetch(url, init).catch((e) => ({ status: `client-error:${e.name}` }));
      const present = await k1Head(key);
      outcomes[label] = { status: res.status, objectAfter: present, cleanup: present === 'present' ? await removeOwn(key) : 'none needed' };
    }
    presignedSafe.length = Object.values(outcomes).every((o) => o.objectAfter === 'absent' && !(o.status >= 200 && o.status < 300));
    record({ id: 'T2-03', objective: 'Size enforced during upload by the store (Q2)', operation: 'PUT larger, smaller and chunked bodies to a link signed for the exact length',
      expected: 'every attempt refused, no object created', actual: presignedSafe.length ? 'enforced' : 'NOT ENFORCED — direct uploads stay disabled', evidence: outcomes, cleanup: 'see evidence' });
    assert.ok(presignedSafe.length, `size not enforced: ${JSON.stringify(outcomes)}`);
  });

  test('T2-08 ACL: unsigned x-amz-acl on a presigned PUT, and a public-read ACL set with K1, must not expose an object', async (t) => {
    if (!permissionsOk) return t.skip('permissions not verified');
    const png = fixture('synthetic_64x48.png');
    const ev = {};
    const k1 = keyFor('t2-08-header.png');
    const url = await store.presignPut({ key: k1, contentType: 'image/png', contentLength: png.length, expiresIn: 60 });
    willCreate(k1, png.length, 'T2-08');
    const put = await fetch(url, { method: 'PUT', body: png, headers: { 'Content-Type': 'image/png', 'x-amz-acl': 'public-read' } });
    ev.unsignedAclPut = put.status;
    ev.anonGetAfterHeader = (await k1Head(k1)) === 'present' ? (await fetch(objectUrl(k1))).status : 'no object';
    ev.cleanupHeader = await removeOwn(k1);
    const k2 = keyFor('t2-08-acl.png');
    willCreate(k2, png.length, 'T2-08');
    await s3k1.send(new sdk.PutObjectCommand({ Bucket: cfg.bucket, Key: k2, Body: png, ContentType: 'image/png' }));
    try {
      await s3k1.send(new sdk.PutObjectAclCommand({ Bucket: cfg.bucket, Key: k2, ACL: 'public-read' }));
      ev.putObjectAcl = 'accepted';
    } catch (e) {
      ev.putObjectAcl = `rejected ${errInfo(e)}`;
    }
    ev.anonGetAfterAcl = (await fetch(objectUrl(k2))).status;
    ev.cleanupAcl = await removeOwn(k2);
    const exposed = ev.anonGetAfterHeader === 200 || ev.anonGetAfterAcl === 200;
    presignedSafe.acl = !exposed && !(put.status >= 200 && put.status < 300 && ev.anonGetAfterHeader === 200);
    record({ id: 'T2-08', objective: 'Can K1 or a presigned PUT make an object public (Q7)?', operation: 'presigned PUT + unsigned x-amz-acl; PutObjectAcl public-read; anonymous GET after each',
      expected: 'anonymous GET 401/403 in both cases', actual: exposed ? 'EXPOSED — stop: K1 can publish objects' : 'not exposed', evidence: ev, cleanup: `${ev.cleanupHeader}/${ev.cleanupAcl}` });
    assert.ok(!exposed, `object exposed publicly: ${JSON.stringify(ev)}`);
  });

  test('T2-09 presigned PUT: wrong Content-Type and an expired link are refused', async (t) => {
    if (!permissionsOk) return t.skip('permissions not verified');
    const png = fixture('synthetic_64x48.png');
    const k1 = keyFor('t2-09-type.png');
    const u1 = await store.presignPut({ key: k1, contentType: 'image/png', contentLength: png.length, expiresIn: 60 });
    willCreate(k1, png.length, 'T2-09');
    const wrongType = await fetch(u1, { method: 'PUT', body: png, headers: { 'Content-Type': 'text/html' } });
    const typeObj = await k1Head(k1);
    const c1 = await removeOwn(k1);
    const k2 = keyFor('t2-09-expired.png');
    const u2 = await store.presignPut({ key: k2, contentType: 'image/png', contentLength: png.length, expiresIn: 1 });
    await wait(2500);
    willCreate(k2, png.length, 'T2-09');
    const expired = await fetch(u2, { method: 'PUT', body: png, headers: { 'Content-Type': 'image/png' } });
    const expObj = await k1Head(k2);
    const c2 = await removeOwn(k2);
    record({ id: 'T2-09', objective: 'Signed type and expiry are enforced', operation: 'PUT text/html to an image/png link; PUT after a 1-second link expired',
      expected: '4xx and no object, both', actual: `wrong type ${wrongType.status} (object ${typeObj}); expired ${expired.status} (object ${expObj})`, evidence: {}, cleanup: `${c1}/${c2}` });
    assert.ok(wrongType.status >= 400 && typeObj === 'absent');
    assert.ok(expired.status >= 400 && expObj === 'absent');
  });

  test('T2-13 direct (presigned) upload end to end — only if T2-03 and T2-08 passed in this run', async (t) => {
    if (!(presignedSafe.length && presignedSafe.acl)) return t.skip('presigned PUT not proven safe in this run');
    process.env.RUMPTY_UPLOAD_MODE = 'presigned';
    process.env.RUMPTY_PRESIGNED_PUT_VERIFIED = 'true';
    try {
      const buf = fixture('synthetic_64x48.png');
      const r = await H.requestMediaUpload(req('live-owner', { kind: 'test-portfolio', mimeType: 'image/png', sizeBytes: buf.length, sha256: sha(buf) }));
      const key = (await db.doc(`media/${r.mediaId}`).get()).data().objectKey;
      willCreate(key, buf.length, 'T2-13');
      const put = await fetch(r.upload.url, { method: 'PUT', body: buf, headers: r.upload.headers });
      const c = await H.confirmMediaUpload(req('live-owner', { mediaId: r.mediaId }));
      const d = await H.deleteMedia(req('live-owner', { mediaId: r.mediaId }));
      const gone = await k1Head(key);
      record({ id: 'T2-13', objective: 'The app\'s direct-upload path works against the real store', operation: 'requestMediaUpload (presigned) → PUT with the returned headers → confirm → delete',
        expected: 'PUT 200, verified, deleted, object absent', actual: `PUT ${put.status}, ${c.status}, ${d.status}, object ${gone}`, evidence: { mediaId: r.mediaId, mode: r.mode }, cleanup: gone });
      assert.deepEqual([r.mode, put.status, c.status, d.status, gone], ['presigned', 200, 'verified', 'deleted', 'absent']);
    } finally {
      delete process.env.RUMPTY_UPLOAD_MODE;
      delete process.env.RUMPTY_PRESIGNED_PUT_VERIFIED;
    }
  });

  test('T2-05 / T2-06 / T2-07 vendor behaviour (informational)', async (t) => {
    if (!uploaded.PNG) return t.skip('no uploaded image');
    const png = fixture('synthetic_64x48.png');
    const k5 = keyFor('t2-05.png');
    willCreate(k5, png.length, 'T2-05');
    let checksum;
    try {
      await s3k1.send(new sdk.PutObjectCommand({ Bucket: cfg.bucket, Key: k5, Body: png, ContentType: 'image/png', ChecksumSHA256: crypto.createHash('sha256').update('other').digest('base64') }));
      checksum = 'ACCEPTED (checksum header ignored)';
    } catch (e) { checksum = `rejected ${errInfo(e)}`; }
    const c5 = await removeOwn(k5);
    const { getSignedUrl } = require('@aws-sdk/s3-request-presigner');
    const overrideUrl = await getSignedUrl(s3k1, new sdk.GetObjectCommand({ Bucket: cfg.bucket, Key: uploaded.PNG.key, ResponseContentType: 'text/plain' }), { expiresIn: 60 });
    const o = await fetch(overrideUrl);
    let missingDelete;
    try {
      const r = await s3k2.send(new sdk.DeleteObjectCommand({ Bucket: cfg.bucket, Key: keyFor('t2-07-never-created.png') }));
      missingDelete = `success (HTTP ${r.$metadata.httpStatusCode})`;
    } catch (e) { missingDelete = `error ${errInfo(e)}`; }
    record({ id: 'T2-05/06/07', objective: 'Checksum header (Q4), response overrides (Q5), delete of a missing key (Q6)', operation: 'PUT with wrong checksum; GET with response-content-type; DELETE never-created key',
      expected: 'informational', actual: `checksum: ${checksum}; override: ${o.status} ${o.headers.get('content-type')}; missing delete: ${missingDelete}`, evidence: {}, cleanup: c5 });
    assert.equal(c5, 'absent');
  });

  test('T2-12 an object altered after upload is rejected at confirmation and removed', async (t) => {
    if (!permissionsOk) return t.skip('permissions not verified');
    const png = fixture('synthetic_64x48.png');
    const r = await H.requestMediaUpload(req('live-owner', { kind: 'test-portfolio', mimeType: 'image/png', sizeBytes: png.length, sha256: sha(png) }));
    const key = (await db.doc(`media/${r.mediaId}`).get()).data().objectKey;
    willCreate(key, png.length * 2, 'T2-12');
    await H.uploadMediaContent(req('live-owner', { mediaId: r.mediaId, dataBase64: png.toString('base64') }));
    const tampered = Buffer.from(png);
    tampered[40] ^= 0x01;
    await s3k1.send(new sdk.PutObjectCommand({ Bucket: cfg.bucket, Key: key, Body: tampered, ContentType: 'image/png' }));
    let reason = null;
    await H.confirmMediaUpload(req('live-owner', { mediaId: r.mediaId })).catch((e) => { reason = e.details && e.details.reason; });
    const after = await k1Head(key);
    const status = (await db.doc(`media/${r.mediaId}`).get()).data().status;
    record({ id: 'T2-12', objective: 'Server-side SHA-256 on the stored bytes; invalid object cleaned up', operation: 'proxy upload, overwrite with altered bytes, confirm',
      expected: 'checksum_mismatch, object removed, record rejected', actual: `${reason}, object ${after}, ${status}`, evidence: { mediaId: r.mediaId }, cleanup: after });
    assert.deepEqual([reason, after, status], ['checksum_mismatch', 'absent', 'rejected']);
  });

  test('T2-11 authorised deletion of each uploaded image; repeat deletion; object gone; record consistent; link refused afterwards', async (t) => {
    if (!Object.keys(uploaded).length) return t.skip('nothing uploaded');
    const out = {};
    let otherDenied = false;
    await H.deleteMedia(req('live-other', { mediaId: uploaded.JPEG.id })).catch((e) => { otherDenied = e.code === 'not-found'; });
    for (const [label, { id, key }] of Object.entries(uploaded)) {
      const d1 = await H.deleteMedia(req('live-owner', { mediaId: id }));
      const d2 = await H.deleteMedia(req('live-owner', { mediaId: id }));
      const gone = await k1Head(key);
      const doc = (await db.doc(`media/${id}`).get()).data();
      let urlRefused = false;
      await H.getMediaUrl(req('live-owner', { mediaId: id })).catch((e) => { urlRefused = e.code === 'failed-precondition'; });
      out[label] = { first: d1.status, repeat: d2.status, object: gone, record: doc.status, quota: doc.quota, urlRefused };
      assert.deepEqual([d1.status, d2.status, gone, doc.status, doc.quota, urlRefused], ['deleted', 'deleted', 'absent', 'deleted', 'released', true], label);
    }
    const q = (await db.doc('media_quotas/live-owner').get()).data();
    record({ id: 'T2-11', objective: 'Delete through the backend; idempotent; nothing left; no further access', operation: 'non-owner delete; owner delete ×2 per image; HEAD; record; getMediaUrl',
      expected: 'non-owner refused; deleted twice; absent; record deleted/released; link refused', actual: `non-owner refused=${otherDenied}; ${JSON.stringify(out)}`,
      evidence: { quotaAfter: { usedBytes: q.usedBytes, reservedBytes: q.reservedBytes, pendingCount: q.pendingCount } }, cleanup: 'all absent' });
    assert.ok(otherDenied);
    assert.deepEqual([q.usedBytes, q.reservedBytes, q.pendingCount], [0, 0, 0]);
  });
});
