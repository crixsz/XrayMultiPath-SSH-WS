#!/bin/bash
DOMAIN=$(cat /root/.acme_domain 2>/dev/null)
if [ -z "$DOMAIN" ]; then
    echo "$(date): No domain found in /root/.acme_domain" >> /root/.acme_renew.log
    exit 1
fi

echo "$(date): Starting renewal for $DOMAIN" >> /root/.acme_renew.log

systemctl stop nginx 2>/dev/null

if /root/.acme.sh/acme.sh --renew -d "$DOMAIN" --force >> /root/.acme_renew.log 2>&1; then
    echo "$(date): Renewal successful" >> /root/.acme_renew.log
else
    echo "$(date): Renewal failed" >> /root/.acme_renew.log
fi

systemctl start nginx 2>/dev/null
