# Environment Setup

## Path used: optional cloud path (AWS)

This submission uses the **AWS cloud path**, not Multipass + MinIO:

| Concern | Primary path in the brief | This submission |
|---|---|---|
| Servers | Multipass VMs | 3 × EC2 `t3.micro`, Ubuntu 22.04, region `ap-south-1` (Mumbai) |
| Image | Multipass `jammy` | `aws_ami` data source, Canonical owner `099720109477`, newest `ubuntu-jammy-22.04-amd64-server-*` |
| IP source for the inventory | `multipass info` | `terraform output -json servers` |
| Remote state | MinIO S3 at `http://localhost:9000` (no locking) | Amazon S3 bucket `kijanikiosk-tfstate-<account>-<region>`, encrypted, versioned, public access blocked |
| State locking | Not available; documented gap | **Enabled**: S3 native lock file (`use_lockfile = true`, Terraform ≥ 1.10) |

Why AWS: Tuesday's class (30 Sep) already provisioned EC2 servers in `ap-south-1` with Terraform and configured them with Ansible, so this path builds directly on that work. It is also the only path where Challenge C (security groups) is real and where the backend can lock state.

**On MinIO and locking (for completeness).** Had this used the primary path, MinIO's S3-compatible API would store state but Terraform's S3 backend could not lock it in our setup, so two simultaneous applies could corrupt the state. Production deployments solve this with DynamoDB lock tables on AWS (now superseded by S3's native lock file, used here), GCS's built-in object locking on GCP, or Consul's locking backend for a vendor-neutral setup.

`pipeline.sh multipass` exits with a clear message rather than half-supporting a second path.

## Tool versions

Minimum versions the code requires, and the versions recorded on the machine that produced `pipeline-run1.log` / `pipeline-run2.log`. The recorded column is filled in by `./record-environment.sh`; the same values are also printed in the Preflight section of each pipeline log.

<!-- BEGIN RECORDED VERSIONS -->
| Tool | Required | Recorded |
|---|---|---|
| Terraform | ≥ 1.10 (S3 `use_lockfile`) | _run ./record-environment.sh_ |
| AWS provider | ~> 5.0 | _run ./record-environment.sh_ |
| Ansible (core) | ≥ 2.15 | _run ./record-environment.sh_ |
| community.general collection | any recent | _run ./record-environment.sh_ |
| AWS CLI | v2 | _run ./record-environment.sh_ |
| jq | ≥ 1.6 | _run ./record-environment.sh_ |
| Operator OS | Linux / macOS / WSL2 | _run ./record-environment.sh_ |
| Target OS | Ubuntu 22.04 LTS | Asserted by the playbook on every host |
| Multipass / MinIO | not used (cloud path) | n/a |
<!-- END RECORDED VERSIONS -->

## One-time setup

```bash
# 1. Tools (Ubuntu/WSL example)
sudo apt-get install -y jq curl unzip python3-pip
#    Terraform >= 1.10: https://developer.hashicorp.com/terraform/install
#    AWS CLI v2:        https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
pipx install --include-deps ansible      # or: pip install ansible

# 2. AWS credentials for an IAM user (never the root account)
aws configure            # region: ap-south-1

# 3. The SSH key Terraform uploads and Ansible uses (path set in ansible/group_vars/kijanikiosk.yml)
ssh-keygen -t ed25519 -f ~/.ssh/kijanikiosk -N ''
```

The S3 state bucket does not need to be created by hand: on first run `pipeline.sh` notices it is missing and creates it with `terraform/bootstrap/` (which keeps its own small local state because it has to exist before the remote backend does).

## Producing the submission evidence

```bash
cd week4/friday
LOG_FILE=pipeline-run1.log ./pipeline.sh          # creates 3 servers, configures them
LOG_FILE=pipeline-run2.log ./pipeline.sh          # must show 0 Terraform changes and changed=0
cat ansible/inventory.ini                          # IPs must match terraform output
./record-environment.sh                            # fills in the versions table above
LOG_FILE=destroy-output.txt ./pipeline.sh destroy  # clean teardown
```

Run 1 and run 2 should be back to back from the same network: the security group is pinned to your current public IP, so if your IP changes between runs the second plan will (correctly) show the SSH rule being updated.

## Cost

Three `t3.micro` instances, three 10 GiB gp3 volumes and a tiny S3 bucket: within the AWS free tier for new accounts, otherwise a few US cents per hour. Run the destroy step when finished.
