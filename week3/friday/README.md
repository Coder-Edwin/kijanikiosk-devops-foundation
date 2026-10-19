# Week 3 Friday: KijaniKiosk Production Server Foundation

One idempotent script that converges the week-long (dirty) Ubuntu 24.04 VM to the production spec for `kk-api`, `kk-payments` and `kk-logs`, plus the documentation Nia and Tendo asked for.

| File | Contents |
|---|---|
| [`kijanikiosk-provision.sh`](kijanikiosk-provision.sh) | The 8-phase script: units, logrotate, journald and nginx all written inline |
| [`pre-provisioning-audit.txt`](pre-provisioning-audit.txt) | Audit output before the first run, with interpretation |
| [`provision-run-dirty.log`](provision-run-dirty.log) | First run, on the dirty VM (exit 0, "FOUND/FIX" lines show detected state) |
| [`provision-run-clean.log`](provision-run-clean.log) | Second run straight after (exit 0, idempotency proof) |
| [`post-remediation-verification.txt`](post-remediation-verification.txt) | Forced rotation + `kk-api` write test, getfacl, ufw, scores |
| [`access-model-final.md`](access-model-final.md) | Access model with the health directory and the logrotate interaction |
| [`kk-payments-hardening.md`](kk-payments-hardening.md) | Score log from 9.0 to 1.2, rejected directives, final unit |
| [`hardening-decisions.md`](hardening-decisions.md) | The one-page document for Nia |
| [`integration-notes.md`](integration-notes.md) | Resolutions for Integration Challenges A to D |
| [`reflection.md`](reflection.md) | Answers to the three reflection questions |
| [`screenshots/`](screenshots/) | Evidence screenshots |
| [`tools/`](tools/) | Helpers that produce the evidence files on the VM |

## The eight phases

| Phase | What it converges | Dirty condition handled |
|---|---|---|
| 1 Pre-flight | root, Ubuntu 24.04, run lock, inventory of inherited state | lists all of D1 to D6 up front |
| 2 Packages | base packages; nginx and curl compared with their pins **before** install; holds | D5 (exit 3 on mismatch) |
| 3 Accounts | `kijanikiosk` + per-service groups; three nologin, locked system accounts | D1 |
| 4 Access model | directories, owners, modes, exact ACLs (incl. defaults), env files, log files | D2, Challenge A |
| 5 Firewall | ufw reset to default-deny and rebuilt from intent, every rule commented | D4 |
| 6 systemd + nginx | three hardened units written inline, drop-ins removed, nginx proxy | D6 |
| 7 Journal + logrotate | persistent journal capped at 500M; logrotate config, `--debug`, forced rotation | D3 |
| 8 Health + verification | `health/last-provision.json`, then every PASS/FAIL check; exit 1 on any FAIL | |

## Running it on the VM

```bash
git fetch origin && git checkout feature/week3-production-foundation
cd week3/friday

# Only if the VM was reset this week (say so in the PR):
#   sudo tools/simulate-dirty-state.sh

sudo tools/01-audit.sh                  # -> pre-provisioning-audit.txt   [screenshot]
#   paste the generated "# Expected dirty conditions" lines over the generic
#   list at the top of kijanikiosk-provision.sh

# If you are connected over SSH from a network other than 10.0.1.0/24, the
# script keeps your current session allowed automatically. To allow your
# host explicitly as well:  export KK_ADMIN_CIDR=<your-host-ip>/32
sudo -E tools/02-run-provision.sh dirty # -> provision-run-dirty.log      [screenshot of summary]
sudo -E tools/02-run-provision.sh clean # -> provision-run-clean.log
sudo tools/03-post-verify.sh            # -> post-remediation-verification.txt  [screenshots listed]
```

If Phase 2 stops with **exit 3**, the installed nginx or curl version differs from the pin. Decide deliberately: either update the pin at the top of the script in a commit that says why, or pass it for this environment (`sudo -E KK_PIN_NGINX=<version> tools/02-run-provision.sh dirty`).
