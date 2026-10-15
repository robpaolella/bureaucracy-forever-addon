-- Sync: reserves in and awards out, by pasted text, the helper's inbox and officers' add-ons.
local _, ns = ...

local Sync = {}
ns.Sync = Sync

-- The site's pasted reserves text (spec 3.2): every line pasted so far, as a string or a list.
-- Returns the validated snapshot and the update notice (nil when none), or nil and an error
-- for the officer. Stores nothing: the caller loads it (Raids.Load).
function Sync.ReadPasted(pasted)
  local Snapshot = ns.Snapshot
  local text, err = Snapshot.Assemble(pasted)
  if not text then return nil, err end
  local tree
  tree, err = Snapshot.Parse(text)
  if tree == nil then return nil, err end
  local snapshot
  snapshot, err = Snapshot.Validate(tree, ns.version)
  if not snapshot then return nil, err end
  return snapshot, Snapshot.UpdateNotice(snapshot.addon, ns.version)
end

-- Whether the operation is, or names, a practice award: these are never copied out (spec 12).
local function isPractice(op)
  if op.practice then return true end
  local award = op.key and ns.Records.Get(op.key)
  return award ~= nil and award.practice == true
end

-- The copy-out text for a loaded raid (spec 12): the header, one operation text per line in the
-- order they happened, and E;<count>. Returns the text and the number of operation lines, or
-- nil and why. Practice records are left out and not counted.
function Sync.CopyOut(raidId)
  if raidId == nil then
    return nil, "Awards made with no raid can't be copied until they are attached to a raid."
  end
  local snapshot = ns.Raids.Get(raidId)
  if not snapshot then
    return nil, "That raid isn't loaded, so its code and environment are unknown."
  end
  local lines = { string.format("BFOUT1;%s;%s;%s", ns.OpText.Escape(raidId),
    ns.OpText.Escape(snapshot.code), ns.OpText.Escape(snapshot.env)) }
  for _, op in ipairs(ns.Records.Ops(raidId)) do
    if not isPractice(op) then lines[#lines + 1] = ns.OpText.Encode(op) end
  end
  local count = #lines - 1
  if count == 0 then return nil, "Nothing to copy: this raid has no awards to send." end
  lines[#lines + 1] = "E;" .. count
  return table.concat(lines, "\n"), count
end

-- Officers' sync messages (spec 10.2, 10.3). The game sends the prefix apart from the body, and
-- counts both, with a separator, against its 255 bytes.
Sync.PREFIX = "BFLOOT1"
local PIECE = 160
local MSGID_CHARS = "abcdefghijklmnopqrstuvwxyz0123456789"

-- A new msgid: six lower-case letters or digits.
function Sync.NewMsgId()
  local chars = {}
  for i = 1, 6 do
    local n = math.random(#MSGID_CHARS)
    chars[i] = MSGID_CHARS:sub(n, n)
  end
  return table.concat(chars)
end

-- Where the next piece of text, from byte first, ends: at most 160 bytes, never inside a UTF-8
-- character or a %XX escape.
local function pieceEnd(text, first)
  local last = math.min(first + PIECE - 1, #text)
  while last < #text and text:byte(last + 1) >= 0x80 and text:byte(last + 1) <= 0xBF do
    last = last - 1
  end
  if last < #text then
    if text:sub(last, last) == "%" then last = last - 1
    elseif text:sub(last - 1, last - 1) == "%" then last = last - 2 end
  end
  return last
end

-- An operation's O message bodies, in order (spec 10.2): "O;msgid;n/N;raid;author;piece".
-- raid is the raid code, author the officer who made it ("First Last"); msgid is new by default.
function Sync.EncodeOp(op, raid, author, msgid)
  local text = ns.OpText.Encode(op)
  local pieces, first = {}, 1
  while first <= #text do
    local last = pieceEnd(text, first)
    pieces[#pieces + 1] = text:sub(first, last)
    first = last + 1
  end
  msgid = msgid or Sync.NewMsgId()
  local Escape = ns.OpText.Escape
  local bodies = {}
  for n, piece in ipairs(pieces) do
    bodies[n] = string.format("O;%s;%d/%d;%s;%s;%s", msgid, n, #pieces, Escape(raid), Escape(author),
      piece)
  end
  return bodies
end

-- One O message body's fields: { msgid, n, total, raid, author, piece }, raid and author
-- unescaped, piece as sent (its operation text is decoded once whole). Nil and "malformed" for
-- another type, missing fields, a bad msgid, n/N out of range, or a bad escape.
function Sync.ParseChunk(body)
  local msgid, n, total, raid, author, piece = body:match("^O;([^;]*);(%d+)/(%d+);([^;]*);([^;]*);(.+)$")
  if not msgid or not msgid:find("^[a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9]$") then
    return nil, "malformed"
  end
  n, total = tonumber(n), tonumber(total)
  raid, author = ns.OpText.Unescape(raid), ns.OpText.Unescape(author)
  if n < 1 or n > total or not raid or raid == "" or not author or author == "" then
    return nil, "malformed"
  end
  return { msgid = msgid, n = n, total = total, raid = raid, author = author, piece = piece }
end
