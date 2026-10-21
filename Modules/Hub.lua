-- Hub: officers' hidden sync messages in and out (ADDON-SPEC.md 10, 10.2 to 10.4; #71, #25).
-- Checks each message's prefix and sender, hands its body to the handler for its type, and
-- rebuilds O messages from their chunks before applying the operation through Records. Sends
-- this add-on's own operations, and Q requests and resends, through one paced queue. Keeps who in
-- the group runs the add-on (P), shares the group's raid selection (S) and names the chooser (#62).
-- Trades what each add-on holds (H) and asks for what differs (C), for catch-up (#20), and answers
-- a C with the operations its sender lacks, applying such replies with the forwarder kept (#114).
local _, ns = ...

local Hub = {}
ns.Hub = Hub

local bare = ns.Rules.Bare
local Sync = ns.Sync

-- The game delivers only registered prefixes: the newer ones are registered so the add-on can
-- tell the officer it needs updating (conductor's call, #71, 2026-10-15).
local NEWEST = 5
local RETRY_EVERY, RETRIES = 10, 3
local MAX_PARTIAL = 4

local handlers = {}
local noticed = {}

-- handler(body, sender) for messages whose body starts with "<kind>;"; sender is a bare name.
function Hub.Register(kind, handler)
  handlers[kind] = handler
end

-- Whether the bare name is in the player's group (spec 10: members only).
local function inGroup(name)
  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do
      local member = GetRaidRosterInfo(i)
      if member and bare(member) == name then return true end
    end
    return false
  end
  for i = 1, GetNumGroupMembers() - 1 do
    local member = UnitName("party" .. i)
    if member and bare(member) == name then return true end
  end
  return false
end

function Hub.Receive(prefix, body, sender)
  local version = tonumber(tostring(prefix):match("^BFLOOT(%d)$"))
  if not version or version < 1 or version > NEWEST then return end
  sender = bare(tostring(sender))
  -- The group channel echoes the add-on's own messages: it holds those already.
  if sender == bare(UnitName("player")) then return end
  if not inGroup(sender) then
    ns.Log("Sync: ignored a message from " .. sender .. ", who isn't in the group.")
    return
  end
  if version > 1 then
    if not noticed[version] then
      noticed[version] = true
      ns.Print("an officer's add-on in your group is newer than yours (sync version " .. version
        .. "): update Bureaucracy Forever to keep awards in sync.")
    end
    return
  end
  local kind = tostring(body):match("^(%u);")
  local handler = kind and handlers[kind]
  if handler then return handler(body, sender) end
  ns.Log("Sync: ignored a " .. (kind or "malformed") .. " message from " .. sender .. ".")
end

-- Incomplete O and C messages, by sender, kind and msgid (a C's reqid), and each sender's in the
-- order they started. An entry: { key, kind, sender, msgid, total, raid, author (nil for a C),
-- pieces = { [n] = piece }, count, lastAt (when the last new chunk came) }.
local partials, started = {}, {}

local function forget(entry)
  partials[entry.key] = nil
  local list = started[entry.sender]
  for i, other in ipairs(list) do
    if other == entry then table.remove(list, i) break end
  end
end

local function drop(entry, why)
  forget(entry)
  ns.Log("Sync: dropped " .. entry.sender .. "'s message " .. entry.msgid .. " (" .. why .. ").")
end

local function missing(entry)
  local list = {}
  for n = 1, entry.total do
    if not entry.pieces[n] then list[#list + 1] = n end
  end
  return table.concat(list, ",")
end

-- Every 10 seconds with no new chunk while chunks are missing, asks the sender for them; after
-- three asks, drops it. A new chunk starts the count again: a long C arrives paced over a minute.
local function retry(entry, asked, wait)
  C_Timer.After(wait or RETRY_EVERY, function()
    if partials[entry.key] ~= entry then return end
    local quiet = GetTime() - entry.lastAt
    if quiet < RETRY_EVERY then return retry(entry, 0, RETRY_EVERY - quiet) end
    if asked == RETRIES then return drop(entry, "chunks still missing") end
    local body = "Q;" .. entry.msgid .. ";" .. missing(entry)
    Hub.sendRequest(entry.sender, body)
    retry(entry, asked + 1)
  end)
end

-- The award an operation names, as "Ana Vale's <item>" when held, for the officer.
local function awardName(op)
  local key = op.type == "award" and op.id or op.key
  local award = ns.Records.Get(key) or (op.type == "award" and op) or {}
  local item = award.item and (select(2, GetItemInfo(award.item)) or ("item " .. award.item))
  if award.char and item then return award.char .. "'s " .. item .. " (" .. key .. ")" end
  return "award " .. key
end

-- Applies a whole operation to its raid through Records, with the author as its sender; via is
-- the bare name of whoever forwarded it (a catch-up reply, #114), nil for a direct message.
function Hub.Apply(op, raidId, author, via)
  local Records = ns.Records
  local fields = { id = op.id, at = op.at, practice = op.practice, raid = raidId, via = via,
    author = bare(author) }
  local ok, why
  if op.type == "award" then
    for _, field in ipairs({ "boss", "item", "char", "user", "method", "roll", "note" }) do
      fields[field] = op[field]
    end
    fields.sender = author
    ok, why = Records.Award(fields)
  elseif op.type == "confirm" then
    ok, why = Records.Confirm(op.key, fields)
  elseif op.type == "not-confirmed" then
    ok, why = Records.NotConfirmed(op.key, fields)
  elseif op.type == "void" then
    fields.reason = op.reason
    ok, why = Records.Void(op.key, fields)
  else
    local award = {}
    for field, value in pairs(op.award) do award[field] = value end
    award.sender = author
    ok, why = Records.Replace(op.key, award, fields)
  end
  if ok then return end
  if why == "key-conflict" then
    ns.Print(author .. " sent a different version of " .. awardName(op)
      .. ". The one already recorded is kept.")
  else
    ns.Log("Sync: " .. author .. "'s operation " .. op.id .. " was not recorded (" .. why .. ").")
  end
end

-- The ids of the operations held for a raid, in the order made or received.
local function heldIds(raidId)
  local ids = {}
  for n, op in ipairs(ns.Records.Ops(raidId)) do ids[n] = op.id end
  return ids
end

-- A whole message is forgotten: a late copy of one of its chunks starts a new message, which
-- Records replays once whole (an id held with the same payload changes nothing), so a msgid used
-- again for another operation still arrives.
local function complete(entry, raidId)
  forget(entry)
  local text = table.concat(entry.pieces, "", 1, entry.total)
  local whole = entry.kind == "O" and ns.OpText.Decode(text) or entry.kind == "C" and Sync.ParseIds(text)
  if not whole then
    return ns.Log("Sync: dropped " .. entry.sender .. "'s message " .. entry.msgid .. " (malformed).")
  end
  if entry.kind == "O" then
    -- An author other than the sender came forwarded, in a catch-up reply.
    local via = bare(entry.author) ~= entry.sender and entry.sender or nil
    return Hub.Apply(whole, raidId, entry.author, via)
  end
  local theirs, lacking = {}, {}
  for _, id in ipairs(whole) do theirs[id] = true end
  for _, id in ipairs(heldIds(raidId)) do
    if not theirs[id] then lacking[#lacking + 1] = id end
  end
  Hub.onCatchUp(entry.sender, entry.msgid, raidId, lacking)
end

-- Keeps a chunk of an O or C message (as Sync.ParseChunk or Sync.ParseRequest gives it) from
-- sender, and handles the message once all its chunks have arrived.
local function collect(kind, chunk, sender)
  local raidId, notice = ns.Raids.FindByCode(chunk.raid)
  if not raidId then
    return ns.Log("Sync: ignored " .. sender .. "'s message for raid " .. chunk.raid .. ": "
      .. (notice or "not loaded."))
  end
  local key = sender .. ";" .. kind .. ";" .. chunk.msgid
  local entry = partials[key]
  if not entry then
    entry = { key = key, kind = kind, sender = sender, msgid = chunk.msgid, total = chunk.total,
      raid = chunk.raid, author = chunk.author, pieces = {}, count = 0 }
    started[sender] = started[sender] or {}
    if #started[sender] == MAX_PARTIAL then drop(started[sender][1], "too many incomplete") end
    partials[key] = entry
    table.insert(started[sender], entry)
    retry(entry, 0)
  elseif chunk.total ~= entry.total or chunk.raid ~= entry.raid or chunk.author ~= entry.author then
    return ns.Log("Sync: dropped a chunk of " .. sender .. "'s message " .. chunk.msgid
      .. " that doesn't match its others.")
  end
  if entry.pieces[chunk.n] then return end
  entry.pieces[chunk.n] = chunk.piece
  entry.count = entry.count + 1
  entry.lastAt = GetTime()
  if entry.count == entry.total then complete(entry, raidId) end
end

Hub.Register("O", function(body, sender)
  local chunk = Sync.ParseChunk(body)
  if not chunk then return ns.Log("Sync: dropped a malformed O message from " .. sender .. ".") end
  collect("O", chunk, sender)
end)

-- A catch-up request (spec 10.4): the ids the sender holds, whispered after an H of ours differed.
Hub.Register("C", function(body, sender)
  local chunk = Sync.ParseRequest(body)
  if not chunk then return ns.Log("Sync: dropped a malformed C message from " .. sender .. ".") end
  collect("C", chunk, sender)
end)

-- The end of a catch-up reply (spec 10.2): "D;reqid;count". Only logged: the operations came
-- before it as O messages.
Hub.Register("D", function(body, sender)
  local reqid, count = body:match("^D;([a-z0-9]+);(%d%d?%d?)$")
  if not reqid or #reqid ~= 6 then
    return ns.Log("Sync: dropped a malformed D message from " .. sender .. ".")
  end
  ns.Log("Sync: " .. sender .. " answered catch-up request " .. reqid .. " with " .. tonumber(count)
    .. " operations.")
end)

-- A resend request for a message this add-on sent: "Q;msgid;1,3".
Hub.Register("Q", function(body, sender)
  local msgid, list = body:match("^Q;([a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9]);([%d,]+)$")
  local chunks = {}
  for n in ((list or "") .. ","):gmatch("([^,]*),") do
    n = tonumber(n:match("^%d%d?%d?$"))
    if not n or n < 1 then msgid = nil break end
    chunks[#chunks + 1] = n
  end
  if not msgid then return ns.Log("Sync: dropped a malformed Q message from " .. sender .. ".") end
  Hub.onRequest(sender, msgid, chunks)
end)

-- Sending (#25): this add-on's own operations go out as O messages, one at a time, paced so the
-- game doesn't throttle them, and held during boss fights. The queue lives only in this session:
-- the records stay in Records, and catch-up covers what was never sent. The pace and sizes are
-- cautious guesses, to check in a real raid (#22).
local PACE = 1          -- seconds between two messages
local FAILED_WAIT = 5   -- seconds before trying a message the game didn't send again
local QUEUE_SIZE = 100  -- messages waiting to be sent
local SENT_KEPT = 100   -- recent operations kept to resend: at least a full queue's worth

-- Each queued message: { body, target (a whisper; nil for the group), failed }.
local queue, waiting, fighting, nextAt = {}, false, false, 0
local sent, sentOrder = {}, {}

-- The group's add-on channel, or nil when not in a group.
local function groupChannel()
  if IsInRaid() then return "RAID" end
  if GetNumGroupMembers() > 0 then return "PARTY" end
end

local function succeeded(result)
  local results = Enum and Enum.SendAddonMessageResult
  return result == true or result == ((results and results.Success) or 0)
end

-- Out of the group: nothing more is sent, and catch-up covers what was waiting.
local function dropQueue()
  if #queue == 0 then return end
  ns.Log("Sync: not in a group, so " .. #queue .. " messages weren't sent; catch-up covers them.")
  queue = {}
end

-- Sends the message at the head of the queue, and says how long to wait before the next.
local function sendHead()
  local channel = groupChannel()
  if not channel then
    dropQueue()
    return 0
  end
  local message = queue[1]
  local result = C_ChatInfo.SendAddonMessage(Sync.PREFIX, message.body,
    message.target and "WHISPER" or channel, message.target)
  if succeeded(result) then
    table.remove(queue, 1)
    return PACE
  end
  if not message.failed then
    message.failed = true
    ns.Log("Sync: the game didn't send a message (" .. tostring(result) .. "); trying it again.")
  end
  return FAILED_WAIT
end

local pump
pump = function()
  waiting = false
  if fighting or #queue == 0 then return end
  local wait = nextAt - GetTime()
  if wait <= 0 then
    wait = sendHead()
    nextAt = GetTime() + wait
    if #queue == 0 then return end
  end
  waiting = true
  C_Timer.After(wait, pump)
end

-- Queues messages (a list of { body, target }), all or none. Returns false and why not: "not in
-- a group" or "the sending queue is full"; uncapped ones are never refused for a full queue.
local function enqueue(messages, uncapped)
  if not groupChannel() then return false, "not in a group" end
  if not uncapped and #queue + #messages > QUEUE_SIZE then return false, "the sending queue is full" end
  for _, message in ipairs(messages) do queue[#queue + 1] = message end
  if not waiting then pump() end
  return true
end

-- Keeps a sent message's bodies, so a Q for its chunks can be answered.
local function remember(msgid, bodies)
  sent[msgid] = bodies
  sentOrder[#sentOrder + 1] = msgid
  if #sentOrder > SENT_KEPT then sent[table.remove(sentOrder, 1)] = nil end
end

-- Sends an operation made on this add-on (as Records returns it) to the group, for its raid id.
-- Returns true once queued; otherwise logs why, and the record waits for catch-up. Never call it
-- for an operation received from another officer: those are never sent again.
function Hub.SendOp(op, raidId)
  local snapshot = raidId and ns.Raids.Get(raidId)
  if not snapshot then
    ns.Log("Sync: " .. op.id .. " has no loaded raid, so it wasn't sent; catch-up covers it.")
    return false
  end
  local msgid = Sync.NewMsgId()
  local bodies = Sync.EncodeOp(op, snapshot.code, bare(UnitName("player")), msgid)
  local messages = {}
  for n, body in ipairs(bodies) do messages[n] = { body = body } end
  local queued, why = enqueue(messages)
  if not queued then
    ns.Log("Sync: " .. why .. ", so " .. op.id .. " wasn't sent; catch-up covers it.")
    return false
  end
  remember(msgid, bodies)
  return true
end

-- Whispers a Q to target, paced with the rest.
function Hub.sendRequest(target, body)
  local queued, why = enqueue({ { body = body, target = target } })
  if not queued then ns.Log("Sync: " .. why .. ", so " .. body .. " to " .. target .. " wasn't sent.") end
end

-- Re-sends the chunks of msgid that sender asked for again, as whispers.
function Hub.onRequest(sender, msgid, chunks)
  local bodies = sent[msgid]
  if not bodies then
    return ns.Log("Sync: " .. sender .. " asked again for " .. msgid .. ", which is no longer held.")
  end
  local messages = {}
  for _, n in ipairs(chunks) do
    if bodies[n] then
      messages[#messages + 1] = { body = bodies[n], target = sender }
    else
      ns.Log("Sync: " .. sender .. " asked for chunk " .. n .. " of " .. msgid .. ", which has none.")
    end
  end
  local queued, why = enqueue(messages)
  if not queued then
    ns.Log("Sync: " .. why .. ", so " .. msgid .. " wasn't sent again to " .. sender .. ".")
  end
end

-- Who runs the add-on (P) and the group's selection (S), spec 2.1 and 10.4 (#62). Neither needs a
-- loaded raid, and both keep flowing while not a guild run. The roster, the bare names seen sending
-- P, lives only in this session.
local roster = {}
-- Whether the player was in a group at the last look; nil until the first PLAYER_ENTERING_WORLD.
local grouped

-- Queues a P or S body to the group, or as a whisper to target, paced with the rest. A full queue
-- never refuses one: no catch-up covers a lost selection, and each is a single short message.
local function sendBody(body, target)
  local queued, why = enqueue({ { body = body, target = target } }, true)
  if not queued then ns.Log("Sync: " .. why .. ", so " .. body .. " wasn't sent.") end
end

-- What this add-on holds (spec 10.2, #20): an H body ("H;raid;version;count;digest") per loaded
-- raid, sent to the group, or whispered to target, for each raid id given (every loaded one when
-- nil). The ids held count no awards merged from the site: those add no operations.
local function sendHeld(target, raidIds)
  if not raidIds then
    raidIds = {}
    for n, raid in ipairs(ns.Raids.Status()) do raidIds[n] = raid.id end
  end
  for _, raidId in ipairs(raidIds) do
    local ids = heldIds(raidId)
    sendBody(string.format("H;%s;%d;%d;%s", ns.OpText.Escape(ns.Raids.Get(raidId).code), Sync.VERSION,
      #ids, ns.Digest.Of(ids)), target)
  end
end

-- An H whose digest differs from ours is answered with a C, whispered: every id held, chunked like
-- an O, and kept to resend like one. All or none, as for an O; the next H covers a full queue.
Hub.Register("H", function(body, sender)
  local raid, digest = body:match("^H;([^;]*);%d%d?%d?;%d+;(%x%x%x%x%x%x%x%x)$")
  raid = raid and ns.OpText.Unescape(raid)
  if not (raid and raid ~= "" and digest == digest:lower()) then
    return ns.Log("Sync: dropped a malformed H message from " .. sender .. ".")
  end
  local raidId, notice = ns.Raids.FindByCode(raid)
  if not raidId then
    return ns.Log("Sync: ignored " .. sender .. "'s H for raid " .. raid .. ": " .. (notice or "not loaded."))
  end
  local ids = heldIds(raidId)
  if ns.Digest.Of(ids) == digest then return end
  local reqid = Sync.NewMsgId()
  local bodies = Sync.EncodeRequest(ids, ns.Raids.Get(raidId).code, reqid)
  local messages = {}
  for n, request in ipairs(bodies) do messages[n] = { body = request, target = sender } end
  local queued, why = enqueue(messages)
  if not queued then
    return ns.Log("Sync: " .. why .. ", so the catch-up request to " .. sender .. " wasn't sent.")
  end
  remember(reqid, bodies)
end)

-- A whole catch-up request from sender (spec 10.4): lacking are the ids held for raidId that
-- sender's list doesn't have, in the order made or received. Whispers sender each such operation
-- as O messages with its author, then "D;reqid;count"; nothing at all when it lacks none. Only
-- whole operations that fit the queue, the D counted, go; when some don't, it logs them and
-- whispers an H, queued after the rest, so sender asks again for them once the queue has drained:
-- rounds repeat until both match.
function Hub.onCatchUp(sender, reqid, raidId, lacking)
  ns.Log("Sync: " .. sender .. " asked to catch up (" .. reqid .. ") on raid " .. raidId .. "; they lack "
    .. #lacking .. (#lacking > 0 and (": " .. table.concat(lacking, ", ")) or "") .. ".")
  if #lacking == 0 then return end
  local wanted = {}
  for _, id in ipairs(lacking) do wanted[id] = true end
  local code = ns.Raids.Get(raidId).code
  local room = QUEUE_SIZE - #queue - 1
  local messages, replies = {}, {}
  for _, op in ipairs(ns.Records.Ops(raidId)) do
    if wanted[op.id] then
      local msgid = Sync.NewMsgId()
      local bodies = Sync.EncodeOp(op, code, ns.Records.Author(op), msgid)
      if #messages + #bodies > room then break end
      for _, body in ipairs(bodies) do messages[#messages + 1] = { body = body, target = sender } end
      replies[#replies + 1] = { msgid, bodies }
    end
  end
  local queued, why = false, "the sending queue is full"
  if #replies > 0 then
    messages[#messages + 1] = { body = "D;" .. reqid .. ";" .. #replies, target = sender }
    queued, why = enqueue(messages)
  end
  if not queued then
    ns.Log("Sync: " .. why .. ", so the catch-up reply to " .. sender .. " wasn't sent.")
    if not groupChannel() then return end
  else
    for _, reply in ipairs(replies) do remember(reply[1], reply[2]) end
    if #replies == #lacking then return end
    ns.Log("Sync: the sending queue is full, so " .. (#lacking - #replies) .. " of " .. #lacking
      .. " operations weren't sent to " .. sender .. "; they are sent when " .. sender .. " asks again.")
  end
  sendHeld(sender, { raidId })
end

-- The held selection as an S body ("S;choice;at;by"), or nil when it is none.
function Hub.SelectionBody()
  local status = ns.Selection.Status()
  if status.activeBy == "none" then return nil end
  local choice = status.activeBy == "off" and "-" or status.code
  return "S;" .. choice .. ";" .. status.at .. ";" .. ns.OpText.Escape(status.chosenBy)
end

-- This officer's own choice (the question, the Sync tab, a paste) goes to the group.
ns.Selection.onChoose = function()
  local body = Hub.SelectionBody()
  if body and groupChannel() then sendBody(body) end
end

-- Every P;1 is answered, not only one from a name not yet seen: an officer who reloads or logs in
-- again has lost their roster, and a P;0 is never answered, so nothing loops. The answer holds an
-- H per loaded raid: the newcomer's own H only makes the others ask it, so this lets it ask them.
Hub.Register("P", function(body, sender)
  local reply = body:match("^P;([01])$")
  if not reply then return ns.Log("Sync: dropped a malformed P message from " .. sender .. ".") end
  roster[sender] = true
  if reply == "0" then return end
  sendBody("P;0", sender)
  local selection = Hub.SelectionBody()
  if selection then sendBody(selection, sender) end
  sendHeld(sender)
end)

Hub.Register("S", function(body, sender)
  local choice, at, by = body:match("^S;([^;]*);(%d%d?%d?%d?%d?%d?%d?%d?%d?%d?);([^;]+)$")
  by = by and ns.OpText.Unescape(by)
  if not (by and by ~= "" and (choice == "-" or choice:find("^[PS][%u%d][%u%d][%u%d][%u%d][%u%d]$"))) then
    return ns.Log("Sync: dropped a malformed S message from " .. sender .. ".")
  end
  local applied, notice = ns.Selection.Apply(choice, tonumber(at), by)
  if not applied then return end
  if notice then ns.Print(notice) end
  ns.UI.RefreshSync()
end)

-- Whether the bare name is a group member the game shows offline (the roster's online flag; in a
-- party, UnitIsConnected). The player and anyone not found in the group never count as offline.
local function offline(name)
  if name == bare(UnitName("player")) then return false end
  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do
      local member, _, _, _, _, _, _, online = GetRaidRosterInfo(i)
      if member and bare(member) == name then return online == false end
    end
    return false
  end
  for i = 1, GetNumGroupMembers() - 1 do
    local member = UnitName("party" .. i)
    if member and bare(member) == name then return not UnitIsConnected("party" .. i) end
  end
  return false
end

-- The bare names of the other group members seen running the add-on and online, sorted. A name
-- that goes offline stays in the roster, so it counts again on coming back.
function Hub.Roster()
  local list = {}
  for name in pairs(roster) do
    if not offline(name) then list[#list + 1] = name end
  end
  table.sort(list, ns.Selection.NameBefore)
  return list
end

-- The loot master's bare name, or nil when master loot is off.
local function lootMaster()
  if not (C_PartyInfo and C_PartyInfo.GetLootMethod) then return nil end
  local method, partyIndex, raidIndex = C_PartyInfo.GetLootMethod()
  if method ~= "master" and not (Enum and Enum.LootMethod and method == Enum.LootMethod.Masterlooter) then
    return nil
  end
  local name
  if partyIndex == 0 then
    name = UnitName("player")
  elseif IsInRaid() then
    name = raidIndex and raidIndex > 0 and (GetRaidRosterInfo(raidIndex))
  else
    name = partyIndex and UnitName("party" .. partyIndex)
  end
  return name and bare(name) or nil
end

-- The group leader's bare name, or nil.
local function leader()
  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do
      local name, rank = GetRaidRosterInfo(i)
      if name and rank == 2 then return bare(name) end
    end
    return nil
  end
  if UnitIsGroupLeader("player") then return bare(UnitName("player")) end
  for i = 1, GetNumGroupMembers() - 1 do
    local name = UnitName("party" .. i)
    if name and UnitIsGroupLeader("party" .. i) then return bare(name) end
  end
end

-- Who asks the raid question (spec 2.1): the loot master if master loot is on and they run the
-- add-on, else the raid leader if they run it, else the add-on user who comes first by name, byte
-- by byte. An officer who is offline doesn't count. It runs on the online P roster and the game's
-- loot master and leader, so every add-on with the same roster gives the same name.
function Hub.Chooser()
  local users = { [bare(UnitName("player"))] = true }
  for _, name in ipairs(Hub.Roster()) do users[name] = true end
  local master, lead = lootMaster(), leader()
  if master and users[master] then return master end
  if lead and users[lead] then return lead end
  local first
  for name in pairs(users) do
    if not first or ns.Selection.NameBefore(name, first) then first = name end
  end
  return first
end

-- True when this player is the chooser (#53 asks the question then).
function Hub.IsChooser()
  return Hub.Chooser() == bare(UnitName("player"))
end

-- The first PLAYER_ENTERING_WORLD of a session is the login or the /reload: in a group, the
-- add-on says it runs and what it holds; out of one, a login clears the saved selection and a
-- /reload keeps it.
ns.On("PLAYER_ENTERING_WORLD", function(isInitialLogin)
  if grouped ~= nil then return end
  grouped = groupChannel() ~= nil
  if grouped then
    sendBody("P;1")
    return sendHeld()
  end
  if isInitialLogin then ns.Selection.Clear() end
end)

-- Joining a group says the add-on runs and what it holds; leaving it clears the roster and the
-- selection, so a new group asks fresh; a name that leaves the group leaves the roster.
ns.On("GROUP_ROSTER_UPDATE", function()
  if grouped == nil then return end
  local now = groupChannel() ~= nil
  if now and not grouped then
    sendBody("P;1")
    sendHeld()
  elseif now then
    for name in pairs(roster) do
      if not inGroup(name) then roster[name] = nil end
    end
  elseif grouped then
    -- What was queued for the old group, a selection included, never reaches the next one.
    dropQueue()
    roster = {}
    ns.Selection.Clear()
    ns.UI.RefreshSync()
  end
  grouped = now
end)

-- A snapshot loaded in a group says what is held for it. Before the first PLAYER_ENTERING_WORLD
-- (the inbox, read at load) it waits for that event's H for every raid.
ns.Raids.OnLoad(function(raidId)
  if grouped and groupChannel() then sendHeld(nil, { raidId }) end
end)

ns.On("ENCOUNTER_START", function() fighting = true end)
ns.On("ENCOUNTER_END", function()
  fighting = false
  if not waiting then pump() end
end)

for version = 1, NEWEST do
  C_ChatInfo.RegisterAddonMessagePrefix("BFLOOT" .. version)
end

ns.On("CHAT_MSG_ADDON", function(prefix, body, _, sender)
  Hub.Receive(prefix, body, sender)
end)
