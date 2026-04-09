$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "ERLBASIC TEST RUNNER" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Building and running EUnit tests..." -ForegroundColor Yellow
rebar3 eunit

if ($LASTEXITCODE -ne 0) {
    throw "EUnit tests failed"
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "RUNNING SMOKE TESTS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Push-Location smoke_tests
try {
    escript smoke_runner.escript .
    if ($LASTEXITCODE -ne 0) {
        throw "Smoke tests failed"
    }
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "ALL TESTS PASSED!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
