# Integration notes: where the requirements collided

Each challenge: the conflict, the options considered, the choice, and why.

---

## Challenge A: `ProtectSystem=strict` and the EnvironmentFile

**The conflict.** `ProtectSystem=strict` makes the filesystem read-only to the service, and during the week I had configuration in two places: `/opt/kijanikiosk/config/` and an earlier `/etc/kijanikiosk/` from the Tuesday lab. The worry in the brief is that the service could fail to read its own configuration.

**What I found when I tested it.** Two facts changed the shape of the problem:

1. `EnvironmentFile=` is read by **systemd itself (PID 1) before the sandbox is applied**, not by the service process. Even a file under `/etc` would load. So `ProtectSystem=strict` never stops the unit from *starting*.
2. `strict` makes paths **read-only, not unreadable**. A service can still read a config file it opens at runtime under `/etc` or `/opt`. What `strict` blocks is *writing*, and a few other directives (`ProtectHome=`, `InaccessiblePaths=`, `TemporaryFileSystem=`) can block reading.

So the real conflict is not "can it read" but **"which copy is the truth, and who may change it"**. Two copies of `payments-api.env` in two places, with different owners, is exactly the kind of drift that caused Thursday's incident.

**Options considered.**

| Option | Effect |
|---|---|
| Keep config in `/etc/kijanikiosk` | Works for reading, but `/etc` files are root-owned by convention and readable by default; it splits ownership of KijaniKiosk across two trees. |
| `ReadOnlyPaths=/etc/kijanikiosk` / `BindReadOnlyPaths=` | Adds directives to grant something `strict` already allows. No security gain. |
| Move everything to `/opt/kijanikiosk/config`, remove the `/etc` copy | One location, owned by the access model, covered by the same ACL audit. |

