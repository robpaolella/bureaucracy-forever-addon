-- Notice: the shared notice window (design/9-loot-ui, the notice-* states). Notice.Raise(key, view)
-- draws one: an icon, a lead, a hint, a download link in a copyable box and buttons, each part
-- optional. A notice raised during a boss fight waits and shows when the fight ends, so it never
-- covers the loot pop-up. The update notice (#109) is raised when a loaded snapshot's `addon`
-- record names a newer version; the handover notice (#110) uses the same window.
local _, ns = ...

local Notice = {}
ns.Notice = Notice

local WIDTH = 460
local ALERT = "Interface\\DialogFrame\\DialogAlertIcon"
local GREEN = "|cff40ff40%s|r"

local p, frame            -- UI's drawing parts, and the notice's frame
local shown               -- the notice on screen: { key, view }
local pending             -- a notice waiting for the fight to end
local fighting = false
local newest              -- the newest version already raised this session

local function hide()
  shown = nil
  frame:Hide()
end

local function draw()
  local view = shown.view
  for _, b in ipairs(frame.buttons) do b:Hide() end
  local y = 18
  frame.icon:Hide()
  local x = 20
  if view.icon then
    frame.icon:Show()
    frame.icon:ClearAllPoints()
    frame.icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -y)
    x = 66
  end
  frame.lead:SetWidth(WIDTH - x - 20)
  frame.lead:SetText(view.lead)
  frame.lead:ClearAllPoints()
  frame.lead:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -y)
  y = y + math.max(frame.lead:GetStringHeight(), view.icon and 36 or 0) + 10
  frame.hint:Hide()
  if view.hint then
    frame.hint:Show()
    frame.hint:SetText(view.hint)
    frame.hint:ClearAllPoints()
    frame.hint:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -y)
    y = y + frame.hint:GetStringHeight() + 10
  end
  frame.link:Hide()
  if view.link then
    frame.link:Show()
    frame.link.url = view.link
    frame.link:SetText(view.link)
    frame.link:ClearAllPoints()
    frame.link:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -y)
    y = y + 30
  end
  local buttons = view.buttons or { { label = "Close" } }
  local width = 0
  for i, b in ipairs(buttons) do
    local button = frame.buttons[i]
    button.label:SetText(b.label)
    button:SetWidth(math.max(90, button.label:GetStringWidth() + 24))
    button.onClick = b.onClick
    width = width + button:GetWidth() + (i > 1 and 10 or 0)
  end
  local left = (WIDTH - width) / 2
  for i in ipairs(buttons) do
    local button = frame.buttons[i]
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", frame, "TOPLEFT", left, -y)
    button:Show()
    left = left + button:GetWidth() + 10
  end
  frame:SetHeight(y + 24 + 20)
  frame:Show()
  if view.link then
    frame.link:SetFocus()
    frame.link:HighlightText()
  end
end

-- Shows a notice, or holds it until the boss fight ends. A held one is replaced by a later one
-- with the same key. view: { icon, lead, hint, link, buttons = { { label, onClick } } }; with no
-- buttons there is a Close. Clicking any button closes the notice, then runs its onClick.
function Notice.Raise(key, view)
  if fighting then
    pending = { key = key, view = view }
    return
  end
  shown = { key = key, view = view }
  draw()
end

-- For the tests: the notice on screen, or the one waiting for the fight to end.
function Notice.Shown() return shown end
function Notice.Pending() return pending end

-- The update notice for a loaded snapshot's addon record: only for a newer version than this
-- add-on and than any already raised this session, so it shows once per version.
function Notice.CheckUpdate(addon)
  if type(addon) ~= "table" or not ns.Snapshot.IsNewer(addon.version, ns.version) then return end
  if newest and not ns.Snapshot.IsNewer(addon.version, newest) then return end
  newest = addon.version
  local version = addon.version:gsub("|", "||")
  Notice.Raise("update", {
    icon = ALERT,
    lead = "A newer " .. p.WHITE:format("Bureaucracy Forever") .. " is out: " .. GREEN:format(version)
      .. " (you have " .. (tostring(ns.version):gsub("|", "||")) .. ").",
    hint = "Copy the link (Ctrl+C), download it, replace the add-on folder, then /reload. "
      .. "The desktop helper updates it for you.",
    link = type(addon.url) == "string" and addon.url or nil,
  })
end

