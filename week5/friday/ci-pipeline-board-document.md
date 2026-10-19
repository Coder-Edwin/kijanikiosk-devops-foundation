# How KijaniKiosk Checks Every Change Before It Can Reach Customers

*Prepared for Nia, for the board review*

## Why this matters

KijaniKiosk moves money for customers. A wrong fee or a security weakness is a financial and regulatory problem. Until now, checking a change depended on each developer remembering to do it. Now an automatic process checks every change, every time.

## What happens after a developer saves their work

When a developer saves a change to our shared codebase, an automated checker picks it up within a few minutes and runs six checks in a fixed order. Each check must pass before the next one starts. If all pass, the result is stored in our private software library under a unique version number. Only versions in that library can later be released to customers.

A full run takes about one minute. Our limit is ten minutes, and the system stops itself if a run ever takes longer.

| Step | What it checks | Why it matters |
|---|---|---|
| 1. Tidiness | The code follows our agreed writing rules | Catches careless slips in seconds, before slower checks run |
| 2. Assembly | The code can be packaged into a working product | A product that cannot be assembled cannot be released |
| 3a. Behaviour | Automated tests confirm, for example, the correct fee for each payment amount, and that a repeated request never charges a customer twice | Stops calculation errors before customers see them |
| 3b. Safety | The outside building blocks we rely on have no known serious security weaknesses | Stops us shipping a known way in for attackers |
| 4. Record-keeping | A sealed copy is filed with a fingerprint linking it to the exact change that produced it | Proves which change produced which product |
| 5. Storage | The sealed copy is placed in our private library under a unique version number | Gives every release a permanent identity |

Steps 3a and 3b run side by side to save time. Both must pass.

## Why the version number matters

Every stored version carries a release number plus a short code identifying the exact change behind it, for example `1.0.0-b30540a`. The library refuses a second product under a label it has already used, so a version always means exactly the same thing. If a problem appears, we can say exactly which change caused it, who made it and which checks it passed. For a financial services platform, that is the traceability an auditor or regulator will ask for.

## What Happens When Something Goes Wrong

If any check fails, the process stops at that point. Nothing after it runs, and nothing is placed in the library, so a faulty change cannot reach customers through this route.

The team is told immediately. The message names the check that failed, the exact change responsible, and links to the full record. When a healthy process turns faulty, that change of state is flagged separately, so a new problem cannot hide among routine messages.

The developer saves a corrected version, which goes through all six checks again from the start.

We tested this by deliberately breaking each step in turn:
- a tidiness error;
- a product that would not assemble;
- a wrong fee for payments between KES 1,001 and 1,500;
- a building block with a known serious weakness;
- a filing error;
- an attempt to store the same version twice.

Each time, the process stopped at the right step, stored nothing and named the problem. The corrected version then passed and was stored under a new number. The test also exposed a flaw in our own alerting: when two checks ran side by side, the message once named the wrong one. We fixed it and repeated the test to confirm.

## What this does not yet do

This process proves a change is ready to release. It does not release anything to customers. That is the next phase of work, and it will take products only from this library.
- **Scope of the tests.** The tests cover the payment rules we have written so far, not every possible situation.
- **Alerts.** Messages appear in the system's own records, not yet in email or chat.
- **Machine.** Everything runs on one machine and the library has no backup yet, so a failure of that machine would stop checking and could lose stored versions.
- **Second review.** No second person yet has to approve a change before it enters this process.

We will close each of these gaps before relying on this process for customer releases.
