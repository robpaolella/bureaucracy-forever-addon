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
end

-- The Reserves tab and the item tooltips (#15): the selected raid's reserves, read only.
local TICK = "|TInterface\\Buttons\\UI-CheckBox-Check:12|t"
local GREY = "|cff808080%s|r"
local CONTENT_WIDTH = 616
local COLUMNS = { item = { 0, 206 }, hr = { 210, 176 }, sr = { 390, 226 } } -- x and width
local ROW_GAP, HEADING_HEIGHT = 4, 22

local function bare(name)
  return (name:gsub("%-.*$", ""))
end

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

local function namesText(holders)
  local parts = {}
  for i, holder in ipairs(holders) do parts[i] = nameText(holder) end
  return #parts > 0 and table.concat(parts, ", ") or GREY:format("-")
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
    if #items > 0 then groups[#groups + 1] = { boss = boss.name, items = items } end
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

-- What the Reserves tab shows. { empty = "no-raid" } with no selected raid loaded;
-- { empty = "no-reserves", raid = name } for a raid nobody reserved in; otherwise the header
-- line and each boss's rows, every row { item, hr, sr } (the item id and two lists of holders).
function UI.ReservesView()
  local raidId = ns.Selection.Status().activeRaid
  local snapshot = ns.Raids.Get(raidId)
  if not snapshot then return { empty = "no-raid" } end
  local users, total = {}, 0
  for _, holders in pairs(snapshot.reserves) do
    for _, h in ipairs(holders) do
      users[h.user] = true
      total = total + 1
    end
  end
  if total == 0 then return { empty = "no-reserves", raid = snapshot.name } end
  local players = 0
  for _ in pairs(users) do players = players + 1 end
  local awards, roster = allAwards(raidId, snapshot), rosterSet()
  local groups = {}
  for _, group in ipairs(reservedGroups(snapshot)) do
    local rows = {}
    for _, item in ipairs(group.items) do
      local hr, sr = holderLists(snapshot, item, awards, roster)
      rows[#rows + 1] = { item = item, hr = hr, sr = sr }
    end
    groups[#groups + 1] = { boss = group.boss, rows = rows }
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
    heading:SetText(group.boss)
    reserves.shown[#reserves.shown + 1] = { heading = heading }
    y = y + HEADING_HEIGHT
    for _, row in ipairs(group.rows) do
      rows = rows + 1
      local item = cell(rows, reserves.items, reserves.child, "GameFontHighlightSmall")
      local hr = cell(rows, reserves.hrs, reserves.child, "GameFontHighlightSmall")
      local sr = cell(rows, reserves.srs, reserves.child, "GameFontHighlightSmall")
      place(item, "item", y, itemText(row.item))
      place(hr, "hr", y, namesText(row.hr))
      place(sr, "sr", y, namesText(row.sr))
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
ns.On("GET_ITEM_INFO_RECEIVED", redrawSoon)

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
  reserves.scroll:SetScript("OnMouseWheel", function(self, delta)
    local to = self:GetVerticalScroll() - delta * 40
    self:SetVerticalScroll(math.max(0, math.min(to, self:GetVerticalScrollRange())))
  end)

  -- The empty state: what is missing, and a way to the Sync tab.
  reserves.title = newText(content, "GameFontNormal")
  reserves.title:SetPoint("CENTER", content, "CENTER", 0, 30)
  reserves.hint = newText(content, "GameFontDisable")
  reserves.hint:SetPoint("TOP", reserves.title, "BOTTOM", 0, -6)
  reserves.hint:SetWidth(380)
  reserves.toSync = CreateFrame("Button", nil, content)
  reserves.toSync:SetSize(90, 24)
  reserves.toSync:SetPoint("TOP", reserves.hint, "BOTTOM", 0, -12)
  local background = reserves.toSync:CreateTexture(nil, "BACKGROUND")
  background:SetAllPoints()
  background:SetColorTexture(0.35, 0.08, 0.08, 1)
  reserves.toSync.label = newText(reserves.toSync, "GameFontNormal")
  reserves.toSync.label:SetPoint("CENTER")
  reserves.toSync.label:SetText("Go to Sync")
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
  tooltip:AddLine("Hard: " .. namesText(hr), 1, 1, 1, true)
  tooltip:AddLine("Soft: " .. namesText(sr), 1, 1, 1, true)
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
  end
  UI.Select(TAB_NAMES[1])

  placeWindow()
  window:Hide()
  -- Set after the first Hide, which isn't the officer closing it.
  window:SetScript("OnHide", function() saved().shown = false end)
  window:SetScript("OnShow", function()
    saved().shown = true
    UI.RefreshReserves()
  end)
end

function UI.Toggle()
  if window:IsShown() then window:Hide() else window:Show() end
end

-- The tooltip's raid line. #16 replaces this once it connects the loaded raids.
function UI.RaidLine()
  return "No raids loaded."
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
end)

for _, event in ipairs({ "confirmed", "unconfirmed", "late" }) do
  ns.Tracking.On(event, UI.RefreshBadge)
end
