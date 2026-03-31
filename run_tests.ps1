$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "ERLBASIC TEST RUNNER" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Compiling eunit test module..." -ForegroundColor Yellow
erl -noshell -pa _build/default/lib/erlbasic/ebin -pa _build/default/lib/cowboy/ebin -eval "Result = compile:file('eunit_tests/erlbasic_eunit_tests.erl', [{outdir, '_build/default/lib/erlbasic/ebin'}]), case Result of {ok,_} -> io:format('Compilation successful~n'); _ -> io:format('Compilation failed: ~p~n', [Result]), halt(1) end, init:stop()"

if ($LASTEXITCODE -ne 0) {
    throw "Test compilation failed"
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "RUNNING EUNIT TESTS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

erl -noshell -pa _build/default/lib/erlbasic/ebin -pa _build/default/lib/cowboy/ebin -eval "eunit:test(erlbasic_eunit_tests, [verbose]), init:stop()"

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
