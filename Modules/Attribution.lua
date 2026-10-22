-- Attribution: which boss an item came from, from the loot tables (ADDON-SPEC.md 11; #23).
-- Kept per raid in BureaucracyForeverDB.attribution[raidId] = { kills = { [bossRowId] = time },
-- pulls = { time, ... }, corpses = { [sourceGuid] = time first opened } }, so a /reload mid-raid
-- loses nothing. Only the selected loaded raid records; the result is a suggestion the officer
-- can change for one award.
local _, ns = ...

local Attribution = {}
ns.Attribution = Attribution

-- The selected raid's id and snapshot, or nil with none loaded or on a run that is not a
-- guild run (spec 2.1: nothing recorded).
local function current()
  if ns.Selection.IsQuiet() then return nil end
  local raidId = ns.Selection.Status().activeRaid
  local snapshot = ns.Raids.Get(raidId)
  if snapshot then return raidId, snapshot end
end

local function saved(raidId)
  ns.db.attribution = ns.db.attribution or {}
  local all = ns.db.attribution
  all[raidId] = all[raidId] or { kills = {}, pulls = {}, corpses = {} }
  return all[raidId]
end

local function normal(name)
  return (tostring(name):lower():gsub("%s", ""))
end

-- The row id of the one non-Trash boss row for the game's kill. A row with an `encounter` matches
-- by that id; the name (ignoring case and spaces) is tried only against rows without one, and
-- only when no row has the id (ADDON-SPEC.md 3.1). No match, or two, gives nil: nothing is guessed.
local function match(snapshot, id, name)
  local byId, byName, ids, names = nil, nil, 0, 0
  for _, boss in ipairs(snapshot.bosses) do
    if not boss.trash then
      if boss.encounter ~= nil then
        if boss.encounter == id then
          byId, ids = boss.id, ids + 1
        end
      elseif normal(boss.name) == normal(name) then
        byName, names = boss.id, names + 1
      end
    end
  end
  if ids > 0 then return ids == 1 and byId or nil end
  return names == 1 and byName or nil
end

ns.On("ENCOUNTER_START", function()
  local raidId = current()
  if not raidId then return end
  local pulls = saved(raidId).pulls
  pulls[#pulls + 1] = time()
end)

ns.On("ENCOUNTER_END", function(id, name, _, _, success)
  local raidId, snapshot = current()
  if not raidId or success ~= 1 then return end
  local bossId = match(snapshot, id, name)
  if not bossId then return end
  saved(raidId).kills[bossId] = time()
  ns.UI.RefreshReserves() -- the heading gains its "· killed" mark if the tab is open
end)

-- True when this boss row is recorded as killed in the selected raid.
function Attribution.Killed(bossId)
  local raidId = current()
  if not raidId then return false end
  local data = (ns.db.attribution or {})[raidId]
  return data ~= nil and data.kills[bossId] ~= nil
end

-- Notes each corpse in the open loot window the first time it is seen; a known one keeps its time.
ns.On("LOOT_OPENED", function()
  local raidId = current()
  if not raidId then return end
  for slot = 1, ns.LootWindow.NumItems() do
    local sources = { ns.LootWindow.SourceInfo(slot) }
    for i = 1, #sources, 2 do
      local corpses = saved(raidId).corpses
      if corpses[sources[i]] == nil then corpses[sources[i]] = time() end
    end
  end
end)

-- The boss row id to suggest for an item on a corpse (its source GUID), or nil for none: the
-- officer picks. A second value, "unlisted", tells that no table holds the item.
function Attribution.Suggest(item, guid)
  local raidId, snapshot = current()
  if not raidId then return nil end
  local candidates, trash = {}, {}
  for _, boss in ipairs(snapshot.bosses) do
    if boss.trash then trash[#trash + 1] = boss.id end
    for _, listed in ipairs(boss.items) do
      if listed == item then
        candidates[#candidates + 1] = boss.id
        break
      end
    end
  end
  if #candidates == 1 then return candidates[1] end
  if #candidates == 0 then
    return #trash == 1 and trash[1] or nil, "unlisted"
  end
  local data = (ns.db.attribution or {})[raidId]
  if not data then return nil end
  local opened = data.corpses[guid] or time()
  local best, bestAt, tied
  for _, id in ipairs(candidates) do
    local at = data.kills[id]
    if at and at <= opened then
      if not bestAt or at > bestAt then
        best, bestAt, tied = id, at, false
      elseif at == bestAt then
        tied = true
      end
    end
  end
  if not best or tied then return nil end
  for _, pulled in ipairs(data.pulls) do
    if pulled > bestAt and pulled <= opened then return nil end
  end
  return best
end
