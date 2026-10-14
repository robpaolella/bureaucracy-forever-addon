## FIXES

**Model:** OpenAI GPT-5.2.  
**Evidence limits:** Read-only pre-choice critique. I reviewed the supplied brief, issue #44 and #16 comments, `design.json`, the revision-1 host, all three self-contained prototypes, affected Lua module stubs, and the supplied screenshot manifest. I did not run a browser or production workflow, as requested. The brief records offline proof; screenshots alone cannot prove interaction behaviour.

1. **Use the approved “Decide later” wording consistently.**  
   - **Evidence:** `design/44-sync-raids/brief.md`, states `ask-guild`, `ask-raid`, `ask-overlap`, and `ask-nomatch`, specifies **“Decide later”**. Every version renders the action as **“Later”**: for example `a-ask-guild-default-1440.png`, `b-ask-overlap-default-1440.png`, and `c-ask-nomatch-default-1440.png`; source `versions/{a,b,c}.html`, `askContent()`.  
   - **Rule:** Checklist 1 — exact draft wording; craft floor — controls name their action.  
   - **Problem:** “Later” is less clear about what will happen to awards and differs from the settled wording.  
   - **Smallest correction:** Change every chooser deferral action from `Later` to `Decide later`, including its accessible/button text.

2. **Show a usable Remove path for the pasted raid in the crowded state in versions B and C.**  
   - **Evidence:** `brief.md`, `sync-crowded`: maximum content includes “a pasted one … with Remove.”  
     - `b-sync-crowded-default-1440.png` lists Blackwing Lair but has no visible Remove action.  
     - `c-sync-crowded-default-1440.png` opens the raid menu, where “Remove a pasted raid…” is greyed out. Source confirms this is not interactive: `versions/c.html`, `SYNC_V.c`, the menu row has no `data-goto`, `tabindex`, or button.  
   - **Rule:** Checklist 3 — all stated roles/content extremes represented in actual pixels; Checklist 4 — recovery and destructive-action affordances; Checklist 5 — local interaction contract.  
   - **Problem:** Officers cannot discover or exercise the required removal path while reviewing the maximum-content case. In C it visually appears unavailable despite a pasted raid being present.  
   - **Smallest correction:** In B, expose **Remove** when the pasted raid is selected and include a crowded-state capture that demonstrates it. In C, replace the disabled menu row with an enabled, keyboard-accessible removal action for the pasted raid, leading to `sync-remove`; update the crowded capture.

3. **Make the prototype’s displayed raid-selection paths honest about what they demonstrate.**  
   - **Evidence:** `versions/{a,b,c}.html`, `SYNC_V.a/b/c`: choosing a different raid routes to `sync-switch` or `sync-chosen`, but the model is regenerated from the fixed state and does not retain the selected row/raid. In C, each non-selected dropdown option similarly routes to a fixed `sync-switch`. The recorded offline proof in `brief.md` says buttons and controls changed state and URL, not that selection was retained.  
   - **Rule:** Checklist 5 — local interactions, URL parameters, and applied markers agree; do not imply unproven browser behaviour.  
   - **Problem:** The controls visually present as raid selection, but the prototype does not demonstrate a changed selection or the corresponding selected marker after confirmation. That makes the variants harder to judge on their core interaction.  
   - **Smallest correction:** Either retain the selected raid in local prototype state and update the visible active marker after Switch, or label these controls explicitly as state-navigation examples and add a capture/state for “different raid selected.” The former is preferable because it tests the intended interaction without changing product scope.

### What is working

- The visual authority is preserved: the window frame, game-style controls, dark environment, typography, tabs, notice dialogs, list treatment, and minimap context all remain recognisably revision 1.
- The alternatives make real independent choices, rather than superficial restyling: A is a table-first Sync tab with a two-step central chooser; B is a split list/detail layout and one-step chooser; C is compact with a dropdown and minimap-adjacent prompt.
- Safety is sound in the provided material: sample raid/player data is declared made-up; no secret material or production call is present in the supplied self-contained files. The visible GitHub URL is a copyable error-recovery value, not a network request.
- The scaled 390-wide captures are an acceptable trade-off, not a responsive-design failure: the brief correctly defines them as a scaled PC game screen, rather than a phone UI.

### Screenshot inspection table

All entries are `default`; each cell names the two manifest images inspected as the supplied 390 and 1440 representations.

