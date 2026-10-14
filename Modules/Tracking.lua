-- Tracking: master loot hand-outs, followed until the game confirms them (#8).
-- A failed hand-out reports no error. Success shows only as LOOT_SLOT_CLEARED (fires twice)
-- and the chat line "X receives loot: [item]" (with "x2" for stacks), so each attempt waits for
-- both, and reports "unconfirmed" if they don't both come in time (beta results: #3).
local _, ns = ...

local Tracking = {}
ns.Tracking = Tracking

-- Seconds to wait for the game's confirmation. One setting, easy to tune after live tests.
Tracking.confirmWait = 5

local listeners = {}
local attempts = {}   -- every attempt, oldest first
local snapshot = {}   -- the open loot window's slots: { key, link, quality, quantity, cleared }
local orphanClears = {} -- cleared slots nobody started an attempt for
local orphanChats = {}  -- "receives loot" lines no attempt claimed

-- Tracking.On(name, fn) hears: "confirmed", "unconfirmed", "late" (a confirmation that came
-- after "unconfirmed", with both signs; attempt.superseded is true if the item was handed out
-- again meanwhile)
-- and "outside" (a hand-out nobody started here, at or above the loot threshold). Each gets
-- one table: an attempt, or { winner, link, quantity, quality } for "outside".
function Tracking.On(name, fn)
  listeners[name] = listeners[name] or {}
  table.insert(listeners[name], fn)
end

local function report(name, info)
  for _, fn in ipairs(listeners[name] or {}) do fn(info) end
end

-- Items compare by id; plain "[Name]" links (and the stand-in's) compare by their text.
local function itemKey(link)
  return link and (link:match("item:(%d+)") or link:match("%[(.-)%]") or link)
end

local function shortName(name)
  return name and name:match("^[^-]+")
end

-- "Name receives loot: [item]x2." -> "Name", link, 2
local function parseLootLine(text)
  local who, rest = text:match("^(.-) receives? loot: (.+)$")
  if not who then return end
  local link = rest:match("(|c.-|r)") or rest:match("(%[.-%])")
  if not link then return end
  if who == "You" then who = UnitName("player") end
  return shortName(who), link, tonumber(rest:match("[%]r]x(%d+)%.?$")) or 1
end

local function prune()
  local limit = GetTime() - Tracking.confirmWait
  for _, list in ipairs({ orphanClears, orphanChats }) do
    for i = #list, 1, -1 do
      if list[i].at < limit then table.remove(list, i) end
    end
  end
end

local function checkConfirmed(attempt)
  -- With the loot window gone there is no slot clear to see, so the chat line alone counts.
  if not (attempt.chat and (attempt.cleared or attempt.windowClosed)) then return end
  if attempt.status == "pending" then
    attempt.status = "confirmed"
    report("confirmed", attempt)
  elseif attempt.status == "unconfirmed" then
    attempt.status = "late"
    report("late", attempt)
  end
end

-- Starts following the hand-out of the item in `slot` to `winner`. Returns the attempt, or
-- nil and why it can't be handed out: "unknown" (a new member the game can't name yet; try
-- again shortly), "grey" (grey items can't go to others) or "empty" (nothing in that slot).
function Tracking.Track(slot, winner)
  local item = snapshot[slot]
  if not item or item.cleared then return nil, "empty" end
  winner = shortName(winner)
  if not winner or winner == "Unknown" then return nil, "unknown" end
  if item.quality == 0 and winner ~= UnitName("player") then return nil, "grey" end
  for _, old in ipairs(attempts) do
    if old.slot == slot and old.status == "unconfirmed" then old.superseded = true end
  end
  local attempt = {
    slot = slot, winner = winner, link = item.link, key = item.key,
    quantity = item.quantity, status = "pending", startedAt = GetTime(),
  }
  table.insert(attempts, attempt)
  C_Timer.After(Tracking.confirmWait, function()
    if attempt.status == "pending" then
      attempt.status = "unconfirmed"
      report("unconfirmed", attempt)
    end
  end)
  return attempt
end

-- Hands the slot's item to the candidate at `index` and follows it. Same results as Track.
function Tracking.Give(slot, index)
  local attempt, reason = Tracking.Track(slot, GetMasterLootCandidate(slot, index))
  if attempt then GiveMasterLoot(slot, index) end
  return attempt, reason
end

-- Attempts still waiting, and those given up on but still open to a late confirmation. One a
-- newer hand-out from the same slot replaced is left out: the newer one counts on its own.
function Tracking.Pending()
  local list = {}
  for _, a in ipairs(attempts) do
    if a.status == "pending" or (a.status == "unconfirmed" and not a.superseded) then
      list[#list + 1] = a
    end
  end
  return list
end

local function takeOrphan(list, matches)
  for i, entry in ipairs(list) do
    if matches(entry) then return table.remove(list, i) end
  end
end

local function reportOutside(clear, winner)
  if clear.quality >= GetLootThreshold() then
    report("outside", {
      winner = winner, link = clear.link, quantity = clear.quantity, quality = clear.quality,
    })
  end
end

ns.On("LOOT_OPENED", function()
  snapshot = {}
  for slot = 1, GetNumLootItems() do
    local _, _, quantity, _, quality = GetLootSlotInfo(slot)
    local link = GetLootSlotLink(slot)
    snapshot[slot] = {
      link = link, key = itemKey(link), quality = quality or 0, quantity = quantity or 1,
    }
  end
  -- The same corpse can list its items in another order: follow each waiting attempt by item.
  local claimed = {}
  for _, a in ipairs(attempts) do
    if a.status == "pending" and not a.windowClosed then
      local slot = a.slot
      if not (snapshot[slot] and snapshot[slot].key == a.key and not claimed[slot]) then
        slot = nil
        for i, item in ipairs(snapshot) do
          if item.key == a.key and not claimed[i] then slot = i break end
        end
      end
      if slot then
        claimed[slot] = true
        a.slot = slot
      else
        a.windowClosed = true
        checkConfirmed(a)
      end
    end
  end
end)

ns.On("LOOT_CLOSED", function()
  for _, a in ipairs(attempts) do
    if a.status == "pending" then
      a.windowClosed = true
      checkConfirmed(a)
    end
  end
  snapshot = {}
end)

ns.On("LOOT_SLOT_CLEARED", function(slot)
  local item = snapshot[slot]
  if not item or item.cleared then return end -- the game fires it twice: count it once
  item.cleared = true
  -- A clear belongs to the newest waiting attempt for the slot, else to one given up on.
  for _, status in ipairs({ "pending", "unconfirmed" }) do
    for i = #attempts, 1, -1 do
      local a = attempts[i]
      if a.status == status and a.slot == slot and not a.windowClosed and not a.cleared then
        a.cleared = true
        checkConfirmed(a)
        return
      end
    end
  end
  prune()
  local chat = takeOrphan(orphanChats, function(c)
    return c.key == item.key and c.quantity == item.quantity
  end)
  if chat then
    reportOutside(item, chat.winner)
  else
    table.insert(orphanClears, {
      key = item.key, link = item.link, quality = item.quality, quantity = item.quantity, at = GetTime(),
    })
  end
end)

ns.On("CHAT_MSG_LOOT", function(text)
  local winner, link, quantity = parseLootLine(text)
  if not winner then return end
  local key = itemKey(link)
  prune()
  -- Waiting attempts first, then ones given up on (a late confirmation). Among identical
  -- copies the one whose slot has cleared goes first.
  for _, status in ipairs({ "pending", "unconfirmed" }) do
    local match
    for _, a in ipairs(attempts) do
      if a.status == status and not a.chat and a.winner == winner and a.key == key
        and a.quantity == quantity and (not match or (a.cleared and not match.cleared)) then
        match = a
      end
    end
    if match then
      match.chat = true
      checkConfirmed(match)
      return
    end
  end
  local clear = takeOrphan(orphanClears, function(c)
    return c.key == key and c.quantity == quantity
  end)
  if clear then
    reportOutside(clear, winner)
  else
    table.insert(orphanChats, { winner = winner, key = key, quantity = quantity, at = GetTime() })
  end
end)
