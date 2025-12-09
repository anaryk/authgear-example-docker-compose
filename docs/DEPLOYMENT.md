# Authgear Production Deployment Guide

Complete guide for deploying Authgear in production with high availability and security.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                         Internet                             │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│              Proxy Server (Public IP)                        │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Nginx                                                │   │
│  │  - SSL/TLS Termination                               │   │
│  │  - Rate Limiting                                      │   │
│  │  - DDoS Protection                                    │   │
│  │  - Load Balancing                                     │   │
│  └──────────────────────────────────────────────────────┘   │
└────────────────────────┬────────────────────────────────────┘
                         │ Internal Network
                         ▼
┌─────────────────────────────────────────────────────────────┐
│              VM Server (Private IP)                          │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Docker Compose Stack                                │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐           │   │
│  │  │PostgreSQL│  │  Redis   │  │  MinIO   │           │   │
│  │  └──────────┘  └──────────┘  └──────────┘           │   │
│  │  ┌──────────────────────────────────────┐           │   │
│  │  │         Authgear Services            │           │   │
│  │  │  - Main Auth                         │           │   │
│  │  │  - Portal                            │           │   │
│  │  │  - Images                            │           │   │
│  │  └──────────────────────────────────────┘           │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

### VM Server Requirements

- **OS**: Ubuntu 22.04 LTS or later
- **CPU**: Minimum 4 cores (8 cores recommended)
- **RAM**: Minimum 8 GB (16 GB recommended)
- **Storage**: Minimum 100 GB SSD
- **Network**: Private IP address, accessible from proxy server

### Software Requirements

- Docker Engine 24.0+
- Docker Compose 2.20+
- Git
- OpenSSL
- Bash 4.0+

### Network Security

Services are isolated in Docker networks:
- Backend services (PostgreSQL, Redis, MinIO) are not exposed to host
- Only nginx ports (3100, 8010) are exposed for reverse proxy
- **CRITICAL:** Use firewall to restrict access to these ports **ONLY from proxy server IP**

```bash
# Allow only proxy server to access exposed ports
sudo ufw allow from <PROXY_SERVER_IP> to any port 3100
sudo ufw allow from <PROXY_SERVER_IP> to any port 8010
sudo ufw deny 3100
sudo ufw deny 8010
sudo ufw allow ssh
sudo ufw enable
```

## Deployment Steps

### 1. Prepare the VM

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install required packages
sudo apt install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    git \
    openssl

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Add current user to docker group
sudo usermod -aG docker $USER
newgrp docker

# Verify Docker installation
docker --version
docker compose version
```

### 2. Clone Repository

```bash
# Clone the repository
git clone https://github.com/anaryk/authgear-example-docker-compose.git
cd authgear-example-docker-compose
```

### 3. Run Installation Script

```bash
# Make sure scripts are executable
chmod +x scripts/*.sh

# Run installation
./scripts/install.sh
```

The installation script will:

1. Check prerequisites
2. Generate secure passwords
3. Create `.env` file
4. Prompt for domain configuration
5. Build custom Docker images
6. Start infrastructure services
7. Run database migrations
8. Create MinIO buckets
9. Initialize Authgear project
10. Start all services

### 4. Configure DNS

Follow the instructions in [DNS-SETUP.md](./DNS-SETUP.md) to configure:

- A records for `auth.maximal-limit.cz`
- A records for `portal.maximal-limit.cz`
- CAA records for Let's Encrypt

### 5. Set Up Proxy Server

Follow the instructions in [PROXY-SETUP.md](./PROXY-SETUP.md) to:

1. Install and configure Nginx
2. Obtain SSL certificates
3. Configure reverse proxy
4. Enable security features

### 6. Verify Deployment

```bash
# Run health checks
./scripts/health-check.sh

# Check all services are running
docker compose -f docker-compose.production.yml ps

# View logs
docker compose -f docker-compose.production.yml logs -f
```

### 7. Create Admin Account

Access the portal at `https://portal.maximal-limit.cz` and create your admin account.

## Post-Deployment Configuration

### 1. Set Up Automated Backups

```bash
# Add backup to crontab (daily at 2 AM)
crontab -e

# Add this line:
0 2 * * * /path/to/authgear-example-docker-compose/scripts/backup.sh
```

### 2. Configure Monitoring

Set up monitoring for:

- **Service Health**: Use `health-check.sh`
- **Disk Space**: Monitor storage usage
- **Log Analysis**: Review logs regularly
- **SSL Expiry**: Certbot handles auto-renewal

Example monitoring script:

```bash
#!/bin/bash
# /usr/local/bin/authgear-monitor.sh

cd /path/to/authgear-example-docker-compose

# Run health check
if ! ./scripts/health-check.sh; then
    # Send alert (email, Slack, etc.)
    echo "Authgear health check failed" | mail -s "Alert" admin@example.com
fi

# Check disk space
DISK_USAGE=$(df -h /var/lib/docker | tail -1 | awk '{print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -gt 80 ]; then
    echo "Disk usage is ${DISK_USAGE}%" | mail -s "Disk Alert" admin@example.com
fi
```

Add to crontab:
```bash
*/15 * * * * /usr/local/bin/authgear-monitor.sh
```

### 3. Configure Log Rotation

Docker handles log rotation automatically, but verify:

```bash
# Check Docker daemon.json
cat /etc/docker/daemon.json
```

Should include:
```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

