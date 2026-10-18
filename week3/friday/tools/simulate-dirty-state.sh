#!/usr/bin/env bash
# OPTIONAL. Only for a VM that was reset or rebuilt this week.
# Recreates the kind of hand-made state the brief describes, so the
# provisioning script is tested against a dirty server, not a clean one.
# Say so in the PR if you used it: the brief allows simulation, it does not
# allow pretending the state was organic.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with sudo"; exit 2; }
echo "Simulating Tuesday-Thursday hand-made state..."

# D1: accounts created by hand with the wrong parameters
getent group kijanikiosk >/dev/null || groupadd kijanikiosk
id kk-api &>/dev/null      || useradd --system --shell /bin/bash --create-home kk-api        # login shell + home
id kk-payments &>/dev/null || useradd --system --shell /usr/sbin/nologin kk-payments          # not in kijanikiosk
id kk-logs &>/dev/null     || useradd --system --shell /usr/sbin/nologin -G kijanikiosk,adm kk-logs  # extra group

# D2: permissions set loosely, ACL missing the kk-payments entry and no defaults
mkdir -p /opt/kijanikiosk/{config,shared/logs}
chmod 777 /opt/kijanikiosk/config
setfacl -m u:kk-api:rwx /opt/kijanikiosk/shared/logs
echo "old" > /opt/kijanikiosk/shared/logs/kk-api.log

# Challenge A: config created under /etc during the week
mkdir -p /etc/kijanikiosk && echo "SERVICE_PORT=3001" > /etc/kijanikiosk/payments-api.env

# D3: Thursday's hand-fixed logrotate config
cat > /etc/logrotate.d/kijanikiosk <<'EOF'
/opt/kijanikiosk/shared/logs/*.log {
    weekly
    rotate 4
    create 0640 root root
}
EOF

# D4: ufw edited by hand twice
ufw allow 22/tcp >/dev/null
ufw allow 80/tcp >/dev/null
ufw deny 3001 >/dev/null
ufw --force enable >/dev/null

# D5: a hold set outside the provisioning script
apt-mark hold curl >/dev/null

# D6: Wednesday's weaker unit plus a drop-in override
cat > /etc/systemd/system/kk-api.service <<'EOF'
[Unit]
Description=kk-api (Wednesday lab)
[Service]
User=kk-api
ExecStart=/usr/bin/python3 -m http.server 3000
NoNewPrivileges=yes
[Install]
WantedBy=multi-user.target
EOF
mkdir -p /etc/systemd/system/kk-api.service.d
printf '[Service]\nProtectSystem=no\n' > /etc/systemd/system/kk-api.service.d/override.conf
systemctl daemon-reload
echo "Done. Now run: sudo tools/01-audit.sh"
