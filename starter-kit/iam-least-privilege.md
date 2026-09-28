# IAM Least Privilege Design

## The principle

> Give each identity **only** the permissions it needs to do its **one** job — and nothing else.

If an identity is ever compromised, least privilege decides how bad the day is. A leaked role that can only write receipts is an incident. A leaked role with `s3:*` on everything is a company-ending breach.

---

## The application task

**Component:** Order Service (runs on the EC2 app servers in the private subnets)

**Task:** *When a customer completes checkout, generate a PDF receipt, store it, and later read it back to attach to the confirmation email.*

That is the whole job. We designed the role by listing exactly what the task needs, then granting only that.

| The task needs to… | AWS action | On which resource |
|---|---|---|
| Save a new receipt | `s3:PutObject` | Only `kijanikiosk-receipts-prod/receipts/*` |
| Read a receipt back to email it | `s3:GetObject` | Only `kijanikiosk-receipts-prod/receipts/*` |
| Encrypt the receipt on upload | `kms:GenerateDataKey` | Only the receipts KMS key, only via S3 |
| Decrypt it on read | `kms:Decrypt` | Only the receipts KMS key, only via S3 |

---

## The role

**Role name:** `kijanikiosk-receipt-writer`
**Attached to:** the app servers' EC2 instance profile
**Credentials:** temporary, issued and rotated automatically by AWS — **no access keys are stored on the servers or in code**

### Trust policy — *who* may use the role

File: [`iam/receipt-writer-trust.json`](iam/receipt-writer-trust.json)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "OnlyEC2InThisAccountMayAssume",
      "Effect": "Allow",
      "Principal": { "Service": "ec2.amazonaws.com" },
      "Action": "sts:AssumeRole",
      "Condition": { "StringEquals": { "aws:SourceAccount": "111122223333" } }
    }
  ]
}
```

Only the EC2 service, acting for instances in *our* account, can assume this role. A human user cannot log in as it, and another AWS account cannot borrow it.

### Permissions policy — *what* the role may do

File: [`iam/receipt-writer-permissions.json`](iam/receipt-writer-permissions.json)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "WriteNewReceipts",
      "Effect": "Allow",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::kijanikiosk-receipts-prod/receipts/*",
      "Condition": {
        "StringEquals": {
          "s3:x-amz-server-side-encryption": "aws:kms",
          "s3:x-amz-server-side-encryption-aws-kms-key-id": "arn:aws:kms:af-south-1:111122223333:key/1a2b3c4d-5e6f-7a8b-9c0d-receiptskey01"
        }
      }
    },
    {
      "Sid": "ReadReceiptsForEmail",
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::kijanikiosk-receipts-prod/receipts/*"
    },
    {
      "Sid": "UseReceiptsKeyOnlyThroughS3",
      "Effect": "Allow",
      "Action": ["kms:GenerateDataKey", "kms:Decrypt"],
      "Resource": "arn:aws:kms:af-south-1:111122223333:key/1a2b3c4d-5e6f-7a8b-9c0d-receiptskey01",
      "Condition": { "StringEquals": { "kms:ViaService": "s3.af-south-1.amazonaws.com" } }
    }
  ]
}
```

*(Account ID `111122223333` and the key ID are placeholders.)*

---

## Why each line is shaped the way it is

| Design choice | What it prevents |
|---|---|
| **Specific actions, no wildcards** (`s3:PutObject`, not `s3:*`) | The role cannot delete, overwrite bucket settings, change permissions or make the bucket public. |
| **Resource limited to one bucket *and* one prefix** (`/receipts/*`) | Even inside the right bucket, it cannot touch other folders. Other buckets (product images, backups, logs) are completely invisible to it. |
| **No `s3:ListBucket`** | The app always knows the exact key (`receipts/<order-id>.pdf`), so it never needs to list. An attacker with this role cannot enumerate every customer's receipt — they would have to guess each order ID. |
| **No `s3:DeleteObject`** | Receipts are financial records. If the role is compromised, the attacker cannot destroy them. Deletion (for retention expiry) is done by an S3 lifecycle rule, not by the app. |
| **Upload must use our KMS key** (condition on `PutObject`) | The app cannot accidentally — or maliciously — store an unencrypted receipt. The request is rejected outright. |
| **KMS use only via S3** (`kms:ViaService`) | The role cannot call KMS directly to decrypt arbitrary data; the key only works as part of an S3 read/write. |
| **Role, not access keys** | There are no long-lived secrets to leak in a Git commit or a log file. |

### What the role deliberately **cannot** do

- ❌ Read or write any other bucket
- ❌ List the contents of the receipts bucket
- ❌ Delete or overwrite bucket configuration
- ❌ Change IAM, start/stop servers, or read database snapshots
- ❌ Use the KMS key outside of S3

Because IAM denies everything by default, none of these need to be listed — they are simply never granted.

---

## Defence in depth: the bucket policy

IAM controls what the *role* can do. The bucket's own resource policy adds a second, independent layer, so a mistake in one does not open the door.

File: [`iam/receipts-bucket-policy.json`](iam/receipts-bucket-policy.json)

- **Deny any request that is not over TLS** — receipts contain personal data and must never travel unencrypted.
- **Deny the app role unless the request comes through our VPC Gateway Endpoint for S3** — even if the role's temporary credentials are stolen off a server, they are useless from the attacker's own laptop.

The bucket also has **S3 Block Public Access** turned on, and **versioning** enabled so an overwritten receipt can be recovered.

---

## How we would verify it

1. **IAM Access Analyzer** — validate the policy JSON for errors and flag over-broad grants.
2. **IAM Policy Simulator** — prove that `PutObject` on `receipts/123.pdf` is allowed and that `DeleteObject`, `ListBucket` and `PutObject` on `images/x.png` are denied.
3. **CloudTrail** — after launch, review which actions the role actually used. If a granted permission is never used, remove it.

---

## Other identities (same pattern, not detailed here)

| Identity | Its one job |
|---|---|
| Policy `db-secret-read` (attached alongside the receipt policy on the app role) | `secretsmanager:GetSecretValue` on the single secret holding the database password |
| Role `kijanikiosk-ci-deployer` | Used by GitHub Actions via OIDC (no stored keys) to deploy a new app version — cannot read customer data |
| Role `kijanikiosk-image-processor` (future service) | Read/write the product-images bucket only |

Each permission lives in its own small, named policy, so reviewers can read one job at a time — and when a component is split into its own service later, its policy moves with it to a separate role. A bug in image handling can then never touch receipts.
