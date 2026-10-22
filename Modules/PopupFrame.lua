-- PopupFrame: draws the loot pop-up (#77) from the content model Popup.Build() makes (#10).
-- It opens on LOOT_OPENED for the loot master, closes on LOOT_CLOSED, and redraws when the officer
-- picks a boss, while a candidate's name is still loading, when a boss fight starts or ends and when
-- the game confirms a hand-out or gives up on it, and as each roll arrives (#90). Give hands out
-- (#38) and Call roll starts a roll-off (#13); then the row lists the rolls and Give follows the
-- name picked there. D/B (#39)
-- gives to the raid's pick in one click; a right-click or Shift-click, or a click with no pick yet,
-- opens the list to choose one. A hand-out the game didn't confirm shows its three choices (#95).
local _, ns = ...

local PopupFrame = {}
ns.PopupFrame = PopupFrame

local WIDTH, TEXT_WIDTH, PAD = 560, 380, 10
local ROW_MIN, RECHECK_SECONDS = 46, 1
local BOX_WIDTH = WIDTH - 2 * PAD - 40 -- the hand-out box, from the text column to the row's right
local BADGE_COLORS = {
  hr = { 0.85, 0.4, 0.1 }, sr = { 0.2, 0.55, 0.85 }, open = { 0.45, 0.45, 0.45 },
}
local NO_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local SPINNER = "Interface\\COMMON\\StreamCircle"
local GOLD = { 1, 0.82, 0 }
local PRACTICE_TAG = " · |cffffd100practice|r" -- the foot's practice mode tag (#17)
-- Game icons for the tick and the arrows: the game's font has no such characters.
local TICK = "Interface\\Buttons\\UI-CheckBox-Check"
local ARROW_DOWN = "|TInterface\\Buttons\\Arrow-Down-Up:12:12|t"
local ARROW_UP = "|TInterface\\Buttons\\Arrow-Up-Up:12:12|t"
local NC_WIDTHS = { 90, 150, 120 } -- the three choices of a not confirmed row
local DB_SHOWN = 12 -- names the D/B list shows at once; the wheel scrolls the rest

local frame, menu, dbList
local rows, entries, dbEntries = {}, {}, {} -- widgets reused from one draw to the next
local dbRow, dbOffset = nil, 0 -- the row whose D/B list is open, and how far it is scrolled
local generation = 0 -- bumped by every LOOT_OPENED and LOOT_CLOSED, so a stale wait does nothing
local open = false -- the loot window is open and the pop-up belongs to it
local elseOpen -- the award key whose Give to someone else list is open
local dismissed = false -- the officer closed the pop-up with its X; it stays shut for this loot window

-- A piece of text styled like a game font. If the client has no font by that name the text still
-- appears, in a plain font: a missing name must never stop the add-on loading.
local function newText(parent, fontName)
  local ok, text = pcall(parent.CreateFontString, parent, nil, "OVERLAY", fontName)
  if not (ok and text) then
    text = parent:CreateFontString(nil, "OVERLAY")
    text:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
  end
  text:SetJustifyH("LEFT")
  return text
end

-- A button drawn like the add-on's others: dark red, its label in the game's gold.
local function newButton(parent, width, height)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(width, height)
  b.background = b:CreateTexture(nil, "BACKGROUND")
  b.background:SetAllPoints()
  b.label = newText(b, "GameFontNormal")
  b.label:SetPoint("CENTER")
  return b
end

local function setButton(b, text, enabled)
  b.label:SetText(text)
  if enabled then
    b:Enable()
    b.background:SetColorTexture(0.35, 0.08, 0.08, 1)
    b.label:SetTextColor(1, 0.82, 0)
  else
    b:Disable()
    b.background:SetColorTexture(0.15, 0.15, 0.15, 1)
    b.label:SetTextColor(0.5, 0.5, 0.5)
  end
end

-- For the tests: the row widgets and the boss list's entries.
function PopupFrame.rows() return rows end
function PopupFrame.pickEntries() return entries end
function PopupFrame.dbEntries() return dbEntries end

local function build()
  -- The same standard window as the officers' window: the client confirmed this template.
  frame = CreateFrame("Frame", "BureaucracyForeverPopup", UIParent, "BasicFrameTemplateWithInset")
  PopupFrame.frame = frame
  frame:SetSize(WIDTH, 100)
  frame:SetPoint("CENTER", UIParent, "CENTER", 120, 0)
  frame:SetFrameStrata("DIALOG")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:SetClampedToScreen(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

  frame.title = frame.TitleText or (frame.TitleContainer and frame.TitleContainer.TitleText)
  if not frame.title then
    frame.title = newText(frame, "GameFontNormal")
    frame.title:SetPoint("TOP", frame, "TOP", 0, -5)
  end
  -- The template's own close button; without one the add-on draws its own.
  frame.close = frame.CloseButton
  if not frame.close then
    frame.close = newButton(frame, 20, 20)
    frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    setButton(frame.close, "X", true)
    frame.close:SetScript("OnClick", function() frame:Hide() end)
  end
  frame.close:HookScript("OnClick", function() dismissed = true end)

  frame.fight = newText(frame, "GameFontNormal")
  frame.fight:SetWidth(WIDTH - 2 * PAD)
  frame.notice = newText(frame, "GameFontNormal")
  frame.notice:SetWidth(WIDTH - 2 * PAD)
  frame.link = newButton(frame, 90, 16)
  frame.link:SetScript("OnClick", function()
    ns.UI.Select("Sync")
    local window = ns.UI.tabs.Sync:GetParent()
    if window and not window:IsShown() then window:Show() end
  end)
  frame.bossLabel = newText(frame, "GameFontNormal")
  frame.bossLabel:SetText("Boss:")
  frame.boss = newButton(frame, 140, 20)
  frame.count = newText(frame, "GameFontHighlightSmall")
  frame.foot = newText(frame, "GameFontHighlightSmall")
  frame.foot:SetWidth(WIDTH - 2 * PAD)

  -- The boss list drops from the boss button: its own title and one entry per boss.
  menu = CreateFrame("Frame", nil, frame)
  PopupFrame.menu = menu
  menu:SetFrameStrata("TOOLTIP")
  menu:SetSize(220, 100)
  menu.background = menu:CreateTexture(nil, "BACKGROUND")
  menu.background:SetAllPoints()
  menu.background:SetColorTexture(0.08, 0.08, 0.08, 1)
  menu.title = newText(menu, "GameFontNormal")
  menu.title:SetPoint("TOPLEFT", menu, "TOPLEFT", 8, -6)
  menu:Hide()
  frame.boss:SetScript("OnClick", function()
    if menu:IsShown() then menu:Hide() else menu:Show() end
  end)

  -- The D/B list drops from a row's D/B button: its title, the names, then its hints.
  dbList = CreateFrame("Frame", nil, frame)
  PopupFrame.dbList = dbList
  dbList:SetFrameStrata("TOOLTIP")
  dbList:SetSize(210, 100)
  dbList.background = dbList:CreateTexture(nil, "BACKGROUND")
  dbList.background:SetAllPoints()
  dbList.background:SetColorTexture(0.08, 0.08, 0.08, 1)
  dbList.title = newText(dbList, "GameFontNormal")
  dbList.title:SetPoint("TOPLEFT", dbList, "TOPLEFT", 8, -6)
  dbList.more = newText(dbList, "GameFontDisableSmall")
  dbList.note = newText(dbList, "GameFontDisableSmall")
  dbList:EnableMouseWheel(true)
  dbList:SetScript("OnMouseWheel", function(_, delta)
    dbOffset = dbOffset - delta
    PopupFrame.Refresh()
  end)
  dbList:SetScript("OnHide", function() dbRow, dbOffset = nil, 0 end)
  dbList:Hide()
  frame:SetScript("OnHide", function()
    menu:Hide()
    dbList:Hide()
  end)
end

-- Opens the D/B list under a row's D/B button, or closes it when it is open there already.
local function toggleDBList(row)
  if dbList:IsShown() and dbRow == row then
    dbList:Hide()
  else
    dbRow, dbOffset = row, 0
    dbList:Show()
  end
  PopupFrame.Refresh()
end

-- A bordered box like the design's: a grey edge round a dark inside, hidden until drawn.
local function newBox(row)
  local box = CreateFrame("Frame", nil, row)
  box.edge = box:CreateTexture(nil, "BACKGROUND")
  box.edge:SetAllPoints()
  box.edge:SetColorTexture(0.5, 0.5, 0.5, 1)
  box.inside = box:CreateTexture(nil, "BORDER")
  box.inside:SetPoint("TOPLEFT", box, "TOPLEFT", 1, -1)
  box.inside:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -1, 1)
  box.inside:SetColorTexture(0.04, 0.04, 0.04, 1)
  box:Hide()
  return box
end

-- A button in a box that shows its tooltip, even greyed.
local function tipButton(parent, width)
  local b = newButton(parent, width, 20)
  if b.SetMotionScriptsWhileDisabled then b:SetMotionScriptsWhileDisabled(true) end
  b:SetScript("OnEnter", function(self)
    if not self.tip then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(self.tip, 1, 1, 1)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

-- What a click on one of a not confirmed row's three buttons does.
local function choose(row, action)
  local nc = row.data.notConfirmed
  if action == "giveelse" then
    elseOpen = elseOpen ~= nc.key and nc.key or nil
    PopupFrame.Refresh()
    return
  end
  ns.Popup.Choose(nc.key, action)
  PopupFrame.Refresh()
end

-- The Give button of a name, or of the Disenchant/bank line (action "givedb"), in the Give to
-- someone else list.
local function giveElse(row, char, action)
  if ns.Popup.Choose(row.data.notConfirmed.key, action or "giveelse", char) then elseOpen = nil end
  PopupFrame.Refresh()
end

local function newNotConfirmed(row)
  local box = newBox(row)
  -- The warning panel, as the design draws it: an amber edge round a dark amber inside.
  box.warnEdge = box:CreateTexture(nil, "ARTWORK", nil, 0)
  box.warnEdge:SetColorTexture(0.55, 0.35, 0.08, 1)
  box.warnFill = box:CreateTexture(nil, "ARTWORK", nil, 1)
  box.warnFill:SetColorTexture(0.12, 0.07, 0.02, 1)
  box.warnFill:SetPoint("TOPLEFT", box.warnEdge, "TOPLEFT", 1, -1)
  box.warnFill:SetPoint("BOTTOMRIGHT", box.warnEdge, "BOTTOMRIGHT", -1, 1)
  box.text = newText(box, "GameFontNormal")
  box.text:SetWidth(BOX_WIDTH - 36)
  box.text:SetTextColor(1, 0.6, 0.2)
  box.refusal = newText(box, "GameFontHighlightSmall")
  box.refusal:SetWidth(BOX_WIDTH - 12)
  box.refusal:SetTextColor(1, 0.35, 0.35)
  box.hint = newText(box, "GameFontDisableSmall")
  box.hint:SetWidth(BOX_WIDTH - 12)
  box.buttons = {}
  for i, width in ipairs(NC_WIDTHS) do
    local b = tipButton(box, width)
    b:SetScript("OnClick", function()
      local d = row.data and row.data.notConfirmed
      if d and d.buttons[i].enabled then choose(row, d.buttons[i].action) end
    end)
    box.buttons[i] = b
  end
  return box
end

-- The Give to someone else list's box, in parent: onGive(char, action) is a name's Give (action nil)
-- or the Disenchant/bank line's (action "givedb", char the pick); onBack is Back. The Awards tab
-- draws the same list (#101).
local function newList(parent, onGive, onBack)
  local box = newBox(parent)
  box.onGive = onGive
  -- The Disenchant/bank line (#96): its label, the pick's name and its Give.
  box.db = { label = newText(box, "GameFontHighlight"), name = newText(box, "GameFontHighlight"),
    give = tipButton(box, 60), line = box:CreateTexture(nil, "ARTWORK", nil, 0) }
  box.db.line:SetColorTexture(0.2, 0.2, 0.2, 1)
  box.db.line:SetSize(BOX_WIDTH - 12, 1)
  box.db.give:SetScript("OnClick", function()
    if box.db.enabled then box.onGive(box.db.pick, "givedb") end
  end)
  box.title = newText(box, "GameFontNormal")
  box.title:SetWidth(BOX_WIDTH - 90)
  box.back = tipButton(box, 60)
  box.back:SetScript("OnClick", onBack)
  box.empty = newText(box, "GameFontHighlightSmall")
  box.refusal = newText(box, "GameFontHighlightSmall")
  box.refusal:SetWidth(BOX_WIDTH - 12)
  box.refusal:SetTextColor(1, 0.35, 0.35)
  box.hint = newText(box, "GameFontDisableSmall")
  box.hint:SetWidth(BOX_WIDTH - 12)
  box.entries = {}
  return box
end

-- The roll list box: its heading and count, a button per name, the ignored rolls struck through.
local function newRollBox(row)
  local box = newBox(row)
  box.heading = newText(box, "GameFontNormal")
  box.count = newText(box, "GameFontHighlightSmall")
  box.unavailable = newText(box, "GameFontHighlightSmall")
  box.unavailable:SetTextColor(1, 0.6, 0.2)
  box.unavailable:SetWidth(BOX_WIDTH - 12)
  box.hint = newText(box, "GameFontDisableSmall")
  box.names, box.ignored, box.hiddenNames = {}, {}, {}
  -- The warning bar of a tie or hidden rolls, as the design draws it: amber text on a dark amber bar.
  box.warnBar = box:CreateTexture(nil, "ARTWORK")
  box.warnBar:SetColorTexture(0.2, 0.15, 0.02, 1)
  box.warn = newText(box, "GameFontNormal")
  box.warn:SetTextColor(1, 0.6, 0.2)
  -- The Re-roll the tie button with the line it posts, and the hidden rolls' roll box.
  box.reroll = tipButton(box, 130)
  box.reroll:SetScript("OnClick", function()
    local data = row.data
    local button = data and data.rolls and data.rolls.reroll
    if not (button and button.enabled) then return end
    local result, why = ns.Rolls.Reroll(data.slot, data.item)
    if not result then ns.Log("Re-roll for " .. data.link .. " refused: " .. tostring(why)) end
    PopupFrame.Refresh()
  end)
  box.rerollHint = newText(box, "GameFontHighlightSmall")
  box.rerollHint:SetWidth(BOX_WIDTH - 12)
  box.rollLabel = newText(box, "GameFontHighlightSmall")
  box.rollEdit = CreateFrame("EditBox", nil, box)
  box.rollEdit:SetSize(50, 20)
  box.rollEdit:SetAutoFocus(false)
  box.rollEdit:SetMaxLetters(3)
  box.rollEdit:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
  box.rollEdit:SetTextInsets(4, 4, 0, 0)
  box.rollEdit:SetScript("OnEscapePressed", box.rollEdit.ClearFocus)
  box.rollEdit.background = box.rollEdit:CreateTexture(nil, "BACKGROUND")
  box.rollEdit.background:SetAllPoints()
  box.rollEdit.background:SetColorTexture(0, 0, 0, 0.8)
  box.note = newText(box, "GameFontHighlightSmall")
  box.note:SetTextColor(1, 0.6, 0.2)
  box.note:SetWidth(BOX_WIDTH - 12)
  return box
end

local function newRow()
  local row = CreateFrame("Frame", nil, frame)
  row:SetSize(WIDTH - 2 * PAD, ROW_MIN)
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(32, 32)
  row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -4)
  row.title = newText(row, "GameFontNormal")
  row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 40, -2)
  row.badge = row:CreateTexture(nil, "BACKGROUND")
  row.badge:SetPoint("TOPLEFT", row, "TOPLEFT", 40, -20)
  row.badgeText = newText(row, "GameFontHighlightSmall")
  row.badgeText:SetPoint("LEFT", row.badge, "LEFT", 4, 0)
  row.beside = newText(row, "GameFontHighlightSmall")
  row.detail = newText(row, "GameFontHighlightSmall")
  row.skipped = newText(row, "GameFontDisableSmall")
  -- The hand-out box, as the design draws it.
  row.box = newBox(row)
  row.ncBox = newNotConfirmed(row)
  row.list = newList(row, function(char, action) giveElse(row, char, action) end, function()
    elseOpen = nil
    PopupFrame.Refresh()
  end)
  row.rollBox = newRollBox(row)
  row.rollHint = newText(row, "GameFontDisableSmall")
  row.spinner = row.box:CreateTexture(nil, "ARTWORK")
  row.spinner:SetSize(14, 14)
  row.spinner:SetPoint("TOPLEFT", row.box, "TOPLEFT", 6, -6)
  row.spinner:SetTexture(SPINNER)
  row.handout = newText(row.box, "GameFontNormal")
  row.handout:SetWidth(BOX_WIDTH - 32)
  row.handout:SetPoint("TOPLEFT", row.box, "TOPLEFT", 24, -6)
  row.handout:SetTextColor(unpack(GOLD))
  row.handoutNote = newText(row.box, "GameFontHighlightSmall")
  row.handoutNote:SetWidth(BOX_WIDTH - 12)
  row.primary = newButton(row, 150, 20)
  row.primary:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -2)
  -- A greyed button still shows why when hovered.
  if row.primary.SetMotionScriptsWhileDisabled then row.primary:SetMotionScriptsWhileDisabled(true) end
  row.primary:SetScript("OnEnter", function(self)
    local tip = row.data and row.data.buttons[1] and row.data.buttons[1].tooltip
    if not tip then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(tip, 1, 1, 1)
    GameTooltip:Show()
  end)
  row.primary:SetScript("OnLeave", function() GameTooltip:Hide() end)
  row.primary:SetScript("OnClick", function()
    local button = row.data and row.data.buttons[1]
    if not (button and button.enabled) then return end
    if button.action == "roll" or button.action == "openroll" then
      local result, why = ns.Rolls.Start(row.data.slot, row.data.item)
      if not result then ns.Log("Roll call for " .. row.data.link .. " refused: " .. tostring(why)) end
      PopupFrame.Refresh()
      return
    end
    if button.action == "rollgive" then
      local ok, why = ns.Popup.Give(row.data.slot, row.data.item, button.winner, button.roll)
      if not ok then ns.Log("Give for " .. row.data.link .. " refused: " .. tostring(why)) end
      PopupFrame.Refresh()
      return
    end
    if button.action ~= "give" then return end
    local ok, why = ns.Popup.Give(row.data.slot, row.data.item, row.data.winner)
    if not ok then ns.Log("Give for " .. row.data.link .. " refused: " .. tostring(why)) end
    PopupFrame.Refresh()
  end)
  row.db = newButton(row, 110, 20)
  row.db:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -26)
  row.db:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  if row.db.SetMotionScriptsWhileDisabled then row.db:SetMotionScriptsWhileDisabled(true) end
  row.db:SetScript("OnEnter", function(self)
    local tip = row.data and row.data.buttons[2] and row.data.buttons[2].tooltip
    if not tip then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(tip, 1, 1, 1)
    GameTooltip:Show()
  end)
  row.db:SetScript("OnLeave", function() GameTooltip:Hide() end)
  row.db:SetScript("OnClick", function(_, mouseButton)
    local button = row.data and row.data.buttons[2]
    if not (button and button.enabled) then return end
    if not button.pick or mouseButton == "RightButton" or IsShiftKeyDown() then
      toggleDBList(row)
      return
    end
    dbList:Hide()
    local ok, why = ns.Popup.GiveDB(row.data.slot, row.data.item, button.pick)
    if not ok then ns.Log("D/B for " .. row.data.link .. " refused: " .. tostring(why)) end
    PopupFrame.Refresh()
  end)
  return row
end

-- A line below the badge, wrapped to the text column. Returns the new y.
local function addLine(row, line, text, y, color)
  line:ClearAllPoints()
  if not text then
    line:SetText("")
    line:Hide()
    return y
  end
  line:SetWidth(TEXT_WIDTH)
  line:SetPoint("TOPLEFT", row, "TOPLEFT", 40, -y)
  line:SetText(text)
  if color then line:SetTextColor(unpack(color)) end
  line:Show()
  return y + line:GetStringHeight() + 4
end

-- A line inside a box, wrapped to its width; empty text hides it. Returns the new y.
local function boxLine(box, line, text, y)
  line:ClearAllPoints()
  if not text then
    line:SetText("")
    line:Hide()
    return y
  end
  line:SetPoint("TOPLEFT", box, "TOPLEFT", 6, -y)
  line:SetText(text)
  line:Show()
  return y + line:GetStringHeight() + 4
end

-- The not confirmed box: what happened, the three choices, why the last one was refused, the hint.
local function drawNotConfirmed(row, nc, below)
  local box = row.ncBox
  box.text:ClearAllPoints()
  box.text:SetPoint("TOPLEFT", box, "TOPLEFT", 14, -12)
  box.text:SetText(nc.text)
  local panel = box.text:GetStringHeight() + 16
  box.warnEdge:ClearAllPoints()
  box.warnEdge:SetPoint("TOPLEFT", box, "TOPLEFT", 6, -6)
  box.warnEdge:SetSize(BOX_WIDTH - 12, panel)
  local y = 6 + panel + 8
  local x = 6
  for i, b in ipairs(box.buttons) do
    local d = nc.buttons[i]
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", box, "TOPLEFT", x, -y)
    x = x + NC_WIDTHS[i] + 6
    setButton(b, d.text, d.enabled)
    b.tip = d.tooltip
  end
  y = boxLine(box, box.refusal, nc.refusal, y + 26)
  y = boxLine(box, box.hint, nc.hint, y)
  box:ClearAllPoints()
  box:SetPoint("TOPLEFT", row, "TOPLEFT", 40, -below)
  box:SetSize(BOX_WIDTH, y + 4)
  box:Show()
  return below + y + 8
end

-- The Give to someone else list, in its box at x and below in the box's parent: each other
-- contender with the method they hold and a Give button; one who can't receive is greyed with the
-- reason and has no button. Then the Disenchant/bank line, when the list has one, and why the last
-- choice was refused. Returns the new below.
local function drawList(box, list, x, below)
  box.title:ClearAllPoints()
  box.title:SetPoint("TOPLEFT", box, "TOPLEFT", 6, -6)
  box.title:SetText(list.title)
  box.back:ClearAllPoints()
  box.back:SetPoint("TOPRIGHT", box, "TOPRIGHT", -6, -4)
  setButton(box.back, list.back, true)
  local y = 30
  for i, person in ipairs(list.people) do
    local e = box.entries[i]
    if not e then
      e = { name = newText(box, "GameFontHighlight"), method = newText(box, "GameFontHighlightSmall"),
        give = tipButton(box, 60), badge = box:CreateTexture(nil, "ARTWORK", nil, 0),
        line = box:CreateTexture(nil, "ARTWORK", nil, 0) }
      e.badge:SetColorTexture(0, 0, 0, 1)
      e.line:SetColorTexture(0.2, 0.2, 0.2, 1)
      e.line:SetSize(BOX_WIDTH - 12, 1)
      e.give:SetScript("OnClick", function()
        if e.enabled then box.onGive(e.char) end
      end)
      box.entries[i] = e
    end
    e.char, e.enabled = person.char, person.enabled
    e.name:ClearAllPoints()
    e.name:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -(y + 4))
    e.name:SetText(person.char)
    e.method:ClearAllPoints()
    e.method:SetText(person.available and person.method:upper() or person.reason)
    e.badge:ClearAllPoints()
    e.line:ClearAllPoints()
    e.line:SetPoint("TOPLEFT", box, "TOPLEFT", 6, -(y + 25))
    e.line:Show()
    if person.available then
      e.name:SetTextColor(1, 1, 1)
      e.method:SetTextColor(1, 1, 1)
      e.method:SetPoint("TOPLEFT", box, "TOPLEFT", 174, -(y + 5))
      e.badge:SetPoint("TOPLEFT", box, "TOPLEFT", 170, -(y + 4))
      e.badge:SetSize(e.method:GetStringWidth() + 8, 16)
      e.badge:SetColorTexture(unpack(BADGE_COLORS[person.kind]))
      e.badge:Show()
      e.give:ClearAllPoints()
      e.give:SetPoint("TOPRIGHT", box, "TOPRIGHT", -10, -y)
      setButton(e.give, "Give", person.enabled)
      e.give.tip = person.tooltip
      e.give:Show()
    else
      e.name:SetTextColor(0.5, 0.5, 0.5)
      e.method:SetTextColor(0.5, 0.5, 0.5)
      e.method:SetPoint("TOPLEFT", box, "TOPLEFT", 170, -(y + 5))
      e.badge:Hide()
      e.give:Hide()
    end
    e.name:Show()
    e.method:Show()
    y = y + 26
  end
  for i = #list.people + 1, #box.entries do
    local e = box.entries[i]
    e.name:Hide()
    e.method:Hide()
    e.badge:Hide()
    e.line:Hide()
    e.give:Hide()
  end
  box.empty:ClearAllPoints()
  if list.empty then
    box.empty:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -(y + 4))
    box.empty:SetText(list.empty)
    box.empty:Show()
    y = y + 26
  else
    box.empty:SetText("")
    box.empty:Hide()
  end
  -- The Disenchant/bank line: with no pick, greyed with its Give unclickable.
  local db, line = list.db, box.db
  line.label:ClearAllPoints()
  line.name:ClearAllPoints()
  line.give:ClearAllPoints()
  line.line:ClearAllPoints()
  if db then
    line.pick, line.enabled = db.pick, db.enabled
    line.label:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -(y + 4))
    line.label:SetText(db.label)
    line.name:SetPoint("TOPLEFT", box, "TOPLEFT", 170, -(y + 4))
    line.name:SetText(db.pick or "")
    local colour = db.pick and 1 or 0.5
    line.label:SetTextColor(colour, colour, colour)
    line.name:SetTextColor(1, 1, 1)
    line.give:SetPoint("TOPRIGHT", box, "TOPRIGHT", -10, -y)
    setButton(line.give, "Give", db.enabled)
    line.give.tip = db.tooltip
    line.line:SetPoint("TOPLEFT", box, "TOPLEFT", 6, -(y + 25))
    line.label:Show()
    if db.pick then line.name:Show() else line.name:Hide() end
    line.give:Show()
    line.line:Show()
    y = y + 26
  else
    line.pick, line.enabled = nil, false
    line.label:Hide()
    line.name:Hide()
    line.give:Hide()
    line.line:Hide()
  end
  y = boxLine(box, box.refusal, list.refusal, y + 2)
  y = boxLine(box, box.hint, list.hint, y + (list.refusal and 0 or 2))
  box:ClearAllPoints()
  box:SetPoint("TOPLEFT", box:GetParent(), "TOPLEFT", x, -below)
  box:SetSize(BOX_WIDTH, y + 4)
  box:Show()
  return below + y + 8
