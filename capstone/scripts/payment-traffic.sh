#!/usr/bin/env bash
# Sends a steady stream of test payments to one environment, so the alert has a
# rate to measure during the fault demo. Ctrl+C to stop.
#
#   capstone/scripts/payment-traffic.sh kijani-staging [interval-seconds]
set -Euo pipefail
NS="${1:-kijani-staging}"; EVERY="${2:-2}"
IP="$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')"
PORT="$(kubectl get svc kk-payments-service -n "$NS" -o jsonpath='{.spec.ports[0].nodePort}')"
i=0
while true; do
  i=$((i+1))
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -H 'Content-Type: application/json' \
    -d "{\"customerId\":\"traffic-$i\",\"amount\":$((RANDOM % 5000 + 50)),\"currency\":\"KES\"}" "http://$IP:$PORT/payments")"
  echo "$(date +%H:%M:%S) payment $i -> HTTP $code"
  sleep "$EVERY"
done
