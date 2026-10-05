#!/usr/bin/env bash
# KijaniKiosk IaC pipeline: Terraform provisions -> inventory is generated -> Ansible configures.
#
# Usage:
#   ./pipeline.sh            # provision + configure (safe to run repeatedly)
#   ./pipeline.sh apply      # same as above
#   ./pipeline.sh destroy    # tear the three servers down
#
# Capture evidence for submission:
#   LOG_FILE=pipeline-run1.log ./pipeline.sh
#   LOG_FILE=pipeline-run2.log ./pipeline.sh
#   LOG_FILE=destroy-output.txt ./pipeline.sh destroy
#
# Environment overrides:
#   AWS_REGION   region for servers and state bucket   (default: ap-south-1)
#   ADMIN_CIDR   operator IP allowed to SSH             (default: auto-detected /32)
#   AWS_PROFILE  standard AWS CLI profile selection
#
# Path supported: AWS (the optional cloud path in the brief). IPs come from
# `terraform output`, not from `multipass list`. See environment-setup.md.
#
# Exit status is non-zero if any step fails: preflight, terraform init/plan/
# apply, inventory generation, or ansible-playbook.

set -Eeuo pipefail

ACTION="${1:-apply}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/terraform"
BOOTSTRAP_DIR="${TF_DIR}/bootstrap"
ANSIBLE_DIR="${SCRIPT_DIR}/ansible"
INVENTORY="${ANSIBLE_DIR}/inventory.ini"
GROUP_VARS="${ANSIBLE_DIR}/group_vars/kijanikiosk.yml"
AWS_REGION="${AWS_REGION:-ap-south-1}"
export AWS_REGION

# --- Logging -----------------------------------------------------------------
if [[ -n "${LOG_FILE:-}" ]]; then
  [[ "${LOG_FILE}" = /* ]] || LOG_FILE="${SCRIPT_DIR}/${LOG_FILE}"
  : > "${LOG_FILE}"
  exec > >(tee -a "${LOG_FILE}") 2>&1
fi

export TF_IN_AUTOMATION=1
export ANSIBLE_FORCE_COLOR=0
export ANSIBLE_CONFIG="${ANSIBLE_DIR}/ansible.cfg"

step() { printf '\n==================== %s ====================\n' "$*"; }
info() { printf '[pipeline] %s\n' "$*"; }
die()  { printf '[pipeline] ERROR: %s\n' "$*" >&2; exit 1; }

trap 'rc=$?; printf "\n[pipeline] FAILED at line %s (exit %s): %s\n" "$LINENO" "$rc" "$BASH_COMMAND" >&2; exit $rc' ERR

case "${ACTION}" in
  apply|destroy) ;;
  multipass) die "The Multipass path is not implemented here; this pipeline targets AWS. See environment-setup.md." ;;
  -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
  *) die "Unknown action '${ACTION}'. Use: apply | destroy" ;;
esac

step "Pipeline ${ACTION} started $(date -u '+%Y-%m-%dT%H:%M:%SZ') (region ${AWS_REGION})"

# --- Preflight ----------------------------------------------------------------
step "Preflight"
for cmd in terraform ansible-playbook ansible-galaxy aws jq curl; do
  command -v "${cmd}" >/dev/null 2>&1 || die "'${cmd}' is not installed (see environment-setup.md)"
done
info "terraform:        $(terraform version -json | jq -r .terraform_version)"
info "ansible-playbook: $(ansible-playbook --version | sed -n 1p)"
info "aws cli:          $(aws --version 2>&1)"
info "operator OS:      $(uname -srm)"

if ! ansible-galaxy collection list community.general 2>/dev/null | grep '^community\.general' >/dev/null; then
  info "Installing Ansible collections from ansible/requirements.yml"
  ansible-galaxy collection install -r "${ANSIBLE_DIR}/requirements.yml"
fi

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)" \
  || die "AWS credentials not working. Run 'aws configure' with an IAM user (not root)."
info "AWS account:      ${ACCOUNT_ID}"

# Challenge B: the key path has ONE home, group_vars/kijanikiosk.yml.
# Read it from there so Terraform uploads exactly the key Ansible will use.
KEY_LINE="$(grep -E '^ssh_private_key_path:' "${GROUP_VARS}" || true)"
[[ -n "${KEY_LINE}" ]] || die "ssh_private_key_path not found in ${GROUP_VARS}"
SSH_PRIVATE_KEY="$(sed -E 's/^ssh_private_key_path:[[:space:]]*//; s/[[:space:]]*#.*$//; s/["'\'']//g' <<<"${KEY_LINE}")"
SSH_PRIVATE_KEY="${SSH_PRIVATE_KEY/#\~/$HOME}"
SSH_PUBLIC_KEY="${SSH_PRIVATE_KEY}.pub"
[[ -f "${SSH_PRIVATE_KEY}" && -f "${SSH_PUBLIC_KEY}" ]] || die "SSH key pair not found at ${SSH_PRIVATE_KEY}(.pub). Create it: ssh-keygen -t ed25519 -f ${SSH_PRIVATE_KEY} -N ''"
info "SSH key:          ${SSH_PRIVATE_KEY} (Terraform uploads ${SSH_PUBLIC_KEY})"

# Challenge C: SSH is allowed from the operator's IP only, never 0.0.0.0/0.
if [[ -z "${ADMIN_CIDR:-}" ]]; then
  MY_IP="$(curl -fsS --max-time 10 https://checkip.amazonaws.com | tr -d '[:space:]')" \
    || die "Could not detect your public IP. Set ADMIN_CIDR=x.x.x.x/32"
  ADMIN_CIDR="${MY_IP}/32"
fi
info "Admin CIDR:       ${ADMIN_CIDR}"

TF_VARS=(
  -var "aws_region=${AWS_REGION}"
  -var "admin_cidr=${ADMIN_CIDR}"
  -var "ssh_public_key_path=${SSH_PUBLIC_KEY}"
)

# --- Remote state backend -----------------------------------------------------
STATE_BUCKET="kijanikiosk-tfstate-${ACCOUNT_ID}-${AWS_REGION}"
step "Remote state: s3://${STATE_BUCKET}"
if aws s3api head-bucket --bucket "${STATE_BUCKET}" >/dev/null 2>&1; then
  info "State bucket exists."
else
  info "State bucket missing; creating it once with terraform/bootstrap (local state)."
  terraform -chdir="${BOOTSTRAP_DIR}" init -input=false -no-color
  terraform -chdir="${BOOTSTRAP_DIR}" apply -input=false -no-color -auto-approve -var "aws_region=${AWS_REGION}"
fi

step "terraform init"
terraform -chdir="${TF_DIR}" init -input=false -no-color -reconfigure \
  -backend-config="bucket=${STATE_BUCKET}" \
  -backend-config="region=${AWS_REGION}"

# --- Destroy ------------------------------------------------------------------
if [[ "${ACTION}" == "destroy" ]]; then
  step "terraform destroy"
  terraform -chdir="${TF_DIR}" destroy -input=false -no-color -auto-approve "${TF_VARS[@]}"
  step "Post-destroy check"
  REMAINING="$(terraform -chdir="${TF_DIR}" state list 2>/dev/null | wc -l | tr -d ' ')"
  info "Resources left in state: ${REMAINING}"
  [[ "${REMAINING}" == "0" ]] || die "State still lists ${REMAINING} resources"
  info "Clean teardown. State bucket kept on purpose (it holds the history)."
  exit 0
fi

# --- Plan / apply -------------------------------------------------------------
terraform -chdir="${TF_DIR}" fmt -check -recursive -no-color >/dev/null \
  || info "warning: terraform fmt would reformat some files"
terraform -chdir="${TF_DIR}" validate -no-color

step "terraform plan"
# -detailed-exitcode: 0 = no changes, 1 = error, 2 = changes present.
# (Captured with || so neither set -e nor the ERR trap treats "2" as a failure.)
PLAN_RC=0
terraform -chdir="${TF_DIR}" plan -input=false -no-color -detailed-exitcode \
  -out=tfplan "${TF_VARS[@]}" || PLAN_RC=$?

case "${PLAN_RC}" in
  0)
    info "RESULT: terraform plan shows 0 to add, 0 to change, 0 to destroy (no drift)."
    ;;
  2)
    step "terraform apply"
    terraform -chdir="${TF_DIR}" apply -input=false -no-color tfplan
    ;;
  *)
    die "terraform plan failed (exit ${PLAN_RC})"
    ;;
