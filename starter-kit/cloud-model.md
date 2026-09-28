# Cloud Service Model: IaaS, PaaS or SaaS?

## Decision

**KijaniKiosk uses a hybrid model, deliberately chosen layer by layer:**

| Layer | Model | Service | We manage | Provider manages |
|---|---|---|---|---|
| Network | **IaaS** | Amazon VPC, subnets, route tables, NAT Gateway | IP ranges, routing, security groups | Physical network, hardware |
| Web/application compute | **IaaS** | EC2 instances in an Auto Scaling Group behind an Application Load Balancer | OS patching, runtime, app deployment | Hypervisor, hardware, data centre |
| Database | **PaaS** | Amazon RDS for PostgreSQL (Multi-AZ) | Schema, queries, users, backup retention setting | OS, DB engine patching, replication, failover, backups |
| File storage (receipts, product images) | **PaaS** | Amazon S3 | Bucket policy, object layout | Durability, scaling, replication within region |
| Payments | **SaaS** | M-Pesa (Daraja API) and a card payment gateway | Integration and API keys | Everything else, including card-data compliance |
| Transactional email / SMS | **SaaS** | Amazon SES / an SMS provider | Templates, sending rules | Delivery infrastructure |
| Source control and CI | **SaaS** | GitHub + GitHub Actions | Repos, workflows, branch rules | The platform |

The rule we used: **own a layer only when owning it gives us something we actually need. Otherwise, rent it.**

---

## Reasoning, layer by layer

### Why not pure SaaS?

A SaaS e-commerce platform (a hosted shop builder) would get KijaniKiosk online fastest. We rejected it as the core because:

- **Local payment flows.** M-Pesa STK Push and callback handling need custom logic that off-the-shelf shop builders support poorly or through costly plugins.
- **Lock-in.** Product, customer and order data would live in someone else's schema, making it hard to leave.
- **Learning goal.** The team needs to build DevOps capability; SaaS hides the very infrastructure we need to understand.

We *do* use SaaS wherever the problem is not our differentiator — payments, email, source control. Nobody at KijaniKiosk should be running an SMTP server or storing raw card numbers.

### Why PaaS for the database?

The database is the most dangerous component to run ourselves. Getting replication, failover, point-in-time backups and engine patching right is a full-time job. RDS gives us:

- **Multi-AZ failover out of the box** (a synchronous standby in a second AZ — see `regions-azs.md`).
- **Automated backups and point-in-time recovery.**
- **Patching during a maintenance window we choose.**

The trade-off — less control over the engine, slightly higher cost than a self-managed EC2 database — is clearly worth it for a small team.

### Why IaaS (not PaaS) for compute?

This is the closest call. A PaaS like AWS Elastic Beanstalk, App Runner or a container service would reduce our operational work further. We chose EC2 in an Auto Scaling Group *for now* because:

- **The architecture exercise requires it.** We must design subnets, routing and IAM explicitly. EC2 in our own VPC makes every one of those decisions visible and reviewable.
- **Full control over networking.** We decide exactly which subnet each instance lives in and what it can reach.
- **Clear upgrade path.** The app is packaged so it can later move to containers (ECS on Fargate) with the same VPC, subnets and IAM role — a PaaS-style move that does not require redesigning the network.

**Cost of this choice we accept:** we must patch the OS and harden the image. We mitigate this with a standard hardened AMI and by keeping instances in private subnets with no public IPs.

### Shared responsibility — what this means for us

Because compute is IaaS, **security of the operating system is our responsibility**, not AWS's. Because the database is PaaS, **database engine patching is AWS's** — but database *users, passwords and network access* are still ours. Writing this down prevents the most common cloud mistake: assuming the provider is securing something they are not.

---

## When we would revisit this

| Trigger | Likely change |
|---|---|
| Team spends more time patching servers than shipping features | Move compute to ECS on Fargate (PaaS/serverless containers) |
| Traffic becomes very spiky (e.g. flash sales) | Consider serverless for bursty endpoints; add caching |
| Need for search across a large catalogue | Add a managed search service (PaaS) rather than building one |