end

-- What the Awards tab shares to draw a not confirmed award's choices the pop-up's way (#101).
PopupFrame.NewList, PopupFrame.DrawList = newList, drawList
PopupFrame.TipButton, PopupFrame.SetButton = tipButton, setButton
-- And what its Pick winner picker draws with (#126): the bordered box and the badges' colours.
PopupFrame.NewBox, PopupFrame.BADGE_COLORS = newBox, BADGE_COLORS

-- The hidden rolls' name buttons, flowing across the box; a click awards to that player with the
-- roll typed in the box (#102). Returns the new y.
local function drawHiddenNames(row, box, names, y)
  local x, lineY = 6, y
  for i, e in ipairs(names) do
    local b = box.hiddenNames[i]
    if not b then
      b = tipButton(box, 100)
      b:SetScript("OnClick", function(self)
        local data = row.data
        local ok, why = ns.Popup.GiveHidden(data.slot, data.item, self.pick, box.rollEdit:GetText())
        if not ok then
          ns.Log("Give for " .. data.link .. " to " .. self.pick .. " refused: " .. tostring(why))
        end
        if ok then box.rollEdit:SetText("") end
        PopupFrame.Refresh()
      end)
      box.hiddenNames[i] = b
    end
    b.pick = e.name
    b.tip = e.tooltip
    setButton(b, e.name, e.enabled)
    local width = b.label:GetStringWidth() + 20
    if x > 6 and x + width > BOX_WIDTH - 6 then x, lineY = 6, lineY + 24 end
    b:SetWidth(width)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", box, "TOPLEFT", x, -lineY)
    b:Show()
    x = x + width + 6
  end
  for i = #names + 1, #box.hiddenNames do box.hiddenNames[i]:Hide() end
  return lineY + 28
end

-- The roll list box: heading and "N of M rolled", one clickable line per name (the picked one gold
-- with a dot), then the ignored rolls in grey, struck through. A tie (#102) puts a warning bar on
-- top, highlights the tied names and ends with the Re-roll button and the line it posts; hidden
-- rolls put a warning bar on top, then the names as buttons and the roll box, instead of the list.
-- Returns the new y.
local function drawRolls(row, rolls, below)
  local box = row.rollBox
  local hidden = rolls.hidden
  local warning = rolls.warning or (hidden and hidden.warning)
  local y
  box.heading:ClearAllPoints()
  box.count:ClearAllPoints()
  if warning then
    box.heading:SetText("")
    box.count:SetText("")
    box.warnBar:ClearAllPoints()
    box.warnBar:SetPoint("TOPLEFT", box, "TOPLEFT", 6, -6)
    box.warnBar:SetSize(BOX_WIDTH - 12, 22)
    box.warnBar:Show()
    box.warn:ClearAllPoints()
    box.warn:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -10)
    box.warn:SetText(warning)
    box.warn:Show()
    y = 34
  else
    box.warnBar:Hide()
    box.warn:Hide()
    box.heading:SetPoint("TOPLEFT", box, "TOPLEFT", 6, -6)
    box.heading:SetText(rolls.heading)
    box.count:SetPoint("TOPRIGHT", box, "TOPRIGHT", -6, -7)
    box.count:SetText(rolls.count)
    y = 26
  end
  local listed = hidden and {} or rolls.entries
  for i, e in ipairs(listed) do
    local line = box.names[i]
    if not line then
      line = tipButton(box, BOX_WIDTH - 12)
      line.name = newText(line, "GameFontHighlight")
      line.name:SetPoint("LEFT", line, "LEFT", 22, 0)
      line.roll = newText(line, "GameFontHighlight")
      line.roll:SetPoint("RIGHT", line, "RIGHT", -6, 0)
      line.dot = newText(line, "GameFontNormal")
      line.dot:SetPoint("LEFT", line, "LEFT", 4, 0)
      line.label:Hide()
      line:SetScript("OnClick", function()
        local ok, why = ns.Popup.PickWinner(row.data.slot, row.data.item, line.pick)
        if not ok then ns.Log("Pick for " .. row.data.link .. " refused: " .. tostring(why)) end
        PopupFrame.Refresh()
      end)
      box.names[i] = line
    end
    line.pick = e.name
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", box, "TOPLEFT", 6, -y)
    line.background:SetColorTexture(0.04, 0.04, 0.04, 1)
    if e.tied then line.background:SetColorTexture(0.12, 0.09, 0.02, 1) end
    if e.selected then line.background:SetColorTexture(0.2, 0.15, 0.02, 1) end
    line.dot:SetText(e.selected and "●" or "○")
    line.name:SetText(e.name)
    line.roll:SetText(e.waiting and "waiting" or tostring(e.roll))
    local color = e.selected and GOLD or (e.waiting and { 0.5, 0.5, 0.5 } or { 1, 1, 1 })
    line.dot:SetTextColor(unpack(color))
    line.name:SetTextColor(unpack(color))
    line.roll:SetTextColor(unpack(color))
    line:Enable()
    line:Show()
    y = y + 20
  end
  for i = #listed + 1, #box.names do box.names[i]:Hide() end
  for i, ig in ipairs(rolls.ignored) do
    local line = box.ignored[i]
    if not line then
      line = { name = newText(box, "GameFontDisableSmall"), roll = newText(box, "GameFontDisableSmall"),
        strike = box:CreateTexture(nil, "ARTWORK") }
      line.strike:SetColorTexture(0.5, 0.5, 0.5, 1)
      line.strike:SetHeight(1)
      box.ignored[i] = line
    end
    line.name:ClearAllPoints()
    line.name:SetPoint("TOPLEFT", box, "TOPLEFT", 28, -(y + 4))
    line.name:SetText(ig.name .. " (" .. ig.reason .. ")")
    line.roll:ClearAllPoints()
    line.roll:SetPoint("TOPRIGHT", box, "TOPRIGHT", -12, -(y + 4))
    line.roll:SetText(tostring(ig.roll))
    line.strike:ClearAllPoints()
    line.strike:SetPoint("LEFT", line.roll, "LEFT", 0, 0)
    line.strike:SetWidth(line.roll:GetStringWidth())
    line.name:Show()
    line.roll:Show()
    line.strike:Show()
    y = y + 18
  end
  for i = #rolls.ignored + 1, #box.ignored do
    local line = box.ignored[i]
    line.name:Hide()
    line.roll:Hide()
    line.strike:Hide()
  end
  y = boxLine(box, box.unavailable, rolls.unavailable, y + 2)
  local reroll = rolls.reroll
  box.reroll:ClearAllPoints()
  box.rerollHint:ClearAllPoints()
  if reroll then
    box.reroll:SetPoint("TOPLEFT", box, "TOPLEFT", 6, -(y + 4))
    box.reroll.tip = reroll.tooltip
    setButton(box.reroll, reroll.text, reroll.enabled)
    box.reroll:Show()
    y = boxLine(box, box.rerollHint, reroll.hint, y + 30)
  else
    box.reroll:Hide()
    boxLine(box, box.rerollHint, nil, y)
  end
  box.rollLabel:ClearAllPoints()
  box.rollEdit:ClearAllPoints()
  if hidden then
    y = drawHiddenNames(row, box, rolls.entries, y)
    box.rollLabel:SetPoint("TOPLEFT", box, "TOPLEFT", 6, -(y + 4))
    box.rollLabel:SetText(hidden.label)
    box.rollLabel:Show()
    box.rollEdit:SetPoint("TOPLEFT", box, "TOPLEFT", 12 + box.rollLabel:GetStringWidth(), -y)
    box.rollEdit:Show()
    y = boxLine(box, box.note, hidden.note, y + 26)
  else
    for _, b in ipairs(box.hiddenNames) do b:Hide() end
    box.rollLabel:Hide()
    box.rollEdit:Hide()
    boxLine(box, box.note, nil, y)
  end
  box:ClearAllPoints()
  box:SetPoint("TOPLEFT", row, "TOPLEFT", 40, -below)
  box:SetSize(BOX_WIDTH, y + 4)
  box:Show()
  return below + y + 8
end

local function drawRow(row, data, y)
  row:ClearAllPoints()
  row:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
  local _, _, _, _, _, _, _, _, _, icon = GetItemInfo(data.item)
  row.icon:SetTexture(icon or NO_ICON)
  row.title:SetText(data.link .. (data.copy and (" · " .. data.copy) or ""))
  row.badgeText:SetText(data.label:upper())
  row.badge:SetSize(row.badgeText:GetStringWidth() + 8, 16)
  row.badge:SetColorTexture(unpack(BADGE_COLORS[data.mode]))
  row.beside:ClearAllPoints()
  row.beside:SetPoint("LEFT", row.badge, "RIGHT", 6, 0)
  local contenders = data.action == "roll" and not data.rolls
  row.beside:SetText(contenders and "" or data.text)
  local below = 40
  below = addLine(row, row.detail, contenders and data.text or nil, below)
  local notes = data.skippedText
  for _, note in ipairs({ data.unavailable or false, data.dbNote or false }) do
    if note then notes = (notes and (notes .. "\n") or "") .. note end
  end
  below = addLine(row, row.skipped, notes, below)
  -- While the game confirms a hand-out the row says so in its box, with a turning spinner, in place
  -- of buttons.
  local handout, box = data.handout, row.box
  if handout then
    row.handout:SetText(handout.text)
    local inside = 6 + row.handout:GetStringHeight() + 4
    row.handoutNote:ClearAllPoints()
    row.handoutNote:SetPoint("TOPLEFT", box, "TOPLEFT", 6, -inside)
    row.handoutNote:SetText(handout.note)
    inside = inside + row.handoutNote:GetStringHeight() + 6
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", row, "TOPLEFT", 40, -below)
    box:SetSize(BOX_WIDTH, inside)
    box:Show()
    row:SetScript("OnUpdate", function()
      if row.spinner.SetRotation then row.spinner:SetRotation(-GetTime() * 4) end
    end)
    below = below + inside + 4
  else
    box:Hide()
    row:SetScript("OnUpdate", nil)
  end
  row.rollBox:Hide()
  row.rollHint:Hide()
  row.primary:ClearAllPoints()
  if data.rolls then
    -- The roll box belongs to one row's item: a new item starts it empty.
    if row.rollItem ~= data.item then row.rollBox.rollEdit:SetText("") end
    row.rollItem = data.item
    below = drawRolls(row, data.rolls, below)
    -- The Give button sits under the list, as the design draws it, with its hint beside it. Hidden
    -- rolls have none: a name click awards.
    row.primary:SetWidth(240)
    row.primary:SetPoint("TOPLEFT", row, "TOPLEFT", 40, -below)
    row.rollHint:ClearAllPoints()
    row.rollHint:SetPoint("LEFT", row.primary, "RIGHT", 8, 0)
    row.rollHint:SetText(data.rolls.hint or "")
    if data.rolls.hint then row.rollHint:Show() else row.rollHint:Hide() end
    if not data.rolls.hidden then below = below + 26 end
  else
    row.rollItem = nil
    row.rollBox.rollEdit:SetText("")
    row.primary:SetWidth(150)
    row.primary:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -2)
  end
  local nc = data.notConfirmed
  row.ncBox:Hide()
  row.list:Hide()
  if nc and elseOpen == nc.key then
    below = drawList(row.list, nc.list, 40, below)
  elseif nc then
    below = drawNotConfirmed(row, nc, below)
  end
  local height = math.max(ROW_MIN, below + 4)
  row:SetHeight(height)
  row.data = data
  for i, button in ipairs({ row.primary, row.db }) do
    local b = data.buttons[i]
    if b and not b.hidden then
      setButton(button, b.text, b.enabled)
      button:Show()
    else
      button:Hide()
    end
  end
  row:Show()
  return y + height + 6
end

local function drawMenu(boss, redraw)
  menu:ClearAllPoints()
  menu:SetPoint("TOPLEFT", frame.boss, "BOTTOMLEFT", 0, -2)
  menu.title:SetText(boss.menuTitle)
  local y = 26
  for i, item in ipairs(boss.menu) do
    local entry = entries[i]
    if not entry then
      entry = newButton(menu, 208, 18)
      entry.label:ClearAllPoints()
      entry.label:SetPoint("LEFT", entry, "LEFT", 4, 0)
      entries[i] = entry
    end
    entry:ClearAllPoints()
    entry:SetPoint("TOPLEFT", menu, "TOPLEFT", 6, -y)
    setButton(entry, (item.selected and "> " or "   ") .. item.name
      .. (item.killed and ("  · killed " .. item.killed) or ""), true)
    entry.background:SetColorTexture(0.08, 0.08, 0.08, 1)
    entry:SetScript("OnClick", function()
      ns.Popup.PickBoss(item.id)
      menu:Hide()
      redraw()
    end)
    entry:Show()
    y = y + 20
  end
  for i = #boss.menu + 1, #entries do entries[i]:Hide() end
  menu:SetHeight(y + 6)
end

-- The D/B list, under its row's D/B button: up to DB_SHOWN names from dbOffset on, the pick
-- ticked. Choosing a name remembers it and gives nothing.
local function drawDBList(list)
  local members = list.members
  dbOffset = math.max(0, math.min(dbOffset, #members - DB_SHOWN))
  dbList:ClearAllPoints()
  dbList:SetPoint("TOPRIGHT", dbRow.db, "BOTTOMRIGHT", 0, -2)
  dbList.title:SetText(list.title)
  local y, shown = 26, math.min(DB_SHOWN, #members)
  for i = 1, shown do
    local member = members[dbOffset + i]
    local entry = dbEntries[i]
    if not entry then
      entry = newButton(dbList, 198, 18)
      entry.tick = entry:CreateTexture(nil, "ARTWORK")
      entry.tick:SetSize(14, 14)
      entry.tick:SetPoint("LEFT", entry, "LEFT", 2, 0)
      entry.tick:SetTexture(TICK)
      entry.label:ClearAllPoints()
      entry.label:SetPoint("LEFT", entry, "LEFT", 20, 0)
      dbEntries[i] = entry
    end
    entry:ClearAllPoints()
    entry:SetPoint("TOPLEFT", dbList, "TOPLEFT", 6, -y)
    setButton(entry, member.name, true)
    if member.selected then entry.tick:Show() else entry.tick:Hide() end
    entry.background:SetColorTexture(0.08, 0.08, 0.08, 1)
    entry.member = member
    entry:SetScript("OnClick", function()
      ns.Popup.SetDBPick(member.name)
      dbList:Hide()
      PopupFrame.Refresh()
    end)
    entry:Show()
    y = y + 20
  end
  for i = shown + 1, #dbEntries do dbEntries[i]:Hide() end
  local below, above = #members - dbOffset - shown, dbOffset
  dbList.more:ClearAllPoints()
  if below > 0 or above > 0 then
    dbList.more:SetPoint("TOPLEFT", dbList, "TOPLEFT", 8, -(y + 2))
    dbList.more:SetText(below > 0 and (ARROW_DOWN .. " " .. below .. " more · scroll")
      or (ARROW_UP .. " " .. above .. " more · scroll"))
    dbList.more:Show()
    y = y + 16
  else
    dbList.more:SetText("")
    dbList.more:Hide()
  end
  dbList.note:ClearAllPoints()
  dbList.note:SetPoint("TOPLEFT", dbList, "TOPLEFT", 8, -(y + 2))
  dbList.note:SetText(list.note)
  dbList:SetHeight(y + 22)
end

-- Draws the model, or hides the pop-up when there is none. Returns the model.
function PopupFrame.Refresh()
  if not frame then build() end
  local model = ns.Popup.Build()
  if not model then
    frame:Hide()
    return nil
  end
  local boss = model.boss
  frame.title:SetText(model.title)
  local y = 32
  frame.fight:ClearAllPoints()
  if model.fight then
    frame.fight:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
    frame.fight:SetText(model.fight)
    frame.fight:Show()
    y = y + frame.fight:GetStringHeight() + 8
  else
    frame.fight:SetText("")
    frame.fight:Hide()
  end
  if boss.notice or model.notice then
    frame.notice:ClearAllPoints()
    frame.notice:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
    frame.notice:SetText(boss.notice or model.notice)
    frame.notice:Show()
    frame.link:ClearAllPoints()
    if model.syncLink then
      frame.link:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(y + frame.notice:GetStringHeight() + 2))
      setButton(frame.link, "Load reserves", true)
      frame.link.background:SetColorTexture(0, 0, 0, 0)
      frame.link:Show()
      y = y + 18
    else
      frame.link:Hide()
    end
    y = y + frame.notice:GetStringHeight() + 8
  else
    frame.notice:SetText("")
    frame.notice:Hide()
    frame.link:Hide()
  end
  frame.bossLabel:ClearAllPoints()
  frame.boss:ClearAllPoints()
  frame.count:ClearAllPoints()
  if boss.name then
    frame.bossLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(y + 4))
    frame.boss:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + 36, -y)
    setButton(frame.boss, boss.name .. " ▾", boss.menu ~= nil)
    frame.bossLabel:Show()
    frame.boss:Show()
    if boss.menu then drawMenu(boss, PopupFrame.Refresh) end
  else
    frame.bossLabel:Hide()
    frame.boss:Hide()
  end
  frame.count:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -(y + 4))
  frame.count:SetText(model.count .. (model.count == 1 and " item" or " items"))
  y = y + 28
  -- The list stays open only while its award still waits as not confirmed.
  local listed
  for _, data in ipairs(model.rows) do
    listed = listed or (data.notConfirmed and data.notConfirmed.key == elseOpen)
  end
  if not listed then elseOpen = nil end
  for i, data in ipairs(model.rows) do
    rows[i] = rows[i] or newRow()
    y = drawRow(rows[i], data, y)
  end
  for i = #model.rows + 1, #rows do rows[i]:Hide() end
  -- The open D/B list stays only while its row still offers an enabled D/B button.
  if dbList:IsShown() then
    local button = dbRow and dbRow:IsShown() and dbRow.data.buttons[2]
    if button and button.enabled then drawDBList(model.dbMenu) else dbList:Hide() end
  end
  frame.foot:ClearAllPoints()
  frame.foot:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
  frame.foot:SetText(model.foot .. (model.practice and PRACTICE_TAG or ""))
  frame:SetHeight(y + frame.foot:GetStringHeight() + PAD)
  frame.model = model
  if not dismissed then frame:Show() end
  return model
end

-- While a candidate's name hasn't loaded the model says so (#10): ask again after a short wait,
-- for as long as this loot window stays open.
local function recheckSoon(model)
  if not (model and model.recheck) then return end
  local mine = generation
  C_Timer.After(RECHECK_SECONDS, function()
    if mine ~= generation or not open then return end
    recheckSoon(PopupFrame.Refresh())
  end)
end

ns.On("LOOT_OPENED", function()
  generation = generation + 1
  open, dismissed = true, false
  recheckSoon(PopupFrame.Refresh())
end)

ns.On("LOOT_CLOSED", function()
  generation = generation + 1
  open, elseOpen = false, nil
  if frame then frame:Hide() end
end)

-- A boss fight starting or ending, or the game settling a hand-out, changes what the rows show.
local function redraw()
  if open then PopupFrame.Refresh() end
end
PopupFrame.Redraw = redraw -- practice mode switching changes the title and the foot
ns.On("ADDON_RESTRICTION_STATE_CHANGED", redraw)
ns.On("CHAT_MSG_SYSTEM", redraw) -- a roll (counted or ignored): Rolls, loaded earlier, reads it first
ns.Tracking.On("confirmed", redraw)
ns.Tracking.On("unconfirmed", redraw)
ns.Tracking.On("late", redraw)
