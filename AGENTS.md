# bureaucracy-forever-addon

In-game officer add-on for the Bureaucracy guild's loot system: when an item drops, officers see who hard- and soft-reserved it, and awards flow back to the guild site. It runs in the WoW Forever game client, used by guild officers.

## Stack
A World of Warcraft add-on in Lua 5.1, for the WoW Forever client: build 1.60.1.70338, `## Interface: 16001`, project id 18 (checked in the beta, robpaolella/bureaucracy-forever-addon#3). Lint with luacheck, test with busted, both on Lua 5.1.

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
- In the game: make a folder `Interface\AddOns\BureaucracyForever` in the WoW Forever folder, and copy into it `BureaucracyForever.toc`, `Core.lua`, `Inbox.lua` and the `Modules` folder. The folder name must match the `.toc` name. Log in and type `/bf`: chat shows the add-on's version.
- After changing a file, `/reload` picks it up. A file new to the `.toc` needs a full restart of the game.

## Layout
- `BureaucracyForever.toc`: the game's list of the add-on's files, in load order, its version and its saved data (`BureaucracyForeverDB`).
- `Core.lua`: the shared namespace (`ns`), the event hub (`ns.On(event, handler)`) and the `/bf` command. Every file gets `local ADDON_NAME, ns = ...`.
- `Modules/`: one file per part, each adding its table to `ns`: `Rules` (who should get each drop), `Records` (award records), `Tracking` (hand-outs until the game confirms them), `Sync` (reserves in, awards out), `UI` (the pop-up and the officers' window).
- `Inbox.lua`: written by the desktop helper, read at login or `/reload`. It ships empty and stays in the `.toc`, because the game only finds a new file after a full restart.
- `spec/`: busted tests. `spec/support/wow.lua` is the game stand-in: it loads the add-on in `.toc` order and fakes the game calls the add-on uses (events, slash commands, loot window, master loot, chat, timers, the chat log). It blocks chat lines with no click behind them, as the game does. Extend it as code needs more of the game.
- Game calls the add-on uses are listed in `.luacheckrc`; add each new one there.
- `release/`: the release tooling, not part of the add-on and not in the `.toc`. `Release.lua` works out the version and notes, `Draft.lua` creates or refreshes the draft, `build.sh` builds the zip, `main.lua` runs them for the workflow.

## Deploy
Releases are zips on GitHub Releases; see Releases. The game files never change on a merge alone: officers install a published release.

## Releases
- **What is released:** the add-on, as `BureaucracyForever-<version>.zip`. It holds one `BureaucracyForever` folder with the `.toc` and the files it lists, including the empty `Inbox.lua`, so a new install works. `release/build.sh` builds it.
- **Version rule:** Semantic Versioning, worked out from the pull requests merged since the last published release: `fix` gives a patch, `feat` a minor, `!` or a `BREAKING CHANGE:` footer a major; other types alone give no release. The first release is 1.0.0.
- **Where the version lives:** stamped into the zip's `.toc` (`## Version:`) at build time, and shown by `/bf`. It is never edited by hand or committed: the `.toc` in git says `0.0.0-dev`.
- **Source:** each merged pull request's title and body, looked up through the GitHub API, not commit messages. A commit with no pull request counts by its subject.
- **Release note:** every PR body has a `Release note:` line: one plain-English sentence for officers. A `feat`, `fix` or breaking PR always has a real one; `Release note: none` is only for other types. A missing note falls back to the PR title, marked for Robert to reword.
- **The draft:** after each merge to main, the Release workflow (`.github/workflows/release.yml`) creates or refreshes the one draft release on the repo's Releases page, targeting the merged commit's SHA. A merge that changes nothing in the release leaves the draft, and any edits to it, as it is.
- **Publishing:** only Robert publishes, by clicking Publish on the draft; no workflow or agent does. Publishing creates the tag `v<version>`, which is never moved or reused: a bad release is fixed by a newer one.
- **Dry run:** the workflow also runs on every PR and by hand (Actions, Release, Run workflow): it builds the zip as a downloadable artifact and creates no release or draft.

## Watch out for
- WoW add-ons can't make web requests. Reserves get in and awards get out only through files written on logout or `/reload` (SavedVariables), copy-paste export strings, or the desktop helper.
- In a boss fight the game hides chat from add-ons and blocks their chat lines. A chat line sent from a timer, with no click behind it, was blocked in the beta (`ADDON_ACTION_BLOCKED`); the stand-in also blocks one sent from an event, to be safe. The beta results are in #3's comments.

## Reference material
- Loot add-on plan and beta results: robpaolella/bureaucracy-forever-addon#3. The site's loot plan: robpaolella/bureaucracy-forever#89.
- Data formats shared with the site and the helper live in the site repo's `ADDON-SPEC.md` (`/git/bureaucracy-forever`, robpaolella/bureaucracy-forever#271). Any format change is agreed there first.
- Desktop helper: robpaolella/bureaucracy-forever-helper.
