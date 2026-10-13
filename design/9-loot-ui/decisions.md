# Design decisions: <feature>

- Design issue: #<number>; covered build issues: <numbers or unsplit plan>
- Revision: 1; replaces: none (or merged folder/revision)
- Maker: <provider/model and thinking level>

## Choice and approval
Chosen version and why. When versions differed on more than one independent decision,
Robert's pick for each, asked as its own numbered question; the chosen version combines
them, even if no single version had all of them:

| # | Decision | Options (version) | Robert's pick and why |
| --- | --- | --- | --- |
| 1 | <e.g. how names show> | <a: ...; b: ...> | <pick, reference/date> |

Robert's exact confirmation and date/reference authorizing the
PR. Design PR: use the linked PR on the design issue once created; the session adds
that link there after opening it. Only Robert merging that PR approves it for building;
chat approval, a critique PASS and a closed/unmerged PR do not.

## Alternatives
| Version | What differs / why rejected or chosen | Only this version had (lost) | Robert's OK to drop | Evidence |
| --- | --- | --- | --- | --- |
| a | <reason> | <features no kept version has, or none> | <his words, date/reference> | [All-version manifest](screenshots/all/manifest.json) and named images |

A version is removed, replaced or left out at freeze only after Robert confirms what it
alone had can go.

All-version captures were completed and inspected before pruning versions/. Approved
state × theme × width evidence: [manifest](screenshots/approved/manifest.json).
Record actual counts, inspected image paths, offline proof and any capture limitations.

## Independent critique
Maker and other-company reviewer, exact launch command, evidence path, verdict and date.
Numbered findings, fixes and the single fixes-only re-check. Retain the final verdict.

## Comments and changes
| ID / source | Version / element | Original note | Agreed change and verification | Resolved |
| --- | --- | --- | --- | --- |
| <Open Design ID or herdr reference> | <target> | <note> | <result> | <date/status> |

## Experiment
None, or Robert's permission, question, branch/preview, chosen behaviour, rejected
attempts, static-version updates and unmerged/closed experiment PR. Code reuse: forbidden
unless specific parts are explicitly authorized here. Keep the branch as a primary source.

## Open items
None affecting the approved scope. Preserve any deferred, out-of-scope questions explicitly.

## Build handoff
Merged folder/revision is the feature authority; DESIGN.md/live site govern site-wide
look. Reconcile issues and paused branches in prep before marking ready. Without a
conductor, the design session owns that follow-up. Later revisions use new issues/PRs.
