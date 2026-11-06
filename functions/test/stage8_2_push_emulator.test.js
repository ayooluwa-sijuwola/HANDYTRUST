// Stage 8.2 (approved backend change) — push delivery: server-side
// preference, per-device tokens, invalid-token cleanup, account-switch
// token release, private payloads, conversation routes, de-duplication.
// Firestore emulator only; FCM is replaced by an injected sender (no sends).
process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8090';
process.env.GCLOUD_PROJECT = 'handytrust-stage82-push-test';

const { test, describe, beforeEach, after } = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
const fns = require('../index.js');

const db = admin.firestore();
const PROJECT = process.env.GCLOUD_PROJECT;
const TOKEN_A = 'tokA_' + 'a'.repeat(40);
const TOKEN_B = 'tokB_' + 'b'.repeat(40);

let sent;
function sender(results) {
  return async (messages) => {
    sent.push(...messages);
    return messages.map((m, i) => (typeof results === 'function' ? results(m, i) : { success: true }));
  };
}

beforeEach(async () => {
  await fetch(`http://127.0.0.1:8090/emulator/v1/projects/${PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  sent = [];
  fns._setPushSender(sender());
});
after(() => fns._setPushSender(null));

const device = (uid, id, token, updatedAt = admin.firestore.Timestamp.now()) => db.doc(`fcm_tokens/${uid}/devices/${id}`).set({ token, platform: 'android', updatedAt });
const at = (ms) => admin.firestore.Timestamp.fromMillis(ms);
const T0 = Date.UTC(2026, 10, 5, 9, 0, 0);
const exists = async (path) => (await db.doc(path).get()).exists;
const notif = (over = {}) => ({ userId: 'u1', type: 'job_status_update', title: 'Work submitted', body: 'Review it', jobId: 'j1', route: '/job/j1', ...over });

describe('Server-side notification preference', () => {
  test('preference off → no push, nothing sent', async () => {
    await db.doc('users/u1').set({ name: 'U', notificationsEnabled: false });
    await device('u1', 'd1', TOKEN_A);
    const r = await fns._deliverPush(notif(), 'n1');
    assert.equal(r.reason, 'preference_off');
    assert.equal(sent.length, 0);
  });
  test('preference on (or missing) → push sent', async () => {
    await db.doc('users/u1').set({ name: 'U' });
    await device('u1', 'd1', TOKEN_A);
    const r = await fns._deliverPush(notif(), 'n1');
    assert.equal(r.sent, 1);
  });
  test('no registered device → skipped without error', async () => {
    const r = await fns._deliverPush(notif(), 'n1');
    assert.equal(r.reason, 'no_tokens');
  });
});

describe('Per-device tokens', () => {
  test('every device of the account receives the push', async () => {
    await device('u1', 'd1', TOKEN_A);
    await device('u1', 'd2', TOKEN_B);
    const r = await fns._deliverPush(notif(), 'n1');
    assert.equal(r.devices, 2);
    assert.deepEqual(sent.map((m) => m.token).sort(), [TOKEN_A, TOKEN_B].sort());
  });
  test('legacy single token + same device token → sent once (de-duplicated)', async () => {
    await db.doc('fcm_tokens/u1').set({ token: TOKEN_A });
    await device('u1', 'd1', TOKEN_A);
    await fns._deliverPush(notif(), 'n1');
    assert.equal(sent.length, 1);
  });
  test('legacy token from an older app version still receives pushes', async () => {
    await db.doc('fcm_tokens/u1').set({ token: TOKEN_B });
    await fns._deliverPush(notif(), 'n1');
    assert.deepEqual(sent.map((m) => m.token), [TOKEN_B]);
  });
});

describe('Invalid-token cleanup', () => {
  test('unregistered token → only that device removed; others kept', async () => {
    await device('u1', 'd1', TOKEN_A);
    await device('u1', 'd2', TOKEN_B);
    fns._setPushSender(sender((m) => (m.token === TOKEN_A ? { success: false, error: { code: 'messaging/registration-token-not-registered' } } : { success: true })));
    const r = await fns._deliverPush(notif(), 'n1');
    assert.equal(r.removed, 1);
    assert.equal((await db.doc('fcm_tokens/u1/devices/d1').get()).exists, false);
    assert.equal((await db.doc('fcm_tokens/u1/devices/d2').get()).exists, true);
  });
  test('transient failures never remove a token', async () => {
    await device('u1', 'd1', TOKEN_A);
    for (const code of ['messaging/internal-error', 'messaging/server-unavailable', 'messaging/quota-exceeded', 'messaging/invalid-argument', undefined]) {
      fns._setPushSender(sender(() => ({ success: false, error: code ? { code } : undefined })));
      const r = await fns._deliverPush(notif(), 'n1');
      assert.equal(r.removed, 0, String(code));
    }
    assert.equal((await db.doc('fcm_tokens/u1/devices/d1').get()).exists, true);
  });
  test('a token refreshed during delivery is not removed (compare-and-delete)', async () => {
    await device('u1', 'd1', TOKEN_A);
    fns._setPushSender(async (messages) => {
      await device('u1', 'd1', TOKEN_B); // refreshed while the old one failed
      return messages.map(() => ({ success: false, error: { code: 'messaging/invalid-registration-token' } }));
    });
    const r = await fns._deliverPush(notif(), 'n1');
    assert.equal(r.removed, 0);
    assert.equal((await db.doc('fcm_tokens/u1/devices/d1').get()).data().token, TOKEN_B);
  });
  test('invalid legacy token → legacy field cleared', async () => {
    await db.doc('fcm_tokens/u1').set({ token: TOKEN_A });
    fns._setPushSender(sender(() => ({ success: false, error: { code: 'messaging/registration-token-not-registered' } })));
    await fns._deliverPush(notif(), 'n1');
    assert.equal((await db.doc('fcm_tokens/u1').get()).data().token, undefined);
  });
});

describe('Account switching on a shared device', () => {
  test('a token registered by a new account is released from every other account', async () => {
    await device('alice', 'phone', TOKEN_A);
    await db.doc('fcm_tokens/carol').set({ token: TOKEN_A });
    await device('bob', 'phone', TOKEN_A);
    const released = await fns._releaseTokenElsewhere('bob', 'phone', TOKEN_A);
    assert.equal(released, 2);
    assert.equal((await db.doc('fcm_tokens/alice/devices/phone').get()).exists, false);
    assert.equal((await db.doc('fcm_tokens/carol').get()).data().token, undefined);
    assert.equal((await db.doc('fcm_tokens/bob/devices/phone').get()).exists, true);
  });
});

describe('Payload privacy and routing', () => {
  test('message pushes carry no message text; Android channel + private visibility', async () => {
    await device('u1', 'd1', TOKEN_A);
    await fns._deliverPush(notif({ type: 'message_received', title: 'New Message', body: 'my address is 12 Secret Street', route: '/job/j1', chatWith: 'a1' }), 'n1');
    const m = sent[0];
    assert.equal(m.notification.body, 'You have a new message about one of your jobs.');
    assert.ok(!JSON.stringify(m).includes('Secret Street'));
    assert.equal(m.android.notification.channelId, 'handy_trust_main');
    assert.equal(m.android.notification.visibility, 'private');
    assert.equal(m.data.route, '/job/j1'); // F-1: what older app versions open
    assert.equal(m.data.chatWith, 'a1'); // new versions open the exact conversation
    assert.equal(m.data.uid, 'u1'); // recipient, for foreground suppression (F-6/F-11)
    for (const v of Object.values(m.data)) assert.equal(typeof v, 'string'); // FCM data must be strings
  });
  test('dispute and payout pushes use minimal text', () => {
    for (const type of ['dispute_raised', 'payout_completed', 'payout_blocked']) {
      const c = fns._pushContent({ type, title: 'x', body: '₦85,000 released to 0123456789' });
      assert.ok(!c.body.includes('₦'), type);
    }
    // F-9: stored bodies never reach the lock screen; titles are fixed server strings.
    const c = fns._pushContent({ type: 'job_status_update', title: 'Work submitted', body: 'Review it' });
    assert.equal(c.title, 'Work submitted');
    assert.equal(c.body, 'There is an update on one of your jobs.');
  });

  test('F-9: no stored body (amounts, names, free text) is sent for ANY type', () => {
    const secret = 'Kola sent a quote for ₦85,000 — call 08031234567 at 12 Secret Street';
    const types = ['message_received', 'dispute_raised', 'payout_completed', 'payout_blocked', 'quote_received',
      'quote_withdrawn', 'quote_rejected', 'agreement_pending', 'agreement_accepted', 'agreement_changes_requested',
      'job_assigned', 'job_status_update', 'review_received', 'a_type_added_later'];
    for (const type of types) {
      const c = fns._pushContent({ type, title: 'Fixed Title', body: secret });
      assert.ok(!c.body.includes('₦') && !/\d{6,}/.test(c.body) && !c.body.includes('Secret') && !c.body.includes('Kola'), type);
      assert.ok(c.body.length > 0 && c.title.length > 0, type);
    }
  });
});

describe('Message notifications: exact conversation, recipient only, no duplicates', () => {
  test('route names the sender; only the recipient is notified; same event twice → one record', async () => {
    const msg = { senderId: 'cust1', receiverId: 'art1', text: 'Can you come at 9?', type: 'text' };
    await fns._handleMessageCreated('j1', msg, 'evt-1');
    await fns._handleMessageCreated('j1', msg, 'evt-1'); // trigger retry
    const all = await db.collection('notifications').get();
    assert.equal(all.size, 1);
    const n = all.docs[0].data();
    assert.equal(n.userId, 'art1');
    assert.equal(n.type, 'message_received');
    // F-1: older app versions open /job/{id}; their /chat route cannot be
    // opened from a tap. New versions build the chat route from chatWith.
    assert.equal(n.route, '/job/j1');
    assert.equal(n.chatWith, 'cust1');
  });
});

describe('F-7: token ownership converges on the newest registration', () => {
  test('a late event for an older registration never removes the newer one', async () => {
    await device('alice', 'phone', TOKEN_A, at(T0));
    await device('bob', 'phone', TOKEN_A, at(T0 + 5000));
    const released = await fns._releaseTokenElsewhere('alice', 'phone', TOKEN_A, at(T0)); // arrives after bob's write
    assert.equal(released, 0);
    assert.equal(await exists('fcm_tokens/bob/devices/phone'), true);
    assert.equal(await fns._releaseTokenElsewhere('bob', 'phone', TOKEN_A, at(T0 + 5000)), 1);
    assert.equal(await exists('fcm_tokens/alice/devices/phone'), false);
  });
  test('a duplicate/stale event whose registration has since changed does nothing', async () => {
    await device('alice', 'phone', TOKEN_A, at(T0 + 9000)); // rewritten after the event
    await device('bob', 'phone', TOKEN_A, at(T0 + 1000));
    assert.equal(await fns._releaseTokenElsewhere('alice', 'phone', TOKEN_A, at(T0)), 0);
    assert.equal(await exists('fcm_tokens/bob/devices/phone'), true);
  });
  test('concurrent registrations of one token leave exactly one owner (the newest)', async () => {
    await device('alice', 'phone', TOKEN_A, at(T0));
    await device('bob', 'phone', TOKEN_A, at(T0 + 1));
    await Promise.all([
      fns._releaseTokenElsewhere('alice', 'phone', TOKEN_A, at(T0)),
      fns._releaseTokenElsewhere('bob', 'phone', TOKEN_A, at(T0 + 1)),
    ]);
    assert.equal(await exists('fcm_tokens/alice/devices/phone'), false);
    assert.equal(await exists('fcm_tokens/bob/devices/phone'), true);
  });
  test('identical timestamps: deterministic single winner', async () => {
    await device('alice', 'phone', TOKEN_A, at(T0));
    await device('bob', 'phone', TOKEN_A, at(T0));
    await fns._releaseTokenElsewhere('alice', 'phone', TOKEN_A, at(T0));
    await fns._releaseTokenElsewhere('bob', 'phone', TOKEN_A, at(T0));
    const left = [await exists('fcm_tokens/alice/devices/phone'), await exists('fcm_tokens/bob/devices/phone')];
    assert.deepEqual(left, [false, true]);
  });
  test('a registration refreshed after the lookup is not removed (compare-and-delete)', async () => {
    await device('alice', 'phone', TOKEN_B, at(T0 + 1)); // was TOKEN_A when looked up; refreshed since
    const ref = db.doc('fcm_tokens/alice/devices/phone');
    assert.equal(await fns._releaseIfOlder(ref, TOKEN_A, at(T0 + 5000), 'fcm_tokens/bob/devices/phone'), false);
    assert.equal((await ref.get()).data().token, TOKEN_B);
  });
  test('the same event delivered twice is idempotent', async () => {
    await device('alice', 'phone', TOKEN_A, at(T0));
    await device('bob', 'phone', TOKEN_A, at(T0 + 10));
    assert.equal(await fns._releaseTokenElsewhere('bob', 'phone', TOKEN_A, at(T0 + 10)), 1);
    assert.equal(await fns._releaseTokenElsewhere('bob', 'phone', TOKEN_A, at(T0 + 10)), 0);
    assert.equal(await exists('fcm_tokens/bob/devices/phone'), true);
  });
});

describe('F-8: bounded registrations per account', () => {
  const tok = (i) => `tok${String(i).padStart(2, '0')}_` + 'x'.repeat(40);
  test('pushes go to at most the 10 most recently refreshed devices', async () => {
    for (let i = 0; i < 12; i++) await device('u1', `d${i}`, tok(i), at(T0 + i * 1000));
    const r = await fns._deliverPush(notif(), 'n1');
    assert.equal(fns.MAX_PUSH_DEVICES, 10);
    assert.equal(r.devices, 10);
    assert.deepEqual(sent.map((m) => m.token).sort(), [...Array(10)].map((_, k) => tok(k + 2)).sort());
  });
  test('registrations beyond 10 are pruned, oldest first', async () => {
    for (let i = 0; i < 13; i++) await device('u1', `d${i}`, tok(i), at(T0 + i * 1000));
    assert.equal(await fns._pruneDevices('u1'), 3);
    for (const i of [0, 1, 2]) assert.equal(await exists(`fcm_tokens/u1/devices/d${i}`), false);
    for (let i = 3; i < 13; i++) assert.equal(await exists(`fcm_tokens/u1/devices/d${i}`), true);
    assert.equal(await fns._pruneDevices('u1'), 0);
  });
  test('stale registrations (not refreshed for 270 days) are swept; recent ones kept', async () => {
    const day = 24 * 60 * 60 * 1000;
    const now = T0 + 400 * day;
    await device('u1', 'old', tok(1), at(now - 300 * day));
    await device('u1', 'new', tok(2), at(now - 10 * day));
    await device('u2', 'edge', tok(3), at(now - 269 * day));
    assert.equal(await fns._sweepStaleDevices(now), 1);
    assert.equal(await exists('fcm_tokens/u1/devices/old'), false);
    assert.equal(await exists('fcm_tokens/u1/devices/new'), true);
    assert.equal(await exists('fcm_tokens/u2/devices/edge'), true);
  });
});
