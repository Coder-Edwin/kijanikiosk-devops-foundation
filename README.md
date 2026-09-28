# KijaniKiosk DevOps Foundation

The engineering blueprint for the KijaniKiosk online platform, written **before** real customers arrive.

KijaniKiosk is an online shop serving customers in Kenya and the wider East African region. This repository does not contain the application itself. It records the infrastructure decisions the team agreed on, and the reasoning behind them, so that anyone joining later can see *why* the platform is shaped the way it is.

## What's inside

| File | Question it answers |
|---|---|
| [`starter-kit/delivery-notes.md`](starter-kit/delivery-notes.md) | How do Flow, Feedback and Learning show up in the way we work? |
| [`starter-kit/cloud-model.md`](starter-kit/cloud-model.md) | IaaS, PaaS or SaaS — which layer do we own, and why? |
| [`starter-kit/regions-azs.md`](starter-kit/regions-azs.md) | Where does the platform run, and how does it survive a data-centre failure? |
| [`starter-kit/iam-least-privilege.md`](starter-kit/iam-least-privilege.md) | What exactly is the application allowed to do in the cloud account? |
| [`starter-kit/iam/`](starter-kit/iam/) | The IAM trust policy and permissions policy as real JSON |
| [`starter-kit/network-topology.png`](starter-kit/network-topology.png) | How is the network segmented into public and private subnets? |
| [`starter-kit/network-topology.md`](starter-kit/network-topology.md) | The routing logic behind the diagram |
| [`starter-kit/reflection.md`](starter-kit/reflection.md) | Shortcuts, hardest decision, and what to improve first |

## Branching model

```
main        ← production-ready only; protected
  └─ develop   ← integration branch; every feature lands here first via PR
       └─ feature/*   ← one branch per unit of work
```

Work starts on a `feature/*` branch cut from `develop`, is reviewed in a pull request, and is merged into `develop`. `develop` is promoted to `main` when a release is ready. Nobody commits directly to `main` or `develop`.

## Target platform (summary)

- **Cloud:** AWS
- **Region:** `af-south-1` (Cape Town), 2 Availability Zones in use, 3 available
- **Network:** one VPC `10.0.0.0/16`, public subnets for the load balancer and NAT only, private subnets for the application and database
- **Model:** hybrid — IaaS for networking and compute, PaaS for the database, SaaS for payments, email and source control
