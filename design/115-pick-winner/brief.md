# Design: Pick winner for a needs-a-winner award (loot design revision 3)

- Design issue: #115
- Revision: 3
- Replaces: in [`design/9-loot-ui/`](../9-loot-ui/) (revision 1, design issue #9, PR #36), only what the Awards tab's `Pick winner` button opens, and the needs-a-winner row once it is fixed. Every other screen stays on revision 1 (and the Sync tab on revision 2, [`design/44-sync-raids/`](../44-sync-raids/)).
- Source: #40 (Awards tab: Undo and "needs a winner"), its prep sweep and Robert's answers there: a confirmed award that is undone becomes "needs a winner" (2026-10-21), and Pick winner gets a design revision ("Whatever you suggest.", 2026-10-21).

## Job and audience
The **loot master**, in the officers' window during or after a raid. An award was undone after
the game had already confirmed it: the item has left the corpse, and the person it was given to
still has it. Usually the right person then got it by trade. Pick winner records who has it now,
with how they won it, and tells the raid with one correction line. Nothing is handed out.

Success: in a few clicks the record says who really has the item, the raid sees one clear line,
and the guild site gets the reason in a note. A wrong pick is as easy to spot before posting as
possible, because a posted line can't be taken back.

Product facts: ADDON-SPEC 4 (`replace` makes a new award with a new key; `note` up to 200
characters; `LootMethod`) and 9.2 (the Replacement line `Correction: {link} → {winner}
({method}, roll {roll}), not {oldwinner}`, built by `OpText.BuildLine`). The add-on's chat
lines know four methods: hard reserve, soft reserve, open roll with its roll (1 to 100), and
disenchant/bank (no winner). `note` and `user` never appear in a chat line.

## Covers
| Build issue | Part of this feature | Out of scope |
| --- | --- | --- |
| #40 | The `NEEDS A WINNER` row's Pick winner: what it opens, the choices (other reserve holders, someone else in the raid by open roll, disenchant/bank, the previous winner), the note, the line shown before posting, Post correction and Cancel, the boss-fight wait, and the row and chat after posting or when the line can't be posted | Undo itself and the struck "Undone" row (revision 1 draws them); the not-confirmed row's buttons (#12); sending undos to other officers (#19) |

Revision 1 still covers everything else it covers.

## Boundaries and visual authority
- **Authority:** revision 1's brief and approved `index.html` (WoW's standard window style, the game's own interface art, a Friz Quadrata lookalike). This repo has no `PRODUCT.md` or `DESIGN.md`; revision 1's brief is the visual authority and this brief adds only Pick winner.
- **Reuse:** the officers' window, Awards tab rows, mode badges, note bars, buttons, text boxes, the dropdown and its member list (revision 1's Disenchant/bank list), the boxed panel inside a row (revision 1's give-else box), the notice window (revision 1's "How was it won?"), and revision 2's radio-style choice rows. No new kind of element, except in version C, a panel attached beside the officers' window.
- **Must not change:** revision 1's other screens and rows; the spec's line wording.

