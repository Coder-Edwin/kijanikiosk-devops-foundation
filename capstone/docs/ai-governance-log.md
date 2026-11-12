# AI Governance Log

Every AI-assisted change in this capstone is recorded here before it is merged. The AI output is treated as a draft from an untrusted contributor: it is reviewed, tested and corrected by the engineer, and the corrections are recorded.

**Format:** eight fields per entry (Week 10 format).
1. Date
2. Tool
3. Task
4. What the AI produced
5. What it got wrong
6. What the reviewer changed
7. How the output was verified
8. Governance checklist item

---

## Entry 1: Scope document and architecture diagram

| Field | Entry |
|---|---|
| **1. Date** | 2026-11-12 |
| **2. Tool** | Claude (Anthropic), used as a pair-programming assistant |
| **3. Task** | Draft the one-page scope document and the architecture diagram for Track A from the capstone brief and the Week 8 repository state |
| **4. What the AI produced** | `docs/scope.md` and `docs/scope.pdf`, plus `docs/architecture.dot` and its rendered SVG and PNG |
| **5. What it got wrong** | **(a)** The first diagram used a left-to-right layout and rendered 5,945 px wide, which is unreadable on a slide. **(b)** The deploy-to-smoke-test arrow had no label, although the rubric requires every connection to be labelled. **(c)** Production's receipt bucket was missing, so the diagram implied only staging writes receipts. **(d)** The first PDF embedded fonts (37 KB) and printed the in-scope list numbers clipped. |
| **6. What the reviewer changed** | Edwin Otwori reviewed the scope wording, all six success criteria and every labelled arrow in the diagram against the Track A brief on 2026-11-12. No edits were needed, and the content was kept as drafted after the AI's own corrections in field 5. |
| **7. How the output was verified** | Rendered the diagram and confirmed every edge has a label. Confirmed the PDF is exactly one page. Checked that the scope has five in-scope items and four out-of-scope items with reasons. Checked that each success criterion maps to a step that can be shown live. |
| **8. Governance checklist item** | *Human review of AI output before use:* nothing in this entry is merged to `develop` until the reviewer has completed field 6. |

---

## Entry 2: Infrastructure layer (Terraform + Ansible)

| Field | Entry |
|---|---|
| **1. Date** | 2026-11-12 |
| **2. Tool** | Claude (Anthropic), used as a pair-programming assistant |
| **3. Task** | Write the Terraform for the `kijani-staging` namespace and the Ansible playbook that configures both environments, plus a timed bootstrap script for success criterion S1 |
| **4. What the AI produced** | `infra/terraform/*.tf` (namespace, ResourceQuota, LimitRange), `infra/ansible/configure-environments.yml` with per-environment vars, and `scripts/bootstrap-infra.sh` |
| **5. What it got wrong** | **(a)** The first playbook read the pull secret with an unquoted jsonpath (`{.data.\.dockerconfigjson}`). Ansible's argument splitting strips that backslash, so kubectl would have looked up a key that does not exist. The task would have succeeded and copied an **empty** pull secret into staging, and `no_log` would have hidden it. Every staging pod would later have failed with ImagePullBackOff, far from the cause. **(b)** The summary query embedded double quotes that the same splitting would have mangled. **(c)** A Terraform comment claimed staging is "isolated from production". Only name and resource isolation exist: there is no NetworkPolicy, and minikube's default CNI would not enforce one. |
| **6. What the reviewer changed** | Edwin Otwori ran the playbook and the bootstrap on the Ubuntu VM. He then ran the RESET rehearsal (delete staging, rebuild in 11 s) and a second run to confirm idempotency (`changed=0`). He accepted the corrected code without further edits. |
| **7. How the output was verified** | Before committing, simulated Ansible's argument splitting with `shlex` on both jsonpath arguments. On the VM: `terraform apply` created 3 resources; the playbook ended `ok=8 changed=2 failed=0` and showed distinct `DB_HOST` and bucket values per namespace; the pull secret in staging has type `kubernetes.io/dockerconfigjson`. Evidence: `docs/evidence/s1-infra-bootstrap.txt` and `docs/evidence/s1-infra-reset.txt`. |
| **8. Governance checklist item** | *Secrets are never exposed by automation:* the pull secret is copied with `no_log: true`, never written to a file or the repository, and its value does not appear in either evidence file. |
