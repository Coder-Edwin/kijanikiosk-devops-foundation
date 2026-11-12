#!/usr/bin/env bash
# Deploy one image tag to one environment, using the single shared manifest.
# If the rollout does not become healthy, roll back automatically and fail.
#
#   capstone/scripts/deploy.sh <namespace> <image:tag>
set -Eeuo pipefail
NS="${1:?namespace}"; IMAGE="${2:?image:tag}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Deploying $IMAGE to namespace $NS"
sed "s#IMAGE_PLACEHOLDER#${IMAGE}#" "$ROOT/k8s/deployment.yaml" | kubectl apply -n "$NS" -f -
kubectl apply -n "$NS" -f "$ROOT/k8s/service.yaml"
kubectl annotate deployment/kk-payments -n "$NS" kubernetes.io/change-cause="deploy $IMAGE" --overwrite >/dev/null

if ! kubectl rollout status deployment/kk-payments -n "$NS" --timeout=180s; then
  echo "Rollout of $IMAGE in $NS did not become healthy: rolling back" >&2
  kubectl describe deployment kk-payments -n "$NS" | tail -20 >&2 || true
  kubectl rollout undo deployment/kk-payments -n "$NS" || true
  kubectl rollout status deployment/kk-payments -n "$NS" --timeout=120s || true
  exit 1
fi
kubectl get pods -n "$NS" -l app=kk-payments -o wide
