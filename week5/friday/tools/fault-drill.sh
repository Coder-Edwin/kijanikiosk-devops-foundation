#!/usr/bin/env bash
# Runs the fault-injection drill: builds each commit in faults/drill-plan.txt, in order,
# through the real kijanikiosk-ci job, and saves the evidence for every run.
# Each fault commit is followed by a restore commit, so the pipeline returns to green after every fault.
# Usage (from the repo root, after git pull): sudo week5/friday/tools/fault-drill.sh [plan-file]
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"            # week5/friday
PLAN="${1:-${HERE}/faults/drill-plan.txt}"   # optional: another plan file
PW_FILE="${HERE}/infra/secrets/jenkins_admin_password"
JENKINS="http://localhost:8080"; JOB="${JENKINS}/job/kijanikiosk-ci"
SUMMARY="${HERE}/evidence/$(basename "$PLAN" .txt)-summary.txt"
[[ -r "$PW_FILE" ]] || { echo "run with sudo" >&2; exit 1; }
mkdir -p "${HERE}/evidence"

CJ="$(mktemp)"; trap 'rm -f "$CJ"' EXIT
AUTH=(-g -u "admin:$(cat "$PW_FILE")" -b "$CJ" -c "$CJ")
api() { curl -sf "${AUTH[@]}" "$@"; }
pyget() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }

up() { [[ "$(curl -s -o /dev/null -w '%{http_code}' "${JENKINS}/login")" == 200 ]]; }

# The job definition lives in casc.yaml. A single-file bind mount keeps the old file after git pull,
# so restart Jenkins once to load the version of the job that accepts a commit SHA.
if ! api "${JOB}/api/json?tree=property[parameterDefinitions[name]]" | grep -q GIT_REF; then
  echo "==> Loading the updated job definition (restarting Jenkins, ~1 minute)"
  docker restart kk-jenkins >/dev/null
  sleep 15; until up; do sleep 5; done; sleep 10
  api "${JOB}/api/json?tree=property[parameterDefinitions[name]]" | grep -q GIT_REF \
    || { echo "job still has no GIT_REF parameter; check: docker logs kk-jenkins | grep -i casc" >&2; exit 1; }
fi

CRUMB="$(api "${JENKINS}/crumbIssuer/api/json" | pyget 'd["crumbRequestField"]+":"+d["crumb"]')"

wait_idle() {
  while api "${JOB}/api/json?tree=builds[building]{0,3}" | grep -q '"building":true'; do
    echo "    waiting for a running build to finish..."; sleep 10
  done
}

trigger() {   # $1 = commit SHA -> prints the build number
  local loc n
  loc="$(curl -sf -D - -o /dev/null "${AUTH[@]}" -H "$CRUMB" -X POST \
          "${JOB}/buildWithParameters" --data-urlencode "GIT_REF=$1" \
        | tr -d '\r' | awk 'tolower($1)=="location:"{print $2}')"
  for _ in $(seq 1 60); do
    n="$(api "${loc}api/json" | pyget 'd["executable"]["number"] if d.get("executable") else ""')"
    [[ -n "$n" ]] && { echo "$n"; return; }
    sleep 3
  done
  echo "build for $1 never left the queue" >&2; exit 1
}

{
  echo "KijaniKiosk fault-injection drill  $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo "Each row: the commit built, the stage results Jenkins recorded, and the pipeline's own notices."
  echo
} > "$SUMMARY"

while IFS='|' read -r step kind sha what; do
  [[ -z "$step" || "$step" == \#* ]] && continue
  wait_idle
  echo "==> ${step} ${kind}: ${what} (commit ${sha:0:7})"
  n="$(trigger "$sha")"
  echo "    build #${n} started"
  out="$("${HERE}/tools/collect-build.sh" "$n")"
  log="${HERE}/evidence/build-${n}-console.txt"
  {
    echo "=== ${step} ${kind}: ${what}"
    echo "commit ${sha:0:7}, build #${n}"
    echo "$out" | grep -v '^saved:'
    grep -E 'skipped due to earlier failure|NOTIFY team|STATUS CHANGE|PUBLISHED|npm error (code|409|[0-9]+ (high|critical))|[0-9]+:[0-9]+ +error|✖ [0-9]+ problem|build output is missing|✖ failing tests|AssertionError|vulnerabilit|No artifacts found|ERROR: ' "$log" \
      | sed -E 's/^\[[^]]*\] //' | sort -u | head -20 | sed 's/^/  | /'
    echo
  } | tee -a "$SUMMARY"
done < "$PLAN"

chown -R "${SUDO_USER:-root}": "${HERE}/evidence" 2>/dev/null || true
echo "Drill complete. Summary: week5/friday/evidence/fault-drill-summary.txt"
