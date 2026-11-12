# KijaniKiosk Capstone: kk-payments from commit to production

Track A (Infrastructure-First). This folder takes kk-payments from the Week 8 container pipeline to a gated, two-environment delivery system: staging and production namespaces built as code, a Jenkins pipeline with a smoke test and a recorded production approval, Prometheus alerting, and the receipt chain running on LocalStack.

> **Status:** Capstone Session 1. Scope and architecture are complete; the implementation folders are added phase by phase (see the roadmap below).

## Documents

| Document | Purpose |
|---|---|
| [`docs/scope.md`](docs/scope.md) / [`docs/scope.pdf`](docs/scope.pdf) | Problem statement, in/out of scope, measurable success criteria |
| [`docs/architecture.svg`](docs/architecture.svg) / [`docs/architecture.png`](docs/architecture.png) | System diagram; every arrow is labelled with what flows across it. Source: [`docs/architecture.dot`](docs/architecture.dot) |
| [`docs/ai-governance-log.md`](docs/ai-governance-log.md) | Record of every AI-assisted change: what it produced, what it got wrong, what was changed |

## Planned layout

```
capstone/
├── README.md
├── Jenkinsfile              # delivery layer: build → staging → smoke test → approval → production
├── app/                     # kk-payments service (TypeScript), Dockerfile.production
├── k8s/                     # one Deployment + Service manifest used by both environments
├── infra/
│   ├── terraform/           # creates the kijani-staging namespace
│   └── ansible/             # per-environment ConfigMaps and pull secret
├── monitoring/              # Prometheus config and alert rules
├── serverless/              # receipt chain Lambdas on LocalStack
├── scripts/                 # smoke test and helper scripts
└── docs/                    # scope, architecture, governance log, test plan, feedback log
```

## Roadmap

| Phase | Layer | Outcome |
|---|---|---|
| 1 | Planning | Scope document, architecture diagram, repository structure |
| 2 | Infrastructure | `kijani-staging` created by Terraform, configured by Ansible |
| 3 | Runtime | Probes, limits, JSON logs, metrics, environment-specific ConfigMaps |
| 4 | Delivery | Jenkins: merge to `main` → staging → smoke test → approval gate → production |
| 5 | Intelligence | Prometheus alert rule; receipt chain on LocalStack |
| 6 | Proof | Fault demo, peer review, slides, `v1.0.0`, reflection |
