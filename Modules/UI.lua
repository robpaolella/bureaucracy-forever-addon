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
  end
  UI.Select(TAB_NAMES[1])

  placeWindow()
  window:Hide()
  -- Set after the first Hide, which isn't the officer closing it.
  window:SetScript("OnHide", function() saved().shown = false end)
  window:SetScript("OnShow", function() saved().shown = true end)
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
  if wasShown then window:Show() end
end)

for _, event in ipairs({ "confirmed", "unconfirmed", "late" }) do
  ns.Tracking.On(event, UI.RefreshBadge)
end
