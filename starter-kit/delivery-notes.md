# DevOps Delivery Notes

How the three DevOps principles — **Flow**, **Feedback** and **Learning** (the "Three Ways") — show up in how the KijaniKiosk team delivers this starter kit and, later, the platform itself.

The point of this file is not to define the terms. It is to show where each one is *visible* in our day-to-day workflow, so a reviewer can check we are actually doing it.

---

## 1. Flow — moving work from idea to production smoothly

Flow is about making work move left-to-right (idea → code → review → production) quickly and in small pieces, without piling up in queues.

| Practice | Where you can see it in this repo |
|---|---|
| **Small batches** | Each document was written and committed separately rather than in one giant commit, so each change is easy to review and easy to revert. |
| **One branch per unit of work** | All starter-kit files were built on `feature/starter-kit-files`, cut from `develop`. `main` was never touched directly. |
| **Clear path to production** | `feature/*` → PR → `develop` → release PR → `main`. There is exactly one way for code to reach `main`, so nobody has to guess. |
| **Work made visible** | The pull request describes what changed and why. Anyone on the team can see what is in progress without asking. |
| **Limit work in progress** | One feature branch open at a time for this kit. Finishing and merging beats starting something new. |

**What we avoid:** long-lived branches that drift from `develop` for weeks and end in a painful merge; "big bang" releases where ten changes ship together and nobody knows which one broke checkout.

---

## 2. Feedback — finding problems early, while they are cheap to fix

Feedback is about shortening the time between making a mistake and finding out about it.

| Practice | Where you can see it |
|---|---|
| **Pull request review** | No change reaches `develop` without passing through a PR. The PR is where a second person asks "why is this subnet public?" *before* it becomes an outage. |
| **Reviewable design, not just code** | Infrastructure decisions (region, IAM, subnets) are written down in Markdown so they can be reviewed and commented on line by line, exactly like code. |
| **Branch protection (planned)** | `main` and `develop` will require an approved PR and passing checks before merge. |
| **Automated checks (next step)** | A CI job will lint Markdown, validate the IAM JSON files, and — once infrastructure is written as code — run `terraform validate` and a policy scanner on every PR. |
| **Production feedback (at launch)** | CloudWatch alarms on the load balancer's 5xx rate and latency, and on database CPU/storage, so the team hears about problems before customers tweet about them. |

**Feedback we built into the design itself:**
- The IAM policy is narrow, so if the application tries to do something unexpected, AWS *denies it and logs it* — that denial is a feedback signal, not just a block.
- The multi-AZ design is only useful if we *know* when an AZ fails; health checks on the load balancer are the feedback loop that triggers failover.

---

## 3. Learning — getting better every cycle

Learning is about turning experience (especially failures) into lasting improvements, and making it safe to experiment.

| Practice | Where you can see it |
|---|---|
| **Decisions recorded with reasons** | Every document in `starter-kit/` explains *why*, not just *what*. When a decision turns out wrong, the next engineer can see the original reasoning and change it deliberately rather than guessing. |
| **Reflection built into delivery** | `reflection.md` records where shortcuts were tempting and what to improve first. This is a mini-retrospective. |
| **Blameless post-incident reviews (at launch)** | When something breaks, the question is "what in our system allowed this?", not "who did it?". Findings become PRs against this repo. |
| **Git history as a learning record** | Commit messages explain intent. `git log` on any file tells the story of how our thinking changed. |
| **Safe experimentation** | Feature branches mean anyone can try an idea without risk to `develop` or `main`. A bad experiment is simply a branch that never gets merged. |

---

## How the three fit together in one change

Taking the network design as an example:

1. **Flow** — the network diagram and routing notes were written on the feature branch as a small, focused change.
2. **Feedback** — the PR asks reviewers to check one specific thing: *does anything in a private subnet have a route to the Internet Gateway?* That question is quick to answer and catches the most dangerous mistake.
3. **Learning** — if a reviewer spots a gap (e.g. "the database has no route out for patching — is that intended?"), the answer is written back into `network-topology.md`, so the next person doesn't have to ask again.
