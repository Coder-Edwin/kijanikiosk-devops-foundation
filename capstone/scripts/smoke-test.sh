#!/usr/bin/env bash
# Smoke test a deployed environment. Exits non-zero on the first failed check,
# which stops the pipeline before the production approval gate.
#
#   capstone/scripts/smoke-test.sh <namespace> <expected-tag> [full|health]
#   full   (default): health, version, environment config, payment, receipt chain
#   health:           health, version and environment config only (production)
set -Euo pipefail
NS="${1:?namespace}"; TAG="${2:?expected tag}"; MODE="${3:-full}"
LOCALSTACK_URL="${LOCALSTACK_URL:-http://localhost:4566}"
REPORT="smoke-${NS}.txt"
: > "$REPORT"
say()  { echo "$*" | tee -a "$REPORT"; }
pass() { say "PASS  $*"; }
fail() { say "FAIL  $*"; say "RESULT: smoke test FAILED for $NS ($TAG)"; exit 1; }

NODE_IP="$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')"
PORT="$(kubectl get svc kk-payments-service -n "$NS" -o jsonpath='{.spec.ports[0].nodePort}')"
URL="http://${NODE_IP}:${PORT}"
CM() { kubectl get configmap kk-payments-config -n "$NS" -o "jsonpath={.data.$1}"; }
EXP_ENV="$(CM APP_ENV)"; EXP_DB="$(CM DB_HOST)"; BUCKET="$(CM RECEIPTS_BUCKET)"
field() { sed -nE "s/.*\"$1\":\"?([^\",}]*)\"?.*/\1/p"; }

say "Smoke test: namespace=$NS tag=$TAG url=$URL mode=$MODE  ($(date -Iseconds))"

health="$(curl -sf --max-time 5 "$URL/health")" || fail "GET /health did not return 200"
pass "GET /health -> $health"
[[ "$(echo "$health" | field version)" == "$TAG" ]]        || fail "version is $(echo "$health" | field version), expected $TAG"
pass "version matches deployed tag ($TAG)"
[[ "$(echo "$health" | field environment)" == "$EXP_ENV" ]] || fail "environment is $(echo "$health" | field environment), expected $EXP_ENV"
pass "environment is $EXP_ENV"
[[ "$(echo "$health" | field dbHost)" == "$EXP_DB" ]]       || fail "dbHost is $(echo "$health" | field dbHost), expected $EXP_DB"
pass "DB_HOST comes from this environment's ConfigMap ($EXP_DB)"
curl -sf --max-time 5 "$URL/ready" >/dev/null || fail "GET /ready is not 200"
pass "GET /ready -> 200"
curl -sf --max-time 5 "$URL/metrics" | grep -q '^kk_payments_build_info' || fail "/metrics missing kk_payments_build_info"
pass "/metrics exposes kk_payments_build_info"

if [[ "$MODE" == "full" ]]; then
  resp="$(curl -s --max-time 10 -w '\n%{http_code}' -H 'Content-Type: application/json' \
          -d "{\"customerId\":\"smoke-${TAG}\",\"amount\":100,\"currency\":\"KES\",\"method\":\"mpesa\"}" "$URL/payments")"
  code="$(echo "$resp" | tail -1)"; body="$(echo "$resp" | head -1)"
  [[ "$code" == "201" ]] || fail "POST /payments returned $code: $body"
  pass "POST /payments -> 201 $body"
  key="$(echo "$body" | field key)"
  curl -sf --max-time 5 "$LOCALSTACK_URL/$BUCKET/$key" >/dev/null || fail "receipt not found at s3://$BUCKET/$key"
  pass "receipt stored at s3://$BUCKET/$key"
  if [[ "$NS" == "kijani-staging" ]]; then
    PROCESSED="kk-payments-processed-staging"
    for _ in $(seq 1 20); do
      curl -sf --max-time 3 "$LOCALSTACK_URL/$PROCESSED/$key" >/dev/null && break
      sleep 0.5
    done
    curl -sf --max-time 3 "$LOCALSTACK_URL/$PROCESSED/$key" >/dev/null || fail "receipt chain did not produce s3://$PROCESSED/$key within 10 s"
    pass "receipt chain fired: kk-receipt-processor wrote s3://$PROCESSED/$key"
  fi
fi
say "RESULT: smoke test PASSED for $NS ($TAG)"
