# Design decisions: Pick winner for a needs-a-winner award (revision 3)

- Design issue: #115; covered build issues: #40
- Revision: 3; replaces: in `design/9-loot-ui/` (revision 1, merged), only what Pick winner opens and the fixed row
- Maker: claude-bridge/claude-opus-5-5

## Choice and approval
Pending. The versions differ on one decision:

| # | Decision | Options (version) | Robert's pick and why |
| --- | --- | --- | --- |
| 1 | Where Pick winner opens | a: a box inside the row, the list scrolled to it; b: its own window in the middle of the screen; c: a panel attached beside the officers' window | Pending |

Everything else is the same in all three: the choices, the note, the line shown before posting, Post correction and Cancel, and every state.

## Interview
Robert, 2026-10-21, to the three questions on #115 (who can be picked, the note, check before posting) and the brief: "You decide on all of this." The session's recommendations stand, as listed in brief.md, Confirmed decisions.

## Alternatives
Filled in at approval.

## Independent critique
Round 1, 2026-10-21. Maker claude-bridge/claude-opus-5-5; checker routed by `node /git/maestro/routing/route.ts role checker --maker claude-bridge/claude-opus-5-5`: OpenAI GPT-5.6 Terra, thinking medium, a different company.
Command: `node /git/maestro/scripts/read-only-run.ts "$PWD" review /git/maestro/skills/design-feature/reviewer-prompt.md "Design: …/design/115-pick-winner. Images and manifest: /tmp/design-review-n8UuYz/versions. Maker: claude-bridge/claude-opus-5-5. …" -- --model openai/gpt-5.6-terra --thinking medium` (exit 0, tree unchanged). Evidence: 78 captures, 3 versions × 13 states × default × 390/1440, commit 83477b7. Full text: `work/115-pick-winner/critique-1.md`.
Verdict: **PASS**, no fixes. Trade-offs it noted: A keeps the picker by its row but scrolls earlier bosses out of view; B focuses the decision but hides more of the list; C keeps the whole list and the marked row visible but uses the most width.

## Comments and changes
| ID / source | Version / element | Original note | Agreed change and verification | Resolved |
| --- | --- | --- | --- | --- |

## Offline proof (versions)
2026-10-21: each of `versions/a.html`, `b.html`, `c.html` opened from disk in Chrome (chrome-devtools-axi, session `d115`) with every network request sent to a dead proxy (`--proxy-server=127.0.0.1:9`). The page's requests were its own `file:` and inlined `data:` art and fonts only. In each version the flow Pick winner → Someone else in the raid → Quill Ashby from the list → roll 77 showed the line `Correction: [Belt of Might] → Quill Ashby (open roll, 77), not Pell Harrow <BF1;R;…>`, enabled Post correction, and Post landed on `?state=pick-done&theme=default` with that line in chat and the row "Quill Ashby, Open roll, 77, Corrected 20:47". No script errors.

## Experiment
None.

## Open items
- Decision 1, above.

## Build handoff
Merged folder/revision is the feature authority; revision 1's brief governs the add-on's look. Reconcile #40 in prep before marking it ready. Later revisions use new issues/PRs.
