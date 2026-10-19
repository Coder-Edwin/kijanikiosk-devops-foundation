# Week 5 Friday: KijaniKiosk CI Pipeline

The CI pipeline for `kijanikiosk-payments`: every commit is linted, built, tested, security-audited, archived with a fingerprint and published to Nexus as `<semver>-<git-sha>`. The pipeline itself is the [`Jenkinsfile`](../../Jenkinsfile) at the repository root.

## Layout

| Path | What it is |
|---|---|
| `kijanikiosk-payments/` | The Node 22 service the pipeline builds. It handles M-Pesa phone normalisation, fee bands and idempotent payment intake. It has no runtime dependencies. |
| `infra/` | Docker Compose stack. **Jenkins** 2.580.1 LTS: Docker CLI added, plugins pinned in `plugins.txt`, everything configured by `casc.yaml`. **Nexus** 3.97.0. |
| `tools/setup-ci-stack.sh` | One-command bring-up. Generates the secrets and opens the firewall for Docker agents to reach Nexus. Configures Nexus: npm hosted repository with write policy `allow_once`, a least-privilege `ci-publisher` user, anonymous access off. Tests container → Nexus connectivity. |
| `tools/collect-build.sh` | Saves a build's full console log and per-stage results into `evidence/`. |
| `tools/fault-drill.sh` | Builds the fault and restore commits listed in a plan file, in order, through the real job. |
| `tools/credential-audit.sh` | The five credential checks. |
| `faults/` | Drill plans and the fault catalogue. |
| `evidence/` | Console log and stage table for every build, plus drill summaries. |

## Run it on the VM

```bash
git checkout feature/week5-ci-pipeline
sudo week5/friday/tools/setup-ci-stack.sh          # Jenkins on :8080, Nexus on :8081
# Jenkins → kijanikiosk-ci → Build with Parameters (default GIT_REF = the branch tip)
sudo week5/friday/tools/collect-build.sh last green # saves the log as green-pipeline-run.txt
sudo week5/friday/tools/credential-audit.sh | tee week5/friday/credential-audit.txt
```

Passwords are generated into `infra/secrets/`, which is git-ignored. Read them with `sudo cat`.

## Design notes

- **Agent → Nexus (Challenge A).** Inside the agent container, `localhost` is the container itself. `NEXUS_URL` is therefore the Docker bridge address, `http://172.17.0.1:8081`. ufw allows `172.16.0.0/12 → 8081/tcp`. The setup script proves both sides: the bridge address returns HTTP 200, and `localhost` returns `ECONNREFUSED`.
- **Stash scope (Challenge B).** This does not apply. The pipeline uses one Docker agent at the top level, so every stage shares one workspace and `package.json` is always present for `npm version` and `npm publish`.
- **Versioning.**
  - The Build stage runs `npm version <package.json version>-<first 7 of GIT_COMMIT> --no-git-tag-version` **before** building, so `dist/build-info.json` inside the tarball records the same version and commit.
  - An all-digit SHA prefix gets a `g` in front to stay valid semver.
  - Nexus `allow_once` makes a version immutable.
- **Credentials.**
  - The Nexus password lives in a Docker secret file and enters Jenkins through configuration as code, where it is stored encrypted.
  - The Jenkinsfile references only the ID `nexus-ci-publisher`.
  - The publish step is a single-quoted `sh` with `set +x`, so the encoded auth string is never echoed (Jenkins masks the raw password but not its base64 form).
  - `.npmrc` is written and removed in that same step, with a `trap` so it is removed even if the publish fails.
