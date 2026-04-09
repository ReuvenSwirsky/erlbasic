$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

# Determine which config file to use
$configFile = "sys.config"
if (-not (Test-Path $configFile)) {
    Write-Host "No sys.config found, running with defaults" -ForegroundColor Yellow
    Write-Host "Starting erlbasic..."
    rebar3 shell
} else {
    Write-Host "Loading configuration from $configFile" -ForegroundColor Cyan
    Write-Host "Starting erlbasic..."
    rebar3 shell --config $configFile
}
exit $LASTEXITCODE
