<#
.SYNOPSIS
  Starts the LOCAL Firebase emulators for the RumptyCloud staging media test.

.DESCRIPTION
  Project demo-handytrust-media: a "demo-" project can never reach real Firebase.
  Auth 9099 · Firestore 8090 · Functions 5001 · Storage 9199.
  The emulated Functions use your RumptyCloud staging key(s) from
  functions\.secret.local to store files in the real staging bucket.
  Emulator data is saved between runs in %USERPROFILE%\handytrust-emulator-data.

    powershell -ExecutionPolicy Bypass -File tool\start_rumpty_emulators.ps1
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$secret = Join-Path $root 'functions\.secret.local'
$need = @('RUMPTY_ACCESS_KEY_ID', 'RUMPTY_SECRET_ACCESS_KEY', 'RUMPTY_CLEANUP_ACCESS_KEY_ID', 'RUMPTY_CLEANUP_SECRET_ACCESS_KEY')

if (-not (Test-Path $secret)) {
  Write-Host 'RumptyCloud credentials are not set up yet. Run this first:' -ForegroundColor Red
  Write-Host '  powershell -ExecutionPolicy Bypass -File tool\set_rumpty_credentials.ps1'
  exit 1
}
# Check the variable NAMES only (values are never read into this window).
$present = @(Get-Content $secret | Where-Object { $_ -match '^[A-Z_]+=\S' } | ForEach-Object { ($_ -split '=', 2)[0] })
$missing = @($need | Where-Object { $present -notcontains $_ })
if ($missing.Count -gt 0) {
  Write-Host ('functions\.secret.local is missing: ' + ($missing -join ', ')) -ForegroundColor Red
  Write-Host 'Run tool\set_rumpty_credentials.ps1 again.'
  exit 1
}

$data = Join-Path $env:USERPROFILE 'handytrust-emulator-data'
$fbArgs = @('emulators:start', '--only', 'auth,firestore,functions,storage', '--project', 'demo-handytrust-media', '--export-on-exit', $data)
if (Test-Path (Join-Path $data 'firebase-export-metadata.json')) { $fbArgs += @('--import', $data) }

Write-Host 'Starting emulators for demo-handytrust-media (never a real Firebase project)...' -ForegroundColor Cyan
Write-Host 'Keep this window open. Ready when you see "All emulators ready". Ctrl+C stops them (data is saved).'
Push-Location $root
try { & firebase @fbArgs } finally { Pop-Location }