### 4. Security Hardening

#### A. Configure Firewall

```bash
# If using UFW
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow from PROXY_SERVER_IP to any port 3100
sudo ufw allow from PROXY_SERVER_IP to any port 8010
sudo ufw enable
```

#### B. Enable Fail2Ban

```bash
sudo apt install -y fail2ban

# Configure SSH protection
sudo tee /etc/fail2ban/jail.local << EOF
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
EOF

sudo systemctl restart fail2ban
```

#### C. Disable Root Login

```bash
sudo nano /etc/ssh/sshd_config

# Set:
PermitRootLogin no
PasswordAuthentication no

sudo systemctl restart sshd
```

#### D. Enable Automatic Security Updates

```bash
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
```

## Updating the Application

### Standard Update

```bash
cd /path/to/authgear-example-docker-compose

# Run update script
./scripts/update.sh
```

The update script will:

1. Create backup
2. Pull latest Docker images
3. Run database migrations
4. Perform rolling restart
5. Verify deployment
6. Clean up old images

### Emergency Rollback

If update fails:

```bash
# Stop all services
docker compose -f docker-compose.production.yml down

# Restore from latest backup
cd backups
tar xzf backup_YYYYMMDD_HHMMSS.tar.gz

# Restore database
docker compose -f docker-compose.production.yml up -d postgres
docker compose -f docker-compose.production.yml exec -T postgres \
    psql -U authgear_user -d authgear_production < backup_YYYYMMDD_HHMMSS/postgres/authgear_YYYYMMDD_HHMMSS.sql

# Start all services
docker compose -f docker-compose.production.yml up -d
```

## Maintenance Tasks

### Daily Tasks

- [ ] Review application logs for errors
- [ ] Check disk space usage
- [ ] Verify backups completed successfully

### Weekly Tasks

- [ ] Run health checks
- [ ] Review security logs
- [ ] Check SSL certificate expiry
- [ ] Update system packages

### Monthly Tasks

- [ ] Test backup restoration
- [ ] Review and rotate access logs
- [ ] Update Docker images
- [ ] Review resource usage and scale if needed

## Troubleshooting

### Services Won't Start

```bash
# Check Docker daemon
sudo systemctl status docker

# Check logs
docker compose -f docker-compose.production.yml logs

# Check disk space
df -h

# Check resources
docker stats
```

### Database Connection Issues

```bash
# Check PostgreSQL is running
docker compose -f docker-compose.production.yml ps postgres

# Check database logs
docker compose -f docker-compose.production.yml logs postgres

# Test connection
docker compose -f docker-compose.production.yml exec postgres \
    psql -U authgear_user -d authgear_production -c "SELECT 1"
```

### Performance Issues

