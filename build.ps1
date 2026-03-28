$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$rebar3 = "$env:USERPROFILE\rebar3"
if (-not (Test-Path $rebar3)) {
    Write-Host "Downloading rebar3..."
    Invoke-WebRequest -Uri "https://github.com/erlang/rebar3/releases/latest/download/rebar3" -OutFile $rebar3
}

& escript $rebar3 compile
if ($LASTEXITCODE -ne 0) {
    throw "Build failed with exit code $LASTEXITCODE"
}

# Copy compiled beams and app file where the smoke test runner expects them
Copy-Item "$PSScriptRoot\_build\default\lib\erlbasic\ebin\*.beam" "$PSScriptRoot\ebin\" -Force
Copy-Item "$PSScriptRoot\_build\default\lib\erlbasic\ebin\erlbasic.app" "$PSScriptRoot\ebin\" -Force

Write-Host "Build succeeded."
