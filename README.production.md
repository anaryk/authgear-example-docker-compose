# Authgear Production Stack - Production Ready

Complete production-ready deployment for Authgear authentication system with enterprise-grade security, monitoring, and disaster recovery.

## 🎯 Overview

This repository contains a complete production deployment setup for [Authgear](https://www.authgear.com/) using Docker Compose, designed for deployment on a VM with an external reverse proxy.

### Architecture

```
Internet → Proxy Server (SSL/TLS) → VM (Docker Compose Stack)
           ├─ auth.maximal-limit.cz
           └─ portal.maximal-limit.cz
```

## ✨ Features

- **🔐 Security First**: Automated password generation, secrets management, SSL/TLS
- **📦 Production Ready**: Health checks, restart policies, resource limits
- **🔄 Zero Downtime Updates**: Rolling updates with automatic backups
- **📊 Monitoring**: Built-in health checks and logging
- **💾 Disaster Recovery**: Automated backups with retention policies
- **🚀 CI/CD**: GitHub Actions for building and pushing custom images
- **🛡️ Hardened**: Rate limiting, fail2ban, security headers

## 📋 Prerequisites

### VM Server
- Ubuntu 22.04 LTS or later
- 4+ CPU cores (8 recommended)
- 8+ GB RAM (16 GB recommended)
- 100+ GB SSD storage
- Private IP address

### Proxy Server
- Public IP address
- Nginx
- Certbot for Let's Encrypt

## 🚀 Quick Start

### 1. Clone Repository

```bash
git clone https://github.com/anaryk/authgear-example-docker-compose.git
cd authgear-example-docker-compose
```

### 2. Run Installation

```bash
chmod +x scripts/*.sh
./scripts/install.sh
```

The installation script will:
- ✅ Validate prerequisites
- ✅ Generate secure passwords
- ✅ Configure domains
- ✅ Build Docker images
- ✅ Initialize databases
- ✅ Start all services

### 3. Configure DNS

Add these DNS records to `maximal-limit.cz`:

```dns
auth.maximal-limit.cz.    IN    A    <PROXY_SERVER_IP>
portal.maximal-limit.cz.  IN    A    <PROXY_SERVER_IP>
```

See [DNS Setup Guide](./docs/DNS-SETUP.md) for details.

### 4. Set Up Proxy Server

Follow the [Proxy Setup Guide](./docs/PROXY-SETUP.md) to configure Nginx with SSL.

### 5. Verify Deployment

```bash
./scripts/health-check.sh
```

## 📁 Project Structure

```
.
├── scripts/
│   ├── install.sh          # Initial installation
│   ├── update.sh           # Update stack
│   ├── backup.sh           # Backup databases
│   ├── health-check.sh     # Monitor services
│   └── test.sh             # Test suite
├── docs/
│   ├── DEPLOYMENT.md       # Deployment guide
│   ├── DNS-SETUP.md        # DNS configuration
│   └── PROXY-SETUP.md      # Proxy server setup
├── docker-compose.production.yml
├── nginx.production.conf   # Nginx config for VM
├── proxy-server-nginx.conf # Nginx config for proxy
├── .env.example            # Environment template
├── postgres/
│   └── Dockerfile          # Custom PostgreSQL image
└── .github/
    └── workflows/
        └── build-images.yml # CI/CD workflow
```

## 🔧 Configuration

### Environment Variables

Copy `.env.example` to `.env` and configure:

```bash
# Automatically handled by install.sh
AUTH_DOMAIN=auth.maximal-limit.cz
PORTAL_DOMAIN=portal.maximal-limit.cz
POSTGRES_PASSWORD=<generated>
REDIS_PASSWORD=<generated>
MINIO_ROOT_PASSWORD=<generated>
```

### Docker Compose Services

- **postgres**: PostgreSQL 16 with pg_partman and pgaudit
- **redis**: Redis 7 with persistence
- **minio**: MinIO for object storage
- **nginx**: Internal reverse proxy
- **authgear**: Main authentication service
- **authgear-portal**: Admin portal
- **authgear-images**: Image service
- **authgear-deno**: Deno runtime for hooks

## 🛠️ Management Scripts

### Installation

```bash
./scripts/install.sh
```

### Update Stack

```bash
./scripts/update.sh
```

Performs:
1. Backup current state
2. Pull latest images
3. Run migrations
4. Rolling restart
5. Verification

### Backup

```bash
./scripts/backup.sh
```

Backs up:
- PostgreSQL databases
- Redis data
- MinIO buckets
- Configuration files

### Health Check

```bash
./scripts/health-check.sh
```

Monitors:
- Service status
- Database connectivity
- Disk space
- Recent errors

### Run Tests

```bash
./scripts/test.sh
```

## 📊 Monitoring

### Health Checks

All services include health checks:
- PostgreSQL: `pg_isready`
- Redis: `redis-cli ping`
- MinIO: HTTP health endpoint
- Authgear services: HTTP `/healthz` endpoint

### Logging

Logs are automatically rotated:
- Max size: 10-50 MB per file
- Retention: 3-5 files per service

View logs:
```bash
docker compose -f docker-compose.production.yml logs -f [service]
```

## 🔒 Security

### Features

- ✅ Automated password generation (32+ chars)
- ✅ No DEV_MODE in production
- ✅ Rate limiting (Nginx)
- ✅ Security headers (HSTS, CSP, etc.)
- ✅ Fail2ban integration
- ✅ Firewall configuration
- ✅ SSL/TLS with Let's Encrypt
- ✅ Secrets isolation

### Hardening Checklist

- [ ] Firewall configured (UFW/iptables)
- [ ] SSH key-based authentication
- [ ] Fail2ban enabled
- [ ] Automatic security updates
- [ ] Regular backup testing
- [ ] Monitoring alerts configured
- [ ] SSL A+ rating verified

## 💾 Backup & Recovery

### Automated Backups

Set up cron job:
```bash
0 2 * * * /path/to/scripts/backup.sh
```

### Backup Retention

- Daily: 30 days
- Compressed archives in `backups/`

### Restore

```bash
cd backups
tar xzf backup_YYYYMMDD_HHMMSS.tar.gz
# Restore databases manually or via script
```

## 🔄 Updates

### Authgear Version Updates

Edit `docker-compose.production.yml`:
```yaml
authgear:
  image: quay.io/theauthgear/authgear-server:NEW_VERSION
```

Then run:
```bash
./scripts/update.sh
```

### System Updates

```bash
sudo apt update && sudo apt upgrade -y
```

## 🧪 Testing

### Run Test Suite

```bash
./scripts/test.sh
```

Tests include:
- File structure validation
- Script permissions
- Docker Compose syntax
- Nginx configuration
- Secret management
- Shellcheck validation

### Shellcheck Validation

All scripts pass shellcheck:
```bash
shellcheck scripts/*.sh
```

## 📚 Documentation

- [Deployment Guide](./docs/DEPLOYMENT.md) - Complete deployment instructions
- [DNS Setup](./docs/DNS-SETUP.md) - DNS configuration for maximal-limit.cz
- [Proxy Setup](./docs/PROXY-SETUP.md) - Reverse proxy configuration

## 🔧 Troubleshooting

### Services Not Starting

```bash
# Check logs
docker compose -f docker-compose.production.yml logs

# Check resources
docker stats
```

### Database Issues

```bash
# Check PostgreSQL
docker compose -f docker-compose.production.yml exec postgres pg_isready

# Access PostgreSQL
docker compose -f docker-compose.production.yml exec postgres psql -U authgear_user
```

### Network Issues

```bash
# Test connectivity
curl http://localhost:3100/healthz
curl http://localhost:8010/healthz
```

## 🌟 Best Practices

1. **Always backup before updates**
2. **Test in staging first**
3. **Monitor disk space regularly**
4. **Review logs weekly**
5. **Keep secrets secure**
6. **Update regularly**
7. **Test disaster recovery**

## 📈 Scaling

### Vertical Scaling

Adjust resource limits in `docker-compose.production.yml`:
```yaml
deploy:
  resources:
    limits:
      cpus: '4'
      memory: 4G
```

### Horizontal Scaling

For high traffic, consider:
- Multiple VMs with load balancer
- Managed PostgreSQL (RDS, Cloud SQL)
- Managed Redis (ElastiCache)
- Object storage (S3, GCS)
- Kubernetes deployment

## 🤝 Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create feature branch
3. Run tests: `./scripts/test.sh`
4. Ensure shellcheck passes
5. Submit pull request

## 📄 License

MIT License - See LICENSE file for details

## 🆘 Support

- [Authgear Documentation](https://docs.authgear.com/)
- [GitHub Issues](https://github.com/anaryk/authgear-example-docker-compose/issues)
- [Authgear Discord](https://discord.gg/authgear)

## ✅ Production Checklist

Before going live:

- [ ] DNS records configured and propagated
- [ ] SSL certificates obtained (A+ rating)
- [ ] All services healthy
- [ ] Backups automated and tested
- [ ] Monitoring configured
- [ ] Firewall rules applied
- [ ] Security hardening completed
- [ ] Documentation reviewed
- [ ] Disaster recovery tested
- [ ] Performance tested
- [ ] Compliance requirements met

## 🎯 Next Steps

1. **Deploy**: Run `./scripts/install.sh`
2. **Configure DNS**: Set up domain records
3. **Set Up Proxy**: Configure reverse proxy
4. **Create Admin**: Access portal and create account
5. **Configure Backups**: Set up cron job
6. **Enable Monitoring**: Set up alerts
7. **Test Everything**: Run full test suite

---

**Made with ❤️ for production deployments**

For detailed instructions, see the [Deployment Guide](./docs/DEPLOYMENT.md).
