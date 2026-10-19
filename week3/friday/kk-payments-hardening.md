# kk-payments hardening log

**Target:** `systemd-analyze security kk-payments.service` below **2.5**, with the service still starting and serving.
**Result:** **1.2 (OK)**, service active on port 3001.

## How the scores were measured

Each directive (or tightly related group) was added one at a time to the same unit file and scored with `systemd-analyze security --offline=true` (systemd 255, the version shipped with Ubuntu 24.04), so every step has a measured number. The final unit is then started on the VM by the provisioning script, and Phase 8 checks both that `kk-payments` is **active** and that its live score is below 2.5 (screenshot in `screenshots/`). Each intermediate step is a strict subset of the final unit's directives, so a final unit that starts means no intermediate step could have broken startup. If the final unit had failed, the procedure was the brief's: `daemon-reload`, `start`, `status`, then `journalctl -u kk-payments -n 30` to see which directive blocked what.

The service process is a placeholder (`python3 -m http.server`) because no payments code is deployed yet. That matters for judgment: every directive kept here must also suit a real payments process that talks to a card or mobile-money gateway over the network, reads its configuration and writes only its own data.

## Starting score

| Step | Unit contents | Score |
|---|---|---|
| 0 | Dedicated `kk-payments` account, `EnvironmentFile`, `ExecStart`; no sandboxing | **9.0 UNSAFE** |

Running as a non-root account is already in the baseline, which is why it does not start at 9.6.

## Directives added, one step at a time

| Step | Directive(s) added | Score after | Why, in one line | Breaks the service? |
|---|---|---|---|---|
| 1 | `NoNewPrivileges=yes` | 8.9 | The process can never gain privileges (no setuid escalation). | No |
| 2 | `ProtectSystem=strict`, `ReadWritePaths=/opt/kijanikiosk/payments/data` | 8.7 | Whole filesystem read-only; one writable directory. | No |
| 3 | `ProtectHome=yes` | 8.5 | Users' home directories invisible. | No |
| 4 | `PrivateTmp=yes` | 8.3 | Private /tmp; no shared temp files with other services. | No |
| 5 | `PrivateDevices=yes`, `DevicePolicy=closed` | 7.7 | No access to hardware devices. | No |
| 6 | `CapabilityBoundingSet=` (empty), `AmbientCapabilities=` | **5.5** | Removes every root capability: the biggest single drop. | No |
| 7 | `ProtectKernelTunables`, `ProtectKernelModules`, `ProtectKernelLogs`, `ProtectControlGroups` | 4.8 | Cannot change kernel settings, load modules, read kernel logs or edit cgroups. | No |
| 8 | `RestrictNamespaces=yes` | 4.1 | Cannot create namespaces (a common container-escape step). | No |
| 9 | `RestrictSUIDSGID`, `LockPersonality`, `RestrictRealtime`, `MemoryDenyWriteExecute` | 3.8 | No setuid files, no ABI tricks, no CPU starvation, no writable+executable memory. | No: Python has no JIT, so it never needs writable+executable memory |
| 10 | `ProtectClock`, `ProtectHostname` | 3.7 | Cannot change the clock (transaction timestamps) or hostname. | No |
| 11 | `SystemCallArchitectures=native` | **3.5** | Blocks 32-bit system-call entry points. Below 3.5 is where Page 3 stopped. | No |
| 12 | `SystemCallFilter=@system-service`, `SystemCallFilter=~@privileged @resources`, `SystemCallErrorNumber=EPERM` | **1.9** | Allow-list of ordinary service system calls; privileged and resource-control calls denied. First step **below 2.5**. | No |
| 13 | `RestrictAddressFamilies=AF_INET AF_INET6` | 1.5 | Only IP sockets: no raw packets, no netlink, no Unix sockets. | No: it only needs TCP |
| 14 | `IPAddressDeny=any`, `IPAddressAllow=localhost 10.0.1.0/24` | 1.4 | Kernel-level allow-list: only loopback (nginx) and the monitoring subnet. A second wall behind ufw. | No: nginx (loopback) and monitoring are inside the allow-list |
| 15 | `ProtectProc=invisible`, `ProcSubset=pid` | 1.2 | Cannot see other processes or most of /proc. | No |
| 16 | `UMask=0027`, `RemoveIPC=yes`, `KeyringMode=private` | 1.2 | Files it creates are not world-readable; no leftover IPC; private keyring. Below the scale's rounding, but each closes a real gap. | No |

**Final: 1.2 OK.** `kk-api` and `kk-logs` use the same common block with their own allow-lists and score **1.1** (target below 3.5).

### What made the difference beyond Page 3

