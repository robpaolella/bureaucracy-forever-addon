-- StartQuestion: the raid question at the start of a run (ADDON-SPEC.md 2.1; design/44-sync-raids, the
-- ask-* states; #53). When the player enters a raid instance in a raid group, the chooser (Hub.Chooser)
-- is asked after 5 seconds, so the other add-ons' P messages have arrived: "Is this a guild run?", the
-- loaded raids with the suggestion pre-selected and "No, not a guild run" last. A raid already selected
-- is asked about again only in a different instance (ask-again). The question only draws: the answer
-- goes through Selection, which shares it with the group (an S message). Saved beside the selection:
-- questionKept, the instance where the officer answered Keep to ask-again.
local _, ns = ...

local Q = {}
ns.StartQuestion = Q

local WAIT = 5              -- seconds after entering, for the P messages
local WIDTH = 480
local AHEAD = 12 * 60 * 60  -- a candidate starts within 12 hours (spec 7.5)
local GREEN = "|cff40ff40%s|r"
local OFF_FACTS = "The add-on stays off until you leave the group"
local PICK_LEAD = "If it's a guild run, pick its raid event. If not, choose the last option."

local p, frame              -- UI's drawing parts, and the question's frame
local shown                 -- the question on screen: { kind, held (the selection it was asked on), ... }
local asker                 -- who was asked on the last entry, by the chooser rule
local token = 0             -- the latest wait, so an older one does nothing

local function me() return ns.Rules.Bare(UnitName("player")) end

-- The raid instance the player is in, as its number and name, or nil outside one.
local function raidInstance()
  local name, kind, _, _, _, _, _, id = GetInstanceInfo()
  if kind == "raid" then return id, name end
end

-- The raid instance where the officer kept the selected raid (ask-again's Keep), saved so a /reload
-- keeps it, and only while that selection holds: { instance, at } (the selection's at).
local function kept()
  local k = ns.db.questionKept
  return k and k.at == ns.Selection.Status().at and k.instance or nil
end

-- The raid question to ask on entering instance id, or nil (spec 2.1, Asked again): every entry
-- while no raid is chosen; with one chosen, only a different instance from its own.
local function due(id)
  local status = ns.Selection.Status()
  if status.activeBy == "none" then return "entry" end
  if status.activeBy == "off" then return nil end
  local snapshot = ns.Raids.Get(status.activeRaid)
  if snapshot and snapshot.instance and snapshot.instance ~= id and kept() ~= id then return "again" end
end

-- The loaded raids for instance id: the candidates (spec 2.1) and how many are under way.
local function candidates(raids, id)
  local now, set, underWay = time(), {}, 0
  for _, raid in ipairs(raids) do
    local ends = raid.startsAt + raid.durationMin * 60
    if id and raid.instance == id and raid.startsAt <= now + AHEAD and now < ends then
      set[raid.id] = true
      if raid.startsAt <= now then underWay = underWay + 1 end
    end
  end
  return set, underWay
end

local function hide()
  shown = nil
  frame:Hide()
end

-- Puts a piece y pixels down the question, x from its left (or centred), and shows it.
local function place(piece, y, x)
  piece:ClearAllPoints()
  if x then piece:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -y)
  else piece:SetPoint("TOP", frame, "TOP", 0, -y) end
  piece:Show()
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

local draw

-- Picking a row: its radio on, the others off, and Start enabled.
local function pick(choice)
  shown.pick = choice
  draw()
end

local function row(index)
  local r = frame.rows[index]
  if r then return r end
  r = CreateFrame("Button", nil, frame)
  r:SetSize(WIDTH - 40, 32)
  r.background = r:CreateTexture(nil, "BACKGROUND")
  r.background:SetAllPoints()
  r.radio = p.newText(r, "GameFontHighlightSmall")
  r.radio:SetPoint("LEFT", r, "LEFT", 6, 0)
  r.name = p.newText(r, "GameFontHighlightSmall")
  r.name:SetPoint("TOPLEFT", r, "TOPLEFT", 28, -3)
  r.name:SetJustifyH("LEFT")
  r.facts = p.newText(r, "GameFontDisableSmall")
  r.facts:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -2)
  r.facts:SetJustifyH("LEFT")
  r:SetScript("OnClick", function(self) pick(self.choice) end)
  frame.rows[index] = r
  return r
end

-- Draws the question in shown: title, lead, hint, note, rows and buttons, top to bottom.
draw = function()
  local view = shown.view
  for _, r in ipairs(frame.rows) do r:Hide() end
  for _, b in ipairs(frame.buttons) do b:Hide() end
  frame.note:Hide()
  frame.hint:Hide()
  local y = 18
  frame.title:SetText(view.title)
  place(frame.title, y)
  y = y + 18
  frame.lead:SetText(view.lead)
  place(frame.lead, y)
  y = y + frame.lead:GetStringHeight() + 8
  if view.hint then
    frame.hint:SetText(view.hint)
    place(frame.hint, y)
    y = y + frame.hint:GetStringHeight() + 8
  end
  if view.note then
    p.setNote(frame.note, "warn", view.note)
    place(frame.note, y, 20)
    y = y + frame.note:GetHeight() + 6
  end
  local choices = {}
  for _, raid in ipairs(view.rows or {}) do choices[#choices + 1] = raid end
  if view.rows then
    choices[#choices + 1] = { choice = "off", name = "No, not a guild run", facts = OFF_FACTS }
  end
  for i, c in ipairs(choices) do
    local r, on = row(i), c.choice == shown.pick
    r.choice = c.choice
    r.radio:SetText(p.RADIO[on])
    r.name:SetText(p.WHITE:format(c.name))
    r.facts:SetText(c.facts)
    r.background:SetColorTexture(0.25, 0.2, 0.05, on and 0.6 or 0)
    if c.choice == "off" then y = y + 6 end
    place(r, y, 20)
    y = y + 34
  end
  local width = 0
  for i, b in ipairs(view.buttons) do
    local button = frame.buttons[i]
    setButton(button, b.label, not b.needsPick or shown.pick ~= nil)
    button.onClick = b.onClick
    width = width + button:GetWidth() + (i > 1 and 10 or 0)
  end
  local x = (WIDTH - width) / 2
  for i in ipairs(view.buttons) do
    local button = frame.buttons[i]
    place(button, y + 4, x)
    x = x + button:GetWidth() + 10
  end
  frame:SetHeight(y + 44)
  frame:Show()
end

-- The answer from a row: a raid (confirmed: the question's own text said the awards stay), or "off".
local function answer(confirmed)
  local choice = shown.pick
  hide()
  if choice == "off" then
    ns.Selection.ChooseOff()
    ns.UI.RefreshSync()
  elseif confirmed then
    ns.Selection.ChooseRaid(choice, true)
    ns.UI.RefreshSync()
  else
    ns.UI.Choose(choice)
  end
end

local function decideLater() hide() end

-- The loaded raids as rows, the candidates for instance id marked as matching.
local function rows(raids, id)
  local set = candidates(raids, id)
  local list = {}
  for _, raid in ipairs(raids) do
    local players = p.reserveCounts(ns.Raids.Get(raid.id))
    list[#list + 1] = { choice = raid.id,
      name = p.raidName(raid) .. (set[raid.id] and " " .. GREEN:format("Matches") or ""),
      facts = p.whenText(raid) .. " · " .. p.plural(players, "player", "players") }
  end
  return list
end

local function count(n) return n == 2 and "Two" or tostring(n) end

-- What a list question says about instance id (name for people): its lead after where, its hint, and
-- the raid to pre-select (spec 2.1: the suggestion; none for an overlap, a tie or no match).
local function listing(raids, id, name)
  local suggested = ns.Selection.Suggest(id)
  local set, underWay = candidates(raids, id)
  if suggested then return PICK_LEAD, nil, suggested end
  if underWay > 1 then
    return count(underWay) .. " raid events for " .. p.plain(name) .. " are under way. Which one is this?"
  end
  if next(set) then return PICK_LEAD end
  return nil, "No raid event is set for " .. p.plain(name) .. " (instance " .. tostring(id) .. "). If this "
    .. "is a custom raid, an officer can enter " .. tostring(id) .. " as its In-game instance number on the "
    .. "guild site."
end

-- "Your 12 Molten Core awards stay with that raid and are still sent to the site.", or nil with none.
local function staying(raidId)
  local n = #ns.Raids.Awards(raidId)
  if n == 0 then return nil end
  return string.format("Your %d %s %s with that raid and %s still sent to the site.", n,
    p.plain(ns.Raids.Get(raidId).name), n == 1 and "award stays" or "awards stay", n == 1 and "is" or "are")
end

-- The fallback note when master loot is off (ask-fallback).
local function fallback()
  if p.lootMaster() then return nil end
  local lead = UnitIsGroupLeader("player") and " and you lead the raid" or ""
  return "You're asked because master loot is off" .. lead
    .. ". Turn master loot on to hand out items with the pop-up."
end

-- ask-guild, ask-raid, ask-overlap, ask-nomatch and ask-fallback; with no raid loaded, only No or later.
local function entryView(id, name)
  local raids = ns.Raids.Status()
  local where = "You've entered " .. p.WHITE:format(p.plain(name)) .. " with a raid group."
  local view = { title = "Is this a guild run?", note = fallback(),
    buttons = { { label = "Start", needsPick = true, onClick = function() answer(false) end },
      { label = "Decide later", onClick = decideLater } } }
  if #raids == 0 then
    view.lead = where .. " Is this a guild run?"
    view.hint = "There's no raid event to choose: no raids are loaded. If it's a guild run, choose Decide "
      .. "later, then choose the raid in the Sync tab once one loads."
    view.rows = {}
    return view
  end
  local lead, hint, suggested = listing(raids, id, name)
  view.lead, view.hint, view.rows = lead and where .. " " .. lead or where, hint, rows(raids, id)
  return view, suggested
end

-- ask-again: a different raid instance from the selected raid's, with its suggestion to switch to.
-- Without one (an overlap, a tie or no match) the loaded raids are listed, nothing picked.
local function againView(id, name)
  local current = ns.Selection.Status().activeRaid
  local keepName = p.plain(ns.Raids.Get(current).name)
  local keep = { label = "Keep " .. keepName, onClick = function()
    ns.db.questionKept = { instance = id, at = ns.Selection.Status().at }
    hide()
  end }
  local suggested = ns.Selection.Suggest(id)
  local where = "You've entered " .. p.WHITE:format(p.plain(name)) .. "."
  if suggested then
    return { title = "Bureaucracy Forever", note = fallback(),
      lead = where .. " Switch the raid to " .. p.WHITE:format(p.raidName(ns.Raids.Get(suggested))) .. "?",
      hint = staying(current),
      buttons = { { label = "Switch", onClick = function()
        shown.pick = suggested
        answer(true)
      end }, keep, { label = "Not a guild run", onClick = function()
        shown.pick = "off"
        answer(true)
      end } } }
  end
  local raids = ns.Raids.Status()
  local lead, hint = listing(raids, id, name)
  local hints = {}
  for _, line in ipairs({ hint or false, staying(current) or false }) do
    if line then hints[#hints + 1] = line end
  end
  return { title = "Bureaucracy Forever", note = fallback(),
    lead = where .. " " .. (lead or "Which raid event is this?"),
    hint = #hints > 0 and table.concat(hints, " ") or nil, rows = rows(raids, id),
    buttons = { { label = "Start", needsPick = true, onClick = function() answer(true) end }, keep } }
end

local function show(kind, view, suggested)
  local status = ns.Selection.Status()
  shown = { kind = kind, view = view, pick = suggested,
    held = { activeBy = status.activeBy, activeRaid = status.activeRaid, at = status.at } }
  draw()
end

-- After the wait: asks if the player is still in instance id, in a raid group, and is the chooser.
local function check(id)
  local now, name = raidInstance()
  if now ~= id or not IsInRaid() then return end
  asker = ns.Hub.Chooser()
  if asker ~= me() then return end
  local kind = due(id)
  if kind == "entry" then show(kind, entryView(id, name))
  elseif kind == "again" then show(kind, againView(id, name)) end
end

-- Waits 5 seconds (a timer: no click is behind it, and it sends nothing), then checks.
local function wait()
  local id = raidInstance()
  if not id or not IsInRaid() then return end
  token = token + 1
  local mine = token
  C_Timer.After(WAIT, function()
    if mine == token then check(id) end
  end)
end

-- ask-gone: from Choose a raid now on the notice that the selected raid has left the helper's list.
-- Lists only the raids still loaded, nothing picked.
function Q.AskGone()
  local gone = ns.Selection.Gone()
  local lead = gone and p.WHITE:format(p.goneName(gone)) .. " has left the helper's list. " or ""
  show("gone", { title = "Is this a guild run?",
    lead = lead .. "If this is still a guild run, pick its raid event. If not, choose the last option.",
    rows = rows(ns.Raids.Status()),
    buttons = { { label = "Start", needsPick = true, onClick = function() answer(false) end },
      { label = "Decide later", onClick = decideLater } } })
end

-- The selection changed (another officer's choice, leaving the group): a question asked about the
-- old one no longer applies and closes. UI.RefreshSync calls it after every change.
function Q.Recheck()
  if not shown then return end
  local held, status = shown.held, ns.Selection.Status()
  local outOfGroup = shown.kind ~= "gone" and not IsInRaid()
  if outOfGroup or held.activeBy ~= status.activeBy or held.activeRaid ~= status.activeRaid
    or held.at ~= status.at then
    hide()
  end
end

-- For the tests: the frame and what is on screen.
function Q.Shown() return shown end

local function build()
  p = ns.UI.parts
  frame = CreateFrame("Frame", "BureaucracyForeverQuestion", UIParent)
  Q.frame = frame
  frame:SetSize(WIDTH, 200)
  frame:SetFrameStrata("DIALOG")
  frame:EnableMouse(true)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
  local background = frame:CreateTexture(nil, "BACKGROUND")
  background:SetAllPoints()
  background:SetColorTexture(0, 0, 0, 0.92)
  frame.title = p.newText(frame, "GameFontNormal")
  for _, key in ipairs({ "lead", "hint" }) do
    frame[key] = p.newText(frame, key == "lead" and "GameFontHighlight" or "GameFontHighlightSmall")
    frame[key]:SetWidth(WIDTH - 40)
  end
  frame.note = p.newNote(frame)
  frame.note:SetWidth(WIDTH - 40)
  frame.note.text:SetWidth(WIDTH - 52)
  frame.rows, frame.buttons = {}, {}
  for i = 1, 3 do
    local b = p.newButton(frame, "", 90)
    b:SetScript("OnClick", function(self) self.onClick() end)
    frame.buttons[i] = b
  end
  -- Escape closes it, as Decide later does.
  frame:SetScript("OnHide", function() shown = nil end)
  frame:Hide()
  table.insert(UISpecialFrames, "BureaucracyForeverQuestion")
end

ns.On("ADDON_LOADED", function(name)
  if name == ns.name then build() end
end)

-- Whether the player was in a raid group at the last look.
local raidGroup = false

-- Entering the world: a loading screen, such as into or out of an instance. Never after /reload.
-- Entering another raid instance forgets a Keep given in the one before.
ns.On("PLAYER_ENTERING_WORLD", function(_, isReloadingUi)
  raidGroup = IsInRaid()
  if isReloadingUi then return end
  local id = raidInstance()
  if id and id ~= kept() then ns.db.questionKept = nil end
  wait()
end)

-- Joining a raid group (or the party becoming one) in a raid instance asks after the wait, and so
-- does the chooser who takes over when the one asked leaves the group. Leaving it closes the question.
ns.On("GROUP_ROSTER_UPDATE", function()
  local now = IsInRaid()
  if not now then
    if shown and shown.kind ~= "gone" then hide() end
    asker = nil
  elseif not raidGroup then
    wait()
  elseif asker and asker ~= me() then
    local left = true
    for _, name in ipairs(ns.Hub.Roster()) do
      if name == asker then left = false end
    end
    if left then
      asker = nil
      wait()
    end
  end
  raidGroup = now
end)
