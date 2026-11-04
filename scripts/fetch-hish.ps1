# Downloads the hiSH release pinned in third_party/hish/hish.lock.json and copies the QEMU
# libraries, kernel and Alpine image into the hish module. Skips work when already up to date.
#   .\scripts\fetch-hish.ps1          fetch if needed
#   .\scripts\fetch-hish.ps1 -Force   fetch and copy again
param([switch]$Force)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = Split-Path $PSScriptRoot -Parent
$lock = Get-Content (Join-Path $root 'third_party\hish\hish.lock.json') -Raw | ConvertFrom-Json
$cacheDir = Join-Path $root 'third_party\hish\cache'
$libsDir = Join-Path $root 'hish\libs'
$rawDir = Join-Path $root 'hish\src\main\resources\rawfile\hish'
$stamp = Join-Path $libsDir '.hish-release'

function Test-UpToDate {
  if (-not (Test-Path $stamp)) { return $false }
  if ((Get-Content $stamp -Raw).Trim() -ne $lock.release) { return $false }
  foreach ($abi in $lock.abis) {
    foreach ($lib in $lock.libs) {
      if (-not (Test-Path (Join-Path $libsDir "$abi\$lib"))) { return $false }
    }
  }
  foreach ($p in $lock.rawfiles.PSObject.Properties) {
    if (-not (Test-Path (Join-Path $rawDir $p.Value))) { return $false }
  }
  return $true
}

function Get-Sha256([string]$path) {
  return (Get-FileHash -Algorithm SHA256 -Path $path).Hash.ToLowerInvariant()
}

function Save-Entry($archive, [string]$entryName, [string]$dest) {
  $entry = $archive.GetEntry($entryName)
  if ($null -eq $entry) { throw "hiSH release is missing $entryName" }
  New-Item -ItemType Directory -Force (Split-Path $dest -Parent) | Out-Null
  $in = $entry.Open()
  $out = [System.IO.File]::Create($dest)
  try { $in.CopyTo($out) } finally { $out.Dispose(); $in.Dispose() }
}

if (-not $Force -and (Test-UpToDate)) {
  Write-Host "hiSH runtime $($lock.release) is up to date."
  return
}

New-Item -ItemType Directory -Force $cacheDir | Out-Null
$zip = Join-Path $cacheDir "$($lock.release).zip"
if (-not (Test-Path $zip) -or (Get-Sha256 $zip) -ne $lock.sha256) {
  Write-Host "Downloading hiSH $($lock.release)..."
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $tmp = "$zip.part"
  Invoke-WebRequest -Uri $lock.url -OutFile $tmp -UseBasicParsing
  $actual = Get-Sha256 $tmp
  if ($actual -ne $lock.sha256) {
    Remove-Item $tmp -Force
    throw "hiSH download checksum mismatch: expected $($lock.sha256), got $actual"
  }
  Move-Item -Force $tmp $zip
}

Write-Host "Unpacking hiSH runtime..."
$outer = [System.IO.Compression.ZipFile]::OpenRead($zip)
try {
  $hapEntry = $outer.Entries | Where-Object { $_.FullName -like '*.hap' } | Select-Object -First 1
  if ($null -eq $hapEntry) { throw 'hiSH release zip contains no .hap' }
  $hapStream = New-Object System.IO.MemoryStream
  $s = $hapEntry.Open()
  try { $s.CopyTo($hapStream) } finally { $s.Dispose() }
  $hapStream.Position = 0
  $hap = New-Object System.IO.Compression.ZipArchive($hapStream, [System.IO.Compression.ZipArchiveMode]::Read)
  try {
    foreach ($abi in $lock.abis) {
      foreach ($lib in $lock.libs) {
        Save-Entry $hap "libs/$abi/$lib" (Join-Path $libsDir "$abi\$lib")
      }
    }
    foreach ($p in $lock.rawfiles.PSObject.Properties) {
      Save-Entry $hap $p.Name (Join-Path $rawDir $p.Value)
    }
  } finally { $hap.Dispose(); $hapStream.Dispose() }
} finally { $outer.Dispose() }

Set-Content -Path $stamp -Value $lock.release -NoNewline
Write-Host "hiSH runtime $($lock.release) ready."
