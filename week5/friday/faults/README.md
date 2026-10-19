# Fault-injection drill

Every fault is a real commit on `feature/week5-ci-pipeline`, followed immediately by a
`git revert` that restores it. `drill-plan.txt` lists the commits in order and
`tools/fault-drill.sh` builds each one through the real `kijanikiosk-ci` job, so the
evidence in `../evidence/` comes from the pipeline that is committed.

| Step | Stage | Fault | Expected first failure |
|------|-------|-------|------------------------|
| 1 | Lint | unused constant in `src/fees.js` | Lint (ESLint `no-unused-vars`) |
| 2 | Build | entry point stops exporting `createServer()` | Build (`scripts/build.js` API check) |
| 3 | Verify / Test | fee band 1,001-1,500 charges 25 instead of 23 | Test |
| 4 | Verify / Security Audit | production dependency `lodash@4.17.20` | Security Audit (`npm audit --audit-level=high`) |
| 5 | Archive | `archiveArtifacts` pattern `dist/*.tgz` matches nothing | Archive |
| 6 | Publish | the same commit is published a second time | Publish (Nexus `allow_once` rejects the duplicate version) |

Step 6 needs no code change: re-running an already-published commit is the fault.
It is restored by building the next commit, which carries a new version.