```bash
# Check resource usage
docker stats

# Check PostgreSQL performance
docker compose -f docker-compose.production.yml exec postgres \
    psql -U authgear_user -d authgear_production -c "
    SELECT pid, now() - pg_stat_activity.query_start AS duration, query 
    FROM pg_stat_activity 
    WHERE state != 'idle' ORDER BY duration DESC;"

# Check Redis memory
docker compose -f docker-compose.production.yml exec redis redis-cli info memory
```

### Cannot Access Application

1. Check DNS resolution: `dig auth.maximal-limit.cz`
2. Check proxy server: `curl -I https://auth.maximal-limit.cz`
3. Check VM services: `./scripts/health-check.sh`
4. Check firewall rules
5. Review Nginx logs on proxy server

## Scaling Considerations

### Vertical Scaling (Current Setup)

Increase resources on the VM:

```yaml
# In docker-compose.production.yml
deploy:
  resources:
    limits:
      cpus: '4'      # Increase CPU
      memory: 4G     # Increase memory
```

### Horizontal Scaling (Future)

For high-traffic scenarios, consider:

1. **Multiple VMs** behind load balancer
2. **Managed PostgreSQL** (AWS RDS, Google Cloud SQL)
3. **Managed Redis** (AWS ElastiCache, Redis Cloud)
4. **Object Storage** (AWS S3, Google Cloud Storage)
5. **Container Orchestration** (Kubernetes, Docker Swarm)

## Disaster Recovery

### Backup Strategy

**What's Backed Up:**
- PostgreSQL database
- Redis data
- MinIO buckets (images, exports)
- Configuration files
- SSL certificates (on proxy server)

**Retention:**
- Daily backups: 30 days
- Weekly backups: 90 days
- Monthly backups: 1 year

### Recovery Procedure

1. **Provision new VM** with same specifications
2. **Install Docker** and dependencies
3. **Clone repository** and checkout same version
4. **Restore configuration** from backup
5. **Restore databases** from backup
6. **Start services** and verify
7. **Update DNS** if IP changed
8. **Update proxy configuration**

**RTO (Recovery Time Objective)**: 2-4 hours  
**RPO (Recovery Point Objective)**: 24 hours

## Security Best Practices

1. **Keep secrets secure** - Never commit `.env` to Git
2. **Regular updates** - Keep all software up to date
3. **Audit logs** - Review access and error logs regularly
4. **Principle of least privilege** - Limit access to production systems
5. **Encrypted backups** - Encrypt backups before storing
6. **2FA everywhere** - Enable 2FA for all admin accounts
7. **Network segmentation** - Keep VM on private network
8. **Security scanning** - Regular vulnerability scans

## Compliance Considerations

### GDPR Compliance

- Configure data retention policies
- Implement user data export/deletion
- Maintain audit logs
- Document data processing

### SOC 2 Considerations

- Implement access controls
- Enable detailed audit logging
- Regular security assessments
- Incident response procedures

## Support and Resources

### Documentation

- [Authgear Official Docs](https://docs.authgear.com/)
- [Docker Documentation](https://docs.docker.com/)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)

### Community

- [Authgear GitHub](https://github.com/authgear/authgear-server)
- [Authgear Discord](https://discord.gg/authgear)

### Monitoring Tools

- [Prometheus](https://prometheus.io/)
- [Grafana](https://grafana.com/)
- [UptimeRobot](https://uptimerobot.com/)
- [DataDog](https://www.datadoghq.com/)

## Checklist

Before going to production:

- [ ] DNS records configured and propagated
- [ ] SSL certificates obtained and valid
- [ ] All services healthy and responding
- [ ] Backups automated and tested
- [ ] Monitoring and alerts configured
- [ ] Firewall rules configured
- [ ] Security hardening completed
- [ ] Documentation reviewed and updated
- [ ] Admin accounts created and secured
- [ ] Disaster recovery plan documented
- [ ] Performance tested under load
- [ ] Compliance requirements met

## Getting Help

If you encounter issues:

1. Check this documentation
2. Review application logs
3. Run health check script
4. Search GitHub issues
5. Ask in community Discord
6. Contact Authgear support

## License

This deployment configuration is provided as-is under the MIT License.
