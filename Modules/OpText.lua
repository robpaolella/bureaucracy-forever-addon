-- OpText: an operation as one line of text (ADDON-SPEC.md 10.1, escaping 9.3). Shared by the
-- copy-out text (12) and the officers' sync messages (#19).
local _, ns = ...

local OpText = {}
ns.OpText = OpText

-- Spec 9.3: "%", ";", "<", ">", "|" and bytes below 0x20 or 0x7F become %XX; the rest stays.
function OpText.Escape(value)
  if value == nil then return "" end
  return (tostring(value):gsub("[%%;<>|%c]", function(char)
    return string.format("%%%02X", char:byte())
  end))
end

local TYPES = { award = "A", confirm = "K", ["not-confirmed"] = "N", void = "V", replace = "R" }
local AWARD_FIELDS = { "boss", "item", "char", "user", "method", "roll", "note", "sender", "at" }

-- Escapes and joins the first n fields; a nil field is an empty one.
local function join(parts, n)
  for i = 1, n do parts[i] = OpText.Escape(parts[i]) end
  return table.concat(parts, ";", 1, n)
end

-- Appends the award's fields from index n + 1 on; returns the new length.
local function addAward(parts, n, award)
  for _, field in ipairs(AWARD_FIELDS) do
    n = n + 1
    parts[n] = award[field]
  end
  return n
end

-- The operation's line, without raid and env (they come from the envelope or the copy-out
-- header). The practice field is "1" or empty. A replace's new award takes the replace's practice.
function OpText.Encode(op)
  local practice = op.practice and "1" or ""
  local kind = op.type
  if kind == "award" then
    local parts = { "A", op.id }
    local n = addAward(parts, 2, op)
    parts[n + 1] = practice
    return join(parts, n + 1)
  elseif kind == "confirm" or kind == "not-confirmed" then
    return join({ TYPES[kind], op.id, op.key, op.at, practice }, 5)
  elseif kind == "void" then
    return join({ "V", op.id, op.key, op.reason, op.at, practice }, 6)
  elseif kind == "replace" then
    local parts = { "R", op.id, op.key, op.at, practice, op.award.id }
    return join(parts, addAward(parts, 6, op.award))
  end
  error("unknown operation type: " .. tostring(kind))
end

-- Whether text is well-formed UTF-8: no stray continuation bytes, overlong forms, surrogates or
-- code points past U+10FFFF.
function OpText.ValidUtf8(text)
  local i, n = 1, #text
  while i <= n do
    local c = text:byte(i)
    local size, low, high = 1, 0x80, 0xBF
    if c >= 0xC2 and c <= 0xDF then size = 2
    elseif c >= 0xE0 and c <= 0xEF then
      size = 3
      if c == 0xE0 then low = 0xA0 elseif c == 0xED then high = 0x9F end
    elseif c >= 0xF0 and c <= 0xF4 then
      size = 4
      if c == 0xF0 then low = 0x90 elseif c == 0xF4 then high = 0x8F end
    elseif c >= 0x80 then return false end
    for k = 1, size - 1 do
      local b = text:byte(i + k)
      if not b or b < (k == 1 and low or 0x80) or b > (k == 1 and high or 0xBF) then return false end
    end
    i = i + size
  end
  return true
end

-- Undoes Escape: the field's text, or nil when it has a "%" without two hex digits, a byte
-- Escape always writes as %XX (";" is the separator), or isn't valid UTF-8 once decoded.
function OpText.Unescape(field)
  if field:find("[<>|%c]") or field:gsub("%%%x%x", ""):find("%%") then return nil end
  local text = field:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)
  if not OpText.ValidUtf8(text) then return nil end
  return text
end

