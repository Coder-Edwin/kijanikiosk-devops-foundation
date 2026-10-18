# KijaniKiosk access model (final, Week 3 Friday)

Tuesday's model, re-stated as the provisioning script now enforces it, plus two additions: the **health directory** (Integration Challenge B) and the **logrotate interaction** (Requirement 3). Every row below is applied by `kijanikiosk-provision.sh` Phase 3 or 4 and checked in Phase 8.

## Principals

| Principal | Type | Groups | Purpose |
|---|---|---|---|
| `kk-api` | system account, `/usr/sbin/nologin`, home `/nonexistent`, password locked | `kk-api` (primary), `kijanikiosk` | Customer-facing API behind nginx |
| `kk-payments` | same | `kk-payments`, `kijanikiosk` | Payments service (financial data) |
| `kk-logs` | same | `kk-logs`, `kijanikiosk` | Log collector, owns the shared logs and health output |
| `kijanikiosk` | group | members: the three service accounts + the operator | "May traverse /opt/kijanikiosk and read shared output" |
| operator (Amina's account) | human | `kijanikiosk` | Reads health and logs without sudo; never writes |
| root | | | Provisioning only |

Each service has its **own primary group**, so a file can be shared with exactly one service by setting its group, without an ACL.

## Directories and files

| Path | Owner:group | Mode | ACL | Who can do what |
|---|---|---|---|---|
| `/opt/kijanikiosk` | `root:kijanikiosk` | `0750` | none (minimal) | Members traverse; others see nothing |
| `/opt/kijanikiosk/config` | `root:kijanikiosk` | `0750` | none | Members list; files decide who reads |
| `config/api.env` | `root:kk-api` | `0640` | none | Only `kk-api` (and root) reads |
| `config/payments-api.env` | `root:kk-payments` | `0640` | none | Only `kk-payments` reads; `kk-api` is explicitly tested as **denied** |
| `config/logs.env` | `root:kk-logs` | `0640` | none | Only `kk-logs` reads |
| `/opt/kijanikiosk/<svc>` and `<svc>/app` | `root:kk-<svc>` | `0750` | none | Service reads its code, cannot change it |
| `/opt/kijanikiosk/<svc>/data` | `kk-<svc>:kk-<svc>` | `0750` | none | The only place the service may write (also its sole `ReadWritePaths`) |
| `/opt/kijanikiosk/shared` | `root:kijanikiosk` | `0750` | none | Traverse only |
| `/opt/kijanikiosk/shared/logs` | `kk-logs:kijanikiosk` | `2770`* | see below | `kk-logs` and `kk-api` write; `kk-payments` and the group read |
| `shared/logs/kk-*.log` | `kk-logs:kijanikiosk` | `0660`* | inherited | Same as the directory |
| `/opt/kijanikiosk/health` **(new)** | `kk-logs:kijanikiosk` | `2750` | default `group::r-x` | root and `kk-logs` write; the group (operator, monitoring) reads |
| `health/last-provision.json` **(new)** | `kk-logs:kijanikiosk` | `0640` | inherited | Readable by the group without sudo |

\* With named ACL entries the group permission bits show the ACL **mask**, not the owning group's access. `2770` on `shared/logs` means "mask rwx"; the owning group `kijanikiosk` is held to `r-x` by its own ACL entry.

### `shared/logs` ACL (access and default)

```
user::rwx                      # kk-logs (owner)
user:kk-api:rwx                # writes its log entries
user:kk-payments:r-x           # reads for audit correlation, cannot alter evidence
group::r-x                     # kijanikiosk: operator and monitoring read
mask::rwx
other::---
default:user::rwx
default:user:kk-api:rwx
default:user:kk-payments:r-x
default:group::r-x
default:mask::rwx
default:other::---
```

The **default** entries are what make the model survive change: any file created later in the directory, by a service, by an operator or by logrotate, inherits these entries automatically.

## Addition 1: the health directory (Challenge B)

| Question | Decision |
|---|---|
| Who writes? | The provisioning script (root) in Phase 8, and later `kk-logs` when it reports health itself. Nobody else. |
| Who reads? | The `kijanikiosk` group: the operator account and a future monitoring agent. Services other than `kk-logs` have no reason to read it but may, as group members; it holds no secrets. |
| Ownership | `kk-logs:kijanikiosk`, matching the account that will own it at runtime, so the file is not left root-owned and unreadable. |
| Mode | Directory `2750` (setgid keeps every new file in the `kijanikiosk` group); file `0640`. |
| ACL? | A **default** ACL only (`default:group::r-x`, `default:other::---`). It guarantees group read on files created by any process, whatever that process's umask, without granting anything new. No named-user entries are needed. |
| Verified by | Phase 8: file exists, is valid JSON, is `kk-logs:kijanikiosk 640`, and `sudo -u <operator> cat` succeeds. |

The operator is added to `kijanikiosk` by the script (`KK_OPERATOR_USER`, default the account that ran sudo). A login session that was open before the change must log out and back in to pick up the group.

## Addition 2: how logrotate interacts with the model (Requirement 3)

1. **Only default ACLs propagate.** logrotate's `create` directive sets owner, group and mode only. The named entries on the new file come from the directory's default ACL, applied by the kernel when the file is created. (Confirmed in logrotate 3.21's source: when `create` specifies a mode it does not copy the old file's ACL.)
2. **The `create` mode becomes the ACL mask.** logrotate sets the new file's mode after creating it, and on a file with an ACL the group bits of the mode *are* the mask. `create 0640` gives mask `r--`, so `kk-api`'s inherited `rwx` becomes **effective `r--`** and the API silently loses write access after the first rotation. `create 0660` gives mask `rw-`, so `kk-api` keeps `rw` and `kk-payments` keeps `r`. **This is the single most important number in the logrotate config.**
3. **logrotate must act as `kk-logs`.** Because the directory grants write to non-root accounts, logrotate refuses to rotate there ("insecure permissions") unless told which account to use: `su kk-logs kijanikiosk`. Acting as `kk-logs` also means new files are owned `kk-logs` and, thanks to the setgid directory, grouped `kijanikiosk`, exactly matching `create 0660 kk-logs kijanikiosk`.
4. **The services keep writing after rotation.** systemd opens each service's log file on its behalf. After rotation the open handle still points at the renamed file, so `postrotate` runs `systemctl try-restart` for the three units (they implement no reload; see integration-notes.md, Challenge C). logrotate runs postrotate scripts as root even when `su` is set.
5. **Verified every run.** Phase 7 appends a marker, forces a rotation, and Phase 8 checks each new file is `kk-logs:kijanikiosk 660`, that `kk-api`'s effective permission is `rw`, that `sudo -u kk-api touch shared/logs/test-write.tmp` succeeds and that `kk-payments` can read the new `kk-api.log`. The same test is in `post-remediation-verification.txt`.

## Interaction with systemd sandboxing

`ProtectSystem=strict` makes the whole filesystem read-only to each service; `ReadWritePaths=` re-opens only what the table above says it may write: `kk-api` its data directory and `shared/logs`, `kk-logs` its data directory, `shared/logs` and `health`, `kk-payments` its data directory only. The file permissions and the sandbox therefore agree: a service cannot write somewhere even if a permission were loosened by mistake.

## Evidence

`screenshots/03-getfacl-four-directories.png`: `getfacl` for `/opt/kijanikiosk`, `config`, `shared/logs` and `health`. The same output is in `post-remediation-verification.txt`, section 2.
