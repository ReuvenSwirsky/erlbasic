$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

# ── Build ────────────────────────────────────────────────────────────────────
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "BUILD" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
& .\build.ps1
Write-Host ""

# ── EUnit tests ──────────────────────────────────────────────────────────────
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "EUNIT TESTS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

erl -noshell -pa _build/default/lib/erlbasic/ebin -pa _build/default/lib/cowboy/ebin `
    -eval "Result = compile:file('eunit_tests/erlbasic_eunit_tests.erl', [{outdir, '_build/default/lib/erlbasic/ebin'}]), case Result of {ok,_} -> ok; _ -> io:format('Compilation failed: ~p~n', [Result]), halt(1) end, init:stop()"
if ($LASTEXITCODE -ne 0) { throw "EUnit test compilation failed" }

erl -noshell -pa _build/default/lib/erlbasic/ebin -pa _build/default/lib/cowboy/ebin `
    -eval "eunit:test(erlbasic_eunit_tests, [verbose]), init:stop()"
if ($LASTEXITCODE -ne 0) { throw "EUnit tests failed" }
Write-Host ""

# ── Smoke tests ───────────────────────────────────────────────────────────────
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "SMOKE TESTS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Push-Location smoke_tests
try {
    escript smoke_runner.escript .
    if ($LASTEXITCODE -ne 0) { throw "Smoke tests failed" }
} finally {
    Pop-Location
}
Write-Host ""

# ── Pass/fail perf tests ──────────────────────────────────────────────────────
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "PERF TESTS (pass/fail)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

escript perf_tests/perf_runner.escript $PSScriptRoot
if ($LASTEXITCODE -ne 0) { throw "Performance tests failed" }
Write-Host ""

# ── Textlife benchmark (saves history) ────────────────────────────────────────
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "TEXTLIFE BENCHMARK (100 generations)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

escript perf_tests/textlife_100gen_benchmark.escript $PSScriptRoot
if ($LASTEXITCODE -ne 0) { throw "Textlife benchmark failed" }
Write-Host ""

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host "========================================" -ForegroundColor Green
Write-Host "ALL TESTS PASSED" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
