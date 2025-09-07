# Xray Multi-Path SSH WebSocket Setup

## Nginx Configuration

```nginx
server {
    listen 80;
    listen [::]:80;
    listen 443 ssl http2 reuseport;
    listen [::]:443 http2 reuseport;
    server_name test.pikai.me;
    
    ssl_certificate /etc/xray/xray.crt;
    ssl_certificate_key /etc/xray/xray.key;
    ssl_ciphers EECDH+CHACHA20:EECDH+CHACHA20-draft:EECDH+ECDSA+AES128:EECDH+aRSA+AES128:RSA+AES128:EECDH+ECDS$;
    ssl_protocols TLSv1.1 TLSv1.2 TLSv1.3;
    
    root /home/vps/public_html;
    
    location / {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:700;
        proxy_http_version 1.1;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $http_host;
    }
}
```

## Python 2.7.16 Installation
```bash
apt update -y
apt install python-2.7
```

## Dropbear SSH Setup

### Install Dropbear
```bash
sudo apt-get update
sudo apt-get install dropbear
```

## Setup Checklist

1. ✅ **Install Dropbear**
2. ✅ **Install Python 2.7.18**
3. ✅ **Configure Dropbear**
   - Set `NO_START=0`
   - Set `DROPBEAR_PORT=69`
4. ✅ **Restart Dropbear Service**
5. ✅ **Setup WS-Stunnel**
   - Download ws-stunnel
   - Run with `python -O ws-stunnel`
   - Create systemd service at `/etc/systemd/system/ws-stunnel.service`

## Important Notes

> **Configuration:** Use new xray.conf with `/` pointing to `::700`
