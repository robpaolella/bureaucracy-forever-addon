# Design decisions: the raid question and the Sync tab (revision 2)

- Design issue: #44; covered build issues: #16
- Revision: 2; replaces: the Sync tab of revision 1, `design/9-loot-ui/` (merged, 880aae7)
- Maker: claude-bridge/claude-opus-5-5

## Choice and approval
Chosen: **version D**, now `index.html`. It combines Robert's three picks below: A's Sync tab, plus B's one-step question in the middle of the screen.

| # | Decision | Options (version) | Robert's pick and why |
| --- | --- | --- | --- |
| 1 | Sync tab layout | a: one column, raid list as a table; b: list left, details right; c: compact "Raid:" dropdown, paste behind a button | **a**, "I agree, A it is." (herdr, 2026-10-13). Shows every raid and its numbers at once, in the table style the add-on's other tabs use |
| 2 | Question flow | a, c: two steps (guild run? then which raid); b: one step (raid list plus "No, not a guild run") | **b**, "I agree, B it is." (herdr, 2026-10-13). The matching raid is pre-selected, so usually one press of Start |
| 3 | Question placement | a, b: centred dialog; c: small window under the minimap | **centred**, "Yes, middle of the screen." (herdr, 2026-10-13). Can't be missed; unanswered means awards held as "no raid" |

Combined as **version D** (`versions/d.html`): A's Sync tab with B's one-step question, centred. It adds no behaviour that no version had, so no new critique (step 6). Checked offline with the same flows as the re-check (all land on the right screen); 40 captures (20 states × default × 390/1440) in `/tmp/design-review-nzzUB4/versions` inspected via contact sheets.

Robert's confirmation: "4. Approved." (herdr, 2026-10-13), in answer to looking through D and dropping A, B and C with what only they had. Design PR: linked on #44 under `## Design PR`. Only Robert merging that PR approves the design for building; chat approval, a critique PASS and a closed or unmerged PR do not.

## Alternatives
| Version | What differs / why rejected or chosen | Only this version had (lost) | Robert's OK to drop | Evidence |
| --- | --- | --- | --- | --- |
| a | Its Sync tab was chosen (decision 1) and kept in D; its two-step question was not (decision 2) | The two-step question shown in the middle of the screen ("Is this a guild run?" then "Which raid event?") | "4. Approved." (2026-10-13), asked with the list of what goes | [manifest](screenshots/all/manifest.json), `screenshots/all/a-*.png` |
| b | Its one-step, centred question was chosen (decisions 2, 3) and kept in D; its layout was not (decision 1) | Raid list on the left with the chosen raid's details on the right | "4. Approved." (2026-10-13) | [manifest](screenshots/all/manifest.json), `screenshots/all/b-*.png` |
| c | Not chosen on any decision | Compact "Raid:" dropdown with paste behind a button; the question in a small window under the minimap; the two-step question there | "4. Approved." (2026-10-13) | [manifest](screenshots/all/manifest.json), `screenshots/all/c-*.png` |
| d | Chosen: Robert's picks combined | - | - | [manifest](screenshots/approved/manifest.json) |

A version is removed, replaced or left out at freeze only after Robert confirms what it
alone had can go.

All-version captures were completed and inspected before `versions/` was removed: 160 images, 4 versions × 20 states × default × 390/1440, in `screenshots/all/` (inspected as contact sheets, one per version and width). Approved evidence: 42 images, 21 states × default × 390/1440 (the 21st, `ask-gone`, was added after approval, below; it is in no rejected version, so `screenshots/all/` has 20 states), in `screenshots/approved/` ([manifest](screenshots/approved/manifest.json)), every manifest entry present and inspected. Capture limit: 390 wide is the PC game screen scaled down, not a phone layout (brief).
Final offline proof (2026-10-13): `index.html` opened from disk in headless Chrome with all network requests sent to a dead proxy. No request left `file:`/`data:`, fonts 2/2, no broken images, and the flows (crowded → pick Onyxia's Lair → Switch; Remove Blackwing Lair; overlap → Start; ask-again → Switch; Decide later; undecided → pick) each reached the right screen and URL. The host snapshot `host.html` was removed after this proof; it is revision 1's approved `design/9-loot-ui/index.html` with nothing added. The tooling in `work/44-sync-raids/` built the versions from it.

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
| herdr, 2026-10-13 | All versions | Robert's picks: 1 A, 2 B, 3 middle of the screen | Combined as version D; checked offline and at both widths | Done |
| herdr, 2026-10-13 | D | "4. Approved." | D frozen as `index.html` | Done |
| Pre-PR review (GPT-5.6 Terra), 2026-10-13 | `sync-gone` | Blocking: "Choose a raid now" isn't in the brief (OK only), and the question it opened still listed and pre-selected the raid that had left | Robert, "5. Keep it." (herdr, 2026-10-13). The button now opens a new state, `ask-gone`, listing only the raids still loaded, none pre-selected; Decide later and Not a guild run keep that list. Brief updated (sync-gone, ask-gone). Rebuilt from `work/44-sync-raids/`; every other approved image byte-identical; checked offline | Done |

No Open Design comments were left (`design.ts comments`: none open).

## Experiment
None.

## Open items
None affecting the approved scope. Outside it: the data format for the raid question, "not a guild run" and the shared selection is agreed in the site repo, robpaolella/bureaucracy-forever#307 (open). It blocks building #16, not this design.

## Build handoff
Merged folder/revision is the feature authority; DESIGN.md/live site govern site-wide
look. Reconcile issues and paused branches in prep before marking ready. Without a
conductor, the design session owns that follow-up. Later revisions use new issues/PRs.
