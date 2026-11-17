# Idempotent Exact checkout + toolchain bootstrap for this plugin (Windows).
# Usage: exact-bootstrap.ps1 [-Check] [-Auto] [-TimeoutSeconds N]
# Env: EXACT, EXACT_PLUGIN_NO_AUTOUPDATE=1

[CmdletBinding()]
param(
  [switch]$Check,
  [switch]$Auto,
  [int]$TimeoutSeconds = 0
)

$ErrorActionPreference = 'Stop'
$LogPrefix = 'exact-plugin'
$LsRemoteTimeoutSecs = 5
if ($env:EXACT_PLUGIN_LS_REMOTE_TIMEOUT_SECS -match '^[0-9]+$') {
  $LsRemoteTimeoutSecs = [int]$env:EXACT_PLUGIN_LS_REMOTE_TIMEOUT_SECS
}

function Say([string]$Message) {
  if ($Auto) { Write-Host "$LogPrefix`: $Message" } else { Write-Host "$LogPrefix`: $Message" }
}
function Warn([string]$Message) { Write-Warning "$LogPrefix`: $Message" }
function Die([string]$Message) {
  Warn $Message
  if ($Auto) { exit 0 }
  exit 1
}

if ($Auto -and $env:EXACT_PLUGIN_NO_AUTOUPDATE -eq '1') { exit 0 }

# -Auto only acts inside an Exact app (app.contract or exact.mjs) or the Exact
# checkout itself (scripts/exact.mjs), searching up from the session directory.
function Test-ExactProject {
  $d = (Get-Location).ProviderPath
  while ($d) {
    if ((Test-Path -LiteralPath (Join-Path $d 'app.contract')) -or
        (Test-Path -LiteralPath (Join-Path $d 'exact.mjs')) -or
        (Test-Path -LiteralPath (Join-Path (Join-Path $d 'scripts') 'exact.mjs'))) { return $true }
    $parent = Split-Path -Parent $d
    if (-not $parent -or $parent -eq $d) { break }
    $d = $parent
  }
  return $false
}
if ($Auto -and -not (Test-ExactProject)) { exit 0 }

if ($TimeoutSeconds -gt 0 -and -not $env:EXACT_BOOTSTRAP_TIMED) {
  $env:EXACT_BOOTSTRAP_TIMED = '1'
  $argList = @()
  if ($Check) { $argList += '-Check' }
  if ($Auto) { $argList += '-Auto' }
  $job = Start-Job -ScriptBlock {
    param($Script, $Args)
    & $Script @Args
    exit $LASTEXITCODE
  } -ArgumentList $PSCommandPath, $argList
  if (-not (Wait-Job $job -Timeout $TimeoutSeconds)) {
    Stop-Job $job -Force
    Remove-Job $job -Force
    if ($Auto) { exit 0 }
    Die "timed out after ${TimeoutSeconds}s"
  }
  Receive-Job $job -ErrorAction SilentlyContinue | Out-Null
  Remove-Job $job -Force
  if ($Auto) { exit 0 }
  exit 0
}

$ExactDir = if ($env:EXACT) { $env:EXACT } else { Join-Path $HOME 'exact' }
$ExactRepoUrl = if ($env:EXACT_REPO_URL) { $env:EXACT_REPO_URL } else { 'https://github.com/expo/exact.git' }
$CheckStatus = 0

# SessionStart -Auto: probe upstream HEAD; exit silently unless it moved.
if ($Auto) {
  $gitMarker = Join-Path $ExactDir '.git'
  if (-not (Test-Path $gitMarker)) { exit 0 }
  $localHead = ''
  try {
    Push-Location $ExactDir
    $localHead = (git rev-parse HEAD 2>$null).Trim()
  } catch { }
  finally { Pop-Location }
  if (-not $localHead) { exit 0 }

  $remoteHead = ''
  $lsJob = Start-Job -ScriptBlock {
    param($Url)
    $env:GIT_TERMINAL_PROMPT = '0'
    git ls-remote $Url HEAD 2>$null
  } -ArgumentList $ExactRepoUrl
  if (-not (Wait-Job $lsJob -Timeout $LsRemoteTimeoutSecs)) {
    Stop-Job $lsJob -Force
    Remove-Job $lsJob -Force
    exit 0
  }
  $remoteOut = (Receive-Job $lsJob | Out-String).Trim()
  Remove-Job $lsJob -Force
  if ($remoteOut -match '^([0-9a-f]{7,40})\b') {
    $remoteHead = $Matches[1]
  }
  if (-not $remoteHead) { exit 0 }
  if ($remoteHead -eq $localHead) { exit 0 }
}

