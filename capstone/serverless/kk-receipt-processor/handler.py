"""kk-receipt-processor: first link of the receipt chain.

Triggered by s3:ObjectCreated on kk-payments-receipts-staging. Validates the
receipt written by kk-payments, stamps it as processed and writes it to the
processed bucket, which in turn triggers kk-notifier.
"""
import json
import os
import urllib.parse
from datetime import datetime, timezone

import boto3

s3 = boto3.client("s3")  # LocalStack injects AWS_ENDPOINT_URL into the function environment
PROCESSED_BUCKET = os.environ["PROCESSED_BUCKET"]
REQUIRED = ("receiptId", "customerId", "amount", "currency", "environment", "createdAt")


def log(level, msg, **fields):
    print(json.dumps({"ts": datetime.now(timezone.utc).isoformat(), "level": level, "msg": msg,
                      "function": "kk-receipt-processor", **fields}))


def handler(event, _context):
    processed = 0
    for record in event.get("Records", []):
        bucket = record["s3"]["bucket"]["name"]
        key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])
        receipt = json.loads(s3.get_object(Bucket=bucket, Key=key)["Body"].read())

        missing = [f for f in REQUIRED if f not in receipt]
        if missing or not isinstance(receipt.get("amount"), (int, float)) or receipt["amount"] <= 0:
            log("error", "invalid receipt rejected", key=key, missing=missing)
            continue

        receipt["status"] = "validated"
        receipt["processedAt"] = datetime.now(timezone.utc).isoformat()
        s3.put_object(Bucket=PROCESSED_BUCKET, Key=key, Body=json.dumps(receipt),
                      ContentType="application/json")
        log("info", "receipt validated", receiptId=receipt["receiptId"], key=key, target=PROCESSED_BUCKET)
        processed += 1
    return {"processed": processed}
