# Design decisions: Pick winner for a needs-a-winner award (revision 3)

- Design issue: #115; covered build issues: #40
- Revision: 3; replaces: in `design/9-loot-ui/` (revision 1, merged), only what Pick winner opens and the fixed row
- Maker: claude-bridge/claude-opus-5-5

## Choice and approval
Chosen: **version A** (`index.html`). Robert, 2026-10-21 in herdr, asked where Pick winner should open with A recommended: "You choose." The session chose A: it reuses the approved give-else box that opens inside a row (revision 1's pop-up), and keeps the picker next to the award it corrects. Robert's reply after all three options and what each costs were shown to him is also his confirmation to drop B and C (Alternatives). Robert's merge of the design PR approves it for building.

The versions differed on one decision:

| # | Decision | Options (version) | Robert's pick and why |
| --- | --- | --- | --- |
| 1 | Where Pick winner opens | a: a box inside the row, the list scrolled to it; b: its own window in the middle of the screen; c: a panel attached beside the officers' window | a. Delegated ("You choose."); the session picked A for the reasons above |

Everything else is the same in all three: the choices, the note, the line shown before posting, Post correction and Cancel, and every state.

## Interview
Robert, 2026-10-21, to the three questions on #115 (who can be picked, the note, check before posting) and the brief: "You decide on all of this." The session's recommendations stand, as listed in brief.md, Confirmed decisions.

## Alternatives
Screenshots of every version, state and width: `screenshots/all/` (`b-*` and `c-*`; manifest.json).
- **B, its own window in the middle of the screen** (`screenshots/all/b-*`). What only it had: a centred window that focuses on the one decision, like revision 1's "How was it won?" question, with the Awards tab behind it. Lost: that focused, separate window; it hid more of the list.
- **C, a panel attached beside the officers' window** (`screenshots/all/c-*`). What only it had: the whole awards list stays visible next to the picker, with the row marked. Lost: the fully visible list; it took the most screen width.
Confirmation to drop both: Robert's "You choose." above, given after both options and their trade-offs were set out to him.

## Independent critique
Round 1, 2026-10-21. Maker claude-bridge/claude-opus-5-5; checker routed by `node /git/maestro/routing/route.ts role checker --maker claude-bridge/claude-opus-5-5`: OpenAI GPT-5.6 Terra, thinking medium, a different company.
Command: `node /git/maestro/scripts/read-only-run.ts "$PWD" review /git/maestro/skills/design-feature/reviewer-prompt.md "Design: …/design/115-pick-winner. Images and manifest: /tmp/design-review-n8UuYz/versions. Maker: claude-bridge/claude-opus-5-5. …" -- --model openai/gpt-5.6-terra --thinking medium` (exit 0, tree unchanged). Evidence: 78 captures, 3 versions × 13 states × default × 390/1440, commit 83477b7. Full text: `work/115-pick-winner/critique-1.md`.
Verdict: **PASS**, no fixes. Trade-offs it noted: A keeps the picker by its row but scrolls earlier bosses out of view; B focuses the decision but hides more of the list; C keeps the whole list and the marked row visible but uses the most width.

## Comments and changes
| ID / source | Version / element | Original note | Agreed change and verification | Resolved |
| --- | --- | --- | --- | --- |

## Offline proof (versions)
2026-10-21: each of `versions/a.html`, `b.html`, `c.html` opened from disk in Chrome (chrome-devtools-axi, session `d115`) with every network request sent to a dead proxy (`--proxy-server=127.0.0.1:9`). The page's requests were its own `file:` and inlined `data:` art and fonts only. In each version the flow Pick winner → Someone else in the raid → Quill Ashby from the list → roll 77 showed the line `Correction: [Belt of Might] → Quill Ashby (open roll, 77), not Pell Harrow <BF1;R;…>`, enabled Post correction, and Post landed on `?state=pick-done&theme=default` with that line in chat and the row "Quill Ashby, Open roll, 77, Corrected 20:47". No script errors.

## Offline proof (approved)
2026-10-21: `index.html` (a copy of `versions/a.html`) opened from disk in Chrome (chrome-devtools-axi, session `d115b`) with every request sent to a dead proxy. No requests other than `file:` and `data:`; both fonts loaded. Pick winner → Someone else in the raid → Quill Ashby → roll 77 → Post correction landed on `?state=pick-done&theme=default`, with the line `Correction: [Belt of Might] → Quill Ashby (open roll, 77), not Pell Harrow <BF1;R;…>` in chat and the row "Quill Ashby, Open roll, 77, Corrected 20:47". The only console error is Chrome's notice that `file:` pages are unique origins when the page rewrites its own URL; the URL still updated. Approved shots: `screenshots/approved/`, 13 states × default × 390/1440, 26 images; they match version A's shots in `screenshots/all/` (one 390 image differs in a few pixels of rendering, same content). `host.html` and `versions/` were removed after these checks; the folder was synced to Open Design.

## Experiment
None.

## Open items
None affecting the approved scope.

## Build handoff
Merged folder/revision is the feature authority; revision 1's brief governs the add-on's look. Reconcile #40 in prep before marking it ready. Later revisions use new issues/PRs.
