-- Popup: the loot pop-up's content model (#10). Build reads the open loot window, the loaded
-- raid and the group, and returns what the pop-up shows; nothing is drawn (the frame is #77).
-- Only the loot master gets a model (design Q3), and none on a run that is not a guild run.
-- Give is the officer's click on a Give button (#38): it hands out, records and announces.
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
local FIGHT_NOTICE = "Boss fight in progress. The game locks chat for add-ons, so awards wait until it ends."
local FIGHT_TOOLTIP = "Chat is locked until the fight ends"
local ANNOUNCED = "Announced in raid chat. Waiting for the game to confirm (a few seconds)."
local NOT_ANNOUNCED = "Not announced in raid chat: the line couldn't be posted. Waiting for the game to"
  .. " confirm (a few seconds)."
-- The game's limits that lock chat: on during a boss fight only (beta, #3). Its Combat limit (every
-- fight) and Map limit (the whole time in an instance) leave chat alone.
local CHAT_LIMITS = { "Encounter", "Chat" }
local UNKNOWN_BOSS_NOTICE = "These items drop from more than one boss. Pick the boss before awarding."
local NO_RESERVES_NOTICE = "No reserves loaded, so every item is an open roll."

local bare = ns.Rules.Bare
local chosenBoss -- the boss row id the officer picked for this loot window

ns.On("LOOT_CLOSED", function() chosenBoss = nil end)

-- Whether the game locks chat for add-ons now (a boss fight). A call that fails counts as no lock.
function Popup.ChatLocked()
  if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
    local ok, on = pcall(C_ChatInfo.InChatMessagingLockdown)
    if ok and on then return true end
  end
  local active = C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive
  local types = Enum and Enum.AddOnRestrictionType
  if not (active and types) then return false end
  for _, name in ipairs(CHAT_LIMITS) do
    if types[name] ~= nil then
      local ok, on = pcall(active, types[name])
      if ok and on then return true end
    end
  end
  return false
end

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

-- One row. earlier is the list of awards assumed for earlier copies of the item. pendingKey is the
-- award of the row's own hand-out, still waiting for the game: it doesn't count as received yet.
local function resolveRow(it, ctx, earlier, copyNote, pendingKey)
  local awards = {}
  for _, a in ipairs(ctx.awards) do
    if not (pendingKey and a.key == pendingKey) then awards[#awards + 1] = a end
  end
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
    row.winner, row.user, row.action = winner.char, winner.user, "give"
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

-- The buttons of a row, once the boss is known: Give and D/B need a boss picked. In a boss fight
-- the Give and roll buttons wait, with a tooltip saying why. A row being handed out has none.
local function addButtons(row, boss, locked)
  if row.handout then
    row.buttons = {}
    return
  end
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
  if locked then primary.enabled, primary.tooltip = false, FIGHT_TOOLTIP end
  local pick = ns.db.dbPick -- chosen by #39
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
-- selected, killed } } }), notice (no reserves), fight (the boss fight note, while chat is locked),
-- syncLink, rows (every item of every loot-window page; each: slot, item, link, copy, mode, label,
-- contenders, winner, user, skipped, skippedText, note, text, action, unavailable, handout (while
-- the game confirms a hand-out: { text, note }), buttons (each: text, action, enabled, tooltip)),
-- count, foot, recheck.
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
  local locked = Popup.ChatLocked()
  local handouts = {}
  for _, a in ipairs(ns.Tracking.Pending()) do
    if a.status == "pending" and not a.windowClosed then handouts[a.slot] = a end
  end
  local total, seen, earlier, copyNotes = {}, {}, {}, {}
  for _, it in ipairs(items) do total[it.item] = (total[it.item] or 0) + 1 end
  local model = { boss = boss, rows = {}, count = #items, foot = footLine(raidId, snapshot) }
  for _, it in ipairs(items) do
    seen[it.item] = (seen[it.item] or 0) + 1
    earlier[it.item] = earlier[it.item] or {}
    local handout = handouts[it.slot]
    local row = resolveRow(it, ctx, earlier[it.item], copyNotes[it.item], handout and handout.awardKey)
    if total[it.item] > 1 then
      row.copy = string.format("Copy %d of %d", seen[it.item], total[it.item])
      if row.action == "give" then
        copyNotes[it.item] = string.format("Copy %d goes to the %s", seen[it.item], modeWords(row.mode))
      end
    end
    if handout then
      row.handout = { text = "Handing out to " .. handout.winner .. "…",
        note = handout.announced and ANNOUNCED or NOT_ANNOUNCED }
    end
    addButtons(row, boss, locked)
    model.recheck = model.recheck or row.recheck
    model.rows[#model.rows + 1] = row
  end
  model.title = "Loot" .. (boss.name and (" · " .. boss.name) or "")
  if not snapshot then
    model.notice, model.syncLink = NO_RESERVES_NOTICE, "Sync"
  end
  if locked then model.fight = FIGHT_NOTICE end
  return model
end

-- The officer clicked a row's Give button: hands the item to the winner, found by name among
-- this corpse's candidates (their order changes per corpse), records the award as announced and
-- posts its line in raid chat. A line that can't be built is not posted, and the officer is
-- told; the hand-out and the award stand. Returns the hand-out (Tracking's attempt, with
-- awardKey and announced), or nil and why: "fight" (chat is locked), "not ready" (no Give
-- enabled for the slot), "not a candidate" or Tracking.Give's reasons.
function Popup.Give(slot)
  if Popup.ChatLocked() then return nil, "fight" end
  local model = Popup.Build()
  local row
  for _, r in ipairs(model and model.rows or {}) do
    if r.slot == slot then row = r end
  end
  if not (row and row.action == "give" and row.buttons[1] and row.buttons[1].enabled) then
    return nil, "not ready"
  end
  local index
  for i = 1, MAX_CANDIDATES do
    local name = GetMasterLootCandidate(slot, i)
    if not name then break end
    if bare(name) == bare(row.winner) then
      index = i
      break
    end
  end
  if not index then return nil, "not a candidate" end
  local attempt, reason = ns.Tracking.Give(slot, index)
  if not attempt then return nil, reason end
  local method = row.mode == "hr" and "HR" or "SR"
  local op, why = ns.Records.Award({ boss = model.boss.id, item = row.item, char = row.winner,
    user = row.user, method = method })
  local line, problem
  if op then
    attempt.awardKey = op.id
    local snapshot = ns.Raids.Get(ns.Selection.Status().activeRaid)
    line, problem = ns.OpText.BuildLine("award", { raid = snapshot.code, key = op.id, item = row.item,
      link = row.link, boss = model.boss.id, method = method, winner = row.winner, practice = op.practice })
  else
    problem = "the award wasn't saved (" .. tostring(why) .. ")"
  end
  if line then
    C_ChatInfo.SendChatMessage(line, IsInRaid() and "RAID" or "PARTY")
    attempt.announced = true
  else
    ns.Log("Award line for " .. row.link .. " not posted: " .. problem)
    ns.Print(row.link .. " is being handed to " .. row.winner .. ", but its raid chat line couldn't be"
      .. " posted. Type /bf log for why.")
  end
  return attempt
end

-- Once the game confirms a hand-out made here, its award is confirmed. Not confirmed is #12's.
ns.Tracking.On("confirmed", function(attempt)
  if not attempt.awardKey then return end
  local ok, why = ns.Records.Confirm(attempt.awardKey)
  if not ok then ns.Log("Confirming the award " .. attempt.awardKey .. " failed: " .. tostring(why)) end
end)

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
