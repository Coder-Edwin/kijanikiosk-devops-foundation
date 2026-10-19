#!/usr/bin/env bash
# Brings up Jenkins + Nexus on the VM and configures Nexus for the pipeline.
# Idempotent: safe to re-run. Usage: sudo week5/friday/tools/setup-ci-stack.sh
set -euo pipefail

INFRA="$(cd "$(dirname "$0")/../infra" && pwd)"
SECRETS="${INFRA}/secrets"
NEXUS="http://localhost:8081"
REPO="npm-kijanikiosk"
NODE_IMAGE="node:22.23.3-alpine3.24"   # same pinned image the Jenkinsfile uses

say()  { printf '\n==> %s\n' "$*"; }
ok()   { printf '    OK   %s\n' "$*"; }
fail() { printf '    FAIL %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || fail "run with sudo"
command -v docker >/dev/null || fail "Docker is not installed"

say "1. Docker Compose plugin"
if docker compose version >/dev/null 2>&1; then ok "$(docker compose version)"
else apt-get update -qq && apt-get install -y -qq docker-compose-v2 && ok "installed docker-compose-v2"; fi

say "2. Secrets (generated once, never committed: infra/secrets is git-ignored)"
mkdir -p "$SECRETS"; chmod 700 "$SECRETS"
for s in jenkins_admin_password nexus_admin_password nexus_ci_password; do
  if [[ -s "${SECRETS}/${s}" ]]; then ok "${s} already exists"
  else openssl rand -base64 24 | tr -d '/+=\n' > "${SECRETS}/${s}"; ok "generated ${s}"; fi
done
chmod 600 "${SECRETS}"/*
# Readable by the Jenkins container user (uid 1000) through the compose secret mount.
chown 1000:1000 "${SECRETS}/jenkins_admin_password" "${SECRETS}/nexus_ci_password"
printf 'DOCKER_GID=%s\n' "$(getent group docker | cut -d: -f3)" > "${INFRA}/.env"
ok "DOCKER_GID=$(getent group docker | cut -d: -f3) written to infra/.env"

say "3. Firewall: let Docker containers (the pipeline's agents) reach Nexus on the host"
if command -v ufw >/dev/null && ufw status | grep -q '^Status: active'; then
  if ufw status | grep -q '8081/tcp.*172.16.0.0/12'; then ok "rule already present"
  else ufw allow from 172.16.0.0/12 to any port 8081 proto tcp comment 'Docker agents -> Nexus (CI publish)' >/dev/null; ok "allowed 172.16.0.0/12 -> 8081/tcp"; fi
else ok "ufw inactive: nothing to do"; fi

say "4. Start the stack"
docker compose -f "${INFRA}/docker-compose.yml" --project-directory "$INFRA" up -d --build
ok "containers started"

say "5. Wait for Nexus (first start takes 2-4 minutes)"
for _ in $(seq 1 90); do
  [[ "$(curl -s -o /dev/null -w '%{http_code}' "${NEXUS}/service/rest/v1/status")" == 200 ]] && break
  sleep 5
done
[[ "$(curl -s -o /dev/null -w '%{http_code}' "${NEXUS}/service/rest/v1/status")" == 200 ]] || fail "Nexus did not come up"
ok "Nexus is up"

ADMIN_PW="$(cat "${SECRETS}/nexus_admin_password")"
CI_PW="$(cat "${SECRETS}/nexus_ci_password")"
if docker exec kk-nexus test -f /nexus-data/admin.password; then
  INITIAL="$(docker exec kk-nexus cat /nexus-data/admin.password)"
  curl -sf -u "admin:${INITIAL}" -X PUT -H 'Content-Type: text/plain' \
       --data "${ADMIN_PW}" "${NEXUS}/service/rest/v1/security/users/admin/change-password"
  docker exec kk-nexus rm -f /nexus-data/admin.password
  ok "Nexus admin password changed from the one-time initial password"
else
  ok "Nexus admin password already set"
fi
api() { curl -sf -u "admin:${ADMIN_PW}" -H 'Content-Type: application/json' "$@"; }

say "6. Configure Nexus"
# Community Edition asks for the EULA to be accepted once.
if eula="$(api "${NEXUS}/service/rest/v1/system/eula" 2>/dev/null)"; then
  if grep -q '"accepted" *: *false' <<<"$eula"; then
    api -X POST "${NEXUS}/service/rest/v1/system/eula" \
        --data "$(sed 's/"accepted" *: *false/"accepted": true/' <<<"$eula")" && ok "EULA accepted"
  else ok "EULA already accepted"; fi
fi
api -X PUT "${NEXUS}/service/rest/v1/security/anonymous" \
    --data '{"enabled":false,"userId":"anonymous","realmName":"NexusAuthorizingRealm"}' >/dev/null && ok "anonymous access disabled"
active="$(api "${NEXUS}/service/rest/v1/security/realms/active")"
if grep -q NpmToken <<<"$active"; then ok "npm realm already active"
else api -X PUT "${NEXUS}/service/rest/v1/security/realms/active" \
         --data "$(python3 -c 'import json,sys; r=json.loads(sys.argv[1]); r.append("NpmToken"); print(json.dumps(r))' "$active")" \
       && ok "npm Bearer Token realm activated"; fi

if api "${NEXUS}/service/rest/v1/repositories/${REPO}" >/dev/null 2>&1; then ok "repository ${REPO} exists"
else
  # allow_once: a version can be published exactly once. Re-publishing the
  # same version is rejected, which is how version uniqueness is enforced.
  api -X POST "${NEXUS}/service/rest/v1/repositories/npm/hosted" --data "{
    \"name\": \"${REPO}\", \"online\": true,
    \"storage\": {\"blobStoreName\": \"default\", \"strictContentTypeValidation\": true, \"writePolicy\": \"allow_once\"}
  }" && ok "created npm hosted repository ${REPO} (write policy: allow once)"
fi

if api "${NEXUS}/service/rest/v1/security/roles/kk-ci-publish" >/dev/null 2>&1; then ok "role kk-ci-publish exists"
else
  api -X POST "${NEXUS}/service/rest/v1/security/roles" --data "{
    \"id\": \"kk-ci-publish\", \"name\": \"kk-ci-publish\",
    \"description\": \"CI may publish to and read ${REPO}, nothing else\",
    \"privileges\": [\"nx-repository-view-npm-${REPO}-add\", \"nx-repository-view-npm-${REPO}-edit\",
                     \"nx-repository-view-npm-${REPO}-read\", \"nx-repository-view-npm-${REPO}-browse\"],
    \"roles\": []
  }" >/dev/null && ok "created least-privilege role kk-ci-publish"
fi

if api "${NEXUS}/service/rest/v1/security/users?userId=ci-publisher" | grep -q '"userId" *: *"ci-publisher"'; then
  ok "user ci-publisher exists"
else
  api -X POST "${NEXUS}/service/rest/v1/security/users" --data "{
    \"userId\": \"ci-publisher\", \"firstName\": \"CI\", \"lastName\": \"Publisher\",
    \"emailAddress\": \"ci-publisher@kijanikiosk.local\", \"password\": \"${CI_PW}\",
    \"status\": \"active\", \"roles\": [\"kk-ci-publish\"]
  }" >/dev/null && ok "created user ci-publisher (role kk-ci-publish)"
fi

say "7. Integration Challenge A: can a Docker container reach Nexus on the host?"
code="$(docker run --rm "$NODE_IMAGE" node -e \
  "fetch('http://172.17.0.1:8081/service/rest/v1/status').then(r=>console.log(r.status)).catch(e=>console.log('ERR '+e.cause?.code))")"
if [[ "$code" == 200 ]]; then ok "from inside ${NODE_IMAGE}: http://172.17.0.1:8081 -> HTTP 200"
else fail "container cannot reach Nexus at 172.17.0.1:8081 (${code}). Check ufw and the Docker bridge address."; fi
code="$(docker run --rm "$NODE_IMAGE" node -e \
  "fetch('http://localhost:8081/service/rest/v1/status').then(r=>console.log(r.status)).catch(e=>console.log('ERR '+(e.cause?.code||e.message)))")"
ok "for comparison, localhost:8081 from inside the container -> ${code} (expected ERR ECONNREFUSED)"

say "8. Wait for Jenkins"
for _ in $(seq 1 60); do
  [[ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/login)" == 200 ]] && break
  sleep 5
done
[[ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/login)" == 200 ]] || fail "Jenkins did not come up"
ok "Jenkins is up"

cat <<EOF

Ready.
  Jenkins: http://localhost:8080   user: admin   password: sudo cat ${SECRETS}/jenkins_admin_password
  Nexus:   http://localhost:8081   user: admin   password: sudo cat ${SECRETS}/nexus_admin_password
  Pipeline job: kijanikiosk-ci (polls GitHub every 2 minutes; "Build Now" starts it at once)
EOF
