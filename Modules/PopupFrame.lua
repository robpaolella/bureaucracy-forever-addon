-- PopupFrame: draws the loot pop-up (#77) from the content model Popup.Build() makes (#10).
-- It opens on LOOT_OPENED for the loot master, closes on LOOT_CLOSED, and redraws when the officer
-- picks a boss or while a candidate's name is still loading. The buttons are drawn only: giving,
-- rolling and D/B belong to #11, #12 and #13.
local _, ns = ...

local PopupFrame = {}
ns.PopupFrame = PopupFrame

local WIDTH, TEXT_WIDTH, PAD = 560, 380, 10
local ROW_MIN, RECHECK_SECONDS = 46, 1
local BADGE_COLORS = {
  hr = { 0.85, 0.4, 0.1 }, sr = { 0.2, 0.55, 0.85 }, open = { 0.45, 0.45, 0.45 },
}
local NO_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local frame, menu
local rows, entries = {}, {} -- widgets reused from one draw to the next
local generation = 0 -- bumped by every LOOT_OPENED and LOOT_CLOSED, so a stale wait does nothing
local open = false -- the loot window is open and the pop-up belongs to it
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
  frame:SetScript("OnHide", function() menu:Hide() end)
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
  row.primary = newButton(row, 150, 20)
  row.primary:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -2)
  row.db = newButton(row, 110, 20)
  row.db:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -26)
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
  local contenders = data.action == "roll"
  row.beside:SetText(contenders and "" or data.text)
  local below = 40
  below = addLine(row, row.detail, contenders and data.text or nil, below)
  local notes = data.skippedText
  if data.unavailable then notes = (notes and (notes .. "\n") or "") .. data.unavailable end
  below = addLine(row, row.skipped, notes, below)
  local height = math.max(ROW_MIN, below + 4)
  row:SetHeight(height)
  setButton(row.primary, data.buttons[1].text, data.buttons[1].enabled)
  setButton(row.db, data.buttons[2].text, data.buttons[2].enabled)
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
  for i, data in ipairs(model.rows) do
    rows[i] = rows[i] or newRow()
    y = drawRow(rows[i], data, y)
  end
  for i = #model.rows + 1, #rows do rows[i]:Hide() end
  frame.foot:ClearAllPoints()
  frame.foot:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
  frame.foot:SetText(model.foot)
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
  open = false
  if frame then frame:Hide() end
end)
