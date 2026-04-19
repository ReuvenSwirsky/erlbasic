# Certbot Deployment Guide for ErlBASIC

This guide covers deploying ErlBASIC with Let's Encrypt SSL certificates using Certbot, including automatic renewal.

## Prerequisites

- A public domain name pointing to your server (e.g., `erlbasic.example.com`)
- Server with a public IP address
- Port 80 open for HTTP validation (required for initial setup)
- Port 443 for HTTPS
- Root or sudo access

## Installation

### Ubuntu/Debian
```bash
sudo apt update
sudo apt install certbot
```

### CentOS/RHEL
```bash
sudo yum install epel-release
sudo yum install certbot
```

### Windows
Not recommended for production. Use Linux server or WSL2.

## Initial Certificate Generation

### Method 1: Standalone Mode (Recommended for Initial Setup)

This method temporarily runs its own web server on port 80 for validation.

**Step 1: Stop your ErlBASIC server** (to free port 80):
```bash
# If running as systemd service
sudo systemctl stop erlbasic

# Or kill the process
pkill beam.smp
```

**Step 2: Generate certificates**:
```bash
sudo certbot certonly --standalone \
  -d erlbasic.example.com \
  -d www.erlbasic.example.com \
  --email your-email@example.com \
  --agree-tos \
  --no-eff-email
```

**Step 3: Copy certificates to ErlBASIC directory**:
```bash
# Create ssl directory
sudo mkdir -p /opt/erlbasic/priv/ssl

# Copy certificates (preserving symlinks)
sudo cp -L /etc/letsencrypt/live/erlbasic.example.com/fullchain.pem \
  /opt/erlbasic/priv/ssl/cert.pem
sudo cp -L /etc/letsencrypt/live/erlbasic.example.com/privkey.pem \
  /opt/erlbasic/priv/ssl/key.pem

# Set ownership (adjust user as needed)
sudo chown -R erlbasic:erlbasic /opt/erlbasic/priv/ssl
sudo chmod 600 /opt/erlbasic/priv/ssl/key.pem
```

### Method 2: Webroot Mode (If You Have Existing Web Server)

If you're running ErlBASIC behind nginx or Apache:

```bash
sudo certbot certonly --webroot \
  -w /var/www/html \
  -d erlbasic.example.com \
  --email your-email@example.com \
  --agree-tos
```

## Configuration

Update your `sys.config` or `config/sys.config`:

```erlang
[
  {erlbasic, [
    {http_port, 8081},
    {enable_https, true},
    {https_port, 8443},
    {certfile, "/opt/erlbasic/priv/ssl/cert.pem"},
    {keyfile, "/opt/erlbasic/priv/ssl/key.pem"}
  ]}
].
```

For production behind a reverse proxy, you might use standard ports:
```erlang
{http_port, 80},
{https_port, 443}
```

## Automatic Certificate Renewal

Let's Encrypt certificates expire after 90 days. Set up automatic renewal:

### Create Renewal Script

Create `/opt/erlbasic/scripts/renew_certs.sh`:

```bash
#!/bin/bash
# Certificate renewal script for ErlBASIC

DOMAIN="erlbasic.example.com"
CERT_PATH="/etc/letsencrypt/live/$DOMAIN"
APP_SSL_PATH="/opt/erlbasic/priv/ssl"
LOG_FILE="/var/log/erlbasic-cert-renewal.log"

echo "=== Certificate Renewal Check: $(date) ===" >> "$LOG_FILE"

# Stop ErlBASIC to free port 80
systemctl stop erlbasic >> "$LOG_FILE" 2>&1

# Renew certificate
certbot renew --standalone --quiet >> "$LOG_FILE" 2>&1
RENEW_STATUS=$?

if [ $RENEW_STATUS -eq 0 ]; then
    echo "Certificate renewal check completed" >> "$LOG_FILE"
    
    # Copy new certificates if they were updated
    cp -L "$CERT_PATH/fullchain.pem" "$APP_SSL_PATH/cert.pem" >> "$LOG_FILE" 2>&1
    cp -L "$CERT_PATH/privkey.pem" "$APP_SSL_PATH/key.pem" >> "$LOG_FILE" 2>&1
    
    # Set permissions
    chown erlbasic:erlbasic "$APP_SSL_PATH"/*.pem
    chmod 600 "$APP_SSL_PATH/key.pem"
    
    echo "Certificates copied to application directory" >> "$LOG_FILE"
else
    echo "ERROR: Certificate renewal failed with status $RENEW_STATUS" >> "$LOG_FILE"
fi

# Restart ErlBASIC
systemctl start erlbasic >> "$LOG_FILE" 2>&1

if systemctl is-active --quiet erlbasic; then
    echo "ErlBASIC service restarted successfully" >> "$LOG_FILE"
else
    echo "ERROR: ErlBASIC service failed to restart" >> "$LOG_FILE"
fi

echo "" >> "$LOG_FILE"
```

Make it executable:
```bash
sudo chmod +x /opt/erlbasic/scripts/renew_certs.sh
```

### Setup Cron Job

Add to root's crontab:
```bash
sudo crontab -e
```

Add this line (runs twice daily at 2:30 AM and 2:30 PM):
```cron
30 2,14 * * * /opt/erlbasic/scripts/renew_certs.sh
```

Or use systemd timer (see below).

### Alternative: Systemd Timer (Recommended)

