-- luacheck: ignore
-- BF Probe v5: a throwaway test add-on, posted on issue #3 and #33, not part of the add-on.
-- It is kept here only so its tests can run it. It is not in the .toc and not in the release zip.
-- BF Probe: a one-off test of what WoW Forever lets a loot add-on see and do.
-- It writes what it sees to BFProbeDB, which the game saves on logout or /reload.
-- It acts only when asked: a test line in chat, a hidden ping, a master loot hand-out, or the
-- timer test (which also switches the chat log off and straight back on), or the lines test
-- (party, raid and raid warning lines from a timer).
-- At each login or /reload it also reports what BFProbeInbox.lua says.
-- Delete the BFProbe folder when the tests are done.

local ADDON_NAME = ...
local PREFIX = "BFProbe"
local MAX_LOG = 500
-- The paste test text in issue #3 of bureaucracy-forever-addon.
local PASTE_EXPECTED = { length = 7445, lines = 164, checksum = 812064 }

local probe = CreateFrame("Frame")
local handlers = {}
local window
local lastGroupSize
local missingEvents = {}

local function isSecret(value)
  return issecretvalue ~= nil and issecretvalue(value) == true
end

-- A value as plain text for the log, or "<secret>" when the game hides it from add-ons.
local function show(value)
  if isSecret(value) then return "<secret>" end
  if value == nil then return "nil" end
  local ok, text = pcall(tostring, value)
  return ok and text or "<error>"
end

