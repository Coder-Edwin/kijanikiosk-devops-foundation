#!/usr/bin/env bash
# Saves the evidence for one pipeline run: full console log + per-stage result table.
# Usage: sudo week5/friday/tools/collect-build.sh [BUILD_NUMBER|last] [label]
#   label "green" also copies the log to week5/friday/green-pipeline-run.txt
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"           # week5/friday
PW_FILE="${HERE}/infra/secrets/jenkins_admin_password"
JOB="http://localhost:8080/job/kijanikiosk-ci"
BUILD="${1:-last}"; LABEL="${2:-}"
[[ "$BUILD" == last ]] && BUILD="lastBuild"
OUT="${HERE}/evidence"; mkdir -p "$OUT"

[[ -r "$PW_FILE" ]] || { echo "run with sudo (needs ${PW_FILE})" >&2; exit 1; }
j() { curl -sf -u "admin:$(cat "$PW_FILE")" "$@"; }

NUM="$(j "${JOB}/${BUILD}/api/json?tree=number" | python3 -c 'import json,sys; print(json.load(sys.stdin)["number"])')"
while [[ "$(j "${JOB}/${NUM}/api/json?tree=building" | python3 -c 'import json,sys; print(json.load(sys.stdin)["building"])')" == True ]]; do
  echo "build #${NUM} still running..."; sleep 10
done

j "${JOB}/${NUM}/consoleText" > "${OUT}/build-${NUM}-console.txt"
j "${JOB}/${NUM}/wfapi/describe" | python3 -c '
import json, sys
d = json.load(sys.stdin)
print(f"Build #{d[\"id\"]}  result={d[\"status\"]}  total={d[\"durationMillis\"]/1000:.1f}s")
print(f"{\"Stage\":<18}{\"Result\":<16}{\"Duration\":>10}")
for s in d["stages"]:
    print(f"{s[\"name\"]:<18}{s[\"status\"]:<16}{s[\"durationMillis\"]/1000:>9.1f}s")
' | tee "${OUT}/build-${NUM}-stages.txt"

if [[ "$LABEL" == green ]]; then
  cp "${OUT}/build-${NUM}-console.txt" "${HERE}/green-pipeline-run.txt"
  echo "copied to week5/friday/green-pipeline-run.txt"
fi
chown -R "${SUDO_USER:-root}": "$OUT" "${HERE}/green-pipeline-run.txt" 2>/dev/null || true
echo "saved: week5/friday/evidence/build-${NUM}-console.txt and build-${NUM}-stages.txt"
