// HandyTrust — RumptyCloud staging media (synthetic test media only).
//
// Design: design/RUMPTYCLOUD_STAGING_INTEGRATION_PHASE2_PLAN.md (and the
// implementation report RUMPTYCLOUD_STAGING_INTEGRATION_IMPLEMENTATION_REPORT.md).
//
// Firebase decides, RumptyCloud stores:
//   - every operation is a callable that checks Firebase Auth + Firestore;
//   - `media/{id}` is the record of truth (written only here);
//   - RumptyCloud keys exist only in this process (Functions secrets / the
//     emulator's functions/.secret.local) and never reach the client;
//   - the client never supplies a bucket, object key, owner or URL.
//
// Upload modes:
//   - 'proxy' (default): the file comes through `uploadMediaContent`; its size,
//     signature, dimensions and SHA-256 are checked BEFORE anything is written
//     to the bucket. Independent of any vendor behaviour.
//   - 'presigned': a 300 s PUT URL with Content-Type and Content-Length
//     signed. Only enabled when RUMPTY_PRESIGNED_PUT_VERIFIED=true, i.e. after
//     the live tests prove RumptyCloud rejects a wrong length (T2-03) and
//     unsigned ACL headers (T2-08). Until then it is never used.
//
// Staging scope: only the synthetic kinds below. No real media category, no
// video, no documents, no identity documents.
'use strict';

const crypto = require('crypto');
const admin = require('firebase-admin');
const { onCall, HttpsError } = require('firebase-functions/v2/https');

if (!admin.apps.length) admin.initializeApp();
const db = () => admin.firestore();
const Timestamp = admin.firestore.Timestamp;

