# bureaucracy-forever-addon

In-game officer add-on for the Bureaucracy guild's loot system: when an item drops, officers see who hard- and soft-reserved it, and awards flow back to the guild site. It runs in the WoW Forever game client, used by guild officers.

## Stack
A World of Warcraft add-on in Lua 5.1, for the WoW Forever client: build 1.60.1.70374, `## Interface: 16001`, project id 18 (checked in the beta, robpaolella/bureaucracy-forever-addon#3 and #41). Lint with luacheck, test with busted, both on Lua 5.1.

## Checks
Run both from the repo root before any PR; CI runs them on every PR.
- `luacheck .`
- `busted`

To install the tools (Debian or Ubuntu; CI does the same):
```
sudo apt-get install -y lua5.1 liblua5.1-0-dev luarocks
sudo luarocks --lua-version=5.1 install luacheck 1.2.0-1
sudo luarocks --lua-version=5.1 install busted 2.3.0-1
```

## Run locally
- Outside the game: the tests run the add-on in a stand-in for the game (`spec/support/wow.lua`).
- In the game: make a folder `Interface\AddOns\BureaucracyForever` in the WoW Forever folder, and copy into it `BureaucracyForever.toc`, `Core.lua`, `Inbox.lua` and the `Modules` folder. The folder name must match the `.toc` name. Log in and type `/bf version`: chat shows the add-on's version (`/bf` opens the officers' window).
- After changing a file, `/reload` picks it up. A file new to the `.toc` needs a full restart of the game.

