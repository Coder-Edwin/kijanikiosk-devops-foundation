# Week 5 Reflection

## 1. Two requirements in tension

**The tension.** Requirement 1 says to declare all environment variables explicitly. Two values the pipeline depends on cannot be known before the run starts:
- the artifact version, which needs the commit SHA;
- the stage that failed.

My first Jenkinsfile declared the failure-tracking variable `LAST_STAGE` in the `environment {}` block to satisfy "explicit". Declarative Pipeline makes values in that block read-only for the run, so `env.LAST_STAGE = env.STAGE_NAME` silently did nothing. Build #3's notice reported a Publish failure as "FAILED in stage 'Checkout'".

**First fix, and the second bug it exposed.** I moved the variable out of the block and set it at the start of each stage. The fault drill then exposed a second problem: Test and Security Audit run in parallel. Both wrote the same variable, and build #11 blamed Security Audit for a Test failure.

**What I prioritised.** I chose the truthfulness of the failure notice over a literal reading of "declare everything in one block":
- Every value that does not depend on the run is declared in `environment {}`: the image, the registry URL, the repository, the credential ID and the npm settings.
- The three values that do depend on it (`ARTIFACT_VERSION`, `PACKAGE_NAME`, `FAILED_STAGE`) are named in a comment in that block, with the reason they cannot live there.
- `FAILED_STAGE` is set in each stage's own `post { failure }` block, which only runs for the stage that actually failed, so parallel branches cannot overwrite each other.

Build #19 proved the fix: same fault, correct stage named.

**A smaller tension: fail-fast against parallel completeness.** With `failFast true`, a failing Test aborts a Security Audit that is still running. In practice the audit finished first in both runs, so the team saw both results. If the audit ever becomes slow, `failFast` will start hiding its result, and I would revisit that choice.

## 2. One sentence, two registers

**Board document:**
> "The library refuses a second product under a label it has already used, so a version always means exactly the same thing."

**For a Jenkinsfile comment or for Osei:**
> "`npm-kijanikiosk` is a hosted npm repository with `writePolicy: allow_once`, and the version is `<package.json semver>-<GIT_COMMIT[0..6]>`. A second `npm publish` of the same commit gets `409 Conflict … redeploy is not allowed`, which fails the Publish stage, so a published tarball is immutable and maps to exactly one commit."

**What is the same:**
- the guarantee: a version is written once and never changes;
- the consequence: an attempt to reuse a version is refused, not silently accepted.

**What is different:** the technical version adds the mechanism, which the board does not need:
- where the rule is enforced: the registry's write policy, not the pipeline;
- how the version string is built;
- the exact error code, so an engineer can recognise it in a log (build #17);
- the fact that the refusal shows up as a failed Publish stage.

The board version adds the reason it matters, which an engineer usually leaves unstated: "always means exactly the same thing", which is what an auditor needs.

## 3. From four developers to forty: what breaks first

**The trigger and branch model breaks first.** The job polls one branch every two minutes and publishes every commit it builds.

**Why it breaks at forty developers:**
- **Unchecked branches.** Forty developers work on dozens of branches and pull requests at once. Under this model their changes are not checked until they are merged into the one watched branch. The pipeline would catch problems after integration instead of before it.
- **Registry noise.** Every built commit becomes a permanent version in Nexus. With forty people, that becomes hundreds of `1.0.0-<sha>` pre-release versions a week. None of them sorts meaningfully: SHAs are not chronological, so `1.0.0-b30540a` vs `1.0.0-f01ee4a` says nothing about which is newer. The Week 7 deploy side would have no reliable way to pick "the latest good build".

**What I would change:**
1. **Replace the single polled job with a multibranch pipeline triggered by GitHub webhooks.** Every branch and pull request gets the same Lint, Build, Verify and Archive checks, and the result is reported back on the pull request before review.
2. **Publish only from `develop` and `main`** (`when { branch ... }` on the Publish stage). Feature branches are verified and archived but never written to the registry.
3. **Make published versions orderable.** Bump the semver on merge, or add a build counter (`1.0.0-<build>.<sha>`), so the deploy side can sort versions while keeping the SHA for traceability.

**The next limit.** After that, the bottleneck becomes capacity. Two executors on the controller's own VM, with the controller also running Nexus, will queue builds at peak times. The fix is dedicated build agents, and moving Nexus off the CI host with a backup.
