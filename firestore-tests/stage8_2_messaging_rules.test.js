// Stage 8.2 (approved backend change) — read/delivered receipts may be
// written only by the message's recipient, once, at server time; per-device
// FCM token documents are owner-only with a strict shape.
// Run against the Firestore emulator (127.0.0.1:8090).
const { test, before, after, beforeEach, describe } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const { serverTimestamp, Timestamp, doc, setDoc, updateDoc, getDoc, deleteDoc } = require('firebase/firestore');

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'handytrust-stage82-messaging',
    firestore: { rules: fs.readFileSync(path.resolve(__dirname, '../firestore.rules'), 'utf8'), host: '127.0.0.1', port: 8090 },
  });
});
after(async () => env.cleanup());
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (c) => {
    const db = c.firestore();
    await setDoc(doc(db, 'users/cust1'), { name: 'C', roles: ['customer'], accountStatus: 'active' });
    await setDoc(doc(db, 'users/art1'), { name: 'A', roles: ['artisan'], accountStatus: 'active' });
    await setDoc(doc(db, 'artisans/art1'), { name: 'A' });
    await setDoc(doc(db, 'jobs/j1'), { customerId: 'cust1', artisanId: 'art1', status: 'inChat', category: 'Plumbing', description: 'x' });
    // m1: artisan → customer, unread; m2: already read; m3: already delivered
    await setDoc(doc(db, 'jobs/j1/messages/m1'), { id: 'm1', jobId: 'j1', senderId: 'art1', receiverId: 'cust1', text: 'hi', type: 'text', isRead: false, createdAt: Timestamp.now() });
    await setDoc(doc(db, 'jobs/j1/messages/m2'), { id: 'm2', jobId: 'j1', senderId: 'art1', receiverId: 'cust1', text: 'hi', type: 'text', isRead: true, createdAt: Timestamp.now() });
    await setDoc(doc(db, 'jobs/j1/messages/m3'), { id: 'm3', jobId: 'j1', senderId: 'art1', receiverId: 'cust1', text: 'hi', type: 'text', isRead: false, deliveredAt: Timestamp.now(), createdAt: Timestamp.now() });
  });
});

const as = (uid) => env.authenticatedContext(uid, { email_verified: true, firebase: { sign_in_provider: 'password' } }).firestore();
const msg = (db, id) => doc(db, `jobs/j1/messages/${id}`);

describe('Read receipts: recipient only, false → true once, server time', () => {
  test('recipient marks read with readAt + deliveredAt (server time)', async () => {
    await assertSucceeds(updateDoc(msg(as('cust1'), 'm1'), { isRead: true, readAt: serverTimestamp(), deliveredAt: serverTimestamp() }));
  });
  test('older app versions ({isRead: true} only) still work', async () => {
    await assertSucceeds(updateDoc(msg(as('cust1'), 'm1'), { isRead: true }));
  });
  test('the SENDER cannot mark a message read (no fake receipts)', async () => {
    await assertFails(updateDoc(msg(as('art1'), 'm1'), { isRead: true }));
  });
  test('a non-party cannot touch read state', async () => {
    await assertFails(updateDoc(msg(as('stranger'), 'm1'), { isRead: true }));
  });
  test('read cannot be reset (true → false)', async () => {
    await assertFails(updateDoc(msg(as('cust1'), 'm2'), { isRead: false }));
  });
  test('no duplicate read event on an already-read message', async () => {
    await assertFails(updateDoc(msg(as('cust1'), 'm2'), { isRead: true, readAt: serverTimestamp() }));
    await assertFails(updateDoc(msg(as('cust1'), 'm2'), { readAt: serverTimestamp() }));
  });
  test('readAt must be the server time and only with the read flag', async () => {
    await assertFails(updateDoc(msg(as('cust1'), 'm1'), { isRead: true, readAt: Timestamp.fromDate(new Date(2020, 0, 1)) }));
    await assertFails(updateDoc(msg(as('cust1'), 'm1'), { readAt: serverTimestamp() }));
  });
  test('recipient cannot edit content or participants', async () => {
    await assertFails(updateDoc(msg(as('cust1'), 'm1'), { isRead: true, text: 'changed' }));
    await assertFails(updateDoc(msg(as('cust1'), 'm1'), { isRead: true, senderId: 'cust1' }));
  });
});

describe('Delivered: recipient only, once, server time', () => {
  test('recipient stamps deliveredAt', async () => {
    await assertSucceeds(updateDoc(msg(as('cust1'), 'm1'), { deliveredAt: serverTimestamp() }));
  });
  test('deliveredAt cannot be set twice', async () => {
    await assertFails(updateDoc(msg(as('cust1'), 'm3'), { deliveredAt: serverTimestamp() }));
  });
  test('sender cannot claim delivery', async () => {
    await assertFails(updateDoc(msg(as('art1'), 'm1'), { deliveredAt: serverTimestamp() }));
  });
  test('client-chosen delivery time is rejected', async () => {
    await assertFails(updateDoc(msg(as('cust1'), 'm1'), { deliveredAt: Timestamp.fromDate(new Date(2030, 0, 1)) }));
  });
});

