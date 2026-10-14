# Design: the loot pop-up and the officers' window

- Design issue: #9
- Revision: 1
- Replaces: none
- Source plan: #3, plan v3 with the round-3 fixes (build issues exist; see Covers)

## Job and audience
Guild officers in the WoW Forever game client, mainly the **loot master** during a raid: a
40-person group waiting on them, often voice chat going, a boss just died. They need to see
at a glance who should get each item and act in one click, without slowing the raid. Other
officers watch the same awards live and check reserves. Officers also rehearse in dungeons
(practice mode) and alone (Test drop).

Success: every item goes to the right person in one click, the raid sees a clear line in
chat, and every award (and every mistake and its fix) is recorded for the guild site.

Product facts come from Robert's decisions in #3 (rounds 1–9) and this interview. The rules
are the site's own (hard reserve, then soft reserve, then open roll; holders who already got
the item or hit a win limit skipped); the add-on doesn't invent rules.

## Covers
| Build issue | Part of this feature | Out of scope |
| --- | --- | --- |
| #10 | The loot pop-up: boss (changeable), items with mode and contenders, skipped holders and why, several copies, status line, no-reserves case | Awarding logic |
| #11 | The award button and its feedback; Disenchant/bank button with its member dropdown; waiting for a boss fight to end; unavailable ("Unknown", not on the list) winners | Failed hand-outs |
| #12 | Not confirmed: Try again, Give to someone else, Not handed out | The Awards tab itself |
| #13 | Roll-offs: call, rolls listed live, ineligible rolls ignored, ties and Re-roll, hidden rolls | Countdown (see #33) |
| #14 | Awards tab: rows, Undo, "not confirmed", "needs a winner", practice awards apart, other officers' read-only view | Sending undos between officers |
| #15 | Reserves tab (by boss, HR/SR, greyed absent, ticked received, trial marked) and item tooltips | Changing reserves in game |
| #16 | Sync tab: paste box and result, copy-out, status, raid switch confirmation, "no raid" awards | The helper's inbox reading |
| #17 | Practice mode marker and the Test drop button | Outside hand-outs in practice (#21) |
| #20 | Update notice (copyable link) and loot master handover prompt | The site's catch-up |
| #21 | The question after a hand-out made from the game's own loot menu | Changing the game's loot menu |

## Boundaries and visual authority
- **Authority files:** this repo has no `PRODUCT.md` or `DESIGN.md`. This brief, confirmed by Robert on 2026-10-13 (Q11, "Yes, this looks good. Build it."), is the complete product and visual authority for this design; the product facts come from #3 and the decisions below.
- **Visual authority: WoW's own standard window style** (Robert, #3 Q9, and this interview Q2).
  The mock-ups use the game's real interface art (Robert, Q2: "just use WoW's actual design";
  he accepts the liability). The font is a free lookalike of Friz Quadrata, because that face is
  licensed from a font company, not Blizzard. In game, the add-on uses the game's built-in
  window templates and fonts.
- **No host page.** There is no web page or existing add-on UI to snapshot: this is the
  "new page with no host" exception. The mock-ups sit on a plain dark game-screen backdrop
  with the game's own loot window drawn beside the pop-up for context.
- **ElvUI / LUI:** not in scope. Those reskin Blizzard's frames and add-ons that have a skin
  written for them, not ours automatically. Backlog item.
- **New kinds of element for Robert's approval:** the pop-up, the officers' window with three
  tabs, the minimap button (approved in principle, Q4), the Disenchant/bank dropdown (Q5), the
  notices and the outside hand-out question.
- Must not change: the loot rules; the game's own loot window (we sit beside it, never replace it).

## States, themes and content
Theme: `default` only (the game has one look). Widths: designed for desktop (1440×900). The
390×844 capture just shows the same game windows; phone use isn't applicable to a PC game
(Robert, interview, no objection).

Sample data: Molten Core-style bosses and items, made-up "First Last" names. Typical: 2–4
items per corpse. Worst case (Q6): 40-person raid, 6 items with two identical copies, 5 hard
reserves on one item, 8 soft reserves on another.

