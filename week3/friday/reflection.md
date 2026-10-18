# Reflection: Week 3 Friday, KijaniKiosk Production Server Foundation

## 1. When did two requirements conflict?

The sharpest one appeared when I put Requirement 3 (the access model must survive logrotate) next to Tuesday's ACL model. On paper they agreed: the directory has default ACLs, so new files inherit `kk-api:rwx` and `kk-payments:r-x`. The trap is the `create` line. I had been thinking of `create 0640 kk-logs kijanikiosk` as "owner writes, group reads", which is the safe-looking choice. But logrotate sets the mode *after* the file inherits its ACL, and on a file with an ACL the group bits of the mode are the **mask**. `0640` means mask `r--`, so `kk-api`'s inherited `rwx` becomes effective `r--`. Nothing errors: the API just stops being able to write after the first night's rotation. `0660` is the only value that keeps both the write and the read.

Two smaller collisions followed from the same fix. Because the directory grants write to non-root accounts, logrotate refuses to touch it without `su`. And with `su` set, I had to confirm that the `postrotate` restart would still run with enough rights. Reading logrotate's source showed scripts switch back to root, so it does.

What I learned: permissions are not a static table. They are the result of an order of operations (directory default, then file create, then chmod), and the order is where the bug hides. That is why the script now *performs* a rotation and tests the result every run instead of trusting the configuration.

## 2. One sentence, rewritten for Tendo

**For Nia:** "Each service cannot change system files, cannot see other programs and can write to just one folder of its own."

**For Tendo:** "Each unit runs with `ProtectSystem=strict` and a single `ReadWritePaths=` entry (`kk-api` and `kk-logs` also get `shared/logs`), `ProtectProc=invisible` with `ProcSubset=pid`, `PrivateDevices=yes`, an empty `CapabilityBoundingSet=` and `NoNewPrivileges=yes`, giving 1.1 to 1.2 on `systemd-analyze security`."

**Gained:** precision and checkability. Tendo can open the unit and confirm each claim, and he can see the exceptions Nia's version hides: `kk-api` *can* write to the shared log folder, so "just one folder" is a simplification.

**Lost:** the consequence. Nia's sentence says what an attacker cannot do, which is what the board asks about. Tendo's lists mechanisms and leaves the reader to work out the meaning. It also invites a number-chase ("why not 0.7?") that hides the judgment calls, like rejecting `PrivateNetwork=`, that matter more than the score.

## 3. The most fragile part of the script

**Phase 5, the firewall**, for two reasons.

- **The source-address assumption.** The brief restricts SSH to the monitoring subnet. On my VM the host machine is on a different network, so I added a lockout guard that allows whichever address currently holds an SSH session. In a real environment that guard is wrong twice over: an operator connecting from a laptop would permanently widen the rule, and an automation runner with no session would be locked out the moment the reset runs. The run also resets ufw whenever the live ruleset differs from what the script last applied, which briefly drops custom rules on a live server.
- **The verification parses text.** The per-rule checks match `ufw status numbered` lines with regular expressions. A ufw version that formats interface rules or comments differently would make correct rules report FAIL.

To make it robust I would need to know: which network the operators and the automation actually connect from (a bastion host inside the monitoring subnet would remove the guard entirely); whether anything else on the target manages the firewall (a cloud security group, another agent) that a reset would fight with; and which ufw version is installed, or better, verify the generated `user.rules` file or the kernel's iptables/nftables rules directly instead of the human-readable status output.
