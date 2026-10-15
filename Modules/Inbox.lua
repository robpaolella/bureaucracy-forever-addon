-- Inbox: the desktop helper's file (ADDON-SPEC.md 7.3), read once at login or /reload, after every
-- file has loaded (the helper's Inbox.lua is last in the .toc). Each raid's snapshot is checked
-- by Snapshot.Validate and loaded as an inbox copy (Raids.ReplaceInbox). The file is data the game
-- has already run; the add-on checks its shape before using any of it.
local ADDON_NAME, ns = ...

local Inbox = {}
ns.Inbox = Inbox

-- This session's read: whether a valid file was read (the helper is present), when, the
-- problems found and each loaded raid's catch-up. The placeholder file defines nothing.
local read = { problems = {}, catchups = {} }

local function isList(v)
  if type(v) ~= "table" then return false end
  local count = 0
  for _ in pairs(v) do count = count + 1 end
  for i = 1, count do
    if v[i] == nil then return false end
  end
  return true
end

-- An integer as spec 7.3 rule 2 allows: whole and within ±(2^53 - 1), so not infinite.
local function isInteger(v)
  return type(v) == "number" and v == math.floor(v) and math.abs(v) <= 9007199254740991
end

-- Why the file as a whole can't be used, or nil.
local function fileProblem(inbox)
  if type(inbox) ~= "table" then return "isn't an inbox" end
  if inbox.formatVersion ~= 1 then return "has a format this add-on doesn't read; update the add-on" end
  if not isInteger(inbox.written) then return "has no time it was written" end
  if not isList(inbox.raids) then return "has no list of raids" end
end

-- Reads the inbox global. A missing inbox changes nothing; a file that fails as a whole loads
-- nothing and keeps the inbox raids as they were. An entry that fails is skipped and reported.
-- Runs whatever the selection is: loading raids records, shows and sends nothing.
function Inbox.Read(inbox)
  read = { problems = {}, catchups = {} }
  if inbox == nil then return end
  local problem = fileProblem(inbox)
  if problem then
    read.problems[1] = "The helper's file " .. problem .. ", so no raids were loaded from it."
    return
  end
  local snapshots, catchups, seen = {}, {}, {}
  for i, entry in ipairs(inbox.raids) do
    local snapshot, err
    if type(entry) ~= "table" then
      err = "it isn't a raid."
    else
      snapshot, err = ns.Snapshot.Validate(entry.snapshot, ns.version)
      if snapshot and seen[snapshot.raid] then snapshot, err = nil, "the raid is listed twice." end
    end
    if snapshot then
      seen[snapshot.raid] = true
      snapshots[#snapshots + 1] = snapshot
      if type(entry.catchup) == "table" then catchups[snapshot.raid] = entry.catchup end
    else
      -- The validator's wording is for pasted text; reword it for the helper's file.
      err = err:gsub("^Th[ei]s? reserves text", "it"):gsub(", then paste it again%.", ".")
        :gsub(" Copy it again from the site%.$", "")
      read.problems[#read.problems + 1] =
        string.format("Raid %d in the helper's file wasn't loaded: %s", i, err)
    end
  end
  read.present, read.readAt, read.catchups = true, time(), catchups
  local _, left = ns.Raids.ReplaceInbox(snapshots)
  for _, raidId in ipairs(left) do
    local notice = ns.Selection.RaidGone(raidId)
    if notice then read.problems[#read.problems + 1] = notice end
  end
end

-- True when this session read a valid inbox: the helper wrote it (#64's chat log).
function Inbox.HelperPresent()
  return read.present == true
end

-- A loaded inbox raid's catch-up (spec 3.4) as the helper wrote it, unchecked, or nil (#64).
function Inbox.Catchup(raidId)
  return read.catchups[raidId]
end

-- For the status read (Raids.Status): present, readAt (when this session read a valid inbox,
-- or nil) and the problems the read reported.
function Inbox.Status()
  return { present = Inbox.HelperPresent(), readAt = read.readAt, problems = read.problems }
end

ns.On("ADDON_LOADED", function(name)
  if name ~= ADDON_NAME then return end
  Inbox.Read(BureaucracyLootInbox)
  for _, problem in ipairs(read.problems) do ns.Print(problem) end
end)
