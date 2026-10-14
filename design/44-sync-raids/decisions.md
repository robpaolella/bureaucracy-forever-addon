# Design decisions: the raid question and the Sync tab (revision 2)

- Design issue: #44; covered build issues: #16
- Revision: 2; replaces: the Sync tab of revision 1, `design/9-loot-ui/` (merged, 880aae7)
- Maker: claude-bridge/claude-opus-5-5

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
Round 1, 2026-10-13. Maker claude-bridge/claude-opus-5-5; checker routed by `node /git/maestro/routing/route.ts role checker --maker claude-bridge/claude-opus-5-5`: OpenAI GPT-5.6 Terra, thinking medium (the reviewer's text calls itself "GPT-5.2"; the launch used `--model openai/gpt-5.6-terra`).
Command: `node /git/maestro/scripts/read-only-run.ts "$PWD" review /git/maestro/skills/design-feature/reviewer-prompt.md "Design: …/design/44-sync-raids. Images and manifest: /tmp/design-review-vQF3jp/versions. Maker: claude-bridge/claude-opus-5-5. …" -- --model openai/gpt-5.6-terra --thinking medium` (exit 0, tree unchanged). Evidence: 114 captures, 3 versions × 19 states × default × 390/1440, commit c5fabbe. Full text: `work/44-sync-raids/critique-1.md`.
Verdict: FIXES.
1. Use the brief's "Decide later" wording on the question's put-off button; all versions say "Later".
2. Crowded state (B and C): show a usable Remove for the pasted raid. B lists Blackwing Lair (pasted) with no Remove; C's menu row "Remove a pasted raid…" is greyed and inert.
3. Raid switching in the prototypes jumps to a fixed state and never shows the newly chosen raid as selected; keep the choice in local state after Switch, or add a "different raid selected" state.
Fixes: not yet applied. Re-check: pending (fixes 1-3 only).

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
