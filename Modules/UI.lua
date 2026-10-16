-- UI: the loot pop-up and the officers' window (#9).
-- The officers' window (#37): a titled frame, three tabs (Awards, Reserves, Sync) and an empty
-- footer, plus a minimap button. Tab content and the footer's contents belong to #14 to #17:
-- they draw into UI.tabs[name] and UI.footer.
local _, ns = ...

local UI = {}
ns.UI = UI

local WIDTH, HEIGHT = 640, 420
local TAB_NAMES = { "Awards", "Reserves", "Sync" }
local DEFAULT_ANGLE = math.rad(225) -- lower left of the minimap, where the design draws it

UI.tabs = {}   -- tab name -> its content frame, shown while the tab is selected
UI.tabButtons = {} -- tab name -> its button under the window

-- A piece of text styled like a game font. If the client has no font by that name the text still
-- appears, in a plain font: a missing name must never stop the add-on loading.
local function newText(parent, fontName)
  local ok, text = pcall(parent.CreateFontString, parent, nil, "OVERLAY", fontName)
  if ok and text then return text end
  text = parent:CreateFontString(nil, "OVERLAY")
  text:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
  return text
end

local window, button, badge

-- The saved part of BureaucracyForeverDB: window, minimap, shown. Made on the first write, so a
-- session that changes nothing saves nothing.
local function saved()
  ns.db.ui = ns.db.ui or {}
  return ns.db.ui
end
local function read() return ns.db.ui or {} end

