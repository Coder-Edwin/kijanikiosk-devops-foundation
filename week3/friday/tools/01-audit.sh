#!/usr/bin/env bash
# Pre-provisioning audit. Run BEFORE the provisioning script, on the dirty VM.
# Writes ../pre-provisioning-audit.txt: the brief's audit commands verbatim,
# a few extra probes the script also relies on, and an interpretation section
# generated from what was actually found (review and edit it before committing).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
OUT=pre-provisioning-audit.txt
[[ $EUID -eq 0 ]] || { echo "Run with sudo: sudo $0"; exit 2; }

run() { printf '\n$ %s\n' "$*"; bash -c "$*" 2>&1; printf '(exit %s)\n' "$?"; }

{
echo "KijaniKiosk pre-provisioning audit"
echo "Host: $(hostname)   Date: $(date -Is)   Kernel: $(uname -r)"
echo "OS: $(. /etc/os-release; echo "$PRETTY_NAME")"
echo "================================================================"
echo "Audit commands from the brief"
echo "================================================================"
run "getent passwd kk-api kk-payments kk-logs"
run "getent group kijanikiosk"
run "ls -la /opt/kijanikiosk/"
run "getfacl /opt/kijanikiosk/shared/logs/ 2>/dev/null"
run "getfacl /opt/kijanikiosk/config/ 2>/dev/null"
run "ufw status numbered"
run "apt-mark showhold"
run "systemctl list-unit-files | grep kk-"
run "systemd-analyze security kk-api.service 2>/dev/null | head -5"
run "du -sh /opt/kijanikiosk/shared/logs/"
run "journalctl --disk-usage"
echo
echo "================================================================"
echo "Extra probes used by the provisioning script"
echo "================================================================"
run "id kk-api; id kk-payments; id kk-logs"
run "dpkg-query -W -f='\${Package} \${Version} \${Status}\n' nginx curl acl ufw logrotate python3"
run "ls -la /etc/kijanikiosk/ 2>/dev/null || echo 'no /etc/kijanikiosk'"
run "ls -la /etc/systemd/system/kk-*.service /etc/systemd/system/kk-*.service.d 2>/dev/null"
run "ls -la /etc/logrotate.d/kijanikiosk 2>/dev/null && cat /etc/logrotate.d/kijanikiosk"
run "ls -la /opt/kijanikiosk/shared/logs/ /opt/kijanikiosk/config/ 2>/dev/null"
run "test -d /var/log/journal && echo 'journal: persistent dir exists' || echo 'journal: volatile (no /var/log/journal)'"
} > "$OUT"

# ---------------- Interpretation (generated from the findings) -------------
notes=()
for u in kk-api kk-payments kk-logs; do
  if id "$u" &>/dev/null; then
    shell="$(getent passwd "$u" | cut -d: -f7)"; home="$(getent passwd "$u" | cut -d: -f6)"
    extra=""; [[ "$shell" != /usr/sbin/nologin ]] && extra+=", login shell ${shell}"
    [[ "$home" != /nonexistent ]] && extra+=", home ${home}"
    notes+=("D1: ${u} already exists (UID $(id -u "$u")${extra}): handled in Phase 3 by id check, parameters converged with usermod")
  fi
done
if [[ -d /opt/kijanikiosk/config ]]; then
  m="$(stat -c '%a %U:%G' /opt/kijanikiosk/config)"
  [[ "$m" != "750 root:kijanikiosk" ]] && notes+=("D2: /opt/kijanikiosk/config is ${m} (spec 750 root:kijanikiosk): fixed in Phase 4")
fi
if [[ -d /opt/kijanikiosk/shared/logs ]]; then
  getfacl -p /opt/kijanikiosk/shared/logs 2>/dev/null | grep -q '^user:kk-payments:' \
    || notes+=("D2: /opt/kijanikiosk/shared/logs ACL has no kk-payments entry: fixed in Phase 4")
  getfacl -p /opt/kijanikiosk/shared/logs 2>/dev/null | grep -q '^default:' \
    || notes+=("D2: /opt/kijanikiosk/shared/logs has no default ACL, so new files (logrotate) would not inherit access: fixed in Phase 4")
fi
[[ -f /etc/logrotate.d/kijanikiosk ]] && notes+=("D3: hand-edited /etc/logrotate.d/kijanikiosk present: compared, backed up and replaced in Phase 7")
if ufw status | grep -q '^Status: active'; then
  n="$(ufw status numbered | grep -c '^\[')"
  ufw status numbered | grep -E '^\[' | grep -vq '#' && c=" (some without comments)" || c=""
  notes+=("D4: ufw active with ${n} hand-made rule(s)${c}: reset to baseline and rebuilt from intent in Phase 5")
fi
h="$(apt-mark showhold | xargs)"
[[ -n "$h" ]] && notes+=("D5: package holds present (${h}): versions compared with pins in Phase 2, holds re-asserted")
for p in nginx curl; do
  v="$(dpkg-query -W -f='${Version}' "$p" 2>/dev/null)"; [[ -n "$v" ]] && notes+=("D5: ${p} installed at ${v}: compared with the pin before any install (Phase 2)")
done
for s in kk-api kk-payments kk-logs; do
  [[ -f /etc/systemd/system/${s}.service ]] && notes+=("D6: ${s}.service exists from an earlier lab: compared with the inline unit, replaced if different (Phase 6)")
  [[ -d /etc/systemd/system/${s}.service.d ]] && notes+=("D6: ${s}.service.d drop-in overrides present: backed up and removed (Phase 6)")
done
[[ -d /etc/kijanikiosk ]] && notes+=("Challenge A: config files under /etc/kijanikiosk: backed up and removed, single source is /opt/kijanikiosk/config (Phase 4)")
[[ -d /var/log/journal ]] || notes+=("Journal is volatile (no /var/log/journal): made persistent, capped at 500M (Phase 7)")

{
echo
echo "================================================================"
echo "Interpretation: dirty conditions found (copied to the top of the script)"
echo "================================================================"
echo "# Expected dirty conditions found in pre-provisioning audit:"
if ((${#notes[@]})); then printf '# - %s\n' "${notes[@]}"; else echo "# - none detected: the VM looks clean; run tools/simulate-dirty-state.sh first"; fi
} >> "$OUT"

echo "Wrote $(pwd)/${OUT}"
tail -n $(( ${#notes[@]} + 2 )) "$OUT"
echo
echo "SCREENSHOT NOW: this terminal (dirty state before the script runs)."
