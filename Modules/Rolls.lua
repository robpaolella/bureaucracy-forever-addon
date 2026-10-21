-- Rolls: the roll-off engine (#13). Calls a roll for a pop-up row in raid chat, reads the players'
-- /roll lines, and returns the roll-off as data (Rolls.Result) for the pop-up to draw (#90). It draws
-- nothing and records nothing: the pick and the roll recorded with the award are #90's.
local _, ns = ...

local Rolls = {}
ns.Rolls = Rolls

local LINE_LIMIT = 255 -- the game's limit for a chat line, in bytes (links count in full)
local EARLY_LIMIT = 20 -- rolls kept from before any call
local MODE_WORDS = { hr = "hard reserve", sr = "soft reserve" }
local REASON_NOT_ELIGIBLE = "not eligible"
local REASON_NOT_TIED = "not in the tie"
local REASON_SECOND = "second roll, the first counts"
local REASON_RANGE = "not a 1-100 roll"
local REASON_EARLY = "rolled before the call"

local bare = ns.Rules.Bare

local offs = {} -- roll-offs by key, so a result can be read later
local current -- the roll-off now reading rolls: the newest one not over
local early = {} -- rolls seen while none was reading, kept to show with the next call

local function keyOf(slot, item) return slot .. ":" .. tostring(item) end

-- Whether practice mode is on (#17): the calls then start with "[Practice] ".
function Rolls.IsPractice() return ns.Practice() end

local function contains(list, name)
  for _, n in ipairs(list) do
    if bare(n) == bare(name) then return true end
  end
  return false
end

-- "A", "A and B", "A, B and C".
local function joined(names)
  if #names <= 1 then return names[1] or "" end
  return table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
end

-- Builds a line that fits the game's limit: build(namesText) gets the names that fit, and "and N
-- more" after them when some don't. Returns the line, or nil when not even no names fit.
local function fit(names, build)
  local prefix = Rolls.IsPractice() and "[Practice] " or ""
  for shown = #names, 0, -1 do
    local text
    if shown == #names then
      text = joined(names)
    elseif shown > 0 then
      text = table.concat(names, ", ", 1, shown) .. " and " .. (#names - shown) .. " more"
    else
      text = #names .. " players"
    end
    local line = prefix .. build(text)
    if #line <= LINE_LIMIT then return line end
  end
end

-- The raid warning when the player may post one, else raid chat (party chat outside a raid).
local function post(line)
  local channel = "PARTY"
  if IsInRaid() then
    local rights = UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
    channel = rights and "RAID_WARNING" or "RAID"
  end
  C_ChatInfo.SendChatMessage(line, channel)
  return channel
end

function Rolls.CallLine(link, kind, names)
  if kind == "open" then
    return fit({}, function() return "Open roll for " .. link .. ": everyone /roll" end)
  end
  return fit(names, function(text)
    return "Roll for " .. link .. ": " .. text .. " (" .. MODE_WORDS[kind] .. ")"
  end)
end

-- The officer clicked a row's Call roll or Call open roll: posts the call and starts reading
-- rolls for it. slot and item are what the clicked button showed. Returns the roll-off's result
-- (see Rolls.Result), or nil and why: "fight" (chat is locked), "not ready", "changed", "not a roll"
-- "another roll" (another row's roll-off is still reading: End it first, or wait for its hand-out)
-- or "line too long".
function Rolls.Start(slot, item)
  if ns.Popup.ChatLocked() then return nil, "fight" end
  local model = ns.Popup.Build()
  local row
  for _, r in ipairs(model and model.rows or {}) do
    if r.slot == slot then row = r end
  end
  if not row then return nil, "not ready" end
  -- Rolls can't be told apart by item, so one roll-off reads at a time (the same row may call again).
  if current and not current.over and current.key ~= keyOf(slot, item) then return nil, "another roll" end
  if row.item ~= item then return nil, "changed" end
  if row.action ~= "roll" and row.action ~= "openroll" then return nil, "not a roll" end
  local kind = row.action == "openroll" and "open" or row.mode
  local eligible
  if kind ~= "open" then
    eligible = {}
    for i, name in ipairs(row.contenders) do eligible[i] = name end
  end
  local line = Rolls.CallLine(row.link, kind, eligible)
  if not line then return nil, "line too long" end
  post(line)
  local off = { slot = slot, item = item, link = row.link, kind = kind, eligible = eligible, round = 1,
    counted = {}, ignored = {}, hidden = false, key = keyOf(slot, item) }
  for _, e in ipairs(early) do
    off.ignored[#off.ignored + 1] = { name = e.name, roll = e.roll, reason = REASON_EARLY }
  end
  early = {}
  if kind == "open" then
    off.everyone = {}
    for i = 1, 40 do
      local name = GetMasterLootCandidate(slot, i)
      if not name then break end
      off.everyone[#off.everyone + 1] = name
    end
  end
  offs[keyOf(slot, item)] = off
  current = off
  return Rolls.Result(slot, item)
end

-- The tie, if any: the names that share the highest counted roll (two or more), and that roll.
local function topOf(off)
  local best, names = 0, {}
  for _, r in ipairs(off.counted) do
    if r.roll > best then best, names = r.roll, { r.name }
    elseif r.roll == best then names[#names + 1] = r.name end
  end
  return best, names
end

-- The officer re-rolls a tie: posts the tie line and counts only the tied players' new rolls.
-- Returns the result, or nil and why: "fight", "no roll-off", "no tie".
function Rolls.Reroll(slot, item)
  if ns.Popup.ChatLocked() then return nil, "fight" end
  local off = offs[keyOf(slot, item)]
  if not off then return nil, "no roll-off" end
  local _, tied = topOf(off)
  if off.hidden or #tied < 2 then return nil, "no tie" end
  local line = fit(tied, function(text) return "Tie for " .. off.link .. ": " .. text .. ", roll again" end)
  if not line then return nil, "line too long" end
  post(line)
  off.round, off.counted, off.eligible, off.tiedOnly = off.round + 1, {}, tied, true
  off.over = false
  current = off
  return Rolls.Result(slot, item)
end

-- A roll-off's data for the pop-up: { item, link, kind ("hr", "sr" or "open"), round, entries (each:
-- name, roll or nil while waiting; for an open roll, the players who rolled), rolled, total (nil for
-- an open roll), ignored (each: name, roll, reason), winner (the highest roll; nil on a tie or when
-- hidden), tie (the tied names, or nil), hidden (a roll arrived hidden: pick from entries) }, or nil.
function Rolls.Result(slot, item)
  local off = offs[keyOf(slot, item)]
  if not off then return nil end
  local result = { slot = slot, item = item, link = off.link, kind = off.kind, round = off.round,
    entries = {}, rolled = #off.counted, ignored = {}, hidden = off.hidden }
  for i, e in ipairs(off.ignored) do result.ignored[i] = e end
  local byName = {}
  for _, r in ipairs(off.counted) do byName[bare(r.name)] = r.roll end
  local names = off.eligible
  if not names then
    names = {}
    if off.hidden then
      for _, n in ipairs(off.everyone) do names[#names + 1] = n end
    else
      for _, r in ipairs(off.counted) do names[#names + 1] = r.name end
    end
  end
  for _, name in ipairs(names) do
    result.entries[#result.entries + 1] = { name = name, roll = byName[bare(name)] }
  end
  if off.eligible then result.total = #off.eligible end
  if not off.hidden then
    local top, tied = topOf(off)
    if #tied == 1 then result.winner = tied[1]
    elseif #tied > 1 then result.tie = tied end
    result.top = top > 0 and top or nil
  end
  return result
end

-- The officer is done with a row's roll-off (the item went another way): it stops reading rolls and
-- the next call may start. Its result stays readable until the loot window closes.
function Rolls.End(slot, item)
  local off = offs[keyOf(slot, item)]
  if off then off.over = true end
end

local function handleRoll(text)
  if issecretvalue and issecretvalue(text) then
    -- A hidden system message may be a roll: the officer has to read it in the chat window.
    if current and not current.over then current.hidden = true end
    return
  end
  if type(text) ~= "string" then return end
  local name, roll, low, high = text:match("^(.-) rolls (%d+) %((%d+)%-(%d+)%)$")
  if not name then return end
  roll = tonumber(roll)
  local off = current
  if not off or off.over then
    early[#early + 1] = { name = name, roll = roll }
    if #early > EARLY_LIMIT then table.remove(early, 1) end
    return
  end
  local reason
  if tonumber(low) ~= 1 or tonumber(high) ~= 100 then
    reason = REASON_RANGE
  elseif off.eligible and not contains(off.eligible, name) then
    reason = off.tiedOnly and REASON_NOT_TIED or REASON_NOT_ELIGIBLE
  else
    for _, r in ipairs(off.counted) do
      if bare(r.name) == bare(name) then reason = REASON_SECOND end
    end
  end
  if reason then
    off.ignored[#off.ignored + 1] = { name = name, roll = roll, reason = reason }
  else
    off.counted[#off.counted + 1] = { name = name, roll = roll }
  end
end

ns.On("CHAT_MSG_SYSTEM", handleRoll)

-- A hand-out the game confirmed, or gave up on, ends the roll-off for that slot: later rolls are
-- for the next one.
local function handedOut(attempt)
  if current and current.slot == attempt.slot then current.over = true end
end
ns.Tracking.On("confirmed", handedOut)
ns.Tracking.On("unconfirmed", handedOut)

ns.On("LOOT_CLOSED", function()
  offs, current, early = {}, nil, {}
end)
