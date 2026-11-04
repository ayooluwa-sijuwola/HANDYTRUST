/**
 * Stage 7 — address-privacy migration verification (Stage 6 M-2,
 * adminBackfillJobLocationPrivacy). LOCAL Firestore emulator only; never
 * run against production in this stage.
 */
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8090';
process.env.GCLOUD_PROJECT = 'handytrust-stage7-migration';

const { test, describe, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
const fns = require('../index.js');

const db = admin.firestore();
const PROJECT = process.env.GCLOUD_PROJECT;
const get = async (p) => (await db.doc(p).get()).data();
const pad = (i) => String(i).padStart(3, '0');

beforeEach(async () => {
  await fetch(`http://127.0.0.1:8090/emulator/v1/projects/${PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
});

async function seedLegacy(n) {
  for (let i = 0; i < n; i++) {
    await db.doc(`jobs/j${pad(i)}`).set({
      customerId: `c${i}`, artisanId: i % 2 ? `a${i}` : '', status: i % 3 ? 'completed' : 'requested',
      category: 'Plumbing', agreedAmount: 10000 + i, description: `job ${i}`,
      customerLat: 6.5 + i / 1000, customerLng: 3.4, customerAddress: `${i} Home Street, Ikeja, Lagos`,
    });
  }
}

async function runAll(pageSize) {
  let cursor = null; let pages = 0; let moved = 0; let examined = 0;
  do {
    const r = await fns._backfillJobLocationPrivacy({ startAfter: cursor, pageSize });
    pages++; moved += r.moved; examined += r.examined; cursor = r.nextCursor;
  } while (cursor);
  return { pages, moved, examined };
}

describe('Backfill pagination and completeness', () => {
  test('multi-page run visits every job exactly once and moves every exact location', async () => {
    await seedLegacy(23);
    const r = await runAll(5);
    assert.equal(r.examined, 23);
    assert.equal(r.moved, 23);
    assert.equal(r.pages, 5);
    const left = (await db.collection('jobs').get()).docs.filter((d) =>
      ['customerLat', 'customerLng', 'customerAddress'].some((k) => d.data()[k] !== undefined));
    assert.equal(left.length, 0);
  });

  test('page size exactly divides the collection: the final empty page terminates cleanly', async () => {
    await seedLegacy(10);
    const r = await runAll(5);
    assert.equal(r.moved, 10);
    assert.equal(r.pages, 3); // 5 + 5 + empty
  });
});

describe('Rerun safety and interrupted resume', () => {
  test('a second full run moves nothing and does not rewrite the private documents', async () => {
    await seedLegacy(7);
    await runAll(3);
    const before = await get('jobs/j003/private/location');
    const r = await runAll(3);
    assert.equal(r.moved, 0);
    assert.deepEqual(await get('jobs/j003/private/location'), before); // movedAt unchanged
  });

  test('an interrupted run resumes from its cursor; restarting from scratch is also safe', async () => {
    await seedLegacy(9);
    const first = await fns._backfillJobLocationPrivacy({ pageSize: 4 });
    assert.equal(first.moved, 4);
    // "crash" here; resume from the reported cursor
    const resumed = await runAllFrom(first.nextCursor, 4);
    assert.equal(resumed, 5);
    assert.equal((await runAll(4)).moved, 0); // operator restarts from the beginning
  });

  async function runAllFrom(cursor, pageSize) {
    let moved = 0;
    while (cursor) {
      const r = await fns._backfillJobLocationPrivacy({ startAfter: cursor, pageSize });
      moved += r.moved; cursor = r.nextCursor;
    }
    return moved;
  }
});

describe('Data preservation', () => {
  test('non-location fields are untouched; exact values are preserved byte-for-byte in private', async () => {
    await seedLegacy(3);
    const original = await get('jobs/j001');
    await runAll(10);
    const job = await get('jobs/j001');
    for (const k of ['customerId', 'artisanId', 'status', 'category', 'agreedAmount', 'description']) {
      assert.deepEqual(job[k], original[k], k);
    }
    const priv = await get('jobs/j001/private/location');
    assert.equal(priv.customerAddress, original.customerAddress);
    assert.equal(priv.customerLat, original.customerLat);
    assert.equal(priv.customerLng, original.customerLng);
    assert.equal(job.areaLabel, 'Ikeja, Lagos');
  });

  test('an existing coarse area (newer app) is not recomputed or overwritten', async () => {
    await db.doc('jobs/k1').set({
      customerId: 'c', status: 'requested', customerAddress: 'Old Street, Yaba, Lagos', customerLat: 6.5, customerLng: 3.37,
      areaLat: 6.6, areaLng: 3.35, areaGeohash4: 's1x', areaLabel: 'Ikeja, Lagos',
    });
    await runAll(10);
    const job = await get('jobs/k1');
    assert.equal(job.areaLabel, 'Ikeja, Lagos');
    assert.equal(job.areaLat, 6.6);
  });

  test('partial / null legacy fields: only real values are moved; nulls are removed from the main doc', async () => {
    await db.doc('jobs/k2').set({ customerId: 'c', status: 'requested', customerAddress: 'Flat 2, 12 Home St, Ikeja, Lagos', customerLat: null });
    await runAll(10);
    const job = await get('jobs/k2');
    assert.equal(job.customerAddress, undefined);
    assert.equal('customerLat' in job, false);
    const priv = await get('jobs/k2/private/location');
    assert.deepEqual(Object.keys(priv).sort(), ['customerAddress', 'movedAt']);
    assert.equal(job.areaLat, undefined); // no coordinates → no coarse point invented
  });

  test('jobs that never had a location are counted as examined, not moved, and get no private doc', async () => {
    await db.doc('jobs/k3').set({ customerId: 'c', status: 'requested' });
    const r = await runAll(10);
    assert.deepEqual([r.examined, r.moved], [1, 0]);
    assert.equal((await db.doc('jobs/k3/private/location').get()).exists, false);
  });
});

describe('No legacy exposure through side channels', () => {
  test('the migration creates no notifications, alerts or audit rows (nothing that could carry the address)', async () => {
    await seedLegacy(4);
    await runAll(2);
    for (const c of ['notifications', 'admin_alerts', 'audit_logs']) {
      assert.equal((await db.collection(c).get()).size, 0, c);
    }
  });
});

describe('F-3 fixed (Stage 7.1): a newer private address is never overwritten', () => {
  const OLD = { customerAddress: 'OLD 1 Stale St, Yaba, Lagos', customerLat: 6.5, customerLng: 3.37 };
  const NEW = { customerAddress: 'NEW 9 Fresh Rd, Ikeja, Lagos', customerLat: 6.6, customerLng: 3.35 };

  test('stale job-document copy is deleted; the private address, and an area derived from it, are kept', async () => {
    await db.doc('jobs/k4').set({ customerId: 'c', status: 'requested', ...OLD });
    await db.doc('jobs/k4/private/location').set(NEW);
    await runAll(10);
    assert.deepEqual(await get('jobs/k4/private/location'), NEW); // byte-for-byte, no marker fields
    const job = await get('jobs/k4');
    assert.equal(job.customerAddress, undefined);
    assert.equal(job.areaLabel, 'Ikeja, Lagos'); // from the kept (newer) address
    assert.equal(job.areaLat, 6.6);
  });

  test('repeated runs after the fix keep the newer address', async () => {
    await db.doc('jobs/k5').set({ customerId: 'c', status: 'requested', ...OLD });
    await db.doc('jobs/k5/private/location').set(NEW);
    for (let i = 0; i < 3; i++) await runAll(1);
    assert.equal((await get('jobs/k5/private/location')).customerAddress, NEW.customerAddress);
  });

  test('concurrent customer update during the migration: the newer address always wins (20 races)', async () => {
    for (let i = 0; i < 20; i++) {
      const id = `race${pad(i)}`;
      await db.doc(`jobs/${id}`).set({ customerId: 'c', status: 'requested', ...OLD });
    }
    // Every job: migration and a "customer" private write race each other.
    await Promise.all(Array.from({ length: 20 }, async (_, i) => {
      const id = `race${pad(i)}`;
      await Promise.all([
        fns._protectJobLocation(db.doc(`jobs/${id}`)),
        db.doc(`jobs/${id}/private/location`).set(NEW, { merge: true }),
      ]);
    }));
    for (let i = 0; i < 20; i++) {
      const id = `race${pad(i)}`;
      assert.equal((await get(`jobs/${id}/private/location`)).customerAddress, NEW.customerAddress, id);
      assert.equal((await get(`jobs/${id}`)).customerAddress, undefined, id);
    }
  });

  test('concurrent migration runs (two operators) move each job once and keep a consistent copy', async () => {
    await seedLegacy(12);
    const [a, b] = await Promise.all([runAll(4), runAll(4)]);
    assert.equal(a.moved + b.moved, 12);
    for (let i = 0; i < 12; i++) {
      assert.equal((await get(`jobs/j${pad(i)}/private/location`)).customerAddress, `${i} Home Street, Ikeja, Lagos`);
    }
  });
});