| State slug | Role / situation | Content | Actions / feedback |
| --- | --- | --- | --- |
| popup-typical | Loot master, boss corpse opened | 3 items: single HR, single SR, nobody (open roll) | Award buttons named for the winner; Roll call; D/B |
| popup-crowded | Loot master, worst case | 6 items incl. two copies, 5 HR, 8 SR, skipped holders ("not in raid", "the game won't let them receive this item"), an unlisted item | Several copies resolved in turn |
| popup-page2 | Loot master, worst case, game's loot window turned to page 2 | Items 5 and 6 | A and B: unchanged list; C: labels follow the page |
| popup-boss | Loot master, corpse not clearly a boss | Boss shown as "Trash" with the change control open | Pick a boss before awarding |
| popup-no-reserves | Loot master, no reserves loaded | Notice: no reserves loaded; every item an open roll | Link to Sync tab |
| popup-fight | Loot master during a boss fight | Award buttons wait: "Chat is locked until the fight ends" | Buttons enable after the fight |
| popup-unavailable | Winner "Unknown" or not on the game's list | Button disabled with reason | Next tier offered |
| popup-db | Disenchant/bank dropdown open | Raid members list, last pick remembered | One click thereafter |
| roll-called | Roll call posted | Eligible players, rolls arriving; an ineligible roll ignored; a second roll by the same player ignored | Highest pre-selected; Award |
| roll-tie | Tie | Tied players flagged | Re-roll posts the tie line |
| roll-hidden | Rolls can't be read | Eligible names to click | Officer picks the winner |
| handout-waiting | Just clicked Award | "Handing out…" | Confirms within seconds |
| not-confirmed | Game didn't confirm | Try again / Give to someone else / Not handed out | Lines per Q7 |
| give-else | Picking another winner | Candidate list | Correction + new award line |
| awards | Any officer, Awards tab | ~12 awards, a not-confirmed row, a needs-a-winner row, a voided row, practice awards apart | Undo, choices |
| awards-empty | Awards tab, raid just started | Nothing yet | Explains what will appear |
| awards-officer | Officer who isn't loot master | Same rows, change buttons greyed | "Only the loot master (Konvett Konvett) can change awards." |
| reserves | Reserves tab | By boss; HR/SR names; absent greyed; received ticked; trial marked | Read only |
| reserves-empty | No reserves loaded | Explains and points to Sync | |
| tooltip | Hovering an item anywhere | HR and SR names added to the item tooltip | |
| sync-empty | Sync tab, nothing loaded | Paste box, Load | |
| sync-loaded | Reserves loaded | Raid, copied when, helper inbox status; copy-out | Copy-out selects text |
| sync-refused | Bad or newer-format paste | Reason ("update the add-on") | |
| sync-switch | Loading another raid's reserves while awards exist | Confirmation | |
| sync-noraid | Awards made with nothing loaded | "No raid" awards and Attach | |
| practice | Practice mode on | "[Practice]" marker on pop-up and window; Test drop button | |
| notice-update | Newer version seen | Update notice with copyable download link | |
| notice-handover | Loot master changed | Handover prompt | |
| outside-handout | Item given from the game's own menu | How was it won? HR/SR/open roll/D/B, pre-filled | Answer posts the line |
| minimap | Any officer, hovering the minimap button | Tooltip: loaded raid, not-confirmed count | Click opens the window; drag moves the button |

Loading and error: the add-on has no network loading; errors are the refused paste, not
confirmed hand-outs, and unavailable winners, all listed above. Keyboard: game windows close
with Escape; prototype controls are keyboard-accessible.

## Host snapshot and offline proof
No host (exception above). Each version is a single self-contained HTML file with the game
art and font inlined; checked offline with the network disabled at both widths (2026-10-13: headless Chrome with all network blocked; the pages made no requests, art and fonts rendered).
Host parts used: none.

## Confirmed decisions
Recorded on #9 (interview rounds 1–4, 2026-10-13):
1. Q1 Start before the spec; readable chat wording decided here, noted on bureaucracy-forever#271.
2. Q2 Use WoW's real interface art in the mock-ups; ElvUI/LUI skins later (backlog).
3. Q3 Only the loot master gets the pop-up; every officer can open the window; change buttons greyed for others.
4. Q4 `/bf` and a minimap button (tooltip: loaded raid, not-confirmed count).
5. Q5 Disenchant/bank button with a dropdown of raid members, remembering the last pick for the raid.
6. Q6 Worst case as above.
7. Q7 Chat lines:
   - Award (raid chat): `[Item] → Ashla Brightwater (hard reserve)` / `(soft reserve)` / `(open roll, 87)` / `(disenchant/bank)`
   - Roll call (raid warning): `Roll for [Item]: A, B, C (hard reserve)`; open: `Open roll for [Item]: everyone /roll`
   - Tie (raid warning): `Tie for [Item]: A and B, roll again`
   - Not handed out: `Correction: [Item] was not handed to A`; Give to someone else: that line, then a new award line
   - Undo: `Undo: [Item] is no longer awarded to A`
   - Needs a winner fixed: `Correction: [Item] → B (soft reserve), not A`
   - Practice: every line starts `[Practice] `
8. Q8 Award, correction and undo lines end with a short machine code, e.g. `{bf:A7K2-19-4410}` (format from the spec).
9. Q9 Roll-offs: rolls listed live, officer clicks to award, Re-roll for ties, no countdown for now.
10. Q10 Beta test of timer chat lines filed as #33; a countdown may follow as a revision.

## Real-site experiment
None.

## Open decisions
- Layout choices the versions differ on (asked one by one after the critique).
