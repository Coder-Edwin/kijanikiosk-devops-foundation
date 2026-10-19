#!/usr/bin/env bash
# OPTIONAL. Only for a VM that was reset or rebuilt this week.
# Recreates the kind of hand-made state the brief describes, so the
# provisioning script is tested against a dirty server, not a clean one.
# Every change is applied unconditionally, so it also re-dirties a VM the
# provisioning script has already converged.
# Say so in the PR if you used it: the brief allows simulation, it does not
# allow pretending the state was organic.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with sudo"; exit 2; }
echo "Simulating Tuesday-Thursday hand-made state..."

# The tools the hand-made state needs (a fresh desktop install may lack them).
for p in acl ufw; do
  dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'install ok installed' || apt-get install -y -qq "$p"
done

# usermod refuses to change accounts that are running processes.
systemctl stop kk-payments kk-api kk-logs 2>/dev/null || true

# D1: accounts created by hand with the wrong parameters
getent group kijanikiosk >/dev/null || groupadd kijanikiosk
id kk-api &>/dev/null      || useradd --system kk-api
id kk-payments &>/dev/null || useradd --system kk-payments
id kk-logs &>/dev/null     || useradd --system kk-logs
usermod --shell /bin/bash --home /home/kk-api kk-api          # login shell + home
usermod --groups "" --home /home/kk-payments kk-payments      # not in kijanikiosk
usermod --groups kijanikiosk,adm kk-logs                      # extra group

# D2: permissions set loosely, ACL missing the kk-payments entry and no defaults
mkdir -p /opt/kijanikiosk/{config,shared/logs}
chmod 777 /opt/kijanikiosk/config
setfacl -b /opt/kijanikiosk/shared/logs
setfacl -m u:kk-api:rwx /opt/kijanikiosk/shared/logs
echo "old" >> /opt/kijanikiosk/shared/logs/kk-api.log
chown root:root /opt/kijanikiosk/shared/logs/kk-api.log
chmod 644 /opt/kijanikiosk/shared/logs/kk-api.log

# Challenge A: config created under /etc during the week
mkdir -p /etc/kijanikiosk && echo "SERVICE_PORT=3001" > /etc/kijanikiosk/payments-api.env

# D3: Thursday's hand-fixed logrotate config
cat > /etc/logrotate.d/kijanikiosk <<'CONF'
/opt/kijanikiosk/shared/logs/*.log {
    weekly
    rotate 4
    create 0640 root root
}
CONF

# D4: ufw edited by hand twice (rules without comments, appended to history)
ufw allow 22/tcp >/dev/null
ufw allow 80/tcp >/dev/null
ufw deny 3001 >/dev/null
ufw --force enable >/dev/null

# D5: a hold set outside the provisioning script, and a pinned package's hold lost
apt-mark hold curl >/dev/null
dpkg-query -W nginx >/dev/null 2>&1 && apt-mark unhold nginx >/dev/null || true

# D6: Wednesday's weaker unit plus a drop-in override
cat > /etc/systemd/system/kk-api.service <<'UNIT'
[Unit]
Description=kk-api (Wednesday lab)
[Service]
User=kk-api
ExecStart=/usr/bin/python3 -m http.server 3000
NoNewPrivileges=yes
[Install]
WantedBy=multi-user.target
UNIT
mkdir -p /etc/systemd/system/kk-api.service.d
printf '[Service]\nProtectSystem=no\n' > /etc/systemd/system/kk-api.service.d/override.conf
systemctl daemon-reload
echo "Done. Now run: sudo tools/01-audit.sh"
