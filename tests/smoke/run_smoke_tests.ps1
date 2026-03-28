$ErrorActionPreference = "Stop"
Set-PSDebug -Off
Set-Location $PSScriptRoot

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$runnerPath = (Resolve-Path (Join-Path $PSScriptRoot "smoke_runner.escript")).Path

$compileExpr = 'Files = filelib:wildcard("src/*.erl"), lists:foreach(fun(F) -> case compile:file(F, [report_errors, report_warnings, {outdir,"ebin"}]) of {ok,_} -> ok; error -> halt(1) end end, Files), halt(0).'
Push-Location $repoRoot
& erl -noshell -eval $compileExpr
Pop-Location
if ($LASTEXITCODE -ne 0) {
    throw "Build failed with exit code $LASTEXITCODE"
}

$escriptPath = Join-Path ${env:ProgramFiles} "Erlang OTP\bin\escript.exe"
& $escriptPath $runnerPath $PSScriptRoot
if ($LASTEXITCODE -ne 0) {
    throw "Smoke tests failed with exit code $LASTEXITCODE"
}

Write-Host "Smoke tests passed."