-- Core: the add-on's namespace, its event hub and the /bf command.
-- Every file listed in the .toc receives the add-on's name and the shared namespace table.
local ADDON_NAME, ns = ...

local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata

ns.name = ADDON_NAME
ns.version = getMetadata(ADDON_NAME, "Version")

function ns.Print(text)
  print("|cff33ff99Bureaucracy:|r " .. text)
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

SLASH_BUREAUCRACYFOREVER1 = "/bf"
SlashCmdList.BUREAUCRACYFOREVER = function(input)
  local command = strtrim(input or ""):lower()
  if command == "" then
    ns.UI.Toggle()
  elseif command == "version" then
    ns.Print("version " .. tostring(ns.version) .. ".")
  elseif command == "minimap" then
    ns.UI.ShowMinimapButton(not ns.UI.button:IsShown())
  else
    ns.Print("type /bf to open or close the window, /bf version for the version,"
      .. " /bf minimap to show or hide the minimap button.")
  end
end
