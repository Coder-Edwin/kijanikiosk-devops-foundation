#!/usr/bin/env bash
# Runs INSIDE the LocalStack container (awslocal is bundled there).
# Creates the receipt buckets and wires the two-function receipt chain:
#   kk-payments-receipts-staging --ObjectCreated--> kk-receipt-processor
#   --> kk-payments-processed-staging --ObjectCreated--> kk-notifier
# Idempotent: safe to run repeatedly.
set -euo pipefail
SRC=/opt/kijani-serverless
ACCOUNT=000000000000
REGION=us-east-1
ROLE_ARN="arn:aws:iam::${ACCOUNT}:role/kk-receipt-chain"

for b in kk-payments-receipts-staging kk-payments-processed-staging kk-payments-receipts; do
  awslocal s3api head-bucket --bucket "$b" 2>/dev/null || awslocal s3api create-bucket --bucket "$b" >/dev/null
  echo "bucket ready: $b"
done

awslocal iam get-role --role-name kk-receipt-chain >/dev/null 2>&1 || awslocal iam create-role \
  --role-name kk-receipt-chain \
  --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null

deploy_fn() {
  local name="$1" env_json="$2" zip="/tmp/${1}.zip"
  (cd "$SRC/$name" && python3 -m zipfile -c "$zip" handler.py)
  if awslocal lambda get-function --function-name "$name" >/dev/null 2>&1; then
    awslocal lambda update-function-code --function-name "$name" --zip-file "fileb://$zip" >/dev/null
  else
    awslocal lambda create-function --function-name "$name" --runtime python3.12 \
      --handler handler.handler --role "$ROLE_ARN" --timeout 30 \
      --zip-file "fileb://$zip" --environment "$env_json" >/dev/null
  fi
  awslocal lambda wait function-active-v2 --function-name "$name"
  awslocal lambda add-permission --function-name "$name" --statement-id s3-invoke \
    --action lambda:InvokeFunction --principal s3.amazonaws.com >/dev/null 2>&1 || true
  echo "function ready: $name"
}

deploy_fn kk-receipt-processor '{"Variables":{"PROCESSED_BUCKET":"kk-payments-processed-staging"}}'
deploy_fn kk-notifier '{"Variables":{}}'

notify() {
  awslocal s3api put-bucket-notification-configuration --bucket "$1" --notification-configuration \
    "{\"LambdaFunctionConfigurations\":[{\"LambdaFunctionArn\":\"arn:aws:lambda:${REGION}:${ACCOUNT}:function:$2\",\"Events\":[\"s3:ObjectCreated:*\"]}]}"
  echo "trigger ready: s3://$1 -> $2"
}
notify kk-payments-receipts-staging kk-receipt-processor
notify kk-payments-processed-staging kk-notifier
