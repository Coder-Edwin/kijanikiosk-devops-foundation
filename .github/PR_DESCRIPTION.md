## Summary

Adds the **KijaniKiosk DevOps Starter Kit** — the documented engineering foundation for the platform before launch.

## What's in this PR

| File | Purpose |
|---|---|
| `starter-kit/delivery-notes.md` | How Flow, Feedback and Learning appear in our workflow |
| `starter-kit/cloud-model.md` | Hybrid model: IaaS network/compute, PaaS database, SaaS payments/email/Git — with reasoning per layer |
| `starter-kit/regions-azs.md` | `af-south-1` region choice and 2-AZ reliability design, incl. RPO/RTO targets |
| `starter-kit/iam-least-privilege.md` + `iam/*.json` | `kijanikiosk-receipt-writer` role: write/read receipts only, KMS-enforced, no list/delete |
| `starter-kit/network-topology.png` + `.md` | VPC `10.0.0.0/16`: public / private-app / private-data subnets per AZ, route tables and security-group chain |
| `starter-kit/reflection.md` | Shortcuts resisted, hardest decision, first improvements |

## Key decisions for reviewers

- **Only `rt-public` routes to the Internet Gateway.** App subnets reach out through a NAT per AZ; data subnets have no `0.0.0.0/0` route at all.
- **Two NAT Gateways, not one** — avoids AZ-a becoming a hidden single point of failure for AZ-b.
- **App role has no `s3:ListBucket` or `s3:DeleteObject`** — receipts can't be enumerated or destroyed if the role is compromised.
- **Region is Cape Town** for latency and data residency; latency must be measured from Kenyan networks before launch.

## How to review

1. Open `network-topology.png` and check: can anything in a private subnet be reached from the internet?
2. Read the IAM permissions JSON: is there any action the receipt task doesn't need?
3. Challenge the region and IaaS/PaaS choices in `regions-azs.md` and `cloud-model.md`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01Daa7JUwjk4voJbmKfKzKjy