local CODES = {}
for kind, code in pairs(TYPES) do CODES[code] = kind end
-- Fields after the type (spec 10.1); a replace's are followed by its new award's.
local LAYOUT = {
  award = { "id", "boss", "item", "char", "user", "method", "roll", "note", "sender", "at", "practice" },
  confirm = { "id", "key", "at", "practice" },
  ["not-confirmed"] = { "id", "key", "at", "practice" },
  void = { "id", "key", "reason", "at", "practice" },
  replace = { "id", "key", "at", "practice" },
}
local NUMBERS = { item = true, roll = true, at = true }

-- Sets fields[from..] on target by the names in layout; nil when a value has the wrong type.
local function fill(target, layout, fields, from)
  for i, name in ipairs(layout) do
    local value = fields[from + i - 1]
    if value == "" then
      value = nil
    elseif name == "practice" then
      if value ~= "1" then return nil end
      value = true
    elseif NUMBERS[name] then
      if not value:find("^%d+$") then return nil end
      value = tonumber(value)
    end
    target[name] = value
  end
  return target
end

-- The operation an operation text (spec 10.1) describes, with the fields Encode reads, or nil and
-- "malformed": an unknown type, the wrong field count, a bad escape, text that isn't UTF-8, a
-- practice field other than "1" or empty, or an item, roll or time that isn't a whole number.
-- Raid and env are not in the text: the caller adds them from the envelope.
function OpText.Decode(text)
  local fields = {}
  for field in (text .. ";"):gmatch("([^;]*);") do
    local value = OpText.Unescape(field)
    if value == nil then return nil, "malformed" end
    fields[#fields + 1] = value
  end
  local kind = CODES[fields[1]]
  local layout = LAYOUT[kind]
  if not layout then return nil, "malformed" end
  local count = 1 + #layout + (kind == "replace" and #AWARD_FIELDS + 1 or 0)
  if #fields ~= count then return nil, "malformed" end
  local op = fill({ type = kind }, layout, fields, 2)
  if op and kind == "replace" then
    op.award = fill({}, { "id", unpack(AWARD_FIELDS) }, fields, 2 + #layout)
    if not op.award then op = nil end
  end
  if not op then return nil, "malformed" end
  return op
end

-- The raid-chat line (ADDON-SPEC.md 9; wording from the approved design, `design/9-loot-ui`).
local MAX_LINE = 255
local MAX_KEY = 24
local HOW = { HR = "hard reserve", SR = "soft reserve" }
local DE = "disenchant/bank"

local function isText(value) return type(value) == "string" and value ~= "" end

-- The first problem with the fields every line needs, or nil.
local function checkCommon(kind, data)
  if not (isText(data.raid) and data.raid:find("^[PS][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9]$")) then
    return "the raid code is not P or S and five letters or digits"
  end
  local names = { "key" }
  if kind ~= "award" then names[#names + 1] = "id" end
  if kind == "correction" then names[#names + 1] = "newKey" end
  for _, name in ipairs(names) do
    local value = data[name]
    if not (isText(value) and value:find("^[%w_-]+$")) then
      return "the " .. name .. " is missing or has odd characters"
    end
    if #value > MAX_KEY then
      return "the " .. name .. " is over " .. MAX_KEY
        .. " characters: void it on the site or by the helper's upload"
    end
  end
  if kind == "correction" and data.newKey == data.key then return "the new key equals the voided key" end
  if not isText(data.link) then return "the item link is missing" end
  for _, name in ipairs({ "winner", "oldWinner" }) do
    local value = data[name]
    if value ~= nil and (type(value) ~= "string" or value:find("[<>|]")) then
      return "the " .. name .. " is not plain text (it has <, > or |)"
    end
  end
end

-- The first problem with an award's or correction's item, boss and method, or nil.
local function checkAward(data)
  local item = data.item
  if not (type(item) == "number" and item >= 1 and item <= 9999999 and item % 1 == 0) then
    return "the item id is not a whole number of at most 7 digits"
  end
  if not data.link:find("|Hitem:" .. string.format("%d", item) .. ":", 1, true) then
    return "the item link does not match the item id"
  end
  if not (isText(data.boss) and #data.boss >= 5) then return "the boss id is missing" end
  local method, roll = data.method, data.roll
  if method ~= "HR" and method ~= "SR" and method ~= "OPEN_ROLL" and method ~= "DISENCHANT_BANK" then
    return "the loot method " .. tostring(method) .. " is not built into chat lines"
  end
  if roll ~= nil and not (type(roll) == "number" and roll >= 1 and roll <= 100 and roll % 1 == 0) then
    return "the roll is not 1 to 100"
  end
  if method == "OPEN_ROLL" and roll == nil then return "an open roll needs its roll number" end
  local winner = data.winner
  if method == "DISENCHANT_BANK" then
    if isText(winner) then return "a disenchant/bank line has no winner" end
  elseif not isText(winner) then
    return "the winner is missing"
  end
end

-- The human part, fullest first: each next one has given way one more step (spec 9.1a).
local function humanParts(kind, data)
  local link, winner = data.link, data.winner
  local to = isText(winner) and winner or nil
  local how = data.method == "OPEN_ROLL" and ("open roll, " .. tostring(data.roll)) or HOW[data.method]
  if kind == "undo" then
    local now = to and ("is no longer awarded to " .. to) or "is no longer going to " .. DE
    return { "Undo: " .. link .. " " .. now, "Undo: " .. link, link }
  end
  local parts, label, old = {}, kind == "correction" and "Correction: " or "", nil
  if kind == "correction" then old = isText(data.oldWinner) and data.oldWinner or DE end
  local target = to and (to .. " (" .. how .. ")") or DE
  local base = label .. link .. " → " .. target
  parts[1] = old and (base .. ", not " .. old) or base
  if old then parts[#parts + 1] = base end
  if to then parts[#parts + 1] = label .. link .. " → " .. to end
  parts[#parts + 1] = label .. link
  if label ~= "" then parts[#parts + 1] = link end
  return parts
end

-- The chat line for an operation ("award", "undo" or "correction"; the spec's replacement line is
-- the correction), or nil and the reason it can't be built or won't fit. `data` holds: raid, key
-- (an award's own key; for undo and correction the key being voided), id (the undo's or
-- correction's own id), newKey (a correction's new award), item, link, boss (a LootBoss id),
-- method, roll, winner (nil for DISENCHANT_BANK; for undo, the winner being undone, nil for
-- disenchant/bank), oldWinner (a correction's previous winner, nil for disenchant/bank) and
-- practice. The machine part is never shortened.
function OpText.BuildLine(operation, data)
  if operation ~= "award" and operation ~= "undo" and operation ~= "correction" then
    return nil, "unknown operation " .. tostring(operation)
  end
  local problem = checkCommon(operation, data) or (operation ~= "undo" and checkAward(data)) or nil
  if not problem and operation == "undo" and not data.link:find("|Hitem:%d+:") then
    problem = "the item link is not an item link"
  end
  if problem then return nil, problem end

  local boss = operation ~= "undo" and data.boss:sub(-5):lower() or nil
  local fields, count
  if operation == "award" then
    fields = { "A", data.raid, data.key, data.item, boss, data.method, data.roll, data.winner }
    count = 8
  elseif operation == "undo" then
    fields = { "V", data.raid, data.id, data.key }
    count = 4
  else
    fields = { "R", data.raid, data.id, data.key, data.newKey, data.item, boss, data.method, data.roll,
      data.winner }
    count = 10
  end
  for i = 1, count do fields[i] = OpText.Escape(fields[i]) end
  local machine = "<" .. (data.practice and "BF1P;" or "BF1;") .. table.concat(fields, ";", 1, count) .. ">"
  local prefix = data.practice and "[Practice] " or ""
  for _, human in ipairs(humanParts(operation, data)) do
    local line = prefix .. human .. " " .. machine
    if #line <= MAX_LINE then return line end
  end
  return nil, "the line is over " .. MAX_LINE .. " bytes even with the shortest wording"
end