local function showArgs(...)
  local parts = {}
  for i = 1, select("#", ...) do
    parts[#parts + 1] = show((select(i, ...)))
  end
  return table.concat(parts, ", ")
end

local function say(text)
  print("|cff33ff99BF Probe:|r " .. text)
end

local function enumName(enumTable, value)
  if enumTable == nil or isSecret(value) then return show(value) end
  for name, v in pairs(enumTable) do
    if v == value then return name end
  end
  return show(value)
end

local function restrictions()
  if not (C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive
      and Enum and Enum.AddOnRestrictionType) then
    return "n/a"
  end
  local active = {}
  for name, value in pairs(Enum.AddOnRestrictionType) do
    local ok, on = pcall(C_RestrictedActions.IsAddOnRestrictionActive, value)
    if not ok then
      active[#active + 1] = name .. "?"
    elseif not isSecret(on) and on then
      active[#active + 1] = name
    end
  end
  table.sort(active)
  return #active > 0 and table.concat(active, "+") or "none"
end

local function chatLockdown()
  if not (C_ChatInfo and C_ChatInfo.InChatMessagingLockdown) then return "n/a" end
  local ok, on = pcall(C_ChatInfo.InChatMessagingLockdown)
  return ok and show(on) or "error"
end

-- Where the player is and which add-on limits are on, added to every log entry.
-- The game reports no limits at all while a limit is changing, so say so instead.
local function context(limitChanging)
  local inInstance, instanceType = IsInInstance()
  local zone = GetInstanceInfo()
  return ("%s; instance %s %s; combat %s; chat lockdown %s; limits %s"):format(
    show(zone), show(inInstance), show(instanceType), show(InCombatLockdown()),
    chatLockdown(), limitChanging and "(changing, see entry)" or restrictions())
end

local function log(event, detail, limitChanging)
  if not BFProbeDB then return end
  local entries = BFProbeDB.log
  entries[#entries + 1] = ("%s ; %s ; %s @ %s"):format(date("%Y-%m-%d %H:%M:%S"), event, detail,
    context(limitChanging))
  while #entries > MAX_LOG do table.remove(entries, 1) end
end

local function buildText()
  local version, build, _, interface = GetBuildInfo()
  return ("%s.%s, interface %s, project %s (Camelot %s)"):format(show(version), show(build),
    show(interface), show(WOW_PROJECT_ID), show(WOW_PROJECT_CAMELOT))
end

local function unitName(unit)
  local ok, name, realm = pcall(UnitName, unit)
  if not ok then return "error" end
  if isSecret(name) then return "<secret>" end
  if name == nil then return "nil" end
  if isSecret(realm) then return name .. " / <secret>" end
  if realm and realm ~= "" then return name .. " / " .. realm end
  return name
end

local function playerText()
  local ok, name, realm = pcall(UnitFullName, "player")
  return ("UnitName %s; UnitFullName %s / %s"):format(unitName("player"),
    ok and show(name) or "error", ok and show(realm) or "error")
end

local function roster()
  local count = GetNumGroupMembers()
  if isSecret(count) then return "<secret count>" end
  if count == 0 then return "not in a group" end
  local names = {}
  if IsInRaid() then
    for i = 1, count do
      local ok, name = pcall(GetRaidRosterInfo, i)
      names[#names + 1] = ok and show(name) or "error"
    end
  else
    names[#names + 1] = unitName("player")
    for i = 1, count - 1 do
      names[#names + 1] = unitName("party" .. i)
    end
  end
  return count .. " in group: " .. table.concat(names, ", ")
end

local function lootMethod()
  if not (C_PartyInfo and C_PartyInfo.GetLootMethod) then return "n/a" end
  local ok, method, partyIndex, raidIndex = pcall(C_PartyInfo.GetLootMethod)
  if not ok then return "error" end
  return ("%s (master looter party %s, raid %s)"):format(enumName(Enum and Enum.LootMethod, method),
    show(partyIndex), show(raidIndex))
end

local function availableLootMethods()
  if not (C_PartyInfo and C_PartyInfo.GetAvailableLootMethods) then return "n/a" end
  local ok, methods = pcall(C_PartyInfo.GetAvailableLootMethods)
  if not ok or type(methods) ~= "table" then return "error" end
  local names = {}
  for _, method in ipairs(methods) do
    names[#names + 1] = enumName(Enum and Enum.LootMethod, method)
  end
  return table.concat(names, ", ")
end

local QUALITY_NAMES = { [0] = "Poor", [1] = "Common", [2] = "Uncommon", [3] = "Rare", [4] = "Epic" }

local function lootThreshold()
  local ok, threshold = pcall(GetLootThreshold)
  if not ok then return "error" end
  if isSecret(threshold) then return "<secret>" end
  return ("%s (%s)"):format(show(threshold), QUALITY_NAMES[threshold] or "?")
end

local function legacyLoot()
  if not (C_Loot and C_Loot.IsLegacyLootModeEnabled) then return "n/a" end
  local ok, on = pcall(C_Loot.IsLegacyLootModeEnabled)
  return ok and show(on) or "error"
end

local function masterLootCandidates(slot)
  local names = {}
  for i = 1, 40 do
    local ok, name = pcall(GetMasterLootCandidate, slot, i)
    if ok and isSecret(name) then
      names[#names + 1] = i .. "=<secret>"
    elseif ok and name then
      names[#names + 1] = i .. "=" .. name
    end
  end
  return names
end

local function describeLoot()
  local count = GetNumLootItems()
  if isSecret(count) then return "<secret>", { "the item count is hidden" } end
  local lines = {}
  for slot = 1, count do
    local _, _, name, quantity, _, quality, locked = pcall(GetLootSlotInfo, slot)
    local okLink, link = pcall(GetLootSlotLink, slot)
    local label
    if not okLink then
      label = "error"
    elseif isSecret(link) then
      label = "<secret link>"
    elseif link then
      label = link
    else
      label = show(name)
    end
    local candidates = masterLootCandidates(slot)
    lines[#lines + 1] = ("slot %d: %s x%s, quality %s, locked %s%s"):format(slot, label,
      show(quantity), show(quality), show(locked),
      #candidates > 0 and ("; master loot to " .. table.concat(candidates, ", ")) or "")
  end
  return count, lines
end

-- Commands ------------------------------------------------------------------

local function check()
  local lines = {
    "client " .. buildText(),
    "you: " .. playerText(),
    "group: " .. roster(),
    "loot method " .. lootMethod() .. "; available: " .. availableLootMethods(),
    "loot threshold " .. lootThreshold(),
    "legacy loot mode " .. legacyLoot(),
    "where: " .. context(),
  }
  for _, line in ipairs(lines) do say(line) end
  log("CHECK", table.concat(lines, " / "))
end

local function postTestLine()
  local channel = IsInRaid() and "RAID" or IsInGroup() and "PARTY" or "SAY"
  local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
  local ok, err = pcall(send, "BF Probe test line, please ignore", channel)
  log("POST_TEST_LINE", ("channel %s; call ok %s %s"):format(channel, show(ok), show(err)))
  say(("asked the game to post a test line in %s (call ok: %s). Did it appear in chat?"):format(
    channel:lower(), show(ok)))
end

local function checkPaste()
  local text = window.box:GetText()
  text = text:gsub("\r", "")
  text = text:gsub("%s+$", "")
  local checksum, lines = 0, 1
  for i = 1, #text do
    local byte = text:byte(i)
    checksum = (checksum * 31 + byte) % 1000003
    if byte == 10 then lines = lines + 1 end
  end
  local match = #text == PASTE_EXPECTED.length and lines == PASTE_EXPECTED.lines
    and checksum == PASTE_EXPECTED.checksum
  BFProbeDB.paste = { length = #text, lines = lines, checksum = checksum, match = match,
    first = text:sub(1, 40), last = text:sub(-40) }
  log("PASTE_CHECK", ("%d characters, %d lines, checksum %d, match %s"):format(
    #text, lines, checksum, show(match)))
  if match then
    say("paste test PASSED: all 164 lines arrived exactly.")
  else
    say(("paste test DIFFERENT: got %d characters, %d lines, checksum %d; expected %d, %d, %d."):format(
      #text, lines, checksum, PASTE_EXPECTED.length, PASTE_EXPECTED.lines, PASTE_EXPECTED.checksum))
  end
end

local function button(parent, text, width, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, 24)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

local function buildWindow()
  local frame = CreateFrame("Frame", "BFProbeWindow", UIParent)
  frame:SetSize(560, 380)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  tinsert(UISpecialFrames, "BFProbeWindow")

  local background = frame:CreateTexture(nil, "BACKGROUND")
  background:SetAllPoints()
  background:SetColorTexture(0, 0, 0, 0.85)

  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  frame.title:SetPoint("TOPLEFT", 12, -10)
  frame.title:SetPoint("TOPRIGHT", -12, -10)
  frame.title:SetJustifyH("LEFT")

  -- A scrolling box when the client has the standard template, a clipped one if not.
  local ok, scroll = pcall(CreateFrame, "ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  if not ok then
    scroll = CreateFrame("ScrollFrame", nil, frame)
  end
  scroll:SetPoint("TOPLEFT", 12, -34)
  scroll:SetPoint("BOTTOMRIGHT", -34, 44)

  local box = CreateFrame("EditBox", nil, scroll)
  box:SetMultiLine(true)
  box:SetMaxLetters(0)
  box:SetAutoFocus(false)
  box:EnableMouse(true)
  box:SetFontObject(ChatFontNormal)
  box:SetSize(510, 300)
  box:SetScript("OnEscapePressed", box.ClearFocus)
  scroll:SetScrollChild(box)
  scroll:EnableMouse(true)
  scroll:SetScript("OnMouseDown", function() box:SetFocus() end)
  frame.box = box

  local close = button(frame, "Close", 80, function() frame:Hide() end)
  close:SetPoint("BOTTOMRIGHT", -12, 12)
  local post = button(frame, "Post test line in chat", 180, postTestLine)
  post:SetPoint("RIGHT", close, "LEFT", -8, 0)
  local verify = button(frame, "Check pasted text", 150, checkPaste)
  verify:SetPoint("RIGHT", post, "LEFT", -8, 0)
  return frame
end

local function openWindow(title, text)
  window = window or buildWindow()
  window.title:SetText(title)
  window.box:SetText(text)
  window:Show()
  window.box:SetFocus()
  if text ~= "" then window.box:HighlightText() end
end

local function exportText()
  local out = { "BF Probe export " .. date("%Y-%m-%d %H:%M:%S"), "client " .. buildText(),
    "loads " .. BFProbeDB.loads }
  local entries = BFProbeDB.log
  for i = math.max(1, #entries - 199), #entries do
    -- Item links carry | codes, which the box would draw instead of copying.
    out[#out + 1] = (entries[i]:gsub("|", "!"))
  end
  return table.concat(out, "\n")
end

local function ping()
  local channel = IsInRaid() and "RAID" or IsInGroup() and "PARTY" or nil
  if not channel then
    say("join a group first: the ping goes to BF Probe on your group members' screens.")
    return
  end
  local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, "ping " .. date("%H:%M:%S"), channel)
  local resultName = ok and enumName(Enum and Enum.SendAddonMessageResult, result) or show(result)
  log("PING", ("channel %s; call ok %s; result %s"):format(channel, show(ok), resultName))
  say(("sent a hidden ping to your %s: %s."):format(channel:lower(), resultName))
end

-- Give the first master loot item to yourself, or with toOther to the first person on the
-- list who isn't you.
local function give(toOther)
  local count = GetNumLootItems()
  if isSecret(count) or count == 0 then
    say("open a loot window first, as master looter, with an item at or above the loot threshold.")
    return
  end
  -- Every exact form your name could take in the master loot list: "First", "First Last"
  -- or "First-Last". Only an exact match counts, so the item can't go to someone else.
  local myNames = {}
  for _, fetch in ipairs({ UnitName, UnitFullName }) do
    local ok, name, second = pcall(fetch, "player")
    if ok and name and not isSecret(name) then
      myNames[name] = true
      if second and not isSecret(second) and second ~= "" then
        myNames[name .. " " .. second] = true
        myNames[name .. "-" .. second] = true
      end
    end
  end
  if next(myNames) == nil then
    say("your own name is hidden from add-ons right now.")
    return
  end
  local seen = {}
  for slot = 1, count do
    for i = 1, 40 do
      local ok, candidate = pcall(GetMasterLootCandidate, slot, i)
      if ok and isSecret(candidate) then
        seen[#seen + 1] = "<secret>"
      elseif ok and candidate then
        seen[#seen + 1] = candidate
        if (myNames[candidate] == true) ~= (toOther == true) then
          local okLink, link = pcall(GetLootSlotLink, slot)
          local gave, err = pcall(GiveMasterLoot, slot, i)
          log("GIVE", ("slot %d (%s) to candidate %d (%s)%s: call ok %s %s"):format(slot,
            okLink and show(link) or "error", i, candidate, toOther and ", not you" or "",
            show(gave), show(err)))
          say(("asked the game to give slot %d to %s (call ok: %s). Did it land in %s bags?"):format(
            slot, toOther and candidate or "you", show(gave), toOther and "their" or "your"))
          return
        end
      end
    end
  end
  log("GIVE", ("no %s; candidates seen: %s"):format(toOther and "one else on the list" or "exact match",
    table.concat(seen, ", ")))
  say(("found no master loot item in this window that %s can receive. Candidates seen: %s"):format(
    toOther and "anyone but you" or "you", #seen > 0 and table.concat(seen, ", ") or "none"))
end

local TIMER_LINE = "BF Probe timer line, please ignore"

local function chatLogging()
  local ok, on = pcall(LoggingChat)
  return ok and show(on) or "error"
end

-- What the add-on can still do with no click behind it: a hidden message, a chat line and
-- the chat log switch, each from a timer.
local function timerBody()
  local channel = IsInRaid() and "RAID" or IsInGroup() and "PARTY" or nil
  local sends = {}
  if channel then
    sends[1] = { channel }
  else
    -- Alone, whisper yourself, in each form your name could take.
    local first, last = UnitFullName("player")
    if first and not isSecret(first) then
      sends[#sends + 1] = { "WHISPER", first }
      if last and not isSecret(last) and last ~= "" then
        sends[#sends + 1] = { "WHISPER", first .. " " .. last }
        sends[#sends + 1] = { "WHISPER", first .. "-" .. last }
      end
    end
  end
  for _, s in ipairs(sends) do
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, "timer " .. date("%H:%M:%S"), s[1], s[2])
    log("TIMER_PING", ("channel %s%s; call ok %s; result %s"):format(s[1], s[2] and (" to " .. s[2]) or "",
      show(ok), ok and enumName(Enum and Enum.SendAddonMessageResult, result) or show(result)))
  end
  local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
  local okLine, errLine = pcall(send, TIMER_LINE, "SAY")
  log("TIMER_LINE", ("channel SAY; call ok %s %s"):format(show(okLine), show(errLine)))
  local before = chatLogging()
  local okOff = pcall(LoggingChat, false)
  local afterOff = chatLogging()
  local okOn = pcall(LoggingChat, true)
  local afterOn = chatLogging()
  log("TIMER_CHATLOG", ("chat log on: before %s; after switching off %s (call ok %s); after switching on %s (call ok %s)"):format(
    before, afterOff, show(okOff), afterOn, show(okOn)))
  say(("timer test done. Chat log on: before %s, after off %s, after on %s. Did a /say line appear, "
    .. "and a 'got a hidden ping' line?"):format(before, afterOff, afterOn))
end

local function timerTest()
  say("timer test: in 3 seconds, with no click behind it, BF Probe sends a hidden message, "
    .. "posts a /say line and switches the chat log off and on again.")
  C_Timer.After(3, function()
    local ok, err = pcall(timerBody)
    if not ok then
      log("ERROR", "timer test: " .. show(err))
      say("the timer test hit an error: " .. show(err))
    end
  end)
end

-- Chat lines to the group, each sent from a timer with no click behind it: a party line in a
-- party; a raid line and a raid warning in a raid.
local lineAttempt

local function hasWarningRights()
  local ok, allowed = pcall(function()
    return UnitIsGroupLeader("player") == true or UnitIsGroupAssistant("player") == true
  end)
  return ok and allowed
end

-- What to send now, and what to tell the player about what won't be sent.
local function linesPlan()
  local plan, notes = {}, {}
  if IsInRaid() then
    plan[1] = { label = "raid line", text = "BF Probe raid line from a timer, please ignore", channel = "RAID" }
    if hasWarningRights() then
      plan[2] = { label = "raid warning", text = "BF Probe raid warning from a timer, please ignore",
        channel = "RAID_WARNING" }
    else
      notes[#notes + 1] = "you aren't the raid leader or an assistant, so no raid warning is tried."
    end
  elseif IsInGroup() then
    plan[1] = { label = "party line", text = "BF Probe party line from a timer, please ignore", channel = "PARTY" }
  else
    notes[#notes + 1] = "you aren't in a party or raid, so nothing would be sent. Form a party first."
  end
  return plan, notes
end

local function sendLine(item)
  lineAttempt = item
  local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
  local ok, err = pcall(send, item.text, item.channel)
  lineAttempt = nil
  local result = "sent (the game took it, no block reported)"
  if not ok then
    result = "error: " .. show(err)
  elseif item.blocked then
    result = "blocked (ADDON_ACTION_BLOCKED)"
  end
  log("LINES_" .. item.channel, ("%s; call ok %s; %s"):format(item.label, show(ok), result))
  say(("%s: %s. Did it appear in chat?"):format(item.label, result))
end

local function linesBody()
  local plan, notes = linesPlan()
  for _, note in ipairs(notes) do
    log("LINES", note)
    say(note)
  end
  for _, item in ipairs(plan) do sendLine(item) end
end

local function linesTest()
  local plan, notes = linesPlan()
  for _, note in ipairs(notes) do say(note) end
  if #plan == 0 then
    log("LINES", "nothing to send: " .. notes[1])
    return
  end
  local names = {}
  for _, item in ipairs(plan) do names[#names + 1] = item.label end
  say(("lines test: in 3 seconds, with no click behind it, BF Probe sends: %s."):format(
    table.concat(names, " and ")))
  C_Timer.After(3, function()
    local ok, err = pcall(linesBody)
    if not ok then
      log("ERROR", "lines test: " .. show(err))
      say("the lines test hit an error: " .. show(err))
    end
  end)
end

local function help()
  say(("loaded %d time(s), %d entries logged. Commands:"):format(BFProbeDB.loads, #BFProbeDB.log))
  say("/bfprobe check - what the add-on can see right now")
  say("/bfprobe paste - the paste-in test")
  say("/bfprobe copy - the copy-out test")
  say("/bfprobe ping - send a hidden add-on message to your group")
  say("/bfprobe give - as master looter, give the first item you can receive to yourself")
  say("/bfprobe give other - as master looter, give the first item to the first person on the list who isn't you")
  say("/bfprobe timers - what the add-on can do with no click behind it")
  say("/bfprobe lines - in 3 seconds, send party, raid and raid warning lines from a timer")
end

local function runCommand(command)
  if command == "check" then
    check()
  elseif command == "paste" then
    openWindow("Paste test: click in the box, paste (Ctrl+V or Cmd+V), then click Check pasted text.", "")
  elseif command == "copy" then
    openWindow("Copy test: the text is selected. Copy it (Ctrl+C or Cmd+C) and paste it into Pi.",
      exportText())
  elseif command == "ping" then
    ping()
  elseif command == "give" then
    give(false)
  elseif command == "give other" then
    give(true)
  elseif command == "timers" then
    timerTest()
  elseif command == "lines" then
    linesTest()
  else
    help()
  end
end

SLASH_BFPROBE1 = "/bfprobe"
SlashCmdList.BFPROBE = function(input)
  local command = strtrim(input or ""):lower()
  local ok, err = pcall(runCommand, command)
  if not ok then
    log("ERROR", "/bfprobe " .. command .. ": " .. show(err))
    say("that command hit an error: " .. show(err))
  end
end

-- Events --------------------------------------------------------------------

function handlers.ADDON_LOADED(name)
  if name ~= ADDON_NAME then return end
  BFProbeDB = BFProbeDB or {}
  BFProbeDB.log = BFProbeDB.log or {}
  BFProbeDB.loads = (BFProbeDB.loads or 0) + 1
  BFProbeDB.client = buildText()
  local ok, result = pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
  log("LOADED", ("load %d; client %s; message prefix %s"):format(BFProbeDB.loads, BFProbeDB.client,
    ok and enumName(Enum and Enum.RegisterAddonMessagePrefixResult, result) or show(result)))
  if #missingEvents > 0 then
    log("MISSING_EVENTS", table.concat(missingEvents, ", "))
  end
  say(("loaded, load number %d. Client %s. Type /bfprobe for the commands."):format(
    BFProbeDB.loads, BFProbeDB.client))
  -- BFProbeInbox.lua stands in for the file the desktop helper will write. The test changes
  -- it outside the game, then checks that /reload reads the new text.
  local inbox = BFProbeInbox
  log("INBOX", "inbox file says " .. show(inbox))
  if inbox == nil then
    say("the inbox file didn't load. Is BFProbeInbox.lua in the BFProbe folder? Restart the game after adding it.")
  else
    say("inbox file says: " .. show(inbox))
  end
end

function handlers.LOOT_OPENED(autoLoot)
  local count, lines = describeLoot()
  log("LOOT_OPENED", ("%s item(s), auto loot %s, method %s: %s"):format(show(count), show(autoLoot),
    lootMethod(), table.concat(lines, " / ")))
  say(("loot window: %s item(s), loot method %s."):format(show(count), lootMethod()))
  for _, line in ipairs(lines) do say(line) end
end

function handlers.CHAT_MSG_LOOT(text, playerName, _, _, playerName2)
  log("CHAT_MSG_LOOT", ("text %s; player %s; player2 %s"):format(show(text), show(playerName),
    show(playerName2)))
end

function handlers.CHAT_MSG_SYSTEM(text)
  if isSecret(text) then
    log("CHAT_MSG_SYSTEM", "<secret>")
    say("a system message (a /roll?) arrived hidden from add-ons.")
  elseif type(text) == "string" and text:find("%(%d+%-%d+%)") then
    log("CHAT_MSG_SYSTEM roll", text)
    say("read a roll: " .. text)
  end
end

function handlers.PLAYER_ENTERING_WORLD(isLogin, isReload)
  log("PLAYER_ENTERING_WORLD", showArgs(isLogin, isReload) .. "; chat log on " .. chatLogging())
end

function handlers.CHAT_MSG_SAY(text, sender)
  if isSecret(text) or type(text) ~= "string" or not text:find("BF Probe", 1, true) then return end
  log("CHAT_MSG_SAY", ("from %s: %s"):format(show(sender), text))
end

function handlers.CHAT_MSG_ADDON(prefix, text, channel, sender)
  if isSecret(prefix) then
    log("CHAT_MSG_ADDON", "<secret prefix>")
  elseif prefix == PREFIX then
    log("CHAT_MSG_ADDON", ("from %s in %s: %s"):format(show(sender), show(channel), show(text)))
    say(("got a hidden ping from %s: %s"):format(show(sender), show(text)))
  end
end

function handlers.ENCOUNTER_END(encounterID, encounterName, difficultyID, groupSize, success)
  log("ENCOUNTER_END", showArgs(encounterID, encounterName, difficultyID, groupSize, success))
  say(("boss fight ended: %s (id %s), success %s."):format(show(encounterName), show(encounterID),
    show(success)))
end

function handlers.START_LOOT_ROLL(rollID, rollTime, lootHandle)
  local ok, link = pcall(GetLootRollItemLink, rollID)
  log("START_LOOT_ROLL", ("roll %s, time %s, handle %s, item %s"):format(show(rollID), show(rollTime),
    show(lootHandle), ok and show(link) or "error"))
end

function handlers.GROUP_ROSTER_UPDATE()
  local size = GetNumGroupMembers()
  if isSecret(size) or size == lastGroupSize then return end
  lastGroupSize = size
  log("GROUP_ROSTER_UPDATE", roster() .. "; loot method " .. lootMethod())
end

function handlers.PARTY_LOOT_METHOD_CHANGED()
  log("PARTY_LOOT_METHOD_CHANGED", lootMethod() .. "; threshold " .. lootThreshold()
    .. "; available: " .. availableLootMethods())
end

function handlers.ADDON_ACTION_BLOCKED(addonName, functionName)
  if lineAttempt then lineAttempt.blocked = true end
  log("ADDON_ACTION_BLOCKED", showArgs(addonName, functionName))
  say(("the game blocked %s from calling %s."):format(show(addonName), show(functionName)))
end
handlers.ADDON_ACTION_FORBIDDEN = handlers.ADDON_ACTION_BLOCKED

function handlers.ADDON_RESTRICTION_STATE_CHANGED(restrictionType, state)
  local typeName = enumName(Enum and Enum.AddOnRestrictionType, restrictionType)
  local stateName = enumName(Enum and Enum.AddOnRestrictionState, state)
  log("ADDON_RESTRICTION_STATE_CHANGED", typeName .. " " .. stateName, true)
  if typeName ~= "Combat" then
    say(("add-on limit %s is now %s."):format(typeName, stateName))
  end
end

local EVENTS = {
  "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
  "LOOT_OPENED", "LOOT_CLOSED", "LOOT_SLOT_CLEARED", "OPEN_MASTER_LOOT_LIST",
  "CHAT_MSG_LOOT", "CHAT_MSG_SYSTEM", "CHAT_MSG_ADDON", "CHAT_MSG_SAY",
  "ENCOUNTER_START", "ENCOUNTER_END", "ENCOUNTER_LOOT_RECEIVED",
  "START_LOOT_ROLL", "LOOT_ITEM_ROLL_WON", "GROUP_ROSTER_UPDATE", "PARTY_LOOT_METHOD_CHANGED",
  "LEGACY_LOOT_RULES_CHANGED", "ADDON_RESTRICTION_STATE_CHANGED",
  "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN",
}

for _, event in ipairs(EVENTS) do
  if not pcall(probe.RegisterEvent, probe, event) then missingEvents[#missingEvents + 1] = event end
end

local reportedError = false
probe:SetScript("OnEvent", function(_, event, ...)
  local handler = handlers[event]
  local ok, err
  if handler then
    ok, err = pcall(handler, ...)
  else
    ok, err = pcall(log, event, showArgs(...))
  end
  if not ok then
    pcall(log, "ERROR", event .. ": " .. show(err))
    if not reportedError then
      reportedError = true
      say("hit an error (logged). The tests still count; carry on.")
    end
  end
end)
