<#
.SYNOPSIS
  Runs the bounded LIVE RumptyCloud staging tests (real bucket, synthetic images).

.DESCRIPTION
  Uses its own temporary emulators (do not run the normal emulators at the
  same time). Limits per run: <= 30 objects, <= 25 MB; every object it creates
  is deleted and checked by key. Evidence files (no credentials, no links) are
  written to a folder under %TEMP%.

    powershell -ExecutionPolicy Bypass -File tool\run_rumpty_live_tests.ps1
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$secret = Join-Path $root 'functions\.secret.local'
if (-not (Test-Path $secret)) { Write-Host 'Run tool\set_rumpty_credentials.ps1 first.' -ForegroundColor Red; exit 1 }

Write-Host ''
Write-Host 'Before a LIVE run, open the RumptyCloud dashboard and check:' -ForegroundColor Cyan
Write-Host '  1. Bucket handytrust-staging-media (assets-handytrust-01a0f99e-5d6ffa) is READY and PRIVATE'
Write-Host '  2. Billing: prepaid balance is $5 or less'
Write-Host '  3. Billing: automatic top-up is OFF'
Write-Host '  4. Note the current balance (check it again after the run)'
if ((Read-Host 'Bucket READY and PRIVATE? (yes/no)') -ne 'yes') { Write-Host 'Stopped.'; exit 1 }
if ((Read-Host 'Balance is $5 or less? (yes/no)') -ne 'yes') { Write-Host 'Stopped: lower the balance first.'; exit 1 }
if ((Read-Host 'Automatic top-up is OFF? (yes/no)') -ne 'yes') { Write-Host 'Stopped: turn auto top-up off first.'; exit 1 }

$report = Join-Path $env:TEMP ('rumpty-live-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $report | Out-Null
$env:RUMPTY_LIVE = '1'
$env:RUMPTY_LIVE_OWNER_CONFIRMED = 'balance-checked-auto-topup-off'
$env:RUMPTY_LIVE_REPORT_DIR = $report
$cmd = 'cd functions && node --test test/media_live.test.js && cd .. && flutter test test/media_live_app_test.dart && node functions/tools/verify_keys_absent.js'
Push-Location $root
try {
  & firebase emulators:exec --only 'auth,firestore,functions' --project demo-handytrust-media $cmd
  $code = $LASTEXITCODE
} finally {
  Pop-Location
  Remove-Item Env:RUMPTY_LIVE, Env:RUMPTY_LIVE_OWNER_CONFIRMED, Env:RUMPTY_LIVE_REPORT_DIR -ErrorAction SilentlyContinue
}
Write-Host ''
Write-Host "Evidence: $report" -ForegroundColor Cyan
Write-Host 'Now check the balance in the dashboard again. If it dropped unexpectedly, stop live testing.'
exit $code
