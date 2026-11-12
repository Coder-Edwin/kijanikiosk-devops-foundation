# AI Governance Log

Every AI-assisted change in this capstone is recorded here before it is merged. The AI output is treated as a draft from an untrusted contributor: it is reviewed, tested and corrected by the engineer, and the corrections are recorded.

**Format:** eight fields per entry (Week 10 format).
1. Date
2. Tool
3. Task
4. What the AI produced
5. What it got wrong
6. What the reviewer changed
7. How the output was verified
8. Governance checklist item

---

## Entry 1: Scope document and architecture diagram

| Field | Entry |
|---|---|
| **1. Date** | 2026-11-12 |
| **2. Tool** | Claude (Anthropic), used as a pair-programming assistant |
| **3. Task** | Draft the one-page scope document and the architecture diagram for Track A from the capstone brief and the Week 8 repository state |
| **4. What the AI produced** | `docs/scope.md` and `docs/scope.pdf`, plus `docs/architecture.dot` and its rendered SVG and PNG |
| **5. What it got wrong** | **(a)** The first diagram used a left-to-right layout and rendered 5,945 px wide, which is unreadable on a slide. **(b)** The deploy-to-smoke-test arrow had no label, although the rubric requires every connection to be labelled. **(c)** Production's receipt bucket was missing, so the diagram implied only staging writes receipts. **(d)** The first PDF embedded fonts (37 KB) and printed the in-scope list numbers clipped. |
| **6. What the reviewer changed** | *To be completed by Edwin after review.* Record each edit made to the scope wording, success criteria or diagram, or state explicitly what was checked and kept. |
| **7. How the output was verified** | Rendered the diagram and confirmed every edge has a label. Confirmed the PDF is exactly one page. Checked that the scope has five in-scope items and four out-of-scope items with reasons. Checked that each success criterion maps to a step that can be shown live. |
| **8. Governance checklist item** | *Human review of AI output before use:* nothing in this entry is merged to `develop` until the reviewer has completed field 6. |
