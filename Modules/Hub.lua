-- Hub: officers' hidden sync messages in (ADDON-SPEC.md 10, 10.2 to 10.4; #71). Checks each
-- message's prefix and sender, hands its body to the handler for its type, and rebuilds O
-- messages from their chunks before applying the operation through Records.
local _, ns = ...

local Hub = {}
ns.Hub = Hub

local bare = ns.Rules.Bare

-- The game delivers only registered prefixes: the newer ones are registered so the add-on can
-- tell the officer it needs updating (conductor's call, #71, 2026-10-15).
local NEWEST = 5
local RETRY_EVERY, RETRIES = 10, 3
local MAX_PARTIAL = 4

-- Listeners #25 connects to sending. sendRequest(target, body) whispers a Q to target;
-- onRequest(sender, msgid, chunks) re-sends the chunks of msgid that sender asked for again.
Hub.sendRequest = nil
Hub.onRequest = nil

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
local partials, started, done = {}, {}, {}

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
    if Hub.sendRequest then
      Hub.sendRequest(entry.sender, body)
    else
      ns.Log("Sync: no sender connected for " .. body .. " to " .. entry.sender .. ".")
    end
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

local function complete(entry, raidId)
  forget(entry)
  done[entry.sender .. ";" .. entry.msgid] = true
  local op = ns.OpText.Decode(table.concat(entry.pieces, "", 1, entry.total))
  if not op then
    return ns.Log("Sync: dropped " .. entry.sender .. "'s message " .. entry.msgid .. " (malformed).")
  end
  apply(op, raidId, entry.author)
end

Hub.Register("O", function(body, sender)
  local chunk = ns.Sync.ParseChunk(body)
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
  if done[key] then return end
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
  if Hub.onRequest then return Hub.onRequest(sender, msgid, chunks) end
  ns.Log("Sync: " .. sender .. " asked again for " .. msgid .. "; nothing connected to re-send.")
end)

for version = 1, NEWEST do
  C_ChatInfo.RegisterAddonMessagePrefix("BFLOOT" .. version)
end

ns.On("CHAT_MSG_ADDON", function(prefix, body, _, sender)
  Hub.Receive(prefix, body, sender)
end)
