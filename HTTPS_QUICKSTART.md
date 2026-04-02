# HTTPS Quick Start Guide

## For Local Development (Localhost/Local Network)

### 1. Generate Self-Signed Certificates
```powershell
pwsh generate_certs.ps1
```

Automatically creates certificates valid for:
- `localhost`
- `127.0.0.1`
- All detected local network IP addresses (e.g., `192.168.1.100`)

### 2. Enable HTTPS
```powershell
# Use the pre-configured HTTPS config
cp sys.config.https sys.config

# Or manually edit sys.config and set:
# {enable_https, true}
```

### 3. Run
```powershell
pwsh build.ps1
pwsh run.ps1
```

### 4. Access
- **HTTP**: http://localhost:8081
- **HTTPS**: https://localhost:8443
- **Local Network**: https://192.168.1.100:8443

**Note**: Browsers will show security warnings for self-signed certificates. Click "Advanced" → "Proceed" to continue.

---

## For Production (Let's Encrypt with Auto-Renewal)

### 1. Install Certbot
```bash
# Ubuntu/Debian
sudo apt update && sudo apt install certbot
```

### 2. Generate Certificate
```bash
# Stop ErlBASIC to free port 80
sudo systemctl stop erlbasic

# Generate certificate
sudo certbot certonly --standalone \
  -d erlbasic.example.com \
  --email your-email@example.com \
  --agree-tos
```

### 3. Copy Certificates
```bash
sudo mkdir -p /opt/erlbasic/priv/ssl
sudo cp -L /etc/letsencrypt/live/erlbasic.example.com/fullchain.pem \
  /opt/erlbasic/priv/ssl/cert.pem
sudo cp -L /etc/letsencrypt/live/erlbasic.example.com/privkey.pem \
  /opt/erlbasic/priv/ssl/key.pem
sudo chown erlbasic:erlbasic /opt/erlbasic/priv/ssl/*.pem
sudo chmod 600 /opt/erlbasic/priv/ssl/key.pem
```

### 4. Configure sys.config
```erlang
{erlbasic, [
    {http_port, 80},
    {enable_https, true},
    {https_port, 443},
    {certfile, "/opt/erlbasic/priv/ssl/cert.pem"},
    {keyfile, "/opt/erlbasic/priv/ssl/key.pem"}
]}
```

### 5. Setup Auto-Renewal

See [CERTBOT_DEPLOYMENT.md](CERTBOT_DEPLOYMENT.md) for complete setup of:
- Renewal script (`/opt/erlbasic/scripts/renew_certs.sh`)
- Systemd timer for automatic renewal
- Post-renewal hooks

Quick setup:
```bash
# Add to crontab (runs twice daily)
sudo crontab -e
# Add line:
30 2,14 * * * /opt/erlbasic/scripts/renew_certs.sh
```

---

## Testing on Local Network

### Find Your IP Address
```powershell
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -ne "127.0.0.1" }
```

### Allow Firewall Access
```powershell
New-NetFirewallRule -DisplayName "ErlBASIC HTTPS" -Direction Inbound -LocalPort 8443 -Protocol TCP -Action Allow
```

### Access from Other Devices
From phones, tablets, or computers on the same network:
```
https://192.168.1.100:8443
```

---

## Configuration Reference

| Setting | Default | Description |
|---------|---------|-------------|
| `http_port` | `8081` | HTTP listener port |
| `enable_https` | `false` | Enable HTTPS listener |
| `https_port` | `8443` | HTTPS listener port |
| `certfile` | `"priv/ssl/cert.pem"` | SSL certificate file path |
| `keyfile` | `"priv/ssl/key.pem"` | SSL private key file path |
| `cacertfile` | `undefined` | Optional CA certificate chain |

---

## Files Created

- **generate_certs.ps1** - Certificate generation script
- **sys.config** - Main configuration file
- **sys.config.https** - Example HTTPS configuration
- **priv/ssl/** - Directory for certificates (gitignored)
- **CERTBOT_DEPLOYMENT.md** - Production deployment guide
- **HTTPS_TESTING.md** - Comprehensive testing guide

---

## Troubleshooting

### "Certificate file not found"
```powershell
pwsh generate_certs.ps1
```

### "Port already in use"
```powershell
Get-NetTCPConnection -LocalPort 8443 | Select-Object OwningProcess
Stop-Process -Id <PID> -Force
```

### Browser shows "NET::ERR_CERT_COMMON_NAME_INVALID"
Regenerate certificates with your specific IP:
```powershell
pwsh generate_certs.ps1 -HostIP 192.168.1.100
```

---

## For More Details

- **Production Deployment**: See [CERTBOT_DEPLOYMENT.md](CERTBOT_DEPLOYMENT.md)
- **Testing Guide**: See [HTTPS_TESTING.md](HTTPS_TESTING.md)
- **Configuration**: See `sys.config` comments
