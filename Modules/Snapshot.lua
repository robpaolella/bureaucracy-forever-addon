-- Snapshot: the site's reserves text read as data (ADDON-SPEC.md 3, 6, 7.3, 8). Pure: no game
-- calls, no saved data. Text is parsed by hand and never run: no loadstring, ever.
local _, ns = ...

local Snapshot = {}
ns.Snapshot = Snapshot

Snapshot.FORMAT_VERSION = 1
-- Limits from spec 7.3 rule 5. A pasted snapshot's text is one raid's entry.
Snapshot.MAX_DEPTH = 8
Snapshot.MAX_STRING = 200
Snapshot.MAX_TEXT = 200000
local MAX_INTEGER = 9007199254740991

local COPY_AGAIN = " Copy it again from the site."

-- Assembler (spec 3.2). pasted is a string or a list of strings; each line is
-- "BFSNAP1:<part>/<parts>:<piece>". Returns the joined text, or nil, an error and the
-- missing part numbers (when parts are missing). Pieces are kept exact: a part may end
-- inside a string, where a space matters.
function Snapshot.Assemble(pasted)
  if type(pasted) == "string" then pasted = { pasted } end
  local pieces, parts, size = {}, nil, 0
  for _, chunk in ipairs(pasted) do
    for line in chunk:gmatch("[^\r\n]+") do
      if line:match("%S") then
        local part, count, piece = line:match("^%s*BFSNAP1:(%d+)/(%d+):(.*)$")
        part, count = tonumber(part), tonumber(count)
        if not part then
          return nil, "This isn't the reserves text from the site." .. COPY_AGAIN
        end
        if count < 1 or part < 1 or part > count or count > Snapshot.MAX_TEXT then
          return nil, "The reserves text is damaged." .. COPY_AGAIN
        end
        if (parts and parts ~= count) or (pieces[part] and pieces[part] ~= piece) then
          return nil, "These parts come from different copies of the reserves text." .. COPY_AGAIN
        end
        if not pieces[part] then size = size + #piece end
        parts, pieces[part] = count, piece
      end
    end
  end
  if not parts then return nil, "Paste the reserves text from the site." end
  if size > Snapshot.MAX_TEXT then
    return nil, "The reserves text is too long for the add-on (over 200,000 characters)."
  end
  local missing = {}
  for i = 1, parts do
    if not pieces[i] then missing[#missing + 1] = i end
  end
  if #missing > 0 then
    local shown = {}
    for i = 1, math.min(#missing, 5) do shown[i] = tostring(missing[i]) end
    local list = table.concat(shown, ", ")
    if #missing > 5 then list = list .. " and " .. (#missing - 5) .. " more" end
    return nil, string.format("Still waiting for part%s %s of %d. Paste the rest to load the raid.",
      #missing > 1 and "s" or "", list, parts), missing
  end
  return table.concat(pieces)
end

-- Parser for the grammar of spec 8.2: tables, strings, integers and booleans, nothing else.
-- Returns the value, or nil and an error.
function Snapshot.Parse(text)
  if #text > Snapshot.MAX_TEXT then
    return nil, "The reserves text is too long for the add-on (over 200,000 characters)."
  end
  local pos = 1

  local function fail(why) error({ why = why }, 0) end
  local function skip() pos = text:find("%S", pos) or #text + 1 end
  local function peek() return text:sub(pos, pos) end
  local function expect(char)
    if peek() ~= char then fail("expected " .. char) end
    pos = pos + 1
  end

  local function readInteger()
    local digits = text:match("^%-?%d+", pos)
    if not digits then fail("expected a number") end
    pos = pos + #digits
    if text:match("^[%w_%.]", pos) then fail("numbers must be whole numbers") end
    local value = tonumber(digits)
    if #digits:gsub("^%-", "") > 16 or math.abs(value) > MAX_INTEGER then fail("a number is too big") end
    return value
  end

  -- Only \\, \" and three-digit \ddd escapes (spec 7.3 rule 4); other bytes must be printable.
  local function readString()
    pos = pos + 1
    local out = {}
    while true do
      local byte = text:byte(pos)
      if byte == nil then fail("a text value has no closing quote") end
      if byte == 34 then break end
      if byte == 92 then
        local escaped = text:sub(pos + 1, pos + 1)
        if escaped == "\\" or escaped == '"' then
          out[#out + 1] = escaped
          pos = pos + 2
        else
          local code = tonumber(text:match("^%d%d%d", pos + 1))
          if not code or code > 255 then fail("a text value has an escape the format doesn't allow") end
          out[#out + 1] = string.char(code)
          pos = pos + 4
        end
      elseif byte < 32 or byte > 126 then
        fail("a text value holds a character that should be escaped")
      else
        out[#out + 1] = string.char(byte)
        pos = pos + 1
      end
      if #out > Snapshot.MAX_STRING then
        fail("a text value is longer than " .. Snapshot.MAX_STRING .. " characters")
      end
    end
    pos = pos + 1
    return table.concat(out)
  end

  local readValue

  local function readTable(depth)
    if depth > Snapshot.MAX_DEPTH then fail("it nests deeper than " .. Snapshot.MAX_DEPTH .. " levels") end
    pos = pos + 1
    local t, count = {}, 0
    skip()
    while peek() ~= "}" do
      local key
      if peek() == "[" then
        pos = pos + 1
        skip()
        key = readInteger()
        skip()
        expect("]")
        skip()
        expect("=")
      else
        local name = text:match("^[%a_][%w_]*", pos)
        if name and name ~= "true" and name ~= "false" then
          pos = pos + #name
          skip()
          expect("=")
          key = name
        end
      end
      if key == nil then
        count = count + 1
        key = count
      end
      if t[key] ~= nil then fail("a field appears twice") end
      t[key] = readValue(depth)
      skip()
      if peek() == "," then
        pos = pos + 1
        skip()
      elseif peek() ~= "}" then
        fail("expected , or }")
      end
    end
    pos = pos + 1
    return t
  end

  readValue = function(depth)
    skip()
    local char = peek()
    if char == "{" then return readTable(depth + 1) end
    if char == '"' then return readString() end
    if char:match("[%-%d]") then return readInteger() end
    for _, word in ipairs({ "true", "false" }) do
      if text:match("^" .. word .. "%f[^%w_]", pos) then
        pos = pos + #word
        return word == "true"
      end
    end
    fail("unexpected " .. (char == "" and "end of text" or "character " .. char))
  end

  local ok, result = pcall(function()
    local value = readValue(0)
    skip()
    if pos <= #text then fail("unexpected text after the end") end
    return value
  end)
  if ok then return result end
  if type(result) ~= "table" then error(result, 0) end
  return nil, string.format("The reserves text is damaged near character %d (%s).%s",
    pos, result.why, COPY_AGAIN)
end

-- Versions compare as dotted numbers, ignoring a suffix such as "-dev". nil if unreadable.
local function versionParts(version)
  if type(version) ~= "string" then return nil end
  local core = version:match("^[^%-+]*")
  if not core:match("^%d+[%.%d]*$") or core:match("%.%.") or core:match("%.$") then return nil end
  local parts = {}
  for n in core:gmatch("%d+") do parts[#parts + 1] = tonumber(n) end
  return parts
end

function Snapshot.IsNewer(version, than)
  local a, b = versionParts(version), versionParts(than)
  if not a or not b then return false end
  for i = 1, math.max(#a, #b) do
    if (a[i] or 0) ~= (b[i] or 0) then return (a[i] or 0) > (b[i] or 0) end
  end
  return false
end

-- The notice when the snapshot names a newer add-on than this one, or nil. "|" is doubled so
-- the game shows it as text, not as a colour or link code.
function Snapshot.UpdateNotice(addon, mine)
  if type(addon) ~= "table" or not Snapshot.IsNewer(addon.version, mine) then return nil end
  local notice = string.format("Version %s of the add-on is out (you have %s).",
    (addon.version:gsub("|", "||")), mine)
  if type(addon.url) == "string" then
    notice = notice .. " Download it from " .. addon.url:gsub("|", "||") .. "."
  end
  return notice
end

-- Validator (spec 3.1). Checks run on any Lua table, so the inbox reader can use them too.
local function bad(where, why) error({ where = where, why = why }, 0) end

local function integer(v) return type(v) == "number" and v == math.floor(v) and math.abs(v) <= MAX_INTEGER end
local function str(v) return type(v) == "string" and #v <= Snapshot.MAX_STRING end
local function boolean(v) return type(v) == "boolean" end
local function oneOf(...)
  local allowed = {}
  for _, v in ipairs({ ... }) do allowed[v] = true end
  return function(v) return allowed[v] == true end
end

-- A check returns true (the value is kept as it is), a cleaned copy, or false.
local function checked(check, value, where)
  local result = check(value, where)
  if not result then bad(where, "has the wrong type") end
  if result == true then return value end
  return result
end

local function list(each)
  return function(v, where)
    if type(v) ~= "table" then bad(where, "should be a list") end
    local count, out = 0, {}
    for _ in pairs(v) do count = count + 1 end
    for i = 1, count do
      if v[i] == nil then bad(where, "should be a list") end
      out[i] = checked(each, v[i], where .. " " .. i)
    end
    return out
  end
end

-- fields: { name, check, optional }. Only these fields are copied: unknown ones are left behind.
local function record(fields)
  return function(v, where)
    if type(v) ~= "table" then bad(where, "should be a table") end
    local out = {}
    for _, field in ipairs(fields) do
      local name, check, optional = field[1], field[2], field[3]
      local path = (where == "" and "" or where .. ", ") .. name
      local value = v[name]
      if value == nil then
        if not optional then bad(path, "is missing") end
      else
        out[name] = checked(check, value, path)
      end
    end
    return out
  end
end

local holder = record({
  { "user", str }, { "char", str }, { "kind", oneOf("HR", "SR") }, { "trial", boolean },
  { "blocked", str, true },
})

local function reserves(v, where)
  if type(v) ~= "table" then bad(where, "should be a table") end
  local out = {}
  for item, holders in pairs(v) do
    if not integer(item) then bad(where, "should be keyed by item number") end
    out[item] = list(holder)(holders, where .. " " .. item)
  end
  return out
end

-- `user` and `roll` are absent when none, and a DISENCHANT_BANK award has no `char` (spec 3.4, 4).
local awardFields = record({
  { "key", str }, { "boss", str }, { "item", integer }, { "char", str, true },
  { "user", str, true },
  { "method", oneOf("HR", "SR", "MAIN_SPEC", "OFF_SPEC", "OPEN_ROLL", "DISENCHANT_BANK") },
  { "roll", function(v) return integer(v) and v >= 1 and v <= 100 end, true }, { "voided", boolean },
})
local function award(v, where)
  local out = awardFields(v, where)
  if out.char == nil and out.method ~= "DISENCHANT_BANK" then bad(where .. ", char", "is missing") end
  return out
end

local validate = record({
  { "formatVersion", oneOf(Snapshot.FORMAT_VERSION) },
  { "raid", str }, { "code", str }, { "env", oneOf("production", "staging") },
  { "name", str }, { "startsAt", integer }, { "durationMin", integer },
  { "instance", integer, true }, { "generated", integer },
  { "addon", record({ { "version", str }, { "url", str } }) },
  { "bosses", list(record({
    { "id", str }, { "name", str }, { "trash", boolean }, { "items", list(integer) },
    { "encounter", integer, true },
  })) },
  { "reserves", reserves },
  { "awards", list(award) },
})

-- Takes a parsed snapshot and this add-on's version. Returns a clean copy holding only the
-- spec's fields, or nil and an error. A newer formatVersion is refused before anything else.
function Snapshot.Validate(tree, mine)
  if type(tree) ~= "table" then return nil, "The reserves text isn't a raid snapshot." .. COPY_AGAIN end
  if integer(tree.formatVersion) and tree.formatVersion > Snapshot.FORMAT_VERSION then
    local message = "This reserves text needs a newer version of the add-on. Update the add-on, "
      .. "then paste it again."
    local notice = Snapshot.UpdateNotice(tree.addon, mine)
    return nil, notice and message .. " " .. notice or message
  end
  local ok, result = pcall(validate, tree, "")
  if ok then return result end
  if type(result) ~= "table" then error(result, 0) end
  return nil, string.format("The reserves text isn't valid: %s %s.%s", result.where, result.why, COPY_AGAIN)
end
