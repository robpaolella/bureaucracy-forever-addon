local wow = require("spec.support.wow")

local function link(id) return "|cffa335ee|Hitem:" .. id .. "::::::::60:::::|h[Item " .. id .. "]|h|r" end

local function holder(char, kind)
  return { user = char:lower():gsub("%s", ""), char = char, kind = kind, trial = false }
end

local function tree(reserves)
  return {
    formatVersion = 1, raid = "raid00001", code = "MC0001", env = "staging", name = "Molten Core",
    startsAt = 1792000000, durationMin = 240, generated = 1791990000,
    addon = { version = "0.1.0", url = "https://example.invalid/addon" },
    bosses = { { id = "luc", name = "Lucifron", trash = false, items = { 1, 2, 3 } } },
    reserves = reserves, awards = {},
  }
end

describe("Rolls", function()
  local ns
  local GROUP = { "Masterlooter", "Ashla Brightwater", "Doran Vale", "Bram Ironvein", "Mirel Stone" }

  -- Item 1: hard reserved by two; item 2: soft reserved by two; item 3: nobody.
  local function setup(reserves, group)
    ns = wow.start()
    wow.state.group = group or GROUP
    wow.state.groupIsRaid = true
    wow.state.lootMethod = { "master", 0, 0 }
    ns.Raids.Load(assert(ns.Snapshot.Validate(tree(reserves or {
      [1] = { holder("Ashla Brightwater", "HR"), holder("Doran Vale", "HR") },
      [2] = { holder("Bram Ironvein", "SR"), holder("Mirel Stone", "SR") },
    }), "0.1.0")), "pasted")
    assert(ns.Selection.ChooseRaid("raid00001"))
    local items = {}
    for id = 1, 3 do
      items[id] = { id = id, link = link(id), quality = 4, sourceGuid = "corpse1",
        candidates = group or GROUP }
    end
    wow.openLoot(items)
    assert(ns.Popup.PickBoss("luc"))
  end

  local function call(slot)
    local result, why
    wow.click(function() result, why = ns.Rolls.Start(slot, slot) end)
    return result, why
  end

  local function roll(name, n, range)
    wow.fire("CHAT_MSG_SYSTEM", name .. " rolls " .. n .. " " .. (range or "(1-100)"))
  end

  local function reasons(result)
    local list = {}
    for _, e in ipairs(result.ignored) do list[#list + 1] = e.name .. ":" .. e.reason end
    return list
  end

  describe("the call", function()
    it("posts a raid warning for a hard reserve with leader rights (design Q7)", function()
      setup()
      wow.state.leader = true
      assert.is_truthy(call(1))
      local text = "Roll for " .. link(1) .. ": Ashla Brightwater and Doran Vale (hard reserve)"
      assert.are.same({ { text = text, channel = "RAID_WARNING" } }, wow.sent)
    end)

    it("posts a raid warning with assistant rights, and the soft reserve wording", function()
      setup()
      wow.state.assistant = true
      assert.is_truthy(call(2))
      assert.are.equal("Roll for " .. link(2) .. ": Bram Ironvein and Mirel Stone (soft reserve)",
        wow.sent[1].text)
      assert.are.equal("RAID_WARNING", wow.sent[1].channel)
    end)

    it("falls back to raid chat without rights", function()
      setup()
      assert.is_truthy(call(1))
      assert.are.equal("RAID", wow.sent[1].channel)
    end)

    it("calls an open roll", function()
      setup()
      assert.is_truthy(call(3))
      assert.are.equal("Open roll for " .. link(3) .. ": everyone /roll", wow.sent[1].text)
    end)

    it("starts with [Practice] when the practice hook says so", function()
      setup()
      ns.Rolls.IsPractice = function() return true end
      assert.is_truthy(call(3))
      assert.are.equal("[Practice] Open roll for " .. link(3) .. ": everyone /roll", wow.sent[1].text)
    end)

    it("lists the names that fit, then 'and N more', on one line within 255 bytes", function()
      local names, group, holders = {}, { "Masterlooter" }, {}
      for i = 1, 14 do
        names[i] = "Longnamedplayer" .. string.char(64 + i) .. " Surname"
        group[#group + 1] = names[i]
        holders[i] = holder(names[i], "HR")
      end
      setup({ [1] = holders }, group)
      local result = call(1)
      local line = wow.sent[1].text
      assert.is_true(#line <= 255)
      assert.is_nil(line:find("\n"))
      assert.is_truthy(line:find(" and %d+ more %(hard reserve%)$"))
      assert.is_truthy(line:find(names[1], 1, true))
      assert.are.equal(14, result.total) -- the roll-off still waits for all of them
    end)

    it("posts nothing while the fight lock is on", function()
      setup()
      wow.bossFight(true)
      local result, why = call(1)
      assert.is_nil(result)
      assert.are.equal("fight", why)
      assert.are.same({}, wow.sent)
      assert.is_nil(ns.Rolls.Result(1, 1))
    end)

    it("refuses a row that is not a roll, or changed", function()
      setup({})
      assert.are.equal("not ready", select(2, call(9)))
      local _, why = ns.Rolls.Start(1, 99)
      assert.are.equal("changed", why)
    end)

    it("refuses a row that is not a roll", function()
      setup({ [1] = { holder("Ashla Brightwater", "HR") } })
      assert.are.equal("not a roll", select(2, call(1)))
    end)
  end)

  describe("reading rolls", function()
    it("counts eligible rolls, shows waiting, and pre-selects the highest", function()
      setup()
      call(1)
      local r = ns.Rolls.Result(1, 1)
      assert.are.same({ { name = "Ashla Brightwater" }, { name = "Doran Vale" } }, r.entries)
      assert.are.equal(0, r.rolled)
      assert.are.equal(2, r.total)
      roll("Doran Vale", 40)
      r = ns.Rolls.Result(1, 1)
      assert.are.equal(1, r.rolled)
      assert.are.same({ { name = "Ashla Brightwater" }, { name = "Doran Vale", roll = 40 } }, r.entries)
      assert.are.equal("Doran Vale", r.winner)
      roll("Ashla Brightwater", 77)
      r = ns.Rolls.Result(1, 1)
      assert.are.equal(2, r.rolled)
      assert.are.equal("Ashla Brightwater", r.winner)
      assert.is_nil(r.tie)
      assert.is_false(r.hidden)
    end)

    it("lists a roll from someone not eligible with its reason", function()
      setup()
      call(1)
      roll("Mirel Stone", 99)
      local r = ns.Rolls.Result(1, 1)
      assert.are.same({ "Mirel Stone:not eligible" }, reasons(r))
      assert.is_nil(r.winner)
      assert.are.equal(0, r.rolled)
    end)

    it("counts the first of two rolls by one player", function()
      setup()
      call(1)
      roll("Doran Vale", 30)
      roll("Doran Vale", 95)
      local r = ns.Rolls.Result(1, 1)
      assert.are.same({ "Doran Vale:second roll, the first counts" }, reasons(r))
      assert.are.equal(30, r.entries[2].roll)
      assert.are.equal(1, r.rolled)
    end)

    it("ignores a roll typed before the call, and lists it", function()
      setup()
      roll("Doran Vale", 99)
      call(1)
      local r = ns.Rolls.Result(1, 1)
      assert.are.same({ "Doran Vale:rolled before the call" }, reasons(r))
      assert.are.equal(0, r.rolled)
      roll("Doran Vale", 10)
      assert.are.equal("Doran Vale", ns.Rolls.Result(1, 1).winner)
    end)

    it("ignores a roll that is not 1-100", function()
      setup()
      call(1)
      roll("Doran Vale", 500, "(1-1000)")
      roll("Ashla Brightwater", 3, "(5-100)")
      local r = ns.Rolls.Result(1, 1)
      assert.are.same({ "Doran Vale:not a 1-100 roll", "Ashla Brightwater:not a 1-100 roll" }, reasons(r))
      assert.are.equal(0, r.rolled)
    end)

    it("lets everyone count in an open roll", function()
      setup()
      call(3)
      roll("Mirel Stone", 12)
      roll("Masterlooter", 88)
      roll("Mirel Stone", 99)
      local r = ns.Rolls.Result(3, 3)
      assert.is_nil(r.total)
      assert.are.same({ { name = "Mirel Stone", roll = 12 }, { name = "Masterlooter", roll = 88 } },
        r.entries)
      assert.are.equal("Masterlooter", r.winner)
      assert.are.same({ "Mirel Stone:second roll, the first counts" }, reasons(r))
    end)

    it("matches a roll from a player with a realm in the name", function()
      setup()
      call(1)
      roll("Doran Vale-Realm", 50)
      assert.are.equal(1, ns.Rolls.Result(1, 1).rolled)
    end)

    it("ignores other system messages", function()
      setup()
      call(1)
      wow.fire("CHAT_MSG_SYSTEM", "Doran Vale has joined the raid group.")
      assert.are.equal(0, ns.Rolls.Result(1, 1).rolled)
      assert.are.same({}, ns.Rolls.Result(1, 1).ignored)
    end)

    it("stops reading once the game confirms the hand-out", function()
      setup()
      call(1)
      roll("Doran Vale", 50)
      ns.Tracking.Give(1, 3)
      wow.fire("LOOT_SLOT_CLEARED", 1)
      wow.fire("CHAT_MSG_LOOT", "Doran Vale receives loot: " .. link(1) .. ".")
      roll("Ashla Brightwater", 90)
      local r = ns.Rolls.Result(1, 1)
      assert.are.equal("Doran Vale", r.winner)
      assert.are.equal(1, r.rolled)
    end)

    it("clears with the loot window", function()
      setup()
      call(1)
      wow.fire("LOOT_CLOSED")
      assert.is_nil(ns.Rolls.Result(1, 1))
    end)
  end)

  describe("ties", function()
    it("flags a tie and re-rolls with only the tied players' new rolls counting", function()
      setup({ [1] = { holder("Ashla Brightwater", "HR"), holder("Doran Vale", "HR"),
        holder("Bram Ironvein", "HR") } })
      call(1)
      roll("Ashla Brightwater", 60)
      roll("Doran Vale", 60)
      roll("Bram Ironvein", 20)
      local r = ns.Rolls.Result(1, 1)
      assert.is_nil(r.winner)
      assert.are.same({ "Ashla Brightwater", "Doran Vale" }, r.tie)
      wow.sent = {}
      local result
      wow.click(function() result = ns.Rolls.Reroll(1, 1) end)
      assert.are.equal("Tie for " .. link(1) .. ": Ashla Brightwater and Doran Vale, roll again",
        wow.sent[1].text)
      assert.are.equal("RAID", wow.sent[1].channel)
      assert.are.equal(2, result.round)
      assert.are.equal(0, result.rolled)
      roll("Bram Ironvein", 99)
      roll("Doran Vale", 10)
      roll("Ashla Brightwater", 11)
      r = ns.Rolls.Result(1, 1)
      assert.are.same({ "Bram Ironvein:not in the tie" }, reasons(r))
      assert.are.equal("Ashla Brightwater", r.winner)
      assert.is_nil(r.tie)
    end)

    it("refuses a re-roll with no tie, no roll-off or a fight on", function()
      setup()
      assert.are.equal("no roll-off", select(2, ns.Rolls.Reroll(1, 1)))
      call(1)
      roll("Doran Vale", 10)
      assert.are.equal("no tie", select(2, ns.Rolls.Reroll(1, 1)))
      roll("Ashla Brightwater", 10)
      wow.bossFight(true)
      wow.sent = {}
      assert.are.equal("fight", select(2, ns.Rolls.Reroll(1, 1)))
      assert.are.same({}, wow.sent)
    end)
  end)

  describe("hidden rolls", function()
    it("marks the roll-off hidden, lists the eligible names and pre-selects nobody", function()
      setup()
      call(1)
      roll("Doran Vale", 50)
      wow.fire("CHAT_MSG_SYSTEM", wow.secret)
      local r = ns.Rolls.Result(1, 1)
      assert.is_true(r.hidden)
      assert.is_nil(r.winner)
      assert.is_nil(r.tie)
      assert.are.same({ "Ashla Brightwater", "Doran Vale" }, { r.entries[1].name, r.entries[2].name })
    end)

    it("lists the group for a hidden open roll", function()
      setup()
      call(3)
      wow.fire("CHAT_MSG_SYSTEM", wow.secret)
      local r = ns.Rolls.Result(3, 3)
      assert.is_true(r.hidden)
      assert.are.equal(#GROUP, #r.entries)
    end)

    it("does nothing for a hidden message with no roll-off", function()
      setup()
      wow.fire("CHAT_MSG_SYSTEM", wow.secret)
      assert.is_nil(ns.Rolls.Result(1, 1))
    end)
  end)
end)
