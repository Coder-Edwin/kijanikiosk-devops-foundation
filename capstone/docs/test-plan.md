# Test Plan

Written before the peer review session. Each case maps to a scope success criterion (S1–S6). The reviewer runs the cases from a clean checkout using only the README, and records findings in [`feedback-log.md`](feedback-log.md).

## Environment
Ubuntu 24.04 VM with minikube (docker driver), Jenkins, LocalStack and the monitoring stack set up per README §4.

## Cases

| ID | Criterion | Steps | Expected result | Pass/Fail | Notes |
|---|---|---|---|---|---|
| T1 | S1 | `RESET=1 bash capstone/scripts/bootstrap-infra.sh` | Staging deleted and recreated; ConfigMaps show different DB_HOST per environment; "converged in" < 300 s | | |
| T2 | S1 | Run `ansible-playbook configure-environments.yml` twice | Second run reports `changed=0` | | |
| T3 | S2 | Merge a small PR into `main` (e.g. bump `version` in `app/package.json`) | Jenkins build starts within 2 minutes with no manual trigger | | |
| T4 | S3 | Let the pipeline reach *Smoke test staging* | `smoke-kijani-staging.txt` shows the new tag, `environment staging`, staging DB_HOST, all PASS | | |
| T5 | S4 | Approve with an empty reason | Build fails with "a reason is required"; production unchanged | | |
| T6 | S4 | Re-run, approve with a reason | `approval-record.txt` contains approver + reason; production `/health` shows the new tag | | |
| T7 | S4 | `docker stop kijani-localstack`, push a change to `main` | Pipeline stops at *Smoke test staging*; the gate is never offered; production still serves the previous tag | | |
| T8 | S5 | `POST /payments` to staging, then `bash capstone/scripts/show-receipt-chain.sh` | Receipt in `kk-payments-receipts-staging`, copy in `kk-payments-processed-staging`, `receipt.notification` in kk-notifier logs within 10 s | | |
| T9 | S6 | LocalStack stopped + `payment-traffic.sh kijani-staging` running | `KkPaymentsReceiptWriteErrors` is Firing in Prometheus within 3 min; resolves after `docker start kijani-localstack` | | |
| T10 | Runtime | `kubectl delete pod -n kijani-staging -l app=kk-payments --wait=false` | Replacement pods Ready; no failed smoke requests during replacement (two replicas, maxUnavailable 0) | | |
| T11 | Security | `grep -rEn 'ghp_[A-Za-z0-9]{20,}|github_pat_|dckr_pat_' capstone/` and `kubectl exec` into a pod: `id` | No credentials committed; process runs as uid 10001; root filesystem read-only | | |
| T12 | Docs | Reviewer follows README §4 without asking the author anything | Working system; every question asked is logged as a finding | | |

## Severity scale used in the feedback log
- **High:** breaks a success criterion or exposes a secret.
- **Medium:** works but needs an undocumented step or misleads the reader.
- **Low:** clarity or polish.
