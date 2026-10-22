-- OutsideHandout: the question after a hand-out made from the game's own loot menu (#21; design/9-loot-ui,
-- the outside-handout state). Tracking reports such a hand-out ("outside", at or above the loot
-- threshold); the officer is asked how it was won, pre-filled from the reserves, and the answer is
-- recorded as an award (confirmed: the game already handed it out), sent to the other officers
-- (Hub.SendOwn) and posted in raid chat. Nothing is recorded until the officer answers. Later puts it
-- off: it joins this session's list of unanswered hand-outs (Unanswered), kept in memory only.
-- Several hand-outs are asked one at a time, in order; in a boss fight the question waits until the
-- fight ends, as notices do. On a run that is not a guild run nothing is asked or kept.
local _, ns = ...

local OutsideHandout = {}
ns.OutsideHandout = OutsideHandout

local WIDTH = 460
local GREY = "|cff808080%s|r"
local HINT = "Recording it posts the award line in raid chat."
local CHOICES = {
  { method = "HR", label = "Hard reserve", held = "(they hard-reserved it)" },
  { method = "SR", label = "Soft reserve", held = "(they soft-reserved it)" },
  { method = "OPEN_ROLL", label = "Open roll, roll:" },
  { method = "DISENCHANT_BANK", label = "Disenchant/bank" },
}

