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
