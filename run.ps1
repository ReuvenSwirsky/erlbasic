$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

& "$PSScriptRoot\build.ps1"
if ($LASTEXITCODE -ne 0) {
    throw "Build step failed with exit code $LASTEXITCODE"
}

Write-Host "Starting erlbasic on port 5555 and web server on port 8081..."

# Build the -pa arguments for all dependencies
$paArgs = @('-pa', '_build/default/lib/erlbasic/ebin')
Get-ChildItem "_build\default\lib" -Directory | ForEach-Object {
    $ebinPath = Join-Path $_.FullName "ebin"
    if (Test-Path $ebinPath) {
        $paArgs += '-pa'
        $paArgs += $ebinPath
    }
}

& erl @paArgs -eval "application:ensure_all_started(erlbasic), timer:sleep(infinity)"
exit $LASTEXITCODE
