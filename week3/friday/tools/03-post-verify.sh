#!/usr/bin/env bash
# Post-remediation verification, run AFTER both provisioning runs.
# Writes ../post-remediation-verification.txt, including the brief's
# rotation sequence and the definitive kk-api write test (run after the
# forced rotation, not before).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
[[ $EUID -eq 0 ]] || { echo "Run with sudo: sudo $0"; exit 2; }
OUT=post-remediation-verification.txt
OPERATOR="${KK_OPERATOR_USER:-${SUDO_USER:-}}"
run() { printf '\n$ %s\n' "$*"; bash -c "$*" 2>&1; printf '(exit %s)\n' "$?"; }

{
echo "KijaniKiosk post-remediation verification   host=$(hostname)   $(date -Is)"
echo "================================================================"
echo "1. Log rotation and the access model (Requirement 3)"
echo "================================================================"
run "logrotate --force --debug /etc/logrotate.d/kijanikiosk"
run "logrotate --force /etc/logrotate.d/kijanikiosk"
run "ls -la /opt/kijanikiosk/shared/logs/"
run "getfacl /opt/kijanikiosk/shared/logs/"
run "getfacl /opt/kijanikiosk/shared/logs/kk-api.log"
echo
echo "\$ sudo -u kk-api touch /opt/kijanikiosk/shared/logs/test-write.tmp && echo PASS || echo FAIL"
sudo -u kk-api touch /opt/kijanikiosk/shared/logs/test-write.tmp \
  && echo "PASS: kk-api can write after logrotate" \
  || echo "FAIL: kk-api cannot write to shared/logs"
run "getfacl /opt/kijanikiosk/shared/logs/test-write.tmp"
rm -f /opt/kijanikiosk/shared/logs/test-write.tmp
echo
sudo -u kk-payments head -c0 /opt/kijanikiosk/shared/logs/kk-api.log \
  && echo "PASS: kk-payments can read kk-api.log after logrotate" \
  || echo "FAIL: kk-payments cannot read kk-api.log"

echo
echo "================================================================"
echo "2. Access model: getfacl for the four key directories"
echo "================================================================"
for d in /opt/kijanikiosk /opt/kijanikiosk/config /opt/kijanikiosk/shared/logs /opt/kijanikiosk/health; do run "getfacl $d"; done
run "ls -la /opt/kijanikiosk/config/"
for s in kk-api:api.env kk-payments:payments-api.env kk-logs:logs.env; do
  u="${s%%:*}"; f="/opt/kijanikiosk/config/${s##*:}"
  sudo -u "$u" cat "$f" >/dev/null 2>&1 && echo "PASS: $u can read $f" || echo "FAIL: $u cannot read $f"
done
sudo -u kk-api cat /opt/kijanikiosk/config/payments-api.env >/dev/null 2>&1 \
  && echo "FAIL: kk-api can read the payments environment file" \
  || echo "PASS: kk-api cannot read the payments environment file"

echo
echo "================================================================"
echo "3. Health check file (Phase 8, Challenge B)"
echo "================================================================"
run "ls -la /opt/kijanikiosk/health/"
if [[ -n "$OPERATOR" ]]; then
  echo "\$ sudo -u ${OPERATOR} cat /opt/kijanikiosk/health/last-provision.json   (operator account, no root)"
  sudo -u "$OPERATOR" cat /opt/kijanikiosk/health/last-provision.json && echo "PASS: ${OPERATOR} can read the health file"
fi

echo
echo "================================================================"
echo "4. Firewall (Requirement 4)"
echo "================================================================"
run "ufw status numbered"
run "ufw status verbose | head -5"
run "curl -sS -m 3 -o /dev/null -w 'loopback 3001 -> HTTP %{http_code}\n' http://localhost:3001/"
echo "External test (run from your HOST machine, not the VM; it must time out or be refused):"
echo "    curl -m 5 http://$(hostname -I | awk '{print $1}'):3001/"

echo
echo "================================================================"
echo "5. systemd hardening scores (Requirements 2 and 6)"
echo "================================================================"
for s in kk-api kk-payments kk-logs; do
  run "systemctl is-active $s; systemd-analyze security --no-pager $s.service | tail -1"
done
run "systemctl show -p After -p Wants kk-payments.service"

echo
echo "================================================================"
echo "6. Journal persistence (Phase 7)"
echo "================================================================"
run "systemd-analyze cat-config systemd/journald.conf | grep -E '^(Storage|SystemMaxUse)='"
run "journalctl --disk-usage"
run "ls -d /var/log/journal/*"
} > "$OUT" 2>&1

echo "Wrote $(pwd)/${OUT}"
grep -E '^(PASS|FAIL)' "$OUT"
cat <<'EOF'

SCREENSHOTS NOW:
  - sudo systemd-analyze security kk-payments.service   (final score below 2.5)
  - sudo systemd-analyze security kk-api.service | tail -1 ; sudo systemd-analyze security kk-logs.service | tail -1
  - getfacl /opt/kijanikiosk /opt/kijanikiosk/config /opt/kijanikiosk/shared/logs /opt/kijanikiosk/health
  - the external curl from your host timing out on port 3001
EOF
