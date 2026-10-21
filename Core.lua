-- Core: the add-on's namespace, its log, its event hub, the practice mode switch and the /bf command.
-- Every file listed in the .toc receives the add-on's name and the shared namespace table.
local ADDON_NAME, ns = ...

local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata

ns.name = ADDON_NAME
ns.version = getMetadata(ADDON_NAME, "Version")

function ns.Print(text)
  print("|cff33ff99Bureaucracy:|r " .. text)
end

-- The log: the last 50 things the add-on noted that need no chat line, kept for this session
-- only and printed by /bf log, oldest first.
local LOG_SIZE = 50
ns.log = {}

function ns.Log(text)
  table.insert(ns.log, { at = time(), text = text })
  if #ns.log > LOG_SIZE then table.remove(ns.log, 1) end
end

local function printLog()
  if #ns.log == 0 then
    ns.Print("nothing has been logged this session.")
    return
  end
  for _, entry in ipairs(ns.log) do
    ns.Print(date("%H:%M:%S", entry.at) .. " " .. entry.text)
  end
end

-- Modules call ns.On(event, handler) to hear a game event; handlers get the event's arguments.
local handlers = {}
local frame = CreateFrame("Frame")

function ns.On(event, handler)
  if not handlers[event] then
    handlers[event] = {}
    frame:RegisterEvent(event)
  end
  table.insert(handlers[event], handler)
end

frame:SetScript("OnEvent", function(_, event, ...)
  for _, handler in ipairs(handlers[event]) do
    handler(...)
  end
end)

ns.On("ADDON_LOADED", function(name)
  if name ~= ADDON_NAME then return end
  BureaucracyForeverDB = BureaucracyForeverDB or {}
  ns.db = BureaucracyForeverDB
end)

-- Practice mode (#17): hand-outs are real, but their awards are marked practice and never reach the
-- guild site. Saved, so a /reload keeps it; every login turns it off, so a practice mode left on
-- can't mark a real raid's awards.
local PRACTICE_ON = "Practice mode on: awards are marked [Practice] and nothing is sent to the guild site."

function ns.Practice()
  return ns.db ~= nil and ns.db.practice == true
end

-- Turns practice mode on or off and says so in chat. It applies to the next hand-out: awards
-- already made keep their mark.
function ns.SetPractice(on)
  ns.db.practice = on and true or nil
  ns.Print(on and PRACTICE_ON or "Practice mode off.")
  ns.UI.RefreshPractice()
end

ns.On("PLAYER_ENTERING_WORLD", function(isInitialLogin)
  if not isInitialLogin then return end
  ns.db.practice = nil
  ns.UI.RefreshPractice()
end)

SLASH_BUREAUCRACYFOREVER1 = "/bf"
SlashCmdList.BUREAUCRACYFOREVER = function(input)
  local command = strtrim(input or ""):lower()
  if command == "" then
    ns.UI.Toggle()
  elseif command == "version" then
    ns.Print("version " .. tostring(ns.version) .. ".")
  elseif command == "minimap" then
    ns.UI.ShowMinimapButton(not ns.UI.button:IsShown())
  elseif command == "log" then
    printLog()
  elseif command == "practice" then
    ns.SetPractice(not ns.Practice())
  else
    ns.Print("type /bf to open or close the window, /bf version for the version,"
      .. " /bf minimap to show or hide the minimap button, /bf log for the add-on's log,"
      .. " /bf practice to turn practice mode on or off.")
  end
end
