-- Rules: who should get each drop, from the loaded reserves and the raid's awards (#5).
-- Pure: plain tables in the spec's shapes in, no game calls. Mirrors the site's resolveDrop:
-- hard reserves (HR) first, then soft reserves (SR), then an open roll.
local _, ns = ...

local Rules = {}
ns.Rules = Rules

-- Why a holder is skipped; a `blocked` code from the snapshot is passed on as given.
Rules.NOT_IN_RAID = "not in raid"
Rules.CANNOT_RECEIVE = "cannot receive"
Rules.TRIAL = "trial"
Rules.RECEIVED = "already received"

-- "Bob-Realm" and "Bob" are the same character.
local function bare(name)
  return (name:gsub("%-.*$", ""))
end
Rules.Bare = bare

local function nameSet(list)
  if not list then return nil end
  local set = {}
  for _, name in ipairs(list) do set[bare(name)] = true end
  return set
end

-- The users who hold this item, counting each award key once and not counting voids. A key
-- seen voided anywhere stays voided (a void always wins, spec 4.2).
local function receivers(awards, item)
  local byKey, users = {}, {}
  for _, a in ipairs(awards or {}) do
    if a.item == item and a.user then
      if a.key == nil then
        if not a.voided then users[#users + 1] = a.user end
      elseif byKey[a.key] == nil then
        byKey[a.key] = { user = a.user, voided = a.voided and true or false }
      elseif a.voided then
        byKey[a.key].voided = true
      end
    end
  end
  local set = {}
  for _, u in ipairs(users) do set[u] = true end
  for _, a in pairs(byKey) do
    if not a.voided then set[a.user] = true end
  end
  return set
end

-- args: item (id), reserves (snapshot's, per item id), awards (baseline and the add-on's,
-- merged), roster and candidates (lists of names; nil skips that check).
-- Returns { mode, contenders, skipped }. mode is "hr-single" (one HR holder, no roll),
-- "hr-multi", "sr" or "open". Each skipped entry is a holder plus its `reason`.
-- For several copies, add each award as it is made and resolve again.
function Rules.Resolve(args)
  local item = args.item
  local reserves = args.reserves or {}
  local holders = reserves[item] or reserves[tostring(item)] or {}
  local received = receivers(args.awards, item)
  local inRaid, canReceive = nameSet(args.roster), nameSet(args.candidates)

  local live = { HR = {}, SR = {} }
  local skipped = {}
  for _, h in ipairs(holders) do
    local reason
    if h.trial then
      reason = Rules.TRIAL
    elseif received[h.user] then
      reason = Rules.RECEIVED
    elseif h.blocked then
      reason = h.blocked
    elseif inRaid and not inRaid[bare(h.char)] then
      reason = Rules.NOT_IN_RAID
    elseif canReceive and not canReceive[bare(h.char)] then
      reason = Rules.CANNOT_RECEIVE
    end
    if reason then
      skipped[#skipped + 1] = { user = h.user, char = h.char, kind = h.kind, trial = h.trial,
        blocked = h.blocked, reason = reason }
    elseif live[h.kind] then
      table.insert(live[h.kind], h)
    end
  end

  if #live.HR > 0 then
    return { mode = #live.HR == 1 and "hr-single" or "hr-multi", contenders = live.HR, skipped = skipped }
  elseif #live.SR > 0 then
    return { mode = "sr", contenders = live.SR, skipped = skipped }
  end
  return { mode = "open", contenders = {}, skipped = skipped }
end
