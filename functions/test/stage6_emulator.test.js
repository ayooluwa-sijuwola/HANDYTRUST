/**
 * Stage 6 — server-generated notifications, location privacy, payout status
 * mirror (design/REMEDIATION_STAGE6_REPORT_2026-11-03.md).
 * LOCAL Firestore emulator only; Paystack is never called.
 */
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8090';
process.env.GCLOUD_PROJECT = 'handytrust-stage6-test';

const { test, describe, beforeEach, after } = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
const fns = require('../index.js');

const db = admin.firestore();
const PROJECT = process.env.GCLOUD_PROJECT;
const get = async (p) => (await db.doc(p).get()).data();
const notificationsFor = async (uid) => (await db.collection('notifications').where('userId', '==', uid).get()).docs.map((d) => d.data());

beforeEach(async () => {
  await fetch(`http://127.0.0.1:8090/emulator/v1/projects/${PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  fns._setPaystackFakes({
    paystack: { createRefund: async () => ({ status: 'pending' }), fetchRefund: async () => ({}), listRefunds: async () => [] },
    transferHttp: { post: async () => ({ data: { data: { status: 'pending', transfer_code: 'T' } } }) },
  });
});
after(() => fns._setPaystackFakes({}));

describe('Server-generated notifications (HT-015 final)', () => {
  beforeEach(async () => {
    await db.doc('jobs/j1').set({ customerId: 'cust1', artisanId: '', status: 'requested' });
  });

  test('new quote → customer notified once, even if the trigger is redelivered', async () => {
    const quote = { artisanId: 'art2', artisanName: 'Ada', amount: 12000, status: 'pending' };
    await fns._handleQuoteWrite('j1', null, quote, 'evt-1');
    await fns._handleQuoteWrite('j1', null, quote, 'evt-1'); // redelivery
    const n = await notificationsFor('cust1');
    assert.equal(n.length, 1);
    assert.equal(n[0].type, 'quote_received');
    assert.match(n[0].body, /Ada sent a quote for ₦12,000/);
    assert.equal(n[0].route, '/job/j1');
  });

  test('quote rejected / closed / withdrawn notify the right party; reopen-withdrawal is silent', async () => {
    const pending = { artisanId: 'art2', status: 'pending', amount: 1 };
    await fns._handleQuoteWrite('j1', pending, { ...pending, status: 'rejected' }, 'e1');
    await fns._handleQuoteWrite('j1', pending, { ...pending, status: 'closed' }, 'e2');
    await fns._handleQuoteWrite('j1', pending, { ...pending, status: 'withdrawn' }, 'e3');
    await fns._handleQuoteWrite('j1', pending, { ...pending, status: 'withdrawn', withdrawnReason: 'artisan_withdrew' }, 'e4');
    assert.deepEqual((await notificationsFor('art2')).map((n) => n.title).sort(), ['Another Quote Was Chosen', 'Quote Declined']);
    assert.equal((await notificationsFor('cust1')).length, 1); // the voluntary withdrawal only
  });

  test('chat message → receiver notified; self/system messages are not', async () => {
    await fns._handleMessageCreated('j1', { senderId: 'art2', receiverId: 'cust1', type: 'text', text: 'Hello there' }, 'm1');
    await fns._handleMessageCreated('j1', { senderId: 'cust1', receiverId: 'cust1', type: 'text', text: 'x' }, 'm2');
    await fns._handleMessageCreated('j1', { senderId: 'art2', receiverId: 'cust1', type: 'system', text: 'x' }, 'm3');
    const n = await notificationsFor('cust1');
    assert.equal(n.length, 1);
    assert.equal(n[0].body, 'Hello there');
  });

  test('dispute raised by the ARTISAN notifies the customer (D3); admin alert is deterministic', async () => {
    const d = { jobId: 'j1', raisedBy: 'art1', againstUserId: 'cust1', reason: 'unreachable' };
    await fns._handleDisputeCreated('d1', d, 'evt-d');
    await fns._handleDisputeCreated('d1', d, 'evt-d');
    assert.equal((await notificationsFor('cust1')).length, 1);
    assert.equal((await db.collection('admin_alerts').get()).size, 1);
  });
});

describe('Notification decision helpers', () => {
  test('agreement changes', () => {
    const base = { customerId: 'c', artisanId: 'a' };
    assert.equal(fns._agreementNotification({ ...base }, { ...base, agreementStatus: 'pendingArtisanConfirmation' }).to, 'a');
    assert.equal(fns._agreementNotification({ ...base, agreementStatus: 'pendingArtisanConfirmation' }, { ...base, agreementStatus: 'confirmed' }).to, 'c');
    assert.equal(fns._agreementNotification({ ...base, agreementStatus: 'pendingArtisanConfirmation' }, { ...base, agreementStatus: 'changesRequested', agreementChangesRequestedReason: 'price' }).body, 'price');
    assert.equal(fns._agreementNotification({ ...base, agreementStatus: 'confirmed' }, { ...base, agreementStatus: 'confirmed' }), null);
  });

  test('work started and cancellation (to the other party only)', () => {
    const base = { customerId: 'c', artisanId: 'a' };
    assert.deepEqual(fns._statusChangeNotifications({ ...base, status: 'escrowLocked' }, { ...base, status: 'inProgress' }).map((n) => n.to), ['c']);
    assert.deepEqual(fns._statusChangeNotifications({ ...base, status: 'inChat' }, { ...base, status: 'cancelled', cancelledBy: 'c' }).map((n) => n.to), ['a']);
    assert.deepEqual(fns._statusChangeNotifications({ ...base, status: 'escrowLocked' }, { ...base, status: 'cancelled', cancelledBy: 'adm' }).map((n) => n.to).sort(), ['a', 'c']);
  });
});

describe('Location privacy (P-K, D9)', () => {
  test('a job written with exact location (older app build) is moved to the private document', async () => {
    await db.doc('jobs/j1').set({
      customerId: 'cust1', status: 'requested',
      customerLat: 6.52437, customerLng: 3.37921, customerAddress: '12 Home Street, Ikeja, Lagos',
    });
    assert.equal(await fns._protectJobLocation(db.doc('jobs/j1')), true);
    const job = await get('jobs/j1');
    assert.equal(job.customerLat, undefined);
    assert.equal(job.customerAddress, undefined);
    assert.equal(job.areaLat, 6.52);
    assert.equal(job.areaLng, 3.38);
    assert.equal(job.areaLabel, 'Ikeja, Lagos');
    assert.equal(job.areaGeohash4, fns._geohashEncode(6.52437, 3.37921, 4));
    const priv = await get('jobs/j1/private/location');
    assert.equal(priv.customerAddress, '12 Home Street, Ikeja, Lagos');
    assert.equal(priv.customerLat, 6.52437);
    assert.equal(await fns._protectJobLocation(db.doc('jobs/j1')), false); // idempotent
  });

  test('backfill pages through existing jobs and reports a cursor', async () => {
    for (let i = 0; i < 3; i++) {
      await db.doc(`jobs/j${i}`).set({ customerId: 'c', status: 'requested', customerAddress: `Addr ${i}`, customerLat: 6.5, customerLng: 3.4 });
    }
    await db.doc('jobs/j9').set({ customerId: 'c', status: 'requested', areaLat: 6.5 });
    const page = await fns._backfillJobLocationPrivacy({ pageSize: 10 });
    assert.equal(page.moved, 3);
    assert.equal(page.nextCursor, null);
  });

  test('geo helpers: area label never leaks a street; invalid coordinates give no area', () => {
    assert.equal(fns._areaLabel('12 Home Street, Lagos'), null);
    assert.equal(fns._areaLabel('Flat 2, 12 Home Street, Ikeja, Lagos'), 'Ikeja, Lagos');
    assert.equal(fns._coarseArea(200, 3, 'x'), null);
  });

  test('geohash matches the published reference value', () => {
    // Reference: geohash of (57.64911, 10.40744) is "u4pruydqqvj" (Niemeyer).
    assert.equal(fns._geohashEncode(57.64911, 10.40744, 11), 'u4pruydqqvj');
  });
});

describe('Payout status mirror (HT-024)', () => {
  test('frozen → on_hold; successful transfer → processing → paid', async () => {
    await db.doc('users/art1').set({ accountStatus: 'suspended', suspensionType: 'fraud' });
    await db.doc('artisans/art1').set({ uid: 'art1' });
    await db.doc('artisan_private/art1').set({ accountNumber: '1', bankName: 'Access Bank', accountName: 'A', paystackRecipientCode: 'R' });
    await db.doc('jobs/j1').set({ customerId: 'cust1', artisanId: 'art1', status: 'completed', agreedAmount: 50000 });
    await db.doc('payments/p1').set({ jobId: 'j1', payerId: 'cust1', status: 'escrowHeld', amount: 50000, serviceAmount: 50000 });
    await db.doc('escrow_releases/j1').set({ jobId: 'j1', status: 'pending', requestedBy: 'cust1' });
    await fns._processEscrowRelease(db.doc('escrow_releases/j1'), 'j1', { post: async () => ({ data: { data: {} } }) });
    assert.equal((await get('jobs/j1')).payoutStatus, 'on_hold');

    await db.doc('users/art1').set({ accountStatus: 'active' });
    await fns._retryPayout({ jobId: 'j1', adminId: 'adm', reason: 'cleared' });
    assert.equal((await get('jobs/j1')).payoutStatus, 'processing');
    await fns._onTransferSucceeded('j1', 'j1-p2');
    assert.equal((await get('jobs/j1')).payoutStatus, 'paid');
  });
});
