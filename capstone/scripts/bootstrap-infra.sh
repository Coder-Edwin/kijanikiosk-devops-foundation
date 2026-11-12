#!/usr/bin/env bash
# Recreates the infrastructure layer from a clean checkout and times it
# (success criterion S1: under 5 minutes).
#
#   bash capstone/scripts/bootstrap-infra.sh            # create / converge
#   RESET=1 bash capstone/scripts/bootstrap-infra.sh    # delete staging first, then rebuild
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
start=$(date +%s)
ts() { date '+%H:%M:%S'; }

kubectl config use-context minikube >/dev/null

if [[ -n "${RESET:-}" ]]; then
  echo "[$(ts)] RESET: deleting kijani-staging"
  kubectl delete namespace kijani-staging --ignore-not-found --wait=true
  rm -f "$ROOT/infra/terraform/terraform.tfstate" "$ROOT/infra/terraform/terraform.tfstate.backup"
fi

echo "[$(ts)] terraform init + apply"
cd "$ROOT/infra/terraform"
terraform init -input=false -no-color >/dev/null
terraform apply -input=false -auto-approve -no-color

echo "[$(ts)] ansible-playbook configure-environments.yml"
cd "$ROOT/infra/ansible"
ansible-playbook configure-environments.yml

echo
echo "[$(ts)] Result"
kubectl get namespace kijani-staging --show-labels
kubectl get resourcequota,limitrange,configmap,secret -n kijani-staging
echo "Infrastructure layer converged in $(( $(date +%s) - start ))s"
