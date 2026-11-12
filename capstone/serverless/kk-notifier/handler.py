"""kk-notifier: last link of the receipt chain.

Triggered by s3:ObjectCreated on kk-payments-processed-staging. In production
this would send the customer an SMS or email; here it emits the structured
notification event that the demo and the smoke test look for.
"""
import json
import urllib.parse
from datetime import datetime, timezone

import boto3

s3 = boto3.client("s3")


def handler(event, _context):
    sent = 0
    for record in event.get("Records", []):
        bucket = record["s3"]["bucket"]["name"]
        key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])
        r = json.loads(s3.get_object(Bucket=bucket, Key=key)["Body"].read())
        print(json.dumps({
            "ts": datetime.now(timezone.utc).isoformat(),
            "level": "info",
            "function": "kk-notifier",
            "event": "receipt.notification",
            "receiptId": r["receiptId"],
            "customerId": r["customerId"],
            "message": f"Receipt {r['receiptId']} for {r['currency']} {r['amount']} confirmed",
            "environment": r.get("environment"),
        }))
        sent += 1
    return {"notified": sent}
