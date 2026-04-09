$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

rebar3 compile
if ($LASTEXITCODE -ne 0) {
    throw "Build failed with exit code $LASTEXITCODE"
}

Write-Host "Build succeeded."
