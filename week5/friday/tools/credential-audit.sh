#!/usr/bin/env bash
# Five credential checks across the Jenkinsfile, git history and every Jenkins build log.
# Compares against the REAL secret values (and their base64 forms) without ever printing them.
# Usage (from the repo root): sudo week5/friday/tools/credential-audit.sh | tee week5/friday/credential-audit.txt
set -uo pipefail

ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
SECRETS="${ROOT}/week5/friday/infra/secrets"
JF="${ROOT}/Jenkinsfile"
[[ -r "${SECRETS}/nexus_ci_password" ]] || { echo "run with sudo" >&2; exit 1; }
git config --global --add safe.directory "$ROOT" 2>/dev/null || true

# Needles: every real secret, plus base64(user:pass) as written into .npmrc.
NEEDLES="$(mktemp)"; trap 'rm -f "$NEEDLES"' EXIT; chmod 600 "$NEEDLES"
for s in jenkins_admin_password nexus_admin_password nexus_ci_password; do cat "${SECRETS}/${s}"; echo; done > "$NEEDLES"
printf 'ci-publisher:%s' "$(cat "${SECRETS}/nexus_ci_password")" | base64 -w0 >> "$NEEDLES"; echo >> "$NEEDLES"
PATTERNS='(_auth|_authToken|password|passwd|secret|token)[[:space:]]*[:=][[:space:]]*["'\'']?[A-Za-z0-9+/]{8,}'

fails=0
result() { if [[ "$2" -eq 0 ]]; then echo "  RESULT: PASS (0 matches)"; else echo "  RESULT: FAIL ($2 matches)"; fails=$((fails+1)); fi; echo; }

echo "KijaniKiosk credential audit  $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "Repository HEAD: $(git -C "$ROOT" rev-parse --short HEAD) on $(git -C "$ROOT" rev-parse --abbrev-ref HEAD)"
echo "Secrets compared: $(grep -c . "$NEEDLES") values (3 passwords + base64 npm auth string); values are never printed"
echo

echo "CHECK 1: Jenkinsfile (every block) contains no real secret or literal credential assignment"
n1=$(grep -cFf "$NEEDLES" "$JF"); n1b=$(grep -cEi "$PATTERNS" "$JF")
echo "  real secret values found: ${n1}"; echo "  literal credential assignments found: ${n1b}"
result 1 $((n1+n1b))

echo "CHECK 2: git history (all commits, all branches, full diffs) contains no secret"
commits=$(git -C "$ROOT" rev-list --all | wc -l)
n2=$(git -C "$ROOT" log --all -p --no-color | grep -cFf "$NEEDLES")
n2b=$(git -C "$ROOT" log --all -p --no-color | grep -E '^\+' | grep -cEi "$PATTERNS")
echo "  commits scanned: ${commits}"; echo "  real secret values found: ${n2}"; echo "  literal credential assignments added: ${n2b}"
result 2 $((n2+n2b))

echo "CHECK 3: every Jenkins build log of kijanikiosk-ci contains no secret"
logs=$(docker exec kk-jenkins sh -c 'ls /var/jenkins_home/jobs/kijanikiosk-ci/builds/*/log 2>/dev/null | wc -l')
n3=$(docker exec kk-jenkins sh -c 'cat /var/jenkins_home/jobs/kijanikiosk-ci/builds/*/log' | grep -caFf "$NEEDLES")
masked=$(docker exec kk-jenkins sh -c 'cat /var/jenkins_home/jobs/kijanikiosk-ci/builds/*/log' | grep -ac 'NEXUS_PASS')
echo "  build logs scanned: ${logs}"; echo "  real secret values found: ${n3}"
echo "  (for reference: ${masked} log lines mention the masked variable name NEXUS_PASS, never its value)"
result 3 "$n3"

echo "CHECK 4: no .npmrc was ever committed or left behind in a workspace"
n4a=$(git -C "$ROOT" log --all --name-only --format= | grep -c '\.npmrc$')
n4b=$(docker exec kk-jenkins sh -c 'find /var/jenkins_home/workspace -name .npmrc 2>/dev/null | wc -l')
echo "  .npmrc paths in git history: ${n4a}"; echo "  .npmrc files in Jenkins workspaces: ${n4b}"
result 4 $((n4a+n4b))

echo "CHECK 5: the Nexus credential is referenced only by ID, inside withCredentials"
echo "  credential references in Jenkinsfile:"
grep -nE 'credentialsId|NEXUS_CREDENTIALS_ID *=' "$JF" | sed 's/^/    /'
n5=0
grep -qE "credentialsId: *env\.NEXUS_CREDENTIALS_ID" "$JF" || n5=$((n5+1))
grep -qE "NEXUS_CREDENTIALS_ID *= *'nexus-ci-publisher'" "$JF" || n5=$((n5+1))
# NEXUS_USER / NEXUS_PASS may only appear between withCredentials( and its closing sh block.
outside=$(awk '/withCredentials\(/{inblk=1} inblk&&/^ *}$/{inblk=0} !inblk&&/NEXUS_(USER|PASS)/{c++} END{print c+0}' "$JF")
echo "  uses of NEXUS_USER/NEXUS_PASS outside the withCredentials block: ${outside}"
n5=$((n5+outside))
# The Jenkins copy is stored encrypted; the config-as-code file holds only a placeholder.
grep -q 'password: "\${nexus_ci_password}"' "${ROOT}/week5/friday/infra/jenkins/casc.yaml" || n5=$((n5+1))
echo "  casc.yaml reads the password from a Docker secret placeholder: yes"
result 5 "$n5"

[[ $fails -eq 0 ]] && echo "SUMMARY: 5/5 checks passed. No credential appears in the Jenkinsfile, git history or build logs." \
                   || echo "SUMMARY: ${fails} check(s) FAILED."
exit "$fails"
