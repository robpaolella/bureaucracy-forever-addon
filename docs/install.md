# Install and update the add-on

For guild officers. The add-on is a zip you download from GitHub and unzip into the game's `AddOns` folder. It works the same on Windows and Mac.

## Download

1. Open the [Releases page](https://github.com/robpaolella/bureaucracy-forever-addon/releases/latest). The latest release is at the top. The guild site's officer area links to the same page.
2. Under **Assets**, download `BureaucracyForever-<version>.zip` (the version number is in the name). Don't use "Source code".

## Find your AddOns folder

1. In the game launcher, click the gear next to **Play**, then **Show in Explorer** (on Mac, **Show in Finder**).
2. If you land in the main World of Warcraft folder, open the client's own folder first (during the beta, `_classic_beta_`).
3. Open `Interface`, then `AddOns`. Create either folder if it's missing.

## Install

1. Unzip the download. You get one folder, `BureaucracyForever`.
2. Put that folder inside `AddOns`, so the path ends `AddOns\BureaucracyForever` (Mac: `AddOns/BureaucracyForever`) and `BureaucracyForever.toc` sits directly in it.
3. Make sure there is exactly one such folder. A folder inside a folder (`BureaucracyForever\BureaucracyForever`) or a copy such as `BureaucracyForever (1)` won't work.
4. Start the game. If the add-on shows as out of date at character select, tick **Load out of date AddOns**.

## Update

1. Close the game, or at least be ready to `/reload` after.
2. Open the latest release's notes. If they have a **Before you update** section, read it first.
3. Replace the files in `AddOns\BureaucracyForever` with the new ones, **but keep `Inbox.lua`**. The desktop helper writes the reserves into that file; if you overwrite or delete it, the reserves are lost until the helper writes them again. Easiest way: copy everything from the new folder except `Inbox.lua`, and replace when asked.
4. In the game, type `/reload`. If the release notes' **Before you update** says a full restart is needed, quit the game and start it again instead.

## Check your version

In the game, type `/bf`. Chat shows `version <version>.`, for example `version 1.2.0.` Compare it with the latest release on the Releases page.
