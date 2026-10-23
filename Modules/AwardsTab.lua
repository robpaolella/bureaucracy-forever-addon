-- The Awards tab and the footer's loot master line (#14): the selected raid's awards, grouped by
-- boss, read only. A not confirmed row has three buttons: for the loot master they are the pop-up's
-- three choices (#101), with its Give to someone else list and refusal text; another officer sees
-- them greyed. A confirmed award has Undo (#40), and one undone after it left the corpse is followed
-- by its NEEDS A WINNER row, whose Pick winner opens the picker in a box under it (#126,
-- design/115-pick-winner version A): choose who has it now, see the line, Post correction. A hand-out
-- from the game's loot menu put off (OutsideHandout.Unanswered) has a NEEDS AN ANSWER row, drawn
-- like NEEDS A WINNER, whose Answer asks its question again (#143). Draws into UI.tabs.Awards and
-- UI.footer.
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
local UNDO_WIDTH, PICK_WIDTH = 60, 80
local HOW = { HR = "Hard reserve", SR = "Soft reserve", OPEN_ROLL = "Open roll",
  DISENCHANT_BANK = "Disenchant/bank" }
local BANNER = "Only the loot master (%s) can change awards."
local EMPTY_TITLE = "No awards yet this raid"
local EMPTY_HINT = "Items you hand out with the pop-up, or from the game's loot menu, show up here "
  .. "with the time, boss, winner and how they won."
local BUTTONS = { "Try again", "Someone else", "Not handed out" }
local NEEDS_WINNER = AMBER:format("NEEDS A WINNER") .. " Undone after it left the corpse"
local NEEDS_ANSWER = AMBER:format("NEEDS AN ANSWER") .. " Given to %s from the game's loot menu"
-- The picker's box, from the item column to the right edge, and how many names it lists at once.
local BOX_X = COLUMNS.item[1]
local BOX_WIDTH = CONTENT_WIDTH - BOX_X
local HOLDERS_SHOWN, MEMBERS_SHOWN, CHOICE_HEIGHT = 6, 12, 22
local GOLD_SMALL = "|cffffd100%s|r"
local NOTE_LABEL = GOLD_SMALL:format("Note for the guild site") .. " "
  .. GREY:format("(optional, never posted in chat)")
local BADGE_DB = { 0.5, 0.3, 0.7 }
local ARROW_DOWN = "|TInterface\\Buttons\\Arrow-Down-Up:12:12|t"
local ARROW_UP = "|TInterface\\Buttons\\Arrow-Up-Up:12:12|t"

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
    boss = bossName(snapshot, award.boss), item = parts.itemText(award.item),
    winner = award.char and plain(award.char) or "",
    how = HOW[award.method] or plain(award.method), roll = award.roll,
    notConfirmed = award.state == "not-confirmed" and not award.voided,
    undoable = (award.state == "confirmed" or award.state == "manual") and not award.voided,
    -- Undone after the game confirmed it, and not yet given to anyone: the item left the corpse.
    needsWinner = award.voided and award.state == "confirmed" and not award.replacedBy or nil,
    voided = award.voided and true or false,
    -- Given by Pick winner: it replaces an award confirmed before it was undone.
    corrected = not award.voided and award.replaces
      and (ns.Records.Get(award.replaces) or {}).state == "confirmed"
      and ("Corrected " .. date("%H:%M", award.at)) or nil,
    note = award.voided and (award.voidReason and plain(award.voidReason)
      or ("Undone " .. date("%H:%M", award.voidedAt or award.at))) or nil,
    at = award.at, voidedAt = award.voidedAt }
end

local function byTime(a, b) return a.at < b.at end

-- The rows in time order, each award that needs a winner followed by its NEEDS A WINNER row
-- (timed when it was undone).
local function ordered(rows)
  table.sort(rows, byTime)
  local out = {}
  for _, r in ipairs(rows) do
    out[#out + 1] = r
    if r.needsWinner then
      local at = r.voidedAt or r.at
      out[#out + 1] = { key = r.key, winnerNeeded = true, boss = r.boss, item = r.item, at = at,
        time = date("%H:%M", at), practiceTime = date("%a %H:%M", at) }
    end
  end
  return out
end

-- What the tab shows: { empty = true } with nothing to list; otherwise { summary, banner (for
-- another officer), readOnly, groups = { { heading, rows } }, practice = { heading, rows } or nil }.
-- A row has its award's `key`. A not confirmed row has `notConfirmed`, `refusal` (why the last
-- choice was refused, even for a player no longer loot master), and for the loot master `choices`
-- (Popup.Choices); a voided one `voided` and its `note`. A confirmed one (or one made on the site)
-- has `undoable`, its `refusal`, and for the loot master `undo` (Popup.UndoButton: enabled,
-- tooltip). A voided confirmed award not replaced has `needsWinner`, and is followed by a row with
-- `winnerNeeded`, its key, boss, item and time. A hand-out of this raid not yet answered has a row
-- with `answerNeeded`, its `handout` (for OutsideHandout.Ask), boss, item, winner and time.
function UI.AwardsView()
  local raidId = ns.Selection.Status().activeRaid
  local snapshot = ns.Raids.Get(raidId)
  local rows, practice, order, byBoss = {}, {}, {}, {}
  local name, me = master()
  -- With Practice mode on, the practice awards held with no raid (a Test drop's) join the practice
  -- group whatever raid is selected; their Undo is the player's own, as Popup.Undo allows.
  local listed = { { ns.Raids.Awards(raidId) } }
  if ns.Practice() then listed[2] = { ns.Raids.NoRaidAwards(), true } end
  for _, list in ipairs(listed) do
    for _, award in ipairs(list[1]) do
      if not list[2] or award.practice then
        local r = row(snapshot, award)
        if me and r.notConfirmed then r.choices = ns.Popup.Choices(r.key) end
        if (me or list[2]) and r.undoable then r.undo = ns.Popup.UndoButton(r.key) end
        if r.notConfirmed or r.undoable then r.refusal = ns.Popup.Refusal(r.key) end
        if award.practice then practice[#practice + 1] = r else rows[#rows + 1] = r end
      end
    end
  end
  for _, h in ipairs(ns.OutsideHandout.Unanswered()) do
    -- A practice one (a Test drop's) goes in the practice group whatever raid is selected.
    if h.practice or raidId and h.raid == raidId then
      local r = { answerNeeded = true, handout = h, boss = bossName(snapshot, h.boss or h.picked),
        item = parts.itemText(h.item), winner = plain(h.winner), at = h.at, time = date("%H:%M", h.at),
        practiceTime = date("%a %H:%M", h.at) }
      if h.practice then practice[#practice + 1] = r else rows[#rows + 1] = r end
    end
  end
  local view = { readOnly = not me, banner = name and not me and BANNER:format(plain(name)) or nil }
  if #rows == 0 and #practice == 0 then
    view.empty = true
    return view
  end
  rows = ordered(rows)
  local standing, unconfirmed, needed, unanswered = 0, 0, 0, 0
  for _, r in ipairs(rows) do
    if not (r.voided or r.winnerNeeded or r.answerNeeded) then standing = standing + 1 end
    if r.notConfirmed then unconfirmed = unconfirmed + 1 end
    if r.winnerNeeded then needed = needed + 1 end
    if r.answerNeeded then unanswered = unanswered + 1 end
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
  if needed > 0 then counts[#counts + 1] = needed .. " needs a winner" end
  if unanswered > 0 then counts[#counts + 1] = unanswered .. " needs an answer" end
  view.summary = table.concat(counts, " · ")
  if #practice > 0 then
    view.practice = { heading = "Practice awards (" .. #practice .. ") · never sent to the guild site",
      rows = ordered(practice) }
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

-- A button greyed for another officer, with nothing behind it, from pool.
local function greyIn(pool, index, label, width, x, y)
  local b = pool[index]
  if not b then
    b = newButton(tab.child, label, width, BUTTON_HEIGHT)
    b:Disable()
    b.background:SetColorTexture(0.2, 0.2, 0.2, 1)
    b.label:SetTextColor(0.5, 0.5, 0.5)
    pool[index] = b
  end
  b:ClearAllPoints()
  b:SetPoint("TOPLEFT", tab.child, "TOPLEFT", x, -y)
  b:Show()
  return b
end

-- The three change buttons of a not confirmed row: greyed, with nothing behind them.
local function greyButton(index, x, y)
  greyIn(tab.buttons, index, BUTTONS[(index - 1) % 3 + 1], 86, x, y)
end

-- The loot master's Undo on a confirmed row: voids the award and posts its undo line (Popup.Undo,
-- through Popup.Choose). Greyed in a boss fight, its tooltip saying why.
local function undoButton(index, y, key, undo)
  local b = tab.undos[index]
  if not b then
    b = PopupFrame.TipButton(tab.child, UNDO_WIDTH)
    b:SetScript("OnClick", function(self)
      if self.undo.enabled then
        ns.Popup.Choose(self.key, "undo")
        UI.RefreshAwards()
      end
    end)
    tab.undos[index] = b
  end
  PopupFrame.SetButton(b, "Undo", undo.enabled)
  b.key, b.undo, b.tip = key, undo, undo.tooltip
  b:ClearAllPoints()
  b:SetPoint("TOPLEFT", tab.child, "TOPLEFT", CONTENT_WIDTH - UNDO_WIDTH, -y)
  b:Show()
  return b
end

-- Opens the picker under the award's NEEDS A WINNER row (one at a time), or closes it when open
-- there. A new picker takes the correction's ids now, so its line is the one posted.
local function togglePicker(key)
  if tab.pickOpen == key then
    tab.pickOpen, tab.pick = nil, nil
  else
    tab.pickOpen, tab.unposted = key, nil
    tab.pick = { id = ns.Records.NewId("replace"), newKey = ns.Records.NewId("award"), offset = 0,
      menuOffset = 0 }
    tab.scrollTo = true
  end
  UI.RefreshAwards()
end

-- The loot master's Pick winner on a NEEDS A WINNER row: opens or closes its picker.
local function pickButton(index, y, key)
  local b = tab.picks[index]
  if not b then
    b = newButton(tab.child, "Pick winner", PICK_WIDTH, BUTTON_HEIGHT)
    b:SetScript("OnClick", function(self) togglePicker(self.key) end)
    tab.picks[index] = b
  end
  b.key = key
  b:ClearAllPoints()
  b:SetPoint("TOPLEFT", tab.child, "TOPLEFT", CONTENT_WIDTH - PICK_WIDTH, -y)
  b:Show()
  return b
end

-- Answer on a NEEDS AN ANSWER row: asks the hand-out's question again (or queues it, or holds it
-- through a boss fight). Enabled for anyone: only the computer that made the hand-out has the row.
local function answerButton(index, y, handout)
  local b = tab.answers[index]
  if not b then
    b = newButton(tab.child, "Answer", PICK_WIDTH, BUTTON_HEIGHT)
    b:SetScript("OnClick", function(self) ns.OutsideHandout.Ask(self.handout) end)
    tab.answers[index] = b
  end
  b.handout = handout
  b:ClearAllPoints()
  b:SetPoint("TOPLEFT", tab.child, "TOPLEFT", CONTENT_WIDTH - PICK_WIDTH, -y)
  b:Show()
  return b
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

-- Puts a piece of the picker x across and y down its box, and shows it.
local function at(piece, x, y)
  piece:ClearAllPoints()
  piece:SetPoint("TOPLEFT", tab.picker, "TOPLEFT", x, -y)
  piece:Show()
end

-- The picker's edit box: onChange(text) follows the officer's typing.
local function editBox(parent, width, letters, onChange)
  local e = CreateFrame("EditBox", nil, parent)
  e:SetSize(width, 20)
  e:SetAutoFocus(false)
  e:SetMaxLetters(letters)
  e:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
  e:SetTextInsets(4, 4, 0, 0)
  e:SetScript("OnEscapePressed", e.ClearFocus)
  e:SetScript("OnEnterPressed", e.ClearFocus)
  e:SetScript("OnTextChanged", function(self, typed)
    if typed then onChange(self:GetText()) end
  end)
  e.background = e:CreateTexture(nil, "BACKGROUND")
  e.background:SetAllPoints()
  e.background:SetColorTexture(0, 0, 0, 0.8)
  return e
end

-- Sets the edit box's text, unless it holds it already (so typing keeps its place).
local function setEdit(e, text)
  if e:GetText() ~= text then e:SetText(text) end
end

-- What a click on a choice of the picker does: it becomes the pick.
local function choosePick(kind, char)
  local pick = tab.pick
  if not pick then return end
  pick.kind, pick.char = kind, char
  if kind ~= "roll" then pick.menuOpen = false end
  UI.RefreshAwards()
end

-- One of the picker's radio choices: a row with its radio, name, badge and hint.
local function newChoice()
  local b = CreateFrame("Button", nil, tab.picker)
  b:SetSize(BOX_WIDTH - 12, CHOICE_HEIGHT)
  b.background = b:CreateTexture(nil, "BACKGROUND")
  b.background:SetAllPoints()
  b.radio = newText(b, "GameFontHighlightSmall")
  b.radio:SetPoint("LEFT", b, "LEFT", 6, 0)
  b.name = newText(b, "GameFontHighlight")
  b.name:SetPoint("LEFT", b, "LEFT", 28, 0)
  b.badgeBack = b:CreateTexture(nil, "ARTWORK")
  b.badge = newText(b, "GameFontHighlightSmall")
  b.hint = newText(b, "GameFontDisableSmall")
  b:SetScript("OnClick", function(self) choosePick(self.kind, self.char) end)
  return b
end

-- Draws a choice at y: c = { name, badge, colour (the badge's), hint, selected, enabled }. A greyed
-- one (enabled false) shows its hint in the badge's place.
local function drawChoice(b, c, y)
  at(b, 6, y)
  b.radio:SetText(parts.RADIO[c.selected and true or false])
  b.name:SetText(c.name)
  local shade = c.enabled and 1 or 0.5
  b.name:SetTextColor(shade, shade, shade)
  b.badge:ClearAllPoints()
  b.badgeBack:ClearAllPoints()
  b.hint:ClearAllPoints()
  local x = 184
  if c.badge then
    b.badge:SetPoint("LEFT", b, "LEFT", x + 4, 0)
    b.badge:SetText(c.badge:upper())
    b.badgeBack:SetPoint("LEFT", b, "LEFT", x, 0)
    b.badgeBack:SetSize(b.badge:GetStringWidth() + 8, 16)
    b.badgeBack:SetColorTexture(c.colour[1], c.colour[2], c.colour[3], 1)
    b.badge:Show()
    b.badgeBack:Show()
    x = x + b.badge:GetStringWidth() + 18
  else
    b.badge:SetText("")
    b.badge:Hide()
    b.badgeBack:Hide()
  end
  b.hint:SetPoint("LEFT", b, "LEFT", x, 0)
  b.hint:SetText(c.hint or "")
  if c.selected then b.background:SetColorTexture(0.25, 0.2, 0.05, 1)
  else b.background:SetColorTexture(0, 0, 0, 0) end
  if c.enabled then b:Enable() else b:Disable() end
  return y + CHOICE_HEIGHT + 2
end

local function badgeColour(kind)
  return kind == "db" and BADGE_DB or PopupFrame.BADGE_COLORS[kind]
end

-- The raid members' list, dropped from the member button: up to MEMBERS_SHOWN names from the
-- pick's menuOffset on, the chosen one ticked; the wheel scrolls the rest.
local function drawMenu(members)
  local menu, pick = tab.menu, tab.pick
  pick.menuOffset = math.max(0, math.min(pick.menuOffset, #members - MEMBERS_SHOWN))
  menu:ClearAllPoints()
  menu:SetPoint("TOPLEFT", tab.picker.member, "BOTTOMLEFT", 0, -2)
  local y, shown = 26, math.min(MEMBERS_SHOWN, #members)
  for i = 1, shown do
    local member = members[pick.menuOffset + i]
    local entry = menu.entries[i]
    if not entry then
      entry = newButton(menu, "", 178, 18)
      entry.background:SetColorTexture(0.08, 0.08, 0.08, 1)
      entry.label:ClearAllPoints()
      entry.label:SetPoint("LEFT", entry, "LEFT", 20, 0)
      entry.tick = entry:CreateTexture(nil, "ARTWORK")
      entry.tick:SetSize(14, 14)
      entry.tick:SetPoint("LEFT", entry, "LEFT", 2, 0)
      entry.tick:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
      entry:SetScript("OnClick", function(self)
        tab.pick.member, tab.pick.menuOpen = self.name, false
        UI.RefreshAwards()
      end)
      menu.entries[i] = entry
    end
    entry.name = member.name
    entry.label:SetText(plain(member.name))
    if member.selected then entry.tick:Show() else entry.tick:Hide() end
    entry:ClearAllPoints()
    entry:SetPoint("TOPLEFT", menu, "TOPLEFT", 6, -y)
    entry:Show()
    y = y + 20
  end
  for i = shown + 1, #menu.entries do menu.entries[i]:Hide() end
  local below, above = #members - pick.menuOffset - shown, pick.menuOffset
  menu.more:ClearAllPoints()
  if below > 0 or above > 0 then
    menu.more:SetPoint("TOPLEFT", menu, "TOPLEFT", 8, -(y + 2))
    menu.more:SetText(below > 0 and (ARROW_DOWN .. " " .. below .. " more · scroll")
      or (ARROW_UP .. " " .. above .. " more · scroll"))
    menu.more:Show()
    y = y + 16
  else
    menu.more:Hide()
  end
  menu:SetHeight(y + 6)
  menu:Show()
end

-- Draws the picker (Popup.Picker's model) in its box at y under its row; returns the new y.
local function drawPicker(model, y)
  local p, pick = tab.picker, tab.pick
  tab.pickShown = true
  local top = 8
  p.intro:SetWidth(BOX_WIDTH - 16)
  at(p.intro, 8, top)
  p.intro:SetText(model.intro)
  top = top + p.intro:GetStringHeight() + 6
  if model.fight then
    parts.setNote(p.fight, "warn", model.fight)
    at(p.fight, 6, top)
    top = top + p.fight:GetHeight() + 6
  else
    p.fight:Hide()
  end
  at(p.reserved, 8, top)
  top = top + 16
  -- The holders, HOLDERS_SHOWN at a time from the pick's offset; the wheel scrolls the rest.
  local holders = model.holders
  pick.offset = math.max(0, math.min(pick.offset, #holders - HOLDERS_SHOWN))
  local shown = math.min(HOLDERS_SHOWN, #holders)
  for i = 1, shown do
    local h = holders[pick.offset + i]
    local b = p.holders[i]
    if not b then
      b = newChoice()
      b:EnableMouseWheel(true)
      b:SetScript("OnMouseWheel", function(_, delta)
        tab.pick.offset = tab.pick.offset - delta
        UI.RefreshAwards()
      end)
      p.holders[i] = b
    end
    b.kind, b.char = "holder", h.char
    top = drawChoice(b, { name = plain(h.char), badge = h.available and h.method or nil,
      colour = badgeColour(h.kind), hint = not h.available and h.reason or nil, selected = h.selected,
      enabled = h.available }, top)
  end
  for i = shown + 1, #p.holders do p.holders[i]:Hide() end
  if #holders > HOLDERS_SHOWN then
    local below = #holders - pick.offset - shown
    p.more:SetText((below > 0 and ARROW_DOWN or ARROW_UP) .. " " .. #holders
      .. " reserve holders · scroll for more")
    at(p.more, 10, top)
    top = top + 16
  else
    p.more:Hide()
  end
  if model.empty then
    p.empty:SetText(model.empty)
    at(p.empty, 10, top + 2)
    top = top + 18
  else
    p.empty:Hide()
  end
  at(p.others, 8, top + 2)
  top = top + 18
  p.roll.kind = "roll"
  top = drawChoice(p.roll, { name = "Someone else in the raid", badge = "Open roll",
    colour = badgeColour("open"),
    selected = model.roll.selected, enabled = true }, top)
  if model.roll.selected then
    local member = model.roll.member and plain(model.roll.member) or "Choose a raid member"
    PopupFrame.SetButton(p.member, member, true)
    at(p.member, 34, top)
    p.rollLabel:SetText("Roll")
    at(p.rollLabel, 214, top + 4)
    setEdit(p.rollEdit, model.roll.roll)
    if model.roll.bad then p.rollEdit:SetTextColor(1, 0.35, 0.35) else p.rollEdit:SetTextColor(1, 1, 1) end
    at(p.rollEdit, 244, top)
    top = top + 26
    if pick.menuOpen then drawMenu(model.roll.members) else tab.menu:Hide() end
  else
    p.member:Hide()
    p.rollLabel:Hide()
    p.rollEdit:Hide()
    tab.menu:Hide()
  end
  p.db.kind = "db"
  top = drawChoice(p.db, { name = "Disenchant/bank", badge = "Disenchant/bank", colour = badgeColour("db"),
    selected = model.db.selected, enabled = true }, top)
  if model.again then
    p.again.kind = "again"
    top = drawChoice(p.again, { name = plain(model.again.char), badge = model.again.method,
      colour = badgeColour(model.again.kind), hint = "had it before: cancels the undo",
      selected = model.again.selected, enabled = true }, top)
  else
    p.again:Hide()
  end
  at(p.noteLabel, 8, top + 4)
  top = top + 20
  setEdit(p.noteEdit, model.note)
  at(p.noteEdit, 6, top)
  top = top + 28
  -- The line Post correction posts, or why it can't yet, in its own dark panel.
  at(p.previewBack, 6, top)
  p.previewHead:SetText("Posts in " .. ns.Popup.ChatName())
  at(p.previewHead, 12, top + 6)
  p.preview:SetText(model.line or model.text)
  if model.line then p.preview:SetTextColor(1, 0.5, 0.25) else p.preview:SetTextColor(0.7, 0.7, 0.7) end
  at(p.preview, 12, top + 22)
  local panel = 28 + p.preview:GetStringHeight()
  p.previewBack:SetSize(BOX_WIDTH - 12, panel)
  top = top + panel + 8
  PopupFrame.SetButton(p.post, "Post correction", model.post.enabled)
  p.post.tip = model.post.tooltip
  at(p.post, 6, top)
  PopupFrame.SetButton(p.cancel, "Cancel", true)
  at(p.cancel, 132, top)
  if model.locked then
    p.locked:SetText(model.locked)
    at(p.locked, 222, top + 4)
  else
    p.locked:Hide()
  end
  top = top + 26
  if model.refusal then
    p.refusal:SetText(model.refusal)
    at(p.refusal, 8, top)
    top = top + p.refusal:GetStringHeight() + 4
  else
    p.refusal:Hide()
  end
  p:ClearAllPoints()
  p:SetPoint("TOPLEFT", tab.child, "TOPLEFT", BOX_X, -y)
  p:SetSize(BOX_WIDTH, top + 4)
  p:Show()
  if tab.scrollTo then tab.scrollTo = y end
  return y + top + 8 + ROW_GAP
end

-- Post correction: records and posts (Popup.Correct). Once recorded the picker closes, and a line
-- that couldn't be posted leaves the window's note; a refusal keeps it open, saying why.
local function postCorrection()
  local op, unposted = ns.Popup.Correct(tab.pickOpen, tab.pick)
  if op then
    tab.pickOpen, tab.pick, tab.unposted = nil, nil, unposted
  end
  UI.RefreshAwards()
end

-- The picker's pieces, made once.
local function buildPicker()
  local p = PopupFrame.NewBox(tab.child)
  tab.picker = p
  p.intro = newText(p, "GameFontHighlightSmall")
  p.intro:SetJustifyH("LEFT")
  p.fight = parts.newNote(p)
  p.fight:SetWidth(BOX_WIDTH - 12)
  p.fight.text:SetWidth(BOX_WIDTH - 24)
  p.reserved = newText(p, "GameFontNormalSmall")
  p.reserved:SetText("Reserved it")
  p.others = newText(p, "GameFontNormalSmall")
  p.others:SetText("Anyone else")
  p.more = newText(p, "GameFontDisableSmall")
  p.empty = newText(p, "GameFontDisableSmall")
  p.holders = {}
  p.roll, p.db, p.again = newChoice(), newChoice(), newChoice()
  p.member = PopupFrame.TipButton(p, 170)
  p.member:SetScript("OnClick", function()
    tab.pick.menuOpen = not tab.pick.menuOpen
    UI.RefreshAwards()
  end)
  p.rollLabel = newText(p, "GameFontHighlightSmall")
  p.rollEdit = editBox(p, 44, 3, function(text)
    tab.pick.roll = text
    UI.RefreshAwards()
  end)
  p.noteLabel = newText(p, "GameFontHighlightSmall")
  p.noteLabel:SetText(NOTE_LABEL)
  p.noteEdit = editBox(p, BOX_WIDTH - 12, 200, function(text)
    tab.pick.note = text
    UI.RefreshAwards()
  end)
  p.previewBack = p:CreateTexture(nil, "BORDER")
  p.previewBack:SetColorTexture(0.1, 0.1, 0.1, 1)
  p.previewHead = newText(p, "GameFontNormalSmall")
  p.preview = newText(p, "GameFontHighlightSmall")
  p.preview:SetWidth(BOX_WIDTH - 24)
  p.preview:SetJustifyH("LEFT")
  p.post = PopupFrame.TipButton(p, 120)
  p.post:SetScript("OnClick", function(self)
    if self:IsEnabled() then postCorrection() end
  end)
  p.cancel = PopupFrame.TipButton(p, 80)
  p.cancel:SetScript("OnClick", function() togglePicker(tab.pickOpen) end)
  p.locked = newText(p, "GameFontDisableSmall")
  p.refusal = newText(p, "GameFontHighlightSmall")
  p.refusal:SetTextColor(1, 0.35, 0.35)
  p.refusal:SetWidth(BOX_WIDTH - 16)

  -- The raid members' list, dropped from the member button.
  local menu = CreateFrame("Frame", nil, tab.child)
  tab.menu = menu
  menu:SetFrameStrata("TOOLTIP")
  menu:SetSize(190, 100)
  menu.background = menu:CreateTexture(nil, "BACKGROUND")
  menu.background:SetAllPoints()
  menu.background:SetColorTexture(0.08, 0.08, 0.08, 1)
  menu.title = newText(menu, "GameFontNormal")
  menu.title:SetPoint("TOPLEFT", menu, "TOPLEFT", 8, -6)
  menu.title:SetText("Who has it now?")
  menu.more = newText(menu, "GameFontDisableSmall")
  menu.entries = {}
  menu:EnableMouseWheel(true)
  menu:SetScript("OnMouseWheel", function(_, delta)
    tab.pick.menuOffset = tab.pick.menuOffset - delta
    UI.RefreshAwards()
  end)
  menu:Hide()
end

-- The line under a row given by Pick winner: "Corrected HH:MM", at the right under its Undo (the
-- row has no room beside it). Returns the new y.
local function correctedLine(index, y, text)
  local line = tab.correcteds[index]
  if not line then
    line = newText(tab.child, "GameFontDisableSmall")
    line:SetJustifyH("RIGHT")
    tab.correcteds[index] = line
  end
  line:ClearAllPoints()
  line:SetPoint("TOPRIGHT", tab.child, "TOPLEFT", CONTENT_WIDTH, -y)
  line:SetText(text)
  line:Show()
  return y + line:GetStringHeight() + ROW_GAP
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
  put(shown.winner, "winner", y, r.winnerNeeded and NEEDS_WINNER
    or r.answerNeeded and NEEDS_ANSWER:format(r.winner)
    or colour(r.winner) .. (r.notConfirmed and " " .. AMBER:format("NOT CONFIRMED") or ""))
  put(shown.how, "how", y, r.how and colour(r.how) or "")
  put(shown.roll, "roll", y, r.roll and colour(tostring(r.roll)) or "")
  -- Undo takes the note's place on a practice row; the group's heading says practice.
  put(shown.note, "note", y, r.note or (practice and not (r.undoable or r.winnerNeeded)
    and AMBER:format("Practice")) or "")
  local line = { time = shown.time, item = shown.item, winner = shown.winner, how = shown.how,
    roll = shown.roll, note = shown.note, voided = r.voided, notConfirmed = r.notConfirmed,
    winnerNeeded = r.winnerNeeded, answerNeeded = r.answerNeeded }
  tab.shown[#tab.shown + 1] = line
  if r.voided then
    used.strikes = used.strikes + 1
    strike(used.strikes, y)
  end
  -- Undo, or Pick winner, at the row's right end: the loot master's, or greyed for another officer.
  if r.undo then
    used.undos = used.undos + 1
    line.undo = undoButton(used.undos, y, r.key, r.undo)
  elseif r.undoable then
    used.undoGreys = used.undoGreys + 1
    line.undo = greyIn(tab.undoGreys, used.undoGreys, "Undo", UNDO_WIDTH, CONTENT_WIDTH - UNDO_WIDTH, y)
  elseif r.winnerNeeded and not tab.view.readOnly then
    used.picks = used.picks + 1
    line.pick = pickButton(used.picks, y, r.key)
  elseif r.winnerNeeded then
    used.pickGreys = used.pickGreys + 1
    line.pick = greyIn(tab.pickGreys, used.pickGreys, "Pick winner", PICK_WIDTH,
      CONTENT_WIDTH - PICK_WIDTH, y)
  elseif r.answerNeeded then
    used.answers = used.answers + 1
    line.answer = answerButton(used.answers, y, r.handout)
  end
  y = y + math.max(shown.item:GetStringHeight(), shown.winner:GetStringHeight(),
    shown.how:GetStringHeight(), (line.undo or line.pick or line.answer) and BUTTON_HEIGHT or 0) + ROW_GAP
  if r.corrected then
    used.correcteds = used.correcteds + 1
    y = correctedLine(used.correcteds, y, r.corrected)
    line.corrected = tab.correcteds[used.correcteds]
  end
  local model = line.pick and tab.pickOpen == r.key and not tab.view.readOnly
    and ns.Popup.Picker(r.key, tab.pick)
  if model then
    y = drawPicker(model, y)
    line.picker = tab.picker
  end
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
  if r.refusal then
    used.refusals = used.refusals + 1
    y = refusal(used.refusals, y, r.refusal)
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
    tab.buttons, tab.choices, tab.refusals, tab.strikes, tab.undos, tab.undoGreys, tab.picks, tab.pickGreys,
    tab.correcteds, tab.answers })
  tab.list:Hide()
  tab.listShown = false
  -- The picker hides only once it's known not to be drawn: hiding it would take the keyboard from
  -- its note box, which redraws the tab on every letter typed.
  tab.pickShown = false
  -- A correction recorded but not posted: a note above the summary, until the next picker opens.
  local top = 0
  if tab.unposted then
    parts.setNote(tab.notice, "warn", tab.unposted)
    tab.notice:Show()
    top = tab.notice:GetHeight() + 4
  else
    tab.notice:Hide()
  end
  local function anchor(piece, x, y)
    piece:ClearAllPoints()
    piece:SetPoint("TOPLEFT", tab.content, "TOPLEFT", x, -(y + top))
  end
  anchor(tab.banner, 4, 2)
  anchor(tab.summary, 4, 20)
  anchor(tab.columns, 0, 36)
  anchor(tab.scroll, 0, 54)
  tab.scroll:SetPoint("BOTTOMRIGHT", tab.content, "BOTTOMRIGHT", 0, 0)
  tab.shown = {}
  tab.practiceToggle:Hide()
  local list = not view.empty
  setShown({ tab.summary, tab.columns, tab.scroll }, list)
  setShown({ tab.title, tab.hint }, not list)
  if view.banner then tab.banner:Show() tab.banner:SetText(view.banner) else tab.banner:Hide() end
  if list then
    tab.summary:SetText(view.summary)
    local used = { rows = 0, headings = 0, buttons = 0, choices = 0, refusals = 0, strikes = 0, undos = 0,
      undoGreys = 0, picks = 0, pickGreys = 0, correcteds = 0, answers = 0 }
    local y = 0
    for _, group in ipairs(view.groups or {}) do
      y = drawHeading(group.heading, y, used)
      for _, r in ipairs(group.rows) do y = drawRow(r, y, used) end
    end
    if view.practice then y = drawPractice(view, y + 6, used) end
    tab.child:SetHeight(y)
  end
  -- The list stays open only while its row is drawn and still not confirmed; the picker only while
  -- its row is drawn and still needs a winner. A picker just opened is scrolled into view.
  if not tab.listShown then tab.elseOpen = nil end
  if not tab.pickShown then
    tab.picker:Hide()
    tab.pickOpen, tab.pick = nil, nil
    tab.menu:Hide()
  end
  if type(tab.scrollTo) == "number" then
    if tab.scroll.UpdateScrollChildRect then tab.scroll:UpdateScrollChildRect() end
    tab.scroll:SetVerticalScroll(math.max(0, math.min(tab.scrollTo - 2 * HEADING_HEIGHT,
      tab.scroll:GetVerticalScrollRange())))
  end
  tab.scrollTo = nil
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
  tab.choices, tab.refusals, tab.undos, tab.undoGreys, tab.picks, tab.pickGreys = {}, {}, {}, {}, {}, {}
  tab.correcteds, tab.answers = {}, {}

  -- The note of a correction recorded but not posted, above everything.
  tab.notice = parts.newNote(content)
  tab.notice:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -2)
  tab.notice:Hide()

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
  -- Give to someone else's list, the pop-up's own: a name's Give, or the Disenchant/bank line's,
  -- hands out and closes it.
  tab.list = PopupFrame.NewList(tab.child, function(char, action)
    if ns.Popup.Choose(tab.listKey, action or "giveelse", char) then tab.elseOpen = nil end
    UI.RefreshAwards()
  end, function()
    tab.elseOpen = nil
    UI.RefreshAwards()
  end)

  buildPicker()

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
