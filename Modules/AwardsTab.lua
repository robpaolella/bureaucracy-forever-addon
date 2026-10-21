-- The Awards tab and the footer's loot master line (#14): the selected raid's awards, grouped by
-- boss, read only. A not confirmed row has three buttons: for the loot master they are the pop-up's
-- three choices (#101), with its Give to someone else list and refusal text; another officer sees
-- them greyed. Draws into UI.tabs.Awards and UI.footer.
local _, ns = ...

local UI = ns.UI
local parts = UI.parts
local newText, newButton = parts.newText, parts.newButton
local bare = ns.Rules.Bare
local PopupFrame = ns.PopupFrame

local CONTENT_WIDTH = 616
local COLUMNS = { time = { 0, 44 }, item = { 48, 190 }, winner = { 242, 170 }, how = { 416, 96 },
  roll = { 514, 30 }, note = { 548, 68 } } -- x and width
local ROW_GAP, HEADING_HEIGHT, BUTTON_HEIGHT = 4, 22, 20
local AMBER, GREY = "|cffffa000%s|r", "|cff808080%s|r"
local HOW = { HR = "Hard reserve", SR = "Soft reserve", OPEN_ROLL = "Open roll",
  DISENCHANT_BANK = "Disenchant/bank" }
local BANNER = "Only the loot master (%s) can change awards."
local EMPTY_TITLE = "No awards yet this raid"
local EMPTY_HINT = "Items you hand out with the pop-up, or from the game's loot menu, show up here "
  .. "with the time, boss, winner and how they won."
local BUTTONS = { "Try again", "Someone else", "Not handed out" }

local tab = {} -- the tab's pieces
UI.awards = tab

local function plain(text) return (tostring(text):gsub("|", "||")) end

local function plural(count, one, many)
  return count .. " " .. (count == 1 and one or many)
end

local function bossName(snapshot, id)
  if id == nil then return "Other" end
  for _, boss in ipairs(snapshot and snapshot.bosses or {}) do
    if boss.id == id then return plain(boss.name) end
  end
  return plain(id)
end

-- The loot master's name and whether that is the player; nil when master loot is off.
local function master()
  local name = parts.lootMaster()
  if not name then return nil, false end
  return name, bare(name) == bare(UnitName("player"))
end

-- The footer's line: who the loot master is, or that there is none.
function UI.LootMasterLine()
  local name, me = master()
  if not name then return "No loot master (master loot is off)" end
  return "Loot master: " .. plain(name) .. (me and " (you)" or "")
end

local function row(snapshot, award)
  return { key = award.key, time = date("%H:%M", award.at), practiceTime = date("%a %H:%M", award.at),
    boss = bossName(snapshot, award.boss), item = parts.itemText(award.item), winner = plain(award.char),
    how = HOW[award.method] or plain(award.method), roll = award.roll,
    notConfirmed = award.state == "not-confirmed" and not award.voided,
    voided = award.voided and true or false,
    note = award.voided and (award.voidReason and plain(award.voidReason)
      or ("Undone " .. date("%H:%M", award.voidedAt or award.at))) or nil,
    at = award.at }
end

local function byTime(a, b) return a.at < b.at end

-- What the tab shows: { empty = true } with nothing to list; otherwise { summary, banner (for
-- another officer), readOnly, groups = { { heading, rows } }, practice = { heading, rows } or nil }.
-- A row has its award's `key`. A not confirmed row has `notConfirmed`, and for the loot master
-- `choices` (Popup.Choices); a voided one `voided` and its `note`.
function UI.AwardsView()
  local raidId = ns.Selection.Status().activeRaid
  local snapshot = ns.Raids.Get(raidId)
  local rows, practice, order, byBoss = {}, {}, {}, {}
  local name, me = master()
  for _, award in ipairs(ns.Raids.Awards(raidId)) do
    local r = row(snapshot, award)
    if me and r.notConfirmed then r.choices = ns.Popup.Choices(r.key) end
    if award.practice then practice[#practice + 1] = r else rows[#rows + 1] = r end
  end
  local view = { readOnly = not me, banner = name and not me and BANNER:format(plain(name)) or nil }
  if #rows == 0 and #practice == 0 then
    view.empty = true
    return view
  end
  table.sort(rows, byTime)
  local standing, unconfirmed = 0, 0
  for _, r in ipairs(rows) do
    if not r.voided then standing = standing + 1 end
    if r.notConfirmed then unconfirmed = unconfirmed + 1 end
    local group = byBoss[r.boss]
    if not group then
      group = { boss = r.boss, rows = {} }
      byBoss[r.boss] = group
      order[#order + 1] = group
    end
    group.rows[#group.rows + 1] = r
  end
  for _, group in ipairs(order) do
    group.heading = group.boss .. " · " .. plural(#group.rows, "item", "items")
  end
  view.groups = order
  local counts = {}
  if standing > 0 then counts[#counts + 1] = plural(standing, "award", "awards") end
  if unconfirmed > 0 then counts[#counts + 1] = unconfirmed .. " not confirmed" end
  view.summary = table.concat(counts, " · ")
  if #practice > 0 then
    table.sort(practice, byTime)
    view.practice = { heading = "Practice awards (" .. #practice .. ") · never sent to the guild site",
      rows = practice }
  end
  return view
end

local function cell(index, pool, fontName)
  local text = pool[index]
  if not text then
    text = newText(tab.child, fontName)
    text:SetJustifyH("LEFT")
    pool[index] = text
  end
  text:ClearAllPoints()
  text:Show()
  return text
end

local function put(text, column, y, value)
  text:SetPoint("TOPLEFT", tab.child, "TOPLEFT", COLUMNS[column][1], -y)
  text:SetWidth(COLUMNS[column][2])
  text:SetText(value)
end

-- The three change buttons of a not confirmed row: greyed, with nothing behind them.
local function greyButton(index, x, y)
  local b = tab.buttons[index]
  if not b then
    b = newButton(tab.child, BUTTONS[(index - 1) % 3 + 1], 86, BUTTON_HEIGHT)
    b:Disable()
    b.background:SetColorTexture(0.2, 0.2, 0.2, 1)
    b.label:SetTextColor(0.5, 0.5, 0.5)
    tab.buttons[index] = b
  end
  b:ClearAllPoints()
  b:SetPoint("TOPLEFT", tab.child, "TOPLEFT", x, -y)
  b:Show()
end

-- The loot master's click on one of a not confirmed row's choices: Give to someone else opens or
-- closes its list (one open at a time); the others act at once. The row then shows its new state.
local function choose(key, action)
  if action == "giveelse" then
    tab.elseOpen = tab.elseOpen ~= key and key or nil
  else
    ns.Popup.Choose(key, action)
  end
  UI.RefreshAwards()
end

-- The loot master's three buttons of a not confirmed row: the pop-up's choices, a greyed one
-- showing why when hovered.
local function choiceButton(index, x, y, key, choice)
  local b = tab.choices[index]
  if not b then
    b = PopupFrame.TipButton(tab.child, 86)
    b:SetScript("OnClick", function(self)
      if self.choice.enabled then choose(self.key, self.choice.action) end
    end)
    tab.choices[index] = b
  end
  PopupFrame.SetButton(b, BUTTONS[(index - 1) % 3 + 1], choice.enabled)
  b.key, b.choice, b.tip = key, choice, choice.tooltip
  b:ClearAllPoints()
  b:SetPoint("TOPLEFT", tab.child, "TOPLEFT", x, -y)
  b:Show()
end

-- Why the last choice on the row was refused, in the pop-up's words. Returns the new y.
local function refusal(index, y, text)
  local line = tab.refusals[index]
  if not line then
    line = newText(tab.child, "GameFontHighlightSmall")
    line:SetJustifyH("LEFT")
    line:SetTextColor(1, 0.35, 0.35)
    line:SetWidth(CONTENT_WIDTH - COLUMNS.item[1])
    tab.refusals[index] = line
  end
  line:ClearAllPoints()
  line:SetPoint("TOPLEFT", tab.child, "TOPLEFT", COLUMNS.item[1], -y)
  line:SetText(text)
  line:Show()
  return y + line:GetStringHeight() + ROW_GAP
end

local function strike(index, y)
  local line = tab.strikes[index]
  if not line then
    line = tab.child:CreateTexture(nil, "OVERLAY")
    line:SetColorTexture(0.5, 0.5, 0.5, 1)
    tab.strikes[index] = line
  end
  line:ClearAllPoints()
  line:SetPoint("TOPLEFT", tab.child, "TOPLEFT", COLUMNS.item[1], -(y + 7))
  line:SetSize(COLUMNS.how[1] + COLUMNS.how[2] - COLUMNS.item[1], 1)
  line:Show()
end

local function hideAll(pools)
  for _, pool in ipairs(pools) do
    for _, piece in ipairs(pool) do piece:Hide() end
  end
end

-- Draws one award row at y; returns the new y.
local function drawRow(r, y, used, practice)
  used.rows = used.rows + 1
  local i = used.rows
  local grey = r.voided
  local function colour(value) return grey and GREY:format(value) or value end
  local shown = { time = cell(i, tab.times, "GameFontHighlightSmall"),
    item = cell(i, tab.items, "GameFontHighlightSmall"),
    winner = cell(i, tab.winners, "GameFontHighlightSmall"),
    how = cell(i, tab.hows, "GameFontHighlightSmall"),
    roll = cell(i, tab.rolls, "GameFontHighlightSmall"),
    note = cell(i, tab.notes, "GameFontDisableSmall") }
  put(shown.time, "time", y, GREY:format(practice and r.practiceTime or r.time))
  put(shown.item, "item", y, colour(r.item))
  put(shown.winner, "winner", y,
    colour(r.winner) .. (r.notConfirmed and " " .. AMBER:format("NOT CONFIRMED") or ""))
  put(shown.how, "how", y, colour(r.how))
  put(shown.roll, "roll", y, r.roll and colour(tostring(r.roll)) or "")
  put(shown.note, "note", y, r.note or (practice and AMBER:format("Practice")) or "")
  local line = { time = shown.time, item = shown.item, winner = shown.winner,
    how = shown.how, roll = shown.roll, note = shown.note, voided = r.voided, notConfirmed = r.notConfirmed }
  tab.shown[#tab.shown + 1] = line
  if r.voided then
    used.strikes = used.strikes + 1
    strike(used.strikes, y)
  end
  y = y + math.max(shown.item:GetStringHeight(), shown.winner:GetStringHeight(),
    shown.how:GetStringHeight()) + ROW_GAP
  local choices = r.notConfirmed and r.choices
  if choices and tab.elseOpen == r.key then
    -- Give to someone else's list, in the buttons' place, as the pop-up draws it.
    tab.listShown = true
    tab.listKey = r.key
    line.list = tab.list
    y = PopupFrame.DrawList(tab.list, choices.list, COLUMNS.item[1], y) - 8 + ROW_GAP
  elseif choices then
    line.choices = {}
    for n = 1, 3 do
      used.choices = used.choices + 1
      choiceButton(used.choices, COLUMNS.item[1] + (n - 1) * 90, y, r.key, choices.buttons[n])
      line.choices[n] = tab.choices[used.choices]
    end
    y = y + BUTTON_HEIGHT + ROW_GAP
  elseif r.notConfirmed then
    for n = 1, 3 do
      used.buttons = used.buttons + 1
      greyButton(used.buttons, COLUMNS.item[1] + (n - 1) * 90, y)
    end
    y = y + BUTTON_HEIGHT + ROW_GAP
  end
  if choices and choices.refusal then
    used.refusals = used.refusals + 1
    y = refusal(used.refusals, y, choices.refusal)
    line.refusal = tab.refusals[used.refusals]
  end
  return y
end

local function drawHeading(text, y, used)
  used.headings = used.headings + 1
  local heading = cell(used.headings, tab.headings, "GameFontNormal")
  heading:SetPoint("TOPLEFT", tab.child, "TOPLEFT", 0, -y)
  heading:SetText(text)
  tab.shown[#tab.shown + 1] = { heading = heading }
  return y + HEADING_HEIGHT
end

local function setShown(pieces, on)
  for _, piece in ipairs(pieces) do
    if on then piece:Show() else piece:Hide() end
  end
end

-- The practice group's rows follow its heading only once the officer opens it.
local function drawPractice(view, y, used)
  used.headings = used.headings + 1
  local heading = cell(used.headings, tab.headings, "GameFontNormal")
  heading:SetPoint("TOPLEFT", tab.child, "TOPLEFT", 0, -y)
  heading:SetText((tab.practiceOpen and "- " or "+ ") .. view.practice.heading)
  tab.shown[#tab.shown + 1] = { heading = heading, practice = true }
  tab.practiceToggle:ClearAllPoints()
  tab.practiceToggle:SetPoint("TOPLEFT", tab.child, "TOPLEFT", 0, -y)
  tab.practiceToggle:SetSize(CONTENT_WIDTH, HEADING_HEIGHT)
  tab.practiceToggle:Show()
  y = y + HEADING_HEIGHT
  if tab.practiceOpen then
    for _, r in ipairs(view.practice.rows) do y = drawRow(r, y, used, true) end
  end
  return y
end

-- Draws the tab: the summary and list, or what will appear here.
function UI.RefreshAwards()
  if not tab.content then return end
  UI.RefreshFooter()
  if not UI.window:IsShown() or not UI.tabs.Awards:IsShown() then return end
  local view = UI.AwardsView()
  tab.view = view
  hideAll({ tab.headings, tab.times, tab.items, tab.winners, tab.hows, tab.rolls, tab.notes,
    tab.buttons, tab.choices, tab.refusals, tab.strikes })
  tab.list:Hide()
  tab.listShown = false
  tab.shown = {}
  tab.practiceToggle:Hide()
  local list = not view.empty
  setShown({ tab.summary, tab.columns, tab.scroll }, list)
  setShown({ tab.title, tab.hint }, not list)
  if view.banner then tab.banner:Show() tab.banner:SetText(view.banner) else tab.banner:Hide() end
  if list then
    tab.summary:SetText(view.summary)
    local used = { rows = 0, headings = 0, buttons = 0, choices = 0, refusals = 0, strikes = 0 }
    local y = 0
    for _, group in ipairs(view.groups or {}) do
      y = drawHeading(group.heading, y, used)
      for _, r in ipairs(group.rows) do y = drawRow(r, y, used) end
    end
    if view.practice then y = drawPractice(view, y + 6, used) end
    tab.child:SetHeight(y)
  end
  -- The list stays open only while its row is drawn and still not confirmed.
  if not tab.listShown then tab.elseOpen = nil end
end

-- The footer's loot master line, on every tab.
function UI.RefreshFooter()
  if tab.footer then tab.footer:SetText(UI.LootMasterLine()) end
end

local function scrollByWheel(self, delta)
  local to = self:GetVerticalScroll() - delta * 40
  self:SetVerticalScroll(math.max(0, math.min(to, self:GetVerticalScrollRange())))
end

local function build()
  local content = UI.tabs.Awards
  content.placeholder:Hide()
  tab.content = content
  tab.headings, tab.times, tab.items, tab.winners, tab.hows = {}, {}, {}, {}, {}
  tab.rolls, tab.notes, tab.buttons, tab.strikes, tab.shown = {}, {}, {}, {}, {}
  tab.choices, tab.refusals = {}, {}

  -- Another officer's view: a line above the list.
  tab.banner = newText(content, "GameFontNormal")
  tab.banner:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -2)
  tab.banner:Hide()
  tab.summary = newText(content, "GameFontHighlightSmall")
  tab.summary:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -20)
  tab.columns = CreateFrame("Frame", nil, content)
  tab.columns:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -36)
  tab.columns:SetSize(CONTENT_WIDTH, 16)
  local labels = { time = "Time", item = "Item", winner = "Winner", how = "How", roll = "Roll" }
  for column, label in pairs(labels) do
    local text = newText(tab.columns, "GameFontNormal")
    text:SetPoint("TOPLEFT", tab.columns, "TOPLEFT", COLUMNS[column][1] + 4, 0)
    text:SetText(label)
  end

  tab.scroll = CreateFrame("ScrollFrame", nil, content)
  tab.scroll:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -54)
  tab.scroll:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
  tab.child = CreateFrame("Frame", nil, tab.scroll)
  tab.child:SetSize(CONTENT_WIDTH, 1)
  tab.scroll:SetScrollChild(tab.child)
  tab.scroll:EnableMouseWheel(true)
  tab.scroll:SetScript("OnMouseWheel", scrollByWheel)
  -- Give to someone else's list, the pop-up's own: a name's Give hands out and closes it.
  tab.list = PopupFrame.NewList(tab.child, function(char)
    if ns.Popup.Choose(tab.listKey, "giveelse", char) then tab.elseOpen = nil end
    UI.RefreshAwards()
  end, function()
    tab.elseOpen = nil
    UI.RefreshAwards()
  end)

  tab.title = newText(content, "GameFontNormal")
  tab.title:SetPoint("CENTER", content, "CENTER", 0, 30)
  tab.title:SetText(EMPTY_TITLE)
  tab.hint = newText(content, "GameFontDisable")
  tab.hint:SetPoint("TOP", tab.title, "BOTTOM", 0, -6)
  tab.hint:SetWidth(380)
  tab.hint:SetText(EMPTY_HINT)

  -- The practice group opens and closes on a click of its heading's strip.
  tab.practiceToggle = CreateFrame("Button", nil, tab.child)
  tab.practiceToggle:SetScript("OnClick", function()
    tab.practiceOpen = not tab.practiceOpen
    UI.RefreshAwards()
  end)

  tab.footer = newText(UI.footer, "GameFontHighlightSmall")
  tab.footer:SetPoint("LEFT", UI.footer, "LEFT", 0, 0)
  UI.RefreshAwards()
end

ns.On("ADDON_LOADED", function(name)
  if name == ns.name then build() end
end)

-- The footer follows the loot method and the group; the list follows the group's changes too, a
-- boss fight starting or ending (the choices that post a line wait) and the loot window (who can
-- receive; refusals clear when it closes).
for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "PARTY_LOOT_METHOD_CHANGED",
  "ADDON_RESTRICTION_STATE_CHANGED", "LOOT_OPENED", "LOOT_CLOSED" }) do
  ns.On(event, function() UI.RefreshAwards() end)
end
for _, event in ipairs({ "confirmed", "unconfirmed", "late" }) do
  ns.Tracking.On(event, function() UI.RefreshAwards() end)
end
