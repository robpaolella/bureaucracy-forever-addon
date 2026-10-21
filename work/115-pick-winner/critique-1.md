## PASS

**Model:** gpt-5.6-terra

**Scope and limits:** read-only pre-choice critique. I inspected `brief.md`, `decisions.md`, `design.json`, both issues and their comments, revision 1 and 2 authorities, `ADDON-SPEC.md`, `Modules/OpText.lua`, all supplied manifest entries, and all 78 supplied images. I reviewed the recorded offline proof in `decisions.md`; I did not independently run the prototypes, so interaction behaviour is assessed from the recorded proof and source, not asserted from screenshots.

### Checklist

1. **Brief — PASS.** `design/115-pick-winner/brief.md` clearly names the loot-master audience, record-only correction task, exact picker and recovery wording, boundaries, and #40 coverage. It correctly excludes Undo and unrelated revision 1/2 screens.
2. **Authority — PASS.** The versions retain revision 1’s WoW frame, type, row, button, chat and warning language; they reuse revision 2’s radio-choice rows. A/B/C differ in the requested single decision: inline row, separate notice window, and attached side panel. No product facts appear invented; chat wording agrees with `OpText.BuildLine`.
3. **Coverage — PASS.** The manifest has 78 unique, readable entries: 3 versions × 13 states × 1 theme × 2 widths. Named exceptional states are visibly covered: no other reserves, ten holders with a scroll cue, invalid roll, boss-fight lock, practice, success, and unposted correction. Loading and empty are explicitly not applicable; the read-only officer state remains governed by revision 1 as the brief says.
4. **Usability — PASS.** At desktop size, all versions keep the item, prior winner, choice, note, exact preview and irreversible action together. Disabled posting has a specific reason; the boss-fight and unposted states state both the problem and recovery. The 390 captures are deliberately scaled PC-game views, not phone layouts; they are therefore not judged against phone touch-target or text-size rules.
5. **Prototype contract — PASS, from recorded evidence.** `versions/a.html`, `b.html`, and `c.html` are self-contained and locally interactive. Visible state/theme controls, URL state parameters and `data-state` / `data-theme` markers agree. The source includes keyboard activation for choices and member options, Escape for the member list, native keyboard buttons, labels, `aria-live` preview, and a 200-character note limit. `decisions.md` records an offline, no-network flow through open roll, selected member, valid preview, post, chat line and completed row, with no script errors.
6. **Safety and decisions — PASS.** Data is clearly marked sample data; names are fictitious; the supplied versions have no production calls beyond a displayed release URL inherited from revision 1. The remaining decision—where the picker opens—is correctly left for Robert.

### Alternative trade-offs

- **A — inline row:** strongest connection to the affected award and closest reuse of the approved Give to someone else pattern. The trade-off is that the list scrolls to the affected row and hides earlier boss groups while it is open.
- **B — notice window:** isolates a consequential correction decision and follows the established “How was it won?” notice. It obscures more of the underlying Awards list, which is an acceptable trade-off only if Robert values focused review over continuous list context.
- **C — attached panel:** preserves both the Awards list and the highlighted source row while keeping the picker separate. It uses the most horizontal space, but the desktop 1440 captures show no collision or clipping.

### Manifest inspection

All images are in `/tmp/design-review-n8UuYz/versions/`. Each filename below is a separate inspected manifest entry.

