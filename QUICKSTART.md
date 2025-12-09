# ⚡ Quick Start Guide

Rychlý návod pro deployment Authgear v produkci.

## 📋 Před začátkem

- [ ] VM s Ubuntu 22.04, 8GB RAM, 4 CPU cores
- [ ] Proxy server s veřejnou IP
- [ ] Doména maximal-limit.cz
- [ ] Přístup k DNS správě

## 🚀 Deployment v 5 krocích

### 1️⃣ Instalace na VM (10 min)

```bash
# Clone repository
git clone https://github.com/anaryk/authgear-example-docker-compose.git
cd authgear-example-docker-compose

# Spustit instalaci
chmod +x scripts/*.sh
./scripts/install.sh
```

Script se zeptá na:
- Auth domain (např. `auth.maximal-limit.cz`)
- Portal domain (např. `portal.maximal-limit.cz`)

Pak automaticky:
- ✅ Vygeneruje hesla
- ✅ Vytvoří .env soubor
- ✅ Nastaví Docker
- ✅ Spustí služby

### 2️⃣ Konfigurace DNS (5-60 min)

V DNS správě pro `maximal-limit.cz` přidat:

```dns
auth.maximal-limit.cz    A    <PROXY_SERVER_PUBLIC_IP>
portal.maximal-limit.cz  A    <PROXY_SERVER_PUBLIC_IP>
```

Ověření:
```bash
dig auth.maximal-limit.cz +short
```

### 3️⃣ Setup Proxy Serveru (15 min)

Na proxy serveru:

```bash
# Instalace
sudo apt update && sudo apt install -y nginx certbot python3-certbot-nginx

# Získat config
wget https://raw.githubusercontent.com/anaryk/authgear-example-docker-compose/main/proxy-server-nginx.conf

# Upravit IP VM a porty
sudo nano proxy-server-nginx.conf

# ⚠️ DŮLEŽITÉ - Nastavit správné porty:
# Změnit YOUR_VM_LOCAL_IP na IP vašeho VM (např. 192.168.1.100)
# 
# Auth doména (auth.maximal-limit.cz):
#   upstream authgear_vm_auth {
#       server 192.168.1.100:3100;  ← Port 3100 pro AUTH
#   }
#
# Portal doména (portal.maximal-limit.cz):
#   upstream authgear_vm_portal {
#       server 192.168.1.100:8010;  ← Port 8010 pro PORTAL
#   }

# Zkopírovat config
sudo cp proxy-server-nginx.conf /etc/nginx/sites-available/authgear
sudo ln -s /etc/nginx/sites-available/authgear /etc/nginx/sites-enabled/
sudo rm /etc/nginx/sites-enabled/default

# Získat SSL certifikáty
sudo certbot --nginx \
  -d auth.maximal-limit.cz \
  -d portal.maximal-limit.cz \
  --email admin@maximal-limit.cz

# Restart Nginx
sudo nginx -t && sudo systemctl reload nginx
```

### 4️⃣ Verifikace (2 min)

```bash
# Na VM - health check
cd /path/to/authgear-example-docker-compose
./scripts/health-check.sh

# Z internetu - test přístupu
curl -I https://auth.maximal-limit.cz
curl -I https://portal.maximal-limit.cz

# SSL test
# Otevřít https://www.ssllabs.com/ssltest/
# Zadat auth.maximal-limit.cz
# Mělo by být A+
```

### 5️⃣ První přihlášení (5 min)

1. Otevřít `https://portal.maximal-limit.cz`
2. Vytvořit admin účet
3. Konfigurovat Authgear projekt

## 🔧 Post-Installation

### Automatické zálohy

```bash
# Přidat do crontab
crontab -e

# Přidat řádek (backup každý den ve 2:00)
0 2 * * * /path/to/authgear-example-docker-compose/scripts/backup.sh
```

### Security Hardening

```bash
# Firewall na VM
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow from <PROXY_SERVER_IP> to any port 3100
sudo ufw allow from <PROXY_SERVER_IP> to any port 8010
sudo ufw enable

# Fail2ban na proxy serveru
sudo apt install -y fail2ban
sudo systemctl enable fail2ban
```

### Monitoring

```bash
# Přidat health check monitoring
crontab -e

# Health check každých 15 minut
*/15 * * * * /path/to/scripts/health-check.sh || echo "Health check failed" | mail -s "Alert" admin@example.com
```

## 📊 Ověření deployment

### Checklist

- [ ] Všechny Docker kontejnery běží: `docker compose ps`
- [ ] Health check projde: `./scripts/health-check.sh`
- [ ] HTTPS funguje: `curl -I https://auth.maximal-limit.cz`
- [ ] SSL A+ rating: SSL Labs test
- [ ] Portal dostupný: `https://portal.maximal-limit.cz`
- [ ] Admin účet vytvořen
- [ ] Backup skript funguje: `./scripts/backup.sh`
- [ ] Firewall nakonfigurován: `sudo ufw status`

## 🆘 Řešení problémů

### Služby se nespustí

```bash
# Zobrazit logy
docker compose -f docker-compose.production.yml logs

# Restartovat vše
docker compose -f docker-compose.production.yml restart
```

### Nedostupný z internetu

1. Zkontrolovat DNS: `dig auth.maximal-limit.cz`
2. Zkontrolovat firewall na proxy: `sudo ufw status`
3. Zkontrolovat Nginx: `sudo nginx -t && sudo systemctl status nginx`
4. Zkontrolovat connectivity proxy -> VM: `ping <VM_IP>`

### SSL chyby

```bash
# Na proxy serveru - zkontrolovat certifikáty
sudo certbot certificates

# Obnovit manuálně
sudo certbot renew

# Zkontrolovat Nginx config
sudo nginx -t
```

## 📚 Další kroky

1. Přečíst kompletní dokumentaci: `docs/DEPLOYMENT.md`
2. Nakonfigurovat monitoring
3. Otestovat disaster recovery
4. Nastavit alerting
5. Zkontrolovat compliance požadavky

## 🎯 Užitečné příkazy

```bash
# Update celého stacku
./scripts/update.sh

# Manuální backup
./scripts/backup.sh

# Health check
./scripts/health-check.sh

# Zobrazit logy
docker compose -f docker-compose.production.yml logs -f [service_name]

# Restartovat službu
docker compose -f docker-compose.production.yml restart [service_name]

# Zastavit vše
docker compose -f docker-compose.production.yml down

# Nastartovat vše
docker compose -f docker-compose.production.yml up -d
```

## 💡 Tipy

1. **Backups**: Testujte restore pravidelně
2. **Monitoring**: Nastavte alerty
3. **Updates**: Dělejte v maintenance window
4. **Logs**: Kontrolujte pravidelně
5. **Security**: Aktualizujte systém týdně

## ⏱️ Odhadovaný čas

- **Instalace VM**: 10 minut
- **DNS propagace**: 5-60 minut
- **Proxy setup**: 15 minut
- **Verifikace**: 5 minut
- **Konfigurace**: 10 minut

**Celkem: ~1-2 hodiny** (včetně DNS propagace)

---

**Ready to go! 🚀**

Pro detailní informace viz [DEPLOYMENT.md](docs/DEPLOYMENT.md)
