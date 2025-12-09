# Proxy Server Setup Guide

This guide explains how to configure the external proxy server that handles SSL termination and forwards requests to the internal VM.

## Architecture Overview

```
Internet → Proxy Server (Public IP) → VM (Private IP)
          ├─ SSL/TLS Termination
          ├─ DDoS Protection
          ├─ Rate Limiting
          └─ Reverse Proxy
```

## Prerequisites

- A server with a public IP address (Ubuntu 22.04 LTS recommended)
- Root or sudo access
- Ports 80 and 443 open in firewall
- Network connectivity to the VM's private IP

## Step 1: Install Nginx

```bash
# Update system packages
sudo apt update && sudo apt upgrade -y

# Install Nginx
sudo apt install -y nginx

# Verify installation
nginx -v
```

## Step 2: Install Certbot for SSL

```bash
# Install Certbot and Nginx plugin
sudo apt install -y certbot python3-certbot-nginx

# Verify installation
certbot --version
```

## Step 3: Configure Firewall

```bash
# If using UFW
sudo ufw allow 'Nginx Full'
sudo ufw allow OpenSSH
sudo ufw enable

# Verify
sudo ufw status

# If using iptables
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT
sudo iptables-save | sudo tee /etc/iptables/rules.v4
```

## Step 4: Copy Nginx Configuration

Copy the provided `proxy-server-nginx.conf` to the proxy server:

```bash
# On your local machine
scp proxy-server-nginx.conf user@proxy-server:/tmp/

# On the proxy server
sudo mv /tmp/proxy-server-nginx.conf /etc/nginx/sites-available/authgear
```

## Step 5: Update Configuration

Edit the configuration file and replace placeholders:

```bash
sudo nano /etc/nginx/sites-available/authgear
```

**Replace:**

1. **YOUR_VM_LOCAL_IP** with your VM's actual private IP (e.g., `192.168.1.100`)

2. **Verify correct ports** (these are already set correctly in the config):
   - **Auth service** (auth.maximal-limit.cz) → `VM_IP:3100`
   - **Portal service** (portal.maximal-limit.cz) → `VM_IP:8010`

Example:
```nginx
# For auth domain
upstream authgear_vm_auth {
    server 192.168.1.100:3100;  # Port 3100 for auth
    keepalive 32;
}

# For portal domain
upstream authgear_vm_portal {
    server 192.168.1.100:8010;  # Port 8010 for portal
    keepalive 32;
}
```

**Important:** Each domain must forward to a different port:
- `auth.maximal-limit.cz` → Port **3100** (main authentication)
- `portal.maximal-limit.cz` → Port **8010** (admin portal)

## Step 6: Obtain SSL Certificates

```bash
# Obtain certificate for auth domain
sudo certbot certonly --nginx \
  -d auth.maximal-limit.cz \
  --email your-email@example.com \
  --agree-tos \
  --no-eff-email

# Obtain certificate for portal domain
sudo certbot certonly --nginx \
  -d portal.maximal-limit.cz \
  --email your-email@example.com \
  --agree-tos \
  --no-eff-email
```

**Note**: Ensure DNS records are already pointing to this server before running certbot.

## Step 7: Enable Site Configuration

```bash
# Remove default site
sudo rm /etc/nginx/sites-enabled/default

# Enable authgear site
sudo ln -s /etc/nginx/sites-available/authgear /etc/nginx/sites-enabled/

# Test configuration
sudo nginx -t

# If test passes, reload Nginx
sudo systemctl reload nginx
```

## Step 8: Set Up Auto-Renewal

Certbot automatically sets up renewal. Verify it's working:

```bash
# Test renewal
sudo certbot renew --dry-run

# Check renewal timer
sudo systemctl status certbot.timer
```

## Step 9: Configure Network Routing

Ensure the proxy server can reach the VM:

```bash
# Test connectivity
ping -c 4 192.168.1.100  # Replace with your VM IP

# Test specific ports
nc -zv 192.168.1.100 3100
nc -zv 192.168.1.100 8010
```

If the VM is on a different network, you may need to:

1. Set up VPN between proxy and VM
2. Configure static routes
3. Use VPC peering (if using cloud providers)

## Enhanced Security Configuration

### 1. Enable HTTP/2

Already enabled in the configuration:
```nginx
listen 443 ssl http2;
```

### 2. Configure Additional Security Headers

Add to your server blocks:

```nginx
add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;
add_header X-Robots-Tag "noindex, nofollow" always;  # If you don't want indexing
```

### 3. Set Up Fail2Ban

Protect against brute force attacks:

```bash
sudo apt install -y fail2ban

# Create custom filter for Nginx
sudo tee /etc/fail2ban/filter.d/nginx-limit-req.conf << 'EOF'
[Definition]
failregex = limiting requests, excess:.* by zone.*client: <HOST>
ignoreregex =
EOF

# Configure jail
sudo tee /etc/fail2ban/jail.d/nginx-limit-req.conf << 'EOF'
[nginx-limit-req]
enabled = true
filter = nginx-limit-req
logpath = /var/log/nginx/error.log
maxretry = 5
findtime = 600
bantime = 3600
EOF

# Restart fail2ban
sudo systemctl restart fail2ban
```

### 4. Configure ModSecurity WAF (Optional)

For advanced protection:

```bash
sudo apt install -y libmodsecurity3 modsecurity-crs

# Follow ModSecurity configuration guides for Nginx
```

## Monitoring and Logging

### 1. Check Nginx Logs

```bash
# Access logs
sudo tail -f /var/log/nginx/access.log

# Error logs
sudo tail -f /var/log/nginx/error.log

# Specific domain logs
sudo tail -f /var/log/nginx/auth.maximal-limit.cz-access.log
sudo tail -f /var/log/nginx/portal.maximal-limit.cz-access.log
```