// ─── Limits (Phase 2 plan §3–§5, §9) ────────────────────────────────────────
const MB = 1024 * 1024;
const IMAGE_TYPES = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp' };
const EXTENSIONS = { jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png', webp: 'image/webp' };
// Synthetic staging kinds only. `test-video` is deliberately absent: video
// stays disabled until size enforcement is proven (plan §3, roadmap M5).
const KINDS = {
  'test-avatar': { maxBytes: 5 * MB },
  'test-portfolio': { maxBytes: 5 * MB },
  'test-thumb': { maxBytes: 1 * MB, maxSide: 512 },
};
const LIMITS = {
  urlTtlSeconds: 300,
  pendingTtlMs: 15 * 60 * 1000,
  verifyingStuckMs: 10 * 60 * 1000,
  userWindowMs: 10 * 60 * 1000,
  userWindowMax: 10,
  userDayMax: 50,
  userStorageBytes: 100 * MB,
  globalStorageBytes: 1024 * MB,
  userPendingMax: 3,
  globalPendingMax: 30,
  // Upload operations (signed PUT URLs or proxied PUTs) for ALL users per
  // minute: 20% of RumptyCloud's 600 writes/min per key, leaving room for
  // deletes and sweeps.
  globalWritesPerMinute: 120,
  maxImageSide: 8000,
  maxImagePixels: 40e6,
  verifyTimeoutMs: 60 * 1000,
  deleteBackoffMs: [60e3, 5 * 60e3, 30 * 60e3, 2 * 3600e3, 12 * 3600e3, 24 * 3600e3, 24 * 3600e3],
  maxDeleteAttempts: 8,
  ownSweepBatch: 5,
  sweepBatch: 50,
  reconcileMaxKeys: 200,
};

// Allow-list: this code can only ever talk to the staging bucket.
const ALLOWED_ENDPOINT = 'https://s3.rumptycloud.com';
const ALLOWED_REGION = 'olas-closet';
const ALLOWED_BUCKETS = new Set(['assets-handytrust-01a0f99e-5d6ffa']);
const PREFIX_RE = /^staging(\/[a-z0-9][a-z0-9-]{0,62})+$/;

const SIGNER_SECRETS = ['RUMPTY_ACCESS_KEY_ID', 'RUMPTY_SECRET_ACCESS_KEY'];
const CLEANUP_SECRETS = ['RUMPTY_CLEANUP_ACCESS_KEY_ID', 'RUMPTY_CLEANUP_SECRET_ACCESS_KEY'];

// ─── Test seams ─────────────────────────────────────────────────────────────
let _nowMs = () => Date.now();
let _storeOverride = null;
function _setMediaClock(fn) { _nowMs = fn || (() => Date.now()); }
function _setMediaStore(store) { _storeOverride = store || null; }
const _nowTs = () => Timestamp.fromMillis(_nowMs());

// ─── Configuration (names only are ever reported, never values) ─────────────
function _config(env = process.env) {
  const c = {
    bucket: env.RUMPTY_BUCKET || '',
    endpoint: env.RUMPTY_ENDPOINT || '',
    region: env.RUMPTY_REGION || '',
    keyPrefix: (env.RUMPTY_KEY_PREFIX || 'staging/media').replace(/\/+$/, ''),
    uploadMode: env.RUMPTY_UPLOAD_MODE === 'presigned' && env.RUMPTY_PRESIGNED_PUT_VERIFIED === 'true' ? 'presigned' : 'proxy',
    signer: { accessKeyId: env.RUMPTY_ACCESS_KEY_ID || '', secretAccessKey: env.RUMPTY_SECRET_ACCESS_KEY || '' },
    janitor: { accessKeyId: env.RUMPTY_CLEANUP_ACCESS_KEY_ID || '', secretAccessKey: env.RUMPTY_CLEANUP_SECRET_ACCESS_KEY || '' },
  };
  const problems = [];
  if (c.endpoint !== ALLOWED_ENDPOINT) problems.push('endpoint');
  if (c.region !== ALLOWED_REGION) problems.push('region');
  if (!ALLOWED_BUCKETS.has(c.bucket)) problems.push('bucket');
  if (!PREFIX_RE.test(c.keyPrefix)) problems.push('key_prefix');
  if (!c.signer.accessKeyId || !c.signer.secretAccessKey) problems.push('signer_key');
  if (!c.janitor.accessKeyId || !c.janitor.secretAccessKey) problems.push('cleanup_key');
  return { ...c, problems };
}

function _requireConfig() {
  const cfg = _config();
  if (cfg.problems.length) {
    _log('media_config_missing', { problems: cfg.problems }); // names only
    throw new HttpsError('failed-precondition', 'Media storage is not configured.');
  }
  return cfg;
}

// ─── Logging: event, ids, status and error class only ──────────────────────
function _log(event, fields = {}) {
  console.log(JSON.stringify({ event, ...fields }));
}
function _errFields(err) {
  return {
    errorName: (err && typeof err.name === 'string' && err.name.slice(0, 80)) || 'Error',
    httpStatus: (err && err.$metadata && err.$metadata.httpStatusCode) || null,
  };
}
function _isNotFound(err) {
  return !!err && (err.name === 'NotFound' || err.name === 'NoSuchKey' || (err.$metadata && err.$metadata.httpStatusCode === 404));
}

// ─── Object store (RumptyCloud via the AWS SDK; fakes in tests) ─────────────
const _clients = new Map();
function _s3(cfg, role) {
  const creds = role === 'janitor' ? cfg.janitor : cfg.signer;
  const id = `${role}:${creds.accessKeyId}`;
  if (!_clients.has(id)) {
    const { S3Client } = require('@aws-sdk/client-s3');
    _clients.set(id, new S3Client({
      endpoint: cfg.endpoint,
      region: cfg.region,
      forcePathStyle: true,
      credentials: { accessKeyId: creds.accessKeyId, secretAccessKey: creds.secretAccessKey },
      // The SDK's default "flexible checksums" put a CRC32 of an EMPTY body
      // into presigned PUT URLs and add headers many S3-compatible stores do
      // not support (verified offline). Only send checksums when required.
      requestChecksumCalculation: 'WHEN_REQUIRED',
      responseChecksumValidation: 'WHEN_REQUIRED',
      maxAttempts: 2,
    }));
  }
  return _clients.get(id);
}

function _rumptyStore(cfg) {
  const s3 = require('@aws-sdk/client-s3');
  const { getSignedUrl } = require('@aws-sdk/s3-request-presigner');
  const Bucket = cfg.bucket;
  const signer = _s3(cfg, 'signer');
  const janitor = _s3(cfg, 'janitor');
  return {
    // K1 (read + write): proxied uploads, verification reads, URL signing.
    async put({ key, body, contentType }) {
      await signer.send(new s3.PutObjectCommand({ Bucket, Key: key, Body: body, ContentType: contentType, ContentLength: body.length }));
    },
    async head(key, { role = 'signer' } = {}) {
      try {
        const r = await (role === 'janitor' ? janitor : signer).send(new s3.HeadObjectCommand({ Bucket, Key: key }));
        return { exists: true, size: Number(r.ContentLength), contentType: r.ContentType || '' };
      } catch (err) {
        if (_isNotFound(err)) return { exists: false };
        throw err;
      }
    },
    async openRead(key, { signal } = {}) {
      const r = await signer.send(new s3.GetObjectCommand({ Bucket, Key: key }), { abortSignal: signal });
      return r.Body; // Node readable stream
    },
    async presignPut({ key, contentType, contentLength, expiresIn }) {
      return getSignedUrl(signer, new s3.PutObjectCommand({ Bucket, Key: key, ContentType: contentType, ContentLength: contentLength }),
        { expiresIn, signableHeaders: new Set(['content-type', 'content-length']) });
    },
    async presignGet({ key, expiresIn }) {
      return getSignedUrl(signer, new s3.GetObjectCommand({ Bucket, Key: key }), { expiresIn });
    },
    // K2 (list + read + delete): deletion and reconciliation only.
    async remove(key) {
      try {
        await janitor.send(new s3.DeleteObjectCommand({ Bucket, Key: key }));
      } catch (err) {
        if (!_isNotFound(err)) throw err; // an already-missing object counts as deleted
      }
    },
    async list({ prefix, maxKeys }) {
      const r = await janitor.send(new s3.ListObjectsV2Command({ Bucket, Prefix: prefix, MaxKeys: maxKeys }));
      return (r.Contents || []).map((o) => ({ key: o.Key, size: Number(o.Size), lastModified: o.LastModified }));
    },
  };
}

const _store = (cfg) => _storeOverride || _rumptyStore(cfg);

// ─── Content validation (no dependency; never trusts Content-Type) ──────────
const PNG_SIG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

function _jpegInfo(buf) {
  let i = 2;
  while (i + 9 < buf.length) {
    if (buf[i] !== 0xff) return null;
    const marker = buf[i + 1];
    if (marker === 0xff) { i += 1; continue; }
    if (marker === 0xd8 || marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) { i += 2; continue; }
    if (marker === 0xd9 || marker === 0xda) return null; // end/scan before any frame header
    const len = buf.readUInt16BE(i + 2);
    if (len < 2) return null;
    if (marker >= 0xc0 && marker <= 0xcf && marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc) {
      return { height: buf.readUInt16BE(i + 5), width: buf.readUInt16BE(i + 7) };
    }
    i += 2 + len;
  }
  return null;
}

function _webpInfo(buf) {
  const chunk = buf.toString('ascii', 12, 16);
  if (chunk === 'VP8 ' && buf.length >= 30) {
    if (buf[23] !== 0x9d || buf[24] !== 0x01 || buf[25] !== 0x2a) return null;
    return { width: buf.readUInt16LE(26) & 0x3fff, height: buf.readUInt16LE(28) & 0x3fff };
  }
  if (chunk === 'VP8L' && buf.length >= 25) {
    if (buf[20] !== 0x2f) return null;
    const b = buf.readUInt32LE(21);
    return { width: (b & 0x3fff) + 1, height: ((b >>> 14) & 0x3fff) + 1 };
  }
  if (chunk === 'VP8X' && buf.length >= 30) {
    return { width: 1 + buf.readUIntLE(24, 3), height: 1 + buf.readUIntLE(27, 3) };
  }
  return null;
}

// Recognises the file from its bytes: { mime, width, height, complete } or null.
function _sniff(buf) {
  if (!Buffer.isBuffer(buf) || buf.length < 12) return null;
  if (buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) {
    const info = _jpegInfo(buf);
    // A complete JPEG ends with EOI (FF D9); allow a few padding bytes only.
    const tail = buf.subarray(Math.max(0, buf.length - 16));
    const complete = tail.includes(Buffer.from([0xff, 0xd9]));
    return info ? { mime: 'image/jpeg', ...info, complete } : { mime: 'image/jpeg', complete };
  }
  if (buf.length >= 24 && buf.subarray(0, 8).equals(PNG_SIG)) {
    if (buf.toString('ascii', 12, 16) !== 'IHDR') return { mime: 'image/png', complete: false };
    const complete = buf.length >= 12 && buf.toString('ascii', buf.length - 8, buf.length - 4) === 'IEND';
    return { mime: 'image/png', width: buf.readUInt32BE(16), height: buf.readUInt32BE(20), complete };
  }
  if (buf.length >= 16 && buf.toString('ascii', 0, 4) === 'RIFF' && buf.toString('ascii', 8, 12) === 'WEBP') {
    const riffSize = buf.readUInt32LE(4);
    const complete = riffSize + 8 === buf.length || riffSize + 9 === buf.length; // odd-size padding
    const info = _webpInfo(buf);
    return info ? { mime: 'image/webp', ...info, complete } : { mime: 'image/webp', complete };
  }
  return null;
}

// Full content check against the declared type and the kind's limits.
function _validateContent(buf, { mimeType, kind }) {
  const s = _sniff(buf);
  if (!s) return { ok: false, reason: 'unrecognised_format' };
  if (s.mime !== mimeType) return { ok: false, reason: 'type_mismatch' };
  if (!s.complete) return { ok: false, reason: 'truncated_or_trailing_data' };
  if (!s.width || !s.height) return { ok: false, reason: 'unreadable_dimensions' };
  if (s.width > LIMITS.maxImageSide || s.height > LIMITS.maxImageSide || s.width * s.height > LIMITS.maxImagePixels) {
    return { ok: false, reason: 'dimensions_too_large' };
  }
  const spec = KINDS[kind];
  if (spec && spec.maxSide && (s.width > spec.maxSide || s.height > spec.maxSide)) return { ok: false, reason: 'thumbnail_too_large' };
  return { ok: true, width: s.width, height: s.height };
}

const _sha256 = (buf) => crypto.createHash('sha256').update(buf).digest('hex');

// ─── Auth ───────────────────────────────────────────────────────────────────
async function _requireMediaUser(request) {
  const auth = request && request.auth;
  if (!auth || !auth.uid) throw new HttpsError('unauthenticated', 'Sign in required.');
  const token = auth.token || {};
  if (token.firebase && token.firebase.sign_in_provider === 'anonymous') throw new HttpsError('permission-denied', 'Sign in with an account to upload media.');
  if (token.email_verified !== true) throw new HttpsError('permission-denied', 'Verify your email address to upload media.');
  const user = await db().collection('users').doc(auth.uid).get();
  if (user.exists && user.data().accountStatus === 'suspended') throw new HttpsError('permission-denied', 'This account cannot upload media.');
  return auth.uid;
}

async function _isAdmin(uid) {
  return (await db().collection('admins').doc(uid).get()).exists;
}

// Owner (or admin, where `allowAdmin`) of an existing media record. A record
// that does not exist and one the caller may not see give the same error,
// so ids cannot be probed.
async function _loadAccessible(mediaId, uid, { allowAdmin }) {
  if (typeof mediaId !== 'string' || !/^[A-Za-z0-9]{20}$/.test(mediaId)) throw new HttpsError('invalid-argument', 'Invalid media id.');
  const snap = await db().collection('media').doc(mediaId).get();
  if (!snap.exists) throw new HttpsError('not-found', 'Media not found.');
  const m = snap.data();
  if (m.ownerUid !== uid && !(allowAdmin && (await _isAdmin(uid)))) throw new HttpsError('not-found', 'Media not found.');
  return m;
}

// ─── Quotas and state transitions ───────────────────────────────────────────
// Each record holds its quota state: 'reserved' (pending: bytes reserved and
// one pending slot), 'used' (verified: bytes in use) or 'released'.
function _clampCounters(o) {
  for (const k of Object.keys(o)) if (typeof o[k] === 'number' && o[k] < 0) o[k] = 0;
  return o;
}
function _moveQuota(counters, from, to, size) {
  const c = { reservedBytes: 0, usedBytes: 0, pendingCount: 0, ...counters };
  if (from === to) return c;
  if (from === 'reserved') { c.reservedBytes -= size; c.pendingCount -= 1; }
  if (from === 'used') c.usedBytes -= size;
  if (to === 'reserved') { c.reservedBytes += size; c.pendingCount += 1; }
  if (to === 'used') c.usedBytes += size;
  return _clampCounters(c);
}

const _mediaRef = (id) => db().collection('media').doc(id);
const _quotaRef = (uid) => db().collection('media_quotas').doc(uid);
const _globalRef = () => db().collection('media_system').doc('limits');

// Atomically applies `decide(media)` → { update, quota?, result? } | null.
async function _transition(mediaId, decide) {
  return db().runTransaction(async (tx) => {
    const mRef = _mediaRef(mediaId);
    const mSnap = await tx.get(mRef);
    if (!mSnap.exists) return { ok: false, reason: 'not_found' };
    const media = mSnap.data();
    const qRef = _quotaRef(media.ownerUid);
    const gRef = _globalRef();
    const [qSnap, gSnap] = await Promise.all([tx.get(qRef), tx.get(gRef)]);
    const out = decide(media);
    if (!out || !out.update) return { ok: false, reason: (out && out.reason) || 'skipped', media };
    const nextQuota = out.quota || media.quota;
    if (nextQuota !== media.quota) {
      tx.set(qRef, { ..._moveQuota(qSnap.data() || {}, media.quota, nextQuota, media.sizeBytes), updatedAt: _nowTs() }, { merge: true });
      tx.set(gRef, { ..._moveQuota(gSnap.data() || {}, media.quota, nextQuota, media.sizeBytes), updatedAt: _nowTs() }, { merge: true });
    }
    const update = { ...out.update, quota: nextQuota, updatedAt: _nowTs() };
    tx.update(mRef, update);
    return { ok: true, media: { ...media, ...update }, result: out.result };
  });
}

// ─── Deletion (revoke first; verify gone; retry with back-off) ──────────────
async function _attemptDelete(cfg, mediaId) {
  const snap = await _mediaRef(mediaId).get();
  if (!snap.exists) return { status: 'not_found' };
  const m = snap.data();
  if (m.status !== 'deleting') return { status: m.status };
  const store = _store(cfg);
  try {
    await store.remove(m.objectKey);
    const h = await store.head(m.objectKey, { role: 'janitor' });
    if (h.exists) throw Object.assign(new Error('object still present'), { name: 'StillPresent' });
    const done = await _transition(mediaId, (cur) => (cur.status === 'deleting'
      ? { update: { status: cur.deleteFinalStatus || 'deleted', deletedAt: _nowTs(), nextDeleteAt: admin.firestore.FieldValue.delete() }, quota: 'released' }
      : null));
    const status = done.ok ? done.media.status : m.status;
    _log('media_deleted', { mediaId, status });
    return { status };
  } catch (err) {
    const attempts = (m.deleteAttempts || 0) + 1;
    const failed = attempts >= LIMITS.maxDeleteAttempts;
    const backoff = LIMITS.deleteBackoffMs[Math.min(attempts - 1, LIMITS.deleteBackoffMs.length - 1)];
    await _transition(mediaId, (cur) => (cur.status === 'deleting'
      ? {
          update: {
            status: failed ? 'delete_failed' : 'deleting',
            deleteAttempts: attempts,
            lastDeleteError: _errFields(err),
            nextDeleteAt: failed ? admin.firestore.FieldValue.delete() : Timestamp.fromMillis(_nowMs() + backoff),
          },
        }
      : null));
    if (failed) {
      await db().collection('admin_alerts').doc(`media_delete_failed_${mediaId}`).set({
        type: 'media_delete_failed', mediaId, createdAt: _nowTs(), resolved: false,
      });
    }
    _log(failed ? 'media_delete_failed' : 'media_delete_retry', { mediaId, attempts, ..._errFields(err) });
    return { status: failed ? 'delete_failed' : 'deleting' };
  }
}

// Moves a record into 'deleting' (access revoked at once) with the status it
// should end in once the object is gone.
async function _beginDelete(mediaId, { finalStatus, by, extra = {} }) {
  return _transition(mediaId, (cur) => {
    if (['deleted', 'expired', 'rejected', 'delete_failed'].includes(cur.status)) return { reason: 'terminal' };
    if (cur.status === 'deleting') return { update: { ...extra } }; // idempotent re-request
    return {
      update: {
        status: 'deleting', deleteFinalStatus: finalStatus, deleteRequestedAt: _nowTs(),
        deleteRequestedBy: by || 'system', deleteAttempts: cur.deleteAttempts || 0, ...extra,
      },
    };
  });
}

// ─── Verification of the stored object ──────────────────────────────────────
async function _readBounded(stream, maxBytes) {
  const parts = [];
  let total = 0;
  for await (const chunk of stream) {
    const b = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    total += b.length;
    if (total > maxBytes) {
      if (typeof stream.destroy === 'function') stream.destroy();
      return { tooLarge: true };
    }
    parts.push(b);
  }
  return { buf: Buffer.concat(parts, total) };
}

async function _verifyStoredObject(store, m) {
  const head = await store.head(m.objectKey);
  if (!head.exists) return { ok: false, reason: 'missing' };
  if (head.size !== m.sizeBytes) return { ok: false, reason: 'size_mismatch' };
  if ((head.contentType || '').toLowerCase().split(';')[0].trim() !== m.mimeType) return { ok: false, reason: 'type_mismatch' };
  const ac = new AbortController();
  const timer = setTimeout(() => ac.abort(), LIMITS.verifyTimeoutMs);
  try {
    const stream = await store.openRead(m.objectKey, { signal: ac.signal });
    const read = await _readBounded(stream, m.sizeBytes);
    if (read.tooLarge || read.buf.length !== m.sizeBytes) return { ok: false, reason: 'size_mismatch' };
    const sha = _sha256(read.buf);
    if (sha !== m.sha256) return { ok: false, reason: 'checksum_mismatch' };
    const v = _validateContent(read.buf, m);
    if (!v.ok) return v;
    return { ok: true, sha256: sha, width: v.width, height: v.height };
  } finally {
    clearTimeout(timer);
  }
}

// ─── Callable handlers ──────────────────────────────────────────────────────
const _str = (v) => (typeof v === 'string' ? v : '');
const _ms = (ts) => (ts && typeof ts.toMillis === 'function' ? ts.toMillis() : 0);

function _counters(data, nowMs) {
  const d = data || {};
  const windowStart = _ms(d.windowStart);
  const dayStart = _ms(d.dayStart);
  return {
    reservedBytes: d.reservedBytes || 0,
    usedBytes: d.usedBytes || 0,
    pendingCount: d.pendingCount || 0,
    windowCount: nowMs - windowStart < LIMITS.userWindowMs ? d.windowCount || 0 : 0,
    windowStart: nowMs - windowStart < LIMITS.userWindowMs ? windowStart : nowMs,
    dayCount: nowMs - dayStart < 24 * 3600e3 ? d.dayCount || 0 : 0,
    dayStart: nowMs - dayStart < 24 * 3600e3 ? dayStart : nowMs,
  };
}

function _limitError(reason, retryAfterSeconds) {
  _log('media_limit', { reason });
  return new HttpsError('resource-exhausted', 'Upload limit reached. Please try again later.', { reason, retryAfterSeconds });
}

async function requestMediaUpload(request) {
  const uid = await _requireMediaUser(request);
  const d = (request && request.data) || {};
  const kind = _str(d.kind);
  const spec = KINDS[kind];
  if (!spec) throw new HttpsError('invalid-argument', 'This media type is not available.');
  const mimeType = _str(d.mimeType).toLowerCase();
  const ext = IMAGE_TYPES[mimeType];
  if (!ext) throw new HttpsError('invalid-argument', 'Only JPEG, PNG and WebP images are accepted.');
  if (d.fileExtension !== undefined) {
    const e = _str(d.fileExtension).toLowerCase().replace(/^\./, '');
    if (EXTENSIONS[e] !== mimeType) throw new HttpsError('invalid-argument', 'The file extension does not match the file type.');
  }
  const sizeBytes = d.sizeBytes;
  if (!Number.isInteger(sizeBytes) || sizeBytes < 1 || sizeBytes > spec.maxBytes) {
    throw new HttpsError('invalid-argument', 'The file is empty or larger than allowed.', { maxBytes: spec.maxBytes });
  }
  const sha256 = _str(d.sha256).toLowerCase();
  if (!/^[0-9a-f]{64}$/.test(sha256)) throw new HttpsError('invalid-argument', 'A SHA-256 checksum of the file is required.');
  const cfg = _requireConfig();

  await _sweepOwnExpired(cfg, uid);

  const nowMs = _nowMs();
  const now = Timestamp.fromMillis(nowMs);
  const mediaId = db().collection('media').doc().id; // random 20-character id
  const day = new Date(nowMs);
  const objectKey = `${cfg.keyPrefix}/${kind}/${day.getUTCFullYear()}/${String(day.getUTCMonth() + 1).padStart(2, '0')}/${crypto.randomUUID()}.${ext}`;
  const expiresAt = Timestamp.fromMillis(nowMs + LIMITS.pendingTtlMs);

  await db().runTransaction(async (tx) => {
    const qRef = _quotaRef(uid);
    const gRef = _globalRef();
    const [qSnap, gSnap] = await Promise.all([tx.get(qRef), tx.get(gRef)]);
    const q = _counters(qSnap.data(), nowMs);
    const g = gSnap.data() || {};
    const minute = Math.floor(nowMs / 60000);
    const minuteCount = g.minute === minute ? g.minuteCount || 0 : 0;
    if (q.windowCount >= LIMITS.userWindowMax) throw _limitError('user_rate', Math.ceil((q.windowStart + LIMITS.userWindowMs - nowMs) / 1000));
    if (q.dayCount >= LIMITS.userDayMax) throw _limitError('user_daily', Math.ceil((q.dayStart + 24 * 3600e3 - nowMs) / 1000));
    if (q.pendingCount >= LIMITS.userPendingMax) throw _limitError('user_pending', 60);
    if (q.usedBytes + q.reservedBytes + sizeBytes > LIMITS.userStorageBytes) throw _limitError('user_storage', null);
    if ((g.pendingCount || 0) >= LIMITS.globalPendingMax) throw _limitError('global_pending', 60);
    if ((g.usedBytes || 0) + (g.reservedBytes || 0) + sizeBytes > LIMITS.globalStorageBytes) throw _limitError('global_storage', null);
    if (minuteCount >= LIMITS.globalWritesPerMinute) throw _limitError('global_rate', 60 - Math.floor((nowMs % 60000) / 1000));

    tx.set(_mediaRef(mediaId), {
      provider: 'rumpty', env: 'staging', bucket: cfg.bucket, objectKey, kind, mimeType, sizeBytes, sha256,
      ownerUid: uid, visibility: 'private', status: 'pending', uploadMode: cfg.uploadMode, quota: 'reserved',
      createdAt: now, updatedAt: now, expiresAt, deleteAttempts: 0,
    });
    tx.set(qRef, {
      reservedBytes: q.reservedBytes + sizeBytes, usedBytes: q.usedBytes, pendingCount: q.pendingCount + 1,
      windowStart: Timestamp.fromMillis(q.windowStart), windowCount: q.windowCount + 1,
      dayStart: Timestamp.fromMillis(q.dayStart), dayCount: q.dayCount + 1, updatedAt: now,
    }, { merge: true });
    tx.set(gRef, {
      reservedBytes: (g.reservedBytes || 0) + sizeBytes, usedBytes: g.usedBytes || 0, pendingCount: (g.pendingCount || 0) + 1,
      minute, minuteCount: minuteCount + 1, updatedAt: now,
    }, { merge: true });
  });
  _log('media_requested', { mediaId, kind, mode: cfg.uploadMode });

  if (cfg.uploadMode !== 'presigned') {
    return { mediaId, mode: 'proxy', expiresAt: expiresAt.toMillis(), maxBytes: spec.maxBytes };
  }
  try {
    const url = await _store(cfg).presignPut({ key: objectKey, contentType: mimeType, contentLength: sizeBytes, expiresIn: LIMITS.urlTtlSeconds });
    return {
      mediaId, mode: 'presigned', expiresAt: Math.min(expiresAt.toMillis(), nowMs + LIMITS.urlTtlSeconds * 1000),
      upload: { method: 'PUT', url, headers: { 'Content-Type': mimeType, 'Content-Length': String(sizeBytes) } },
    };
  } catch (err) {
    _log('media_presign_failed', { mediaId, ..._errFields(err) });
    await _transition(mediaId, (cur) => (cur.status === 'pending' ? { update: { status: 'rejected', rejectedReason: 'signing_failed' }, quota: 'released' } : null));
    throw new HttpsError('unavailable', 'Media storage is unavailable. Please try again.');
  }
}

// Proxy mode: the file is checked completely before it is written.
async function uploadMediaContent(request) {
  const uid = await _requireMediaUser(request);
  const d = (request && request.data) || {};
  const data = _str(d.dataBase64);
  // Cheap bound before decoding: nothing larger than the biggest kind.
  const maxKind = Math.max(...Object.values(KINDS).map((k) => k.maxBytes));
  if (!data || data.length > Math.ceil(maxKind / 3) * 4 + 4) throw new HttpsError('invalid-argument', 'The file is empty or larger than allowed.');
  const cfg = _requireConfig();
  const mediaId = _str(d.mediaId);
  const m = await _loadAccessible(mediaId, uid, { allowAdmin: false });
  if (m.uploadMode !== 'proxy') throw new HttpsError('failed-precondition', 'Upload this file with its upload link.');
  if (m.status !== 'pending') throw new HttpsError('failed-precondition', 'This upload is no longer open.');
  if (_ms(m.expiresAt) <= _nowMs()) {
    await _beginDelete(mediaId, { finalStatus: 'expired', by: 'system' });
    await _attemptDelete(cfg, mediaId);
    throw new HttpsError('failed-precondition', 'This upload has expired. Please start again.');
  }
  const buf = Buffer.from(data, 'base64');
  let reason = null;
  if (buf.length !== m.sizeBytes) reason = 'size_mismatch';
  else if (_sha256(buf) !== m.sha256) reason = 'checksum_mismatch';
  else {
    const v = _validateContent(buf, m);
    if (!v.ok) reason = v.reason;
  }
  if (reason) {
    // Nothing was stored: reject and release the reservation.
    await _transition(mediaId, (cur) => (cur.status === 'pending' ? { update: { status: 'rejected', rejectedReason: reason }, quota: 'released' } : null));
    _log('media_rejected', { mediaId, reason });
    throw new HttpsError('invalid-argument', 'The file was rejected.', { reason });
  }
  const claim = await _transition(mediaId, (cur) => (cur.status === 'pending' ? { update: { status: 'uploading' } } : null));
  if (!claim.ok) throw new HttpsError('failed-precondition', 'This upload is no longer open.');
  try {
    await _store(cfg).put({ key: m.objectKey, body: buf, contentType: m.mimeType });
  } catch (err) {
    _log('media_store_failed', { mediaId, ..._errFields(err) });
    // Safe to retry: the same server-chosen key is written again.
    await _transition(mediaId, (cur) => (cur.status === 'uploading' ? { update: { status: 'pending' } } : null));
    throw new HttpsError('unavailable', 'Media storage is unavailable. Please try again.');
  }
  await _transition(mediaId, (cur) => (cur.status === 'uploading' ? { update: { status: 'uploaded', uploadedAt: _nowTs() } } : null));
  _log('media_uploaded', { mediaId });
  return { mediaId, status: 'uploaded' };
}

async function confirmMediaUpload(request) {
  const uid = await _requireMediaUser(request);
  const cfg = _requireConfig();
  const mediaId = _str(((request && request.data) || {}).mediaId);
  const m = await _loadAccessible(mediaId, uid, { allowAdmin: false });
  if (m.status === 'verified') return { mediaId, status: 'verified' }; // idempotent
  const expectedFrom = m.uploadMode === 'proxy' ? 'uploaded' : 'pending';
  if (m.uploadMode === 'proxy' && m.status === 'pending') throw new HttpsError('failed-precondition', 'Upload the file first.');
  if (m.status !== expectedFrom) throw new HttpsError('failed-precondition', 'This upload cannot be confirmed.');
  if (m.uploadMode === 'presigned' && _ms(m.expiresAt) <= _nowMs()) {
    await _beginDelete(mediaId, { finalStatus: 'expired', by: 'system' });
    await _attemptDelete(cfg, mediaId);
    throw new HttpsError('failed-precondition', 'This upload has expired. Please start again.');
  }
  const claim = await _transition(mediaId, (cur) => (cur.status === expectedFrom ? { update: { status: 'verifying', verifyingSince: _nowTs() } } : null));
  if (!claim.ok) throw new HttpsError('failed-precondition', 'This upload cannot be confirmed.');

  let v;
  try {
    v = await _verifyStoredObject(_store(cfg), m);
  } catch (err) {
    _log('media_verify_error', { mediaId, ..._errFields(err) });
    await _transition(mediaId, (cur) => (cur.status === 'verifying' ? { update: { status: expectedFrom } } : null));
    throw new HttpsError('unavailable', 'Could not check the upload. Please try again.');
  }
  if (v.ok) {
    await _transition(mediaId, (cur) => (cur.status === 'verifying'
      ? { update: { status: 'verified', verifiedAt: _nowTs(), verifiedSha256: v.sha256, width: v.width, height: v.height }, quota: 'used' }
      : null));
    _log('media_verified', { mediaId });
    return { mediaId, status: 'verified' };
  }
  if (v.reason === 'missing' && m.uploadMode === 'presigned') {
    await _transition(mediaId, (cur) => (cur.status === 'verifying' ? { update: { status: 'pending' } } : null));
    throw new HttpsError('failed-precondition', 'The upload has not arrived yet.');
  }
  // Invalid object: revoke, remove it through the cleanup key, then reject.
  _log('media_rejected', { mediaId, reason: v.reason });
  await _beginDelete(mediaId, { finalStatus: 'rejected', by: 'system', extra: { rejectedReason: v.reason } });
  await _attemptDelete(cfg, mediaId);
  throw new HttpsError('invalid-argument', 'The upload failed verification.', { reason: v.reason });
}

async function getMediaUrl(request) {
  const uid = await _requireMediaUser(request);
  const cfg = _requireConfig();
  const mediaId = _str(((request && request.data) || {}).mediaId);
  // Staging rule: owner or admin. Real categories need their own
  // relationship rules (job, conversation, dispute) before they can exist.
  const m = await _loadAccessible(mediaId, uid, { allowAdmin: true });
  if (m.status !== 'verified') throw new HttpsError('failed-precondition', 'This media is not available.');
  const url = await _store(cfg).presignGet({ key: m.objectKey, expiresIn: LIMITS.urlTtlSeconds });
  _log('media_url_issued', { mediaId });
  // Never stored anywhere: returned to this caller only.
  return { mediaId, url, expiresAt: _nowMs() + LIMITS.urlTtlSeconds * 1000, mimeType: m.mimeType, sizeBytes: m.sizeBytes, width: m.width || null, height: m.height || null };
}

async function deleteMedia(request) {
  const uid = await _requireMediaUser(request);
  const cfg = _requireConfig();
  const mediaId = _str(((request && request.data) || {}).mediaId);
  const m = await _loadAccessible(mediaId, uid, { allowAdmin: true });
  if (['deleted', 'expired', 'rejected'].includes(m.status)) return { mediaId, status: m.status, retryScheduled: false };
  if (m.status === 'delete_failed') return { mediaId, status: 'delete_failed', retryScheduled: false };
  if (m.status === 'verifying' || m.status === 'uploading') throw new HttpsError('failed-precondition', 'This media is being processed. Try again shortly.');
  await _beginDelete(mediaId, { finalStatus: 'deleted', by: uid });
  const r = await _attemptDelete(cfg, mediaId);
  return { mediaId, status: r.status, retryScheduled: r.status === 'deleting' };
}

async function runMediaSweep(request) {
  if (!request || !request.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
  if (!(await _isAdmin(request.auth.uid))) throw new HttpsError('permission-denied', 'Admin privileges required.');
  const cfg = _requireConfig();
  const d = request.data || {};
  return _sweepMedia(cfg, { reconcile: d.reconcile === true });
}

// ─── Sweeps ─────────────────────────────────────────────────────────────────
async function _expireDocs(cfg, docs) {
  let n = 0;
  for (const doc of docs) {
    const r = await _beginDelete(doc.id, { finalStatus: 'expired', by: 'system' });
    if (r.ok) {
      await _attemptDelete(cfg, doc.id);
      n++;
    }
  }
  return n;
}

// The caller's own abandoned uploads (bounded) before a new request.
async function _sweepOwnExpired(cfg, uid) {
  const snap = await db().collection('media').where('ownerUid', '==', uid)
    .where('status', 'in', ['pending', 'uploading', 'uploaded']).where('expiresAt', '<', _nowTs())
    .limit(LIMITS.ownSweepBatch).get();
  return _expireDocs(cfg, snap.docs);
}

async function _sweepMedia(cfg, { reconcile = false } = {}) {
  const now = _nowTs();
  const out = { expired: 0, interrupted: 0, deleteRetried: 0, orphans: [] };
  const expired = await db().collection('media').where('status', 'in', ['pending', 'uploading', 'uploaded'])
    .where('expiresAt', '<', now).limit(LIMITS.sweepBatch).get();
  out.expired = await _expireDocs(cfg, expired.docs);

  const stuck = await db().collection('media').where('status', '==', 'verifying')
    .where('verifyingSince', '<', Timestamp.fromMillis(_nowMs() - LIMITS.verifyingStuckMs)).limit(LIMITS.sweepBatch).get();
  for (const doc of stuck.docs) {
    const r = await _beginDelete(doc.id, { finalStatus: 'rejected', by: 'system', extra: { rejectedReason: 'verification_interrupted' } });
    if (r.ok) { await _attemptDelete(cfg, doc.id); out.interrupted++; }
  }

  const retry = await db().collection('media').where('status', '==', 'deleting')
    .where('nextDeleteAt', '<=', now).limit(LIMITS.sweepBatch).get();
  for (const doc of retry.docs) { await _attemptDelete(cfg, doc.id); out.deleteRetried++; }

  if (reconcile) {
    // REPORT ONLY: objects under this deployment's prefix with no live
    // record. Emulator data is ephemeral, so nothing is deleted here; an
    // operator removes specific keys deliberately.
    const objects = await _store(cfg).list({ prefix: `${cfg.keyPrefix}/`, maxKeys: LIMITS.reconcileMaxKeys });
    for (const o of objects) {
      const q = await db().collection('media').where('objectKey', '==', o.key).limit(1).get();
      const st = q.empty ? null : q.docs[0].data().status;
      if (!st || ['deleted', 'expired', 'rejected'].includes(st)) out.orphans.push(o.key);
    }
  }
  _log('media_sweep', { expired: out.expired, interrupted: out.interrupted, deleteRetried: out.deleteRetried, orphans: out.orphans.length });
  return out;
}

// ─── Callables ──────────────────────────────────────────────────────────────
const handlers = { requestMediaUpload, uploadMediaContent, confirmMediaUpload, getMediaUrl, deleteMedia, runMediaSweep };
const BOTH_KEYS = [...SIGNER_SECRETS, ...CLEANUP_SECRETS];
const OPTS = { secrets: BOTH_KEYS, timeoutSeconds: 120, memory: '512MiB' };
const callables = {
  requestMediaUpload: onCall(OPTS, requestMediaUpload),
  uploadMediaContent: onCall(OPTS, uploadMediaContent),
  confirmMediaUpload: onCall(OPTS, confirmMediaUpload),
  getMediaUrl: onCall({ ...OPTS, secrets: BOTH_KEYS }, getMediaUrl),
  deleteMedia: onCall(OPTS, deleteMedia),
  runMediaSweep: onCall({ ...OPTS, timeoutSeconds: 300 }, runMediaSweep),
};

module.exports = {
  handlers, callables,
  _config, _sniff, _validateContent, _sha256, _sweepMedia, _attemptDelete, _verifyStoredObject,
  _setMediaStore, _setMediaClock, _rumptyStore, _moveQuota,
  KINDS, LIMITS, ALLOWED_BUCKETS, SIGNER_SECRETS, CLEANUP_SECRETS,
};
