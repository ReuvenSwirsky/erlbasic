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

Write-Host "Build succeeded."
