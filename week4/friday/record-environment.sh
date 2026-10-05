#!/usr/bin/env bash
# Fills the "Recorded" column of environment-setup.md with the versions
# installed on this machine. Run it on the machine that ran pipeline.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOC="${SCRIPT_DIR}/environment-setup.md"

v() { "$@" 2>/dev/null || echo "not installed"; }

TF="$(v terraform version -json | jq -r '.terraform_version' 2>/dev/null || echo 'not installed')"
AWSP="$(terraform -chdir="${SCRIPT_DIR}/terraform" version -json 2>/dev/null \
        | jq -r '.provider_selections["registry.terraform.io/hashicorp/aws"] // "run terraform init first"' 2>/dev/null \
        || echo 'run terraform init first')"
ANS="$(v ansible --version | sed -n 1p)"
CG="$(ansible-galaxy collection list community.general 2>/dev/null | awk '/^community\.general/ {print $2; exit}')"
AWSCLI="$(v aws --version)"
JQ="$(v jq --version)"
if [[ -r /etc/os-release ]]; then
  OS="$(. /etc/os-release && echo "${PRETTY_NAME}") ($(uname -r))"
else
  OS="$(uname -srm)"
fi
DATE="$(date -u '+%Y-%m-%d')"

TABLE="$(cat <<EOF
<!-- BEGIN RECORDED VERSIONS -->
| Tool | Required | Recorded (${DATE}) |
|---|---|---|
| Terraform | ≥ 1.10 (S3 \`use_lockfile\`) | ${TF} |
| AWS provider | ~> 5.0 | ${AWSP} |
| Ansible (core) | ≥ 2.15 | ${ANS} |
| community.general collection | any recent | ${CG:-not installed} |
| AWS CLI | v2 | ${AWSCLI} |
| jq | ≥ 1.6 | ${JQ} |
| Operator OS | Linux / macOS / WSL2 | ${OS} |
| Target OS | Ubuntu 22.04 LTS | Asserted by the playbook on every host |
| Multipass / MinIO | not used (cloud path) | n/a |
<!-- END RECORDED VERSIONS -->
EOF
)"

python3 - "${DOC}" "${TABLE}" <<'PY'
import re, sys
path, table = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read()
new = re.sub(r"<!-- BEGIN RECORDED VERSIONS -->.*?<!-- END RECORDED VERSIONS -->",
             lambda _: table, text, flags=re.S)
open(path, "w", encoding="utf-8").write(new)
PY

echo "Updated ${DOC}:"
echo "${TABLE}"
