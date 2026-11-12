#!/usr/bin/env bash
# Deploys Prometheus + Alertmanager and loads config and alert rules from the
# repository. Re-run after editing monitoring/*.yml to reload them.
#
#   bash capstone/scripts/setup-monitoring.sh
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
M="$ROOT/monitoring"

kubectl apply -f "$M/monitoring.yaml"
kubectl create configmap prometheus-config -n monitoring --from-file=prometheus.yml="$M/prometheus.yml" --dry-run=client -o yaml | kubectl apply -f -
kubectl create configmap prometheus-rules -n monitoring --from-file=kk-payments.yml="$M/alert-rules.yml" --dry-run=client -o yaml | kubectl apply -f -
kubectl create configmap alertmanager-config -n monitoring --from-file=alertmanager.yml="$M/alertmanager.yml" --dry-run=client -o yaml | kubectl apply -f -

# Pick up changed ConfigMaps
kubectl rollout restart deployment/prometheus deployment/alertmanager -n monitoring
kubectl rollout status deployment/prometheus -n monitoring --timeout=180s
kubectl rollout status deployment/alertmanager -n monitoring --timeout=180s

IP="$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')"
echo "Prometheus:   http://$IP:30090   (Alerts tab shows KkPaymentsReceiptWriteErrors)"
echo "Alertmanager: http://$IP:30093"
