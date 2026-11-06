<#
.SYNOPSIS
  Runs HandyTrust in LOCAL EMULATOR MODE (debug build only).

.DESCRIPTION
  The app talks only to the local emulators (project demo-handytrust-media);
  the production Firebase configuration is left out of this build.
  Start the emulators first (tool\start_rumpty_emulators.ps1).

    Android emulator:  powershell -ExecutionPolicy Bypass -File tool\run_handytrust_emulator_app.ps1
    USB phone:         powershell -ExecutionPolicy Bypass -File tool\run_handytrust_emulator_app.ps1 -UsbPhone
    Pick a device:     ... -Device emulator-5554
#>
param([switch]$UsbPhone, [string]$Device = '')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

function Test-Port([int]$port) {
  try { $c = New-Object Net.Sockets.TcpClient; $c.Connect('127.0.0.1', $port); $c.Close(); return $true } catch { return $false }
}
$down = @(9099, 8090, 5001 | Where-Object { -not (Test-Port $_) })
if ($down.Count -gt 0) {
  Write-Host ('Emulators are not running (no answer on port ' + ($down -join ', ') + ').') -ForegroundColor Red
  Write-Host 'Start them in another window: powershell -ExecutionPolicy Bypass -File tool\start_rumpty_emulators.ps1'
  exit 1
}

$defines = @('--dart-define=HT_EMULATOR=true')
if ($UsbPhone) {
  $adb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
  foreach ($p in 9099, 8090, 5001, 9199) { & $adb reverse "tcp:$p" "tcp:$p" | Out-Null }
  Write-Host 'adb reverse set for ports 9099, 8090, 5001, 9199 (the phone reaches this PC over USB).'
  $defines += '--dart-define=HT_EMULATOR_HOST=127.0.0.1'
}
$flArgs = @('run') + $defines
if ($Device) { $flArgs += @('-d', $Device) }

$env:HT_EMULATOR = 'true'   # build without the production google-services config
Push-Location $root
try { & flutter @flArgs } finally { Pop-Location; Remove-Item Env:HT_EMULATOR -ErrorAction SilentlyContinue }
