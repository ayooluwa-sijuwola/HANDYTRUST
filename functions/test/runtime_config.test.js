/**
 * Stage 7.2 (A) — Cloud Functions runtime is Node.js 22 everywhere it is
 * declared, and every locked dependency supports it. Node 20 was
 * decommissioned on Google Cloud on 2026-10-30 (Stage 7.1 report §8).
 */
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const semver = require('semver');

const root = path.resolve(__dirname, '../..');
const firebaseJson = JSON.parse(fs.readFileSync(path.join(root, 'firebase.json'), 'utf8'));
const pkg = require('../package.json');
const lock = require('../package-lock.json');

test('firebase.json, package.json engines and the lock file all declare Node 22', () => {
  const fnConfigs = [].concat(firebaseJson.functions || []);
  assert.ok(fnConfigs.length > 0);
  for (const f of fnConfigs) assert.equal(f.runtime, 'nodejs22');
  assert.equal(pkg.engines.node, '22');
  assert.equal(lock.packages[''].engines.node, '22');
});

test('no Node 20 declaration remains in runtime configuration', () => {
  const raw = fs.readFileSync(path.join(root, 'firebase.json'), 'utf8') + JSON.stringify(pkg.engines);
  assert.doesNotMatch(raw, /nodejs20|"node":\s*"20"/);
});

test('every locked dependency that declares engines.node accepts Node 22', () => {
  const target = '22.23.4';
  const incompatible = Object.entries(lock.packages)
    .filter(([k, v]) => k && v.engines?.node && !semver.satisfies(target, v.engines.node))
    .map(([k, v]) => `${k} (${v.engines.node})`);
  assert.deepEqual(incompatible, []);
});

test('the functions entry point loads on the running Node and exports only v2 endpoints', () => {
  process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-runtime-check';
  const fns = require('../index.js');
  const endpoints = Object.entries(fns).filter(([, v]) => v && v.__endpoint);
  assert.ok(endpoints.length >= 30);
  for (const [name, v] of endpoints) assert.equal(v.__endpoint.platform, 'gcfv2', name);
});
