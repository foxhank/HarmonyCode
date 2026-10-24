# Command-line build for HarmonyCode (uses the tools bundled with DevEco Studio).
#   .\build.ps1          build web bundles + HAP
#   .\build.ps1 -SkipWeb build HAP only
param([switch]$SkipWeb)
$deveco = if ($env:DEVECO_HOME) { $env:DEVECO_HOME } else { 'C:\Program Files\Huawei\DevEco Studio' }
$node = Join-Path $deveco 'tools\node\node.exe'
$env:DEVECO_SDK_HOME = Join-Path $deveco 'sdk'
$env:PATH = (Join-Path $deveco 'tools\node') + ';' + (Join-Path $deveco 'jbr\bin') + ';' + $env:PATH
Push-Location $PSScriptRoot
try {
  if (-not $SkipWeb) {
    Push-Location web
    if (-not (Test-Path node_modules)) { & (Join-Path $deveco 'tools\node\npm.cmd') install --no-audit --no-fund }
    & $node build.mjs
    Pop-Location
  }
  & $node (Join-Path $deveco 'tools\hvigor\bin\hvigorw.js') --mode module -p module=entry@default -p product=default assembleHap --no-daemon
  if ($LASTEXITCODE -ne 0) { throw "hvigor build failed ($LASTEXITCODE)" }
} finally {
  Pop-Location
}
