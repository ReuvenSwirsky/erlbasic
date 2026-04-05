$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$rebar3 = "$env:USERPROFILE\rebar3"
if (-not (Test-Path $rebar3)) {
    throw "rebar3 not found at $rebar3"
}

Write-Host "Compiling project for text-life benchmark..." -ForegroundColor Yellow
escript $rebar3 compile
if ($LASTEXITCODE -ne 0) {
    throw "Build failed with exit code $LASTEXITCODE"
}

Write-Host "Running asciilife 100-generation benchmark..." -ForegroundColor Yellow
escript perf_tests/textlife_100gen_benchmark.escript $PSScriptRoot
if ($LASTEXITCODE -ne 0) {
    throw "Benchmark failed with exit code $LASTEXITCODE"
}