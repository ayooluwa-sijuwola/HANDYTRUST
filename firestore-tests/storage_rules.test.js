/**
 * Storage Security Rules regression tests — Stage 6 (HT-023, HT-029).
 * Emulator only (Storage + Firestore, for the cross-service rules).
 *
 * Run from the repo root (any free ports; this suite reads them from env):
 *   firebase emulators:exec --only firestore,storage \
 *     "cd firestore-tests && node --test storage_rules.test.js"
 * STORAGE_EMULATOR_PORT / FIRESTORE_EMULATOR_PORT default to the
 * firebase.json values (9199 / 8090).
 */
const { test, before, after, beforeEach, describe } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const { ref, uploadBytes, getMetadata, deleteObject } = require('firebase/storage');

const PROJECT = process.env.GCLOUD_PROJECT || 'demo-handytrust-storage';
let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: PROJECT,
    firestore: {
      rules: fs.readFileSync(path.resolve(__dirname, '../firestore.rules'), 'utf8'),
      host: '127.0.0.1',
      port: Number(process.env.FIRESTORE_EMULATOR_PORT || 8090),
    },
    storage: {
      rules: fs.readFileSync(path.resolve(__dirname, '../storage.rules'), 'utf8'),
      host: '127.0.0.1',
      port: Number(process.env.STORAGE_EMULATOR_PORT || 9199),
    },
  });
});
after(async () => env.cleanup());
beforeEach(async () => {
  await env.clearFirestore();
  await env.clearStorage();
});

const C = 'cust1'; const A = 'art1'; const A2 = 'art2'; const X = 'stranger1';
const storageFor = (uid) =>
  env.authenticatedContext(uid, { firebase: { sign_in_provider: 'password' } }).storage();
const img = () => new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);
const meta = { contentType: 'image/jpeg' };

async function seedFs(fn) {
  await env.withSecurityRulesDisabled(async (c) => fn(c.firestore()));
}
async function putAs(uid, p) {
  await env.withSecurityRulesDisabled(async (c) => uploadBytes(ref(c.storage(), p), img(), meta));
}

describe('Dispute evidence (HT-023)', () => {
  beforeEach(async () => {
    await seedFs(async (f) => {
      await f.doc('disputes/d1').set({ jobId: 'j1', raisedBy: C, againstUserId: A, status: 'open' });
    });
    await putAs(C, `disputes/d1/${C}/evidence_0.jpg`);
  });

  test('the uploader and the other dispute party can read it', async () => {
    await assertSucceeds(getMetadata(ref(storageFor(C), `disputes/d1/${C}/evidence_0.jpg`)));
    await assertSucceeds(getMetadata(ref(storageFor(A), `disputes/d1/${C}/evidence_0.jpg`)));
  });

  test('a stranger or an unrelated artisan cannot', async () => {
    await assertFails(getMetadata(ref(storageFor(X), `disputes/d1/${C}/evidence_0.jpg`)));
    await assertFails(getMetadata(ref(storageFor(A2), `disputes/d1/${C}/evidence_0.jpg`)));
  });

  test('the uploader can read back evidence uploaded before the dispute document exists', async () => {
    await assertSucceeds(uploadBytes(ref(storageFor(A), `disputes/d2/${A}/evidence_0.jpg`), img(), meta));
    await assertSucceeds(getMetadata(ref(storageFor(A), `disputes/d2/${A}/evidence_0.jpg`)));
  });
});

describe('Job photos (HT-023)', () => {
  test('open job: artisan accounts may view (to quote); strangers may not', async () => {
    await seedFs(async (f) => {
      await f.doc('jobs/j1').set({ customerId: C, artisanId: '', status: 'requested' });
      await f.doc(`artisans/${A2}`).set({ uid: A2 });
    });
    await putAs(C, `jobs/j1/${C}/image_0.jpg`);
    await assertSucceeds(getMetadata(ref(storageFor(A2), `jobs/j1/${C}/image_0.jpg`)));
    await assertFails(getMetadata(ref(storageFor(X), `jobs/j1/${C}/image_0.jpg`)));
  });

  test('assigned job: only the parties (non-assigned artisans lose access)', async () => {
    await seedFs(async (f) => {
      await f.doc('jobs/j1').set({ customerId: C, artisanId: A, status: 'inProgress' });
      await f.doc(`artisans/${A2}`).set({ uid: A2 });
    });
    await putAs(C, `jobs/j1/${C}/image_0.jpg`);
    await assertSucceeds(getMetadata(ref(storageFor(A), `jobs/j1/${C}/image_0.jpg`)));
    await assertFails(getMetadata(ref(storageFor(A2), `jobs/j1/${C}/image_0.jpg`)));
  });

  test('customer can upload and read back photos before the job document exists', async () => {
    await assertSucceeds(uploadBytes(ref(storageFor(C), `jobs/new1/${C}/image_0.jpg`), img(), meta));
    await assertSucceeds(getMetadata(ref(storageFor(C), `jobs/new1/${C}/image_0.jpg`)));
  });

  test('nobody can upload into another user\'s folder', async () => {
    await assertFails(uploadBytes(ref(storageFor(X), `jobs/j1/${C}/image_9.jpg`), img(), meta));
  });
});

describe('Avatars (HT-029)', () => {
  test('owner can upload, replace and remove their avatar; others cannot write it', async () => {
    await assertSucceeds(uploadBytes(ref(storageFor(C), `profiles/${C}/avatar.jpg`), img(), meta));
    await assertSucceeds(getMetadata(ref(storageFor(X), `profiles/${C}/avatar.jpg`)));
    await assertFails(uploadBytes(ref(storageFor(X), `profiles/${C}/avatar.jpg`), img(), meta));
    await assertFails(deleteObject(ref(storageFor(X), `profiles/${C}/avatar.jpg`)));
    await assertSucceeds(deleteObject(ref(storageFor(C), `profiles/${C}/avatar.jpg`)));
  });

  test('non-images are refused', async () => {
    await assertFails(uploadBytes(ref(storageFor(C), `profiles/${C}/avatar.jpg`), img(), { contentType: 'text/html' }));
  });
});
