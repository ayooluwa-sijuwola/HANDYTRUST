<#
.SYNOPSIS
  Stores the RumptyCloud STAGING credentials for the LOCAL Firebase Functions emulator.

.DESCRIPTION
  Writes functions\.secret.local (git-ignored). You type the values here; they
  are read hidden and are never printed, logged or sent anywhere.

  Before asking for anything, Git must confirm the file is ignored and not
  tracked. After writing, the file is verified (exists, all four variable
  names have values, Git ignores it, Git does not track it). If any check
  fails, the file is removed and the script reports that nothing was saved.

  Run from the repository folder (Windows PowerShell 5.1 or PowerShell 7):
    powershell -ExecutionPolicy Bypass -File tool\set_rumpty_credentials.ps1
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$secretRelative = 'functions/.secret.local'
$secretFile = Join-Path $root 'functions\.secret.local'
$envFile = Join-Path $root 'functions\.env.local'
$requiredNames = @('RUMPTY_ACCESS_KEY_ID', 'RUMPTY_SECRET_ACCESS_KEY', 'RUMPTY_CLEANUP_ACCESS_KEY_ID', 'RUMPTY_CLEANUP_SECRET_ACCESS_KEY')

# Runs git in the repository root and returns its exit code and stdout lines.
# Windows PowerShell 5.1 turns anything a native program writes to stderr into
# a terminating error when $ErrorActionPreference is 'Stop' (even with
# 2>$null); that is what stopped the old untracked-file check. Git therefore
# runs with 'Continue' and the exit code decides:
#  - an exit code listed in -OkCodes is an expected answer; any stderr text is
#    shown as a warning, never hidden;
#  - any other exit code is a real Git error and is thrown with Git's message.
function Invoke-Git {
  param(
    [Parameter(Mandatory = $true)][string[]]$Arguments,
    [int[]]$OkCodes = @(0)
  )
  $previous = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $raw = @(& git -C $root @Arguments 2>&1)
    $code = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previous
  }
  $out = @()
  $err = @()
  foreach ($item in $raw) {
    if ($item -is [System.Management.Automation.ErrorRecord]) { $err += [string]$item.Exception.Message }
    else { $out += [string]$item }
  }
  $out = @($out | Where-Object { $_.Trim() })
  $err = @($err | Where-Object { $_.Trim() })
  if ($OkCodes -notcontains $code) {
    $detail = (@($err) + @($out)) -join ' | '
    if (-not $detail) { $detail = 'no message' }
    throw "git $($Arguments -join ' ') failed with exit code $code ($detail)."
  }
  foreach ($line in $err) { Write-Warning "git: $line" }
  return [pscustomobject]@{ ExitCode = $code; Output = $out }
}