## Layout
- `BureaucracyForever.toc`: the game's list of the add-on's files, in load order, its version and its saved data (`BureaucracyForeverDB`).
- `Core.lua`: the shared namespace (`ns`), the log (`ns.Log(text)`, the last 50 entries this session), the event hub (`ns.On(event, handler)`) and the `/bf` command (`/bf` toggles the window, `/bf version`, `/bf minimap`, `/bf log` prints the log, `/bf practice` toggles practice mode). Every file gets `local ADDON_NAME, ns = ...`.
- `Modules/`: one file per part, each adding its table to `ns`: `Rules` (who should get each drop), `Records` (award records), `Tracking` (hand-outs until the game confirms them), `Snapshot` (the site's reserves text read and checked as data, never run), `Raids` (the loaded raids' snapshots, kept between sessions), `Selection` (the group's raid selection: which raid awards go to, or not a guild run; and the raid to suggest for the instance the player is in), `Sync` (reserves in, awards out), `Hub` (officers' hidden sync messages in and out: checks each one, rebuilds multi-part messages and records their awards; `Hub.SendOp(op, raidId)` sends an operation made on this add-on, as `Records` returns it, through a paced queue held during boss fights, and the same queue sends resend requests and answers them; for catch-up it sends `H` (what it holds for each loaded raid) at login or `/reload`, on joining a group, on loading a snapshot and in answer to `P;1`, answers a differing `H` with a whispered `C` of every operation id held, and hands a whole `C` to `Hub.onCatchUp` with the ids its sender lacks), `Digest` (the `H` digest: a CRC-32 in plain arithmetic, summed over the operation ids held), `Inbox` (reads the helper's inbox at login or `/reload`: its raids, their catch-ups, whether the helper is present), `Rolls` (roll-offs: `Rolls.Start(slot, item)` posts the call for a pop-up row, reads `/roll` lines and returns the roll-off as data through `Rolls.Result`; `Rolls.Reroll` re-rolls a tie; `Rolls.End` stops one reading, since only one roll-off reads at a time; `Rolls.IsPractice` returns the practice mode switch), `Practice` (practice mode's made-up reserves: `ns.PracticeReserves.Generate(members, drop)` returns one drop's holders, roster, candidates and copies from the group's names), `UI` (the pop-up and the officers' window), `AwardsTab` (the Awards tab: the selected raid's awards grouped by boss, read only, and the footer's loot master line), `Notice` (the shared notice window: `Notice.Raise(key, view)` draws a notice, held until a boss fight ends; raises the update notice when a loaded snapshot names a newer add-on), `StartQuestion` (the raid question: on entering a raid instance in a raid group, the chooser is asked after 5 seconds which raid this run is, or that it is not a guild run; asked again only in a different instance; `StartQuestion.AskGone()` opens it from the notice that the selected raid left the list).
- `Inbox.lua`: written by the desktop helper, read at login or `/reload`. It ships as a one-line placeholder comment (the game reports a zero-byte file as an error at login) and stays in the `.toc`, because the game only finds a new file after a full restart.
- `spec/`: busted tests. `spec/support/wow.lua` is the game stand-in: it loads the add-on in `.toc` order and fakes the game calls the add-on uses (events, slash commands, loot window, master loot, chat, timers, the clock, the chat log, raid rights (`wow.state.leader`, `wow.state.assistant`), hidden values (`wow.secret`), the instance the player is in, boss fights (`wow.bossFight`), what sending a hidden message returns (`wow.state.sendResult`), and the helper's inbox: `wow.start({ inbox = ... })`). It blocks chat lines sent from a timer or event, to be safe: stricter than the game was seen to be (see Watch out for). Extend it as code needs more of the game.
- Game calls the add-on uses are listed in `.luacheckrc`; add each new one there.
- `release/`: the release tooling, not part of the add-on and not in the `.toc`. `Release.lua` works out the version and notes, `Draft.lua` creates or refreshes the draft, `build.sh` builds the zip, `main.lua` runs them for the workflow.

## Deploy
Releases are zips on GitHub Releases; see Releases. The game files never change on a merge alone: officers install a published release.

## Releases
- **What is released:** the add-on, as `BureaucracyForever-<version>.zip`. It holds one `BureaucracyForever` folder with the `.toc` and the files it lists, including the placeholder `Inbox.lua`, so a new install works. `release/build.sh` builds it.
- **Version rule:** Semantic Versioning, worked out from the pull requests merged since the last published release: `fix` gives a patch, `feat` a minor, `!` or a `BREAKING CHANGE:` footer a major; other types alone give no release. The first release is 1.0.0.
- **Where the version lives:** stamped into the zip's `.toc` (`## Version:`) at build time, and shown by `/bf version`. It is never edited by hand or committed: the `.toc` in git says `0.0.0-dev`.
- **Source:** each merged pull request's title and body, looked up through the GitHub API, not commit messages. A commit with no pull request counts by its subject.
- **Release note:** every PR body has a `Release note:` line: one plain-English sentence for officers. A `feat`, `fix` or breaking PR always has a real one; `Release note: none` is only for other types. A missing note falls back to the PR title, marked for Robert to reword.
- **The draft:** after each merge to main, the Release workflow (`.github/workflows/release.yml`) creates or refreshes the one draft release on the repo's Releases page, targeting the merged commit's SHA. A merge that changes nothing in the release leaves the draft, and any edits to it, as it is.
- **Publishing:** only Robert publishes, by clicking Publish on the draft; no workflow or agent does. Publishing creates the tag `v<version>`, which is never moved or reused: a bad release is fixed by a newer one. If Publish lands in the instant a refresh deletes the old draft, the published release is deleted; the run then fails and its error says how to restore it from the tag, which is kept.
- **Dry run:** the workflow also runs on every PR and by hand (Actions, Release, Run workflow): it builds the zip as a downloadable artifact and creates no release or draft.
- **Convention:** /git/maestro/docs/git-workflow.md, Releases. This section holds this repo's whole rule set, so it applies even where that file isn't at hand.

## Watch out for
- WoW add-ons can't make web requests. Reserves get in and awards get out only through files written on logout or `/reload` (SavedVariables), copy-paste export strings, or the desktop helper.
- In a boss fight the game hides chat from add-ons and blocks their chat lines. What the beta showed (dungeon test, The Hall of Thanes, https://github.com/robpaolella/bureaucracy-forever-addon/issues/3#issuecomment-6151079785): during the boss encounter the Encounter and Chat limits were on, and the one system message in the fight (a `/roll`) arrived hidden (`<secret>`); both limits switched off the moment the boss died. Chat lines sent from a click worked in party chat inside the instance, but none was sent during a boss fight, so blocked chat lines in a boss fight were not tested.
- Timer-sent chat lines (from `C_Timer.After`, 3 seconds after the command, no click behind them) were tested in the open world (Eastern Kingdoms), out of combat, with no chat lockdown: a party line, a raid line and a raid warning as raid leader, and a raid line as a non-leader all arrived, with no `ADDON_ACTION_BLOCKED`. An earlier test (BF Probe v3, 2026-10-13, open world, alone, an earlier client build) had a `/say` line sent from a timer blocked (`ADDON_ACTION_BLOCKED`, no line arrived; https://github.com/robpaolella/bureaucracy-forever-addon/issues/3#issuecomment-6152787273). The two tests differ in channel and client build, so the `/say` block was not shown to apply to party and raid lines. A raid warning as a non-leader without assist was not tried. Timer-sent lines in boss fights, instances and chat lockdown were not tested. Results: robpaolella/bureaucracy-forever-addon#41 (https://github.com/robpaolella/bureaucracy-forever-addon/issues/41#issuecomment-6161604207).
- The stand-in still blocks any chat line sent from a timer or event, as a cautious choice.

## Reference material
- Loot add-on plan and beta results: robpaolella/bureaucracy-forever-addon#3. The site's loot plan: robpaolella/bureaucracy-forever#89.
- Data formats shared with the site and the helper live in the site repo's `ADDON-SPEC.md` (`/git/bureaucracy-forever`, robpaolella/bureaucracy-forever#271). Any format change is agreed there first.
- Desktop helper: robpaolella/bureaucracy-forever-helper.
