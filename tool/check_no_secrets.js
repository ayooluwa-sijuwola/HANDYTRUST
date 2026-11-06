#!/usr/bin/env node
// Pre-commit secret scan for RumptyCloud credentials
// (design/RUMPTYCLOUD_STAGING_INTEGRATION_PHASE2_PLAN.md §11).
//
//   node tool/check_no_secrets.js          scan the staged diff (git diff --cached)
//   node tool/check_no_secrets.js --stdin  scan diff text from stdin (tests)
//
// Install as a local hook (owner's choice):  .git/hooks/pre-commit →
//   node tool/check_no_secrets.js || exit 1
//
// Reports only WHICH rule matched and the file name — never the matched text.
// Optional: put the first characters of your real key IDs (one per line) in
// tool/.secret-prefix.local (git-ignored) to block those exact prefixes too.
'use strict';

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const RULES = [
  {
    name: 'RumptyCloud credential variable with a value',
    re: /\bRUMPTY_(?:CLEANUP_)?(?:ACCESS_KEY_ID|SECRET_ACCESS_KEY)\s*[=:]\s*['"]?[A-Za-z0-9/+=_-]{8,}/,
  },
  {
    name: 'secret-like 40-character key near the word "secret"',
    re: /secret[^\n]{0,40}?(?<![A-Za-z0-9/+])[A-Za-z0-9/+]{40}(?![A-Za-z0-9/+])/i,
  },
];
const FILE_RULES = [
  { name: 'credential file added', re: /(^|\/)\.secret\.local$|(^|\/)\.env\.local$|(^|\/)\.secret-prefix\.local$/ },
];

function loadPrefixes(root) {
  try {
    return fs.readFileSync(path.join(root, 'tool', '.secret-prefix.local'), 'utf8')
      .split(/\r?\n/).map((l) => l.trim()).filter((l) => l.length >= 4);
  } catch (_) {
    return [];
  }
}

// Returns [{ file, rule }] for added lines of a unified diff.
function scanDiff(diff, prefixes = []) {
  const hits = [];
  let file = '(unknown)';
  for (const line of diff.split(/\r?\n/)) {
    if (line.startsWith('+++ ')) {
      file = line.replace(/^\+\+\+ (b\/)?/, '');
      for (const r of FILE_RULES) if (r.re.test(file)) hits.push({ file, rule: r.name });
      continue;
    }
    if (!line.startsWith('+') || line.startsWith('+++')) continue;
    const text = line.slice(1);
    for (const r of RULES) if (r.re.test(text)) hits.push({ file, rule: r.name });
    for (const p of prefixes) if (text.includes(p)) hits.push({ file, rule: 'configured key-ID prefix' });
  }
  return hits;
}

function main() {
  const root = path.resolve(__dirname, '..');
  const diff = process.argv.includes('--stdin')
    ? fs.readFileSync(0, 'utf8')
    : execFileSync('git', ['diff', '--cached', '--unified=0', '--no-color'], { cwd: root, encoding: 'utf8', maxBuffer: 256 * 1024 * 1024 });
  const hits = scanDiff(diff, loadPrefixes(root));
  if (hits.length) {
    for (const h of hits) console.error(`BLOCKED: ${h.rule} in ${h.file}`);
    process.exit(1);
  }
  console.log('secret scan: clean');
}

if (require.main === module) main();
module.exports = { scanDiff };
