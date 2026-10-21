-- Hub: officers' hidden sync messages in and out (ADDON-SPEC.md 10, 10.2 to 10.4; #71, #25).
-- Checks each message's prefix and sender, hands its body to the handler for its type, and
-- rebuilds O messages from their chunks before applying the operation through Records. Sends
-- this add-on's own operations, and Q requests and resends, through one paced queue.
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

-- Incomplete O messages, by sender and msgid, and each sender's in the order they started.
-- An entry: { sender, msgid, total, raid, author, pieces = { [n] = piece }, count }.
local partials, started = {}, {}

local function forget(entry)
  partials[entry.sender .. ";" .. entry.msgid] = nil
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

-- Every 10 seconds while chunks are missing, asks the sender for them; after three asks, drops it.
local function retry(entry, asked)
  C_Timer.After(RETRY_EVERY, function()
    if partials[entry.sender .. ";" .. entry.msgid] ~= entry then return end
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

-- Applies a whole operation to its raid through Records, with the author as its sender.
local function apply(op, raidId, author)
  local Records = ns.Records
  local fields = { id = op.id, at = op.at, practice = op.practice, raid = raidId }
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

-- A whole message is forgotten: a late copy of one of its chunks starts a new message, which
-- Records replays once whole (an id held with the same payload changes nothing), so a msgid used
-- again for another operation still arrives.
local function complete(entry, raidId)
  forget(entry)
  local op = ns.OpText.Decode(table.concat(entry.pieces, "", 1, entry.total))
  if not op then
    return ns.Log("Sync: dropped " .. entry.sender .. "'s message " .. entry.msgid .. " (malformed).")
  end
  apply(op, raidId, entry.author)
end

Hub.Register("O", function(body, sender)
  local chunk = Sync.ParseChunk(body)
  if not chunk then return ns.Log("Sync: dropped a malformed O message from " .. sender .. ".") end
  if bare(chunk.author) ~= sender then
    -- Forwarded by a catch-up reply (#20), not applied here.
    return ns.Log("Sync: ignored " .. chunk.author .. "'s operation sent by " .. sender .. ".")
  end
  local raidId, notice = ns.Raids.FindByCode(chunk.raid)
  if not raidId then
    return ns.Log("Sync: ignored " .. sender .. "'s message for raid " .. chunk.raid .. ": "
      .. (notice or "not loaded."))
  end
  local key = sender .. ";" .. chunk.msgid
  local entry = partials[key]
  if not entry then
    entry = { sender = sender, msgid = chunk.msgid, total = chunk.total, raid = chunk.raid,
      author = chunk.author, pieces = {}, count = 0 }
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
  if entry.count == entry.total then complete(entry, raidId) end
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
local SENT_KEPT = 50    -- recent operations whose messages are kept to resend

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

-- Sends the message at the head of the queue, and says how long to wait before the next.
local function sendHead()
  local channel = groupChannel()
  if not channel then
    -- Out of the group: its messages are dropped (catch-up covers them), whispers stay.
    local kept, dropped = {}, 0
    for _, message in ipairs(queue) do
      if message.target then kept[#kept + 1] = message else dropped = dropped + 1 end
    end
    queue = kept
    if dropped > 0 then
      ns.Log("Sync: not in a group, so " .. dropped .. " messages weren't sent; catch-up covers them.")
    end
    if #queue == 0 then return 0 end
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

-- Queues messages (a list of { body, target }), all or none; false when the queue is too full.
local function enqueue(messages)
  if #queue + #messages > QUEUE_SIZE then return false end
  for _, message in ipairs(messages) do queue[#queue + 1] = message end
  if not waiting then pump() end
  return true
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
  if not groupChannel() then
    ns.Log("Sync: not in a group, so " .. op.id .. " wasn't sent; catch-up covers it.")
    return false
  end
  local msgid = Sync.NewMsgId()
  local bodies = Sync.EncodeOp(op, snapshot.code, bare(UnitName("player")), msgid)
  local messages = {}
  for n, body in ipairs(bodies) do messages[n] = { body = body } end
  if not enqueue(messages) then
    ns.Log("Sync: the sending queue is full, so " .. op.id .. " wasn't sent; catch-up covers it.")
    return false
  end
  sent[msgid] = bodies
  sentOrder[#sentOrder + 1] = msgid
  if #sentOrder > SENT_KEPT then sent[table.remove(sentOrder, 1)] = nil end
  return true
end

-- Whispers a Q to target, paced with the rest.
function Hub.sendRequest(target, body)
  if not enqueue({ { body = body, target = target } }) then
    ns.Log("Sync: the sending queue is full, so " .. body .. " to " .. target .. " wasn't sent.")
  end
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
  if not enqueue(messages) then
    ns.Log("Sync: the sending queue is full, so " .. msgid .. " wasn't sent again to " .. sender .. ".")
  end
end

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