**Choice.** Single location: `/opt/kijanikiosk/config/<service>.env`, `root:kk-<service>`, `0640`. Phase 4 detects `/etc/kijanikiosk`, backs it up to `/var/backups/kijanikiosk/<run>/` and removes it, so nothing can read a stale copy. The service can read its file (checked with the brief's `sudo -u kk-payments cat …` test in Phase 8) but cannot change it, because it is root-owned **and** outside the service's only `ReadWritePaths` entry. `kk-api` reading the payments file is tested as **denied**.

**Why.** It satisfies both requirements without adding a directive, and it turns a sandbox rule into a second layer behind file permissions instead of the only one.

---

## Challenge B: the monitoring user and ACL defaults

**The conflict.** The script runs as root, so the health file would be root-owned and unreadable to the operator and the monitoring system. `/opt/kijanikiosk/health` was not in Tuesday's model.

**Options considered.**

| Option | Problem |
|---|---|
| `chmod 644` the file | Readable by every account on the server, and only until the next write replaces it with a root umask. |
| Named-user ACL for Amina's account | Ties the model to one person; breaks when a monitoring agent is added. |
| Group ownership + setgid directory + **default** ACL | Every new file lands in `kijanikiosk` with group read, whoever writes it. |

**Choice.** `/opt/kijanikiosk/health` is `kk-logs:kijanikiosk 2750` with a default ACL of `group::r-x, other::---`; the file is `kk-logs:kijanikiosk 0640`. Readers are the `kijanikiosk` group; the script adds the operator account to it. Writers are root (provisioning) and `kk-logs` (runtime, via `ReadWritePaths`). It is added to `access-model-final.md`.

**Why.** Access is granted to a **role** (the group), not a person, and the default ACL makes it independent of the writing process's umask. Verified in Phase 8 by reading the file as the operator without sudo.

---

## Challenge C: logrotate `postrotate` and a service without reload

**The conflict.** The standard pattern is `postrotate systemctl reload kk-logs.service`. None of my units define `ExecReload=` (the placeholder process cannot reopen files on a signal), so `systemctl reload` fails with *"Job type reload is not applicable for unit kk-logs.service"* and logrotate reports a script error. In addition, systemd opened the log file on the service's behalf (`StandardOutput=append:`), so even a process that handled `SIGHUP` would not own that file handle.

On `PrivateTmp=true`: it does not affect this. Signals and `systemctl` requests go through PID 1, not through the service's filesystem namespace, so a private /tmp neither blocks nor helps the postrotate command.

**Options considered.**

| Option | Effect | Verdict |
|---|---|---|
| `systemctl reload` | Fails: no `ExecReload=` | Rejected |
| `systemctl kill -s HUP` | The placeholder dies on HUP (default action); `Restart=on-failure` restarts it, but through a "failure" path that pollutes alerts | Rejected |
| `copytruncate` | No restart needed, but conflicts with `create` (which Requirement 3 mandates), and lines written between copy and truncate are lost | Rejected for the payments audit trail |
| `systemctl try-restart <units>` | Clean stop/start; systemd reopens the log; does nothing if the service is stopped | **Chosen** |

**Choice.** `sharedscripts` + `postrotate systemctl try-restart kk-api.service kk-payments.service kk-logs.service`. I checked logrotate's source: with `su kk-logs kijanikiosk` set, postrotate scripts still run as **root**, so `systemctl` has the rights it needs.

**Why, and the cost.** It is correct today and needs no application support. The cost is a restart of each service once a day at rotation time, a sub-second gap. When real application code lands, the right fix is an `ExecReload=` that makes the service reopen its log, and then the postrotate line becomes `systemctl reload`. That is recorded as a known gap.

---

## Challenge D: the dirty VM and package holds

**The conflict.** Pinned versions plus a week of `apt upgrade` and hand-set holds. `apt-get install nginx=<pin>` is a no-op if versions match but a silent **downgrade** if they do not, and holds may or may not have stopped the drift.

**Options considered.**

| Option | Risk |
|---|---|
| Always `apt-get install pkg=<pin> --allow-downgrades` | Silently replaces a web server on a production payments node, possibly reverting a security update. |
| Fail loudly on mismatch | The run stops until a person decides. |

**Choice: compare first, fail loudly on mismatch.** Phase 2 reads the installed version with `dpkg-query` *before* touching apt. Equal: logged as "Already at pinned version, install skipped". Not installed: installed at the pin. Different: the script stops with **exit 3**, prints both versions and the two ways forward (update the pin through a reviewed commit, or downgrade deliberately), and changes nothing. After versions are confirmed, missing holds are re-applied; holds on packages outside the spec are reported, not removed, because someone else set them for a reason.

**Why.** On the node that will carry payments, an unplanned downgrade is a change nobody reviewed, and the most likely cause of a mismatch is a security update. Stopping costs a few minutes once; a silent downgrade could cost a breach or an outage. The pins live at the top of the script and can be overridden per environment (`KK_PIN_NGINX`, `KK_PIN_CURL`), so changing a pin is a visible, reviewable decision. (The brief's example pin `1.24.0-1ubuntu2` does not exist in Ubuntu 24.04's archive; the spec pins the reviewed version the archive ships at build time, `1.24.0-2ubuntu7.18`.)

---

## One more collision I hit: the firewall's "monitoring" rule vs. "deny 3001"

Requirement 4 asks for the kk-payments health endpoint to be reachable from the monitoring subnet **and** for port 3001 to be denied from external sources. The health endpoint *is* on 3001. Resolution: three rules in deliberate order, because ufw stops at the first match:

1. allow 3001 on the loopback interface (nginx proxying)
2. allow 3001 from `10.0.1.0/24` (monitoring health checks)
3. deny 3001 from anywhere else

The verification phase checks the presence of each rule **and** that both allows come before the deny. The same allow-list is enforced a second time inside the unit (`IPAddressAllow=localhost 10.0.1.0/24`), so a future firewall mistake does not expose payments on its own.

I also added a **lockout guard**: restricting SSH to `10.0.1.0/24` would cut off my own session on a lab VM whose host is on a different network. The script detects established SSH sessions and keeps each source address allowed (comment: "operator SSH session (lockout guard)"); `KK_ADMIN_CIDR` adds one explicitly. In production this guard should be replaced by a bastion host inside the monitoring subnet.
