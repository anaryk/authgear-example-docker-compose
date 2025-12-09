# DNS Setup Guide for maximal-limit.cz

This document describes the DNS records needed for the production deployment of Authgear.

## Required DNS Records

Add the following DNS records to your domain `maximal-limit.cz`:

### A Records

Point these domains to your **proxy server's public IP address**:

```dns
auth.maximal-limit.cz.    IN    A    <PROXY_SERVER_PUBLIC_IP>
portal.maximal-limit.cz.  IN    A    <PROXY_SERVER_PUBLIC_IP>
```

Replace `<PROXY_SERVER_PUBLIC_IP>` with the actual public IP address of your proxy server.

### AAAA Records (IPv6 - Optional)

If you have IPv6 connectivity:

```dns
auth.maximal-limit.cz.    IN    AAAA    <PROXY_SERVER_PUBLIC_IPV6>
portal.maximal-limit.cz.  IN    AAAA    <PROXY_SERVER_PUBLIC_IPV6>
```

### CAA Records (Recommended for Security)

To restrict which Certificate Authorities can issue certificates for your domain:

```dns
maximal-limit.cz.    IN    CAA    0 issue "letsencrypt.org"
maximal-limit.cz.    IN    CAA    0 issuewild "letsencrypt.org"
maximal-limit.cz.    IN    CAA    0 iodef "mailto:admin@maximal-limit.cz"
```

## DNS Configuration Example

### Using Cloudflare

1. Log in to Cloudflare dashboard
2. Select your domain `maximal-limit.cz`
3. Go to **DNS** section
4. Add the following records:

| Type | Name   | Content                  | Proxy Status | TTL  |
|------|--------|--------------------------|--------------|------|
| A    | auth   | YOUR_PROXY_IP           | DNS only     | Auto |
| A    | portal | YOUR_PROXY_IP           | DNS only     | Auto |
| CAA  | @      | 0 issue "letsencrypt.org" | N/A         | Auto |

**Important**: Set Proxy Status to "DNS only" (grey cloud) during initial setup. You can enable Cloudflare proxy later if needed.

### Using Other DNS Providers

The exact steps vary by provider, but you'll need to:

1. Navigate to DNS management
2. Add two A records pointing to your proxy server IP
3. Add CAA records for Let's Encrypt
4. Wait for DNS propagation (typically 5-60 minutes)

## Verification

### Check DNS Propagation

Use these commands to verify DNS records:

```bash
# Check A records
dig auth.maximal-limit.cz +short
dig portal.maximal-limit.cz +short

# Check from multiple locations
dig @8.8.8.8 auth.maximal-limit.cz +short
dig @1.1.1.1 portal.maximal-limit.cz +short

# Check CAA records
dig maximal-limit.cz CAA +short
```

Expected output:
```
# For A records
<PROXY_SERVER_IP>

# For CAA records
0 issue "letsencrypt.org"
0 issuewild "letsencrypt.org"
```

### Online Tools

You can also use these online tools:

- [WhatsMyDNS](https://www.whatsmydns.net/) - Check global DNS propagation
- [DNS Checker](https://dnschecker.org/) - Verify DNS records worldwide
- [MXToolbox](https://mxtoolbox.com/SuperTool.aspx) - Comprehensive DNS lookup

## SSL Certificate Considerations

### Let's Encrypt Rate Limits

- **50 certificates per registered domain per week**
- **5 duplicate certificates per week**
- Use staging environment for testing to avoid hitting limits

### Wildcard Certificates (Alternative)

Instead of individual certificates, you can use a wildcard:

```dns
*.maximal-limit.cz.    IN    A    <PROXY_SERVER_PUBLIC_IP>
```

This allows `*.maximal-limit.cz` to point to your server, but requires DNS-01 challenge for Let's Encrypt.

## Troubleshooting

### DNS Not Resolving

1. Check if records are correctly added in DNS provider
2. Wait for DNS propagation (up to 48 hours, usually much faster)
3. Clear local DNS cache:
   ```bash
   # macOS
   sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
   
   # Linux
   sudo systemd-resolve --flush-caches
   
   # Windows
   ipconfig /flushdns
   ```

### Wrong IP Address Returned

1. Verify record in DNS provider dashboard
2. Check for conflicting records
3. Ensure no typos in domain names

### SSL Certificate Issues

1. Verify CAA records allow Let's Encrypt
2. Ensure A records point to correct IP
3. Check firewall allows ports 80 and 443
4. Verify ACME challenge path is accessible

## Network Architecture

```
Internet
   │
   ├─> auth.maximal-limit.cz (A record) ──┐
   │                                       │
   └─> portal.maximal-limit.cz (A record) ─┴─> Proxy Server (Public IP)
                                                      │
                                                      │ (Internal Network)
                                                      │
                                                      └─> VM (Local IP: 192.168.x.x)
                                                          ├─> Port 3100 (Auth)
                                                          └─> Port 8010 (Portal)
```

## Security Recommendations

1. **Enable DNSSEC** if your provider supports it
2. **Use CAA records** to restrict certificate issuance
3. **Consider using DANE/TLSA** records for additional security
4. **Monitor DNS changes** - set up alerts for unauthorized changes
5. **Use strong passwords** for DNS provider account
6. **Enable 2FA** on DNS provider account

## Next Steps

After DNS is configured:

1. Wait for DNS propagation
2. Set up the proxy server (see [PROXY-SETUP.md](./PROXY-SETUP.md))
3. Configure SSL certificates with Let's Encrypt
4. Test connectivity to both domains
5. Deploy the application on VM

## Support

If you encounter issues:

1. Check DNS provider documentation
2. Verify with DNS lookup tools
3. Review firewall and network settings
4. Check application logs

For Let's Encrypt issues, see: https://letsencrypt.org/docs/
