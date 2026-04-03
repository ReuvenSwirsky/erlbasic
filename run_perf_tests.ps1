$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$rebar3 = "$env:USERPROFILE\rebar3"
if (-not (Test-Path $rebar3)) {
    throw "rebar3 not found at $rebar3"
}

Write-Host "Compiling project for perf tests..." -ForegroundColor Yellow
escript $rebar3 compile
if ($LASTEXITCODE -ne 0) {
    throw "Build failed with exit code $LASTEXITCODE"
}

Write-Host "Running Life/TextLife perf tests..." -ForegroundColor Yellow
escript perf_tests/perf_runner.escript $PSScriptRoot
if ($LASTEXITCODE -ne 0) {
    throw "Performance tests failed with exit code $LASTEXITCODE"
}

Write-Host "Performance tests passed." -ForegroundColor Green
