# Reflection: Week 4 Friday, KijaniKiosk Full IaC Pipeline

## 1. Where did two requirements conflict?

The clearest conflict was **Challenge D: Requirement 5 (kk-payments must keep `ProtectSystem=strict` and score below 2.5) against Requirement 2 (Ansible must template every config file the service reads).** Week 3 habits put configuration under `/etc`. Under `ProtectSystem=strict`, `/etc` is read-only to the service, so anything it needs to read *or regenerate* there at runtime becomes a trap.

Resolving it taught me that the brief's phrasing ("`/opt` is writable") is only half right, and the other half matters. `ProtectSystem=strict` makes the **whole** filesystem read-only to the process, `/opt` included; only paths listed in `ReadWritePaths=` are writable. So the fix was not "move it to `/opt` and it's writable". It was three separate decisions:

- **Reading config:** `payments-api.env` lives in `/opt/kijanikiosk/config/`, owned `root:kk-payments`, mode `0640`. The service can read it, cannot modify it, and no other account can read the M-Pesa settings. The playbook proves this every run with the brief's own test (`cat` as `kk-payments`, `changed_when: false`).
- **Traversal:** `/opt/kijanikiosk` is `0750 root:kijanikiosk`, so `kk-payments` needs membership of the `kijanikiosk` group just to *reach* its config. Permissions on the parent directory are as much a part of Challenge D as the file's own mode.
- **Writing:** the only writable path is `/opt/kijanikiosk/payments/data` via `ReadWritePaths=`. Logs are written with `StandardOutput=append:`, which systemd opens *before* applying the sandbox, so the service writes its log without having write access to `/var/log` at all.

I also found two quieter conflicts with **"the second run must show zero changes"**:

- **Dynamic AMI lookup vs. zero drift.** `most_recent = true` means the day Canonical publishes a new image, the second plan wants to replace all three servers. I added `lifecycle { ignore_changes = [ami] }`: the lookup chooses the image at creation, and rebuilding onto a new one becomes a deliberate `-replace`.
- **SSH from "your current IP" vs. zero drift and vs. the host firewall.** The security group is pinned to the operator's `/32`, so a changed IP between runs correctly shows a diff. Pinning the *host* firewall (ufw) to the same IP would be worse: Terraform can update the security group, but Ansible could no longer connect to fix ufw. So source restriction lives in the security group; ufw rate-limits port 22 from anywhere. I chose where each control lives by asking which tool can still reach the server after the control changes.

The lesson: requirements that each look simple can only be satisfied together if you know *when* each mechanism takes effect (PID 1 before the sandbox, Terraform before Ansible, plan-time lookups vs. stored state).

## 2. One sentence, rewritten for Tendo

**For Nia:** "The program cannot change system files, cannot gain administrator rights, cannot see other users' files or programs, and can only talk to our internal network."

**For Tendo:** "kk-payments runs under `ProtectSystem=strict` with a single `ReadWritePaths=` entry, `NoNewPrivileges=yes` and an empty `CapabilityBoundingSet=`, `ProtectHome=yes` and `ProtectProc=invisible`, `RestrictAddressFamilies=AF_INET AF_INET6`, and `IPAddressDeny=any` with `IPAddressAllow=localhost <vpc_cidr>`, giving an exposure of 1.1."

**What is gained:** precision. Tendo can check each claim against the unit file, and the sentence exposes what is *not* there: no `PrivateNetwork=` (it must serve the VPC), no `PrivateUsers=` (I left it out because user-namespace mapping interferes with the supplementary `kijanikiosk` group the service needs to traverse `/opt/kijanikiosk`). Those gaps are invisible in Nia's version.

**What is lost:** meaning. Nia's sentence says what an attacker *cannot do*, which is the question the board actually asks. Tendo's version lists mechanisms and leaves the reader to work out the consequence. It also loses honesty about scope: "cannot change system files" sounds absolute, while the technical version makes clear it is a sandbox around one process, not a property of the server.

## 3. The most fragile handoff

**The SSH handoff between Terraform's output and Ansible's first connection.** Everything after it depends on four facts lining up: the IP Terraform outputs is reachable from the machine running Ansible; the security group allows that machine's source address; the key Terraform uploaded is the key Ansible presents; and the instance has finished booting (cloud-init, apt locks).

The pipeline handles the version of this that exists on my laptop: the key path is read from one place (`group_vars`) and fed to Terraform, the operator IP is detected and passed in, `wait_for_connection` plus `cloud-init status --wait` absorb boot timing, and `StrictHostKeyChecking=accept-new` with a separate known-hosts file avoids clashes with recycled IPs. But in a slightly different real environment it breaks easily:

- **The detected IP is wrong.** `checkip.amazonaws.com` returns the NAT egress address. Behind a corporate proxy, a split-tunnel VPN or a CI runner pool, the address SSH actually leaves from may differ, and every host shows `UNREACHABLE`.
- **Production servers will not have public IPs.** The Week 1 network design puts app servers in private subnets. `public_ip` would be empty and the inventory step correctly fails, but there is no alternative route yet.
- **CI runners have no stable IP at all**, so a `/32` allow-list doesn't work for Week 5.

To make it robust I would need to know: how the target network is reached (direct, bastion host, VPN, or AWS Systems Manager), the egress address range of whatever runs the pipeline (laptop vs. CI), whether instances get public addresses, and how host keys should be trusted (pre-published via cloud-init or a known_hosts service rather than accepted on first use). The likely end state is SSM Session Manager as the Ansible connection, which removes port 22 and IP allow-listing from the handoff altogether.
