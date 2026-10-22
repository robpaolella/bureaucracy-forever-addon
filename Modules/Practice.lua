-- PracticeReserves: the made-up reserves of practice mode (#107). Pure: the group's names and a
-- drop number in, one drop's made-up reserves out, no game calls. Over a run of drops it cycles
-- through every reserve case, using only people in the group, so officers can rehearse them in a
-- dungeon. The holders get user ids that can't match a real guild user.
local _, ns = ...

local Practice = {}
ns.PracticeReserves = Practice

Practice.USER_PREFIX = "practice-"

local function holder(name, kind)
  return { user = Practice.USER_PREFIX .. name:lower(), char = name, kind = kind, trial = false }
end

local function without(names, skip)
  local list = {}
  for _, name in ipairs(names) do
    if name ~= skip then list[#list + 1] = name end
  end
  return list
end

-- The cases in the order they come. Each: its name, the fewest members it needs, and a builder
-- from the members (rotated, so the holders vary) to { holders, absent, cannotReceive, copies }.
local CASES = {
  { name = "hr-single", needs = 1, build = function(m)
    return { holders = { holder(m[1], "HR") } }
  end },
  { name = "hr-multi", needs = 3, build = function(m)
    return { holders = { holder(m[1], "HR"), holder(m[2], "HR"), holder(m[3], "HR") } }
  end },
  { name = "sr", needs = 1, build = function(m)
    local holders = { holder(m[1], "SR") }
    if m[2] then holders[2] = holder(m[2], "SR") end
    return { holders = holders }
  end },
  -- Two hard reserve holders the rules skip (one not in the raid, one who can't receive it), and
  -- a soft reserve holder who gets it when there is a third member.
  { name = "skipped", needs = 2, build = function(m)
    local holders = { holder(m[1], "HR"), holder(m[2], "HR") }
    if m[3] then holders[3] = holder(m[3], "SR") end
    return { holders = holders, absent = m[1], cannotReceive = m[2] }
  end },
  { name = "copies", needs = 2, build = function(m)
    return { holders = { holder(m[1], "HR"), holder(m[2], "HR") }, copies = 2 }
  end },
  { name = "open", needs = 0, build = function() return { holders = {} } end },
}
Practice.CASES = {}
for i, c in ipairs(CASES) do Practice.CASES[i] = c.name end

-- The made-up reserves for drop number `drop` (0, 1, 2, ...) among `members` (the group's names).
-- The case is drop's place in the cycle, or the next one the group is big enough for (the open
-- roll needs no one). Returns { case, holders (reserve holders in the snapshot's shape), roster
-- (the names the rules check holders against: leaves the absent holder out), candidates (the names
-- the game would let receive it: leaves the can't-receive holder out), copies (2 for the several
-- copies case, else nil) }.
function Practice.Generate(members, drop)
  local count = #members
  local start = (drop or 0) % #CASES
  for step = 0, #CASES - 1 do
    local case = CASES[(start + step) % #CASES + 1]
    if count >= case.needs then
      local rotated = {}
      for i = 1, count do rotated[i] = members[(drop + i - 1) % count + 1] end
      local made = case.build(rotated)
      return { case = case.name, holders = made.holders, copies = made.copies,
        roster = without(members, made.absent), candidates = without(members, made.cannotReceive) }
    end
  end
end

-- TestDrop (#108): the footer's Test drop button. It opens the pop-up on a made-up loot window with
-- no corpse: one fake item (two copies in the copies case), reserves from PracticeReserves, taking
-- the next case in the cycle each click. The window stands in for the game's through ns.LootWindow, so
-- nothing is handed out for real: a hand-out "succeeds" after a moment, as the game's own signs would
-- (but see give for the one case that fails).
-- Its awards are practice awards with no raid, whatever the raid selection, and are never sent.
local TestDrop = {}
ns.TestDrop = TestDrop

TestDrop.ITEM = 9999999
TestDrop.LINK = "|cffa335ee|Hitem:" .. TestDrop.ITEM .. "::::::::60:::::|h[Practice Blade]|h|r"
TestDrop.confirmAfter = 2 -- seconds until the made-up hand-out is confirmed
local SOURCE = "test-drop"
local ALREADY_OPEN = "Close the game's loot window first."

function TestDrop.IsOpen() return ns.LootWindow.fake ~= nil end

-- Closes the Test drop, if one is open, as the game closing its loot window.
function TestDrop.Close()
  if not ns.LootWindow.fake then return end
  ns.LootWindow.fake = nil
  ns.Fire("LOOT_CLOSED")
end

-- The made-up hand-out: the game's signs of a confirmed one, a moment later. The chat line comes even
-- if the pop-up was closed meanwhile, as the game's would.
-- In the skipped case (#127) the hand-out to the person first given the item never confirms: nothing
-- clears and no line comes, so after Tracking.confirmWait it is not confirmed, and Try again fails
-- again. A hand-out to anyone else confirms, so Give to someone else ends the failure.
local function give(window, slot, index)
  local winner = window.candidates(slot)[index]
  if window.failCase then
    window.failFor = window.failFor or winner
    if winner == window.failFor then return end
  end
  C_Timer.After(TestDrop.confirmAfter, function()
    if ns.LootWindow.fake == window then
      window.slots[slot] = {} -- the item leaves the window, as it does in the game
      ns.Fire("LOOT_SLOT_CLEARED", slot)
      ns.Fire("LOOT_SLOT_CLEARED", slot)
    end
    ns.Fire("CHAT_MSG_LOOT", winner .. " receives loot: " .. TestDrop.LINK .. ".")
    -- The game closes its loot window when the last item is gone.
    if ns.LootWindow.fake == window then
      for _, item in ipairs(window.slots) do
        if item.link then return end
      end
      TestDrop.Close()
    end
  end)
end

-- Opens a Test drop with the next made-up item, replacing one open. Returns true, or nil and why:
-- "not practice" (practice mode is off) or "window" (the game's own loot window is open).
function TestDrop.Open()
  if not ns.Practice() then return nil, "not practice" end
  if not ns.LootWindow.fake and ns.LootWindow.NumItems() > 0 then
    ns.Print(ALREADY_OPEN)
    return nil, "window"
  end
  TestDrop.Close()
  local made = ns.Popup.MadeUp(TestDrop.ITEM)
  local slots = {}
  for i = 1, made.copies or 1 do
    slots[i] = { link = TestDrop.LINK, quality = 4, guid = SOURCE }
  end
  local window = { slots = slots }
  window.failCase = made.case == "skipped"
  window.candidates = function() return made.candidates end
  window.give = function(slot, index) give(window, slot, index) end
  ns.LootWindow.fake, ns.LootWindow.opening = window, true
  local ok, err = pcall(ns.Fire, "LOOT_OPENED")
  ns.LootWindow.opening = nil
  if not ok then error(err, 0) end
  return true
end
