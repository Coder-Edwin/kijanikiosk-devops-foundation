# Reflection

## Where were you tempted to take shortcuts?

**1. One NAT Gateway instead of two.** A NAT Gateway is billed hourly plus per GB, and one shared NAT would have halved that cost. It was tempting to call it "good enough for launch". But a single NAT in AZ-a means that if AZ-a goes down, the servers in AZ-b lose outbound access too — and so lose the ability to confirm M-Pesa payments. That would quietly undo the whole point of running in two AZs. I kept two and wrote down why, so nobody "optimises" it away later without seeing the trade-off.

**2. Putting the app servers in the public subnet.** It would have made the diagram simpler and removed the NAT entirely. It would also have given every app server a public IP and made the security group the only thing standing between the internet and the application. Segmentation is about not relying on a single control.

**3. `s3:*` on the bucket.** Writing a precise IAM policy took longer than granting everything and "tightening it later". In practice, "later" rarely comes, and broad policies are one of the most common causes of cloud data leaks. I listed exactly what the receipt task does and granted only that — which also surfaced the useful decisions to drop `ListBucket` and `DeleteObject`.

**4. Committing everything straight to `main`.** For a solo documentation project, branches and a PR feel like ceremony. I used them anyway, because the habit matters more than this one repository, and because the PR is where the reasoning gets reviewed.

## Which architectural decision required the most reasoning?

**Choosing the region.** Every other decision had a fairly standard "right answer" (private databases, least privilege, multi-AZ). The region choice was a genuine trade-off between competing goods:

- **Cape Town** — closest to customers, keeps data in Africa, but costs more.
- **Ireland** — cheapest and most mature, but further from users and requires documented safeguards for moving Kenyan personal data abroad under the Data Protection Act 2019.

What tipped it was thinking about what actually matters to an online shop: page speed at checkout directly affects sales, and legal simplicity matters for a small team with no compliance department. I also recorded that the decision rests on *assumed* latency figures that must be measured from real Kenyan networks before launch — the decision should be treated as a hypothesis until then.

A close second was the **IaaS vs PaaS decision for compute**, where a PaaS would honestly be less work to run. I chose EC2 because this stage of the project needs the networking to be explicit and reviewable, and I documented a clear trigger for moving to containers later.

## If the KijaniKiosk platform grows significantly, what would you improve first?

In priority order:

1. **Infrastructure as Code (Terraform).** Everything here is currently a design on paper. The first step is to express the VPC, subnets, route tables, security groups and IAM roles as Terraform, reviewed through the same PR workflow. Then the network checklist in `network-topology.md` can be enforced automatically by CI instead of relying on reviewers remembering it.
2. **CI/CD with automated checks.** GitHub Actions deploying via OIDC (no stored keys), running `terraform plan`, IAM policy validation and a security scanner on every PR — turning today's manual Feedback loop into an automatic one.
3. **Observability.** Dashboards and alarms on checkout latency, error rate and payment callback failures, so the team hears about problems before customers do.
4. **A third Availability Zone** and **a caching layer** (ElastiCache) for the product catalogue, to handle flash-sale traffic and survive an AZ failure with capacity still to spare.
5. **Move compute to containers on ECS Fargate**, once server patching starts costing more time than it saves in control.
