-- Popup: the loot pop-up's content model (#10). Pure: reads the open loot window, the loaded raid
-- and the group, and returns what the pop-up shows; nothing is drawn (the frame is #77).
-- Only the loot master gets a model (design Q3), and none on a run that is not a guild run.
-- luacheck: read globals C_PartyInfo
local _, ns = ...

local Popup = {}
ns.Popup = Popup

local MAX_CANDIDATES = 40
local REASONS = {
  ["cannot receive"] = "the game won't let them receive this item (usually: not nearby when the boss died)",
  trial = "trial: shown, doesn't roll",
}
local LABELS = {
  ["hr-single"] = "Hard reserve", ["hr-multi"] = "Hard reserve roll-off",
  sr = "Soft reserve", open = "Open roll",
}
local UNKNOWN_BOSS_NOTICE = "These items drop from more than one boss. Pick the boss before awarding."
local NO_RESERVES_NOTICE = "No reserves loaded, so every item is an open roll."

local bare = ns.Rules.Bare
local chosenBoss -- the boss row id the officer picked for this loot window

ns.On("LOOT_CLOSED", function() chosenBoss = nil end)

-- True when the player is the master looter.
local function isLootMaster()
  if not (C_PartyInfo and C_PartyInfo.GetLootMethod) then return false end
  local method, partyIndex, raidIndex = C_PartyInfo.GetLootMethod()
  if method ~= "master" and not (Enum and Enum.LootMethod and method == Enum.LootMethod.Masterlooter) then
    return false
  end
  if partyIndex == 0 then return true end
  local name = IsInRaid() and raidIndex and raidIndex > 0 and GetRaidRosterInfo(raidIndex)
  return name and bare(name) == bare(UnitName("player")) or false
end

-- The names in the group, the player included.
local function roster()
  local names = { UnitName("player") }
  if IsInRaid() then
    names = {}
    for i = 1, GetNumGroupMembers() do names[#names + 1] = (GetRaidRosterInfo(i)) end
  else
    for i = 1, GetNumGroupMembers() - 1 do names[#names + 1] = UnitName("party" .. i) end
  end
  return names
end

local function candidates(slot)
  local list, unknown = {}, false
  for i = 1, MAX_CANDIDATES do
    local name = GetMasterLootCandidate(slot, i)
    if not name then break end
    list[#list + 1] = name
    if name == "Unknown" then unknown = true end
  end
  return #list > 0 and list or nil, unknown
end

-- The loot window's items at or above the threshold: { slot, item, link, guid }.
local function lootItems()
  local items, threshold = {}, GetLootThreshold() or 0
  for slot = 1, GetNumLootItems() do
    local link = GetLootSlotLink(slot)
    local item = link and tonumber(link:match("item:(%d+)"))
    local quality = select(5, GetLootSlotInfo(slot))
    if item and quality and quality >= threshold then
      items[#items + 1] = { slot = slot, item = item, link = link, guid = (GetLootSourceInfo(slot)) }
    end
  end
  return items
end

local function killTime(raidId, bossId)
  local at = ((ns.db.attribution or {})[raidId] or { kills = {} }).kills[bossId]
  return at and date("%H:%M", at)
end

-- The boss control: the one boss every item points to, or "Trash" and the list to pick from.
local function bossControl(raidId, snapshot, items)
  if not snapshot then return { resolved = true } end
  local suggested, agreed = nil, true
  for i, it in ipairs(items) do
    local id = ns.Attribution.Suggest(it.item, it.guid)
    if i == 1 then suggested = id elseif id ~= suggested then agreed = false end
  end
  local id = chosenBoss or (agreed and suggested or nil)
  local boss = { resolved = id ~= nil, id = id, menuTitle = "Which boss dropped this?", menu = {} }
  local trashMarked = false
  for _, row in ipairs(snapshot.bosses) do
    -- Until a boss is picked the list marks "Trash", as the design draws it.
    local selected = id == row.id or (id == nil and row.trash and not trashMarked)
    trashMarked = trashMarked or (id == nil and row.trash)
    boss.menu[#boss.menu + 1] = { id = row.id, name = row.name, selected = selected,
      killed = not row.trash and killTime(raidId, row.id) or nil }
    if row.id == id then boss.name = row.name end
  end
  if not boss.resolved then
    boss.name, boss.notice = "Trash", UNKNOWN_BOSS_NOTICE
  end
  return boss
end

local function words(kind) return kind == "HR" and "hard reserve" or "soft reserve" end
local function modeWords(mode) return mode == "hr" and "hard reserve" or "soft reserve" end

-- The skipped holders with their reasons, leaving out the winners assumed for earlier copies.
local function skippedList(resolved, earlier)
  local list, assumed = {}, {}
  for _, a in ipairs(earlier) do assumed[a.user] = true end
  for _, s in ipairs(resolved.skipped) do
    if not (s.reason == ns.Rules.RECEIVED and assumed[s.user]) then
      local reason = REASONS[s.reason] or s.reason
      if s.reason == ns.Rules.RECEIVED then reason = words(s.kind) .. " " .. s.reason end
      list[#list + 1] = { name = s.char, reason = reason }
    end
  end
  return list
end

-- One row. earlier is the list of awards assumed for earlier copies of the item.
local function resolveRow(it, ctx, earlier, copyNote)
  local awards = {}
  for _, a in ipairs(ctx.awards) do awards[#awards + 1] = a end
  for _, a in ipairs(earlier) do awards[#awards + 1] = a end
  local cands, unknown = candidates(it.slot)
  local args = { item = it.item, reserves = ctx.reserves, awards = awards, roster = ctx.roster,
    candidates = cands }
  local resolved = ns.Rules.Resolve(args)
  local row = { slot = it.slot, item = it.item, link = it.link }
  if unknown then
    -- A name that hasn't loaded shows as "Unknown": nobody is skipped for it, and a lone winner
    -- not on the list waits for the name (the pop-up asks again).
    args.candidates = nil
    resolved = ns.Rules.Resolve(args)
    row.recheck = true
  end
  local mode = resolved.mode
  row.skipped = skippedList(resolved, earlier)
  row.contenders = {}
  for _, h in ipairs(resolved.contenders) do row.contenders[#row.contenders + 1] = h.char end
  if mode == "hr-single" or (mode == "sr" and #resolved.contenders == 1) then
    local winner = resolved.contenders[1]
    row.winner, row.action = winner.char, "give"
    if unknown and cands then
      local listed
      for _, name in ipairs(cands) do listed = listed or bare(name) == bare(winner.char) end
      if not listed then
        row.unavailable = winner.char
          .. "'s name hasn't loaded yet (shown as \"Unknown\"). Try again in a moment."
      end
    end
    earlier[#earlier + 1] = { item = it.item, user = winner.user }
  elseif mode == "open" then
    row.action = "openroll"
  else
    row.action = "roll"
  end
  row.mode = mode == "open" and "open" or (mode == "sr" and "sr" or "hr")
  row.label = LABELS[mode]
  if mode == "sr" and #resolved.contenders > 1 then row.label = "Soft reserve roll-off" end
  row.note = copyNote
  if mode == "open" then
    if not ctx.snapshot then
      row.note = "No reserves loaded"
    elseif #row.skipped > 0 then
      row.note = "No one else reserved it"
    elseif copyNote then
      row.note = copyNote
    elseif ctx.unlisted[it.item] then
      row.note = "Not on the raid's loot list"
    else
      row.note = "Nobody reserved it"
    end
    row.text = row.note .. " · everyone can roll"
  elseif row.action == "roll" then
    row.text = table.concat(row.contenders, ", ") .. (row.note and (" · " .. row.note) or "")
  else
    row.text = row.winner
  end
  if #row.skipped > 0 then
    local parts = {}
    for i, s in ipairs(row.skipped) do parts[i] = s.name .. " (" .. s.reason .. ")" end
    row.skippedText = "Skipped: " .. table.concat(parts, "; ")
  end
  return row
end

-- The buttons of a row, once the boss is known: Give and D/B need a boss picked.
local function addButtons(row, boss)
  local primary
  if row.action == "give" then
    primary = { text = "Give to " .. row.winner, action = "give",
      enabled = boss.resolved and not row.unavailable }
    if row.unavailable then primary.text = "Give to Unknown" end
  elseif row.action == "roll" then
    primary = { text = "Call roll (" .. #row.contenders .. ")", action = "roll", enabled = true }
  else
    primary = { text = "Call open roll", action = "openroll", enabled = true }
  end
  local pick = ns.db.dbPick -- chosen by #13
  row.buttons = { primary, { text = "D/B: " .. (pick and pick:match("^%S+") or "choose") .. " ▾",
    action = "db", enabled = boss.resolved } }
end

local function footLine(raidId, snapshot)
  if not snapshot then return "Reserves: none loaded" end
  local loaded
  for _, raid in ipairs(ns.Raids.Status()) do
    if raid.id == raidId then loaded = raid.loadedAt end
  end
  return string.format("Reserves: %s, %s · copied %s, loaded %s", snapshot.name,
    date("%a %d %b", snapshot.startsAt), date("%H:%M", snapshot.generated), date("%H:%M", loaded))
end

-- The model for the open loot window, or nil and why: "not loot master", "not a guild run" or
-- "no items". Fields: title, boss ({ name, id, resolved, notice, menuTitle, menu = { { id, name,
-- selected, killed } } }), notice (no reserves), syncLink, rows (every item of every loot-window
-- page; each: slot, item, link, copy, mode, label, contenders, winner, skipped, skippedText, note,
-- text, action, unavailable, buttons), count, foot, recheck.
function Popup.Build()
  if not isLootMaster() then return nil, "not loot master" end
  if ns.Selection.IsQuiet() then return nil, "not a guild run" end
  local items = lootItems()
  if #items == 0 then return nil, "no items" end
  local raidId = ns.Selection.Status().activeRaid
  local snapshot = ns.Raids.Get(raidId)
  local ctx = { snapshot = snapshot, awards = {}, reserves = {}, roster = roster(), unlisted = {} }
  if snapshot then
    ctx.reserves = snapshot.reserves
    for _, a in ipairs(snapshot.awards) do ctx.awards[#ctx.awards + 1] = a end
    for _, a in ipairs(ns.Raids.Awards(raidId)) do ctx.awards[#ctx.awards + 1] = a end
    for _, it in ipairs(items) do
      local _, unlisted = ns.Attribution.Suggest(it.item, it.guid)
      ctx.unlisted[it.item] = unlisted == "unlisted"
    end
  end
  local boss = bossControl(raidId, snapshot, items)
  local total, seen, earlier, copyNotes = {}, {}, {}, {}
  for _, it in ipairs(items) do total[it.item] = (total[it.item] or 0) + 1 end
  local model = { boss = boss, rows = {}, count = #items, foot = footLine(raidId, snapshot) }
  for _, it in ipairs(items) do
    seen[it.item] = (seen[it.item] or 0) + 1
    earlier[it.item] = earlier[it.item] or {}
    local row = resolveRow(it, ctx, earlier[it.item], copyNotes[it.item])
    if total[it.item] > 1 then
      row.copy = string.format("Copy %d of %d", seen[it.item], total[it.item])
      if row.action == "give" then
        copyNotes[it.item] = string.format("Copy %d goes to the %s", seen[it.item], modeWords(row.mode))
      end
    end
    addButtons(row, boss)
    model.recheck = model.recheck or row.recheck
    model.rows[#model.rows + 1] = row
  end
  model.title = "Loot" .. (boss.name and (" · " .. boss.name) or "")
  if not snapshot then
    model.notice, model.syncLink = NO_RESERVES_NOTICE, "Sync"
  end
  return model
end

-- The officer picks the boss (a boss row id of the loaded raid, "Trash" included) for this loot
-- window. Returns true, or nil and why.
function Popup.PickBoss(bossId)
  local snapshot = ns.Raids.Get(ns.Selection.Status().activeRaid)
  for _, row in ipairs(snapshot and snapshot.bosses or {}) do
    if row.id == bossId then
      chosenBoss = bossId
      return true
    end
  end
  return nil, "not a boss of this raid"
end