local bare = ns.Rules.Bare
local p, frame   -- UI's drawing parts, and the question's frame
-- The question on screen: { handout, held (the winner's reserve kind), user, method, roll, boss, askBoss }.
local shown
local queue = {} -- hand-outs waiting to be asked, oldest first
local unanswered = {} -- hand-outs put off with Later this session, oldest first
local fighting = false
local closing = false -- the add-on itself is hiding the question

local function plain(text) return (tostring(text):gsub("|", "||")) end

-- The winner's reserve of the item in the hand-out's raid: its kind ("HR" or "SR") and user, or nil.
local function reserveOf(handout)
  local snapshot = ns.Raids.Get(handout.raid)
  local holders = snapshot and (snapshot.reserves[handout.item] or snapshot.reserves[tostring(handout.item)])
  local found
  for _, h in ipairs(holders or {}) do
    if bare(h.char) == bare(handout.winner) and (not found or h.kind == "HR") then found = h end
  end
  if found then return found.kind, found.user end
end

-- The roll typed in the box, as a whole number from 1 to 100, or nil.
local function rollOf(text)
  text = strtrim(text or "")
  local roll = text:match("^%d+$") and tonumber(text)
  return roll and roll >= 1 and roll <= 100 and roll or nil
end

-- Whether Record and announce can be clicked: a choice made, an open roll's roll typed, a boss picked.
local function ready()
  return shown.method ~= nil and (shown.method ~= "OPEN_ROLL" or rollOf(shown.roll) ~= nil)
    and (not shown.askBoss or shown.boss ~= nil)
end

local function setButton(b, label, enabled)
  b.label:SetText(label)
  b:SetWidth(math.max(90, b.label:GetStringWidth() + 24))
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

local function place(piece, y, x)
  piece:ClearAllPoints()
  if x then piece:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -y)
  else piece:SetPoint("TOP", frame, "TOP", 0, -y) end
  piece:Show()
end

local function bossName(id)
  for _, row in ipairs((ns.Raids.Get(shown.handout.raid) or { bosses = {} }).bosses) do
    if row.id == id then return row.name end
  end
end

-- The boss list under the boss button: the pop-up's, with the picked boss marked.
local function drawMenu()
  local list = ns.Popup.BossMenu(shown.boss, shown.handout.raid)
  local menu = frame.menu
  menu.title:SetText(list.title)
  local y = 26
  for i, item in ipairs(list.menu) do
    local entry = menu.entries[i]
    if not entry then
      entry = p.newButton(menu, "", 208, 18)
      entry.label:ClearAllPoints()
      entry.label:SetPoint("LEFT", entry, "LEFT", 4, 0)
      entry:SetScript("OnClick", function(self) OutsideHandout.PickBoss(self.bossId) end)
      menu.entries[i] = entry
    end
    entry.bossId = item.id
    entry.label:SetText((item.selected and "> " or "   ") .. item.name
      .. (item.killed and ("  · killed " .. item.killed) or ""))
    entry.background:SetColorTexture(0.08, 0.08, 0.08, 1)
    entry:ClearAllPoints()
    entry:SetPoint("TOPLEFT", menu, "TOPLEFT", 6, -y)
    entry:Show()
    y = y + 20
  end
  for i = #list.menu + 1, #menu.entries do menu.entries[i]:Hide() end
  menu:SetHeight(y + 6)
end

-- Draws the question in shown: the lead, the four choices (the roll box on Open roll), the boss when
-- it is asked, the hint and the two buttons, top to bottom.
local function draw()
  local h = shown.handout
  local y = 18
  frame.lead:SetText("You gave " .. h.link .. " to " .. p.WHITE:format(plain(h.winner))
    .. " from the game's loot menu. How was it won?")
  place(frame.lead, y)
  y = y + frame.lead:GetStringHeight() + 12
  for i, c in ipairs(CHOICES) do
    local r = frame.rows[i]
    r.radio:SetText(p.RADIO[shown.method == c.method])
    local note = shown.held == c.method and c.held and (" " .. GREY:format(c.held)) or ""
    r.label:SetText(c.label .. note)
    place(r, y, 40)
    if c.method == "OPEN_ROLL" then
      frame.roll:ClearAllPoints()
      frame.roll:SetPoint("LEFT", r, "LEFT", 28 + r.label:GetStringWidth() + 8, 0)
      frame.roll:Show()
    end
    y = y + 24
  end
  frame.bossLabel:Hide()
  frame.boss:Hide()
  frame.menu:Hide()
  if shown.askBoss then
    y = y + 6
    place(frame.bossLabel, y + 4, 40)
    place(frame.boss, y, 84)
    frame.boss.label:SetText((bossName(shown.boss) or "Choose") .. " ▾")
    drawMenu()
    y = y + 30
  end
  y = y + 6
  frame.hint:SetText(HINT)
  place(frame.hint, y)
  y = y + frame.hint:GetStringHeight() + 12
  setButton(frame.record, "Record and announce", ready())
  setButton(frame.later, "Later", true)
  local left = (WIDTH - frame.record:GetWidth() - frame.later:GetWidth() - 10) / 2
  place(frame.record, y, left)
  place(frame.later, y, left + frame.record:GetWidth() + 10)
  frame:SetHeight(y + 24 + 20)
  frame:Show()
end

local function hide()
  shown = nil
  closing = true
  frame:Hide()
  closing = false
end

local showNext

-- Asks about the next waiting hand-out, unless one is on screen or a boss fight is on. On a run
-- that is not a guild run the waiting ones are dropped: nothing is asked or kept.
showNext = function()
  if shown or fighting then return end
  if ns.Selection.IsQuiet() then
    queue = {}
    return
  end
  local h = table.remove(queue, 1)
  if not h then return end
  local held, user = reserveOf(h)
  shown = { handout = h, held = held, user = user, method = held or "OPEN_ROLL", roll = "",
    boss = h.boss or h.picked, askBoss = h.boss == nil and h.raid ~= nil }
  frame.roll:SetText("")
  draw()
end

-- Opens the question for a hand-out ({ winner, link, item, quantity, at, raid (the raid awards went to
-- when it was handed out: its award goes there; nil for none, held as no raid), boss (the loot
-- window's boss row id, or nil to ask), picked (the boss the officer picked when asked before) }), or
-- queues it behind the one on screen; in a boss fight it waits until the fight ends.
-- One from the unanswered list leaves it while it is asked. Used for each outside hand-out, and for
-- answering one put off with Later (#137).
function OutsideHandout.Ask(handout)
  if ns.Selection.IsQuiet() then return end
  for i, h in ipairs(unanswered) do
    if h == handout then table.remove(unanswered, i) break end
  end
  queue[#queue + 1] = handout
  showNext()
end

-- This session's hand-outs put off with Later, oldest first: { winner, link, item, quantity, at, raid,
-- boss, picked }, as Ask takes them.
-- Kept in memory only; nothing in it is saved, posted or sent.
function OutsideHandout.Unanswered() return unanswered end

-- For the tests: the question on screen and the hand-outs waiting.
function OutsideHandout.Shown() return shown end
function OutsideHandout.Waiting() return queue end

-- The officer's choice: "HR", "SR", "OPEN_ROLL" or "DISENCHANT_BANK".
function OutsideHandout.Choose(method)
  if not shown then return end
  shown.method = method
  draw()
end

-- The officer picked a boss in the list (a boss row id of the selected raid).
function OutsideHandout.PickBoss(bossId)
  if not (shown and bossName(bossId)) then return end
  shown.boss = bossId
  draw()
  frame.menu:Hide()
end

-- Later: closes the question, keeps the hand-out in the unanswered list, and asks the next.
function OutsideHandout.Later()
  if not shown then return end
  local h = shown.handout
  h.picked = shown.askBoss and shown.boss or nil
  hide()
  if not ns.Selection.IsQuiet() then unanswered[#unanswered + 1] = h end
  showNext()
end

-- Record and announce (a click: it posts a chat line): records the award with the answer in the
-- hand-out's raid, confirmed, sends both operations to the other officers and posts the award line,
-- then asks the next. Returns the award operation, or nil and why: "not ready" (Record is disabled),
-- "fight" (chat is locked) or Records.Award's reasons ("not loaded": the hand-out's raid was taken
-- off the list), when the question stays open and the officer is told nothing was recorded.
function OutsideHandout.Record()
  if not (shown and ready()) then return nil, "not ready" end
  if ns.Popup.ChatLocked() then return nil, "fight" end
  if ns.Selection.IsQuiet() then
    hide()
    queue = {}
    return nil, "quiet"
  end
  local h, method, boss = shown.handout, shown.method, shown.boss
  local db = method == "DISENCHANT_BANK"
  local roll = method == "OPEN_ROLL" and rollOf(shown.roll) or nil
  local winner = not db and h.winner or nil
  local user = not db and shown.user or nil
  local op, why = ns.Records.Award({ raid = h.raid, noRaid = h.raid == nil, boss = boss, item = h.item,
    char = winner, user = user, method = method, roll = roll, practice = ns.Practice() })
  if not op then
    ns.Log("Award for " .. h.link .. " not recorded: " .. tostring(why))
    ns.Print("The award of " .. h.link .. " to " .. plain(h.winner) .. " couldn't be recorded. Type /bf log"
      .. " for why.")
    return nil, why
  end
  hide()
  ns.Hub.SendOwn(op, why)
  ns.Hub.SendOwn(ns.Records.Confirm(op.id))
  local snapshot = ns.Raids.Get(op.raid)
  local data = { raid = snapshot and snapshot.code, key = op.id, item = h.item, link = h.link, boss = boss,
    method = method, roll = roll, winner = winner, practice = op.practice }
  ns.Popup.Post("award", data, why, "Award line for " .. h.link, "The award of " .. h.link .. " to "
    .. plain(h.winner) .. " is recorded, but its raid chat line couldn't be posted.")
  ns.UI.RefreshAwards()
  showNext()
  return op, why
end

local function build()
  p = ns.UI.parts
  frame = CreateFrame("Frame", "BureaucracyForeverOutsideHandout", UIParent)
  OutsideHandout.frame = frame
  frame:SetSize(WIDTH, 260)
  frame:SetFrameStrata("DIALOG")
  frame:EnableMouse(true)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
  local background = frame:CreateTexture(nil, "BACKGROUND")
  background:SetAllPoints()
  background:SetColorTexture(0, 0, 0, 0.92)
  -- The notice window's thin grey edge (textures only: no backdrop API).
  for _, edge in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 2 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 2 },
    { "TOPLEFT", "BOTTOMLEFT", 2 }, { "TOPRIGHT", "BOTTOMRIGHT", 2 } }) do
    local line = frame:CreateTexture(nil, "BORDER")
    line:SetColorTexture(0.6, 0.6, 0.6, 1)
    line:SetPoint(edge[1], frame, edge[1], 0, 0)
    line:SetPoint(edge[2], frame, edge[2], 0, 0)
    if edge[3] then line:SetWidth(edge[3]) else line:SetHeight(edge[4]) end
  end
  frame.lead = p.newText(frame, "GameFontHighlight")
  frame.lead:SetWidth(WIDTH - 40)
  frame.hint = p.newText(frame, "GameFontHighlightSmall")
  frame.hint:SetWidth(WIDTH - 40)
  frame.rows = {}
  for i, c in ipairs(CHOICES) do
    local r = CreateFrame("Button", nil, frame)
    r:SetSize(WIDTH - 80, 20)
    r.radio = p.newText(r, "GameFontHighlightSmall")
    r.radio:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.label = p.newText(r, "GameFontHighlightSmall")
    r.label:SetPoint("LEFT", r, "LEFT", 22, 0)
    r.label:SetJustifyH("LEFT")
    r:SetScript("OnClick", function() OutsideHandout.Choose(c.method) end)
    frame.rows[i] = r
  end
  -- The open roll's roll: typing in it chooses Open roll.
  frame.roll = CreateFrame("EditBox", nil, frame)
  frame.roll:SetSize(50, 20)
  frame.roll:SetAutoFocus(false)
  frame.roll:SetMaxLetters(3)
  frame.roll:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
  frame.roll:SetTextInsets(4, 4, 0, 0)
  frame.roll:SetScript("OnEscapePressed", frame.roll.ClearFocus)
  frame.roll:SetScript("OnTextChanged", function(self, typed)
    if not (typed and shown) then return end
    shown.roll, shown.method = self:GetText(), "OPEN_ROLL"
    draw()
  end)
  local box = frame.roll:CreateTexture(nil, "BACKGROUND")
  box:SetAllPoints()
  box:SetColorTexture(0.2, 0.2, 0.2, 0.9)
  -- The boss, asked when the hand-out's boss isn't known: the pop-up's boss button and list.
  frame.bossLabel = p.newText(frame, "GameFontNormal")
  frame.bossLabel:SetText("Boss:")
  frame.boss = p.newButton(frame, "", 160, 22)
  frame.boss.background:SetColorTexture(0.08, 0.08, 0.08, 1)
  frame.menu = CreateFrame("Frame", nil, frame)
  frame.menu:SetFrameStrata("TOOLTIP")
  frame.menu:SetSize(220, 100)
  frame.menu:SetPoint("TOPLEFT", frame.boss, "BOTTOMLEFT", 0, -2)
  local menuBackground = frame.menu:CreateTexture(nil, "BACKGROUND")
  menuBackground:SetAllPoints()
  menuBackground:SetColorTexture(0.08, 0.08, 0.08, 1)
  frame.menu.title = p.newText(frame.menu, "GameFontNormal")
  frame.menu.title:SetPoint("TOPLEFT", frame.menu, "TOPLEFT", 8, -6)
  frame.menu.entries = {}
  frame.menu:Hide()
  frame.boss:SetScript("OnClick", function()
    if frame.menu:IsShown() then frame.menu:Hide() else frame.menu:Show() end
  end)
  frame.record = p.newButton(frame, "", 160)
  frame.record:SetScript("OnClick", function() OutsideHandout.Record() end)
  frame.later = p.newButton(frame, "", 90)
  frame.later:SetScript("OnClick", function() OutsideHandout.Later() end)
  -- Escape closes it, as Later does.
  frame:SetScript("OnHide", function()
    if shown and not closing then OutsideHandout.Later() end
  end)
  frame:Hide()
  table.insert(UISpecialFrames, "BureaucracyForeverOutsideHandout")
end

ns.On("ADDON_LOADED", function(name)
  if name == ns.name then build() end
end)

-- A hand-out from the game's menu: asked about, under the boss of the loot window it came from.
ns.Tracking.On("outside", function(info)
  local item = info.link and tonumber(info.link:match("item:(%d+)"))
  if not item or ns.Selection.IsQuiet() then return end
  local raidId = ns.Selection.Status().activeRaid
  OutsideHandout.Ask({ winner = info.winner, link = info.link, item = item, quantity = info.quantity,
    at = time(), raid = ns.Raids.Get(raidId) and raidId or nil, boss = ns.Popup.WindowBoss() })
end)

-- Chat is locked in a boss fight: the question on screen goes back to the front of the line, with
-- the boss picked so far, and is asked again when the fight ends.
ns.On("ENCOUNTER_START", function()
  fighting = true
  if shown then
    local h = shown.handout
    h.picked = shown.askBoss and shown.boss or nil
    table.insert(queue, 1, h)
    hide()
  end
end)

ns.On("ENCOUNTER_END", function()
  fighting = false
  showNext()
end)