function Get-BunPin([string]$PackageJson) {
  if (-not (Test-Path $PackageJson)) { return $null }
  $raw = Get-Content -Raw $PackageJson
  if ($raw -match '"packageManager"\s*:\s*"bun@([^"]+)"') { return $Matches[1] }
  return $null
}

function Get-BunVersion {
  if (Get-Command bun -ErrorAction SilentlyContinue) {
    return (bun --version 2>$null | Select-Object -First 1)
  }
  return $null
}

function Ensure-Path {
  $bunBin = Join-Path $HOME '.bun\bin'
  $cargoBin = Join-Path $HOME '.cargo\bin'
  if (Test-Path $bunBin) { $env:Path = "$bunBin;$env:Path" }
  if (Test-Path $cargoBin) { $env:Path = "$cargoBin;$env:Path" }
}

Ensure-Path

function Install-Rustup {
  Say 'installing rustup'
  $tmp = Join-Path $env:TEMP 'rustup-init.exe'
  Invoke-WebRequest -Uri 'https://win.rustup.rs' -OutFile $tmp
  & $tmp -y --no-modify-path
  Ensure-Path
  if (-not (Get-Command rustup -ErrorAction SilentlyContinue)) {
    Die 'rustup install finished but rustup is not on PATH'
  }
}

function Install-Bun([string]$Pin) {
  if ($Pin) {
    Say "installing Bun $Pin"
    iex "& {$(irm https://bun.com/install.ps1)} -Version $Pin"
  } else {
    Say 'installing Bun (latest; Exact package.json not readable yet)'
    iex "& {$(irm https://bun.com/install.ps1)}"
  }
  Ensure-Path
  if (-not (Get-Command bun -ErrorAction SilentlyContinue)) {
    Die 'Bun install finished but bun is not on PATH'
  }
}

function Report-PlatformSdks {
  Say 'Xcode: n/a on Windows (macOS/iOS hosts need a Mac)'
  $sdk = $env:ANDROID_HOME
  if (-not $sdk) { $sdk = $env:ANDROID_SDK_ROOT }
  if ($sdk -and (Test-Path $sdk)) {
    Say "Android SDK: present ($sdk)"
  } else {
    Say 'Android SDK: not found (needed for Android; install the SDK yourself)'
  }
}

function Ensure-Checkout {
  $gitMarker = Join-Path $ExactDir '.git'
  if (-not (Test-Path $gitMarker)) {
    if ($Check) {
      Say "checkout: missing at $ExactDir"
      $script:CheckStatus = 1
      return $false
    }
    Say "cloning $ExactRepoUrl -> $ExactDir"
    $parent = Split-Path -Parent $ExactDir
    if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
    git clone $ExactRepoUrl $ExactDir
    if ($LASTEXITCODE -ne 0) { Die 'git clone failed' }
  }
  $exactMjs = Join-Path $ExactDir 'scripts\exact.mjs'
  if (-not (Test-Path $exactMjs)) {
    Say "checkout: $ExactDir lacks scripts/exact.mjs"
    $script:CheckStatus = 1
    if ($Check) { return $false }
    Die "not an Exact checkout: $ExactDir"
  }
  return $true
}

function Update-Checkout {
  Push-Location $ExactDir
  try {
    $dirty = git status --porcelain 2>$null
    if ($dirty) {
      Warn 'checkout has local changes; leaving HEAD alone (will not discard)'
      return
    }
    if ($Check) {
      git fetch --quiet origin 2>$null
      if ($LASTEXITCODE -ne 0) {
        Say 'checkout: could not fetch (network or no upstream)'
        $script:CheckStatus = 1
      } else {
        Say 'checkout: fetch ok'
      }
      return
    }
    Say 'fetching Exact'
    git fetch --quiet origin
    if ($LASTEXITCODE -ne 0) {
      Warn 'git fetch failed; continuing on current commit'
      return
    }
    git pull --ff-only --quiet
    if ($LASTEXITCODE -ne 0) {
      Warn 'pull --ff-only failed; continuing on current commit'
    }
  } finally {
    Pop-Location
  }
}

