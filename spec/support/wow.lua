-- A stand-in for the WoW Forever client, so the add-on can be tested outside the game.
-- It fakes only the game calls the add-on uses, as simple recording fakes. Facts it copies
-- from the beta (robpaolella/bureaucracy-forever-addon#3): Lua 5.1, files run in .toc order
-- with (add-on name, namespace), and a chat line sent with no click or typed command behind
-- it (from a timer or an event) is blocked with ADDON_ACTION_BLOCKED.
-- Later tasks extend it as they need more of the game.
local wow = {}

local ADDON_DIR = "."
local TOC = "BureaucracyForever.toc"

-- The .toc's metadata ("## Key: value" lines) and its files, in order.
function wow.readToc()
  local metadata, files = {}, {}
  for line in io.lines(ADDON_DIR .. "/" .. TOC) do
    local key, value = line:match("^##%s*([^:]+):%s*(.-)%s*$")
    if key then
      metadata[key] = value
    elseif line:match("%S") and not line:match("^#") then
      files[#files + 1] = (line:gsub("%s+$", ""))
    end
  end
  return metadata, files
end

-- Frame templates the game has shown it has (the officer's error log, #55). Add one only once
-- the game confirms it.
wow.knownTemplates = { BasicFrameTemplateWithInset = true }

local frames, timers, now, hardwareEvent
local newFrame

local function protected(name, fn)
  return function(...)
    if not hardwareEvent then
      wow.blocked[#wow.blocked + 1] = name
      wow.fire("ADDON_ACTION_BLOCKED", wow.addonName, name)
      return
    end
    return fn(...)
  end
end

-- A frame, region or widget. It keeps what the add-on sets on it (shown, size, anchor, scripts,
-- text); the other calls it makes are quiet no-ops, because the stand-in draws nothing.
-- Fields the game's templates add (such as TitleText) are not faked: the add-on checks for them.
local frameMethods = {}
local frameMeta = { __index = frameMethods }
for _, name in ipairs({
  "SetFrameStrata", "SetMovable", "EnableMouse", "SetClampedToScreen", "RegisterForDrag",
  "RegisterForClicks", "SetTexture", "SetAllPoints", "SetFont", "SetTextColor", "SetJustifyH",
  "EnableMouseWheel",
}) do
  frameMethods[name] = function() end
end

function frameMethods.RegisterEvent(self, event) self.events[event] = true end
function frameMethods.UnregisterEvent(self, event) self.events[event] = nil end
function frameMethods.SetScript(self, name, fn) self.scripts[name] = fn end
function frameMethods.HookScript(self, name, fn)
  self.hooks = self.hooks or {}
  self.hooks[name] = self.hooks[name] or {}
  table.insert(self.hooks[name], fn)
end
-- A line of text is one line high; a scroll frame scrolls as far as its child is taller.
function frameMethods.GetStringHeight() return 12 end
function frameMethods.SetScrollChild(self, child) self.scrollChild = child end
function frameMethods.SetVerticalScroll(self, offset) self.verticalScroll = offset end
function frameMethods.GetVerticalScroll(self) return self.verticalScroll or 0 end
function frameMethods.GetVerticalScrollRange(self)
  return math.max(0, ((self.scrollChild or {}).height or 0) - (self.height or 0))
end
function frameMethods.GetScript(self, name) return self.scripts[name] end
function frameMethods.SetID(self, id) self.id = id end
function frameMethods.GetID(self) return self.id end
function frameMethods.SetText(self, text) self.text = text end
function frameMethods.GetText(self) return self.text end
function frameMethods.SetSize(self, w, h) self.width, self.height = w, h end
function frameMethods.SetWidth(self, w) self.width = w end
function frameMethods.SetHeight(self, h) self.height = h end
function frameMethods.GetWidth(self) return self.width or 0 end
function frameMethods.GetHeight(self) return self.height or 0 end
function frameMethods.GetEffectiveScale() return 1 end
function frameMethods.GetFrameLevel(self) return self.level or 1 end
function frameMethods.SetFrameLevel(self, level) self.level = level end
function frameMethods.ClearAllPoints(self) self.points = {} end
function frameMethods.SetPoint(self, point, relativeTo, relativePoint, x, y)
  if type(relativeTo) == "number" then
    relativeTo, relativePoint, x, y = nil, nil, relativeTo, relativePoint
  end
  if type(relativePoint) == "number" then x, y, relativePoint = relativePoint, x, nil end
  self.points[#self.points + 1] =
    { point = point, relativeTo = relativeTo, relativePoint = relativePoint, x = x or 0, y = y or 0 }
  -- A frame centred on the screen or a widget keeps a centre the tests can read and move.
  if point == "CENTER" and #self.points == 1 and relativeTo and relativeTo.GetCenter then
    local cx, cy = relativeTo:GetCenter()
    if cx then self.center = { cx + (x or 0), cy + (y or 0) } end
  end
end
function frameMethods.GetCenter(self)
  if self.center then return self.center[1], self.center[2] end
end
function frameMethods.Show(self)
  if self.shown then return end
  self.shown = true
  if self.scripts.OnShow then self.scripts.OnShow(self) end
end
function frameMethods.Hide(self)
  if not self.shown then return end
  self.shown = false
  if self.scripts.OnHide then self.scripts.OnHide(self) end
end
function frameMethods.IsShown(self) return self.shown end
-- Like the game, a font name it doesn't have is an error. The game has confirmed none yet.
local KNOWN_FONTS = {}
function frameMethods.CreateFontString(_, _, _, font)
  if font and not KNOWN_FONTS[font] then
    error("CreateFontString(): Couldn't find inherited node '" .. font .. "'", 2)
  end
  return newFrame()
end
function frameMethods.CreateTexture() return newFrame() end
function frameMethods.SetColorTexture(self, r, g, b, a) self.color = { r, g, b, a } end
function frameMethods.StartMoving(self) self.moving = true end
function frameMethods.StopMovingOrSizing(self) self.moving = false end

newFrame = function(kind, name, parent, template)
  local frame = setmetatable({
    events = {}, scripts = {}, points = {}, shown = true, kind = kind, name = name, parent = parent,
    template = template,
  }, frameMeta)
  if name then _G[name] = frame end
  frames[#frames + 1] = frame
  return frame
end

local function installGlobals(metadata)
  _G.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    wow.printed[#wow.printed + 1] = table.concat(parts, " ")
  end
  _G.strtrim = function(text) return (text:gsub("^%s+", ""):gsub("%s+$", "")) end
  _G.date = os.date
  _G.time = function() return wow.state.time end
  _G.GetTime = function() return now end
  _G.CreateFrame = function(kind, name, parent, template)
    -- Like the game, a template it doesn't have is an error that stops the add-on loading.
    if template and not wow.knownTemplates[template] then
      error("CreateFrame(): Couldn't find inherited node '" .. template .. "'", 2)
    end
    return newFrame(kind, name, parent, template)
  end
  -- The screen, the minimap and the tooltip: wow.state.screen sets the screen's size.
  _G.UIParent = newFrame("Frame", "UIParent")
  _G.UIParent.GetWidth = function() return wow.state.screen.width end
  _G.UIParent.GetHeight = function() return wow.state.screen.height end
  _G.UIParent.center = { wow.state.screen.width / 2, wow.state.screen.height / 2 }
  _G.Minimap = newFrame("Frame", "Minimap")
  _G.Minimap.width, _G.Minimap.center = 140, { 1300, 800 }
  _G.UISpecialFrames = {}
  _G.GetCursorPosition = function() return wow.state.cursor[1], wow.state.cursor[2] end
  -- The tooltip records the lines the add-on gave it, and whether it is showing.
  _G.GameTooltip = newFrame("GameTooltip", "GameTooltip")
  _G.GameTooltip.lines, _G.GameTooltip.shown = {}, false
  _G.GameTooltip.SetOwner = function(self, owner) self.owner, self.lines = owner, {} end
  -- The item link tooltip (a clicked link in chat) is a tooltip of the same kind.
  _G.ItemRefTooltip = newFrame("GameTooltip", "ItemRefTooltip")
  for _, tooltip in ipairs({ _G.GameTooltip, _G.ItemRefTooltip }) do
    tooltip.GetItem = function(self) return self.item and "Item", self.item end
  end
  _G.ItemRefTooltip.lines = {}
  _G.GameTooltip.AddLine = function(self, text) self.lines[#self.lines + 1] = text end
  _G.ItemRefTooltip.AddLine = _G.GameTooltip.AddLine
  _G.SlashCmdList = {}
  _G.C_AddOns = {
    GetAddOnMetadata = function(name, key)
      if name == wow.addonName then return metadata[key] end
    end,
  }

  _G.C_Timer = {
    After = function(seconds, callback)
      timers[#timers + 1] = { at = now + seconds, callback = callback }
    end,
  }

  -- Chat: lines the add-on sent, hidden add-on messages, the chat log switch.
  local function sendChat(text, channel, _, target)
    wow.sent[#wow.sent + 1] = { text = text, channel = channel, target = target }
  end
  _G.SendChatMessage = protected("SendChatMessage", sendChat)
  _G.C_ChatInfo = {
    SendChatMessage = protected("SendChatMessage", sendChat),
    SendAddonMessage = function(prefix, text, channel, target)
      wow.addonMessages[#wow.addonMessages + 1] =
        { prefix = prefix, text = text, channel = channel, target = target }
      return 0 -- Enum.SendAddonMessageResult.Success
    end,
    RegisterAddonMessagePrefix = function() return 0 end,
    InChatMessagingLockdown = function() return wow.state.chatLockdown end,
  }
  _G.LoggingChat = function(on)
    if on ~= nil then wow.state.chatLog = on end
    return wow.state.chatLog
  end

  -- The loot window, as set by wow.openLoot.
  local function slot(i) return wow.state.loot[i] or {} end
  _G.GetNumLootItems = function() return #wow.state.loot end
  _G.GetLootSlotInfo = function(i)
    local s = slot(i)
    return s.texture, s.name, s.quantity or 1, nil, s.quality, s.locked or false
  end
  _G.GetLootSlotLink = function(i) return slot(i).link end
  _G.GetLootSourceInfo = function(i)
    local s = slot(i)
    return s.sourceGuid, s.quantity or 1
  end
  _G.GetMasterLootCandidate = function(i, index)
    return (slot(i).candidates or {})[index]
  end
  _G.GiveMasterLoot = function(i, index)
    wow.gives[#wow.gives + 1] = { slot = i, candidate = index }
  end
  _G.UnitName = function(unit)
    if unit == nil or unit == "player" then return wow.state.player end
    return (wow.state.group or {})[tonumber(unit:match("^party(%d)$")) + 1]
  end
  -- The group: wow.state.group lists its names, the player first; groupIsRaid says if it is a raid.
  _G.IsInRaid = function() return wow.state.groupIsRaid or false end
  _G.GetNumGroupMembers = function() return #(wow.state.group or {}) end
  _G.GetRaidRosterInfo = function(i) return (wow.state.group or {})[i] end
  -- Item facts the game knows, as wow.state.items[id] = { name, link, icon }.
  _G.GetItemInfo = function(id)
    local item = wow.state.items[id]
    if not item then return nil end
    return item.name, item.link, 4, 0, 0, "", "", 1, "", item.icon
  end
  _G.GetLootThreshold = function() return wow.state.lootThreshold end

  -- Where the player is, as set by wow.state.instance: name, type ("none", "party", "raid")
  -- and id, the 8th value.
  _G.GetInstanceInfo = function()
    local i = wow.state.instance
    return i.name, i.type, 0, "", 40, 0, false, i.id
  end
end

-- Starts the game with the add-on installed: runs its files in .toc order, then fires
-- ADDON_LOADED. options.saved holds SavedVariables from an earlier session; options.screen
-- ({ width, height }) sets the screen's size; options.inbox is what the helper's Inbox.lua
-- defines (BureaucracyLootInbox), or the shipped placeholder when absent.
function wow.start(options)
  options = options or {}
  frames, timers, now, hardwareEvent = {}, {}, 0, false
  wow.printed, wow.sent, wow.addonMessages, wow.gives, wow.blocked = {}, {}, {}, {}, {}
  wow.state = { loot = {}, lootThreshold = 2, player = "Masterlooter", chatLog = false, chatLockdown = false,
    items = {}, screen = options.screen or { width = 1920, height = 1080 }, cursor = { 0, 0 },
    time = 1792000000, instance = { name = "Eastern Kingdoms", type = "none", id = 0 } }
  local metadata, files = wow.readToc()
  wow.addonName = TOC:gsub("%.toc$", "")
  installGlobals(metadata)
  -- Each start is a fresh session: only the saved data passed in survives from before.
  for name in (metadata.SavedVariables or ""):gmatch("[^,%s]+") do _G[name] = nil end
  for name, value in pairs(options.saved or {}) do _G[name] = value end
  _G.BureaucracyLootInbox = nil
  wow.ns = {}
  for _, file in ipairs(files) do
    if file == "Inbox.lua" and options.inbox ~= nil then
      _G.BureaucracyLootInbox = options.inbox
    else
      local chunk = assert(loadfile(ADDON_DIR .. "/" .. file:gsub("\\", "/")))
      chunk(wow.addonName, wow.ns)
    end
  end
  wow.fire("ADDON_LOADED", wow.addonName)
  return wow.ns
end

function wow.fire(event, ...)
  for _, frame in ipairs(frames) do
    if frame.events[event] and frame.scripts.OnEvent then
      frame.scripts.OnEvent(frame, event, ...)
    end
  end
end

-- A click or key press: the only time protected calls such as chat lines are allowed.
function wow.click(fn)
  hardwareEvent = true
  local ok, err = pcall(fn)
  hardwareEvent = false
  if not ok then error(err, 2) end
end

-- Types a slash command, such as "/bf practice".
function wow.slash(input)
  local command, rest = input:match("^(%S+)%s*(.-)$")
  for key, handler in pairs(_G.SlashCmdList) do
    for i = 1, 9 do
      local alias = _G["SLASH_" .. key .. i]
      if alias == nil then break end
      if alias:lower() == command:lower() then
        return wow.click(function() handler(rest) end)
      end
    end
  end
  error("no slash command " .. command)
end

-- Moves time forward, running the timers that fall due (never in a hardware event).
function wow.advance(seconds)
  now = now + seconds
  local i = 1
  while i <= #timers do
    if timers[i].at <= now then
      local timer = table.remove(timers, i)
      timer.callback()
    else
      i = i + 1
    end
  end
end

-- Opens a loot window. Each item: { link, name, quality, quantity, candidates = { "First Last" } }.
function wow.openLoot(items)
  wow.state.loot = items
  wow.fire("LOOT_OPENED", false)
end

function wow.closeLoot()
  wow.state.loot = {}
  wow.fire("LOOT_CLOSED")
end

return wow
