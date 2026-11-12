#!/usr/bin/env bash
# Shows the receipt chain's evidence for the demo: objects in each bucket and
# the latest kk-notifier log lines (success criterion S5).
set -Euo pipefail
NAME=kijani-localstack
for b in kk-payments-receipts-staging kk-payments-processed-staging; do
  echo "== s3://$b (latest 5)"
  docker exec "$NAME" awslocal s3 ls "s3://$b" --recursive | tail -5
done
echo "== kk-notifier log (latest notifications)"
docker exec "$NAME" awslocal logs filter-log-events --log-group-name /aws/lambda/kk-notifier \
  --query 'events[].message' --output text 2>/dev/null | tr '\t' '\n' | grep receipt.notification | tail -5
