// RumptyCloud staging media — T1-13: media records, quotas and limits are
// server-only. Clients may read their own records (admins: all) and can
// never create, change or delete them (no forged or self-confirmed uploads,
// no ownership/key/status/visibility changes, no bypassing clean-up).
// Run against the Firestore emulator (127.0.0.1:8090).
const { test, before, after, beforeEach, describe } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const { Timestamp, doc, setDoc, updateDoc, getDoc, getDocs, deleteDoc, collection, query, where } = require('firebase/firestore');

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'handytrust-media-rules',
    firestore: { rules: fs.readFileSync(path.resolve(__dirname, '../firestore.rules'), 'utf8'), host: '127.0.0.1', port: 8090 },
  });
});
after(async () => env.cleanup());

const record = (over = {}) => ({
  provider: 'rumpty', env: 'staging', bucket: 'assets-handytrust-01a0f99e-5d6ffa', objectKey: 'staging/media/test-avatar/2026/11/a.png',
  kind: 'test-avatar', mimeType: 'image/png', sizeBytes: 168, sha256: 'a'.repeat(64), ownerUid: 'u1', visibility: 'private',
  status: 'pending', uploadMode: 'proxy', quota: 'reserved', createdAt: Timestamp.now(), updatedAt: Timestamp.now(), deleteAttempts: 0, ...over,
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (c) => {
    const db = c.firestore();
    await setDoc(doc(db, 'users/u1'), { name: 'U1' });
    await setDoc(doc(db, 'users/u2'), { name: 'U2' });
    await setDoc(doc(db, 'admins/adm'), { role: 'admin' });
    await setDoc(doc(db, 'media/m1'), record());
    await setDoc(doc(db, 'media/m2'), record({ ownerUid: 'u2', status: 'verified', quota: 'used' }));
    await setDoc(doc(db, 'media_quotas/u1'), { reservedBytes: 168, usedBytes: 0, pendingCount: 1 });
    await setDoc(doc(db, 'media_system/limits'), { reservedBytes: 168, usedBytes: 168, pendingCount: 1 });
  });
});

const as = (uid) => env.authenticatedContext(uid, { email_verified: true, firebase: { sign_in_provider: 'password' } }).firestore();
const anon = () => env.unauthenticatedContext().firestore();

describe('T1-13 media/{id}: read own only; no client writes at all', () => {
  test('owner reads own record; another user and anonymous cannot; admin can', async () => {
    await assertSucceeds(getDoc(doc(as('u1'), 'media/m1')));
    await assertFails(getDoc(doc(as('u2'), 'media/m1')));
    await assertFails(getDoc(doc(anon(), 'media/m1')));
    await assertSucceeds(getDoc(doc(as('adm'), 'media/m1')));
  });
  test('list queries must be scoped to the caller', async () => {
    await assertSucceeds(getDocs(query(collection(as('u1'), 'media'), where('ownerUid', '==', 'u1'))));
    await assertFails(getDocs(collection(as('u1'), 'media')));
    await assertFails(getDocs(query(collection(as('u1'), 'media'), where('ownerUid', '==', 'u2'))));
  });
  test('a client cannot forge a record, even a "verified" one for itself', async () => {
    await assertFails(setDoc(doc(as('u1'), 'media/forged'), record({ status: 'verified', quota: 'used' })));
    await assertFails(setDoc(doc(as('u1'), 'media/forged2'), record()));
  });
  test('the owner cannot change status, owner, key, bucket, visibility, checksum or size', async () => {
    for (const change of [{ status: 'verified' }, { ownerUid: 'u2' }, { objectKey: 'staging/media/other.png' }, { bucket: 'other' },
      { visibility: 'public' }, { sha256: 'b'.repeat(64) }, { sizeBytes: 1 }, { deleteAttempts: 0 }, { quota: 'released' }]) {
      await assertFails(updateDoc(doc(as('u1'), 'media/m1'), change));
    }
    await assertFails(updateDoc(doc(as('adm'), 'media/m1'), { status: 'verified' })); // not even admins from a client
  });
  test('nobody can delete a record from a client (clean-up cannot be bypassed)', async () => {
    await assertFails(deleteDoc(doc(as('u1'), 'media/m1')));
    await assertFails(deleteDoc(doc(as('adm'), 'media/m1')));
  });
});

describe('T1-13 media_quotas and media_system', () => {
  test('owner reads own counters; nobody writes them; global limits are invisible', async () => {
    await assertSucceeds(getDoc(doc(as('u1'), 'media_quotas/u1')));
    await assertFails(getDoc(doc(as('u2'), 'media_quotas/u1')));
    await assertFails(updateDoc(doc(as('u1'), 'media_quotas/u1'), { usedBytes: 0, pendingCount: 0 }));
    await assertFails(setDoc(doc(as('u2'), 'media_quotas/u2'), { usedBytes: 0 }));
    await assertFails(getDoc(doc(as('u1'), 'media_system/limits')));
    await assertFails(getDoc(doc(as('adm'), 'media_system/limits')));
    await assertFails(setDoc(doc(as('adm'), 'media_system/limits'), { minuteCount: 0 }));
  });
});
