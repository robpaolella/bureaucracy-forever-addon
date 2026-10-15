-- Selection: the group's raid selection, which raid awards go to (ADDON-SPEC.md 2.1, 10.4; #63).
-- Saved for the helper: activeRaid (a raid id or nil), activeBy ("none", "chosen" or "off") and
-- chosenBy (the officer's name or nil). Beside them, the add-on's own: selectionCode (the chosen
-- raid's code, kept while it waits for that raid to load), selectionAt and selectionBy (the
-- choice's time and chooser, which order changes that cross: the later (at, by) wins).
local _, ns = ...

local Selection = {}
ns.Selection = Selection

local NEEDS_CONFIRMATION = "needs confirmation"

local function db() return ns.db end

local function set(activeBy, raidId, code, at, by)
  local d = db()
  d.activeBy, d.activeRaid = activeBy, raidId
  d.chosenBy = activeBy ~= "none" and by or nil
  d.selectionCode, d.selectionAt, d.selectionBy = code, at, by
end

-- True when (at, by) is later than the held choice: at first, then by byte by byte.
local function isLater(at, by)
  local d = db()
  if not d.selectionAt then return true end
  if at ~= d.selectionAt then return at > d.selectionAt end
  return by > (d.selectionBy or "")
end

-- This officer's name and a time later than the held choice's, so the change wins everywhere.
local function mine()
  local at = time()
  local held = db().selectionAt
  if held and at <= held then at = held + 1 end
  return at, UnitName("player")
end

-- True when moving the selection off the current raid needs the officer's confirmation.
local function leavingAwards(raidId)
  local current = db().activeRaid
  return current ~= nil and current ~= raidId and ns.Raids.HasAwards(current)
end

-- Selects the loaded raid with this code, or holds the code until it loads. A code two loaded
-- raids share selects neither: it is held and the notice returned.
local function applyCode(code, at, by)
  local raidId, notice = ns.Raids.FindByCode(code)
  if raidId then
    set("chosen", raidId, code, at, by)
    return nil
  end
  set("chosen", nil, code, at, by)
  return notice
end

-- activeBy, with no saved choice read as "none".
function Selection.ActiveBy()
  return db().activeBy or "none"
end

-- True on a run that is not a guild run: nothing is recorded, shown or sent (spec 2.1, "No").
function Selection.IsQuiet()
  return Selection.ActiveBy() == "off"
end

-- This officer chooses a loaded raid. Moving off a raid with awards returns nil and
-- "needs confirmation" until confirmed. Choosing the selected raid again changes nothing.
-- Returns true, or nil and why ("not loaded" or "needs confirmation").
function Selection.ChooseRaid(raidId, confirmed)
  local snapshot = ns.Raids.Get(raidId)
  if not snapshot then return nil, "not loaded" end
  if Selection.ActiveBy() == "chosen" and db().activeRaid == raidId then return true end
  if leavingAwards(raidId) and not confirmed then return nil, NEEDS_CONFIRMATION end
  local at, by = mine()
  set("chosen", raidId, snapshot.code:upper(), at, by)
  return true
end

-- This officer chooses "not a guild run". It never asks: awards stay with their raid, and
-- choosing a raid again undoes it.
function Selection.ChooseOff()
  if Selection.ActiveBy() == "off" then return true end
  local at, by = mine()
  set("off", nil, nil, at, by)
  return true
end

-- The site's pasted reserves text (spec 3.2): loads the raid and chooses it. Returns the raid
-- id, the update notice (or nil) and, when choosing needs confirmation, "needs confirmation":
-- the raid stays loaded and ChooseRaid(raidId, true) chooses it. A text that can't be read
-- returns nil and the error.
function Selection.Paste(pasted, confirmed)
  local snapshot, notice = ns.Sync.ReadPasted(pasted)
  if not snapshot then return nil, notice end
  local raidId = ns.Raids.Load(snapshot, "pasted")
  local _, waiting = Selection.ChooseRaid(raidId, confirmed)
  return raidId, notice, waiting
end

-- Applies the group's choice (an S message, spec 10.4): a raid code, or "-" for not a guild
-- run, with the sender's time and chooser. Only a later (at, by) applies; it never asks.
-- Returns true when applied, nil when not, and a notice when the code names two loaded raids.
function Selection.Apply(choice, at, by)
  if not isLater(at, by) then return nil end
  if choice == "-" then
    set("off", nil, nil, at, by)
    return true
  end
  return true, applyCode(choice:upper(), at, by)
end

-- The selected raid is no longer loaded (it left the inbox and isn't pasted): the selection
-- becomes none and its awards stay. Returns the notice for the officer, or nil when raidId
-- wasn't the selected raid or is still loaded.
function Selection.RaidGone(raidId)
  local d = db()
  if raidId == nil or d.activeRaid ~= raidId or ns.Raids.Get(raidId) then return nil end
  local name = d.selectionCode or raidId
  set("none", nil, nil, d.selectionAt, d.selectionBy)
  return "The selected raid (" .. name .. ") is no longer loaded. Choose the raid in the Sync tab."
end

-- Sets none and forgets the held choice, so any choice from the group applies (leaving the
-- group, or logging in outside one; #62).
function Selection.Clear()
  set("none", nil, nil, nil, nil)
end

-- The selection for the status read: activeRaid, activeBy, chosenBy, at, code, and waiting
-- (true when a chosen raid isn't loaded yet).
function Selection.Status()
  local d = db()
  local activeBy = Selection.ActiveBy()
  return {
    activeRaid = d.activeRaid, activeBy = activeBy, chosenBy = d.chosenBy,
    at = d.selectionAt, code = d.selectionCode,
    waiting = activeBy == "chosen" and d.activeRaid == nil,
  }
end

-- A raid loaded: a held choice waiting for its code is applied.
ns.Raids.afterLoad = function(raidId)
  local d = db()
  if Selection.ActiveBy() ~= "chosen" or d.activeRaid or not d.selectionCode then return end
  if ns.Raids.Get(raidId).code:upper() ~= d.selectionCode then return end
  applyCode(d.selectionCode, d.selectionAt, d.selectionBy)
end

-- Removing a pasted raid with awards asks first, selected or not (design #44); its awards stay.
-- Removing the selected raid's last copy sets none.
ns.Raids.beforeRemove = function(raidId, confirmed)
  if ns.Raids.HasAwards(raidId) and not confirmed then return NEEDS_CONFIRMATION end
  local d = db()
  if d.activeRaid == raidId and not d.raids[raidId].inbox then
    set("none", nil, nil, d.selectionAt, d.selectionBy)
  end
end
