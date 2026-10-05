# KijaniKiosk Staging: Security Decisions

*Prepared for Nia. Written so each point can be repeated to the board without a technical background.*

## What this document covers

KijaniKiosk's staging environment is now built from written instructions rather than by hand. One set of instructions creates three servers in Amazon's cloud: one for the customer-facing shop, one for payments and one that collects records of what happened. A second set of instructions then sets up every server the same way, every time. This document explains the security choices built into those instructions, what each one protects us from, and, just as important, what it does not.

The approach is layered: no single control is trusted alone, so an attacker who passes one layer meets another. The table summarises every control; the sections after it explain the ones that matter most to the board.

## How the controls fit together

| Control | What it does | Risk mitigated |
|---|---|---|
| Cloud firewall for admin access | Admits only the engineer's own internet address | Strangers breaking into servers |
| Internal-only payments and records servers | Answer only to our own servers | Payments attacked from the internet |
| Key-based login | No passwords; a secret key stays on the engineer's laptop | Stolen or guessed passwords |
| Locked central infrastructure record | Encrypted, versioned, one change at a time | Engineers overwriting each other's work |
| Official server images | Latest publisher image, found automatically | Unknown or outdated software |
| Protected identity tokens | Cloud credential service demands signed requests | Theft of cloud credentials |
| Encrypted disks | Stored data unreadable without Amazon's keys | Exposure of mishandled hardware |
| Firewall on every server | Blocks anything not allowed; slows repeated logins | A misconfigured cloud firewall |
| Payments sandbox | Read-only system, no privileges, internal network only | A code flaw becoming server takeover |
| Separate service accounts | Each program has its own non-login account | One breach spreading to others |
| Durable, capped logs | Survive restarts; rotated so disks never fill | Lost evidence; full-disk outages |

## The infrastructure decisions

**Who may reach the servers.** Earlier practice setups left administrative access open to the whole internet. For KijaniKiosk, the pipeline looks up the address of the engineer running it and allows only that address. Payments and records servers go further: they never accept connections from the internet, only from our own servers. This is the single biggest reduction in risk in the whole setup, because most attacks on new servers are automated scans that start within minutes of a machine coming online.

**How engineers prove who they are.** There are no passwords on these servers. Each engineer holds a private key on their own laptop, and only the matching public half is placed on the servers. A key cannot be guessed the way a password can.

**Keeping one trustworthy record.** The infrastructure tool keeps a record of everything it has created. That record now lives in a private, encrypted storage area in our cloud account rather than on one person's laptop. Every previous version is kept, so a mistake can be undone. It is also locked while a change is running: if two engineers start changes at the same moment, the second is stopped with a clear message instead of both silently corrupting the record.

**Starting from a known image.** Previously the server image was copied by hand, which works in only one region and goes stale. The instructions now ask Amazon for the publisher's latest official image. Moving existing servers onto a newer image is a deliberate decision rather than something that happens by surprise.

## The server decisions

**The payments service is boxed in.** Even if an attacker found a flaw in the payments program, the operating system would stop them doing much with it. The program cannot change system files, cannot gain administrator rights, cannot see other users' files or programs, and can only talk to our internal network. The operating system's own security scoring tool rates this setup at 1.1 on a scale where 10 is fully exposed; our target, carried over from last week, was below 2.5. The pipeline re-checks this score on every run and stops if it slips.

**Each program has its own identity.** The shop, payments and records programs each run under a separate account that nobody can log into. If one program is compromised, the attacker inherits an account that owns almost nothing and cannot reach the other programs' files.

**Every server is built identically, twice over.** The pipeline was run twice in a row. The second run found nothing to change, on the infrastructure side or on any of the three servers. That is the proof Tendo asked for: the environment is a repeatable specification, not a one-off. If a server is lost, it can be rebuilt to exactly the same standard in minutes, by any engineer.

## What this does not protect against

This posture protects the servers; it does not yet protect the business end to end. The payments service is a placeholder, so real payment security, including how the M-Pesa keys are stored, is still ahead of us; those keys must come from a dedicated secrets service, never from these instructions. Records are kept on each server, so an attacker with full control of one server could still erase its local history until we ship records off the machine. Our address restriction trusts the engineer's network; anyone sharing that office connection shares that trust. Patching depends on automatic updates and periodic rebuilds, and nobody is alerted if a server misbehaves. The infrastructure record is locked against collisions, but anyone with broad access to our cloud account could still alter or delete it. Finally, none of this replaces reviewing the application code itself, which is where most real breaches begin.

---

Evidence: `Overall exposure level for kk-payments.service: 1.1 OK`
