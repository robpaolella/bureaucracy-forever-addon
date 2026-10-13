# Design decisions: the loot pop-up and the officers' window

- Design issue: #9; covered build issues: #10, #11, #12, #13, #14, #15, #16, #17, #20, #21
- Revision: 1; replaces: none (or merged folder/revision)
- Maker: claude-bridge/claude-opus-5-5 (two design sessions, both Opus 5.5)

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
- Maker: claude-bridge/claude-opus-5-5. Reviewer: openai/gpt-5.6-terra, thinking medium (routed with `route.ts role checker --maker claude-bridge/claude-opus-5-5`), a different company.
- Command: `node /git/maestro/scripts/read-only-run.ts /git/bureaucracy-forever-addon review /git/maestro/skills/design-feature/reviewer-prompt.md "Design: .../design/9-loot-ui. Images and manifest: /tmp/design-review-CN5GvG/versions. ..." -- --model openai/gpt-5.6-terra --thinking medium`. Exit 0, repo unchanged.
- Evidence: 174 captures (3 versions × 29 states × default × 390/1440), all marked seen by the reviewer.
- Verdict 2026-10-13: **FIXES**, three:
  1. No `PRODUCT.md` / `DESIGN.md`. Fix: brief now states this repo has neither and the brief (confirmed by Robert, Q11) is the full authority.
  2. Version C showed only four labelled items of the six-item worst case. Fix: the game's loot window page arrows work; C's labels follow the page; new state `popup-page2` in all versions (A and B show their unchanged list beside page 2).
  3. B's item queue and arrows and C's ⚠ looked interactive but did nothing. Fix: they now select the item (B) and open "Item details" (C), keyboard-reachable buttons, local only.
- Fixes-only re-check (same reviewer and launcher, prompt limited to the three fixes; 180 captures incl. `popup-page2`): **PASS** on all three, 2026-10-13. The reviewer clicked the controls in Chrome and saw only local and inlined requests.

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
