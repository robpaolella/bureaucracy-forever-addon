-- Popup: the loot pop-up's content model (#10). Build reads the open loot window, the loaded
-- raid and the group, and returns what the pop-up shows; nothing is drawn (the frame is #77).
-- Only the loot master gets a model (design Q3), and none on a run that is not a guild run.
-- Give is the officer's click on a Give button (#38): it hands out, records and announces.
-- A hand-out the game doesn't confirm is recorded as not confirmed, and the officer resolves it
-- with TryAgain, GiveElse (from GiveElseList) or NotHandedOut (#12). Build shows the row of such a
-- hand-out as not confirmed, with those three choices (#95).
-- GiveDB is the D/B button (#39): it gives to the raid's remembered disenchanter or bank character.
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
local OPEN_WINDOW = "Open the loot window to hand it out."
-- The game's limits that lock chat: on during a boss fight only (beta, #3). Its Combat limit (every
-- fight) and Map limit (the whole time in an instance) leave chat alone.
local CHAT_LIMITS = { "Encounter", "Chat" }
local UNKNOWN_BOSS_NOTICE = "These items drop from more than one boss. Pick the boss before awarding."
local NO_RESERVES_NOTICE = "No reserves loaded, so every item is an open roll."
local DB_TITLE = "Disenchant/bank: give to"
local DB_CHOOSE_TIP = "Disenchant/bank: choose the character to give to."
local NC_HINT = "Try again posts nothing. Give to someone else posts one correction line, and Not handed"
  .. " out posts an undo line. If you close this, it waits in the Awards tab as \"not confirmed\"."
local NC_FIGHT_TOOLTIP = "Posts a line, so it waits until the boss fight ends"
-- What the row says when TryAgain, GiveElse or NotHandedOut refuses, by their reasons.
local REFUSALS = {
  fight = "Chat is locked in the boss fight. Try again works now; the other two wait until it ends.",
  window = "The loot window is closed. Open it to hand the item out.",
  changed = "The item isn't in the loot window now.",
  ["not a candidate"] = "The game won't let them receive it now (usually: not nearby when the boss died).",
  ["not a contender"] = "They aren't one of the people who reserved it.",
  ["not in raid"] = "They aren't in the raid.",
  ["cannot receive"] = "The game won't let them receive it now (usually: not nearby when the boss died).",
  ["no pick"] = "No disenchant/bank character is chosen for this raid. Choose one with D/B first.",
  ["not loot master"] = "Only the loot master can hand items out.",
  ["not unconfirmed"] = "This award is already settled.",
  ["handing out"] = "A hand-out of it is still waiting for the game.",
  unknown = "The game can't name them yet. Try again in a moment.",
  grey = "Grey items can only go to you.",
  empty = "That item is gone from the loot window.",
}

local bare = ns.Rules.Bare
local chosenBoss -- the boss row id the officer picked for this loot window
local sessionPick -- the D/B pick while no raid is loaded: kept until the game closes, never saved
local dbNotes = {} -- per slot, why the last D/B click handed nothing out
local refusals = {} -- per award key, why the last not-confirmed choice was refused

ns.On("LOOT_CLOSED", function() chosenBoss, dbNotes, refusals = nil, {}, {} end)

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
-- the Give and roll buttons wait, with a tooltip saying why. A row being handed out, or not
-- confirmed, has none (a not confirmed row's choices are in row.notConfirmed).
local function addButtons(row, boss, locked)
  if row.handout or row.notConfirmed then
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
  local pick = Popup.DBPick()
  local db = { text = "D/B: " .. (pick and pick:match("^%S+") or "choose") .. " ▾", action = "db",
    pick = pick, enabled = boss.resolved and not locked }
  if locked then
    db.tooltip = FIGHT_TOOLTIP
  elseif pick then
    db.tooltip = "Disenchant/bank: give to " .. pick .. ". Right-click or Shift-click to choose someone else."
  else
    db.tooltip = DB_CHOOSE_TIP
  end
  row.buttons = { primary, db }
end

-- The D/B list: the group's members by name, the pick ticked. members: { { name, selected } }.
local function dbMenu(raidId)
  local pick, names, members = Popup.DBPick(), roster(), {}
  table.sort(names, function(a, b) return bare(a):lower() < bare(b):lower() end)
  for i, name in ipairs(names) do
    members[i] = { name = name, selected = pick ~= nil and bare(name) == bare(pick) }
  end
  return { title = DB_TITLE, members = members,
    note = raidId and "Remembered for this raid." or "Remembered until you close the game." }
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

-- The row's not confirmed state: the hand-out the game gave up on (its award still waits as not
-- confirmed) and the officer's three choices. Buttons that post a line wait in a boss fight; Try
-- again posts none. list is Give to someone else's list, from GiveElseList.
local function notConfirmed(attempt, locked)
  local key = attempt.awardKey
  local wait = locked and NC_FIGHT_TOOLTIP or nil
  local list = { title = "Give " .. attempt.link .. " to someone else", people = {}, back = "Back" }
  local award = ns.Records.Get(key)
  for _, c in ipairs(Popup.GiveElseList(key) or {}) do
    local hard = c.method == "HR"
    list.people[#list.people + 1] = { char = c.char, method = hard and LABELS["hr-single"] or LABELS.sr,
      kind = hard and "hr" or "sr", available = c.available,
      reason = c.reason == "cannot receive" and "can't receive it" or c.reason,
      enabled = c.available and not locked, tooltip = c.available and wait or nil }
  end
  if #list.people == 0 then list.empty = "No one else reserved it." end
  list.hint = "Posts one correction line: Correction: " .. attempt.link .. " → their name, not "
    .. (award.char or "disenchant/bank") .. "."
  return { key = key,
    text = "The game didn't confirm that " .. attempt.winner .. " got it. They may be too far away, or"
      .. " their bags are full.",
    hint = NC_HINT, refusal = refusals[key], list = list,
    buttons = {
      { text = "Try again", action = "tryagain", enabled = true },
      { text = "Give to someone else", action = "giveelse", enabled = not locked, tooltip = wait },
      { text = "Not handed out", action = "nothandedout", enabled = not locked, tooltip = wait },
    } }
end

-- The attempt of each slot whose hand-out the game didn't confirm and whose award still waits
-- as not confirmed (newest first wins), by slot.
local function unconfirmedBySlot()
  local found = {}
  for _, a in ipairs(ns.Tracking.Pending()) do
    local award = a.status == "unconfirmed" and a.awardKey and ns.Records.Get(a.awardKey)
    if award and award.state == "not-confirmed" and not award.voided then found[a.slot] = a end
  end
  return found
end

-- The model for the open loot window, or nil and why: "not loot master", "not a guild run" or
-- "no items". Fields: title, boss ({ name, id, resolved, notice, menuTitle, menu = { { id, name,
-- selected, killed } } }), notice (no reserves), fight (the boss fight note, while chat is locked),
-- syncLink, rows (every item of every loot-window page; each: slot, item, link, copy, mode, label,
-- contenders, winner, user, skipped, skippedText, note, text, action, unavailable, dbNote (why the
-- last D/B click handed nothing out), handout (while the game confirms a hand-out: { text, note }),
-- notConfirmed (once the game gave up on its hand-out: { key, text, hint, refusal (why the last
-- choice was refused), buttons (Try again, Give to someone else, Not handed out: text, action,
-- enabled, tooltip), list = { title, people = { { char, method, kind, available, reason, enabled,
-- tooltip } }, empty, hint, back } }), buttons (each: text, action, enabled, tooltip; the D/B
-- button's also pick)), dbMenu ({ title,
-- members = { { name, selected } }, note }), count, foot, recheck.
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
  local unconfirmed = unconfirmedBySlot()
  local total, seen, earlier, copyNotes = {}, {}, {}, {}
  for _, it in ipairs(items) do total[it.item] = (total[it.item] or 0) + 1 end
  local model = { boss = boss, rows = {}, count = #items, foot = footLine(raidId, snapshot) }
  for _, it in ipairs(items) do
    seen[it.item] = (seen[it.item] or 0) + 1
    earlier[it.item] = earlier[it.item] or {}
    local handout = handouts[it.slot]
    local gaveUp = unconfirmed[it.slot]
    if gaveUp and gaveUp.link and tonumber(gaveUp.link:match("item:(%d+)")) ~= it.item then gaveUp = nil end
    local mine = handout or gaveUp
    local row = resolveRow(it, ctx, earlier[it.item], copyNotes[it.item], mine and mine.awardKey)
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
    if gaveUp and not handout then row.notConfirmed = notConfirmed(gaveUp, locked) end
    row.dbNote = dbNotes[it.slot]
    addButtons(row, boss, locked)
    model.recheck = model.recheck or row.recheck
    model.rows[#model.rows + 1] = row
  end
  model.title = "Loot" .. (boss.name and (" · " .. boss.name) or "")
  if not snapshot then
    model.notice, model.syncLink = NO_RESERVES_NOTICE, "Sync"
  end
  if locked then model.fight = FIGHT_NOTICE end
  model.dbMenu = dbMenu(raidId)
  return model
end

-- The remembered disenchanter or bank character (D/B) of raidId (by default the selected raid), or
-- nil. Saved per raid in
-- BureaucracyForeverDB.dbPick[raidId]; with no raid loaded it lasts until the game closes.
function Popup.DBPick(raidId)
  raidId = raidId or ns.Selection.Status().activeRaid
  if not raidId then return sessionPick end
  local picks = ns.db.dbPick
  return type(picks) == "table" and picks[raidId] or nil
end

-- The officer chose a name in the D/B list: it is remembered for the raid, and nothing is handed
-- out. Returns true, or nil and "not in raid".
function Popup.SetDBPick(name)
  local found
  for _, member in ipairs(roster()) do
    if name and bare(member) == bare(name) then found = member end
  end
  if not found then return nil, "not in raid" end
  local raidId = ns.Selection.Status().activeRaid
  if raidId then
    if type(ns.db.dbPick) ~= "table" then ns.db.dbPick = {} end
    ns.db.dbPick[raidId] = found
  else
    sessionPick = found
  end
  dbNotes = {}
  return true
end

-- The officer's choice on a not confirmed row was refused for `why` (nil: it worked): the row
-- says so until the next choice or the loot window closes.
function Popup.Refused(key, why)
  refusals[key] = why and (REFUSALS[why] or ("It couldn't be done (" .. tostring(why) .. ").")) or nil
end

-- Posts the operation's chat line, built from data, in raid (or party) chat. With no data (the
-- record wasn't saved; why says why) or a line that can't be built, nothing is posted: the log
-- says why under `what`, and the officer is told `told`. Returns true once posted.
local function post(operation, data, why, what, told)
  local line, problem
  if data then
    line, problem = ns.OpText.BuildLine(operation, data)
  else
    problem = "the record wasn't saved (" .. tostring(why) .. ")"
  end
  if line then
    C_ChatInfo.SendChatMessage(line, IsInRaid() and "RAID" or "PARTY")
    return true
  end
  ns.Log(what .. " not posted: " .. problem)
  ns.Print(told .. " Type /bf log for why.")
end

-- The officer clicked a row's Give button: hands the item to the winner, found by name among
-- this corpse's candidates (their order changes per corpse), records the award as announced and
-- posts its line in raid chat. A line that can't be built is not posted, and the officer is
-- told; the hand-out and the award stand. item and winner are what the clicked button showed: if
-- the row now names another item or winner, nothing happens. Returns the hand-out (Tracking's
-- attempt, with awardKey and announced), or nil and why: "fight" (chat is locked), "not ready"
-- (no Give enabled for the slot), "changed", "not a candidate" or Tracking.Give's reasons.
function Popup.Give(slot, item, winner)
  if Popup.ChatLocked() then return nil, "fight" end
  local model = Popup.Build()
  local row
  for _, r in ipairs(model and model.rows or {}) do
    if r.slot == slot then row = r end
  end
  if not (row and row.action == "give" and row.buttons[1] and row.buttons[1].enabled) then
    return nil, "not ready"
  end
  if row.item ~= item or row.winner ~= winner then return nil, "changed" end
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
  local data
  if op then
    attempt.awardKey = op.id
    local snapshot = ns.Raids.Get(ns.Selection.Status().activeRaid)
    data = { raid = snapshot.code, key = op.id, item = row.item, link = row.link, boss = model.boss.id,
      method = method, winner = row.winner, practice = op.practice }
  end
  attempt.announced = post("award", data, why, "Award line for " .. row.link,
    row.link .. " is being handed to " .. row.winner .. ", but its raid chat line couldn't be posted.")
  return attempt
end

-- The newest hand-out of the award still followed (waiting, or given up on), or nil.
local function attemptOf(key)
  local found
  for _, a in ipairs(ns.Tracking.Pending()) do
    if a.awardKey == key then found = a end
  end
  return found
end

local function itemOf(link) return link and tonumber(link:match("item:(%d+)")) end

-- The award, if it is not confirmed and not voided: the only kind the three choices act on. Or
-- nil and why: "not unconfirmed", or "handing out" while a hand-out of it waits for the game.
local function unconfirmedAward(key)
  local award = ns.Records.Get(key)
  if not (award and award.state == "not-confirmed" and not award.voided) then
    return nil, "not unconfirmed"
  end
  local attempt = attemptOf(key)
  if attempt and attempt.status == "pending" then return nil, "handing out" end
  return award
end

-- The loot window slot holding the award's item: its last hand-out's slot first, else any slot
-- with that item (the same corpse can list its items in another order); or nil.
local function findSlot(key, item)
  local attempt = attemptOf(key)
  local slots = attempt and { attempt.slot } or {}
  for slot = 1, GetNumLootItems() do slots[#slots + 1] = slot end
  for _, slot in ipairs(slots) do
    if itemOf(GetLootSlotLink(slot)) == item then return slot end
  end
end

-- findSlot, or nil and why: "window" (no loot window open) or "changed" (the item isn't in it).
-- The officer is told either way.
local function lootSlot(key, item)
  local slot = findSlot(key, item)
  if slot then return slot end
  ns.Print(OPEN_WINDOW)
  return nil, GetNumLootItems() == 0 and "window" or "changed"
end

-- The index of the candidate with this name for the slot, or nil.
local function candidateIndex(slot, char)
  for i = 1, MAX_CANDIDATES do
    local name = GetMasterLootCandidate(slot, i)
    if not name then return end
    if bare(name) == bare(char) then return i end
  end
end

-- The officer clicked a row's D/B button: hands the item to the raid's pick, found by name among
-- this corpse's candidates, records the award as Disenchant/bank with no winner (spec 9.2) and
-- posts its line. A line that can't be built is not posted, and the officer is told; the hand-out
-- and the award stand. item and pick are what the clicked button showed. A pick who can't receive
-- the item hands nothing out, and the row says why. Returns the hand-out (Tracking's attempt, with
-- awardKey and announced), or nil and why: "fight", "not ready" (no D/B enabled for the slot),
-- "no pick", "changed", "not a candidate" or Tracking.Give's reasons.
function Popup.GiveDB(slot, item, pick)
  if Popup.ChatLocked() then return nil, "fight" end
  local model = Popup.Build()
  local row
  for _, r in ipairs(model and model.rows or {}) do
    if r.slot == slot then row = r end
  end
  local button = row and row.buttons[2]
  if not (button and button.enabled) then return nil, "not ready" end
  if not button.pick then return nil, "no pick" end
  if row.item ~= item or button.pick ~= pick then return nil, "changed" end
  local index = candidateIndex(slot, pick)
  if not index then
    local inRaid
    for _, member in ipairs(roster()) do inRaid = inRaid or bare(member) == bare(pick) end
    dbNotes[slot] = inRaid and ("The game won't let " .. pick .. " receive this item (usually: not"
      .. " nearby when the boss died). Right-click D/B to choose someone else.")
      or (pick .. " isn't in the raid. Right-click D/B to choose someone else.")
    return nil, "not a candidate"
  end
  local attempt, reason = ns.Tracking.Give(slot, index)
  if not attempt then return nil, reason end
  dbNotes[slot] = nil
  ns.Rolls.End(slot, item)
  local op, why = ns.Records.Award({ boss = model.boss.id, item = row.item, method = "DISENCHANT_BANK" })
  local data
  if op then
    attempt.awardKey = op.id
    local snapshot = ns.Raids.Get(ns.Selection.Status().activeRaid)
    data = { raid = snapshot and snapshot.code, key = op.id, item = row.item, link = row.link,
      boss = model.boss.id, method = "DISENCHANT_BANK", practice = op.practice }
  end
  attempt.announced = post("award", data, why, "Award line for " .. row.link,
    row.link .. " is being handed to " .. pick .. " to disenchant or bank, but its raid chat line"
      .. " couldn't be posted.")
  return attempt
end

-- The checks every hand-out choice shares. Returns the award and the slot, or nil and why.
local function handoutCheck(key)
  local award, why = unconfirmedAward(key)
  if not award then return nil, why end
  if not isLootMaster() then return nil, "not loot master" end
  local slot, reason = lootSlot(key, award.item)
  if not slot then return nil, reason end
  return award, slot
end

-- Try again: hands the award's item to the same winner once more, with no new announcement and
-- no new record; the award is confirmed once the game confirms this hand-out. It needs no free
-- chat, so it works in a boss fight. key is the award's key. Returns the new hand-out (Tracking's
-- attempt, with awardKey and announced as the first hand-out had it), or nil and why: "not
-- unconfirmed" (no such award, or it isn't waiting as not confirmed), "handing out" (a hand-out
-- of it still waits for the game: every choice waits for that), "not loot master",
-- "window" (the loot window is closed), "changed" (the item isn't in the loot window), "not a
-- candidate" (the game won't let the winner receive it now) or Tracking.Give's reasons. A refusal
-- changes nothing and hands nothing out. A Disenchant/bank award names no winner: it goes to whom
-- its last hand-out went, or after a /reload to its own raid's D/B pick ("no pick" when none).
function Popup.TryAgain(key)
  local award, slot = handoutCheck(key)
  if not award then return nil, slot end
  local before = attemptOf(key)
  local recipient = award.char or (before and before.winner) or Popup.DBPick(award.raid)
  if not recipient then return nil, "no pick" end
  local index = candidateIndex(slot, recipient)
  if not index then return nil, "not a candidate" end
  local attempt, reason = ns.Tracking.Give(slot, index)
  if not attempt then return nil, reason end
  attempt.awardKey, attempt.announced = key, before and before.announced
  return attempt
end

-- The people the award's item could go to instead: the item's other reserve holders, hard
-- reserves first, each with the method the new award carries. Trials, holders who already have
-- it and the site's blocked holders are left out. key is the award's key. Returns a list of
-- { char, user, method ("HR" or "SR"), available, reason (when not available: "not in raid",
-- or "cannot receive" when the open loot window's candidates leave them out) }, or nil and "not
-- unconfirmed" or "handing out".
function Popup.GiveElseList(key)
  local award, why = unconfirmedAward(key)
  if not award then return nil, why end
  local snapshot = ns.Raids.Get(award.raid)
  local reserves = snapshot and snapshot.reserves or {}
  local holders = reserves[award.item] or reserves[tostring(award.item)] or {}
  local awards = {}
  for _, a in ipairs(snapshot and snapshot.awards or {}) do awards[#awards + 1] = a end
  for _, a in ipairs(ns.Raids.Awards(award.raid)) do
    if a.key ~= key then awards[#awards + 1] = a end
  end
  -- A name not loaded yet ("Unknown") can't be matched, so then nobody counts as unable to receive.
  local slot = findSlot(key, award.item)
  local cands, unknown
  if slot then cands, unknown = candidates(slot) end
  if unknown then cands = nil end
  local list = {}
  for _, kind in ipairs({ "HR", "SR" }) do
    local same = {}
    for _, h in ipairs(holders) do
      if h.kind == kind and h.user ~= award.user then same[#same + 1] = h end
    end
    local resolved = ns.Rules.Resolve({ item = award.item, reserves = { [award.item] = same },
      awards = awards, roster = roster(), candidates = cands })
    local status = {}
    for _, h in ipairs(resolved.contenders) do status[h.user] = { available = true } end
    for _, s in ipairs(resolved.skipped) do
      if s.reason == ns.Rules.NOT_IN_RAID or s.reason == ns.Rules.CANNOT_RECEIVE then
        status[s.user] = { available = false, reason = s.reason }
      end
    end
    for _, h in ipairs(same) do
      local st = status[h.user]
      if st then
        list[#list + 1] = { char = h.char, user = h.user, method = kind, available = st.available,
          reason = st.reason }
      end
    end
  end
  return list
end

-- Give to someone else: hands the award's item to char, one of GiveElseList's available people,
-- records the replacement (the old award voided, a new one with the method char holds) and posts
-- the one correction line. A line that can't be built is not posted, and the officer is told;
-- the hand-out and the records stand. key is the award's key. Returns the new hand-out (with
-- awardKey, the new award's key, and announced), or nil and why: "fight" (chat is locked),
-- "not a contender" (not on the list), "not in raid", "cannot receive" (greyed on the list), or
-- TryAgain's reasons. A refusal changes nothing, hands nothing out and posts nothing.
function Popup.GiveElse(key, char)
  if Popup.ChatLocked() then return nil, "fight" end
  local award, slot = handoutCheck(key)
  if not award then return nil, slot end
  local pick
  for _, c in ipairs(Popup.GiveElseList(key)) do
    if c.char == char then pick = c end
  end
  if not pick then return nil, "not a contender" end
  if not pick.available then return nil, pick.reason end
  local index = candidateIndex(slot, char)
  if not index then return nil, "not a candidate" end
  local attempt, reason = ns.Tracking.Give(slot, index)
  if not attempt then return nil, reason end
  local link = GetLootSlotLink(slot)
  local op, why = ns.Records.Replace(key, { boss = award.boss, item = award.item, char = pick.char,
    user = pick.user, method = pick.method })
  local data
  if op then
    attempt.awardKey = op.award.id
    local snapshot = ns.Raids.Get(award.raid)
    data = { raid = snapshot and snapshot.code, id = op.id, key = key, newKey = op.award.id,
      item = award.item, link = link, boss = award.boss, method = pick.method, winner = pick.char,
      oldWinner = award.char, practice = op.practice }
  end
  attempt.announced = post("correction", data, why, "Correction line for " .. link,
    link .. " is being handed to " .. pick.char .. " instead of " .. (award.char or "disenchant/bank")
      .. ", but its raid chat line couldn't be posted.")
  return attempt
end

-- Not handed out: voids the award and posts its undo line. It needs no loot window. A line that
-- can't be built is not posted, and the officer is told; the void stands. key is the award's key.
-- Returns the void operation, or nil and why: "fight" (chat is locked), "not unconfirmed",
-- "handing out" or Records.Void's reasons. A refusal changes nothing and posts nothing.
function Popup.NotHandedOut(key)
  if Popup.ChatLocked() then return nil, "fight" end
  local award, refused = unconfirmedAward(key)
  if not award then return nil, refused end
  local op, why = ns.Records.Void(key, { reason = "not handed out" })
  if not op then return nil, why end
  local attempt = attemptOf(key)
  local link = attempt and attempt.link or select(2, GetItemInfo(award.item)) or ("item " .. award.item)
  local snapshot = ns.Raids.Get(award.raid)
  post("undo", { raid = snapshot and snapshot.code, id = op.id, key = key, link = link,
    winner = award.char, practice = op.practice }, nil, "Undo line for " .. link,
    link .. (award.char and (" is no longer awarded to " .. award.char) or " is no longer going to"
      .. " disenchant/bank") .. ", but its raid chat line couldn't be posted.")
  return op
end

-- Once the game confirms a hand-out made here, its award is confirmed, even after it was given
-- up on (a late confirmation). One for an award changed meanwhile is told to the officer.
local function confirmed(attempt)
  if not attempt.awardKey then return end
  local award = ns.Records.Get(attempt.awardKey)
  if award and award.voided then
    ns.Log("The game confirmed " .. attempt.link .. " to " .. attempt.winner
      .. " after its award was changed")
    ns.Print("The game says " .. attempt.winner .. " got " .. attempt.link .. " after all, but that award"
      .. " was already changed. Check the Awards tab.")
    return
  end
  local ok, why = ns.Records.Confirm(attempt.awardKey)
  if not ok then ns.Log("Confirming the award " .. attempt.awardKey .. " failed: " .. tostring(why)) end
end
ns.Tracking.On("confirmed", confirmed)
ns.Tracking.On("late", confirmed)

-- A hand-out the game didn't confirm in time: its award is recorded as not confirmed.
ns.Tracking.On("unconfirmed", function(attempt)
  local award = attempt.awardKey and ns.Records.Get(attempt.awardKey)
  if not award or award.voided then return end
  local ok, why = ns.Records.NotConfirmed(attempt.awardKey)
  if ok then
    ns.Log("The game didn't confirm " .. attempt.link .. " to " .. attempt.winner)
  else
    ns.Log("Recording " .. attempt.awardKey .. " as not confirmed failed: " .. tostring(why))
  end
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
