$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

Write-Host "Compiling project for perf tests..." -ForegroundColor Yellow
rebar3 compile
if ($LASTEXITCODE -ne 0) {
    throw "Build failed with exit code $LASTEXITCODE"
}

Write-Host "Running Life/AsciiLife perf tests..." -ForegroundColor Yellow
escript perf_tests/perf_runner.escript $PSScriptRoot
if ($LASTEXITCODE -ne 0) {
    throw "Performance tests failed with exit code $LASTEXITCODE"
}

Write-Host "Running websocket graphics benchmark..." -ForegroundColor Yellow
escript perf_tests/ws_graphics_benchmark.escript $PSScriptRoot
if ($LASTEXITCODE -ne 0) {
    throw "Websocket graphics benchmark failed with exit code $LASTEXITCODE"
}

Write-Host "Performance tests passed." -ForegroundColor Green