Create `/etc/systemd/system/erlbasic-cert-renewal.service`:

```ini
[Unit]
Description=Renew ErlBASIC SSL Certificates
After=network.target

[Service]
Type=oneshot
ExecStart=/opt/erlbasic/scripts/renew_certs.sh
User=root
```

Create `/etc/systemd/system/erlbasic-cert-renewal.timer`:

```ini
[Unit]
Description=Run ErlBASIC certificate renewal twice daily
Requires=erlbasic-cert-renewal.service

[Timer]
OnCalendar=*-*-* 02:30:00
OnCalendar=*-*-* 14:30:00
Persistent=true

[Install]
WantedBy=timers.target
```

Enable and start the timer:
```bash
sudo systemctl daemon-reload
sudo systemctl enable erlbasic-cert-renewal.timer
sudo systemctl start erlbasic-cert-renewal.timer

# Check status
sudo systemctl status erlbasic-cert-renewal.timer
sudo systemctl list-timers erlbasic-cert-renewal.timer
```

## Post-Renewal Hook (No Downtime)

For zero-downtime renewal using webroot or DNS challenge:

Create `/etc/letsencrypt/renewal-hooks/deploy/erlbasic.sh`:

```bash
#!/bin/bash
DOMAIN="erlbasic.example.com"
CERT_PATH="/etc/letsencrypt/live/$DOMAIN"
APP_SSL_PATH="/opt/erlbasic/priv/ssl"

# Copy new certificates
cp -L "$CERT_PATH/fullchain.pem" "$APP_SSL_PATH/cert.pem"
cp -L "$CERT_PATH/privkey.pem" "$APP_SSL_PATH/key.pem"
chown erlbasic:erlbasic "$APP_SSL_PATH"/*.pem
chmod 600 "$APP_SSL_PATH/key.pem"

# Reload ErlBASIC (if you implement hot reload)
# Or just restart
systemctl restart erlbasic
```

Make it executable:
```bash
sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/erlbasic.sh
```

Then renewal can run without stopping:
```bash
sudo certbot renew --webroot -w /var/www/html
```

## Testing Renewal

Test the renewal process without actually renewing:
```bash
sudo certbot renew --dry-run
```

Force renewal for testing (even if not expired):
```bash
sudo certbot renew --force-renewal
```

## Reverse Proxy Configuration (Optional)

For production, run ErlBASIC on high ports (8081/8443) behind nginx on standard ports (80/443):

### Nginx Configuration

Create `/etc/nginx/sites-available/erlbasic`:

```nginx
# Redirect HTTP to HTTPS
server {
    listen 80;
    server_name erlbasic.example.com;
    return 301 https://$server_name$request_uri;
}

# HTTPS Server
server {
    listen 443 ssl http2;
    server_name erlbasic.example.com;

    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/erlbasic.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/erlbasic.example.com/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    # Proxy to ErlBASIC
    location / {
        proxy_pass http://localhost:8081;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # WebSocket Support
    location /ws {
        proxy_pass http://localhost:8081/ws;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 86400;
    }
}
```

Enable and restart nginx:
```bash
sudo ln -s /etc/nginx/sites-available/erlbasic /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

With nginx, certbot can use the webroot method without stopping anything:
```bash
sudo certbot certonly --webroot -w /var/www/html -d erlbasic.example.com
```

## Troubleshooting

### Port 80 Already in Use
Check what's using port 80:
```bash
sudo lsof -i :80
sudo netstat -tlnp | grep :80
```

### Certificate Permissions
Ensure proper permissions:
```bash
sudo chmod 644 /opt/erlbasic/priv/ssl/cert.pem
sudo chmod 600 /opt/erlbasic/priv/ssl/key.pem
sudo chown erlbasic:erlbasic /opt/erlbasic/priv/ssl/*.pem
```

### Check Certificate Expiry
```bash
# Via OpenSSL
openssl x509 -in /opt/erlbasic/priv/ssl/cert.pem -noout -dates

# Via Certbot
sudo certbot certificates
```

### View Renewal Logs
```bash
sudo tail -f /var/log/letsencrypt/letsencrypt.log
sudo tail -f /var/log/erlbasic-cert-renewal.log
```

### Manual Renewal
```bash
sudo certbot renew --force-renewal
sudo /opt/erlbasic/scripts/renew_certs.sh
```

## Security Best Practices

1. **Keep private keys secure**: Never commit `key.pem` to version control
2. **Use strong ciphers**: The provided nginx config uses modern ciphers
3. **Enable HTTP/2**: Already included in nginx config
4. **Keep certbot updated**: `sudo apt upgrade certbot`
5. **Monitor expiry**: Set up monitoring alerts 30 days before expiry
6. **Use separate user**: Run ErlBASIC as non-root user
7. **Firewall rules**: Only open necessary ports (80, 443)

## Certificate Locations

- Let's Encrypt certificates: `/etc/letsencrypt/live/{domain}/`
- Application certificates: `/opt/erlbasic/priv/ssl/`
- Renewal logs: `/var/log/letsencrypt/letsencrypt.log`
- Custom renewal logs: `/var/log/erlbasic-cert-renewal.log`

## Additional Resources

- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)
- [Certbot Documentation](https://eff-certbot.readthedocs.io/)
- [SSL Server Test](https://www.ssllabs.com/ssltest/)
