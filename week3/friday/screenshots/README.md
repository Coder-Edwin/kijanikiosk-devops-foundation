# Evidence screenshots

Take these on the VM while running the steps in `../README.md`, and save them here with these names:

| File | What it shows | Taken after |
|---|---|---|
| `01-dirty-state-before.png` | Terminal with the audit output (accounts already existing, ACL/ufw drift) | `tools/01-audit.sh` |
| `02-dirty-run-verification-pass.png` | The verification summary of the first run: every check PASS, exit 0 | `tools/02-run-provision.sh dirty` |
| `03-getfacl-four-directories.png` | `getfacl` for `/opt/kijanikiosk`, `config`, `shared/logs`, `health` | `tools/03-post-verify.sh` |
| `04-kk-payments-security.png` | `sudo systemd-analyze security kk-payments.service` with the final score below 2.5 | `tools/03-post-verify.sh` |
| `05-kk-api-kk-logs-security.png` | Final score lines for `kk-api` and `kk-logs`, both below 3.5 | `tools/03-post-verify.sh` |
| `06-port-3001-external-blocked.png` | `curl -m 5 http://<vm-ip>:3001/` from the host timing out | `tools/03-post-verify.sh` |
