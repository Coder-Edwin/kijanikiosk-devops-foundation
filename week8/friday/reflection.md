# Week 8 Friday Reflection

## 1. Automating the whole pipeline: which step is hardest to make reliable?

The sequence was build, tag, push, pull, deploy, verify and self-heal. The hardest step to make reliable in a Jenkins job is **verify**: proving the new Pods actually serve the new version before the job reports success.

Every step before it fails loudly. A broken build, a rejected push or a missing tag stops the pipeline with a non-zero exit code. Verification fails quietly. `kubectl rollout status` reported success after 18 s here, but "rolled out" only means the containers started. It doesn't mean they answer with the right version. The failure I worry about most in an automated run is a **false green**:
- the rollout completes;
- the NodePort curl hits an old Pod still terminating, or a Pod from a previous tag;
- the job compares nothing and passes.

Today's run only caught this because I compared the `version` field in the `/health` response with the computed tag (`1.8.0-3d51203`). Two other failures surfaced during the run:
- The in-cluster check printed nothing because the curl Pod finished before `kubectl run -i` attached. A human noticed; an automated job would have passed.
- The commit step failed (no git identity on the VM), but the script carried on and printed DONE.

I have since fixed both in `run-pipeline.sh`: it reads the curl Pod's logs, and it stops on a failed commit. In Jenkins I would make the verify stage poll `/health` until every Endpoint reports the new tag. It would fail on any mismatch or empty body, and read the curl Pod's result from `kubectl logs`, not from attach.

## 2. Rewriting one Nia sentence for Tendo

**Nia version:** "During today's test we deliberately removed one of the two running copies of the payments service. The platform noticed and had a healthy replacement running 3.4 seconds later."

**Tendo version:** "`kubectl delete pod kk-payments-6b7dcb6766-gvtvb` at T0 02:31:38.797. The ReplicaSet controller created `kk-payments-6b7dcb6766-gzj56`, which reached Running at 02:31:42.149 and Ready 12 ms later (there is no readiness probe yet). That's 3.4 s, with the Service routing to `jrrll` throughout and the image already cached on the node."

**What is lost:** the conditions that make the number true. 3.4 s is a warm-cache, single-node figure, and "Ready" currently equals "process started" because there is no readiness probe. A cold pull on a new node would be much slower. The board version can't carry those caveats without becoming a runbook. So the honesty paragraph has to do that work, and Nia should quote it as "seconds, not minutes", not as a guarantee.

**What is gained:** the decision-relevant fact survives. Recovery is automatic and fast, and customers were served throughout. A non-technical reader can act on that without knowing what a ReplicaSet is.

## 3. Hardcoded values that should move to a ConfigMap or Secret

| Hardcoded today | Where | Belongs in | Problem if it stays |
|---|---|---|---|
| `PORT=3001` | `ENV` in `Dockerfile.production` | ConfigMap | Changing the port needs an image rebuild and a new tag, which mixes a config change into the release history. The Service `targetPort` and the HEALTHCHECK URL must also be changed by hand to match. |
| `NODE_ENV=production` | `ENV` in the Dockerfile | ConfigMap | The same image can't run in staging with staging behaviour. You end up with one image per environment, which defeats "build once, run anywhere". |
| `APP_VERSION` | Baked in at build time | Stays in the image (deliberately) | The exception: it must describe the image itself, so it shouldn't vary by environment. |
| Image registry path `ghcr.io/coder-edwin/...` | Deployment manifest | Kustomize/Helm value per environment (not a Secret) | Moving registries or promoting between registries means editing every manifest. |
| `replicas: 2` and the CPU/memory requests and limits | Deployment manifest | Per-environment overlay values | Production and a developer's minikube need different numbers. Hardcoding them means either overspending in dev or underprovisioning in prod. |
| Registry credentials | Already a Secret (`kijani-registry-credentials`), referenced by name only | Secret | Already correct. But it was created from the full `~/.docker/config.json`, so it holds every registry login on that VM. It should be scoped to GHCR only and rotated. |
| Future payment-provider keys and database URL | Not present yet | Secret (keys, DB password) and ConfigMap (hosts) | The moment they're added as `env:` literals, they land in Git history, and rotating a leaked key means a new release. |
