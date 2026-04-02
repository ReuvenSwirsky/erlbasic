$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

& "$PSScriptRoot\build.ps1"
if ($LASTEXITCODE -ne 0) {
    throw "Build step failed with exit code $LASTEXITCODE"
}

# Determine which config file to use
$configFile = "sys.config"
if (-not (Test-Path $configFile)) {
    Write-Host "No sys.config found, running with defaults" -ForegroundColor Yellow
    $configArg = @()
} else {
    # Remove .config extension if present for -config argument
    $configName = [System.IO.Path]::GetFileNameWithoutExtension($configFile)
    $configArg = @('-config', $configName)
    Write-Host "Loading configuration from $configFile" -ForegroundColor Cyan
}

Write-Host "Starting erlbasic..."

# Build the -pa arguments for all dependencies
$paArgs = @('-pa', '_build/default/lib/erlbasic/ebin')
Get-ChildItem "_build\default\lib" -Directory | ForEach-Object {
    $ebinPath = Join-Path $_.FullName "ebin"
    if (Test-Path $ebinPath) {
        $paArgs += '-pa'
        $paArgs += $ebinPath
    }
}

# Combine all arguments
$erlArgs = $paArgs + $configArg + @('-eval', 'application:ensure_all_started(erlbasic), timer:sleep(infinity)')

& erl @erlArgs
exit $LASTEXITCODE
