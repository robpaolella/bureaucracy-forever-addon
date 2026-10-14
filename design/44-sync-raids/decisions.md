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
| 1 | Sync tab layout | a: one column, raid list as a table; b: list left, details right; c: compact "Raid:" dropdown, paste behind a button | **a**, "I agree, A it is." (herdr, 2026-10-13). Shows every raid and its numbers at once, in the table style the add-on's other tabs use |
| 2 | Question flow | a, c: two steps (guild run? then which raid); b: one step (raid list plus "No, not a guild run") | **b**, "I agree, B it is." (herdr, 2026-10-13). The matching raid is pre-selected, so usually one press of Start |
| 3 | Question placement | a, b: centred dialog; c: small window under the minimap | **centred**, "Yes, middle of the screen." (herdr, 2026-10-13). Can't be missed; unanswered means awards held as "no raid" |

Combined as **version D** (`versions/d.html`): A's Sync tab with B's one-step question, centred. It adds no behaviour that no version had, so no new critique (step 6). Checked offline with the same flows as the re-check (all land on the right screen); 40 captures (20 states × default × 390/1440) in `/tmp/design-review-nzzUB4/versions` inspected via contact sheets.

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
Fixes applied in one batch, 2026-10-13 (`work/44-sync-raids/sync.js`, `sync.css`, rebuilt versions):
1. Every version's question says **Decide later**.
2. B: a Remove button beside the pasted Blackwing Lair in the raid list. C: the open menu's row is now "Remove Blackwing Lair (pasted)…", enabled and keyboard-reachable, leading to the remove dialog, which names the raid being removed.
3. New state `sync-switched` (the picked raid selected; Onyxia's Lair by default). The prototype remembers the raid picked or marked for removal, so Switch, Start, picks and Remove all land on a screen showing the outcome. Checked offline in all three versions: crowded → Onyxia's Lair → Switch; crowded → Remove Blackwing Lair; overlap → second team → Start; ask-again → Switch; undecided → pick.
Re-check (fixes 1-3 only), same checker and command form, evidence `/tmp/design-review-16M24L/versions` (120 captures, 3 versions × 20 states × default × 390/1440): **PASS** on all three (exit 0, tree unchanged). Full text: `work/44-sync-raids/critique-1-recheck.md`.

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
