#!/usr/bin/env bash
# Run the provisioning script and keep a timestamped log of the run.
#   sudo tools/02-run-provision.sh dirty   -> provision-run-dirty.log
#   sudo tools/02-run-provision.sh clean   -> provision-run-clean.log (run immediately after)
# Extra variables (KK_ADMIN_CIDR, KK_PIN_NGINX, ...) are passed through.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
[[ $EUID -eq 0 ]] || { echo "Run with sudo: sudo -E $0 dirty|clean"; exit 2; }
kind="${1:-}"; [[ "$kind" == dirty || "$kind" == clean ]] || { echo "usage: $0 dirty|clean"; exit 2; }
LOG="provision-run-${kind}.log"

{
  echo "# KijaniKiosk provisioning run (${kind} VM)  host=$(hostname)  started=$(date -Is)"
  echo "# command: sudo ./kijanikiosk-provision.sh"
} > "$LOG"
KK_OPERATOR_USER="${KK_OPERATOR_USER:-${SUDO_USER:-}}" ./kijanikiosk-provision.sh 2>&1 | tee -a "$LOG"
rc=${PIPESTATUS[0]}
echo "# finished=$(date -Is)  EXIT CODE: ${rc}" | tee -a "$LOG"
[[ "$kind" == dirty ]] && echo "SCREENSHOT NOW: the verification summary above (all checks passing on the dirty VM)."
exit "$rc"