### 2. Monitor Performance

```bash
# Check Nginx status
sudo systemctl status nginx

# View active connections
sudo nginx -T | grep worker_connections

# Monitor with htop
sudo apt install -y htop
htop
```

### 3. Set Up Log Rotation

Nginx log rotation is configured by default. Verify:

```bash
cat /etc/logrotate.d/nginx
```

## Performance Tuning

### 1. Optimize Nginx Configuration

Edit `/etc/nginx/nginx.conf`:

```nginx
# Worker processes (set to number of CPU cores)
worker_processes auto;

# Worker connections
events {
    worker_connections 4096;
    use epoll;
    multi_accept on;
}

# Buffer sizes
client_body_buffer_size 128k;
client_max_body_size 20M;
```

### 2. Enable Caching (Optional)

For static content:

```nginx
proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=my_cache:10m max_size=1g inactive=60m;

# In server block
proxy_cache my_cache;
proxy_cache_valid 200 1h;
```

## Backup and Disaster Recovery

### 1. Backup Configuration

```bash
# Create backup script
sudo tee /usr/local/bin/backup-nginx-config.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/var/backups/nginx"
mkdir -p "$BACKUP_DIR"
tar czf "$BACKUP_DIR/nginx-config-$(date +%Y%m%d).tar.gz" \
    /etc/nginx \
    /etc/letsencrypt
find "$BACKUP_DIR" -name "nginx-config-*.tar.gz" -mtime +30 -delete
EOF

sudo chmod +x /usr/local/bin/backup-nginx-config.sh

# Add to crontab
echo "0 2 * * * /usr/local/bin/backup-nginx-config.sh" | sudo crontab -
```

### 2. Disaster Recovery

If the proxy server fails:

1. Provision new server
2. Point DNS to new server IP
3. Restore configuration from backup
4. Obtain new SSL certificates (or restore from backup)
5. Test and verify

## Health Checks

### 1. Manual Health Check

```bash
# Test HTTP to HTTPS redirect
curl -I http://auth.maximal-limit.cz

# Test HTTPS
curl -I https://auth.maximal-limit.cz

# Test SSL certificate
openssl s_client -connect auth.maximal-limit.cz:443 -servername auth.maximal-limit.cz
```

### 2. Automated Monitoring

Set up monitoring with:

- **UptimeRobot** - Free uptime monitoring
- **Pingdom** - Advanced monitoring
- **Prometheus + Grafana** - Self-hosted monitoring

Example Prometheus nginx exporter:

```bash
# Install nginx-prometheus-exporter
wget https://github.com/nginxinc/nginx-prometheus-exporter/releases/download/v0.11.0/nginx-prometheus-exporter_0.11.0_linux_amd64.tar.gz
tar xzf nginx-prometheus-exporter_0.11.0_linux_amd64.tar.gz
sudo mv nginx-prometheus-exporter /usr/local/bin/
```

## Troubleshooting

### Issue: 502 Bad Gateway

**Cause**: Cannot reach backend VM

**Solutions**:
1. Verify VM is running and accessible
2. Check firewall rules on VM
3. Verify correct IP address in nginx config
4. Check VM services are running on correct ports

```bash
# Test from proxy server
curl http://192.168.1.100:3100/healthz
curl http://192.168.1.100:8010/healthz
```

### Issue: SSL Certificate Errors

**Cause**: Certificate expired or misconfigured

**Solutions**:
1. Check certificate expiration: `sudo certbot certificates`
2. Renew manually: `sudo certbot renew`
3. Verify certificate paths in nginx config

### Issue: Rate Limiting Too Aggressive

**Cause**: Legitimate users being blocked

**Solutions**:
1. Adjust rate limits in nginx config
2. Whitelist specific IPs
3. Review fail2ban rules

```nginx
# Whitelist IP
geo $limit {
    default 1;
    10.0.0.0/8 0;  # Don't limit internal network
    1.2.3.4 0;      # Don't limit specific IP
}

map $limit $limit_key {
    0 "";
    1 $binary_remote_addr;
}

limit_req_zone $limit_key zone=auth_limit:10m rate=10r/s;
```

## Maintenance

### Update Nginx

```bash
sudo apt update
sudo apt upgrade nginx
sudo systemctl reload nginx
```

### Rotate Logs Manually

```bash
sudo logrotate -f /etc/logrotate.d/nginx
```

### Clear Cache

```bash
sudo rm -rf /var/cache/nginx/*
sudo systemctl reload nginx
```

## Security Checklist

- [ ] Firewall configured (only ports 80, 443, 22 open)
- [ ] SSH key-based authentication enabled
- [ ] Password authentication disabled
- [ ] Fail2ban installed and configured
- [ ] SSL certificates valid and auto-renewing
- [ ] Security headers configured
- [ ] Rate limiting enabled
- [ ] Access logs monitored
- [ ] Backups automated
- [ ] Monitoring alerts configured
- [ ] System updates scheduled

## Additional Resources

- [Nginx Documentation](https://nginx.org/en/docs/)
- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)
- [Mozilla SSL Configuration Generator](https://ssl-config.mozilla.org/)
- [SSL Labs Server Test](https://www.ssllabs.com/ssltest/)

## Next Steps

After completing proxy server setup:

1. Test both domains are accessible via HTTPS
2. Verify SSL certificates are valid (A+ rating on SSL Labs)
3. Deploy the application on VM (see [DEPLOYMENT.md](./DEPLOYMENT.md))
4. Set up monitoring and alerts
5. Configure automated backups
