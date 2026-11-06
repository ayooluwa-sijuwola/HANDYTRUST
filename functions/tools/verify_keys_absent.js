// Confirms that every object the app-side live test created is gone from the
// staging bucket (HEAD with the app key's read permission). Reads the object
// keys from the evidence files in RUMPTY_LIVE_REPORT_DIR. Prints keys and
// results only — never credentials or links.
'use strict';
const fs = require('fs');
const path = require('path');

function readEnvFile(file) {
  const out = {};
  if (!fs.existsSync(file)) return out;
  for (const raw of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    const i = line.indexOf('=');
    if (i > 0) out[line.slice(0, i).trim()] = line.slice(i + 1).trim().replace(/^(['"])(.*)\1$/, '$2');
  }
  return out;
}

(async () => {
  const fnDir = path.resolve(__dirname, '..');
  Object.assign(process.env, readEnvFile(path.join(fnDir, '.env.local')), readEnvFile(path.join(fnDir, '.secret.local')));
  process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-handytrust-media';
  const media = require('../media.js');
  const cfg = media._config();
  if (cfg.problems.length) throw new Error(`configuration incomplete: ${cfg.problems.join(',')}`);
  const dir = process.env.RUMPTY_LIVE_REPORT_DIR;
  if (!dir) throw new Error('RUMPTY_LIVE_REPORT_DIR not set');
  const keys = [];
  for (const f of fs.readdirSync(dir).filter((n) => /^rumpty-live-app-.*\.json$/.test(n))) {
    for (const v of Object.values(JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8')))) if (v && v.objectKey) keys.push(v.objectKey);
  }
  if (!keys.length) throw new Error('no app-side evidence found');
  const store = media._rumptyStore(cfg);
  let present = 0;
  for (const key of keys) {
    const h = await store.head(key);
    if (h.exists) present++;
    console.log(`${h.exists ? 'PRESENT' : 'absent '}  ${key}`);
  }
  fs.writeFileSync(path.join(dir, 'rumpty-live-app-keys-check.json'), JSON.stringify({ checked: keys.length, present }, null, 2));
  console.log(`checked ${keys.length} app-created keys: ${present} present`);
  process.exit(present ? 1 : 0);
})().catch((e) => {
  console.error(`key check failed: ${e.name || 'Error'}`);
  process.exit(1);
});
