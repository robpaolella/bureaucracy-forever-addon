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
