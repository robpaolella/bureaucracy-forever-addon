-- Raids: the loaded raids' snapshots, kept between sessions (ADDON-SPEC.md 2, 2.1; #47).
-- Saved as BureaucracyForeverDB.raids[raidId] = { pasted = copy, inbox = copy }, each copy
-- { snapshot, loadedAt }. A raid's two copies are kept apart: a pasted one stays until the
-- officer removes it, the inbox's are replaced on every read. The copy in use is the one with
-- the later `generated`; on a tie the pasted one (same site build, so same content).
-- The selection (activeRaid) is Selection's (#63); the award lists (awards[raidId], noRaid) are #7's.
local _, ns = ...

local Raids = {}
ns.Raids = Raids

-- Hooks for the selection (#63). afterLoad(raidId) runs after a raid's snapshot is stored.
-- beforeRemove(raidId, confirmed) runs before a pasted raid is removed: it returns nil to let
-- it go, or a reason (such as "needs confirmation") to refuse.
Raids.afterLoad = nil
Raids.beforeRemove = nil

-- Others that run after a snapshot is stored, after afterLoad: Raids.OnLoad(hook), hook(raidId).
local loadHooks = {}
function Raids.OnLoad(hook)
  loadHooks[#loadHooks + 1] = hook
end

local function afterLoad(raidId)
  if Raids.afterLoad then Raids.afterLoad(raidId) end
  for _, hook in ipairs(loadHooks) do hook(raidId) end
end

local ORIGINS = { pasted = true, inbox = true }

local function store()
  ns.db.raids = ns.db.raids or {}
  return ns.db.raids
end

local function copyInUse(entry)
  local pasted, inbox = entry.pasted, entry.inbox
  if not (pasted and inbox) then return pasted or inbox, pasted and "pasted" or "inbox" end
  if inbox.snapshot.generated > pasted.snapshot.generated then return inbox, "inbox" end
  return pasted, "pasted"
end

local function loadedIds()
  local ids = {}
  for id, entry in pairs(store()) do
    if entry.pasted or entry.inbox then ids[id] = true end
  end
  return ids
end

local function loaded(raidId)
  if not raidId then return nil end
  local entry = store()[raidId]
  if entry and (entry.pasted or entry.inbox) then return entry end
end

-- The snapshot in use for a loaded raid, or nil.
function Raids.Get(raidId)
  local entry = loaded(raidId)
  return entry and copyInUse(entry).snapshot
end

-- Stores a snapshot validated by Snapshot.Validate, with its origin ("pasted" or "inbox").
-- A new copy replaces the raid's held copy of the same origin. Returns the raid id.
function Raids.Load(snapshot, origin)
  assert(ORIGINS[origin], "origin must be pasted or inbox")
  local raids = store()
  raids[snapshot.raid] = raids[snapshot.raid] or {}
  raids[snapshot.raid][origin] = { snapshot = snapshot, loadedAt = time() }
  afterLoad(snapshot.raid)
  return snapshot.raid
end

-- Replaces every inbox copy with the given validated snapshots (one per raid); an empty list
-- clears them, and pasted copies stay. Returns two lists of raid ids, sorted: the raids loaded
-- now that weren't before, and the raids no longer loaded at all (a pasted copy keeps a raid).
function Raids.ReplaceInbox(snapshots)
  local before = loadedIds()
  local raids = store()
  for id, entry in pairs(raids) do
    entry.inbox = nil
    if not entry.pasted then raids[id] = nil end
  end
  local now = time()
  for _, snapshot in ipairs(snapshots) do
    raids[snapshot.raid] = raids[snapshot.raid] or {}
    raids[snapshot.raid].inbox = { snapshot = snapshot, loadedAt = now }
  end
  local after = loadedIds()
  local added, left = {}, {}
  for id in pairs(after) do
    if not before[id] then added[#added + 1] = id end
  end
  for id in pairs(before) do
    if not after[id] then left[#left + 1] = id end
  end
  table.sort(added)
  table.sort(left)
  for _, snapshot in ipairs(snapshots) do afterLoad(snapshot.raid) end
  return added, left
end

-- Removes a raid's pasted copy; its inbox copy, if any, stays loaded. confirmed is passed to
-- the beforeRemove hook. Returns true, or nil and why: "not pasted" or the hook's reason.
function Raids.Remove(raidId, confirmed)
  local entry = store()[raidId]
  if not (entry and entry.pasted) then return nil, "not pasted" end
  if Raids.beforeRemove then
    local reason = Raids.beforeRemove(raidId, confirmed)
    if reason then return nil, reason end
  end
  entry.pasted = nil
  if not entry.inbox then store()[raidId] = nil end
  return true
end

-- The loaded raid with this code (spec 2), as its id and snapshot. A code two loaded raids
-- share gives neither: nil and a notice for the officer.
function Raids.FindByCode(code)
  local found
  code = tostring(code):upper()
  for id in pairs(loadedIds()) do
    if Raids.Get(id).code:upper() == code then
      if found then
        return nil, "Two loaded raids have the code " .. code .. ". Choose the raid in the Sync tab."
      end
      found = id
    end
  end
  if found then return found, Raids.Get(found) end
end

-- The loaded raids for the Sync tab, soonest start first. Each: id, code, name, env, instance
-- (when present), startsAt, durationMin, generated and loadedAt of the copy in use, origin (the
-- copy in use: "pasted" or "inbox"), and pasted and inbox (true for each copy held). Then the
-- selection (Selection.Status) and the helper's inbox read (Inbox.Status).
function Raids.Status()
  local list = {}
  for id in pairs(loadedIds()) do
    local entry = store()[id]
    local copy, origin = copyInUse(entry)
    local s = copy.snapshot
    list[#list + 1] = {
      id = id, code = s.code, name = s.name, env = s.env, instance = s.instance,
      startsAt = s.startsAt, durationMin = s.durationMin, generated = s.generated,
      loadedAt = copy.loadedAt, origin = origin,
      pasted = entry.pasted ~= nil, inbox = entry.inbox ~= nil,
    }
  end
  table.sort(list, function(a, b)
    if a.startsAt ~= b.startsAt then return a.startsAt < b.startsAt end
    return a.id < b.id
  end)
  return list, ns.Selection.Status(), ns.Inbox.Status()
end

-- The environment of the selected raid (activeRaid), or nil with none or one not loaded:
-- awards are then held as no raid (#7).
function Raids.Env()
  local snapshot = Raids.Get(ns.db.activeRaid)
  return snapshot and snapshot.env
end

-- The saved award records of a raid, voided ones included, and the no-raid list. #7 fills them.
function Raids.Awards(raidId)
  return (ns.db.awards or {})[raidId] or {}
end

function Raids.NoRaidAwards()
  return ns.db.noRaid or {}
end

function Raids.HasAwards(raidId)
  return #Raids.Awards(raidId) > 0
end