# The script's parent folder must be the root of the Git repository, so the
# ignore/track checks apply to the file this script writes.
function Assert-GitRepository {
  $r = Invoke-Git @('rev-parse', '--show-toplevel')
  $top = [string](@($r.Output) | Select-Object -Last 1)
  if (-not $top) { throw 'git rev-parse did not report a repository root.' }
  $topPath = (Resolve-Path -LiteralPath $top.Trim()).Path.TrimEnd('\')
  $rootPath = (Resolve-Path -LiteralPath $root).Path.TrimEnd('\')
  if ($topPath -ne $rootPath) {
    throw "This script belongs to $rootPath but Git reports the repository root as $topPath."
  }
}

# git check-ignore: exit 0 = ignored, 1 = not ignored, anything else = error.
function Test-SecretFileIgnored {
  $r = Invoke-Git @('check-ignore', '-q', '--', $secretRelative) -OkCodes 0, 1
  return ($r.ExitCode -eq 0)
}

# git ls-files prints the path only when it is tracked. An untracked path is
# not an error (exit 0, no output), so any non-zero exit is a real Git error.
function Test-SecretFileTracked {
  $r = Invoke-Git @('ls-files', '--', $secretRelative)
  return (@($r.Output).Count -gt 0)
}

# Names (never values) of the variables that have a non-empty value. Splits
# at the FIRST '=' so values containing '=' (base64) are handled.
function Get-CredentialNames([string]$path) {
  $names = @()
  foreach ($line in [IO.File]::ReadAllLines($path)) {
    $t = $line.Trim()
    if (-not $t -or $t.StartsWith('#')) { continue }
    $i = $t.IndexOf('=')
    if ($i -lt 1) { continue }
    if ($t.Length -gt ($i + 1)) { $names += $t.Substring(0, $i).Trim() }
  }
  return $names
}

function Read-Hidden([string]$prompt) {
  $secure = Read-Host -Prompt $prompt -AsSecureString
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try { return ([Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)).Trim() }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

function Assert-Value([string]$value, [string]$what) {
  if ([string]::IsNullOrWhiteSpace($value)) { throw "$what is empty. Nothing was written." }
  # Secret keys may legitimately contain = + / (base64); only spaces and
  # quotes would break the file.
  if ($value -match "[\s`"']") { throw "$what contains a space or a quote. Copy only the value. Nothing was written." }
  if ($value.Length -lt 4) { throw "$what looks too short. Nothing was written." }
}

function Invoke-Main {
  # Before asking for anything: Git must protect the file.
  if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'Git is not available in this PowerShell window (needed to confirm the file is git-ignored). Open the VS Code terminal and run again. Nothing was written.'
  }
  try {
    Assert-GitRepository
    $tracked = Test-SecretFileTracked
    $ignored = Test-SecretFileIgnored
  } catch {
    throw ('Git check failed: ' + $_.Exception.Message + ' Nothing was written.')
  }
  if ($tracked) { throw "$secretRelative is TRACKED by Git. Remove it from Git (git rm --cached) before storing credentials. Nothing was written." }
  if (-not $ignored) { throw "$secretRelative is NOT git-ignored (.gitignore must contain the line '$secretRelative'). Nothing was written." }

  Write-Host ''
  Write-Host 'RumptyCloud STAGING credentials (bucket assets-handytrust-01a0f99e-5d6ffa)' -ForegroundColor Cyan
  Write-Host 'Git check passed: the credential file is ignored and not tracked.'
  Write-Host 'Typing is hidden. Values go only to functions\.secret.local.'
  Write-Host ''
  Write-Host 'KEY 1 - app key. Required permissions: READ + WRITE.'
  $id1 = Read-Hidden '  Access key ID'
  $sk1 = Read-Hidden '  Secret access key'
  Assert-Value $id1 'Key 1 access key ID'
  Assert-Value $sk1 'Key 1 secret access key'

  Write-Host ''
  $answer = Read-Host 'Do you have a SECOND key for clean-up with DELETE permission? (y/n)'
  if ($answer -match '^[yY]') {
    Write-Host 'KEY 2 - clean-up key. Required permission: DELETE (LIST optional).'
    $id2 = Read-Hidden '  Access key ID'
    $sk2 = Read-Hidden '  Secret access key'
    Assert-Value $id2 'Key 2 access key ID'
    Assert-Value $sk2 'Key 2 secret access key'
    if ($id2 -eq $id1) { throw 'Key 2 is the same key as Key 1. Run again and answer "n" to use single-key mode. Nothing was written.' }
    $single = $false
  } else {
    Write-Host ''
    Write-Host 'Single-key mode: Key 1 must have READ + WRITE + DELETE.' -ForegroundColor Yellow
    Write-Host 'Risk: one leaked key could read, overwrite and delete everything in the staging bucket.'
    Write-Host 'Safer: create a second key with only DELETE permission in the RumptyCloud dashboard.'
    $ok = Read-Host 'Type ACCEPT to use one key for this staging bucket'
    if ($ok -ne 'ACCEPT') { throw 'Not accepted. Nothing was written.' }
    $id2 = $id1; $sk2 = $sk1; $single = $true
  }

  $lines = @(
    '# RumptyCloud STAGING credentials - local Functions emulator only. Git-ignored. Never commit or share.',
    "RUMPTY_ACCESS_KEY_ID=$id1",
    "RUMPTY_SECRET_ACCESS_KEY=$sk1",
    "RUMPTY_CLEANUP_ACCESS_KEY_ID=$id2",
    "RUMPTY_CLEANUP_SECRET_ACCESS_KEY=$sk2"
  )
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  [IO.File]::WriteAllText($secretFile, (($lines -join "`n") + "`n"), $utf8)
  $id1 = $null; $sk1 = $null; $id2 = $null; $sk2 = $null; $lines = $null

  # After writing: verify everything, or remove the file and report failure.
  $problems = @()
  try {
    if (-not (Test-Path -LiteralPath $secretFile -PathType Leaf)) {
      $problems += 'the file does not exist after writing'
    } else {
      $present = @(Get-CredentialNames $secretFile)
      $missing = @($requiredNames | Where-Object { $present -notcontains $_ })
      if ($missing.Count -gt 0) { $problems += ('missing or empty: ' + ($missing -join ', ')) }
      if (-not (Test-SecretFileIgnored)) { $problems += 'Git does not ignore the file' }
      if (Test-SecretFileTracked) { $problems += 'Git tracks the file' }
    }
  } catch {
    $problems += ('a check could not run: ' + $_.Exception.Message)
  }
  if ($problems.Count -gt 0) {
    $removal = 'The credential file was removed.'
    if (Test-Path -LiteralPath $secretFile) {
      try { Remove-Item -LiteralPath $secretFile -Force }
      catch { $removal = "The credential file could NOT be removed - delete $secretFile yourself." }
    }
    throw ('Verification FAILED: ' + ($problems -join '; ') + ". $removal NOTHING WAS SAVED.")
  }

  # Record the single-key decision in the non-secret local config.
  try {
    $envLines = @()
    if (Test-Path -LiteralPath $envFile) { $envLines = @(Get-Content -LiteralPath $envFile | Where-Object { $_ -notmatch '^RUMPTY_SINGLE_KEY_ACCEPTED=' }) }
    if ($single) { $envLines += 'RUMPTY_SINGLE_KEY_ACCEPTED=true' }
    [IO.File]::WriteAllText($envFile, (($envLines -join "`n") + "`n"), $utf8)
  } catch {
    throw ('The credentials were saved and verified, but functions\.env.local could not be updated: ' + $_.Exception.Message)
  }

  Write-Host ''
  Write-Host 'Saved functions\.secret.local (values not shown).' -ForegroundColor Green
  Write-Host ('Full path: ' + (Resolve-Path -LiteralPath $secretFile).Path)
  Write-Host ('Computer: ' + $env:COMPUTERNAME + '   User: ' + $env:USERNAME)
  Write-Host ('Verified: ' + ($requiredNames -join ', ') + ' present; ignored by Git; not tracked by Git.')
  if ($single) { Write-Host 'Mode: single key (accepted).' } else { Write-Host 'Mode: two keys.' }
}

# Runs when executed (-File or &). Dot-sourcing only loads the functions.
if ($MyInvocation.InvocationName -ne '.') { Invoke-Main }