describe('F-2: delivery receipt and read receipt for the same message (chat open as it arrives)', () => {
  test('delivery receipt lands first, then the read (isRead + readAt only) is accepted', async () => {
    const db = as('cust1');
    await assertSucceeds(updateDoc(msg(db, 'm1'), { deliveredAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(msg(db, 'm1'), { isRead: true, readAt: serverTimestamp() }));
  });
  test('the pre-correction read payload (also stamping deliveredAt) is refused once delivered — why it was removed', async () => {
    const db = as('cust1');
    await assertSucceeds(updateDoc(msg(db, 'm1'), { deliveredAt: serverTimestamp() }));
    await assertFails(updateDoc(msg(db, 'm1'), { isRead: true, readAt: serverTimestamp(), deliveredAt: serverTimestamp() }));
  });
});

describe('Per-device FCM tokens (fcm_tokens/{uid}/devices/{deviceId})', () => {
  const D1 = '3f6c2a10-8b1e-4c2d-9a7e-1b2c3d4e5f60';
  const D2 = 'a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d';
  const dev = (db, uid = 'cust1', id = D1) => doc(db, `fcm_tokens/${uid}/devices/${id}`);
  const good = () => ({ token: 'tok_' + 'x'.repeat(40), platform: 'android', updatedAt: serverTimestamp() });

  test('owner registers a device', async () => {
    await assertSucceeds(setDoc(dev(as('cust1')), good()));
  });
  test('two devices of one account coexist', async () => {
    await assertSucceeds(setDoc(dev(as('cust1'), 'cust1', D1), good()));
    await assertSucceeds(setDoc(dev(as('cust1'), 'cust1', D2), { ...good(), token: 'tok_' + 'y'.repeat(40) }));
  });
  test('F-8: the device id must be the app\'s lowercase UUID (no arbitrary ids)', async () => {
    for (const bad of ['dev-1', 'x'.repeat(64), '3F6C2A10-8B1E-4C2D-9A7E-1B2C3D4E5F60', D1 + '0', 'not-a-uuid-device']) {
      await assertFails(setDoc(dev(as('cust1'), 'cust1', bad), good()));
    }
  });
  test('the owner can still delete a registration whatever its id (clean-up of older ids)', async () => {
    await env.withSecurityRulesDisabled(async (c) => setDoc(dev(c.firestore(), 'cust1', 'legacy-id'), { token: 'tok_' + 'z'.repeat(40), platform: 'android', updatedAt: Timestamp.now() }));
    await assertSucceeds(deleteDoc(dev(as('cust1'), 'cust1', 'legacy-id')));
  });
  test('another user cannot register or delete a device for this account', async () => {
    await assertFails(setDoc(dev(as('art1')), good()));
    await env.withSecurityRulesDisabled(async (c) => setDoc(dev(c.firestore()), { token: 'tok_' + 'z'.repeat(40), platform: 'android', updatedAt: Timestamp.now() }));
    await assertFails(deleteDoc(dev(as('art1'))));
  });
  test('unauthenticated requests are rejected', async () => {
    await assertFails(setDoc(dev(env.unauthenticatedContext().firestore()), good()));
  });
  test('shape is enforced (fields, platform, token size, server time)', async () => {
    await assertFails(setDoc(dev(as('cust1')), { ...good(), extra: 1 }));
    await assertFails(setDoc(dev(as('cust1')), { ...good(), platform: 'desktop' }));
    await assertFails(setDoc(dev(as('cust1')), { ...good(), token: 'short' }));
    await assertFails(setDoc(dev(as('cust1')), { ...good(), updatedAt: Timestamp.fromDate(new Date(2020, 0, 1)) }));
  });
  test('tokens are never readable by clients (even the owner)', async () => {
    await env.withSecurityRulesDisabled(async (c) => setDoc(dev(c.firestore()), { token: 'tok_' + 'z'.repeat(40), platform: 'android', updatedAt: Timestamp.now() }));
    await assertFails(getDoc(dev(as('cust1'))));
  });
  test('owner removes its own device (logout)', async () => {
    await env.withSecurityRulesDisabled(async (c) => setDoc(dev(c.firestore()), { token: 'tok_' + 'z'.repeat(40), platform: 'android', updatedAt: Timestamp.now() }));
    await assertSucceeds(deleteDoc(dev(as('cust1'))));
  });
});
