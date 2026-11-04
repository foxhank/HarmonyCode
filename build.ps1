# Command-line build for HarmonyCode (uses the tools bundled with DevEco Studio).
#   .\build.ps1          build web bundles + HAP
#   .\build.ps1 -SkipWeb build HAP only
# The hiSH runtime (QEMU, kernel, Alpine image) is fetched into the hish module on first build.
param([switch]$SkipWeb)
$deveco = if ($env:DEVECO_HOME) { $env:DEVECO_HOME } else { 'C:\Program Files\Huawei\DevEco Studio' }
$node = Join-Path $deveco 'tools\node\node.exe'
$ohpm = Join-Path $deveco 'tools\ohpm\bin\ohpm.bat'
$env:DEVECO_SDK_HOME = Join-Path $deveco 'sdk'
$env:PATH = (Join-Path $deveco 'tools\node') + ';' + (Join-Path $deveco 'jbr\bin') + ';' + $env:PATH
Push-Location $PSScriptRoot
try {
  & (Join-Path $PSScriptRoot 'scripts\fetch-hish.ps1')
  if (-not $?) { throw 'fetching the hiSH runtime failed' }
  if (-not $SkipWeb) {
    Push-Location web
    if (-not (Test-Path node_modules)) { & (Join-Path $deveco 'tools\node\npm.cmd') install --no-audit --no-fund }
    & $node build.mjs
    Pop-Location
  }
  & $ohpm install --all
  if ($LASTEXITCODE -ne 0) { throw "ohpm install failed ($LASTEXITCODE)" }
  & $node (Join-Path $deveco 'tools\hvigor\bin\hvigorw.js') --mode module -p module=entry@default -p product=default assembleHap --no-daemon
  if ($LASTEXITCODE -ne 0) { throw "hvigor build failed ($LASTEXITCODE)" }
} finally {
  Pop-Location
}
