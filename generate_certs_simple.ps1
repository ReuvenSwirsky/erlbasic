#!/usr/bin/env pwsh
# Simple certificate generation for testing (Windows only)

Write-Host "Generating test certificates..." -ForegroundColor Cyan

# Create ssl directory
New-Item -ItemType Directory -Path "priv/ssl" -Force | Out-Null

# Create a self-signed certificate
$cert = New-SelfSignedCertificate `
    -Subject "CN=localhost" `
    -DnsName "localhost", "127.0.0.1" `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -KeyExportPolicy Exportable `
    -NotAfter (Get-Date).AddYears(1)

# Export to PFX
$pfxPassword = ConvertTo-SecureString -String "test123" -Force -AsPlainText
$pfxPath = "priv/ssl/cert.pfx"
Export-PfxCertificate -Cert $cert -FilePath $pfxPath -Password $pfxPassword | Out-Null

Write-Host "Created PFX certificate: $pfxPath" -ForegroundColor Green
Write-Host "Password: test123" -ForegroundColor Yellow

# Clean up from cert store
Remove-Item "Cert:\CurrentUser\My\$($cert.Thumbprint)"

Write-Host "`nTo use with Erlang/Cowboy, update sys.config:" -ForegroundColor Cyan
Write-Host '{certfile, "priv/ssl/cert.pfx"},' -ForegroundColor White
Write-Host '{keyfile, "test123"}' -ForegroundColor White
Write-Host "`nOr install OpenSSL to convert to PEM format:" -ForegroundColor Cyan
Write-Host "  choco install openssl" -ForegroundColor White
Write-Host "  openssl pkcs12 -in priv/ssl/cert.pfx -out priv/ssl/cert.pem -nodes -passin pass:test123" -ForegroundColor White
