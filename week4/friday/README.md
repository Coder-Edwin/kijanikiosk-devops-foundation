# Week 4 Friday: KijaniKiosk Full IaC Pipeline

Terraform provisions → `pipeline.sh` writes the inventory → Ansible configures. Path used: **AWS** (`ap-south-1`).

```
pipeline.sh
 ├─ preflight: tools, AWS identity, SSH key (from group_vars), operator IP
 ├─ S3 state bucket (bootstrap once if missing)
 ├─ terraform init (S3 backend, locking) → plan -detailed-exitcode → apply only if changes
 ├─ terraform output -json servers  ──►  ansible/inventory.ini
 └─ ansible-playbook kijanikiosk.yml
      wait for SSH + cloud-init
      1 packages · 2 accounts · 3 directories · 4 systemd · 5 firewall · 6 journald · 7 logrotate
      8 verify: HTTP 200 · env file readable by service user · security score < 2.5
```

| Server | Service | Port | Reachable from |
|---|---|---|---|
| api | kk-api | 8080 | VPC + operator IP |
| payments | kk-payments | 8081 | VPC only |
| logs | kk-logs | 8082 | VPC only |

## Run

```bash
ssh-keygen -t ed25519 -f ~/.ssh/kijanikiosk -N ''   # once
aws configure                                        # IAM user, region ap-south-1

LOG_FILE=pipeline-run1.log ./pipeline.sh
LOG_FILE=pipeline-run2.log ./pipeline.sh
cat ansible/inventory.ini
./record-environment.sh
LOG_FILE=destroy-output.txt ./pipeline.sh destroy
```

| Document | For |
|---|---|
| [hardening-decisions.md](hardening-decisions.md) | Nia: security controls and gaps, in plain language |
| [reflection.md](reflection.md) | Tendo: conflicts, translation, fragile handoff |
| [environment-setup.md](environment-setup.md) | Tool versions and why the AWS path |
