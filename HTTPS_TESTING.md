# HTTPS Testing Guide

This guide explains how to test HTTPS on localhost and your local network.

## Quick Start for Local Development

### 1. Generate Self-Signed Certificates

```powershell
pwsh generate_certs.ps1
```

This will:
- Create `priv/ssl/cert.pem` and `priv/ssl/key.pem`
- Automatically detect your local IP addresses
- Generate certificates valid for localhost AND your local IPs
- Display certificate info and setup instructions

### 2. Enable HTTPS

Edit `sys.config` and set:
```erlang
{enable_https, true}
```

Or use the pre-configured HTTPS config:
```powershell
cp sys.config.https sys.config
```

### 3. Build and Run

```powershell
pwsh build.ps1
pwsh run.ps1
```

You should see:
```
erlbasic HTTP server listening on port 8081
erlbasic HTTPS server listening on port 8443
  Using cert: priv/ssl/cert.pem
  Using key:  priv/ssl/key.pem
```

## Testing on Localhost

### Web Browser
```
https://localhost:8443
```

You'll see a security warning because it's self-signed:
- **Chrome/Edge**: Click "Advanced" → "Proceed to localhost (unsafe)"
- **Firefox**: Click "Advanced" → "Accept the Risk and Continue"

### WebSocket Connection
Update the WebSocket URL in your JavaScript:
```javascript
const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
const ws = new WebSocket(`${protocol}//${window.location.host}/ws`);
```

### curl
```bash
# Accept self-signed cert
curl -k https://localhost:8443

# Show certificate details
curl -vk https://localhost:8443 2>&1 | grep -A 10 "Server certificate"
```

### PowerShell
```powershell
# Accept self-signed cert
Invoke-WebRequest -Uri https://localhost:8443 -SkipCertificateCheck
```

## Testing on Local Network

### Find Your IP Address

**PowerShell:**
```powershell
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -ne "127.0.0.1" }
```

**Output example:**
```
IPAddress         : 192.168.1.100
InterfaceAlias    : Ethernet
```

### Generate Certificates with Your IP

The `generate_certs.ps1` script automatically includes all detected local IPs. Or specify one explicitly:

```powershell
pwsh generate_certs.ps1 -HostIP 192.168.1.100
```

### Access from Other Devices

From another computer, phone, or tablet on the same network:

```
https://192.168.1.100:8443
```

You'll need to accept the security warning on each device.

### Testing from Mobile Device

1. Find your server's local IP (e.g., 192.168.1.100)
2. Connect phone/tablet to same WiFi network
3. Open browser and go to `https://192.168.1.100:8443`
4. Accept security warning

**iOS Safari**: Tap "Show Details" → "visit this website"
**Android Chrome**: Tap "Advanced" → "Proceed to 192.168.1.100 (unsafe)"

## Verifying Certificate Coverage

Check what domains/IPs your certificate covers:

```powershell
# Windows (requires OpenSSL)
openssl x509 -in priv/ssl/cert.pem -noout -text | Select-String -Pattern "DNS:|IP Address:"
```

You should see:
```
DNS:localhost, DNS:*.localhost, IP Address:127.0.0.1, IP Address:192.168.1.100
```

## Common Issues

### Certificate Not Valid for IP Address

**Problem**: Browser shows "NET::ERR_CERT_COMMON_NAME_INVALID"

**Solution**: Regenerate certificates with your IP included:
```powershell
pwsh generate_certs.ps1 -HostIP 192.168.1.100
pwsh build.ps1
pwsh run.ps1
```

### Port Already in Use

**Problem**: `eaddrinuse` error

**Solution**: Find and kill the process using the port:
```powershell
# Find process
Get-NetTCPConnection -LocalPort 8443 | Select-Object OwningProcess
# Kill it (use process ID from above)
Stop-Process -Id <PID> -Force
```

### Certificate Files Not Found

**Problem**: "Error: Certificate file not found"

**Solution**: 
```powershell
# Check if files exist
Test-Path priv/ssl/cert.pem
Test-Path priv/ssl/key.pem

# If missing, generate them
pwsh generate_certs.ps1
```

### Firewall Blocking Connections

**Problem**: Can't connect from other devices on local network

**Solution**: Allow port 8443 through Windows Firewall:
```powershell
New-NetFirewallRule -DisplayName "ErlBASIC HTTPS" -Direction Inbound -LocalPort 8443 -Protocol TCP -Action Allow
```

## Testing Commands Reference

### Check if HTTPS is Running
```powershell
# Check HTTP
Test-NetConnection -ComputerName localhost -Port 8081

# Check HTTPS
Test-NetConnection -ComputerName localhost -Port 8443
```

### View Certificate Details
```powershell
# Using OpenSSL
openssl x509 -in priv/ssl/cert.pem -noout -text

# Just expiry date
openssl x509 -in priv/ssl/cert.pem -noout -dates
```

### Test WebSocket over HTTPS
```javascript
// In browser console
const ws = new WebSocket('wss://localhost:8443/ws');
ws.onopen = () => console.log('Connected!');
ws.onmessage = (e) => console.log('Received:', e.data);
ws.onerror = (e) => console.error('Error:', e);
```

### Monitor Connections
```powershell
# Active connections to your server
Get-NetTCPConnection -LocalPort 8443 -State Established

# All listening ports
Get-NetTCPConnection -State Listen | Where-Object { $_.LocalPort -in @(8081, 8443) }
```

## Advanced: Trust Your Own CA

For a better development experience without browser warnings:

### Option 1: Use mkcert (Recommended)

Install mkcert (creates locally-trusted certificates):
```powershell
# Install with Chocolatey
choco install mkcert

# Install local CA
mkcert -install

# Generate certificate
mkcert localhost 127.0.0.1 192.168.1.100
```

This creates `localhost.pem` and `localhost-key.pem`.

Update `sys.config`:
```erlang
{certfile, "localhost.pem"},
{keyfile, "localhost-key.pem"}
```

No more browser warnings! 🎉

### Option 2: Import Your Self-Signed Cert

1. Double-click `priv/ssl/cert.pem`
2. Click "Install Certificate"
3. Store Location: "Current User"
4. Place in store: "Trusted Root Certification Authorities"
5. Restart browser

## Production Testing

For production with real certificates (Let's Encrypt), see [CERTBOT_DEPLOYMENT.md](CERTBOT_DEPLOYMENT.md).

Quick test with Let's Encrypt staging certificates:
```bash
sudo certbot certonly --standalone --staging \
  -d erlbasic.example.com \
  --email your-email@example.com \
  --agree-tos
```

The staging certs won't be trusted by browsers but let you test the renewal process without hitting rate limits.