function Get-StampPath {
  Push-Location $ExactDir
  try {
    $gitDir = (git rev-parse --git-dir).Trim()
    if (-not [System.IO.Path]::IsPathRooted($gitDir)) {
      $gitDir = Join-Path $ExactDir $gitDir
    }
    return (Join-Path $gitDir 'exact-plugin-setup-stamp')
  } finally {
    Pop-Location
  }
}

function Invoke-SetupIfNeeded {
  Ensure-Path
  if (-not (Get-Command bun -ErrorAction SilentlyContinue)) { Die 'bun is required to run Exact setup' }
  if (-not (Get-Command rustup -ErrorAction SilentlyContinue)) { Die 'rustup is required to run Exact setup' }

  Push-Location $ExactDir
  try {
    $head = (git rev-parse HEAD).Trim()
    $stamp = Get-StampPath
    $last = if (Test-Path $stamp) { (Get-Content -Raw $stamp).Trim() } else { '' }

    if ($Check) {
      Say 'running: bun scripts/exact.mjs setup --check'
      bun scripts/exact.mjs setup --check
      if ($LASTEXITCODE -ne 0) {
        Say 'setup --check: reported missing or differing tools (see above)'
        $script:CheckStatus = 1
      } else {
        Say 'setup --check: ok'
      }
      if ($last -eq $head) {
        Say "setup stamp: current ($head)"
      } else {
        Say "setup stamp: stale or missing (last=$(if ($last) { $last } else { 'none' }) head=$head)"
      }
      return
    }

    if ($last -eq $head) {
      Say 'setup: skipped (HEAD unchanged since last successful setup)'
      return
    }

    Say 'running: bun scripts/exact.mjs setup'
    bun scripts/exact.mjs setup
    if ($LASTEXITCODE -ne 0) { Die 'bun scripts/exact.mjs setup failed' }
    Set-Content -Path $stamp -Value $head -NoNewline
    Say "setup: ok; stamped $head"
  } finally {
    Pop-Location
  }
}

# --- main ---
$null = Ensure-Checkout
$bunPin = Get-BunPin (Join-Path $ExactDir 'package.json')
$will = @()
$needRustup = -not (Get-Command rustup -ErrorAction SilentlyContinue)
$haveBun = Get-BunVersion
$needBun = (-not $haveBun) -or ($bunPin -and $haveBun -ne $bunPin)

if ($needRustup) { $will += 'rustup (https://win.rustup.rs)' }
if ($needBun) {
  if ($bunPin) { $will += "Bun $bunPin (https://bun.com/install.ps1)" }
  else { $will += 'Bun latest (https://bun.com/install.ps1)' }
}

if ($will.Count -gt 0) {
  if ($Check) {
    Say 'would install:'
    foreach ($item in $will) { Say "  - $item" }
    $CheckStatus = 1
  } else {
    Say 'will install:'
    foreach ($item in $will) { Say "  - $item" }
    if ($needRustup) { Install-Rustup }
    if (-not $bunPin) {
      $bunPin = Get-BunPin (Join-Path $ExactDir 'package.json')
    }
    if ($needBun) { Install-Bun $bunPin }
  }
} else {
  Say "prerequisites: rustup and Bun $haveBun present"
}

if (Test-Path (Join-Path $ExactDir '.git')) {
  Update-Checkout
  $bunPin = Get-BunPin (Join-Path $ExactDir 'package.json')
  $localVer = Get-BunVersion
  if (-not $Check -and $bunPin -and $localVer -and $localVer -ne $bunPin) {
    Say "Bun pin is now $bunPin (have $localVer); upgrading"
    Install-Bun $bunPin
  } elseif ($Check -and $bunPin -and $localVer -and $localVer -ne $bunPin) {
    Say "Bun pin mismatch: have $localVer, Exact wants $bunPin"
    $CheckStatus = 1
  }
  if (Test-Path (Join-Path $ExactDir 'scripts\exact.mjs')) {
    Invoke-SetupIfNeeded
  }
}

Report-PlatformSdks
if (Test-Path (Join-Path $ExactDir '.git')) {
  Push-Location $ExactDir
  try {
    $head = (git rev-parse HEAD).Trim()
    Say "checkout: $ExactDir"
    Say "HEAD: $head"
  } finally {
    Pop-Location
  }
}

if ($Check) {
  if ($CheckStatus -ne 0) {
    Say 'check: FAILED'
    if ($Auto) { exit 0 }
    exit 1
  }
  Say 'check: OK'
  exit 0
}

exit 0
