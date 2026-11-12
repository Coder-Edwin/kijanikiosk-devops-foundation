#!/usr/bin/env bash
# KijaniKiosk Week 8 Friday: full container delivery pipeline, end to end.
#
# Runs every requirement in order and writes the evidence files next to this
# script from real command output:
#   build-verification.txt  registry-push.txt  deploy-output.txt
#   service-output.txt      self-healing-rerun.txt  pipeline-summary.txt
#
# Usage (from anywhere inside the repo):
#   bash week8/friday/run-pipeline.sh
# Optional:
#   REGISTRY=docker.io/<user> bash week8/friday/run-pipeline.sh   # Docker Hub instead of GHCR
#   SKIP_GIT_PUSH=1 bash week8/friday/run-pipeline.sh            # do not commit/push at the end
#
# Before running: log in to the registry once (the token is typed by you,
# never written by this script):   docker login ghcr.io -u Coder-Edwin
set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

REGISTRY="${REGISTRY:-ghcr.io/coder-edwin}"
IMAGE="$REGISTRY/kk-payments"
SECRET_NAME="kijani-registry-credentials"
BRANCH="feature/week8-container-delivery"

ts()   { date '+%Y-%m-%d %H:%M:%S'; }
hdr()  { printf '\n==== %s ====\n' "$*"; }
step() { printf '\n\033[1;32m>>> %s\033[0m\n' "$*" >&2; }
fail() { printf '\n\033[1;31mSTOPPED: %s\033[0m\n' "$*" >&2; exit 1; }
# run CMD... : print the command, then its output (stdout+stderr)
run()  { printf '$ %s\n' "$*"; "$@" 2>&1; }

for tool in docker kubectl minikube git curl; do
  command -v "$tool" >/dev/null || fail "$tool is not installed"
done

# ---------------------------------------------------------------------------
step "0. Cluster and registry prerequisites"
if ! minikube status >/dev/null 2>&1; then
  minikube start
fi
kubectl config use-context minikube >/dev/null

REG_HOST="${REGISTRY%%/*}"
if ! kubectl get secret "$SECRET_NAME" >/dev/null 2>&1; then
  # Build the ImagePullSecret from your existing docker login. The credential
  # goes straight from your docker config into the cluster; it is never echoed
  # and never written to any file in this repo.
  CFG="$HOME/.docker/config.json"
  if [[ -f "$CFG" ]] && grep -q "\"$REG_HOST\"" "$CFG" && grep -q '"auth"' "$CFG"; then
    kubectl create secret generic "$SECRET_NAME" \
      --from-file=.dockerconfigjson="$CFG" \
      --type=kubernetes.io/dockerconfigjson >/dev/null
    echo "Created $SECRET_NAME from your docker login for $REG_HOST" >&2
  else
    fail "Secret $SECRET_NAME is missing and no docker login for $REG_HOST was found.
Run: docker login $REG_HOST   then re-run this script."
  fi
fi

# ---------------------------------------------------------------------------
step "Reset: clear kk-payments workloads and cached images"
RESET_LOG="$(mktemp)"
{
  hdr "Namespace reset  ($(ts))"
  run kubectl delete deployment kk-payments --ignore-not-found
  run kubectl delete service kk-payments-service --ignore-not-found
  kubectl wait --for=delete pod -l app=kk-payments --timeout=120s >/dev/null 2>&1 || true
  run kubectl get all -l app=kk-payments
  hdr "ImagePullSecret still present (name only)"
  run kubectl get secret "$SECRET_NAME" -o custom-columns=NAME:.metadata.name,TYPE:.type
  hdr "Remove locally cached kk-payments images (cold build)"
  run docker images --filter=reference="*kk-payments*"
  ids="$(docker images --filter=reference="*kk-payments*" -q | sort -u)"
  [[ -n "$ids" ]] && run docker rmi -f $ids || echo "(no cached kk-payments images)"
  ids="$(docker images --filter=reference="*/kk-payments*" -q | sort -u)"
  [[ -n "$ids" ]] && run docker rmi -f $ids || true
} >"$RESET_LOG"