## States, themes and content
Theme `default` only. Designed at 1440×900; the 390×844 capture shows the same game windows scaled down (phone use doesn't apply to a PC game, as in revisions 1 and 2).

Sample data (made up): revision 1's Awards tab. [Belt of Might] (Gehennas) went to Pell Harrow (soft reserve) at 20:31, was confirmed, and was undone at 20:33. Its other reserve holders: Ostrin Pike (hard reserve, already received tonight, so left out as on the give-else list), Hollis Grey (soft reserve), Ardan Vey (soft reserve, not in raid). Minimum: nobody else reserved it. Maximum: 10 other holders (3 hard, 7 soft; 3 not in raid).

| State slug | Situation | Content and wording | Actions / feedback |
| --- | --- | --- | --- |
| pick-start | Awards tab, loot master | Revision 1's `NEEDS A WINNER` row: "Undone after it left the corpse" | Pick winner opens the picker |
| pick-open | Picker open, nothing chosen | "[Belt of Might] was undone after Pell Harrow already had it. Choose who has it now. Nothing is handed out: this records the winner and posts one correction line." Groups: **Reserved it** (Hollis Grey SR; Ardan Vey greyed, "not in raid"), **Anyone else** (Someone else in the raid: open roll; Disenchant/bank; Pell Harrow: "had it before: cancels the undo"). Note box filled with "Traded by Pell Harrow". Preview: "Choose who gets it." | Post correction disabled; Cancel |
| pick-reserve | Hollis Grey chosen | Preview: `Correction: [Belt of Might] → Hollis Grey (soft reserve), not Pell Harrow <BF1;R;…>` | Post correction |
| pick-roll | Someone else in the raid | Member dropdown (raid members, scrolls) and Roll box; Bellis Rook, 92. Preview: `… → Bellis Rook (open roll, 92), not Pell Harrow` | Post correction |
| pick-roll-missing | Roll not valid (920) | Roll shown in red; preview: "A roll is 1 to 100." (empty: "Type their roll, 1 to 100.") | Post correction disabled until valid |
| pick-db | Disenchant/bank | Preview: `… → disenchant/bank, not Pell Harrow` | Post correction |
| pick-again | Pell Harrow after all (the undo was the mistake) | Note box empty (nothing was traded). Preview: `… → Pell Harrow (soft reserve), not Pell Harrow` | Post correction |
| pick-none | Nobody else reserved it | "Nobody else reserved this item." under Reserved it | Other choices as usual |
| pick-crowded | 10 other holders | Hard reserves first; the holders' list scrolls, "▼ 10 reserve holders · scroll for more" | |
| pick-fight | Boss fight | Note bar: "Boss fight in progress. The game locks chat for add-ons, so the correction waits until it ends." | Choices work; Post correction disabled, "Chat is locked until the fight ends." |
| pick-practice | Practice mode | Window title "[Practice] Bureaucracy Forever"; preview starts `[Practice] Correction: …` with `<BF1P;…>` | As usual |
| pick-done | After Post correction | The new award (20:47, Hollis Grey, Soft reserve, "Corrected 20:47", Undo) at the end of its boss group; the struck Pell Harrow row stays; summary loses "1 needs a winner"; the line in raid chat | Undo works as on any award |
| pick-unposted | Recorded, but the line couldn't be posted | Note bar in the window and a chat message: "Hollis Grey now has [Belt of Might] on the record, but its raid chat line couldn't be posted. Type /bf log for why." | The record stands (as the pop-up's give-else does) |

Not applicable: loading (nothing loads), empty (the button exists only on a needs-a-winner row). Other officers: revision 1's `awards-officer` already shows Pick winner greyed ("Only the loot master (Konvett Konvett) can change awards."); unchanged.

Keyboard: the choices are a radio group (Tab to a choice, Enter or Space picks it); the dropdown list closes with Escape; game windows close with Escape; prototype controls are keyboard-accessible.

## Host snapshot and offline proof
No web host (revision 1's exception: a game add-on). The host is revision 1's approved `design/9-loot-ui/index.html`, copied to `host.html` while designing. `work/115-pick-winner/build.py` builds each version from it, adding `pick.js` and `pick.css`. Host parts used, in `index.html`: `windowFrame()` (window, tabs, footer), `AWARDS` and `awardRow()` (the Awards rows), `notice()` (version B), `frame()` (version C), `chat()`/`chatLine()`/`sysLine()` (chat box), `minimap()`, the `.boxed`, `.note-bar`, `table.list`, `.input`, `.dd`, `.menu`, `.mode`, `.btn` classes; revision 2's `.rb` and `.pick` choice rows (from `design/44-sync-raids/index.html`).

Offline proof: see decisions.md.

## Confirmed decisions
Interview on #115, 2026-10-21. Robert: "You decide on all of this." The session took its recommendations:
1. Who can be picked: the item's other reserve holders as on the give-else list (with their hard or soft reserve; not-in-raid greyed), anyone else in the raid as an open roll with the roll typed in, disenchant/bank, and the previous winner (labelled "had it before"), in case the undo itself was the mistake.
2. The note: filled with "Traded by Pell Harrow", editable and clearable; empty when the previous winner is picked. Up to 200 characters, never in chat.
3. Two steps: choose, see the exact raid line, then **Post correction**.
4. The brief: Robert delegated it with the decisions above ("You decide on all of this."); it goes to him with the versions.

## Real-site experiment
None.

## Open decisions
- Where the picker opens (the versions' one difference): A inside the row, B its own window in the middle of the screen, C a panel beside the window.
