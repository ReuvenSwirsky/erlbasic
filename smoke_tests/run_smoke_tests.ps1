$ErrorActionPreference = "Stop"
Set-PSDebug -Off
Set-Location $PSScriptRoot

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$runnerPath = (Resolve-Path (Join-Path $PSScriptRoot "smoke_runner.escript")).Path

$rebar3 = "$env:USERPROFILE\rebar3"
Push-Location $repoRoot
& escript $rebar3 compile
Pop-Location
if ($LASTEXITCODE -ne 0) {
    throw "Build failed with exit code $LASTEXITCODE"
}

& escript $runnerPath $PSScriptRoot
if ($LASTEXITCODE -ne 0) {
    throw "Smoke tests failed with exit code $LASTEXITCODE"
}

Write-Host "Smoke tests passed."