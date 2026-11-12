# Week 8 vs Week 7: How We Now Deliver the Payments Service

**For:** Nia, Monday board presentation
**From:** Amina, Engineering
**Evidence:** every number below comes from the pipeline run recorded in this folder on 12 November 2026.

## The short answer

In Week 7 we delivered software by sending a list of setup instructions to each server and trusting every server to follow them the same way. In Week 8 we deliver a sealed, versioned package that is built once, stored in our private library, and run identically everywhere. A platform then keeps the requested number of copies of the service alive on its own.

That change gives us three things we did not have before: we know exactly what is running, we can return to any previous release in minutes, and a failed copy of the service replaces itself without anyone being woken up.

## Two numbers worth taking to the board

**The package is 94.6% smaller.** Our first attempt this week produced a package of 1,648 megabytes, because it carried every tool used to build the service. The production package we now ship is 89.8 megabytes. It contains only what the service needs to run. A smaller package downloads faster, starts sooner, costs less to store, and gives an attacker far fewer tools to misuse if they ever got inside it.

**A failed copy recovered in 3.4 seconds.** During today's test we deliberately removed one of the two running copies of the payments service. The platform noticed and had a healthy replacement running 3.4 seconds later. Throughout that time the second copy kept serving customers, so from the outside nothing went down. In Week 7, the same failure meant an engineer had to notice the alert, connect to the server and restart it by hand.

## Side-by-side comparison

| Concern | Week 7 (Ansible playbooks to VMs, app run by systemd) | Week 8 (container image in GHCR, run by Kubernetes) |
|---|---|---|
| **Deployment mechanism** | Playbook copies code and installs dependencies on each VM at deploy time; each server builds its own runtime, so two servers can drift apart | Image built once with `--no-cache`, tagged `1.8.0-3d51203` (package.json version + git SHA), pushed to GHCR; the Deployment manifest pulls that exact tag on every node |
| **Rollback mechanism** | Re-run the playbook against an older git ref; dependencies are reinstalled, so the "old" version may not match what originally ran | Point the Deployment `image:` at a previous tag (or `kubectl rollout undo`); the old image is unchanged in the registry, so the rollback is byte-identical |
| **Failure recovery** | systemd restarts a crashed process on the same VM; if the VM itself fails, a human must rebuild it and re-run the playbook | ReplicaSet keeps `replicas: 2`; a deleted Pod was replaced in 3.4 s while the Service routed traffic to the healthy Pod |
| **Scaling** | Provision a new VM, add it to inventory, run the playbook, update the load balancer: tens of minutes | Change `replicas` (or `kubectl scale`); new Pods start from the cached image in seconds and join the Service automatically |

## What this means in plain terms

Every release now carries a label made from two things: the version number the team agreed on, and the exact code snapshot it was built from. If a customer reports a problem, we can say which build they were using within seconds. If a release misbehaves, we switch back to the previous label, and we get back exactly what was running before, not an approximation rebuilt from instructions.

The package also runs under a restricted account rather than with full administrative rights, and the access key for our private library is held by the platform, never written into our code. We checked every file in this delivery for passwords and keys, and found none.

## What Week 8 does not yet solve

This is not yet a production-complete payments platform, and the board should not hear that it is. Everything today ran on a single practice machine, so if that machine fails, both copies of the service fail with it. The platform currently decides a copy is ready as soon as it starts, not when it can actually take payments, so a slow-starting copy could briefly receive customers it cannot serve. Settings that differ between test and live, such as addresses and account details, are still fixed inside the release instead of being supplied separately and securely. And building, checking and releasing are still started by a person rather than run automatically on every change. Week 9 addresses the readiness and settings gaps directly. Running across several machines and fully automating releases remain the next steps after that.
