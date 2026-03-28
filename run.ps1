$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

& "$PSScriptRoot\build.ps1"
if ($LASTEXITCODE -ne 0) {
    throw "Build step failed with exit code $LASTEXITCODE"
}

Write-Host "Starting erlbasic on port 5555..."
& erl -pa ebin -eval "application:start(erlbasic)."
exit $LASTEXITCODE
