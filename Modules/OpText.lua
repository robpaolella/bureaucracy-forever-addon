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
