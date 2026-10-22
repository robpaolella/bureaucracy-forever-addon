-- Inbox: the desktop helper's file (ADDON-SPEC.md 7.3), read once at login or /reload, after every
-- file has loaded (the helper's Inbox.lua is last in the .toc). Each raid's snapshot is checked
-- by Snapshot.Validate and loaded as an inbox copy (Raids.ReplaceInbox). The file is data the game
-- has already run; the add-on checks its shape before using any of it.
local ADDON_NAME, ns = ...

local Inbox = {}
ns.Inbox = Inbox

-- This session's read: whether a valid file was read (the helper is present), when, the
-- problems found, each loaded raid's catch-up, and the loaded entries in file order (each
-- { snapshot, catchup }) for the merge. The placeholder file defines nothing.
local read = { problems = {}, catchups = {}, entries = {} }

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
  read = { problems = {}, catchups = {}, entries = {} }
  if inbox == nil then return end
  local problem = fileProblem(inbox)
  if problem then
    read.problems[1] = "The helper's file " .. problem .. ", so no raids were loaded from it."
    return
  end
  local snapshots, catchups, entries, seen = {}, {}, {}, {}
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
      catchups[snapshot.raid] = entry.catchup
      entries[#entries + 1] = { snapshot = snapshot, catchup = entry.catchup }
    else
      -- The validator's wording is for pasted text; reword it for the helper's file.
      err = err:gsub("^Th[ei]s? reserves text", "it"):gsub(", then paste it again%.", ".")
        :gsub(" Copy it again from the site%.$", "")
      read.problems[#read.problems + 1] =
        string.format("Raid %d in the helper's file wasn't loaded: %s", i, err)
    end
  end
  read.present, read.readAt, read.catchups, read.entries = true, time(), catchups, entries
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

local function isString(v) return type(v) == "string" and #v <= ns.Snapshot.MAX_STRING end
local function isBoolean(v) return type(v) == "boolean" end
local function isRoll(v) return isInteger(v) and v >= 1 and v <= 100 end
local function oneOf(...)
  local allowed = {}
  for _, v in ipairs({ ... }) do allowed[v] = true end
  return function(v) return allowed[v] == true end
end

-- The catch-up's fields (spec 3.4): { name, check or list of fields, optional }.
local AWARD = {
  { "key", ns.Records.ValidId }, { "boss", isString }, { "item", isInteger },
  { "char", isString, true }, { "user", isString, true },
  { "method", oneOf("HR", "SR", "MAIN_SPEC", "OFF_SPEC", "OPEN_ROLL", "DISENCHANT_BANK") },
  { "roll", isRoll, true }, { "voided", isBoolean },
  { "state", oneOf("announced", "confirmed", "not-confirmed", "manual") },
  { "at", isInteger }, { "practice", isBoolean, true },
}
local CATCHUP = {
  { "formatVersion", oneOf(1) }, { "raid", isString }, { "env", oneOf("production", "staging") },
  { "generated", isInteger }, { "awards", AWARD },
  { "voids", { { "key", ns.Records.ValidId }, { "at", isInteger }, { "reason", isString, true } } },
}

-- A copy of v holding only these fields, or nil and why it fails. where prefixes the field.
local function clean(fields, v, where)
  if type(v) ~= "table" then return nil, (where == "" and "it" or where:sub(1, -3)) .. " isn't a table" end
  local out = {}
  for _, field in ipairs(fields) do
    local name, check, optional = field[1], field[2], field[3]
    local value, path = v[name], where .. name
    if value == nil then
      if not optional then return nil, path .. " is missing" end
    elseif type(check) == "table" then
      if not isList(value) then return nil, path .. " isn't a list" end
      local items = {}
      for i, item in ipairs(value) do
        local err
        items[i], err = clean(check, item, path .. " " .. i .. ", ")
        if not items[i] then return nil, err end
      end
      out[name] = items
    elseif not check(value) then
      return nil, path .. " has the wrong type"
    else
      out[name] = value
    end
  end
  -- A DISENCHANT_BANK award has no `char` (spec 4).
  if fields == AWARD and out.char == nil and out.method ~= "DISENCHANT_BANK" then
    return nil, where .. "char is missing"
  end
  return out
end

local FIELD_NAMES = { boss = "boss", item = "item", char = "character", method = "loot method" }

local function joined(words)
  if #words == 1 then return words[1] end
  return table.concat(words, ", ", 1, #words - 1) .. " and " .. words[#words]
end

-- Merges each loaded raid's catch-up into the awards (Records.Merge). A catch-up that fails its
-- checks, or names another raid or environment than its entry's snapshot, is skipped and the
-- others merge. Returns the problems, one chat line each.
function Inbox.Merge()
  local problems = {}
  for _, entry in ipairs(read.entries) do
    local snapshot = entry.snapshot
    local raid = string.format("%s (%s)", (snapshot.name:gsub("|", "||")), (snapshot.code:gsub("|", "||")))
    local catchup, err
    if entry.catchup ~= nil then catchup, err = clean(CATCHUP, entry.catchup, "") end
    if err then
      problems[#problems + 1] = string.format("The site's awards for %s weren't merged: %s.", raid, err)
    elseif catchup and (catchup.raid ~= snapshot.raid or catchup.env ~= snapshot.env) then
      problems[#problems + 1] = string.format(
        "The site's awards for %s name another raid or environment, so they were ignored.", raid)
    elseif catchup then
      local conflicts = ns.Records.Merge(catchup)
      if not conflicts then break end
      for _, conflict in ipairs(conflicts) do
        local award, names = conflict.award, {}
        for i, field in ipairs(conflict.fields) do names[i] = FIELD_NAMES[field] end
        local to = award.char and (award.char:gsub("|", "||")) or "the guild bank"
        problems[#problems + 1] = string.format(
          "The site's award %s (%s, item %d) has a different %s; the add-on kept its own.",
          award.key, to, award.item, joined(names))
      end
    end
  end
  return problems
end

-- For the status read (Raids.Status): present, readAt (when this session read a valid inbox,
-- or nil) and the problems the read reported.
function Inbox.Status()
  return { present = Inbox.HelperPresent(), readAt = read.readAt, problems = read.problems }
end

ns.On("ADDON_LOADED", function(name)
  if name ~= ADDON_NAME then return end
  Inbox.Read(BureaucracyLootInbox)
  -- Hand-outs of a raid that left the inbox, or was removed before, go with it (#143).
  ns.Raids.DropHandouts()
  for _, problem in ipairs(read.problems) do ns.Print(problem) end
  for _, problem in ipairs(Inbox.Merge()) do ns.Print(problem) end
  -- The helper reads the chat log for awards sent live. Only when it is present, so nobody
  -- else's chat is written to a file; never switched off (the game turns it off at login).
  if Inbox.HelperPresent() then LoggingChat(true) end
end)