| Version | State | Theme | Width | Inspected image | Result |
|---|---|---|---|---|---|
| A | pick-start | default | 390 / 1440 | `a-pick-start-default-390.png` / `a-pick-start-default-1440.png` | PASS — needs-a-winner row and Pick winner visible |
| A | pick-open | default | 390 / 1440 | `a-pick-open-default-390.png` / `a-pick-open-default-1440.png` | PASS — inline picker, no initial selection |
| A | pick-reserve | default | 390 / 1440 | `a-pick-reserve-default-390.png` / `a-pick-reserve-default-1440.png` | PASS — reserve choice and correction preview |
| A | pick-roll | default | 390 / 1440 | `a-pick-roll-default-390.png` / `a-pick-roll-default-1440.png` | PASS — open-roll member and roll fields |
| A | pick-roll-missing | default | 390 / 1440 | `a-pick-roll-missing-default-390.png` / `a-pick-roll-missing-default-1440.png` | PASS — invalid-roll recovery and disabled posting |
| A | pick-db | default | 390 / 1440 | `a-pick-db-default-390.png` / `a-pick-db-default-1440.png` | PASS — disenchant/bank preview |
| A | pick-again | default | 390 / 1440 | `a-pick-again-default-390.png` / `a-pick-again-default-1440.png` | PASS — prior-winner choice and cleared note |
| A | pick-none | default | 390 / 1440 | `a-pick-none-default-390.png` / `a-pick-none-default-1440.png` | PASS — explicit no-reserves message |
| A | pick-crowded | default | 390 / 1440 | `a-pick-crowded-default-390.png` / `a-pick-crowded-default-1440.png` | PASS — dense holder list and scroll cue |
| A | pick-fight | default | 390 / 1440 | `a-pick-fight-default-390.png` / `a-pick-fight-default-1440.png` | PASS — chat-lock reason and disabled action |
| A | pick-practice | default | 390 / 1440 | `a-pick-practice-default-390.png` / `a-pick-practice-default-1440.png` | PASS — practice title and preview marker |
| A | pick-done | default | 390 / 1440 | `a-pick-done-default-390.png` / `a-pick-done-default-1440.png` | PASS — corrected award and chat outcome |
| A | pick-unposted | default | 390 / 1440 | `a-pick-unposted-default-390.png` / `a-pick-unposted-default-1440.png` | PASS — durable record plus `/bf log` recovery |
| B | pick-start | default | 390 / 1440 | `b-pick-start-default-390.png` / `b-pick-start-default-1440.png` | PASS — unchanged starting row |
| B | pick-open | default | 390 / 1440 | `b-pick-open-default-390.png` / `b-pick-open-default-1440.png` | PASS — focused separate picker window |
| B | pick-reserve | default | 390 / 1440 | `b-pick-reserve-default-390.png` / `b-pick-reserve-default-1440.png` | PASS — reserve correction preview |
| B | pick-roll | default | 390 / 1440 | `b-pick-roll-default-390.png` / `b-pick-roll-default-1440.png` | PASS — open-roll fields remain legible |
| B | pick-roll-missing | default | 390 / 1440 | `b-pick-roll-missing-default-390.png` / `b-pick-roll-missing-default-1440.png` | PASS — invalid-roll recovery visible |
| B | pick-db | default | 390 / 1440 | `b-pick-db-default-390.png` / `b-pick-db-default-1440.png` | PASS — disenchant/bank preview |
| B | pick-again | default | 390 / 1440 | `b-pick-again-default-390.png` / `b-pick-again-default-1440.png` | PASS — prior-winner correction |
| B | pick-none | default | 390 / 1440 | `b-pick-none-default-390.png` / `b-pick-none-default-1440.png` | PASS — no-reserves message |
| B | pick-crowded | default | 390 / 1440 | `b-pick-crowded-default-390.png` / `b-pick-crowded-default-1440.png` | PASS — crowded list and scroll affordance |
| B | pick-fight | default | 390 / 1440 | `b-pick-fight-default-390.png` / `b-pick-fight-default-1440.png` | PASS — lock explanation remains adjacent to action |
| B | pick-practice | default | 390 / 1440 | `b-pick-practice-default-390.png` / `b-pick-practice-default-1440.png` | PASS — practice markers preserved |
| B | pick-done | default | 390 / 1440 | `b-pick-done-default-390.png` / `b-pick-done-default-1440.png` | PASS — corrected row and chat |
| B | pick-unposted | default | 390 / 1440 | `b-pick-unposted-default-390.png` / `b-pick-unposted-default-1440.png` | PASS — record and failure recovery visible |
| C | pick-start | default | 390 / 1440 | `c-pick-start-default-390.png` / `c-pick-start-default-1440.png` | PASS — unchanged starting row |
| C | pick-open | default | 390 / 1440 | `c-pick-open-default-390.png` / `c-pick-open-default-1440.png` | PASS — attached panel and highlighted source row |
| C | pick-reserve | default | 390 / 1440 | `c-pick-reserve-default-390.png` / `c-pick-reserve-default-1440.png` | PASS — reserve preview fits panel |
| C | pick-roll | default | 390 / 1440 | `c-pick-roll-default-390.png` / `c-pick-roll-default-1440.png` | PASS — member and roll fields fit without clipping |
| C | pick-roll-missing | default | 390 / 1440 | `c-pick-roll-missing-default-390.png` / `c-pick-roll-missing-default-1440.png` | PASS — invalid-roll recovery visible |
| C | pick-db | default | 390 / 1440 | `c-pick-db-default-390.png` / `c-pick-db-default-1440.png` | PASS — disenchant/bank preview |
| C | pick-again | default | 390 / 1440 | `c-pick-again-default-390.png` / `c-pick-again-default-1440.png` | PASS — prior-winner correction |
| C | pick-none | default | 390 / 1440 | `c-pick-none-default-390.png` / `c-pick-none-default-1440.png` | PASS — no-reserves message |
| C | pick-crowded | default | 390 / 1440 | `c-pick-crowded-default-390.png` / `c-pick-crowded-default-1440.png` | PASS — holder density and scroll cue fit panel |
| C | pick-fight | default | 390 / 1440 | `c-pick-fight-default-390.png` / `c-pick-fight-default-1440.png` | PASS — lock state and reason visible |
| C | pick-practice | default | 390 / 1440 | `c-pick-practice-default-390.png` / `c-pick-practice-default-1440.png` | PASS — practice markers preserved |
| C | pick-done | default | 390 / 1440 | `c-pick-done-default-390.png` / `c-pick-done-default-1440.png` | PASS — corrected row and chat |
| C | pick-unposted | default | 390 / 1440 | `c-pick-unposted-default-390.png` / `c-pick-unposted-default-1440.png` | PASS — record and recovery message visible |

Robert should choose between A, B and C based on the trade-offs above; this review does not select one on his behalf.
Unchanged: /git/bureaucracy-forever-addon-worktrees/docs-115-design-pick-winner is as the command found it.