Steps 1 to 11 are the Page 3 family and stop at 3.5. Steps 12 to 15 are what took the service below 2.5. The system-call filter alone is worth 1.6 points: `@system-service` is systemd's curated allow-list for ordinary daemons, and subtracting `@privileged` and `@resources` removes calls such as `setuid`, `mount`, `setrlimit` and `sched_setscheduler` that a payments process never needs. `SystemCallErrorNumber=EPERM` makes a blocked call fail with "permission denied" instead of killing the process, which is easier to diagnose from the journal.

## Directives investigated and NOT applied

| Directive | Score if added | Why it was rejected |
|---|---|---|
| `PrivateNetwork=yes` | 0.7 | Gives the service its own network namespace with only a loopback device. It could no longer receive connections from nginx or the monitoring subnet, and a real payments process could not reach its card or mobile-money gateway. It would score well and do nothing useful. |
| `PrivateUsers=yes` | 1.0 | Creates a user namespace that maps only root and the service's own user and group. The supplementary `kijanikiosk` group becomes "nobody", so the service can no longer traverse `/opt/kijanikiosk` (`0750 root:kijanikiosk`) to reach its own application directory. The process starts and then fails on every file it needs. |
| `RestrictAddressFamilies=none` | 0.9 | Removes IP sockets too. The service could not listen on 3001. |
| `DynamicUser=yes` | n/a | Allocates a throwaway UID at each start. It conflicts with the access model: ACLs on `shared/logs` and the environment file's group name a fixed `kk-payments` account, and the log files must keep the same owner across restarts and rotations. |
| `DeviceAllow=` (to remove the residual `char-rtc:r`) | 1.1 | Worth 0.1. `PrivateDevices=yes` already hides real devices; the residual read-only clock device is harmless. Not worth the risk of breaking time reads in a service where timestamps matter. |

The remaining 1.2 is made up of items that are deliberate: the service needs IP sockets (0.3), the host network (0.5), the shared group for the access model (0.1), the monitoring subnet in its allow-list (0.1), and group-readable files for the log model (0.1).

## Final unit file (as written inline by `kijanikiosk-provision.sh`)

```ini
# Managed by kijanikiosk-provision.sh (written inline). Do not edit on the server.
[Unit]
Description=KijaniKiosk payments service (financial transactions)
After=network-online.target
Wants=network-online.target
After=kk-api.service
Wants=kk-api.service
[Service]
Type=simple
User=kk-payments
Group=kk-payments
SupplementaryGroups=kijanikiosk
EnvironmentFile=/opt/kijanikiosk/config/payments-api.env
WorkingDirectory=/opt/kijanikiosk/payments/app
# Placeholder process until the application is deployed: serves app/ on the port.
ExecStart=/usr/bin/python3 -m http.server ${SERVICE_PORT} --bind ${BIND_ADDRESS} --directory /opt/kijanikiosk/payments/app
Restart=on-failure
RestartSec=5
# systemd (PID 1) opens the log before the sandbox applies; logrotate's
# postrotate try-restart makes it reopen the new file after rotation.
StandardOutput=append:/opt/kijanikiosk/shared/logs/kk-payments.log
StandardError=inherit

# ---- Filesystem ----
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
UMask=0027
# ---- Privilege ----
NoNewPrivileges=yes
CapabilityBoundingSet=
AmbientCapabilities=
RestrictSUIDSGID=yes
RemoveIPC=yes
KeyringMode=private
# ---- Kernel, devices, processes ----
PrivateDevices=yes
DevicePolicy=closed
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
ProtectClock=yes
ProtectHostname=yes
ProtectProc=invisible
ProcSubset=pid
LockPersonality=yes
MemoryDenyWriteExecute=yes
RestrictRealtime=yes
RestrictNamespaces=yes
# ---- System calls and network ----
SystemCallArchitectures=native
SystemCallFilter=@system-service
SystemCallFilter=~@privileged @resources
SystemCallErrorNumber=EPERM
RestrictAddressFamilies=AF_INET AF_INET6
# Payments may write only its own data directory: shared logs are read-only to it.
ReadWritePaths=/opt/kijanikiosk/payments/data
# Only loopback (nginx) and the monitoring subnet may connect.
IPAddressDeny=any
IPAddressAllow=localhost 10.0.1.0/24

[Install]
WantedBy=multi-user.target
```

## Evidence

- `screenshots/04-kk-payments-security.png`: `sudo systemd-analyze security kk-payments.service` on the VM, final line below 2.5.
- `screenshots/05-kk-api-kk-logs-security.png`: final lines for `kk-api` and `kk-logs`, both below 3.5.
- `provision-run-dirty.log` and `provision-run-clean.log`: Phase 8 checks "kk-payments exposure … is below 2.5" and "kk-payments is active".
