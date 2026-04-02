#!/usr/bin/env pwsh
# Generate self-signed SSL certificates for local development
# These certificates work for localhost and local network IP addresses

param(
    [string]$HostIP = "",
    [int]$ValidDays = 365
)

Write-Host "Generating SSL certificates for local development..." -ForegroundColor Cyan

# Create ssl directory if it doesn't exist
$sslDir = "priv/ssl"
if (-not (Test-Path $sslDir)) {
    New-Item -ItemType Directory -Path $sslDir -Force | Out-Null
    Write-Host "Created directory: $sslDir" -ForegroundColor Green
}

# Get local IP addresses
$localIPs = @()
$networkInterfaces = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -ne "127.0.0.1" }
foreach ($interface in $networkInterfaces) {
    $localIPs += $interface.IPAddress
}

Write-Host "`nDetected local IP addresses:" -ForegroundColor Yellow
foreach ($ip in $localIPs) {
    Write-Host "  - $ip" -ForegroundColor White
}

# Build Subject Alternative Names (SAN)
$sanEntries = @("DNS:localhost", "DNS:*.localhost", "IP:127.0.0.1")

if ($HostIP -ne "") {
    $sanEntries += "IP:$HostIP"
    Write-Host "`nIncluding specified IP: $HostIP" -ForegroundColor Yellow
} else {
    # Add all detected local IPs
    foreach ($ip in $localIPs) {
        $sanEntries += "IP:$ip"
    }
}

$sanString = $sanEntries -join ","

# Create OpenSSL config file for SAN
$configFile = "$sslDir/openssl.cnf"
$configContent = @"
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = v3_req

[dn]
C = US
ST = Development
L = Local
O = ErlBASIC Development
CN = localhost

[v3_req]
subjectAltName = $sanString
"@

Set-Content -Path $configFile -Value $configContent
Write-Host "`nCreated OpenSSL config with SANs" -ForegroundColor Green

# Check if OpenSSL is available
$openssl = $null
try {
    $openssl = Get-Command openssl -ErrorAction Stop
} catch {
    Write-Host "`nERROR: OpenSSL not found in PATH" -ForegroundColor Red
    Write-Host "Please install OpenSSL:" -ForegroundColor Yellow
    Write-Host "  - Windows: choco install openssl" -ForegroundColor White
    Write-Host "  - Or download from: https://slproweb.com/products/Win32OpenSSL.html" -ForegroundColor White
    exit 1
}

Write-Host "`nUsing OpenSSL: $($openssl.Source)" -ForegroundColor Cyan

# Generate private key
Write-Host "`nGenerating private key..." -ForegroundColor Cyan
$keyFile = "$sslDir/key.pem"
& openssl genrsa -out $keyFile 2048 2>&1 | Out-Null

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to generate private key" -ForegroundColor Red
    exit 1
}
Write-Host "Created: $keyFile" -ForegroundColor Green

# Generate self-signed certificate
Write-Host "Generating self-signed certificate..." -ForegroundColor Cyan
$certFile = "$sslDir/cert.pem"
& openssl req -new -x509 -key $keyFile -out $certFile -days $ValidDays -config $configFile -extensions v3_req 2>&1 | Out-Null

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to generate certificate" -ForegroundColor Red
    exit 1
}
Write-Host "Created: $certFile" -ForegroundColor Green

# Display certificate info
Write-Host "`n=== Certificate Information ===" -ForegroundColor Cyan
& openssl x509 -in $certFile -noout -text | Select-String -Pattern "Subject:|Not Before|Not After|DNS:|IP Address:" | ForEach-Object {
    Write-Host $_.Line -ForegroundColor White
}

Write-Host "`n=== Setup Complete ===" -ForegroundColor Green
Write-Host "Certificates valid for $ValidDays days" -ForegroundColor White
Write-Host "`nTo enable HTTPS, update your sys.config:" -ForegroundColor Yellow
Write-Host @"
{erlbasic, [
    {http_port, 8081},
    {enable_https, true},
    {https_port, 8443},
    {certfile, "priv/ssl/cert.pem"},
    {keyfile, "priv/ssl/key.pem"}
]}
"@ -ForegroundColor White

Write-Host "`nThen rebuild and run:" -ForegroundColor Yellow
Write-Host "  pwsh build.ps1" -ForegroundColor White
Write-Host "  pwsh run.ps1" -ForegroundColor White

Write-Host "`nAccess your server at:" -ForegroundColor Yellow
Write-Host "  HTTP:  http://localhost:8081" -ForegroundColor White
Write-Host "  HTTPS: https://localhost:8443" -ForegroundColor White
foreach ($ip in $localIPs) {
    Write-Host "  HTTPS: https://$($ip):8443" -ForegroundColor White
}

Write-Host "`nNOTE: Your browser will show a security warning for self-signed certificates." -ForegroundColor Yellow
Write-Host "Click 'Advanced' -> 'Proceed to localhost (unsafe)' to continue." -ForegroundColor White
Write-Host "`nFor production, use certbot (see CERTBOT_DEPLOYMENT.md)" -ForegroundColor Cyan
