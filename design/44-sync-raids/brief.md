# Design: Sync tab with several raids (loot design revision 2)

- Design issue: #44
- Revision: 2
- Replaces: the Sync tab of [`design/9-loot-ui/`](../9-loot-ui/), revision 1 (design issue #9, PR #36, merge commit 880aae7). Only the Sync tab and its dialogs; every other screen stays on revision 1.
- Source: Robert's decision on the helper's design (robpaolella/bureaucracy-forever-helper#2, answer 5: https://github.com/robpaolella/bureaucracy-forever-helper/issues/2#issuecomment-6156569134) and the spec it produced (ADDON-SPEC section 2.1, robpaolella/bureaucracy-forever#289, merged). Hold on #16: https://github.com/robpaolella/bureaucracy-forever-addon/issues/16

## Job and audience
Guild officers in the WoW Forever client. Most run the desktop helper, which writes every
raid starting within 12 hours or under way into the add-on's inbox. On entering a raid
instance, one officer (the loot master, or a fallback) is asked "Is this a guild run?" and
then which raid event, with the matching one suggested; the answer is shared with every
officer's add-on. A pug answered "no" records nothing. The Sync tab shows the selection and
who made it, lets any officer change it, and (without the helper) pastes a raid's reserves
in and copies its awards out.

Success: one click or two at the start of a raid; any officer glancing at the tab knows
which raid awards go to and who chose it; loot from a pug never reaches the site.

Product facts: ADDON-SPEC 2, 2.1, 3.2 and 3.4 as revised by robpaolella/bureaucracy-forever#307
(the raid question, chooser, shared selection, Discard); revision 1's brief for everything else.

## Covers
| Build issue | Part of this feature | Out of scope |
| --- | --- | --- |
| #16 | The raid question (guild run? which raid event? asked again on a new instance) and the Sync tab: the selected raid, who chose it, current instance, raid list, change raid or not a guild run, paste box and result, Copy awards for a chosen raid, "no raid" awards with Attach and Discard, removing a pasted raid; the dialogs: keep-or-switch, raid left the list, remove with awards, discard | Reading the inbox, the choice logic and the selection message (#27, #6, robpaolella/bureaucracy-forever#307); the window frame (#37) |

Revision 1 still covers #10-#15, #17, #20, #21 and #37 unchanged.

## Boundaries and visual authority
- **Authority:** revision 1's brief and approved `index.html` (WoW's standard window style, the game's own interface art, Friz Quadrata lookalike). This repo has no `PRODUCT.md` or `DESIGN.md`; revision 1's brief, confirmed by Robert, is the visual authority and this brief adds only the Sync tab.
- **Reuse:** the officers' window, its tabs and footer, note bars, lists, buttons, text boxes and the notice dialog from revision 1. No new kind of element is planned beyond a raid list with a choice per row (a list of radio-style rows, the game's standard check/radio art) and, depending on the version, the game's standard dropdown (already approved as the Disenchant/bank dropdown, revision 1 Q5).
- **Site wording** (Robert, #16, 2026-10-14: "Agreed, use the site language"): on the site's raid page the buttons are **Copy reserves** and **Import awards**; the raid template field is **In-game instance number** (site design `design/272-addon-site/`).
- **Must not change:** revision 1's other screens; the choice rule in ADDON-SPEC 2.1.

## States, themes and content
Theme `default` only. Designed at 1440×900; the 390×844 capture shows the same game windows scaled down (phone use doesn't apply to a PC game, as in revision 1).

Sample data (made up): Molten Core (instance 409) under way since 19:30, from the helper; Onyxia's Lair (249) starting 22:00; "Alt run: Blackwing Lair" (469) tomorrow is beyond 12 hours, so not listed; a custom raid "Deadmines practice" with no instance number (staging); one pasted raid when the helper isn't running. Typical: 1-2 raids loaded; minimum: none; maximum: 4 (two raids the same evening, a custom raid, a pasted one), with long names.

| State slug | Situation | Content and wording (draft; final wording in the versions) | Actions / feedback |
| --- | --- | --- | --- |
| ask-guild | Dialog: the chooser enters Molten Core (409) in a raid group | "Is this a guild run?" Explains that no means the add-on stays off until they leave the group. If master loot is off, says so | Yes / No, not a guild run / Decide later |
| ask-raid | Dialog after Yes: one raid matches | "Which raid event?" Molten Core pre-selected (under way since 19:30, 38 players); Onyxia's Lair (starts 22:00) listed | Start / Back / Decide later |
| ask-overlap | Dialog after Yes: two Molten Core raids both under way | Both listed with start time and players, neither pre-selected | Start (enabled once one is picked) |
| ask-nomatch | Dialog after Yes: in Zul'Gurub (instance 309), no raid matches | "No raid event is set for Zul'Gurub (instance 309)." Loaded raids listed anyway; a custom raid can use 309 as its In-game instance number on the site | Pick one, or Decide later (awards held as "no raid") |
| ask-again | Dialog: the chooser enters Onyxia's Lair after Molten Core, which has awards | Onyxia's Lair pre-selected; "Your 12 Molten Core awards stay with that raid and are still sent to the site." | Switch / Keep Molten Core |
| sync-chosen | Sync tab, the chooser, raid selected | Active raid, who chose it and when, current instance; raid list with counts; helper line with when its list was last read; Copy awards (raid picker, default active) | Change raid; Not a guild run |
| sync-follower | Sync tab, another officer | Same, with who chose it (the loot master); no question was asked of them | Change raid (shared with the group) |
| sync-off | Not a guild run | "Not a guild run. The add-on is off until you leave the group: no pop-up, nothing recorded." | It's a guild run after all (asks the raid question) |
| sync-undecided | Decide later | "The raid isn't chosen yet. Awards are held as "no raid" until it is." | Choose the raid |
| sync-crowded | Maximum content | 4 raids incl. one with no instance number ("No instance number") and a pasted one ("Pasted 19:42") with Remove; long names | |
| sync-switch | Dialog: changing raid in the Sync tab while the current raid has awards | "Switch to Onyxia's Lair? You have 12 awards for Molten Core. They stay with that raid and are still sent to the site." | Switch / Keep |
| sync-switched | After Switch (or picking a raid when the current one has no awards): the picked raid is now selected | "Chosen by you at 20:14. Awards from this group go to this raid." In the prototype, the raid picked last is the one shown (Onyxia's Lair by default) | |
| sync-gone | Notice: the selected raid left the helper's list | It's no longer in the helper's list (cancelled or over); its awards are kept and still sent; the raid question comes back on the next instance | OK |
| sync-empty | Nothing loaded, helper not running | "No raids loaded." How to get them: the helper, or on the guild site open the raid, choose **Copy reserves** and paste here | Paste box, Load; Copy awards disabled |
| sync-pasted | Helper not running; one pasted raid selected | Loaded line ("Copied from the site 19:42, loaded 19:50"); Copy awards with the text selected and "12 awards, 1 undo. Practice awards are never included."; paste into **Import awards** on the raid page | Copy awards; Remove |
| sync-remove | Dialog: remove a pasted raid with awards (Q3) | "Remove Molten Core? Its 12 awards stay saved and can still be copied." | Remove / Cancel |
| sync-refused | Bad or newer-format paste | As revision 1: needs a newer add-on, download link; nothing changed | |
| sync-noraid | Awards with no raid | "3 awards aren't linked to a raid", list; Attach to a chosen raid (default the active one); Discard (Q7) | Attach / Discard |
| sync-discard | Dialog: Discard "no raid" awards | "Discard 3 awards? They were never sent to the site." | Discard / Cancel |

Not applicable: loading (nothing loads over a network; the inbox is read at login or /reload, shown as a time), locked (none). Roles: the chooser gets the dialogs; every other officer sees the selection (sync-follower) and can change it in the Sync tab.

Keyboard: game windows close with Escape; prototype controls are keyboard-accessible.

## Host snapshot and offline proof
No web host (revision 1's exception: a game add-on). The host is revision 1's approved `design/9-loot-ui/index.html` (merge commit 880aae7), a self-contained file with the game art and fonts inlined. Versions copy it and replace its Sync tab. Host parts used, in `index.html`: `windowFrame()` (window, tabs, footer), `syncBody()` (revision 1's Sync tab), `notice()` (dialogs), `chat()`/`sysLine()` (chat box), the `GROUPS`/`LABELS` switcher lists, CSS classes `.note-bar`, `table.list`, `.input`, `.tab`, `.btn`. Offline proof (2026-10-13): each of `versions/a.html`, `b.html`, `c.html` opened from disk in headless Chrome with every network request sent to a dead proxy; the only requests were the file itself and its inlined `data:` art and fonts (2/2 fonts loaded, no broken images), and the state switcher and in-game buttons changed state and URL offline.

## Confirmed decisions
Interview on #44, 2026-10-14:
1. Q1 No raid for the instance: **b**, one line in the officer's own chat, only in raid instances, plus the Sync tab. No pop-up.
2. Q2 Copy awards: **b**, the active raid by default, with a choice of any loaded raid that has awards. (Attach for "no raid" awards follows the same pattern.)
3. Q3 Removing a pasted raid with awards asks first: **yes**.
4. Button names: the site's, **Copy reserves** and **Import awards** (Robert, #16, 2026-10-14).
5. Q4 The overlap question can be put off: **yes**, "Decide later". Robert asked in the same answer for a way to say a run isn't a guild run, so no loot is recorded for a pug (Q6, open).
6. Q5 Brief confirmed: "Brief seems right." (2026-10-14)
7. Q6 Robert proposed instead a question at the start of each raid: "Is this a guild run?" No: everything stops. Yes: "Please select a raid event", with the one matching raid suggested; and if another officer already selected it, "Raid selected by so and so, you're good to go." Feasibility and refinements asked as Q8-Q9 (2026-10-14).
8. Q7 "No raid" awards can be discarded, asking first: **yes**.
9. Robert: "I'm fine with the officer interacting in this case. It's necessary." The off-the-cuff "Raid selected by Konvett Konvett, you're good to go." is not the wording to use; wording is drafted in the versions. Spec issue opened: robpaolella/bureaucracy-forever#307 (blocks #16).
10. Q8 Only the loot master is asked, with a fallback when master loot isn't set: "the raid leader (if they're an officer), or any officer running the addon at that point. Maybe you tighten up the logic." Tightened (in #307): loot master if master loot is on and they run the add-on; else the raid leader if they run the add-on; else the first add-on user by name. One chooser per group; the answer is shared with every add-on; any officer can change it in the Sync tab.
11. Q9 Asked again only on entering a different raid instance from the selected raid's, with that instance's raid pre-selected: **agreed**.
12. Fallback order confirmed: "Fallback looks good." Q10 **a**: anyone running the add-on counts as an officer (no officer list in the snapshot). Q11 revised states list: **agreed** (2026-10-14).

## Real-site experiment
None.

## Open decisions
- Layout choices the versions differ on (asked one by one after the critique).