-- The handover notice (#110): the loot master this add-on last saw, kept when master loot goes
-- off and forgotten on leaving the group, and the notice when the game hands the role to the player.
local lastMaster -- bare name

local function currentMaster()
  local name = ns.UI.parts.lootMaster()
  return name and ns.Rules.Bare(name) or nil
end

local function plain(text) return (tostring(text):gsub("|", "||")) end

function Notice.Handover(previous)
  local count = #ns.Raids.Awards(ns.Selection.Status().activeRaid)
  Notice.Raise("handover", {
    lead = p.WHITE:format("You're now the loot master."),
    hint = plain(previous) .. "'s " .. count .. (count == 1 and " award is" or " awards are")
      .. " loaded as history. Your add-on now hands out and records awards, and other "
      .. "officers' add-ons follow you.",
    buttons = {
      { label = "Open awards", onClick = function()
        ns.UI.window:Show()
        ns.UI.Select("Awards")
      end },
      { label = "OK" },
    },
  })
end

local function build()
  p = ns.UI.parts
  frame = CreateFrame("Frame", "BureaucracyForeverNotice", UIParent)
  Notice.frame = frame
  frame:SetSize(WIDTH, 160)
  frame:SetFrameStrata("DIALOG")
  frame:EnableMouse(true)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
  local background = frame:CreateTexture(nil, "BACKGROUND")
  background:SetAllPoints()
  background:SetColorTexture(0, 0, 0, 0.92)
  -- The approved design's metallic frame, as a thin grey edge (textures only: no backdrop API).
  for _, edge in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 2 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 2 },
    { "TOPLEFT", "BOTTOMLEFT", 2 }, { "TOPRIGHT", "BOTTOMRIGHT", 2 } }) do
    local line = frame:CreateTexture(nil, "BORDER")
    line:SetColorTexture(0.6, 0.6, 0.6, 1)
    line:SetPoint(edge[1], frame, edge[1], 0, 0)
    line:SetPoint(edge[2], frame, edge[2], 0, 0)
    if edge[3] then line:SetWidth(edge[3]) else line:SetHeight(edge[4]) end
  end
  frame.icon = frame:CreateTexture(nil, "ARTWORK")
  frame.icon:SetTexture(ALERT)
  frame.icon:SetSize(36, 36)
  frame.lead = p.newText(frame, "GameFontHighlight")
  frame.lead:SetJustifyH("LEFT")
  frame.hint = p.newText(frame, "GameFontHighlightSmall")
  frame.hint:SetWidth(WIDTH - 40)
  frame.hint:SetJustifyH("LEFT")
  -- The download link, in a box so it can be copied; typing in it puts the link back.
  frame.link = CreateFrame("EditBox", nil, frame)
  frame.link:SetAutoFocus(false)
  frame.link:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
  frame.link:SetSize(WIDTH - 40, 20)
  frame.link:SetScript("OnTextChanged", function(self, typed)
    if typed then
      self:SetText(self.url)
      self:HighlightText()
    end
  end)
  frame.link:SetScript("OnEscapePressed", frame.link.ClearFocus)
  frame.buttons = {}
  for i = 1, 2 do
    local b = p.newButton(frame, "", 90)
    b:SetScript("OnClick", function(self)
      local onClick = self.onClick
      hide()
      if onClick then onClick() end
    end)
    frame.buttons[i] = b
  end
  -- Escape closes it, as Close does.
  frame:SetScript("OnHide", function() shown = nil end)
  frame:Hide()
  table.insert(UISpecialFrames, "BureaucracyForeverNotice")
end

ns.On("ADDON_LOADED", function(name)
  if name == ns.name then build() end
end)

ns.On("ENCOUNTER_START", function() fighting = true end)
ns.On("ENCOUNTER_END", function()
  fighting = false
  local waiting = pending
  pending = nil
  if waiting then Notice.Raise(waiting.key, waiting.view) end
end)

-- A snapshot that loads (pasted, or from the inbox) is checked for a newer add-on.
local previous = ns.Raids.afterLoad
ns.Raids.afterLoad = function(raidId)
  if previous then previous(raidId) end
  local snapshot = ns.Raids.Get(raidId)
  if snapshot then Notice.CheckUpdate(snapshot.addon) end
end

ns.On("PLAYER_ENTERING_WORLD", function()
  if lastMaster == nil then lastMaster = currentMaster() end
end)

ns.On("GROUP_ROSTER_UPDATE", function()
  if GetNumGroupMembers() == 0 then
    lastMaster = nil
  elseif lastMaster == nil then
    lastMaster = currentMaster()
  end
end)

ns.On("PARTY_LOOT_METHOD_CHANGED", function()
  local now = currentMaster()
  if not now then return end
  local before = lastMaster
  lastMaster = now
  if before and before ~= now and now == ns.Rules.Bare(UnitName("player")) then
    Notice.Handover(before)
  end
end)