local function isNumber(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- The window's saved spot is an offset of its centre from the screen's centre. One that leaves any
-- of the window off the screen (a smaller resolution than last time) is ignored.
local function savedWindowSpot()
  local spot = read().window
  if type(spot) ~= "table" or not isNumber(spot.x) or not isNumber(spot.y) then return end
  if math.abs(spot.x) + WIDTH / 2 > UIParent:GetWidth() / 2
    or math.abs(spot.y) + HEIGHT / 2 > UIParent:GetHeight() / 2 then
    return
  end
  return spot
end

local function placeWindow()
  local spot = savedWindowSpot() or { x = 0, y = 0 }
  window:ClearAllPoints()
  window:SetPoint("CENTER", UIParent, "CENTER", spot.x, spot.y)
end

local function saveWindowSpot()
  local x, y = window:GetCenter()
  if not x then return end
  saved().window = { x = x - UIParent:GetWidth() / 2, y = y - UIParent:GetHeight() / 2 }
end

function UI.Select(name)
  for _, tabName in ipairs(TAB_NAMES) do
    if tabName == name then
      UI.tabs[tabName]:Show()
    else
      UI.tabs[tabName]:Hide()
    end
    local tab = UI.tabButtons[tabName]
    local on = tabName == name
    tab.selected = on
    if on then tab.background:SetColorTexture(0.25, 0.2, 0.05, 1)
    else tab.background:SetColorTexture(0.08, 0.08, 0.08, 1) end
    if on then tab.label:SetTextColor(1, 0.82, 0) else tab.label:SetTextColor(0.6, 0.6, 0.6) end
  end
  UI.selected = name
  if name == "Reserves" then UI.RefreshReserves() end
  if name == "Sync" then UI.RefreshSync() end
end

-- A button drawn like the add-on's others: dark red, its label in the game's gold.
local function newButton(parent, label, width, height)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(width, height or 24)
  local background = b:CreateTexture(nil, "BACKGROUND")
  background:SetAllPoints()
  background:SetColorTexture(0.35, 0.08, 0.08, 1)
  b.label = newText(b, "GameFontNormal")
  b.label:SetPoint("CENTER")
  b.label:SetText(label)
  return b
end

-- The Reserves tab and the item tooltips (#15): the selected raid's reserves, read only.
local TICK = "|TInterface\\Buttons\\UI-CheckBox-Check:12|t"
local GREY = "|cff808080%s|r"
local CONTENT_WIDTH = 616
local COLUMNS = { item = { 0, 206 }, hr = { 210, 176 }, sr = { 390, 226 } } -- x and width
local ROW_GAP, HEADING_HEIGHT = 4, 22

local bare = ns.Rules.Bare

-- The characters in the group, by bare name. Out of a group it is the player alone.
local function rosterSet()
  local set = {}
  local function add(name)
    if name then set[bare(name)] = true end
  end
  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do add((GetRaidRosterInfo(i))) end
  else
    add(UnitName("player"))
    for i = 1, GetNumGroupMembers() - 1 do add(UnitName("party" .. i)) end
  end
  return set
end

-- The snapshot's baseline awards and the raid's own, as Rules reads them.
local function allAwards(raidId, snapshot)
  local awards = {}
  for _, a in ipairs(snapshot.awards) do awards[#awards + 1] = a end
  for _, a in ipairs(ns.Raids.Awards(raidId)) do awards[#awards + 1] = a end
  return awards
end

local function holderKey(h)
  return h.user .. "/" .. h.char .. "/" .. h.kind
end

-- An item's holders, as { name, received, absent, trial }, split into hard and soft reserves.
local function holderLists(snapshot, item, awards, roster)
  local received = {}
  local resolved = ns.Rules.Resolve({ item = item, reserves = snapshot.reserves, awards = awards })
  for _, skipped in ipairs(resolved.skipped) do
    if skipped.reason == ns.Rules.RECEIVED then received[holderKey(skipped)] = true end
  end
  local lists = { HR = {}, SR = {} }
  for _, h in ipairs(snapshot.reserves[item] or {}) do
    table.insert(lists[h.kind], {
      name = h.char, trial = h.trial, received = received[holderKey(h)] or false,
      absent = not roster[bare(h.char)],
    })
  end
  return lists.HR, lists.SR
end

-- One name, marked: grey when not in the raid, a tick once the item is received, "(trial)".
local function nameText(holder)
  local text = (holder.name:gsub("|", "||"))
  if holder.absent then text = GREY:format(text) end
  if holder.received then text = text .. " " .. TICK end
  if holder.trial then text = text .. " " .. GREY:format("(trial)") end
  return text
end

-- The names in a list, or the grey word for nobody.
local function namesText(holders, nobody)
  local parts = {}
  for i, holder in ipairs(holders) do parts[i] = nameText(holder) end
  return #parts > 0 and table.concat(parts, ", ") or GREY:format(nobody)
end

-- The reserved items grouped by boss, in the snapshot's order: { boss, items }. An item that
-- several bosses drop appears under each; reserved items no boss drops come last, as "Other".
local function reservedGroups(snapshot)
  local reserved = snapshot.reserves
  local groups, placed = {}, {}
  for _, boss in ipairs(snapshot.bosses) do
    local items = {}
    for _, item in ipairs(boss.items) do
      if reserved[item] and #reserved[item] > 0 then
        items[#items + 1] = item
        placed[item] = true
      end
    end
    if #items > 0 then groups[#groups + 1] = { boss = boss.name, id = boss.id, items = items } end
  end
  local others = {}
  for item, holders in pairs(reserved) do
    if #holders > 0 and not placed[item] then others[#others + 1] = item end
  end
  table.sort(others)
  if #others > 0 then groups[#groups + 1] = { boss = "Other", items = others } end
  return groups
end

local function plural(count, one, many)
  return count .. " " .. (count == 1 and one or many)
end

-- How many players reserved in a raid, and how many reserves they hold.
local function reserveCounts(snapshot)
  local users, players, total = {}, 0, 0
  for _, holders in pairs(snapshot.reserves) do
    for _, h in ipairs(holders) do
      if not users[h.user] then players = players + 1 end
      users[h.user] = true
      total = total + 1
    end
  end
  return players, total
end

-- What the Reserves tab shows. { empty = "no-raid" } with no selected raid loaded;
-- { empty = "no-reserves", raid = name } for a raid nobody reserved in; otherwise the header
-- line and each boss's rows, every row { item, hr, sr } (the item id and two lists of holders).
function UI.ReservesView()
  local raidId = ns.Selection.Status().activeRaid
  local snapshot = ns.Raids.Get(raidId)
  if not snapshot then return { empty = "no-raid" } end
  local players, total = reserveCounts(snapshot)
  if total == 0 then return { empty = "no-reserves", raid = snapshot.name } end
  local awards, roster = allAwards(raidId, snapshot), rosterSet()
  local groups = {}
  for _, group in ipairs(reservedGroups(snapshot)) do
    local rows = {}
    for _, item in ipairs(group.items) do
      local hr, sr = holderLists(snapshot, item, awards, roster)
      rows[#rows + 1] = { item = item, hr = hr, sr = sr }
    end
    groups[#groups + 1] = {
      boss = group.boss, rows = rows, killed = group.id ~= nil and ns.Attribution.Killed(group.id),
    }
  end
  return {
    header = snapshot.name .. ", " .. date("%a %d %b", snapshot.startsAt) .. " · "
      .. plural(players, "player", "players") .. " · " .. plural(total, "reserve", "reserves"),
    groups = groups,
  }
end

-- The empty state's heading and line.
local function emptyText(view)
  if view.empty == "no-reserves" then
    return "No reserves in this raid", "Nobody has reserved an item for " .. view.raid
      .. ". Load the raid's latest reserves in the Sync tab."
  end
  return "No raid chosen yet", "No raid is chosen yet. Pick one in the Sync tab."
end

-- The item as the game names it, with its icon; "Item <id>" until the game knows it.
local function itemText(item)
  local name, link, _, _, _, _, _, _, _, icon = GetItemInfo(item)
  if not name then return "Item " .. item end
  return (icon and ("|T" .. icon .. ":14|t ") or "") .. (link or name)
end

local reserves = {} -- the tab's pieces
UI.reserves = reserves

local function cell(index, pool, parent, fontName)
  local text = pool[index]
  if not text then
    text = newText(parent, fontName)
    text:SetJustifyH("LEFT")
    pool[index] = text
  end
  text:ClearAllPoints()
  text:Show()
  return text
end

local function place(text, column, y, value)
  text:SetPoint("TOPLEFT", reserves.child, "TOPLEFT", COLUMNS[column][1], -y)
  text:SetWidth(COLUMNS[column][2])
  text:SetText(value)
end

-- Draws the selected raid's reserves: a heading for each boss, a row for each item.
function UI.RefreshReserves()
  if not reserves.content or not window:IsShown() or not UI.tabs.Reserves:IsShown() then return end
  local view = UI.ReservesView()
  local list = not view.empty
  for _, piece in ipairs({ reserves.header, reserves.key, reserves.columns, reserves.scroll }) do
    if list then piece:Show() else piece:Hide() end
  end
  for _, piece in ipairs({ reserves.title, reserves.hint, reserves.toSync }) do
    if list then piece:Hide() else piece:Show() end
  end
  for _, pool in ipairs({ reserves.headings, reserves.items, reserves.hrs, reserves.srs }) do
    for _, text in ipairs(pool) do text:Hide() end
  end
  reserves.shown = {}
  if not list then
    local title, hint = emptyText(view)
    reserves.title:SetText(title)
    reserves.hint:SetText(hint)
    return
  end
  reserves.header:SetText(view.header)
  local y, headings, rows = 0, 0, 0
  for _, group in ipairs(view.groups) do
    headings = headings + 1
    local heading = cell(headings, reserves.headings, reserves.child, "GameFontNormal")
    heading:SetPoint("TOPLEFT", reserves.child, "TOPLEFT", 0, -y)
    heading:SetText(group.killed and group.boss .. " · killed" or group.boss)
    reserves.shown[#reserves.shown + 1] = { heading = heading }
    y = y + HEADING_HEIGHT
    for _, row in ipairs(group.rows) do
      rows = rows + 1
      local item = cell(rows, reserves.items, reserves.child, "GameFontHighlightSmall")
      local hr = cell(rows, reserves.hrs, reserves.child, "GameFontHighlightSmall")
      local sr = cell(rows, reserves.srs, reserves.child, "GameFontHighlightSmall")
      place(item, "item", y, itemText(row.item))
      place(hr, "hr", y, namesText(row.hr, "-"))
      place(sr, "sr", y, namesText(row.sr, "-"))
      reserves.shown[#reserves.shown + 1] = { item = item, hr = hr, sr = sr }
      y = y + math.max(item:GetStringHeight(), hr:GetStringHeight(), sr:GetStringHeight()) + ROW_GAP
    end
  end
  reserves.child:SetHeight(y)
end

-- The game sends a burst of item and roster news; one redraw covers it.
local redrawWaiting
local function redrawSoon()
  if redrawWaiting then return end
  redrawWaiting = true
  C_Timer.After(0.2, function()
    redrawWaiting = false
    UI.RefreshReserves()
  end)
end
ns.On("GROUP_ROSTER_UPDATE", redrawSoon)
-- The Sync tab says which instance the player is in.
for _, event in ipairs({ "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
  ns.On(event, function() UI.RefreshSync() end)
end
ns.On("GET_ITEM_INFO_RECEIVED", redrawSoon)

local function scrollByWheel(self, delta)
  local to = self:GetVerticalScroll() - delta * 40
  self:SetVerticalScroll(math.max(0, math.min(to, self:GetVerticalScrollRange())))
end

local function buildReserves(content)
  content.placeholder:Hide()
  reserves.content = content
  reserves.headings, reserves.items, reserves.hrs, reserves.srs, reserves.shown = {}, {}, {}, {}, {}

  reserves.key = newText(content, "GameFontDisable")
  reserves.key:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -2)
  reserves.key:SetText(TICK .. " received     Grey: not in raid     (trial): shown, doesn't roll")
  reserves.header = newText(content, "GameFontHighlightSmall")
  reserves.header:SetPoint("TOPRIGHT", content, "TOPRIGHT", -4, -2)
  reserves.columns = CreateFrame("Frame", nil, content)
  reserves.columns:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -20)
  reserves.columns:SetSize(CONTENT_WIDTH, 16)
  for column, label in pairs({ item = "Item", hr = "Hard reserve", sr = "Soft reserve" }) do
    local text = newText(reserves.columns, "GameFontNormal")
    text:SetPoint("TOPLEFT", reserves.columns, "TOPLEFT", COLUMNS[column][1] + 4, 0)
    text:SetText(label)
  end

  reserves.scroll = CreateFrame("ScrollFrame", nil, content)
  reserves.scroll:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -38)
  reserves.scroll:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
  reserves.child = CreateFrame("Frame", nil, reserves.scroll)
  reserves.child:SetSize(CONTENT_WIDTH, 1)
  reserves.scroll:SetScrollChild(reserves.child)
  reserves.scroll:EnableMouseWheel(true)
  reserves.scroll:SetScript("OnMouseWheel", scrollByWheel)

  -- The empty state: what is missing, and a way to the Sync tab.
  reserves.title = newText(content, "GameFontNormal")
  reserves.title:SetPoint("CENTER", content, "CENTER", 0, 30)
  reserves.hint = newText(content, "GameFontDisable")
  reserves.hint:SetPoint("TOP", reserves.title, "BOTTOM", 0, -6)
  reserves.hint:SetWidth(380)
  reserves.toSync = newButton(content, "Go to Sync", 90)
  reserves.toSync:SetPoint("TOP", reserves.hint, "BOTTOM", 0, -12)
  reserves.toSync:SetScript("OnClick", function() UI.Select("Sync") end)
end

-- Item tooltips anywhere in the game: the selected raid's hard and soft reserve names, for an
-- item somebody reserved. Nothing is added for any other item.
local function addReserveLines(tooltip, item)
  local raidId = ns.Selection.Status().activeRaid
  local snapshot = ns.Raids.Get(raidId)
  if not (snapshot and item and snapshot.reserves[item] and #snapshot.reserves[item] > 0) then return end
  local hr, sr = holderLists(snapshot, item, allAwards(raidId, snapshot), rosterSet())
  tooltip:AddLine(" ")
  tooltip:AddLine("Bureaucracy reserves", 1, 0.82, 0)
  tooltip:AddLine("Hard: " .. namesText(hr, "none"), 1, 1, 1, true)
  tooltip:AddLine("Soft: " .. namesText(sr, "none"), 1, 1, 1, true)
  tooltip:Show()
end

-- The client's newer tooltip hook when it has one, else the older item script. Either way
-- a line is added once for each time the tooltip is filled.
local function hookTooltips()
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
      addReserveLines(tooltip, data and data.id)
    end)
    return
  end
  for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
    tooltip:HookScript("OnTooltipCleared", function(self) self.reservesAdded = nil end)
    tooltip:HookScript("OnTooltipSetItem", function(self)
      if self.reservesAdded then return end
      self.reservesAdded = true
      local _, link = self:GetItem()
      addReserveLines(self, link and tonumber(link:match("item:(%d+)")))
    end)
  end
end

-- The Sync tab (#16, #51, design/44-sync-raids): the selection and who made it, the loaded raids
-- with a choice per row (and Not a guild run), the helper line, and the paste box that loads a
-- raid's reserves and chooses it for the group, and Awards out (#72): the text to paste into
-- Import awards on the site.
local sync = {} -- the tab's pieces
UI.sync = sync

local RELEASES = "https://github.com/robpaolella/bureaucracy-forever-addon/releases/latest"
local WHITE, AMBER = "|cffffffff%s|r", "|cffffa020%s|r"
local NOTE_COLORS = { good = { 0.08, 0.22, 0.08 }, warn = { 0.28, 0.2, 0.04 }, bad = { 0.32, 0.06, 0.06 } }
local RAID_COLUMNS = { -- x and width
  radio = { 4, 18 }, name = { 26, 160 }, when = { 190, 118 }, instance = { 312, 50 }, counts = { 366, 64 },
  awards = { 434, 40 }, pasted = { 478, 70 },
}
local RAID_HEADINGS = {
  name = "Raid event", when = "When", instance = "Instance", counts = "Players · reserves", awards = "Awards",
}

local function plain(text) return (text:gsub("|", "||")) end
local function clock(at) return date("%H:%M", at) end
local function raidName(raid) return plain(raid.name) .. ", " .. date("%a %d %b", raid.startsAt) end
-- The raid that left the list, by name and day, or by its code for a choice saved without them.
local function goneName(gone)
  return gone.name and raidName(gone) or "The selected raid (" .. plain(gone.code or gone.raid) .. ")"
end

local function agree(count, one, many) return count == 1 and one or many end

-- The game's radio button art, drawn in text: its texture holds the unchecked and checked looks.
local RADIO = { [false] = "|TInterface\\Buttons\\UI-RadioButton:14:14:0:0:64:16:0:16:0:16|t",
  [true] = "|TInterface\\Buttons\\UI-RadioButton:14:14:0:0:64:16:16:32:0:16|t" }
local OFF_LABEL = "Not a guild run " .. GREY:format("· the add-on stays off until you leave the group")

-- The loot master's name, or nil when master loot is off.
local function lootMaster()
  if not (C_PartyInfo and C_PartyInfo.GetLootMethod) then return nil end
  local method, partyIndex, raidIndex = C_PartyInfo.GetLootMethod()
  if method ~= "master" and not (Enum and Enum.LootMethod and method == Enum.LootMethod.Masterlooter) then
    return nil
  end
  if partyIndex == 0 then return UnitName("player") end
  if IsInRaid() then return raidIndex and raidIndex > 0 and (GetRaidRosterInfo(raidIndex)) or nil end
  return partyIndex and UnitName("party" .. partyIndex)
end

-- Who chose: "you", or the officer's name, marked when they are the loot master.
local function chooser(name)
  if name == UnitName("player") then return "you" end
  if not name then return "an officer" end
  local master = lootMaster()
  local tag = master and bare(master) == bare(name) and " (loot master)" or ""
  return plain(name) .. tag
end
-- A note bar: a tinted strip of text, green (good), amber (warn) or red (bad).
local function newNote(parent)
  local note = CreateFrame("Frame", nil, parent)
  note:SetWidth(CONTENT_WIDTH)
  note.background = note:CreateTexture(nil, "BACKGROUND")
  note.background:SetAllPoints()
  note.text = newText(note, "GameFontHighlightSmall")
  note.text:SetPoint("TOPLEFT", note, "TOPLEFT", 6, -5)
  note.text:SetWidth(CONTENT_WIDTH - 12)
  note.text:SetJustifyH("LEFT")
  return note
end

local function setNote(note, kind, text)
  local c = NOTE_COLORS[kind]
  note.kind = kind
  note.background:SetColorTexture(c[1], c[2], c[3], 1)
  note.text:SetText(text)
  note:SetHeight(note.text:GetStringHeight() + 10)
end

-- The status bar's kind and text: the selected raid and who chose it, or why there is none.
function UI.SyncStatus()
  local raids, status = ns.Raids.Status()
  local snapshot = ns.Raids.Get(status.activeRaid)
  if snapshot then
    local players, total = reserveCounts(snapshot)
    local awards = #ns.Raids.Awards(status.activeRaid)
    local how
    if sync.pasted and sync.pasted.raid == status.activeRaid and sync.pasted.at == status.at then
      how = "Chosen when you pasted its reserves at " .. clock(status.at) .. "."
    else
      how = "Chosen by " .. chooser(status.chosenBy) .. " at " .. clock(status.at)
        .. ". Awards from this group go to this raid."
    end
    return "good", WHITE:format(raidName(snapshot)) .. " · " .. plural(players, "player", "players") .. " · "
      .. plural(total, "reserve", "reserves") .. " · " .. plural(awards, "award", "awards")
      .. "\n" .. how
  end
  if status.activeBy == "off" then
    local by = chooser(status.chosenBy)
    return "warn", "Not a guild run. The add-on is off for this group: no loot pop-up, no chat lines, "
      .. "nothing recorded. It turns back on when you leave the group.\n"
      .. (by == "you" and "You chose" or by .. " chose") .. " this at " .. clock(status.at) .. "."
  end
  if status.waiting then
    return "warn", "The chosen raid (" .. plain(status.code) .. ") isn't loaded here yet. Awards are held as "
      .. "\"no raid\" until it loads.\nChosen by " .. chooser(status.chosenBy) .. " at " .. clock(status.at)
      .. ". It applies here once the raid loads: from the helper at login or /reload, or by pasting its "
      .. "reserves below."
  end
  local gone = ns.Selection.Gone()
  if gone then
    return "warn", "No raid chosen. " .. goneName(gone) .. " has left the helper's list. Awards are held as "
      .. "\"no raid\" until a raid is chosen."
  end
  if #raids == 0 then
    return "warn", "No raids loaded. The pop-up still works, but every item is an open roll."
  end
  return "warn", "No raid chosen yet. Awards are held as \"no raid\" until you choose one."
end

local function whenText(raid)
  local now, ends = time(), raid.startsAt + raid.durationMin * 60
  if now < raid.startsAt then return "Starts " .. clock(raid.startsAt) end
  if now < ends then return "Under way since " .. clock(raid.startsAt) end
  return "Ended " .. clock(ends)
end

local function helperText(inbox)
  if inbox.present then
    return "|TInterface\\COMMON\\Indicator-Green:12|t Desktop helper in use: raid events read at "
      .. clock(inbox.readAt) .. " (they update at login or /reload), and awards go to the site live."
  end
  return "|TInterface\\COMMON\\Indicator-Gray:12|t Desktop helper not running: paste reserves in and copy "
    .. "awards out below."
end

-- Where the player is, under the raid table.
local function whereText()
  local name, kind, _, _, _, _, _, id = GetInstanceInfo()
  if kind == nil or kind == "none" then return "You're not in an instance." end
  return "You're in " .. plain(name) .. " (instance " .. tostring(id) .. ")."
end

local dialog

-- The confirmation dialog in the middle of the screen: a question, a line on what follows, and
-- two buttons. The second, or Escape, closes it and changes nothing.
local function confirm(question, hint, yes, no, onYes)
  dialog.text:SetText(question)
  dialog.hint:SetText(hint)
  for b, label in pairs({ [dialog.yes] = yes, [dialog.no] = no }) do
    b.label:SetText(label)
    b:SetWidth(math.max(90, b.label:GetStringWidth() + 24))
  end
  dialog.onYes = onYes
  dialog.yes:Show()
  dialog.no:ClearAllPoints()
  dialog.no:SetPoint("BOTTOMLEFT", dialog, "BOTTOM", 4, 14)
  dialog:Show()
end

-- The same dialog as a notice: its one button closes it.
local function notify(text, hint)
  confirm(text, hint, "", "OK", nil)
  dialog.yes:Hide()
  dialog.no:ClearAllPoints()
  dialog.no:SetPoint("BOTTOM", dialog, "BOTTOM", 0, 14)
end

-- The notice when the selected raid has left the helper's list. Choose a raid now (the raid
-- question, #53) is added with that question.
local function goneNotice(gone)
  local n = #ns.Raids.Awards(gone.raid)
  local kept = n == 0 and "It had no awards."
    or string.format("Its %s %s kept and still sent to the site.", plural(n, "award", "awards"),
      agree(n, "is", "are"))
  notify(WHITE:format(goneName(gone)) .. " has left the helper's list: it was cancelled or has ended.",
    kept .. " You'll be asked which raid it is when you next enter a raid instance.")
end

local function buildDialog()
  dialog = CreateFrame("Frame", "BureaucracyForeverDialog", UIParent)
  UI.dialog = dialog
  dialog:SetSize(440, 130)
  dialog:SetFrameStrata("DIALOG")
  dialog:EnableMouse(true)
  dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
  local background = dialog:CreateTexture(nil, "BACKGROUND")
  background:SetAllPoints()
  background:SetColorTexture(0, 0, 0, 0.92)
  dialog.text = newText(dialog, "GameFontHighlight")
  dialog.text:SetPoint("TOP", dialog, "TOP", 0, -18)
  dialog.text:SetWidth(400)
  dialog.hint = newText(dialog, "GameFontHighlightSmall")
  dialog.hint:SetPoint("TOP", dialog.text, "BOTTOM", 0, -8)
  dialog.hint:SetWidth(400)
  dialog.yes = newButton(dialog, "", 90)
  dialog.yes:SetPoint("BOTTOMRIGHT", dialog, "BOTTOM", -4, 14)
  dialog.yes:SetScript("OnClick", function()
    dialog:Hide()
    dialog.onYes()
  end)
  dialog.no = newButton(dialog, "", 90)
  dialog.no:SetPoint("BOTTOMLEFT", dialog, "BOTTOM", 4, 14)
  dialog.no:SetScript("OnClick", function() dialog:Hide() end)
  dialog:Hide()
  table.insert(UISpecialFrames, "BureaucracyForeverDialog")
end

-- Asks before moving the selection from current, which has awards, to raidId; Switch chooses it
-- (then runs after, if given) and Keep changes nothing.
local function askSwitch(raidId, current, after)
  local keep, n = plain(ns.Raids.Get(current).name), #ns.Raids.Awards(current)
  confirm("Switch the raid to " .. WHITE:format(raidName(ns.Raids.Get(raidId))) .. "?",
    string.format("You have %s for %s. %s with that raid and %s still sent to the site. Every officer in "
      .. "the group switches too.", plural(n, "award", "awards"), keep, agree(n, "It stays", "They stay"),
      agree(n, "is", "are")),
    "Switch", "Keep " .. keep, function()
      ns.Selection.ChooseRaid(raidId, true)
      if after then after() end
      UI.RefreshSync()
    end)
end

-- A row's choice: a raid id, or "off" for Not a guild run. Leaving a raid with awards asks first.
local function choose(choice)
  if choice == "off" then
    ns.Selection.ChooseOff()
  else
    local current = ns.Selection.Status().activeRaid
    local _, why = ns.Selection.ChooseRaid(choice)
    if why == "needs confirmation" then askSwitch(choice, current) end
  end
  UI.RefreshSync()
end

-- Notes the raid as chosen by this paste when the paste changed the selection to it.
local function notePasted(raidId, before)
  local status = ns.Selection.Status()
  if status.activeRaid == raidId and status.at ~= before then
    sync.pasted = { raid = raidId, at = status.at }
  end
end

-- Load: reads the pasted text, loads the raid and chooses it, asking first when the selected raid
-- has awards. A refused text changes nothing and stays in the box.
local function load()
  local held = ns.Selection.Status()
  local before, current = held.at, held.activeRaid
  local raidId, notice, waiting = ns.Selection.Paste(sync.box:GetText())
  if not raidId then
    local newer = notice:find("newer version of the add-on", 1, true) ~= nil
    if newer then
      notice = "This text needs a newer version of the add-on (you have " .. ns.version .. ")."
    end
    sync.result = { kind = "bad", link = newer,
      text = notice .. " Nothing was loaded; your raids are unchanged." }
  else
    sync.box:SetText("")
    sync.box:ClearFocus()
    local snapshot = ns.Raids.Get(raidId)
    sync.result = { kind = "good", text = "Loaded " .. raidName(snapshot) .. ". Copied from the site "
      .. clock(snapshot.generated) .. ", loaded " .. clock(time()) .. "."
      .. (notice and " " .. notice or "") }
    if waiting then
      askSwitch(raidId, current, function() notePasted(raidId, before) end)
    else
      notePasted(raidId, before)
    end
  end
  UI.RefreshSync()
  if sync.result.link then
    sync.link:SetFocus()
    sync.link:HighlightText()
  end
end

-- Remove: drops a pasted raid, asking first when it has awards (they stay saved).
local function remove(raidId)
  local snapshot, n = ns.Raids.Get(raidId), #ns.Raids.Awards(raidId)
  local _, why = ns.Raids.Remove(raidId)
  if why == "needs confirmation" then
    confirm("Remove " .. WHITE:format(raidName(snapshot)) .. "?",
      string.format("Its %s %s saved.", plural(n, "award", "awards"),
        agree(n, "stays", "stay")), "Remove", "Cancel",
      function()
        ns.Raids.Remove(raidId, true)
        UI.RefreshSync()
      end)
  end
  UI.RefreshSync()
end

local function showPlaceholder()
  if (sync.box:GetText() or "") == "" then sync.placeholder:Show() else sync.placeholder:Hide() end
end

-- Puts a piece y pixels down the tab (and x across), and shows it.
local function at(piece, y, x)
  piece:ClearAllPoints()
  piece:SetPoint("TOPLEFT", sync.child, "TOPLEFT", x or 0, -y)
  piece:Show()
end

-- The click target over a row of the raid table: choosing it chooses that row's raid (or off).
-- The selected row's is hidden, as choosing it again changes nothing.
local function drawPick(index, choice, y, height, on)
  local b = sync.picks[index]
  if not b then
    b = CreateFrame("Button", nil, sync.child)
    b:SetFrameLevel(sync.child:GetFrameLevel() + 1)
    b:SetScript("OnClick", function(self) choose(self.choice) end)
    sync.picks[index] = b
  end
  b.choice = choice
  b:SetSize(CONTENT_WIDTH, height)
  at(b, y - 4)
  if on then b:Hide() end
  return b
end

-- One row of the raid table: its choice, cells by column, and Remove for a pasted raid.
local function drawRaid(index, raid, y, on)
  local snapshot = ns.Raids.Get(raid.id)
  local players, total = reserveCounts(snapshot)
  local awards = #ns.Raids.Awards(raid.id)
  local pastedAt = raid.origin == "pasted" and "Pasted " .. clock(raid.loadedAt) or "Pasted"
  local row = {}
  for column, value in pairs({
    radio = RADIO[on],
    name = plain(raid.name) .. " " .. GREY:format(date("%a %d %b", raid.startsAt)),
    when = whenText(raid),
    instance = raid.instance and tostring(raid.instance) or AMBER:format("None"),
    counts = players .. " · " .. total,
    awards = awards > 0 and tostring(awards) or GREY:format("-"),
    pasted = raid.pasted and GREY:format(pastedAt) or "",
  }) do
    sync.cells[column] = sync.cells[column] or {}
    local text = cell(index, sync.cells[column], sync.child, "GameFontHighlightSmall")
    at(text, y, RAID_COLUMNS[column][1])
    text:SetWidth(RAID_COLUMNS[column][2])
    text:SetText(value)
    row[column] = text
  end
  if raid.pasted then
    local b = sync.removes[index]
    if not b then
      b = newButton(sync.child, "Remove", 60, 18)
      b:SetFrameLevel(sync.child:GetFrameLevel() + 2)
      b:SetScript("OnClick", function(self) remove(self.raidId) end)
      sync.removes[index] = b
    end
    b.raidId = raid.id
    at(b, y - 3, CONTENT_WIDTH - 62)
    row.remove = b
  end
  local height = math.max(row.name:GetStringHeight(), 14) + 8
  row.pick = drawPick(index, raid.id, y, height, on)
  return row, height
end

-- The loaded raids whose awards give copy-out text, with the text: { { raid, text }, ... }.
local function copyable(raids)
  local list = {}
  for _, raid in ipairs(raids) do
    local text = ns.Sync.CopyOut(raid.id)
    if text then list[#list + 1] = { raid = raid, text = text } end
  end
  return list
end

-- The count line's numbers from a copy-out text: an award is an A or R line, an undo a V or R
-- line (a replace is both); confirmations are not counted.
local function copyCounts(text)
  local awards, undos = 0, 0
  for kind in text:gmatch("\n(%u);") do
    if kind == "A" or kind == "R" then awards = awards + 1 end
    if kind == "V" or kind == "R" then undos = undos + 1 end
  end
  return awards, undos
end

-- The raid to copy: the one the officer picked, if it still gives text, else the selected raid if
-- it does, else nothing. Returns its entry in offered.
local function copyPicked(offered)
  local selected
  for _, entry in ipairs(offered) do
    if entry.raid.id == sync.copyPick then return entry end
    if entry.raid.id == ns.Selection.Status().activeRaid then selected = entry end
  end
  return selected
end

-- Picks the next raid that can be copied (the picker's button), wrapping round.
local function nextCopyPick()
  local offered = copyable((ns.Raids.Status()))
  local current = copyPicked(offered)
  local index = 0
  for i, entry in ipairs(offered) do
    if entry == current then index = i end
  end
  if offered[1] then sync.copyPick = offered[index % #offered + 1].raid.id end
  UI.RefreshSync()
end

-- Copy awards: shows the picked raid's text in the box, selected, for Ctrl+C.
local function copyOut()
  local picked = copyPicked(copyable((ns.Raids.Status())))
  if not picked then return UI.RefreshSync() end
  sync.copied = picked.raid.id
  UI.RefreshSync()
  sync.out:SetFocus()
  sync.out:HighlightText()
end

-- Draws Awards out at y; returns the new y.
local function drawAwardsOut(y, raids)
  local offered = copyable(raids)
  local picked = copyPicked(offered)
  if sync.copied and not (picked and sync.copied == picked.raid.id) then sync.copied = nil end

  at(sync.outHeading, y)
  y = y + 18
  at(sync.outHint, y)
  y = y + sync.outHint:GetStringHeight() + 6
  if sync.copied then
    at(sync.outNote, y)
    y = y + 18
    at(sync.outScroll, y)
    sync.outText = picked.text
    sync.out:SetText(picked.text)
    y = y + 46
  end
  if #offered > 0 then
    at(sync.outRaidLabel, y + 4)
    at(sync.outPick, y, 40)
    sync.outPick.label:SetText(picked and plain(picked.raid.name) or "Choose a raid")
  end
  local x = #offered > 0 and 290 or 0
  at(sync.copy, y, x)
  if picked then sync.copy:Enable() else sync.copy:Disable() end
  at(sync.outCount, y + 5, x + 90)
  if picked then
    local awards, undos = copyCounts(picked.text)
    sync.outCount:SetText(plural(awards, "award", "awards") .. ", " .. plural(undos, "undo", "undos")
      .. ". Practice awards are never included.")
  else
    sync.outCount:SetText(#offered > 0 and "Choose a raid to copy." or "Nothing to copy yet.")
  end
  return y + 30
end

-- Draws the tab: the status bar, the raid table, the helper line and the paste box with its result.
function UI.RefreshSync()
  if not sync.child or not window:IsShown() or not UI.tabs.Sync:IsShown() then return end
  local raids, status, inbox = ns.Raids.Status()
  for _, pool in pairs(sync.cells) do
    for _, text in ipairs(pool) do text:Hide() end
  end
  local optional = { sync.columns, sync.selected, sync.offRadio, sync.offLabel, sync.where, sync.whereHint,
    sync.resultNote, sync.linkLabel, sync.link, sync.linkHint, sync.outHeading, sync.outHint, sync.outNote,
    sync.outScroll, sync.outRaidLabel, sync.outPick, sync.copy, sync.outCount }
  for _, piece in ipairs(optional) do
    piece:Hide()
  end
  for _, b in pairs(sync.removes) do b:Hide() end -- keyed by row, with gaps for raids not pasted
  for _, b in ipairs(sync.picks) do b:Hide() end

  local y = 0
  at(sync.status, y)
  setNote(sync.status, UI.SyncStatus())
  y = y + sync.status:GetHeight() + 8
  at(sync.raidsHeading, y)
  y = y + 18
  sync.rows = {}
  if #raids > 0 then
    at(sync.columns, y)
    y = y + 18
    for i, raid in ipairs(raids) do
      local on = raid.id == status.activeRaid
      local row, height = drawRaid(i, raid, y, on)
      if on then
        at(sync.selected, y - 4)
        sync.selected:SetHeight(height)
        row.selected = true
      end
      sync.rows[i] = row
      y = y + height
    end
    -- Not a guild run, as the table's last row.
    local off = status.activeBy == "off"
    at(sync.offRadio, y, RAID_COLUMNS.radio[1])
    sync.offRadio:SetText(RADIO[off])
    at(sync.offLabel, y, RAID_COLUMNS.name[1])
    sync.offPick = drawPick(#raids + 1, "off", y, 22, off)
    if off then
      at(sync.selected, y - 4)
      sync.selected:SetHeight(22)
    end
    y = y + 22
    at(sync.where, y)
    sync.where:SetText(whereText())
    at(sync.whereHint, y)
    y = y + 18
  end
  at(sync.helper, y + 2)
  sync.helper:SetText(helperText(inbox))
  y = y + 24
  at(sync.inHeading, y)
  y = y + 18
  at(sync.inHint, y)
  y = y + sync.inHint:GetStringHeight() + 6
  at(sync.boxScroll, y)
  showPlaceholder()
  y = y + 48
  at(sync.load, y)
  y = y + 30
  if sync.result then
    at(sync.resultNote, y)
    setNote(sync.resultNote, sync.result.kind, sync.result.text)
    y = y + sync.resultNote:GetHeight() + 6
    if sync.result.link then
      at(sync.linkLabel, y + 4)
      at(sync.link, y, 90)
      y = y + 24
      at(sync.linkHint, y)
      y = y + 16
    end
  end
  y = drawAwardsOut(y + 8, raids)
  sync.child:SetHeight(y)
end

local function buildSync(content)
  content.placeholder:Hide()
  sync.cells, sync.removes, sync.rows, sync.picks = {}, {}, {}, {}
  sync.scroll = CreateFrame("ScrollFrame", nil, content)
  sync.scroll:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
  sync.scroll:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
  sync.child = CreateFrame("Frame", nil, sync.scroll)
  sync.child:SetSize(CONTENT_WIDTH, 1)
  sync.scroll:SetScrollChild(sync.child)
  sync.scroll:EnableMouseWheel(true)
  sync.scroll:SetScript("OnMouseWheel", scrollByWheel)

  sync.status = newNote(sync.child)
  sync.raidsHeading = newText(sync.child, "GameFontNormal")
  sync.raidsHeading:SetText("Raid events")
  sync.columns = CreateFrame("Frame", nil, sync.child)
  sync.columns:SetSize(CONTENT_WIDTH, 16)
  sync.headings = {}
  for column, label in pairs(RAID_HEADINGS) do
    local text = newText(sync.columns, "GameFontNormalSmall")
    text:SetPoint("TOPLEFT", sync.columns, "TOPLEFT", RAID_COLUMNS[column][1], 0)
    text:SetWidth(RAID_COLUMNS[column][2])
    text:SetJustifyH("LEFT")
    text:SetText(label)
    sync.headings[column] = text
  end
  -- The selected raid's row is highlighted, like the selected tab.
  sync.selected = sync.child:CreateTexture(nil, "BACKGROUND")
  sync.selected:SetWidth(CONTENT_WIDTH)
  sync.selected:SetColorTexture(0.25, 0.2, 0.05, 1)

  local function line(fontName, text)
    local piece = newText(sync.child, fontName)
    piece:SetWidth(CONTENT_WIDTH)
    piece:SetJustifyH("LEFT")
    piece:SetText(text)
    return piece
  end
  sync.offRadio = newText(sync.child, "GameFontHighlightSmall")
  sync.offLabel = line("GameFontHighlightSmall", OFF_LABEL)
  sync.offLabel:SetWidth(CONTENT_WIDTH - RAID_COLUMNS.name[1])
  sync.where = line("GameFontHighlightSmall")
  sync.whereHint = line("GameFontHighlightSmall",
    "Choosing another raid changes it for every officer in the group.")
  sync.whereHint:SetJustifyH("RIGHT")
  sync.helper = line("GameFontHighlightSmall")
  sync.inHeading = line("GameFontNormal", "Reserves in")
  sync.inHint = line("GameFontHighlightSmall", "On the guild site, open the raid and choose "
    .. WHITE:format("Copy reserves") .. ". Paste it here with Ctrl+V (Cmd+V on Mac). "
    .. "Pasting chooses that raid for the group.")

  -- The paste box: an edit box in a scroll frame, so a long text stays inside it.
  sync.boxScroll = CreateFrame("ScrollFrame", nil, sync.child)
  sync.boxScroll:SetSize(CONTENT_WIDTH, 40)
  sync.boxScroll:EnableMouse(true)
  local boxBackground = sync.boxScroll:CreateTexture(nil, "BACKGROUND")
  boxBackground:SetAllPoints()
  boxBackground:SetColorTexture(0, 0, 0, 0.6)
  sync.box = CreateFrame("EditBox", nil, sync.boxScroll)
  sync.box:SetMultiLine(true)
  sync.box:SetAutoFocus(false)
  sync.box:SetMaxLetters(0)
  sync.box:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
  sync.box:SetWidth(CONTENT_WIDTH - 12)
  sync.box:SetTextInsets(6, 6, 4, 4)
  sync.box:SetScript("OnEscapePressed", sync.box.ClearFocus)
  sync.box:SetScript("OnTextChanged", showPlaceholder)
  sync.boxScroll:SetScrollChild(sync.box)
  sync.boxScroll:SetScript("OnMouseDown", function() sync.box:SetFocus() end)
  sync.placeholder = newText(sync.box, "GameFontDisable")
  sync.placeholder:SetPoint("TOPLEFT", sync.box, "TOPLEFT", 6, -4)
  sync.placeholder:SetText("Paste the reserves text here")
  sync.load = newButton(sync.child, "Load", 80)
  sync.load:SetScript("OnClick", load)

  sync.resultNote = newNote(sync.child)
  sync.linkLabel = line("GameFontHighlightSmall", "Download link:")
  sync.linkLabel:SetWidth(86)
  -- The download link, in a box so it can be copied; typing in it puts the link back.
  sync.link = CreateFrame("EditBox", nil, sync.child)
  sync.link:SetAutoFocus(false)
  sync.link:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
  sync.link:SetSize(CONTENT_WIDTH - 90, 20)
  sync.link:SetText(RELEASES)
  sync.link:SetScript("OnTextChanged", function(self, typed)
    if typed then
      self:SetText(RELEASES)
      self:HighlightText()
    end
  end)
  sync.link:SetScript("OnEscapePressed", sync.link.ClearFocus)
  sync.linkHint = line("GameFontHighlightSmall",
    "Press Ctrl+C to copy the link, open it in your browser, replace the add-on folder, then /reload.")
  -- Awards out: the raid picker (a button that steps through the raids with text to copy), Copy
  -- awards, and the box that shows the text selected.
  sync.outHeading = line("GameFontNormal", "Awards out")
  sync.outHint = line("GameFontHighlightSmall", "Paste the text into " .. WHITE:format("Import awards")
    .. " on the raid's page on the guild site.")
  sync.outNote = line("GameFontHighlightSmall", "The text is selected: press Ctrl+C (Cmd+C on Mac).")
  sync.outScroll = CreateFrame("ScrollFrame", nil, sync.child)
  sync.outScroll:SetSize(CONTENT_WIDTH, 40)
  local outBackground = sync.outScroll:CreateTexture(nil, "BACKGROUND")
  outBackground:SetAllPoints()
  outBackground:SetColorTexture(0, 0, 0, 0.6)
  -- Read only: typing in it puts the text back.
  sync.out = CreateFrame("EditBox", nil, sync.outScroll)
  sync.out:SetMultiLine(true)
  sync.out:SetAutoFocus(false)
  sync.out:SetMaxLetters(0)
  sync.out:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
  sync.out:SetWidth(CONTENT_WIDTH - 12)
  sync.out:SetTextInsets(6, 6, 4, 4)
  sync.out:SetScript("OnEscapePressed", sync.out.ClearFocus)
  sync.out:SetScript("OnTextChanged", function(self, typed)
    if typed then
      self:SetText(sync.outText)
      self:HighlightText()
    end
  end)
  sync.outScroll:SetScrollChild(sync.out)
  sync.outRaidLabel = line("GameFontHighlightSmall", "Raid:")
  sync.outRaidLabel:SetWidth(36)
  sync.outPick = newButton(sync.child, "", 240, 22)
  sync.outPick:SetScript("OnClick", nextCopyPick)
  sync.copy = newButton(sync.child, "Copy awards", 90)
  sync.copy:SetScript("OnClick", copyOut)
  sync.outCount = line("GameFontHighlightSmall")
  sync.outCount:SetWidth(CONTENT_WIDTH - 380)
end

local function build()
  window = CreateFrame("Frame", "BureaucracyForeverWindow", UIParent, "BasicFrameTemplateWithInset")
  UI.window = window
  window:SetSize(WIDTH, HEIGHT)
  window:SetFrameStrata("HIGH")
  window:SetMovable(true)
  window:EnableMouse(true)
  window:SetClampedToScreen(true)
  window:RegisterForDrag("LeftButton")
  window:SetScript("OnDragStart", window.StartMoving)
  window:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    saveWindowSpot()
  end)
  -- Escape closes it, like the game's own windows.
  table.insert(UISpecialFrames, "BureaucracyForeverWindow")

  local title = window.TitleText or (window.TitleContainer and window.TitleContainer.TitleText)
  if not title then
    title = newText(window, "GameFontNormal")
    title:SetPoint("TOP", window, "TOP", 0, -5)
  end
  title:SetText("Bureaucracy Forever")

  -- The footer is the strip along the bottom, shared by all tabs.
  UI.footer = CreateFrame("Frame", nil, window)
  UI.footer:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 12, 10)
  UI.footer:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -12, 10)
  UI.footer:SetHeight(24)

  local previous
  for index, name in ipairs(TAB_NAMES) do
    -- Drawn by hand, not from a template: the client's tab templates differ by version.
    local tab = CreateFrame("Button", "BureaucracyForeverWindowTab" .. index, window)
    tab:SetSize(90, 24)
    tab.background = tab:CreateTexture(nil, "BACKGROUND")
    tab.background:SetAllPoints()
    tab.label = newText(tab, "GameFontNormal")
    tab.label:SetPoint("CENTER")
    tab.label:SetText(name)
    UI.tabButtons[name] = tab
    if previous then
      tab:SetPoint("LEFT", previous, "RIGHT", 4, 0)
    else
      tab:SetPoint("TOPLEFT", window, "BOTTOMLEFT", 11, 0)
    end
    tab:SetScript("OnClick", function() UI.Select(name) end)
    previous = tab

    local content = CreateFrame("Frame", nil, window)
    content:SetPoint("TOPLEFT", window, "TOPLEFT", 12, -28)
    content:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -12, 38)
    local placeholder = newText(content, "GameFontDisable")
    placeholder:SetPoint("CENTER")
    placeholder:SetText("Nothing here yet.")
    content.placeholder = placeholder
    UI.tabs[name] = content
    if name == "Reserves" then buildReserves(content) end
    if name == "Sync" then buildSync(content) end
  end
  buildDialog()
  UI.Select(TAB_NAMES[1])

  placeWindow()
  window:Hide()
  -- Set after the first Hide, which isn't the officer closing it.
  window:SetScript("OnHide", function() saved().shown = false end)
  window:SetScript("OnShow", function()
    saved().shown = true
    UI.RefreshReserves()
    UI.RefreshSync()
  end)
end

function UI.Toggle()
  if window:IsShown() then window:Hide() else window:Show() end
end

-- The tooltip's raid line: the selected raid's name, or why there is none.
function UI.RaidLine()
  local raids, status = ns.Raids.Status()
  local snapshot = ns.Raids.Get(status.activeRaid)
  if snapshot then return raidName(snapshot) end
  if status.activeBy == "off" then return "Not a guild run." end
  if #raids == 0 then return "No raids loaded." end
  return "No raid chosen yet."
end

-- The tooltip's lines: { text, kind } with kind "title", "text", "warning" or "hint".
function UI.TooltipLines()
  local lines = {
    { "Bureaucracy Forever", "title" },
    { UI.RaidLine(), "text" },
  }
  local count = #ns.Tracking.Pending()
  if count > 0 then
    local noun = count == 1 and " hand-out" or " hand-outs"
    lines[#lines + 1] = { count .. noun .. " not confirmed", "warning" }
  end
  lines[#lines + 1] = { "Click: open the window", "hint" }
  lines[#lines + 1] = { "Drag: move the button", "hint" }
  return lines
end

local COLORS = {
  title = { 1, 1, 1 }, text = { 1, 1, 1 }, warning = { 1, 0.6, 0.1 }, hint = { 0.7, 0.7, 0.7 },
}

local function showTooltip(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  for _, line in ipairs(UI.TooltipLines()) do
    local c = COLORS[line[2]]
    GameTooltip:AddLine(line[1], c[1], c[2], c[3])
  end
  GameTooltip:Show()
end

-- The badge shows the not-confirmed count, and is hidden at zero.
function UI.RefreshBadge()
  if not button then return end
  local count = #ns.Tracking.Pending()
  badge.text:SetText(count)
  if count > 0 then badge:Show() else badge:Hide() end
end

local function buttonAngle()
  local angle = read().minimap and read().minimap.angle
  return isNumber(angle) and angle or DEFAULT_ANGLE
end

local function placeButton(angle)
  local radius = Minimap:GetWidth() / 2 + 5
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function followCursor()
  local cursorX, cursorY = GetCursorPosition()
  local scale = Minimap:GetEffectiveScale()
  local centerX, centerY = Minimap:GetCenter()
  local angle = math.atan2(cursorY / scale - centerY, cursorX / scale - centerX)
  local ui = saved()
  ui.minimap = ui.minimap or {}
  ui.minimap.angle = angle
  placeButton(angle)
end

function UI.ShowMinimapButton(show)
  local ui = saved()
  ui.minimap = ui.minimap or {}
  ui.minimap.hidden = not show
  if show then button:Show() else button:Hide() end
end

local function buildButton()
  button = CreateFrame("Button", "BureaucracyForeverMinimapButton", Minimap)
  UI.button = button
  button:SetSize(31, 31)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel(8)
  button:RegisterForClicks("LeftButtonUp")
  button:RegisterForDrag("LeftButton")
  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
  icon:SetSize(20, 20)
  icon:SetPoint("CENTER")
  local ring = button:CreateTexture(nil, "OVERLAY")
  ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  ring:SetSize(53, 53)
  ring:SetPoint("TOPLEFT")

  badge = CreateFrame("Frame", nil, button)
  UI.badge = badge
  badge:SetSize(14, 14)
  badge:SetPoint("TOPRIGHT", 4, 4)
  badge:SetFrameLevel(button:GetFrameLevel() + 3)
  local dot = badge:CreateTexture(nil, "BACKGROUND")
  dot:SetTexture("Interface\\COMMON\\Indicator-Red")
  dot:SetAllPoints()
  badge.text = newText(badge, "GameFontHighlightSmall")
  badge.text:SetPoint("CENTER")

  button:SetScript("OnClick", function() UI.Toggle() end)
  button:SetScript("OnEnter", function(self)
    UI.RefreshBadge()
    showTooltip(self)
  end)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)
  button:SetScript("OnDragStart", function(self)
    GameTooltip:Hide()
    self:SetScript("OnUpdate", followCursor)
  end)
  button:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
    followCursor()
  end)

  placeButton(buttonAngle())
  if read().minimap and read().minimap.hidden then button:Hide() end
  UI.RefreshBadge()
end

ns.On("ADDON_LOADED", function(name)
  if name ~= ns.name then return end
  local wasShown = read().shown
  build()
  buildButton()
  hookTooltips()
  if wasShown then window:Show() end
  -- The inbox, read just before, may have taken the selected raid off the list.
  local gone, now = ns.Selection.Gone()
  if now then goneNotice(gone) end
end)

for _, event in ipairs({ "confirmed", "unconfirmed", "late" }) do
  ns.Tracking.On(event, UI.RefreshBadge)
end
