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
| 1 | How the pop-up shows the items | a: one list of every item beside the loot window, roll-offs inside their row; b: one item at a time with a queue; c: labels on the game's loot window plus a side window | **a**. Robert, 2026-10-13: "I agree, I think A is the best option. It allows them to see everything at once." |
| 2 | How the Awards tab is ordered | a, c: one list by time; b: grouped by boss, time order within each | **b**. Robert, 2026-10-13: "I agree as well. I think B is the best view." |

The picks come from different versions, so `versions/d.html` combines them: A's pop-up with B's Awards grouped by boss. It adds no behaviour that no version had, so it doesn't repeat the critique.

**Chosen: version D** (`index.html`): A's pop-up with B's Awards tab grouped by boss. Robert, 2026-10-13 (Q14): "D is approved." That authorizes the design PR; only Robert merging it approves the design for building. The PR link is on #9 under `## Design PR`.

## Alternatives
| Version | What differs / why rejected or chosen | Only this version had (lost) | Robert's OK to drop | Evidence |
| --- | --- | --- | --- | --- |
| a | Its pop-up was chosen (kept in D); its Awards list by time was not | Awards tab as one list by time | "D is approved", 2026-10-13, after being told what each dropped version alone had | [manifest](screenshots/all/manifest.json), `screenshots/all/a-*.png` |
| b | Its Awards grouping was chosen (kept in D); its one-item-at-a-time pop-up was not | One-item card with a queue of item icons and previous/next | same | `screenshots/all/b-*.png` |
| c | Neither decision picked it; labels break when an add-on replaces the game's loot window and page with its 4 slots | Labels attached to the game's loot window, separate details window | same | `screenshots/all/c-*.png` |
| d | Chosen: combines Robert's picks | (kept) | n/a | `screenshots/all/d-*.png`, [approved manifest](screenshots/approved/manifest.json) |

A version is removed, replaced or left out at freeze only after Robert confirms what it
alone had can go.

All-version captures were completed and inspected before pruning `versions/`: 240 images (4 versions × 30 states × default × 390/1440), [manifest](screenshots/all/manifest.json). Approved: 60 images (30 states × default × 390/1440), [manifest](screenshots/approved/manifest.json), every one inspected.
- After the all-version capture, the practice view's officers' window moved up 50px so its tabs fit the 972px-tall capture; `screenshots/all/d-practice-*` show the earlier spot. Small pixel differences elsewhere are the spinner animation and text smoothing.
- Offline proof: `index.html` opened in headless Chrome with all network blocked; the page requested only its own file and inlined `data:` assets; art and fonts rendered. Interactions (B queue, C paging and ⚠) were checked in Chrome with the network blocked before the freeze.
- Capture limitation: the 390 captures show the desktop game windows scaled down; phone use doesn't apply to a PC game (brief).

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
| herdr, 2026-10-13 | All | Robert picked A's pop-up (Q12) and B's Awards grouping (Q13) | Combined as version D; checked at both widths | Done |
| Maker, 2026-10-13 | All, practice state | The practice view never drew the officers' window with its "[Practice]" title | Fixed in all versions; window placed clear of the minimap | Done |

No Open Design comments were left (checked 2026-10-13 after each sync).

## Experiment
None.

## Open items
None affecting the approved scope. Deferred, out of scope:
- Roll-off countdown: waits on the timer chat beta test (#33); may come as a later revision (Q9, Q10).
- ElvUI / LUI skins: backlog.

## Build handoff
Merged folder/revision is the feature authority; DESIGN.md/live site govern site-wide
look. Reconcile issues and paused branches in prep before marking ready. Without a
conductor, the design session owns that follow-up. Later revisions use new issues/PRs.
