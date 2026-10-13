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

local frames, timers, now, hardwareEvent

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

local function newFrame()
  local frame = { events = {}, scripts = {} }
  function frame:RegisterEvent(event) self.events[event] = true end
  function frame:UnregisterEvent(event) self.events[event] = nil end
  function frame:SetScript(name, fn) self.scripts[name] = fn end
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
  _G.GetTime = function() return now end
  _G.CreateFrame = function() return newFrame() end
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
  _G.UnitName = function() return wow.state.player end
  _G.GetLootThreshold = function() return wow.state.lootThreshold end
end

-- Starts the game with the add-on installed: runs its files in .toc order, then fires
-- ADDON_LOADED. options.saved holds SavedVariables from an earlier session.
function wow.start(options)
  options = options or {}
  frames, timers, now, hardwareEvent = {}, {}, 0, false
  wow.printed, wow.sent, wow.addonMessages, wow.gives, wow.blocked = {}, {}, {}, {}, {}
  wow.state = { loot = {}, lootThreshold = 2, player = "Masterlooter", chatLog = false, chatLockdown = false }
  local metadata, files = wow.readToc()
  wow.addonName = TOC:gsub("%.toc$", "")
  installGlobals(metadata)
  -- Each start is a fresh session: only the saved data passed in survives from before.
  for name in (metadata.SavedVariables or ""):gmatch("[^,%s]+") do _G[name] = nil end
  for name, value in pairs(options.saved or {}) do _G[name] = value end
  wow.ns = {}
  for _, file in ipairs(files) do
    local chunk = assert(loadfile(ADDON_DIR .. "/" .. file:gsub("\\", "/")))
    chunk(wow.addonName, wow.ns)
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