# ---------------------------------------------------------------------------
step "Version string (computed, never typed)"
VERSION="$(sed -nE 's/^[[:space:]]*"version":[[:space:]]*"([^"]+)".*/\1/p' package.json | head -1)"
GITSHA="$(git rev-parse --short=7 HEAD)"
TAG="${VERSION}-${GITSHA}"
[[ -n "$VERSION" && ${#GITSHA} -eq 7 ]] || fail "could not compute version string"
echo "TAG=$TAG" >&2

# ---------------------------------------------------------------------------
step "Requirement 1: --no-cache production build and verification"
{
  echo "KijaniKiosk kk-payments: build verification"
  echo "Generated: $(ts)   Host: $(hostname)"
  hdr "Baseline (Monday-style single-stage image, for size comparison only)"
  run docker build -f Dockerfile.baseline -t kk-payments:baseline . | tail -n 5
  hdr "Production build with --no-cache"
  run docker build --no-cache --progress=plain \
      --build-arg APP_VERSION="$TAG" \
      -f Dockerfile.production -t "kk-payments:$TAG" .
  hdr "docker images (size)"
  run docker images --filter=reference="kk-payments*"
  hdr "whoami (must be kijani)"
  run docker run --rm "kk-payments:$TAG" whoami
  hdr "which tsc (must be empty)"
  echo "\$ docker run --rm kk-payments:$TAG which tsc"
  out="$(docker run --rm "kk-payments:$TAG" which tsc 2>&1 || true)"
  echo "${out:-<empty: TypeScript compiler not present>}"
  hdr "Configured user and healthcheck"
  run docker inspect -f 'User={{.Config.User}}  Healthcheck={{json .Config.Healthcheck}}' "kk-payments:$TAG"
  hdr "HEALTHCHECK transition (must reach healthy within 60s)"
  cid="$(docker run -d "kk-payments:$TAG")"
  start=$(date +%s)
  status="starting"
  while (( $(date +%s) - start < 90 )); do
    status="$(docker inspect -f '{{.State.Health.Status}}' "$cid")"
    echo "$(ts)  t+$(( $(date +%s) - start ))s  health=$status"
    [[ "$status" == "healthy" || "$status" == "unhealthy" ]] && break
    sleep 2
  done
  HEALTHY_SECS=$(( $(date +%s) - start ))
  echo "Result: $status after ${HEALTHY_SECS}s"
  docker rm -f "$cid" >/dev/null
} | tee build-verification.txt

grep -q "^kijani$" build-verification.txt || fail "whoami did not return kijani"
grep -q "Result: healthy" build-verification.txt || fail "container did not become healthy"
HEALTHY_SECS="$(sed -nE 's/^Result: healthy after ([0-9]+)s$/\1/p' build-verification.txt)"

PROD_BYTES=$(docker image inspect -f '{{.Size}}' "kk-payments:$TAG")
BASE_BYTES=$(docker image inspect -f '{{.Size}}' "kk-payments:baseline")
PROD_MB=$(awk "BEGIN{printf \"%.1f\", $PROD_BYTES/1000000}")
BASE_MB=$(awk "BEGIN{printf \"%.1f\", $BASE_BYTES/1000000}")
REDUCTION=$(awk "BEGIN{printf \"%.1f\", (1-$PROD_BYTES/$BASE_BYTES)*100}")
(( PROD_BYTES < 100000000 )) || fail "production image is ${PROD_MB}MB (must be under 100MB)"
{
  hdr "Size summary"
  echo "Baseline single-stage image : ${BASE_MB} MB"
  echo "Production two-stage image  : ${PROD_MB} MB"
  echo "Reduction                   : ${REDUCTION}%"
} | tee -a build-verification.txt

# ---------------------------------------------------------------------------
step "Requirement 2: versioned push, delete, fresh pull"
{
  echo "KijaniKiosk kk-payments: registry push and pull verification"
  echo "Generated: $(ts)"
  hdr "Version string computation"
  echo '$ VERSION=$(sed -nE '"'"'s/^[[:space:]]*"version":[[:space:]]*"([^"]+)".*/\1/p'"'"' package.json | head -1)'
  echo '$ GITSHA=$(git rev-parse --short=7 HEAD)'
  echo '$ TAG="${VERSION}-${GITSHA}"'
  echo "VERSION=$VERSION"
  echo "GITSHA=$GITSHA"
  echo "TAG=$TAG"
  hdr "Tag and push"
  run docker tag "kk-payments:$TAG" "$IMAGE:$TAG"
  run docker push "$IMAGE:$TAG"
  hdr "Delete every local copy (registry becomes the only source)"
  run docker rmi "$IMAGE:$TAG" "kk-payments:$TAG"
  run docker images --filter=reference="*kk-payments:$TAG"
  hdr "Fresh pull from the registry"
  run docker pull "$IMAGE:$TAG"
  run docker images --filter=reference="$IMAGE"
  run docker inspect -f 'RepoDigests={{.RepoDigests}}' "$IMAGE:$TAG"
  hdr "Credential audit (no tokens or passwords in committed files)"
  echo "\$ grep -rEn 'ghp_|github_pat_|dckr_pat_|\"auth\"[[:space:]]*:|password[[:space:]]*[:=]' . --exclude=run-pipeline.sh --exclude=registry-push.txt"
  if grep -rEn 'ghp_|github_pat_|dckr_pat_|"auth"[[:space:]]*:|password[[:space:]]*[:=]' . --exclude=run-pipeline.sh --exclude=registry-push.txt; then
    echo "AUDIT FAILED"
  else
    echo "No credentials found: audit passed"
  fi
} | tee registry-push.txt
grep -q "AUDIT FAILED" registry-push.txt && fail "credential audit failed"
grep -q "Status: Downloaded newer image\|Image is up to date" registry-push.txt || fail "fresh pull did not succeed"

# ---------------------------------------------------------------------------
step "Requirement 3: deployment manifest with today's tag"
sed -i -E "s#^([[:space:]]*image:[[:space:]]*).*kk-payments:.*#\1$IMAGE:$TAG#" kk-payments-deployment.yaml
grep -q "image: $IMAGE:$TAG\$" kk-payments-deployment.yaml || fail "manifest image tag not updated"
DEPLOY_START=$(date +%s)
{
  cat "$RESET_LOG"
  hdr "Tag check: manifest vs registry"
  echo "manifest : $(grep -E '^[[:space:]]*image:' kk-payments-deployment.yaml | sed -E 's/^[[:space:]]*image:[[:space:]]*//')"
  echo "registry : $IMAGE:$TAG"
  hdr "Apply deployment  ($(ts))"
  run kubectl apply -f kk-payments-deployment.yaml
  run kubectl rollout status deployment/kk-payments --timeout=180s
  echo "Both Pods Running and ready after $(( $(date +%s) - DEPLOY_START ))s"
  hdr "kubectl get pods"
  run kubectl get pods -l app=kk-payments -o wide
  hdr "kubectl get deployment"
  run kubectl get deployment kk-payments
  hdr "Image actually running"
  run kubectl get pods -l app=kk-payments -o jsonpath='{range .items[*]}{.metadata.name}{"  "}{.spec.containers[0].image}{"\n"}{end}'
} | tee deploy-output.txt
rm -f "$RESET_LOG"
grep -qE '^kk-payments[[:space:]]+2/2' deploy-output.txt || fail "deployment did not reach 2/2"

# ---------------------------------------------------------------------------
step "Requirement 4: service, endpoints, NodePort and in-cluster DNS"
kubectl apply -f kk-payments-service.yaml >/dev/null
for _ in $(seq 1 30); do
  n=$(kubectl get endpoints kk-payments-service -o jsonpath='{.subsets[*].addresses[*].ip}' | wc -w)
  (( n >= 2 )) && break
  sleep 2
done
NODE_IP="$(minikube ip)"
{
  echo "KijaniKiosk kk-payments: service verification"
  echo "Generated: $(ts)"
  hdr "Apply service"
  run kubectl apply -f kk-payments-service.yaml
  run kubectl get service kk-payments-service
  hdr "Endpoints (must list both Pod IPs)"
  run kubectl get endpoints kk-payments-service
  run kubectl get pods -l app=kk-payments -o custom-columns=POD:.metadata.name,IP:.status.podIP
  hdr "External access through the NodePort"
  echo "\$ curl -s http://\$(minikube ip):30001/health    # minikube ip = $NODE_IP"
  NODEPORT_BODY="$(curl -s --max-time 10 "http://$NODE_IP:30001/health" || true)"
  if [[ -z "$NODEPORT_BODY" ]]; then
    echo "(direct NodePort not reachable from this host; using minikube service URL)"
    URL="$(minikube service kk-payments-service --url | head -1)"
    echo "\$ curl -s $URL/health"
    NODEPORT_BODY="$(curl -s --max-time 10 "$URL/health" || true)"
  fi
  echo "$NODEPORT_BODY"
  hdr "In-cluster DNS: kk-payments-service.default.svc.cluster.local:3001"
  DNS_URL="http://kk-payments-service.default.svc.cluster.local:3001/health"
  # Run the curl Pod to completion and read its logs (attaching with -i can
  # miss the output when curl finishes before the attach happens).
  echo "\$ kubectl run dns-check --image=curlimages/curl --restart=Never -- curl -s $DNS_URL && kubectl logs dns-check"
  kubectl delete pod dns-check --ignore-not-found >/dev/null 2>&1 || true
  DNS_BODY=""
  if kubectl run dns-check --image=curlimages/curl --restart=Never -- curl -s --max-time 10 "$DNS_URL" >/dev/null 2>&1 \
     && kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/dns-check --timeout=90s >/dev/null 2>&1; then
    DNS_BODY="$(kubectl logs dns-check 2>&1)"
  fi
  kubectl delete pod dns-check --ignore-not-found >/dev/null 2>&1 || true
  if [[ -n "$DNS_BODY" ]]; then
    echo "$DNS_BODY"
  else
    POD1="$(kubectl get pod -l app=kk-payments -o name | head -1)"
    echo "(curl Pod unavailable; exec into $POD1 instead)"
    echo "\$ kubectl exec $POD1 -- wget -qO- $DNS_URL"
    kubectl exec "$POD1" -- wget -qO- "$DNS_URL" 2>&1
  fi
  echo
  hdr "Version check"
  echo "deployed tag : $TAG"
  echo "health says  : $(echo "$NODEPORT_BODY" | sed -nE 's/.*"version":"([^"]+)".*/\1/p')"
} | tee service-output.txt
grep -q "\"version\":\"$TAG\"" service-output.txt || fail "health endpoint did not report version $TAG"

# ---------------------------------------------------------------------------
step "Self-healing re-run (fresh Pods from today's deployment)"
mapfile -t BEFORE < <(kubectl get pods -l app=kk-payments -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
VICTIM="${BEFORE[0]}"
WATCH_LOG="$(mktemp)"
( kubectl get pods -l app=kk-payments -w --no-headers 2>&1 | while IFS= read -r line; do
    printf '%s  %s\n' "$(date '+%H:%M:%S.%3N')" "$line"; done ) >"$WATCH_LOG" &
WATCH_PID=$!
sleep 2
T0=$(date +%s.%N)
T0_H=$(date -d "@$T0" '+%H:%M:%S.%3N')
kubectl delete pod "$VICTIM" --wait=false >/dev/null
NEWPOD=""; T1=""; T1_READY=""
while :; do
  now=$(date +%s.%N)
  awk "BEGIN{exit !($now - $T0 > 180)}" && fail "no replacement Pod within 180s"
  while read -r name phase ready; do
    [[ " ${BEFORE[*]} " == *" $name "* ]] && continue
    NEWPOD="$name"
    [[ -z "$T1" && "$phase" == "Running" ]] && T1=$(date +%s.%N)
    [[ -z "$T1_READY" && "$ready" == "true" ]] && T1_READY=$(date +%s.%N)
  done < <(kubectl get pods -l app=kk-payments -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.phase}{" "}{.status.containerStatuses[0].ready}{"\n"}{end}')
  [[ -n "$T1" && -n "$T1_READY" ]] && break
  sleep 0.5
done
sleep 3
kill "$WATCH_PID" 2>/dev/null || true
pkill -f "kubectl get pods -l app=kk-payments -w" 2>/dev/null || true
RECOVERY=$(awk "BEGIN{printf \"%.1f\", $T1 - $T0}")
RECOVERY_READY=$(awk "BEGIN{printf \"%.1f\", $T1_READY - $T0}")
{
  echo "KijaniKiosk kk-payments: self-healing re-run (fresh deployment, $(date '+%Y-%m-%d'))"
  hdr "Pods before deletion"
  printf '%s\n' "${BEFORE[@]}"
  hdr "kubectl get pods -w  (timestamped)"
  cat "$WATCH_LOG"
  hdr "Measurement"
  echo "Deleted Pod     : $VICTIM"
  echo "Replacement Pod : $NEWPOD"
  echo "T0 (delete issued)          : $T0_H"
  echo "T1 (replacement Running)    : $(date -d "@$T1" '+%H:%M:%S.%3N')"
  echo "T1 (replacement Ready)      : $(date -d "@$T1_READY" '+%H:%M:%S.%3N')"
  echo "Recovery time T1 - T0       : ${RECOVERY} s  (to Running)"
  echo "Recovery time to Ready      : ${RECOVERY_READY} s"
  hdr "Pods after recovery"
  run kubectl get pods -l app=kk-payments
} | tee self-healing-rerun.txt
rm -f "$WATCH_LOG"

# ---------------------------------------------------------------------------
{
  echo "Week 8 Friday pipeline summary ($(ts))"
  echo "TAG=$TAG"
  echo "IMAGE=$IMAGE:$TAG"
  echo "BASELINE_MB=$BASE_MB"
  echo "PRODUCTION_MB=$PROD_MB"
  echo "SIZE_REDUCTION_PERCENT=$REDUCTION"
  echo "HEALTHY_WITHIN_SECONDS=$HEALTHY_SECS"
  echo "SELF_HEAL_TO_RUNNING_SECONDS=$RECOVERY"
  echo "SELF_HEAL_TO_READY_SECONDS=$RECOVERY_READY"
  echo "REGISTRY_CHOICE=Cloud registry ($REG_HOST), reachable from minikube over the internet (Challenge C option 2)"
} | tee pipeline-summary.txt

# ---------------------------------------------------------------------------
if [[ -z "${SKIP_GIT_PUSH:-}" ]]; then
  step "Commit evidence and push $BRANCH"
  git add -A .
  if ! git diff --cached --quiet; then
    git commit -m "Week 8 Friday: pipeline evidence for kk-payments $TAG" \
      || fail "git commit failed (set git user.name and user.email, then commit week8/friday by hand)"
  fi
  git push -u origin "$BRANCH" || fail "git push failed"
fi

step "DONE. Tag $TAG deployed. Evidence files are in week8/friday/."
