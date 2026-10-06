# bureaucracy-forever-addon

In-game officer add-on for the Bureaucracy guild's loot system: when an item drops, officers see who hard- and soft-reserved it, and awards flow back to the guild site. It runs in the WoW Forever game client, used by guild officers.

## Stack
A World of Warcraft add-on (Lua, with a `.toc` file). The exact client and add-on API version are still to be settled by the feasibility check.

## Checks
None yet: there's no code. Add a linter and tests with the first code.

## Run locally
To be decided with the first code.

## Layout
To be decided with the first code.

## Deploy
To be decided.

## Watch out for
- WoW add-ons can't make web requests. Reserves get in and awards get out only through files written on logout or `/reload` (SavedVariables), copy-paste export strings, or a desktop companion app.
- Robert has beta access to WoW Forever only until about October 21, 2026. The client version and add-on API need checking before then.

## Reference material
- Loot plan: robpaolella/bureaucracy-forever#89. Robert's answer #24 there: the add-on is its own planning track.
- Guild site repo (`/git/bureaucracy-forever`) and its Discord bot (`/git/bureaucracy-forever-discord-bot`) share data through `SYNC-SPEC.md`, kept identical in both repos. Any data format shared with the site must be agreed there, in both repos.