| Version | State | Theme | Width / inspected image(s) | Result |
|---|---|---|---|---|
| A | ask-guild | default | 390, 1440 — `a-ask-guild-default-{390,1440}.png` | Fix #1 |
| A | ask-raid | default | 390, 1440 — `a-ask-raid-default-{390,1440}.png` | Fix #1 |
| A | ask-overlap | default | 390, 1440 — `a-ask-overlap-default-{390,1440}.png` | Fix #1 |
| A | ask-nomatch | default | 390, 1440 — `a-ask-nomatch-default-{390,1440}.png` | Fix #1 |
| A | ask-fallback | default | 390, 1440 — `a-ask-fallback-default-{390,1440}.png` | Fix #1 |
| A | ask-again | default | 390, 1440 — `a-ask-again-default-{390,1440}.png` | Pass |
| A | sync-chosen | default | 390, 1440 — `a-sync-chosen-default-{390,1440}.png` | Pass |
| A | sync-follower | default | 390, 1440 — `a-sync-follower-default-{390,1440}.png` | Pass |
| A | sync-crowded | default | 390, 1440 — `a-sync-crowded-default-{390,1440}.png` | Pass |
| A | sync-switch | default | 390, 1440 — `a-sync-switch-default-{390,1440}.png` | Pass |
| A | sync-off | default | 390, 1440 — `a-sync-off-default-{390,1440}.png` | Pass |
| A | sync-undecided | default | 390, 1440 — `a-sync-undecided-default-{390,1440}.png` | Pass |
| A | sync-gone | default | 390, 1440 — `a-sync-gone-default-{390,1440}.png` | Pass |
| A | sync-noraid | default | 390, 1440 — `a-sync-noraid-default-{390,1440}.png` | Pass |
| A | sync-discard | default | 390, 1440 — `a-sync-discard-default-{390,1440}.png` | Pass |
| A | sync-empty | default | 390, 1440 — `a-sync-empty-default-{390,1440}.png` | Pass |
| A | sync-pasted | default | 390, 1440 — `a-sync-pasted-default-{390,1440}.png` | Pass |
| A | sync-remove | default | 390, 1440 — `a-sync-remove-default-{390,1440}.png` | Pass |
| A | sync-refused | default | 390, 1440 — `a-sync-refused-default-{390,1440}.png` | Pass |
| B | ask-guild | default | 390, 1440 — `b-ask-guild-default-{390,1440}.png` | Fix #1 |
| B | ask-raid | default | 390, 1440 — `b-ask-raid-default-{390,1440}.png` | Fix #1 |
| B | ask-overlap | default | 390, 1440 — `b-ask-overlap-default-{390,1440}.png` | Fix #1 |
| B | ask-nomatch | default | 390, 1440 — `b-ask-nomatch-default-{390,1440}.png` | Fix #1 |
| B | ask-fallback | default | 390, 1440 — `b-ask-fallback-default-{390,1440}.png` | Fix #1 |
| B | ask-again | default | 390, 1440 — `b-ask-again-default-{390,1440}.png` | Pass |
| B | sync-chosen | default | 390, 1440 — `b-sync-chosen-default-{390,1440}.png` | Pass |
| B | sync-follower | default | 390, 1440 — `b-sync-follower-default-{390,1440}.png` | Pass |
| B | sync-crowded | default | 390, 1440 — `b-sync-crowded-default-{390,1440}.png` | Fix #2, #3 |
| B | sync-switch | default | 390, 1440 — `b-sync-switch-default-{390,1440}.png` | Fix #3 |
| B | sync-off | default | 390, 1440 — `b-sync-off-default-{390,1440}.png` | Pass |
| B | sync-undecided | default | 390, 1440 — `b-sync-undecided-default-{390,1440}.png` | Pass |
| B | sync-gone | default | 390, 1440 — `b-sync-gone-default-{390,1440}.png` | Pass |
| B | sync-noraid | default | 390, 1440 — `b-sync-noraid-default-{390,1440}.png` | Pass |
| B | sync-discard | default | 390, 1440 — `b-sync-discard-default-{390,1440}.png` | Pass |
| B | sync-empty | default | 390, 1440 — `b-sync-empty-default-{390,1440}.png` | Pass |
| B | sync-pasted | default | 390, 1440 — `b-sync-pasted-default-{390,1440}.png` | Pass |
| B | sync-remove | default | 390, 1440 — `b-sync-remove-default-{390,1440}.png` | Pass |
| B | sync-refused | default | 390, 1440 — `b-sync-refused-default-{390,1440}.png` | Pass |
| C | ask-guild | default | 390, 1440 — `c-ask-guild-default-{390,1440}.png` | Fix #1 |
| C | ask-raid | default | 390, 1440 — `c-ask-raid-default-{390,1440}.png` | Fix #1 |
| C | ask-overlap | default | 390, 1440 — `c-ask-overlap-default-{390,1440}.png` | Fix #1 |
| C | ask-nomatch | default | 390, 1440 — `c-ask-nomatch-default-{390,1440}.png` | Fix #1 |
| C | ask-fallback | default | 390, 1440 — `c-ask-fallback-default-{390,1440}.png` | Fix #1 |
| C | ask-again | default | 390, 1440 — `c-ask-again-default-{390,1440}.png` | Pass |
| C | sync-chosen | default | 390, 1440 — `c-sync-chosen-default-{390,1440}.png` | Pass |
| C | sync-follower | default | 390, 1440 — `c-sync-follower-default-{390,1440}.png` | Pass |
| C | sync-crowded | default | 390, 1440 — `c-sync-crowded-default-{390,1440}.png` | Fix #2, #3 |
| C | sync-switch | default | 390, 1440 — `c-sync-switch-default-{390,1440}.png` | Fix #3 |
| C | sync-off | default | 390, 1440 — `c-sync-off-default-{390,1440}.png` | Pass |
| C | sync-undecided | default | 390, 1440 — `c-sync-undecided-default-{390,1440}.png` | Pass |
| C | sync-gone | default | 390, 1440 — `c-sync-gone-default-{390,1440}.png` | Pass |
| C | sync-noraid | default | 390, 1440 — `c-sync-noraid-default-{390,1440}.png` | Pass |
| C | sync-discard | default | 390, 1440 — `c-sync-discard-default-{390,1440}.png` | Pass |
| C | sync-empty | default | 390, 1440 — `c-sync-empty-default-{390,1440}.png` | Pass |
| C | sync-pasted | default | 390, 1440 — `c-sync-pasted-default-{390,1440}.png` | Pass |
| C | sync-remove | default | 390, 1440 — `c-sync-remove-default-{390,1440}.png` | Pass |
| C | sync-refused | default | 390, 1440 — `c-sync-refused-default-{390,1440}.png` | Pass |

No alternative is selected here. Once the three corrections have refreshed evidence, the re-check should assess only fixes **#1–#3**, retaining these numbers.
Unchanged: /git/bureaucracy-forever-addon is as the command found it.
