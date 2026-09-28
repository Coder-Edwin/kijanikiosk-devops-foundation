# Region and Availability Zone Design

## Decision

| Item | Choice |
|---|---|
| Primary region | **AWS `af-south-1` (Africa – Cape Town)** |
| AZs used | **2** (`af-south-1a`, `af-south-1b`); a third exists and is reserved for growth |
| Backups | Automated RDS snapshots + S3 in the same region; copy of RDS snapshots to a second region (`eu-west-1`, Ireland) for disaster recovery |

---

## Part 1 — Choosing the region

A region is a separate geographic area containing multiple isolated data centres. The choice affects latency, law, cost and which services are available. We compared the realistic options for a customer base centred on Kenya:

| Criterion | `af-south-1` Cape Town | `eu-west-1` Ireland | `me-central-1` UAE |
|---|---|---|---|
| **Latency to Nairobi** | Lowest of the three in most measurements; stays on the African continent | Higher — traffic crosses to Europe | Competitive, but routing varies by ISP |
| **Data protection** | Keeps customer data in Africa, the simplest story under Kenya's Data Protection Act 2019 cross-border transfer rules | Transfer out of Africa needs documented safeguards | Transfer out of Africa needs documented safeguards |
| **Cost** | Somewhat more expensive than older regions | Among the cheapest | Mid-range |
| **Service availability** | All services we need (VPC, EC2, ALB, RDS Multi-AZ, S3, KMS, SES alternatives) | Everything | Most things |
| **Number of AZs** | 3 | 3 | 3 |

**Why Cape Town wins:** for an online shop, **latency is revenue** — slow checkout pages lose customers — and keeping personal data on the continent reduces legal overhead. The price premium over Ireland is modest at our scale and is outweighed by these two factors.

**Caveats we record honestly:**
- Latency figures depend on the customer's ISP and undersea cable routing. Before launch we will measure real round-trip times from Safaricom and Airtel connections in Nairobi rather than relying on published estimates.
- Cloud providers add regions and edge locations over time. If a region or local zone closer to East Africa becomes available with the services we need, this decision should be reopened.
- For static assets (images, CSS, JS) a CDN (CloudFront) with edge locations in Africa serves content close to users regardless of region.

---

## Part 2 — Multi-AZ reliability

### What an Availability Zone is

An AZ is one or more physically separate data centres inside a region, with independent power, cooling and networking, connected to the other AZs by low-latency links. AZs are designed to **fail independently**: a flood, power failure or network fault in one should not take down another.

### Why we use more than one

If everything runs in a single AZ, a single data-centre incident takes KijaniKiosk offline. Running across two AZs means **any single AZ can fail and the shop keeps taking orders.**

### How each tier survives an AZ failure

| Tier | AZ-a | AZ-b | What happens if AZ-a fails |
|---|---|---|---|
| **Load balancer (ALB)** | node in public subnet A | node in public subnet B | ALB is inherently multi-AZ; health checks stop sending traffic to AZ-a within seconds |
| **App servers (EC2 ASG)** | ≥1 instance in private subnet A | ≥1 instance in private subnet B | ALB routes all traffic to AZ-b; Auto Scaling launches replacement instances in AZ-b until AZ-a recovers |
| **Database (RDS Multi-AZ)** | Primary | Synchronous standby | RDS promotes the standby automatically; the DNS endpoint moves to AZ-b. Typically 1–2 minutes of write interruption; no committed data lost because replication is synchronous |
| **NAT Gateway** | NAT-A in public subnet A | NAT-B in public subnet B | Private subnet B uses its own NAT-B, so outbound calls (e.g. to M-Pesa) keep working |
| **S3** | — | — | Regional service; AWS stores data across multiple AZs automatically |

### Design rules that make this work

1. **Everything stateful lives outside the app servers.** Sessions go in the database (or a cache later), uploaded files go in S3. So any app instance can be destroyed and replaced without losing data.
2. **Minimum capacity is set per AZ, not in total.** The Auto Scaling Group's minimum is 2, spread across both AZs, so there is never a moment when all instances sit in one AZ.
3. **One NAT Gateway per AZ.** A single shared NAT would be cheaper but would make AZ-a a hidden single point of failure for AZ-b's outbound traffic. We pay for two to remove it.
4. **Capacity headroom.** Each AZ must be able to carry the full load alone, at least briefly. We size so that one AZ's instances can handle normal peak traffic while Auto Scaling adds more.

### Why two AZs and not three?

Three AZs tolerate an AZ failure *and* still have redundancy afterwards, but cost more (a third NAT Gateway, more idle instances). For launch, two AZs remove the single-data-centre risk at the lowest cost. **Moving to three AZs is the first reliability upgrade once revenue justifies it** — the VPC already reserves address space for it.

---

## Part 3 — What multi-AZ does *not* protect against

Multi-AZ protects against a data-centre failure. It does **not** protect against:

| Risk | Mitigation |
|---|---|
| Whole-region outage | RDS snapshots copied to `eu-west-1`; documented (and occasionally rehearsed) restore procedure. Recovery would take hours, which is acceptable at this stage |
| Bad deploy or accidental data deletion | RDS point-in-time recovery (7-day retention); S3 versioning on the receipts bucket; ability to roll back to the previous app version |
| Security breach | IAM least privilege and network segmentation (see the other documents) |

### Targets

| Metric | Launch target |
|---|---|
| Availability | 99.9% (≈43 minutes of downtime per month) |
| RPO (data we can afford to lose) — AZ failure | ~0 (synchronous DB standby) |
| RTO (time to recover) — AZ failure | < 5 minutes, automatic |
| RPO / RTO — region failure | < 24 hours / < 8 hours, manual |
