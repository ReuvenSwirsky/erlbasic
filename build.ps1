$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

New-Item -ItemType Directory -Force -Path "$PSScriptRoot\ebin" | Out-Null
Copy-Item "$PSScriptRoot\src\erlbasic.app.src" "$PSScriptRoot\ebin\erlbasic.app" -Force

$compileExpr = 'Files = filelib:wildcard("src/*.erl"), lists:foreach(fun(F) -> case compile:file(F, [report_errors, report_warnings, {outdir,"ebin"}]) of {ok,_} -> ok; error -> halt(1) end end, Files), halt(0).'

& erl -noshell -eval $compileExpr
if ($LASTEXITCODE -ne 0) {
    throw "Build failed with exit code $LASTEXITCODE"
}

Write-Host "Build succeeded."