esac
rm -f "${TF_DIR}/tfplan"

# --- Challenge A: Terraform output -> inventory.ini --------------------------
step "Generate Ansible inventory from Terraform output"
SERVERS_JSON="$(terraform -chdir="${TF_DIR}" output -json servers)"
VPC_CIDR="$(terraform -chdir="${TF_DIR}" output -raw vpc_cidr)"

for role in api payments logs; do
  ip="$(jq -r --arg r "${role}" '.[$r].public_ip // empty' <<<"${SERVERS_JSON}")"
  [[ "${ip}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "No valid public IP for '${role}' in terraform output (got '${ip}')"
done

TMP_INV="$(mktemp)"
{
  echo "# GENERATED by pipeline.sh at $(date -u '+%Y-%m-%dT%H:%M:%SZ') from 'terraform output -json servers'."
  echo "# Do not edit by hand: IPs change whenever Terraform recreates a server."
  echo "[kijanikiosk]"
  jq -r 'to_entries | sort_by(.key)[] |
    "\(.key) ansible_host=\(.value.public_ip) private_ip=\(.value.private_ip) tf_app_port=\(.value.app_port)"' \
    <<<"${SERVERS_JSON}"
  echo
  echo "[kijanikiosk:vars]"
  echo "vpc_cidr=${VPC_CIDR}"
} > "${TMP_INV}"
mv "${TMP_INV}" "${INVENTORY}"
cat "${INVENTORY}"

# --- Ansible ------------------------------------------------------------------
step "ansible-playbook kijanikiosk.yml"
cd "${ANSIBLE_DIR}"
ANSIBLE_OUT="$(mktemp)"
ANSIBLE_RC=0
ansible-playbook -i inventory.ini kijanikiosk.yml | tee "${ANSIBLE_OUT}" || ANSIBLE_RC=${PIPESTATUS[0]}
[[ "${ANSIBLE_RC}" -eq 0 ]] || die "ansible-playbook failed (exit ${ANSIBLE_RC})"

# Sum changed= across the PLAY RECAP so the idempotency result is one line.
TOTAL_CHANGED="$(grep -Eo 'changed=[0-9]+' "${ANSIBLE_OUT}" | awk -F= '{s+=$2} END {print s+0}')"
rm -f "${ANSIBLE_OUT}"

step "Summary"
info "Terraform: $([[ ${PLAN_RC} -eq 0 ]] && echo 'no changes (0 to add, 0 to change, 0 to destroy)' || echo 'changes applied')"
if [[ "${TOTAL_CHANGED}" -eq 0 ]]; then
  info "Ansible:   changed=0 on all three hosts (idempotent)"
else
  info "Ansible:   ${TOTAL_CHANGED} changes applied (expected on a first run; a re-run should show changed=0)"
fi
info "Inventory: ${INVENTORY}"
terraform -chdir="${TF_DIR}" output -no-color ssh_commands
info "Pipeline finished OK $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
