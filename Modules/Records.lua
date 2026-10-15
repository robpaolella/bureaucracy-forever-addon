-- Records: award records, their life cycle, and saving them (ADDON-SPEC.md 2, 4, 4.1, 4.2; #7).
-- Saved as BureaucracyForeverDB.awards[raidId], the raid's award records (voided ones kept), and
-- .ops[raidId], its operations in spec 4's shape, in the order made or received (for sync,
-- copy-out and the helper). Awards made with no loaded raid selected go to .noRaid and
-- .noRaidOps, without raid or env, until Attach. An operation naming an award not held yet stays
-- in the list and takes effect when the award arrives (4.2).
local _, ns = ...

local Records = {}
ns.Records = Records

local FORMAT_VERSION = 1
local ID_CHARS = "abcdefghijklmnopqrstuvwxyz0123456789"
local PREFIX = { award = "aw", confirm = "cf", ["not-confirmed"] = "nc", void = "vd", replace = "rp" }
local AWARD_FIELDS = {
  "raid", "env", "practice", "boss", "item", "char", "user", "method", "roll", "note", "sender", "at",
}
local MAX_TEXT = 200

-- The one place for the "not a guild run" rule (spec 2.1 "No"; #63): nothing new is recorded.
-- Voids and replaces of awards already held still are (Robert, #7, 2026-10-15).
local QUIET_ALLOWED = { void = true, replace = true }

local function quiet(kind, held)
  return ns.Selection.IsQuiet() and not (held and QUIET_ALLOWED[kind])
end

-- The award and operation lists of a raid, or of no raid when raidId is nil. create makes
-- missing lists, so reading never adds empty ones to the saved data.
local function lists(raidId, create)
  local db = ns.db
  if create then
    if raidId then
      db.awards, db.ops = db.awards or {}, db.ops or {}
      db.awards[raidId], db.ops[raidId] = db.awards[raidId] or {}, db.ops[raidId] or {}
    else
      db.noRaid, db.noRaidOps = db.noRaid or {}, db.noRaidOps or {}
    end
  end
  if raidId then return (db.awards or {})[raidId] or {}, (db.ops or {})[raidId] or {} end
  return db.noRaid or {}, db.noRaidOps or {}
end

local function find(list, field, value)
  for _, entry in ipairs(list) do
    if entry[field] == value then return entry end
  end
end

-- The award with this key and its raid id (nil for no raid), or nil.
local function locate(key)
  for raidId, awards in pairs(ns.db.awards or {}) do
    local award = find(awards, "key", key)
    if award then return award, raidId end
  end
  return find(ns.db.noRaid or {}, "key", key), nil
end

-- The operation with this id, a replacement's new award included.
local function findIn(ops, id)
  for _, op in ipairs(ops) do
    if op.id == id then return op end
    if op.award and op.award.id == id then return op.award end
  end
end

local function findOp(id)
  for _, ops in pairs(ns.db.ops or {}) do
    local op = findIn(ops, id)
    if op then return op end
  end
  return findIn(ns.db.noRaidOps or {}, id)
end

local function newId(prefix)
  local id
  repeat
    local chars = {}
    for i = 1, 8 do
      local n = math.random(#ID_CHARS)
      chars[i] = ID_CHARS:sub(n, n)
    end
    id = prefix .. "-" .. table.concat(chars)
  until not findOp(id) and not locate(id)
  return id
end

-- The same payload: every field but the times (spec 4.2).
local function same(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return a == b end
  for k, v in pairs(a) do
    if k ~= "at" and not same(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

-- An operation id (spec 4): 8 to 128 letters, digits, "_" or "-". The add-on makes 11 (9.1a):
-- a two-letter type, "-" and eight lower-case letters or digits.
function Records.ValidId(id)
  return type(id) == "string" and #id >= 8 and #id <= 128 and not id:find("[^%w_%-]")
end

local effect

-- Records an award, then what was waiting for its key (a void always wins, 4.2).
local function arrive(awards, ops, op, replaces)
  local award = { key = op.id, state = "announced", stateAt = op.at, replaces = replaces }
  for _, field in ipairs(AWARD_FIELDS) do award[field] = op[field] end
  awards[#awards + 1] = award
  for _, waiting in ipairs(ops) do
    if waiting.key == op.id then effect(awards, ops, waiting) end
  end
end

-- Applies an operation that names an award by key. Returns false when the award isn't held.
-- Applying one twice changes nothing, in any order.
effect = function(awards, ops, op)
  local award = find(awards, "key", op.key)
  if not award then return false end
  if op.type == "void" or op.type == "replace" then
    -- A voided award stays on the record; the first void's reason and time stand.
    if not award.voided then
      award.voided, award.voidReason, award.voidedAt = true, op.reason, op.at
    end
    if op.type == "replace" then
      award.replacedBy = award.replacedBy or op.award.id
      if not find(awards, "key", op.award.id) then arrive(awards, ops, op.award, op.key) end
    end
  else
    -- Confirmed or not: the later `at` wins, a tie goes to confirmed (4.1).
    local state = op.type == "confirm" and "confirmed" or "not-confirmed"
    if award.state == "announced" or op.at > award.stateAt
      or (op.at == award.stateAt and state == "confirmed") then
      award.state, award.stateAt = state, op.at
    end
  end
  return true
end

-- Saves an operation under raidId (nil: no raid) and applies it. Returns the operation and
-- "recorded", "pending" (it names an award not held yet) or "replayed" (held already); or nil
-- and "key-conflict" (its id is held with another payload: the first is kept).
local function record(raidId, op)
  local held = findOp(op.id)
  if held then
    if same(held, op) then return held, "replayed" end
    return nil, "key-conflict"
  end
  local awards, ops = lists(raidId, true)
  ops[#ops + 1] = op
  if op.type == "award" then
    arrive(awards, ops, op)
    return op, "recorded"
  end
  return op, effect(awards, ops, op) and "recorded" or "pending"
end

-- The raid awards go to now: the selected raid when loaded, else nil (no raid).
local function current()
  local raidId = ns.db.activeRaid
  if ns.Raids.Get(raidId) then return raidId end
end

local function envOf(raidId)
  local snapshot = ns.Raids.Get(raidId)
  return snapshot and snapshot.env
end

local function refusal(fields, kind, held)
  if kind and quiet(kind, held) then return "quiet" end
  if fields.id ~= nil and not Records.ValidId(fields.id) then return "bad id" end
  for _, field in ipairs({ "note", "reason" }) do
    if fields[field] and #fields[field] > MAX_TEXT then return "too long" end
  end
end

-- fields may carry id and at (an operation from another officer); otherwise they are made here.
local function newOp(kind, raidId, env, practice, fields)
  return { type = kind, id = fields.id or newId(PREFIX[kind]), formatVersion = FORMAT_VERSION,
    raid = raidId, env = env, practice = practice and true or nil, at = fields.at or time() }
end

local function awardOp(raidId, env, practice, fields)
  local op = newOp("award", raidId, env, practice, fields)
  for _, field in ipairs({ "boss", "item", "char", "user", "method", "roll", "note" }) do
    op[field] = fields[field]
  end
  -- The site knows the officer's character by its bare name (spec 4.2, 7.2: unknown-sender).
  op.sender = ns.Rules.Bare(fields.sender or UnitName("player"))
  return op
end

-- Each operation below returns the operation and its outcome ("recorded", "pending" or
-- "replayed"), or nil and why: "quiet" (not a guild run, see quiet()), "bad id", "too long" (a
-- note or reason over 200 characters) or "key-conflict".

-- A hand-out was announced. fields: boss, item, char, user, method, roll, note, practice, and
-- optionally id, at and sender (this officer by default). It goes to the selected raid, or is
-- held as no raid while none is loaded.
function Records.Award(fields)
  local reason = refusal(fields, "award")
  if reason then return nil, reason end
  local raidId = current()
  return record(raidId, awardOp(raidId, envOf(raidId), fields.practice, fields))
end

-- An operation naming an award by key goes where the award is held; for an award not held yet,
-- where awards go now. It takes the award's practice mark.
local function keyOp(kind, key, fields, extra)
  fields = fields or {}
  local award, raidId = locate(key)
  local reason = refusal(fields, kind, award ~= nil)
  if reason then return nil, reason end
  local env, practice
  if award then
    env, practice = award.env, award.practice
  else
    raidId = current()
    env, practice = envOf(raidId), fields.practice
  end
  local op = newOp(kind, raidId, env, practice, fields)
  op.key = key
  if extra then
    reason = extra(op, raidId, env, practice)
    if reason then return nil, reason end
  end
  return record(raidId, op)
end

-- fields (optional): id, at, practice (used only for an award not held yet).
function Records.Confirm(key, fields)
  return keyOp("confirm", key, fields)
end

function Records.NotConfirmed(key, fields)
  return keyOp("not-confirmed", key, fields)
end

-- fields (optional): reason, id, at, practice.
function Records.Void(key, fields)
  fields = fields or {}
  return keyOp("void", key, fields, function(op)
    op.reason = fields.reason
  end)
end

-- The award went to someone else: voids key and records award (Award's fields) as a new award
-- with a new key, named in the original's replacedBy and the new one's replaces.
function Records.Replace(key, award, fields)
  return keyOp("replace", key, fields, function(op, raidId, env, practice)
    local reason = refusal(award)
    if reason then return reason end
    op.award = awardOp(raidId, env, practice, award)
    -- The new award needs its own key: not the original's, nor another award's.
    local held = findOp(op.award.id)
    if op.award.id == key or op.award.id == op.id or (held and not same(held, op.award)) then
      return "key-conflict"
    end
  end)
end

-- Attaches every no-raid award and operation to a loaded raid (the selected one by default):
-- each takes the raid's id and environment and keeps its key. Returns how many awards were
-- attached, or nil and why ("quiet", "not loaded").
function Records.Attach(raidId)
  if quiet("attach") then return nil, "quiet" end
  raidId = raidId or current()
  local env = envOf(raidId)
  if not env then return nil, "not loaded" end
  local movedAwards, movedOps = lists(nil)
  ns.db.noRaid, ns.db.noRaidOps = nil, nil
  local awards, ops = lists(raidId, true)
  for _, award in ipairs(movedAwards) do
    award.raid, award.env = raidId, env
    awards[#awards + 1] = award
  end
  for _, op in ipairs(movedOps) do
    op.raid, op.env = raidId, env
    if op.award then op.award.raid, op.award.env = raidId, env end
    ops[#ops + 1] = op
  end
  -- What waited on either side for an award now held applies.
  for _, op in ipairs(ops) do
    if op.key then effect(awards, ops, op) end
  end
  return #movedAwards
end

-- The operations of a raid (nil: no raid), in the order made or received.
function Records.Ops(raidId)
  local _, ops = lists(raidId)
  return ops
end

-- The award with this key and its raid id (nil for no raid), or nil.
Records.Get = locate
