-- Popup: the loot pop-up's content model (#10). Build reads the open loot window, the loaded
-- raid and the group, and returns what the pop-up shows; nothing is drawn (the frame is #77).
-- Only the loot master gets a model (design Q3), and none on a run that is not a guild run.
-- Give is the officer's click on a Give button (#38): it hands out, records and announces.
-- A hand-out the game doesn't confirm is recorded as not confirmed, and the officer resolves it
-- with TryAgain, GiveElse (from GiveElseList) or NotHandedOut (#12). Build shows the row of such a
-- hand-out as not confirmed, with those three choices (#95).
-- GiveElseDB is the give-else list's Disenchant/bank line (#96): it gives to the raid's D/B pick
-- instead. CallOpenRoll is its open roll line (#118): the row then shows that roll's list, and a give
-- from it replaces the not confirmed award.
-- Once a roll is called the row carries the roll list (#90): who rolled what, the winner pre-selected
-- (the officer may pick another name), and the Give button that follows the pick.
-- GiveDB is the D/B button (#39): it gives to the raid's remembered disenchanter or bank character.
-- In practice mode (#107) each item in the window gets made-up reserves from the group (PracticeReserves),
-- the same on every redraw of the window.
-- A Test drop (#108, TestDrop) is a made-up loot window (ns.LootWindow.fake): Build then ignores the
-- loot master and raid selection, its awards have no raid, and its chat lines carry a made-up raid code.
-- In practice mode (#17) every award made here is marked practice; the operations that follow an
-- award (confirm, correction, undo) take the award's own mark, so switching changes only the next.
-- Every operation recorded here is sent to the other officers right after it is saved
-- (Hub.SendOwn, #98).
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
local BOSS_MENU_TITLE = "Which boss dropped this?"
local TEST_DROP = "Test drop"
local TEST_BOSS = "testdrop" -- the boss id its awards carry, so their chat lines can be built
local TEST_DROP_NOTICE = "Test drop: no corpse, reserves are made up, nothing is handed out or sent to the"
  .. " site."
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
  ["not undoable"] = "Only a confirmed award can be undone.",
  ["undo fight"] = "Chat is locked in the boss fight. Undo waits until it ends.",
  ["undo not loot master"] = "Only the loot master can undo awards.",
  unknown = "The game can't name them yet. Try again in a moment.",
  grey = "Grey items can only go to you.",
  empty = "That item is gone from the loot window.",
  ["already db"] = "It already goes to disenchant/bank. To choose someone else, use Not handed out,"
    .. " then D/B.",
  ["pick changed"] = "The disenchant/bank character changed. Check the list and choose again.",
  ["another roll"] = "Another item's roll is still going. Hand that item out first.",
}

local bare = ns.Rules.Bare
local chosenBoss -- the boss row id the officer picked for this loot window
local sessionPick -- the D/B pick while no raid is loaded: kept until the game closes, never saved
local dbNotes = {} -- per slot, why the last D/B click handed nothing out
local refusals = {} -- per award key, why the last not-confirmed choice was refused
local picks = {} -- per slot, the name the officer clicked in the roll list: { item, name }
local rollNotes = {} -- per slot, why the last hidden-roll click handed nothing out: { item, text }
local testPick -- the D/B pick in a Test drop: kept until its window closes, never saved
local testKeys = {} -- a Test drop: the keys of the awards made in this window, for the copies still to come
local madeUp = {} -- practice mode: per item id in this loot window, its made-up reserves
local dropCount = 0 -- practice mode: drops given made-up reserves this session, to move through the cases
local windowItems -- the open loot window's items as it opened, for its boss after some are handed out
local calls = {} -- per not confirmed award key, the open roll called from its give-else list: { slot, item }
local METHODS = { hr = "HR", sr = "SR", open = "OPEN_ROLL" }
local ROLL_HEADINGS = { hr = "Rolls (hard reserve holders only)", sr = "Rolls (soft reserve holders only)",
  open = "Rolls (everyone)" }
local HIDDEN_WARNING = "The game is hiding rolls from add-ons right now. Watch chat, then click the winner."
local NOT_RECEIVE = " can't be given it: the game won't let them receive it (usually: not nearby when"
  .. " the boss died)."

ns.On("LOOT_CLOSED", function()
  chosenBoss, dbNotes, refusals, picks, rollNotes, madeUp, calls = nil, {}, {}, {}, {}, {}, {}
  testPick, testKeys = nil, {}
  windowItems = nil
end)

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

-- The selected raid's id: none in a Test drop (#108), which ignores the raid selection.
local function testDrop() return ns.LootWindow.fake ~= nil or nil end

-- The raid code a chat line carries: the raid's, or for a practice award with no raid (a Test drop's,
-- #108) a made-up one that matches no raid, so the line can still be posted. Nil for any other no-raid
-- award: its line can't be built.
local TEST_CODE = "PTEST0"
local function lineRaid(raidId, practice)
  local snapshot = ns.Raids.Get(raidId)
  if snapshot then return snapshot.code end
  return practice and not raidId and TEST_CODE or nil
end

local function activeRaid()
  if ns.LootWindow.fake then return nil end
  return ns.Selection.Status().activeRaid
end

-- True when the player is the master looter; in a Test drop, always.
local function isLootMaster()
  if ns.LootWindow.fake then return true end
  if not (C_PartyInfo and C_PartyInfo.GetLootMethod) then return false end
  local method, partyIndex, raidIndex = C_PartyInfo.GetLootMethod()
  if method ~= "master" and not (Enum and Enum.LootMethod and method == Enum.LootMethod.Masterlooter) then
    return false
  end
  if partyIndex == 0 then return true end
  local name = IsInRaid() and raidIndex and raidIndex > 0 and GetRaidRosterInfo(raidIndex)
  return name and bare(name) == bare(UnitName("player")) or false
end

-- Practice: the item's made-up reserves, made the first time they're asked for and the same on every
-- redraw of the window. A Test drop asks too (TestDrop), before the pop-up draws.
function Popup.MadeUp(item)
  if not madeUp[item] then
    madeUp[item] = ns.PracticeReserves.Generate(Popup.Roster(), dropCount)
    dropCount = dropCount + 1
  end
  return madeUp[item]
end

-- The names in the group, the player included.
function Popup.Roster()
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
    local name = ns.LootWindow.Candidate(slot, i)
    if not name then break end
    list[#list + 1] = name
    if name == "Unknown" then unknown = true end
  end
  return #list > 0 and list or nil, unknown
end

-- The loot window's items at or above the threshold: { slot, item, link, guid }.
local function lootItems()
  local items, threshold = {}, ns.LootWindow.Threshold() or 0
  for slot = 1, ns.LootWindow.NumItems() do
    local link = ns.LootWindow.SlotLink(slot)
    local item = link and tonumber(link:match("item:(%d+)"))
    local quality = select(5, ns.LootWindow.SlotInfo(slot))
    if item and quality and quality >= threshold then
      items[#items + 1] = { slot = slot, item = item, link = link, guid = (ns.LootWindow.SourceInfo(slot)) }
    end
  end
  return items
end

local function killTime(raidId, bossId)
  local at = ((ns.db.attribution or {})[raidId] or { kills = {} }).kills[bossId]
  return at and date("%H:%M", at)
end

-- The boss list to pick from: the raid's bosses, Trash included, id's row selected. markTrash marks
-- "Trash" while id is nil, as the pop-up's design draws it.
local function bossMenu(raidId, snapshot, id, markTrash)
  local menu, trashMarked = {}, false
  for _, row in ipairs(snapshot.bosses) do
    local selected = id == row.id or (markTrash and id == nil and row.trash and not trashMarked)
    trashMarked = trashMarked or (id == nil and row.trash)
    menu[#menu + 1] = { id = row.id, name = row.name, selected = selected,
      killed = not row.trash and killTime(raidId, row.id) or nil }
  end
  return menu
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
  local boss = { resolved = id ~= nil, id = id, menuTitle = BOSS_MENU_TITLE,
    menu = bossMenu(raidId, snapshot, id, true) }
  for _, row in ipairs(snapshot.bosses) do
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
  local reserves, names = ctx.reserves, ctx.roster
  local made = ctx.made and ctx.made[it.item]
  if made then
    -- Practice: the made-up group stands in for the game's, so the rules skip the holders it leaves out.
    reserves, names, cands, unknown = { [it.item] = made.holders }, made.roster, made.candidates, false
  end
  local args = { item = it.item, reserves = reserves, awards = awards, roster = names,
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
  row.users = {}
  for _, h in ipairs(resolved.contenders) do
    row.contenders[#row.contenders + 1] = h.char
    row.users[bare(h.char)] = h.user
  end
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
    if not ctx.snapshot and not ctx.made then
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

-- "A", "A and B", "A, B and C".
local function nameList(names)
  if #names <= 1 then return names[1] or "" end
  return table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
end

-- Whether the name may be handed the item: the corpse lists them (or its list is unknown).
local function listedFor(slot, name)
  local cands = candidates(slot)
  local listed = not cands
  for _, n in ipairs(cands or {}) do
    listed = listed or n == "Unknown" or bare(n) == bare(name)
  end
  return listed
end

-- The roll list of a row whose roll is called (result: Rolls.Result): the entries by roll, highest
-- first, then those still waiting; the ignored rolls; and the Give button for the picked name, or
-- for the highest roller when none is picked (nobody on a tie or a hidden roll). A tie adds a warning
-- and the Re-roll button; hidden rolls (#102) a warning, the roll box and name buttons that award
-- at once, with no Give button. Returns the list and the Give button.
local function rollList(row, result, boss, locked)
  local entries, order = {}, {}
  for i, e in ipairs(result.entries) do entries[i], order[e] = e, i end
  table.sort(entries, function(a, b)
    if (a.roll ~= nil) ~= (b.roll ~= nil) then return a.roll ~= nil end
    if (a.roll or 0) ~= (b.roll or 0) then return (a.roll or 0) > (b.roll or 0) end
    return order[a] < order[b] -- equal rolls keep their order: the sort alone isn't stable
  end)
  local picked = picks[row.slot]
  picked = picked and picked.item == row.item and picked.name or result.winner
  local list = { heading = ROLL_HEADINGS[result.kind], entries = {}, ignored = {},
    hint = "or click another name" }
  list.count = result.total and (result.rolled .. " of " .. result.total .. " rolled")
    or (result.rolled .. " rolled")
  local tied = {}
  for _, name in ipairs(result.tie or {}) do tied[bare(name)] = true end
  local chosen
  for _, e in ipairs(entries) do
    local selected = picked ~= nil and bare(e.name) == bare(picked)
    if selected then chosen = e end
    list.entries[#list.entries + 1] = { name = e.name, roll = e.roll, waiting = e.roll == nil,
      selected = selected, tied = tied[bare(e.name)] or nil }
  end
  for _, i in ipairs(result.ignored) do
    list.ignored[#list.ignored + 1] = { name = i.name, roll = i.roll, reason = i.reason }
  end
  if result.hidden then
    list.hidden = { warning = HIDDEN_WARNING, label = "Their roll (optional):" }
    if result.kind == "open" then list.hidden.label = "Their roll (needed for an open roll):" end
    for _, e in ipairs(list.entries) do
      e.enabled = boss.resolved and listedFor(row.slot, e.name) and not locked
      if locked then e.tooltip = FIGHT_TOOLTIP end
    end
    local note = rollNotes[row.slot]
    list.hidden.note = note and note.item == row.item and note.text or nil
    list.hint = nil
    return list, { text = "", action = "rollhidden", enabled = false, hidden = true }
  end
  if result.tie then
    list.warning = "Tie at " .. result.top .. ": " .. nameList(result.tie)
    local line = ns.Rolls.RerollLine(row.slot, row.item)
    list.reroll = { text = "Re-roll the tie", action = "reroll", enabled = not locked,
      tooltip = locked and FIGHT_TOOLTIP or nil, hint = line and ("Posts: " .. line) or nil }
  end
  local button = { text = "Give", action = "rollgive", enabled = false }
  if chosen then
    button.winner, button.roll = chosen.name, chosen.roll
    button.text = "Give to " .. chosen.name .. (chosen.roll and (" (" .. chosen.roll .. ")") or "")
    local listed = listedFor(row.slot, chosen.name)
    button.enabled = boss.resolved and listed
    if not listed then list.unavailable = chosen.name .. NOT_RECEIVE end
  end
  if locked then button.enabled, button.tooltip = false, FIGHT_TOOLTIP end
  return list, button
end

-- The buttons of a row, once the boss is known: Give and D/B need a boss picked. In a boss fight
-- the Give and roll buttons wait, with a tooltip saying why. A row being handed out, or not
-- confirmed, has none (a not confirmed row's choices are in row.notConfirmed), except the roll list
-- and its Give once an open roll is called from a not confirmed row's list (#118): the Give carries
-- the award's key, and the award's own boss counts.
local function addButtons(row, boss, locked, result)
  local nc = row.notConfirmed
  -- A roll called from a not confirmed row shows only on that row, only it shows there, and only
  -- until another choice ends it.
  if result and (result.forKey ~= (nc and nc.key) or (nc and not calls[nc.key])) then result = nil end
  if row.handout or (nc and not result) then
    row.buttons = {}
    return
  end
  if nc then
    local button
    row.rolls, button = rollList(row, result, { resolved = true }, locked)
    button.key = nc.key
    row.buttons = { button }
    return
  end
  local primary
  if result and (row.action == "roll" or row.action == "openroll") then
    row.rolls, primary = rollList(row, result, boss, locked)
  elseif row.action == "give" then
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
  local pick, names, members = Popup.DBPick(), Popup.Roster(), {}
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
-- confirmed), what happened and the officer's three choices (Choices). The pop-up's list also has
-- the open roll line (#118), whose roll list shows in the row; the Awards tab's has none.
local function notConfirmed(attempt, locked)
  local choices = Popup.Choices(attempt.awardKey)
  choices.text = "The game didn't confirm that " .. attempt.winner .. " got it. They may be too far away,"
    .. " or their bags are full."
  choices.hint = NC_HINT
  choices.list.openRoll = { label = "Open roll", text = "everyone can roll", button = "Call open roll",
    enabled = not locked, tooltip = locked and NC_FIGHT_TOOLTIP or nil }
  return choices
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
-- contenders, users, winner, user, rolls (once a roll is called: { heading, count, entries = { { name,
-- roll, waiting, selected, tied } }, ignored = { { name, roll, reason } }, hint, unavailable, and for a
-- tie warning and reroll ({ text, action, enabled, tooltip, hint }), for hidden rolls hidden ({ warning,
-- label, note }) with enabled and tooltip on each entry), whose Give button is buttons[1], action
-- "rollgive", with winner and roll (hidden rolls: hidden = true, no Give button)),
-- skipped, skippedText, note, text,
-- action, unavailable, dbNote (why the last D/B click handed nothing out), handout (while the game
-- confirms a hand-out: { text, note }),
-- notConfirmed (once the game gave up on its hand-out: { key, text, hint, refusal (why the last
-- choice was refused), buttons (Try again, Give to someone else, Not handed out: text, action,
-- enabled, tooltip), list = { title, people = { { char, method, kind, available, reason, enabled,
-- tooltip } }, db, openRoll ({ label, text, button, enabled, tooltip }), empty, hint, back } }; and its
-- open roll's list (#118) as rolls, its Give as buttons[1], with key), buttons (each: text, action,
-- enabled, tooltip; the D/B button's also pick)), dbMenu ({ title,
-- members = { { name, selected } }, note }), count, foot, recheck, practice (practice mode is on: the
-- title starts with "[Practice] " and the frame tags the foot).
function Popup.Build()
  local fake = testDrop()
  if not isLootMaster() then return nil, "not loot master" end
  if not fake and ns.Selection.IsQuiet() then return nil, "not a guild run" end
  local items = lootItems()
  if #items == 0 then return nil, "no items" end
  local raidId = activeRaid()
  local snapshot = ns.Raids.Get(raidId)
  local ctx = { snapshot = snapshot, awards = {}, reserves = {}, roster = Popup.Roster(), unlisted = {} }
  if ns.Practice() then
    -- Practice: each item of the window gets made-up reserves, the same on every redraw of it.
    ctx.made = {}
    for _, it in ipairs(items) do ctx.made[it.item] = Popup.MadeUp(it.item) end
  end
  for _, key in ipairs(testKeys) do
    -- A Test drop's own awards count as received, so the next copy goes to another holder.
    local award = ns.Records.Get(key)
    if award then ctx.awards[#ctx.awards + 1] = award end
  end
  if snapshot then
    ctx.reserves = snapshot.reserves
    for _, a in ipairs(snapshot.awards) do ctx.awards[#ctx.awards + 1] = a end
    for _, a in ipairs(ns.Raids.Awards(raidId)) do ctx.awards[#ctx.awards + 1] = a end
    for _, it in ipairs(items) do
      local _, unlisted = ns.Attribution.Suggest(it.item, it.guid)
      ctx.unlisted[it.item] = unlisted == "unlisted"
    end
  end
  local boss = fake and { resolved = true, id = TEST_BOSS, name = TEST_DROP }
    or bossControl(raidId, snapshot, items)
  local locked = Popup.ChatLocked()
  local handouts = {}
  for _, a in ipairs(ns.Tracking.Pending()) do
    if a.status == "pending" and not a.windowClosed then handouts[a.slot] = a end
  end
  local unconfirmed = unconfirmedBySlot()
  local total, seen, earlier, copyNotes = {}, {}, {}, {}
  for _, it in ipairs(items) do total[it.item] = (total[it.item] or 0) + 1 end
  local model = { boss = boss, rows = {}, count = #items,
    foot = fake and "Reserves: made up" or footLine(raidId, snapshot) }
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
    addButtons(row, boss, locked, ns.Rolls.Result(it.slot, it.item))
    model.recheck = model.recheck or row.recheck
    model.rows[#model.rows + 1] = row
  end
  model.practice = ns.Practice()
  model.title = (model.practice and "[Practice] " or "") .. "Loot"
    .. (boss.name and (" · " .. boss.name) or "")
  if fake then
    model.notice = TEST_DROP_NOTICE
  elseif not snapshot and not ctx.made then
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
  raidId = raidId or activeRaid()
  if not raidId then return ns.LootWindow.fake and testPick or sessionPick end
  local saved = ns.db.dbPick
  return type(saved) == "table" and saved[raidId] or nil
end

-- The officer chose a name in the D/B list: it is remembered for the raid, and nothing is handed
-- out. Returns true, or nil and "not in raid".
function Popup.SetDBPick(name)
  local found
  for _, member in ipairs(Popup.Roster()) do
    if name and bare(member) == bare(name) then found = member end
  end
  if not found then return nil, "not in raid" end
  local raidId = activeRaid()
  if raidId then
    if type(ns.db.dbPick) ~= "table" then ns.db.dbPick = {} end
    ns.db.dbPick[raidId] = found
  elseif ns.LootWindow.fake then
    testPick = found
  else
    sessionPick = found
  end
  dbNotes = {}
  return true
end

-- The officer's choice on a not confirmed row was refused for `why` (nil: it worked): the row
-- says so, in `note`'s words when given, until the next choice or the loot window closes.
function Popup.Refused(key, why, note)
  refusals[key] = why and (note or REFUSALS[why] or ("It couldn't be done (" .. tostring(why) .. ")."))
    or nil
end

-- Why the last choice on the award was refused, in the row's words, or nil.
function Popup.Refusal(key) return refusals[key] end

-- Posts the operation's chat line, built from data, in raid (or party) chat. With no data (the
-- record wasn't saved; why says why), a line that can't be built or a send the game refuses with an
-- error, nothing is posted: the log says why under `what`, and the officer is told `told`.
-- Returns true once posted.
local function post(operation, data, why, what, told)
  local line, problem
  if data then
    line, problem = ns.OpText.BuildLine(operation, data)
  else
    problem = "the record wasn't saved (" .. tostring(why) .. ")"
  end
  if line then
    local sent, err = pcall(C_ChatInfo.SendChatMessage, line, IsInRaid() and "RAID" or "PARTY")
    if sent then return true end
    problem = "the game refused it (" .. tostring(err) .. ")"
  end
  ns.Log(what .. " not posted: " .. problem)
  ns.Print(told .. " Type /bf log for why.")
end
-- The outside hand-out question (OutsideHandout) posts its award lines the same way.
Popup.Post = post

local handoutCheck, replaceWith

-- Hands the item to chosen (by name among the corpse's candidates), records the award and posts its
-- line. On a not confirmed row (its open roll, #118) the award is replaced instead, as GiveElse does,
-- with an open roll award carrying the roll. Returns the hand-out, or nil and why: "not a candidate",
-- "changed" (the award isn't waiting as not confirmed now), handoutCheck's or Tracking.Give's reasons.
local function handOut(model, row, chosen, roll, fromRolls)
  local index
  for i = 1, MAX_CANDIDATES do
    local name = ns.LootWindow.Candidate(row.slot, i)
    if not name then break end
    if bare(name) == bare(chosen) then
      index = i
      break
    end
  end
  if not index then return nil, "not a candidate" end
  local nc = row.notConfirmed
  if nc then
    local award, slot = handoutCheck(nc.key)
    if not award then return nil, slot == "not unconfirmed" and "changed" or slot end
    if slot ~= row.slot then return nil, "changed" end
    return replaceWith(nc.key, award, slot, index, { char = chosen, method = "OPEN_ROLL", roll = roll },
      " is being handed to " .. chosen .. " instead of " .. (award.char or "disenchant/bank"))
  end
  local attempt, reason = ns.Tracking.Give(row.slot, index)
  if not attempt then return nil, reason end
  local method = fromRolls and METHODS[row.mode] or (row.mode == "hr" and "HR" or "SR")
  local user = fromRolls and row.users[bare(chosen)] or row.user
  local op, why = ns.Records.Award({ boss = model.boss.id, item = row.item, char = chosen,
    user = user, method = method, roll = roll, practice = ns.Practice(), noRaid = testDrop() })
  ns.Hub.SendOwn(op, why)
  local data
  if op then
    attempt.awardKey = op.id
    if testDrop() then testKeys[#testKeys + 1] = op.id end
    data = { raid = lineRaid(activeRaid(), op.practice), key = op.id, item = row.item, link = row.link,
      boss = model.boss.id, method = method, roll = roll, winner = chosen, practice = op.practice }
  end
  attempt.announced = post("award", data, why, "Award line for " .. row.link,
    row.link .. " is being handed to " .. chosen .. ", but its raid chat line couldn't be posted.")
  return attempt
end

-- The officer clicked a row's Give button: hands the item to the winner, found by name among
-- this corpse's candidates (their order changes per corpse), records the award as announced and
-- posts its line in raid chat. A line that can't be built is not posted, and the officer is
-- told; the hand-out and the award stand. item and winner are what the clicked button showed: if
-- the row now names another item or winner, nothing happens. Returns the hand-out (Tracking's
-- attempt, with awardKey and announced), or nil and why: "fight" (chat is locked), "not ready"
-- (no Give enabled for the slot), "changed", "not a candidate" or Tracking.Give's reasons.
-- A row with a roll list is given to the name picked there, with its roll (the one the button
-- showed): winner and roll are what the clicked button showed. key is the button's key: a not
-- confirmed award's, on the roll list of the open roll called from its row (#118); the row must
-- still be that award's ("changed" if not), and the give replaces the award.
function Popup.Give(slot, item, winner, roll, key)
  if Popup.ChatLocked() then return nil, "fight" end
  local model = Popup.Build()
  local row
  for _, r in ipairs(model and model.rows or {}) do
    if r.slot == slot then row = r end
  end
  local ncKey = row and row.notConfirmed and row.notConfirmed.key
  if key ~= ncKey and (key or row) then return nil, "changed" end
  local button = row and row.buttons[1]
  local fromRolls = row and row.rolls and button.action == "rollgive"
  if not (row and (row.action == "give" or fromRolls) and button and button.enabled) then
    return nil, "not ready"
  end
  if fromRolls then
    if row.item ~= item or button.winner ~= winner or button.roll ~= roll then return nil, "changed" end
  else
    if row.item ~= item or row.winner ~= winner then return nil, "changed" end
    roll = nil
  end
  return handOut(model, row, fromRolls and winner or row.winner, roll, fromRolls)
end

local ROLL_NOTES = {
  ["roll needed"] = "Type their roll first: an open roll needs it.",
  ["bad roll"] = "Their roll must be a whole number from 1 to 100.",
}

-- The officer clicked a name while the game hides the rolls (#102): hands the item to that player
-- and records the award with the roll typed in the box (rollText, as typed; empty for none). The
-- roll is checked before anything is handed out: it must be a whole number from 1 to 100, and an
-- open roll needs one. A refusal changes nothing and leaves a note for the row. Returns the
-- hand-out, or nil and why: "fight", "not ready" (no hidden roll list, or the name's button is off),
-- "not listed", "changed", "roll needed", "bad roll", "not a candidate" or Tracking.Give's reasons.
-- key is as Give's: on a not confirmed row's open roll (#118), the give replaces the award.
function Popup.GiveHidden(slot, item, winner, rollText, key)
  if Popup.ChatLocked() then return nil, "fight" end
  local model = Popup.Build()
  local row
  for _, r in ipairs(model and model.rows or {}) do
    if r.slot == slot then row = r end
  end
  local ncKey = row and row.notConfirmed and row.notConfirmed.key
  if key ~= ncKey and (key or row) then return nil, "changed" end
  if not (row and row.rolls and row.rolls.hidden) then return nil, "not ready" end
  if row.item ~= item then return nil, "changed" end
  local entry
  for _, e in ipairs(row.rolls.entries) do
    if bare(e.name) == bare(winner) then entry = e end
  end
  if not entry then return nil, "not listed" end
  if not entry.enabled then return nil, "not ready" end
  local text = strtrim(rollText or "")
  local roll, why
  if text ~= "" then
    roll = text:match("^%d+$") and tonumber(text)
    if not (roll and roll >= 1 and roll <= 100) then why = "bad roll" end
  elseif row.mode == "open" or row.notConfirmed then
    why = "roll needed"
  end
  local attempt, reason
  if not why then
    attempt, reason = handOut(model, row, entry.name, roll, true)
    why = reason
  end
  rollNotes[slot] = nil
  if not attempt then
    local note = ROLL_NOTES[why] or ("It couldn't be given (" .. tostring(why) .. ").")
    rollNotes[slot] = { item = item, text = note }
    return nil, why
  end
  return attempt
end

-- The officer clicked a name in a row's roll list: the Give button follows. Returns true, or nil and
-- why: "not ready" (the row has no roll list) or "not listed".
function Popup.PickWinner(slot, item, name)
  local model = Popup.Build()
  for _, r in ipairs(model and model.rows or {}) do
    if r.slot == slot and r.item == item and r.rolls then
      for _, e in ipairs(r.rolls.entries) do
        if bare(e.name) == bare(name) then
          picks[slot] = { item = item, name = e.name }
          return true
        end
      end
      return nil, "not listed"
    end
  end
  return nil, "not ready"
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

-- The award's item link: its last hand-out's, else the game's, else its number.
local function linkOf(key, award)
  local attempt = attemptOf(key)
  local made = award.item == ns.TestDrop.ITEM and ns.TestDrop.LINK -- a Test drop's made-up item
  return attempt and attempt.link or made or select(2, GetItemInfo(award.item)) or ("item " .. award.item)
end

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
  for slot = 1, ns.LootWindow.NumItems() do slots[#slots + 1] = slot end
  for _, slot in ipairs(slots) do
    if itemOf(ns.LootWindow.SlotLink(slot)) == item then return slot end
  end
end

-- findSlot, or nil and why: "window" (no loot window open) or "changed" (the item isn't in it).
-- The officer is told either way.
local function lootSlot(key, item)
  local slot = findSlot(key, item)
  if slot then return slot end
  ns.Print(OPEN_WINDOW)
  return nil, ns.LootWindow.NumItems() == 0 and "window" or "changed"
end

-- The index of the candidate with this name for the slot, or nil.
local function candidateIndex(slot, char)
  for i = 1, MAX_CANDIDATES do
    local name = ns.LootWindow.Candidate(slot, i)
    if not name then return end
    if bare(name) == bare(char) then return i end
  end
end

-- Why the D/B pick can't be handed the item: they aren't in the raid, or the game won't let them
-- receive it. The officer's note, naming the pick.
local function dbRefusal(pick)
  local inRaid
  for _, member in ipairs(Popup.Roster()) do inRaid = inRaid or bare(member) == bare(pick) end
  return inRaid and ("The game won't let " .. pick .. " receive this item (usually: not"
    .. " nearby when the boss died). Right-click D/B to choose someone else.")
    or (pick .. " isn't in the raid. Right-click D/B to choose someone else.")
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
    dbNotes[slot] = dbRefusal(pick)
    return nil, "not a candidate"
  end
  local attempt, reason = ns.Tracking.Give(slot, index)
  if not attempt then return nil, reason end
  dbNotes[slot] = nil
  ns.Rolls.End(slot, item)
  local op, why = ns.Records.Award({ boss = model.boss.id, item = row.item, method = "DISENCHANT_BANK",
    practice = ns.Practice(), noRaid = testDrop() })
  ns.Hub.SendOwn(op, why)
  local data
  if op then
    attempt.awardKey = op.id
    data = { raid = lineRaid(activeRaid(), op.practice), key = op.id, item = row.item, link = row.link,
      boss = model.boss.id, method = "DISENCHANT_BANK", practice = op.practice }
  end
  attempt.announced = post("award", data, why, "Award line for " .. row.link,
    row.link .. " is being handed to " .. pick .. " to disenchant or bank, but its raid chat line"
      .. " couldn't be posted.")
  return attempt
end

-- The checks every hand-out choice shares. Returns the award and the slot, or nil and why.
handoutCheck = function(key)
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

local otherHolders

-- The people the award's item could go to instead: the item's other reserve holders, hard
-- reserves first, each with the method the new award carries. Trials, holders who already have
-- it and the site's blocked holders are left out. key is the award's key. Returns a list of
-- { char, user, method ("HR" or "SR"), available, reason (when not available: "not in raid",
-- or "cannot receive" when the open loot window's candidates leave them out) }, or nil and "not
-- unconfirmed" or "handing out".
function Popup.GiveElseList(key)
  local award, why = unconfirmedAward(key)
  if not award then return nil, why end
  return otherHolders(key, award, true)
end

-- The award's item's reserve holders other than its winner, as GiveElseList lists them. atCorpse:
-- the item is still on the corpse, so the open loot window (its candidates, practice mode's made-up
-- reserves) counts; Pick winner's item has left it, so only the raid does.
otherHolders = function(key, award, atCorpse)
  local snapshot = ns.Raids.Get(award.raid)
  local reserves = snapshot and snapshot.reserves or {}
  local holders = reserves[award.item] or reserves[tostring(award.item)] or {}
  -- Practice: the window's made-up holders, group and candidates stand in for the real ones.
  local made = atCorpse and ns.Practice() and madeUp[award.item]
  if made then holders = made.holders end
  local awards = {}
  for _, a in ipairs(snapshot and snapshot.awards or {}) do awards[#awards + 1] = a end
  for _, a in ipairs(ns.Raids.Awards(award.raid)) do
    if a.key ~= key then awards[#awards + 1] = a end
  end
  -- A name not loaded yet ("Unknown") can't be matched, so then nobody counts as unable to receive.
  local slot = atCorpse and findSlot(key, award.item)
  local cands, unknown
  if slot then cands, unknown = candidates(slot) end
  if unknown then cands = nil end
  if made then cands = made.candidates end
  local list = {}
  for _, kind in ipairs({ "HR", "SR" }) do
    local same = {}
    for _, h in ipairs(holders) do
      if h.kind == kind and h.user ~= award.user then same[#same + 1] = h end
    end
    local resolved = ns.Rules.Resolve({ item = award.item, reserves = { [award.item] = same },
      awards = awards, roster = made and made.roster or Popup.Roster(), candidates = cands })
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

-- Hands the not confirmed award's item to the slot's candidate at index, records the replacement
-- (the old award voided, a new one with fields: char, user, method and roll; no char for
-- Disenchant/bank) and posts the one correction line. A line that can't be built is not posted,
-- and the officer is told the link then `told`; the hand-out and the records stand. Returns the
-- new hand-out (with awardKey, the new award's key, and announced), or nil and Tracking.Give's
-- reasons.
replaceWith = function(key, award, slot, index, fields, told)
  local attempt, reason = ns.Tracking.Give(slot, index)
  if not attempt then return nil, reason end
  local link = ns.LootWindow.SlotLink(slot)
  local op, why = ns.Records.Replace(key, { boss = award.boss, item = award.item, char = fields.char,
    user = fields.user, method = fields.method, roll = fields.roll })
  ns.Hub.SendOwn(op, why)
  local data
  if op then
    attempt.awardKey = op.award.id
    data = { raid = lineRaid(award.raid, op.practice), id = op.id, key = key, newKey = op.award.id,
      item = award.item, link = link, boss = award.boss, method = fields.method, roll = fields.roll,
      winner = fields.char, oldWinner = award.char, practice = op.practice }
  end
  attempt.announced = post("correction", data, why, "Correction line for " .. link,
    link .. told .. ", but its raid chat line couldn't be posted.")
  return attempt
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
  return replaceWith(key, award, slot, index, { char = pick.char, user = pick.user, method = pick.method },
    " is being handed to " .. pick.char .. " instead of " .. (award.char or "disenchant/bank"))
end

-- Give to someone else, the Disenchant/bank line: hands the award's item to its raid's D/B pick,
-- records the replacement (the old award voided, a new Disenchant/bank award with no winner) and
-- posts the one correction line, as GiveElse does. pick is the name the clicked line showed. The
-- line is hidden for an award that is itself Disenchant/bank. Returns the new hand-out, or nil,
-- why and, for a pick who can't receive the item, the officer's note naming them: "fight", "already
-- db", "no pick", "pick changed" (the pick isn't the one shown), "not a candidate" or TryAgain's
-- reasons. A refusal changes nothing, hands nothing out and posts nothing.
function Popup.GiveElseDB(key, pick)
  if Popup.ChatLocked() then return nil, "fight" end
  local award, slot = handoutCheck(key)
  if not award then return nil, slot end
  if award.method == "DISENCHANT_BANK" then return nil, "already db" end
  local current = Popup.DBPick(award.raid)
  if not current then return nil, "no pick" end
  if current ~= pick then return nil, "pick changed" end
  local index = candidateIndex(slot, pick)
  if not index then return nil, "not a candidate", dbRefusal(pick) end
  return replaceWith(key, award, slot, index, { method = "DISENCHANT_BANK" },
    " is being handed to " .. pick .. " to disenchant or bank instead of " .. tostring(award.char))
end

-- Call open roll, the pop-up's give-else open roll line (#118): calls an open roll for the not
-- confirmed award's item (Rolls.Start), and its row shows the roll list. Nothing is recorded: the
-- award stays not confirmed until a winner is given from that list, which replaces it. key is the
-- award's key. Returns the roll-off's result, or nil and why: "fight", TryAgain's checks' reasons
-- or Rolls.Start's ("another roll" while another item's roll-off reads).
function Popup.CallOpenRoll(key)
  if Popup.ChatLocked() then return nil, "fight" end
  local award, slot = handoutCheck(key)
  if not award then return nil, slot end
  local result, why = ns.Rolls.Start(slot, award.item, key)
  if not result then return nil, why end
  calls[key] = { slot = slot, item = award.item }
  return result
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
  ns.Hub.SendOwn(op, why)
  local link = linkOf(key, award)
  post("undo", { raid = lineRaid(award.raid, op.practice), id = op.id, key = key, link = link,
    winner = award.char, practice = op.practice }, nil, "Undo line for " .. link,
    link .. (award.char and (" is no longer awarded to " .. award.char) or " is no longer going to"
      .. " disenchant/bank") .. ", but its raid chat line couldn't be posted.")
  return op
end

-- Undo on a confirmed award (or one made by hand on the site) in the Awards tab (#40): voids it and
-- posts its undo line. As NotHandedOut: no loot window needed, and a line that can't be built is not
-- posted, the officer told and the void standing. Returns the void operation, or nil and why:
-- "fight", "not loot master" (not for a Test drop's award), "not undoable" (not confirmed, or already
-- voided), "handing out" or Records.Void's reasons. A refusal changes nothing and posts nothing.
function Popup.Undo(key)
  if Popup.ChatLocked() then return nil, "fight" end
  local award = ns.Records.Get(key)
  -- A Test drop's award (practice, no raid) can be undone by whoever made it, loot master or not.
  if not (isLootMaster() or (award and award.practice and not award.raid)) then
    return nil, "not loot master"
  end
  if not (award and (award.state == "confirmed" or award.state == "manual") and not award.voided) then
    return nil, "not undoable"
  end
  local attempt = attemptOf(key)
  if attempt and attempt.status == "pending" then return nil, "handing out" end
  local op, why = ns.Records.Void(key)
  if not op then return nil, why end
  ns.Hub.SendOwn(op, why)
  local link = linkOf(key, award)
  post("undo", { raid = lineRaid(award.raid, op.practice), id = op.id, key = key, link = link,
    winner = award.char, practice = op.practice }, nil, "Undo line for " .. link,
    link .. (award.char and (" is no longer awarded to " .. award.char) or " is no longer going to"
      .. " disenchant/bank") .. ", but its raid chat line couldn't be posted.")
  return op
end

-- The Undo button of a confirmed award: { enabled, tooltip }. It posts a line, so it waits in a
-- boss fight.
function Popup.UndoButton()
  local locked = Popup.ChatLocked()
  return { enabled = not locked, tooltip = locked and NC_FIGHT_TOOLTIP or nil }
end

-- Pick winner (#126; design/115-pick-winner, version A): who has the item of an award undone after
-- it left the corpse. Built from the award's key alone, so it works after a /reload; nothing is
-- handed out. pick, the officer's picker as it stands: kind ("holder" with char, "roll" with member
-- and roll as typed, "db" or "again"; nil before a choice), note (as typed; nil until edited), and id
-- and newKey (Records.NewId: the correction's ids, so the line shown is the line posted).
local PICK_INTRO = " Choose who has it now. Nothing is handed out: this records the winner and posts one"
  .. " correction line."
local PICK_FIGHT = "Boss fight in progress. The game locks chat for add-ons, so the correction waits until it"
  .. " ends."
local PICK_LOCKED = "Chat is locked until the fight ends."
local PICK_WHY = {
  choose = "Choose who gets it.", member = "Choose who it went to.",
  ["roll needed"] = "Type their roll, 1 to 100.", ["bad roll"] = "A roll is 1 to 100.",
  ["too long"] = "The note can be up to 200 characters.",
  ["not a contender"] = REFUSALS["not a contender"], ["not in raid"] = REFUSALS["not in raid"],
  fight = "Chat is locked in the boss fight. The correction waits until it ends.",
  ["not loot master"] = "Only the loot master can change awards.",
  ["not needed"] = "This award no longer needs a winner.",
}
local MAX_NOTE = 200

-- The award, if it was undone after the game confirmed it and no one has it on the record since:
-- the item left the corpse (derived, not stored). Or nil.
local function needsWinner(key)
  local award = ns.Records.Get(key)
  if award and award.voided and award.state == "confirmed" and not award.replacedBy then return award end
end

-- The raid members who can be picked by open roll: the group but the previous winner, by name.
local function rollMembers(award)
  local list = {}
  for _, name in ipairs(Popup.Roster()) do
    if not (award.char and bare(name) == bare(award.char)) then list[#list + 1] = name end
  end
  table.sort(list)
  return list
end

-- The note the picker holds: as typed, else "Traded by" the previous winner (empty for the previous
-- winner picked again, or a disenchant/bank award, which had none).
local function pickNote(award, pick)
  if pick.note then return pick.note end
  if pick.kind == "again" or not award.char then return "" end
  return "Traded by " .. award.char
end

-- The new award the pick makes (Records.Award's fields, the note included), or nil and why: "choose",
-- "member", "roll needed", "bad roll", "not a contender", "not in raid" or "too long".
local function pickedAward(key, award, pick)
  local new = { boss = award.boss, item = award.item }
  if pick.kind == "holder" then
    local holder
    for _, h in ipairs(otherHolders(key, award)) do
      if h.char == pick.char then holder = h end
    end
    if not holder then return nil, "not a contender" end
    if not holder.available then return nil, "not in raid" end
    new.char, new.user, new.method = holder.char, holder.user, holder.method
  elseif pick.kind == "roll" then
    if not pick.member then return nil, "member" end
    local inRaid
    for _, name in ipairs(rollMembers(award)) do inRaid = inRaid or name == pick.member end
    if not inRaid then return nil, "not in raid" end
    local text = strtrim(pick.roll or "")
    if text == "" then return nil, "roll needed" end
    local roll = text:match("^%d+$") and tonumber(text)
    if not (roll and roll >= 1 and roll <= 100) then return nil, "bad roll" end
    new.char, new.method, new.roll = pick.member, "OPEN_ROLL", roll
  elseif pick.kind == "db" then
    new.method = "DISENCHANT_BANK"
  elseif pick.kind == "again" and award.method ~= "DISENCHANT_BANK" then
    new.char, new.user, new.method, new.roll = award.char, award.user, award.method, award.roll
  else
    return nil, "choose"
  end
  local note = strtrim(pickNote(award, pick))
  if #note > MAX_NOTE then return nil, "too long" end
  new.note = note ~= "" and note or nil
  return new
end

-- The correction line's data for OpText.BuildLine.
local function correctionData(key, award, new, id, newKey, practice)
  return { raid = lineRaid(award.raid, award.practice), id = id, key = key, newKey = newKey,
    item = award.item, link = linkOf(key, award), boss = award.boss, method = new.method, roll = new.roll,
    winner = new.char, oldWinner = award.char, practice = practice }
end

-- The picker of an award that needs a winner, or nil when it doesn't ("not needed"). Fields: key,
-- link, intro, fight (the boss fight note, while chat is locked), holders ({ char, method, kind,
-- available, reason, selected }; hard reserves first), empty (nobody else reserved it), roll
-- ({ selected, members = { { name, selected } }, member, roll, bad (the roll is shown in red) }), db
-- ({ selected }), again (the previous winner: { char, method, kind, selected }; nil for a
-- disenchant/bank award), note, line (the exact line Post correction posts) or text (why it can't
-- post yet, or why the line can't be built), post ({ enabled, tooltip }), locked (why Post waits)
-- and refusal (why the last Post was refused).
function Popup.Picker(key, pick)
  local award = needsWinner(key)
  if not award then return nil, "not needed" end
  local link = linkOf(key, award)
  local locked = Popup.ChatLocked()
  local model = { key = key, link = link, fight = locked and PICK_FIGHT or nil, holders = {},
    note = pickNote(award, pick), refusal = refusals[key],
    intro = link .. " was undone after " .. (award.char and (award.char .. " already had it.")
      or "it went to disenchant/bank.") .. PICK_INTRO }
  for _, h in ipairs(otherHolders(key, award)) do
    local hard = h.method == "HR"
    model.holders[#model.holders + 1] = { char = h.char, method = hard and LABELS["hr-single"] or LABELS.sr,
      kind = hard and "hr" or "sr", available = h.available, reason = h.reason,
      selected = pick.kind == "holder" and pick.char == h.char }
  end
  if #model.holders == 0 then model.empty = "Nobody else reserved this item." end
  local members = {}
  for i, name in ipairs(rollMembers(award)) do
    members[i] = { name = name, selected = name == pick.member }
  end
  model.roll = { selected = pick.kind == "roll", members = members, member = pick.member,
    roll = pick.roll or "" }
  model.db = { selected = pick.kind == "db" }
  if award.method ~= "DISENCHANT_BANK" then
    local hard = award.method == "HR"
    model.again = { char = award.char, kind = hard and "hr" or award.method == "SR" and "sr" or "open",
      method = hard and LABELS["hr-single"] or award.method == "SR" and LABELS.sr or LABELS.open,
      selected = pick.kind == "again" }
  end
  local new, why = pickedAward(key, award, pick)
  model.roll.bad = pick.kind == "roll" and (why == "bad roll") or nil
  if new then
    local line, problem = ns.OpText.BuildLine("correction",
      correctionData(key, award, new, pick.id, pick.newKey, award.practice))
    model.line = line
    if not line then model.text = "The raid chat line can't be posted: " .. problem .. "." end
  else
    model.text = PICK_WHY[why]
  end
  model.locked = locked and PICK_LOCKED or nil
  model.post = { enabled = new ~= nil and not locked,
    tooltip = model.locked or (not new and model.text) or nil }
  return model
end

-- Post correction: records who has the award's item now, as a replacement of the voided award (the
-- first void's reason stands), confirmed at once with no hand-out (the item left the corpse), and
-- posts its one correction line. Each operation is sent to the other officers. A line that can't be
-- built or posted is not posted: the record stands, the officer is told, and the second value is
-- the window's note. Returns the replace operation, or nil and why: "fight", "not loot master",
-- "not needed", pickedAward's reasons or Records.Replace's. A refusal changes nothing and posts
-- nothing; it is kept for the picker (Refused) and logged.
function Popup.Correct(key, pick)
  local award = needsWinner(key)
  local new, why
  if Popup.ChatLocked() then why = "fight"
  elseif not isLootMaster() then why = "not loot master"
  elseif not award then why = "not needed"
  else new, why = pickedAward(key, award, pick) end
  local op, conf, outcome
  if new then
    new.id = pick.newKey
    op, why = ns.Records.Replace(key, new, { id = pick.id })
  end
  if not op then
    ns.Log("Pick winner for " .. (award and linkOf(key, award) or tostring(key)) .. " refused: "
      .. tostring(why))
    Popup.Refused(key, why, PICK_WHY[why])
    return nil, why
  end
  Popup.Refused(key, nil)
  ns.Hub.SendOwn(op, why)
  conf, outcome = ns.Records.Confirm(op.award.id)
  ns.Hub.SendOwn(conf, outcome)
  if not conf then
    ns.Log("Pick winner: the new award " .. op.award.id .. " wasn't confirmed: " .. tostring(outcome))
  end
  local data = correctionData(key, award, new, op.id, op.award.id, op.practice)
  local who = new.char and (new.char .. " now has " .. data.link)
    or (data.link .. " now goes to disenchant/bank")
  if post("correction", data, nil, "Correction line for " .. data.link,
    who .. " on the record, but its raid chat line couldn't be posted.") then
    return op
  end
  return op, who .. " on the record, but the correction line couldn't be posted in raid chat. Tell the raid"
    .. " yourself. Type /bf log for why."
end

-- The three choices of a not confirmed award, built from its key alone, so the Awards tab has them
-- after a /reload too: { key, refusal (why the last choice was refused), buttons (Try again, Give to
-- someone else, Not handed out: text, action, enabled, tooltip), list (Give to someone else's, from
-- GiveElseList: { title, people = { { char, method, kind, available, reason, enabled, tooltip } },
-- db (the Disenchant/bank line: { label, pick, enabled, tooltip }; nil for a Disenchant/bank award),
-- empty, refusal (as above, shown while the list is open), hint, back }) }. Buttons that post a
-- line wait in a boss fight; Try again posts none.
function Popup.Choices(key)
  local award = ns.Records.Get(key)
  local link = linkOf(key, award)
  local locked = Popup.ChatLocked()
  local wait = locked and NC_FIGHT_TOOLTIP or nil
  local list = { title = "Give " .. link .. " to someone else", people = {}, back = "Back" }
  for _, c in ipairs(Popup.GiveElseList(key) or {}) do
    local hard = c.method == "HR"
    list.people[#list.people + 1] = { char = c.char, method = hard and LABELS["hr-single"] or LABELS.sr,
      kind = hard and "hr" or "sr", available = c.available,
      reason = c.reason == "cannot receive" and "can't receive it" or c.reason,
      enabled = c.available and not locked, tooltip = c.available and wait or nil }
  end
  if #list.people == 0 then list.empty = "No one else reserved it." end
  -- The Disenchant/bank line, but not for an award that is Disenchant/bank already (Robert,
  -- 2026-10-21): to change who, the officer uses Not handed out, then D/B.
  if award.method ~= "DISENCHANT_BANK" then
    local pick = Popup.DBPick(award.raid)
    list.db = { label = "Disenchant/bank", pick = pick, enabled = not locked, tooltip = wait }
    if not pick then
      list.db.label, list.db.enabled, list.db.tooltip = "Disenchant/bank: choose first", false, DB_CHOOSE_TIP
    end
  end
  list.refusal = refusals[key]
  list.hint = "Posts one correction line: Correction: " .. link .. " → their name, not "
    .. (award.char or "disenchant/bank") .. "."
  return { key = key, refusal = refusals[key], list = list,
    buttons = {
      { text = "Try again", action = "tryagain", enabled = true },
      { text = "Give to someone else", action = "giveelse", enabled = not locked, tooltip = wait },
      { text = "Not handed out", action = "nothandedout", enabled = not locked, tooltip = wait },
    } }
end

-- The officer's click on a not confirmed award's choice, in the pop-up or the Awards tab: action
-- "tryagain", "nothandedout", "giveelse" (to char), "givedb" (to the D/B pick char, the
-- Disenchant/bank line) or "openroll" (Call open roll); or "undo", Undo on a confirmed one. A refusal
-- is logged and kept for the row (Refused); a choice made clears it, and any other choice made ends
-- the open roll called from the row, undoing nothing. Returns what the choice returns.
function Popup.Choose(key, action, char)
  local ok, why, note
  if action == "openroll" then
    ok, why = Popup.CallOpenRoll(key)
  elseif action == "giveelse" then
    ok, why = Popup.GiveElse(key, char)
  elseif action == "givedb" then
    ok, why, note = Popup.GiveElseDB(key, char)
  elseif action == "tryagain" then
    ok, why = Popup.TryAgain(key)
  elseif action == "undo" then
    ok, why = Popup.Undo(key)
    if REFUSALS["undo " .. tostring(why)] then why = "undo " .. why end
  else
    ok, why = Popup.NotHandedOut(key)
  end
  if not ok then
    local award = ns.Records.Get(key)
    local link = award and linkOf(key, award) or tostring(key)
    local what = ({ giveelse = "Give to " .. tostring(char) .. " instead",
      givedb = "Give to disenchant/bank (" .. tostring(char) .. ") instead",
      openroll = "Call open roll", undo = "Undo" })[action]
    ns.Log((what or ("Not confirmed choice " .. action)) .. " for " .. link .. " refused: " .. tostring(why))
  end
  local call = calls[key]
  if ok and action ~= "openroll" and call then
    ns.Rolls.End(call.slot, call.item)
    calls[key] = nil
  end
  Popup.Refused(key, not ok and why or nil, note)
  return ok, why
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
  ns.Hub.SendOwn(ok, why)
  if not ok then ns.Log("Confirming the award " .. attempt.awardKey .. " failed: " .. tostring(why)) end
end
ns.Tracking.On("confirmed", confirmed)
ns.Tracking.On("late", confirmed)

-- A hand-out the game didn't confirm in time: its award is recorded as not confirmed.
ns.Tracking.On("unconfirmed", function(attempt)
  local award = attempt.awardKey and ns.Records.Get(attempt.awardKey)
  if not award or award.voided then return end
  local ok, why = ns.Records.NotConfirmed(attempt.awardKey)
  ns.Hub.SendOwn(ok, why)
  if ok then
    ns.Log("The game didn't confirm " .. attempt.link .. " to " .. attempt.winner)
  else
    ns.Log("Recording " .. attempt.awardKey .. " as not confirmed failed: " .. tostring(why))
  end
end)

-- The officer picks the boss (a boss row id of the loaded raid, "Trash" included) for this loot
-- window. Returns true, or nil and why.
function Popup.PickBoss(bossId)
  local snapshot = ns.Raids.Get(activeRaid())
  for _, row in ipairs(snapshot and snapshot.bosses or {}) do
    if row.id == bossId then
      chosenBoss = bossId
      return true
    end
  end
  return nil, "not a boss of this raid"
end

-- The loot window's items as it opened: handing them out takes them off the window, not its boss.
ns.On("LOOT_OPENED", function() windowItems = lootItems() end)

-- The boss row id the open loot window's items came from, as the pop-up resolves it (the officer's
-- pick, else the one boss they all point to), or nil: no window open, no raid loaded or no single boss.
function Popup.WindowBoss()
  if not windowItems or ns.Selection.IsQuiet() or testDrop() then return nil end
  local raidId = ns.Selection.Status().activeRaid
  local snapshot = ns.Raids.Get(raidId)
  if not snapshot then return nil end
  return bossControl(raidId, snapshot, windowItems).id
end

-- The pop-up's boss list for raidId (by default the selected raid), bossId's row selected and nothing
-- else, or nil with that raid not loaded: { title, menu = { { id, name, selected, killed } } }.
function Popup.BossMenu(bossId, raidId)
  raidId = raidId or ns.Selection.Status().activeRaid
  local snapshot = ns.Raids.Get(raidId)
  if not snapshot then return nil end
  return { title = BOSS_MENU_TITLE, menu = bossMenu(raidId, snapshot, bossId, false) }
end
