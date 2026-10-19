## Week 5: KijaniKiosk CI pipeline, board-ready delivery

Tendo, this week I built the full CI path for `kijanikiosk-payments`, from a commit to a versioned package in Nexus, all defined as code: Jenkins 2.580.1 LTS (configuration as code, secrets from Docker secrets) and Nexus 3.97.0 run on the VM, and the Jenkinsfile runs a pinned `node:22.23.3-alpine3.24` agent through Lint → Build → parallel Verify (Test ‖ Security Audit) → Archive (fingerprinted) → Publish. Publish uses `withCredentials` with `.npmrc` created and deleted in one `sh` step, and the post block covers always, success, failure and changed. The final green run took about a minute, and each green run has its own `1.0.0-<sha>` version in Nexus. I faulted all six stages with real commits, each followed by a revert that returned the run to green, and the drill caught a real bug: the failure notice named the wrong stage when parallel branches raced, which I fixed and re-tested. The design decision I am most confident about is enforcing version uniqueness in the registry (`allow_once`) rather than in the pipeline: a re-run of an already-published commit fails Publish with a 409 (build #17) instead of silently replacing bytes a deployment may already have pulled, and no pipeline change can bypass it. The next thing I would add is a multibranch pipeline triggered by GitHub webhooks, so every pull request is verified before review and publishing is limited to `develop`/`main` with an orderable version that the Week 7 CD side can reliably sort.

### Deliverables (`week5/friday/`)
| File | Contents |
|---|---|
| `../../Jenkinsfile` | Final pipeline (repo root) |
| `green-pipeline-run.txt` | Full log of the final green run: Docker image, parallel stages, masked credentials, artifact URL, runtime |
| `nexus-versions-screenshot.png` | Nexus UI showing multiple `kijanikiosk-payments` versions |
| `fault-injection-log.md` | Six stages faulted and restored, observed behaviour and rationale per row |
| `ci-pipeline-board-document.md` | The document for Nia (744 words) |
| `credential-audit.txt` | Five credential checks across Jenkinsfile, full git history and every build log |
| `reflection.md` | Answers to the three reflection questions |
| `evidence/` | Console log and stage table for every build, plus drill summaries |
| `infra/`, `tools/`, `kijanikiosk-payments/` | The stack, the scripts that run and audit it, and the service it builds |

### Reflection
The three answers are in [`reflection.md`](reflection.md). In short:
1. **The tension:** "declare every variable" vs values only known at run time. Truthful failure notices won.
2. **The two registers:** the same immutability guarantee, with the mechanism vs the reason.
3. **What breaks first at 40 developers:** the single-branch, publish-every-commit trigger model.
