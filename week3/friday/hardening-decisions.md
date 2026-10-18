# Production Server Security Decisions

**For:** Nia · **From:** Amina · **Scope:** the dedicated payments server for next sprint

## Summary

This server is built by one automated procedure, not by hand. Every setting below is applied identically on every build and checked at the end; if any check fails, the build reports it and stops. For the board, that means our security posture is written down, repeatable and verified.

One principle runs through it: each part of the system gets only the access its job needs, so a fault or break-in stays contained.

## The decisions, in plain language

**Each service runs under its own restricted identity.** The customer service, the payments service and the log service each run as separate accounts that cannot log in and hold no administrator rights. *Risk mitigated: an attacker who takes over one service cannot use it to sign in to the server or act as another service.*

**Each service is sealed inside its own enclosure.** Each service cannot change system files, cannot see other programs and can write to just one folder of its own. On the standard ten-point exposure scale, where lower is safer, the payments service measures about 1, well under our target of 2.5. *Risk mitigated: a flaw in the payments software cannot be turned into control of the whole server.*

**Payment settings are readable only by the payments service.** Each service's configuration lives in one place, readable only by that service. We removed an older copy left over from testing. *Risk mitigated: other services or staff accounts cannot read payment credentials, and there is no forgotten copy to leak.*

**The network only accepts traffic we have chosen.** The firewall starts from "refuse everything" and opens only remote administration, web traffic and the payments health check, all from our monitoring network. The payments service accepts connections only from the web front end on the same machine and from monitoring, enforced twice, by the firewall and by its own enclosure. Every rule carries a written explanation, and the rules are rebuilt from this specification rather than from four days of manual edits. *Risk mitigated: attackers cannot reach the payments service directly, and no forgotten rule leaves a hole open.*

**Logs survive and stay protected.** Activity records are kept across restarts, capped in size and rotated daily. We found and fixed a subtle issue: the nightly rotation would have quietly removed the main service's right to write, leaving gaps in the audit trail. Every build now tests a rotation. *Risk mitigated: we keep a complete, tamper-resistant record of what happened, which we need for incident investigation and for any payments dispute.*

**Software versions are locked, and changes need a person.** Key software is fixed at reviewed versions. If the build finds a different version, it stops and asks for a decision. We chose stopping over automatic downgrading because the likeliest cause of a difference is a security update, and silently undoing one on a payments server is worse than a short delay. *Risk mitigated: no unreviewed software change reaches the payments server.*

**The build reports health in a form anyone authorised can read.** A short status file records whether each service is answering, readable by operations without administrator rights. *Risk mitigated: problems are visible immediately, without extra access.*

## Controls at a glance

| Control | What it does | Risk mitigated |
|---|---|---|
| Dedicated service accounts (`kk-api`, `kk-payments`, `kk-logs`), no login, locked password | Each service runs as its own powerless identity | A compromised service cannot sign in or impersonate another |
| `ProtectSystem=strict`, `ReadWritePaths=` | System files are read-only; one writable folder per service | Tampering with the operating system or other services' files |
| `NoNewPrivileges=yes`, empty `CapabilityBoundingSet=` | Service can never gain administrator powers | Escalation from one service to full control |
| `SystemCallFilter=@system-service`, `RestrictNamespaces=yes`, `ProtectKernel*` | Limits the requests a service can make to the operating system | Attack techniques that rely on unusual requests |
| `IPAddressDeny=any` + `IPAddressAllow=` (payments) | Payments accepts connections only from the server itself and monitoring | Direct attacks on the payments service from any other network |
| `ufw` reset to default-deny, commented rules, port 3001 allowed on loopback and monitoring subnet before the deny | Firewall built from intent, in deliberate order | Unknown or forgotten openings; drift from manual edits |
| Config in `/opt/kijanikiosk/config`, `0640` per service; `/etc/kijanikiosk` removed | Settings readable only by their own service | Leakage of payment credentials; stale duplicate settings |
| ACLs with defaults on shared logs; logrotate `create 0660`, `su kk-logs` | Access rules survive nightly log rotation | Silent loss of audit logging after rotation |
| journald `Storage=persistent`, `SystemMaxUse=500M` | Records kept across restarts, size-capped | Lost evidence after a reboot; disk filling up |
| Version pins with holds; stop on mismatch (exit 3) | Software changes require a human decision | Unreviewed upgrades or downgrades on the payments server |
| Health file `0640`, group `kijanikiosk`, default ACL | Status readable by operations without administrator access | Blind spots, or over-granting access to see status |

## What this does not protect against

This work protects the server and its configuration, not everything. The payments software itself has not been written or reviewed, and a flaw that misuses its legitimate access, such as paying the wrong account, is outside what these controls can stop. Payment credentials are still stored on the server in a protected file rather than in a dedicated secrets vault. Logs are kept on this one machine, so someone who fully compromised it could delete them; copying them elsewhere is next on our list. There is no intrusion detection or alerting yet, and remote administration is limited by network address, not by personal identity with a second factor. Finally, one server is a single point of failure: if it goes down, payments stop until it is rebuilt, which the automated build makes a matter of minutes.
