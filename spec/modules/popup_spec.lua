local wow = require("spec.support.wow")

local function link(id) return "|cffa335ee|Hitem:" .. id .. "::::::::60:::::|h[Item " .. id .. "]|h|r" end

local function holder(char, kind, fields)
  fields = fields or {}
  return { user = fields.user or char:lower():gsub("%s", ""), char = char, kind = kind,
    trial = fields.trial or false, blocked = fields.blocked }
end

local function names(prefix, count)
  local list = {}
  for i = 1, count do list[i] = prefix .. " " .. string.char(64 + i) end
  return list
end

local function tree(fields)
  local t = {
    formatVersion = 1, raid = "raid00001", code = "MC0001", env = "staging", name = "Molten Core",
    startsAt = 1792000000, durationMin = 240, generated = 1791990000,
    addon = { version = "0.1.0", url = "https://example.invalid/addon" },
    bosses = {
      { id = "luc", name = "Lucifron", trash = false, items = { 1, 2, 3, 4, 6 } },
      { id = "mag", name = "Magmadar", trash = false, items = { 6 } },
      { id = "tra", name = "Trash", trash = true, items = {} },
    },
    reserves = {}, awards = {},
  }
  for k, v in pairs(fields or {}) do t[k] = v end
  return t
end

describe("Popup", function()
  local ns

  -- Starts as the loot master in a raid of the given names, with a raid loaded and selected.
  local function setup(fields, group)
    ns = wow.start()
    wow.state.group = group or { "Masterlooter", "Ashla Brightwater", "Doran Vale", "Bram Ironvein",
      "Mirel Stone", "Tovin Hale" }
    wow.state.groupIsRaid = true
    _G.C_PartyInfo = { GetLootMethod = function() return "master", 0, 0 end }
    if fields then
      ns.Raids.Load(assert(ns.Snapshot.Validate(tree(fields), "0.1.0")), "pasted")
      assert(ns.Selection.ChooseRaid("raid00001"))
    end
  end

  local function drop(items)
    for _, it in ipairs(items) do
      it.link = it.link or link(it.id)
      it.quality = it.quality or 4
      it.sourceGuid = it.sourceGuid or "corpse1"
      it.candidates = it.candidates or wow.state.group
    end
    wow.openLoot(items)
  end

  after_each(function() _G.C_PartyInfo = nil end)

  it("gives a model only to the loot master", function()
    setup({})
    drop({ { id = 1 } })
    assert.is_table(ns.Popup.Build())
    _G.C_PartyInfo = { GetLootMethod = function() return "master", 2, 0 end }
    assert.are.same({ nil, "not loot master" }, { ns.Popup.Build() })
    _G.C_PartyInfo = { GetLootMethod = function() return "group", 0, 0 end }
    assert.are.same({ nil, "not loot master" }, { ns.Popup.Build() })
    _G.C_PartyInfo = nil
    assert.are.same({ nil, "not loot master" }, { ns.Popup.Build() })
  end)

  it("finds the master looter in the raid roster by name", function()
    setup({})
    drop({ { id = 1 } })
    _G.C_PartyInfo = { GetLootMethod = function() return "master", 1, 1 end }
    assert.is_table(ns.Popup.Build())
    _G.C_PartyInfo = { GetLootMethod = function() return "master", 2, 3 end }
    assert.is_nil((ns.Popup.Build()))
  end)

  it("gives no model when the run is not a guild run, or nothing is at the threshold", function()
    setup({})
    drop({ { id = 1 }, { id = 2, quality = 1 } })
    assert.are.equal(1, ns.Popup.Build().count)
    wow.state.lootThreshold = 5
    assert.are.same({ nil, "no items" }, { ns.Popup.Build() })
    wow.state.lootThreshold = 2
    assert.is_true(ns.Selection.ChooseOff())
    assert.are.equal("off", ns.Selection.Status().activeBy)
    assert.are.same({ nil, "not a guild run" }, { ns.Popup.Build() })
  end)

  describe("rows", function()
    local function build(reserves, items, group)
      setup({ reserves = reserves }, group)
      drop(items)
      return ns.Popup.Build()
    end

    it("shows a single hard reserve with its give button (popup-typical)", function()
      local m = build({ [1] = { holder("Ashla Brightwater", "HR") },
        [2] = { holder("Doran Vale", "SR") } }, { { id = 1 }, { id = 2 }, { id = 3 } })
      local hr, sr, open = m.rows[1], m.rows[2], m.rows[3]
      assert.are.equal("Hard reserve", hr.label)
      assert.are.equal(1, hr.item)
      assert.are.equal("Ashla Brightwater", hr.text)
      assert.are.same({ "Give to Ashla Brightwater", "D/B: choose ▾" },
        { hr.buttons[1].text, hr.buttons[2].text })
      assert.are.equal("Soft reserve", sr.label)
      assert.are.equal("Give to Doran Vale", sr.buttons[1].text)
      assert.are.same({ "open", "Open roll", "Nobody reserved it · everyone can roll", "Call open roll" },
        { open.mode, open.label, open.text, open.buttons[1].text })
      assert.are.equal("Lucifron", m.boss.name)
      assert.are.equal("Loot · Lucifron", m.title)
      assert.is_true(m.boss.resolved)
      assert.is_true(hr.buttons[1].enabled and hr.buttons[2].enabled)
    end)

    it("makes several hard reserves a roll-off, and a hard reserve beats soft ones", function()
      local m = build({ [1] = { holder("Ashla Brightwater", "HR"), holder("Mirel Stone", "HR"),
        holder("Doran Vale", "SR") } }, { { id = 1 } })
      local row = m.rows[1]
      assert.are.equal("Hard reserve roll-off", row.label)
      assert.are.same({ "Ashla Brightwater", "Mirel Stone" }, row.contenders)
      assert.are.equal("Ashla Brightwater, Mirel Stone", row.text)
      assert.are.equal("Call roll (2)", row.buttons[1].text)
      assert.are.equal("roll", row.action)
    end)

    it("makes several soft reserves a roll-off", function()
      local row = build({ [1] = { holder("Ashla Brightwater", "SR"), holder("Mirel Stone", "SR") } },
        { { id = 1 } }).rows[1]
      assert.are.same({ "sr", "Soft reserve roll-off" }, { row.mode, row.label })
    end)

    it("skips a holder who is not in the raid, with the reason", function()
      local row = build({ [1] = { holder("Ashla Brightwater", "HR"), holder("Kessa Moorfield", "HR") } },
        { { id = 1 } }).rows[1]
      assert.are.equal("Hard reserve", row.label)
      assert.are.same({ { name = "Kessa Moorfield", reason = "not in raid" } }, row.skipped)
      assert.are.equal("Skipped: Kessa Moorfield (not in raid)", row.skippedText)
    end)

    it("skips a holder the game won't let receive the item", function()
      local row = build({ [1] = { holder("Ashla Brightwater", "SR"), holder("Doran Vale", "SR") } },
        { { id = 1, candidates = { "Masterlooter", "Ashla Brightwater" } } }).rows[1]
      assert.are.equal("Soft reserve", row.label)
      assert.are.equal("Skipped: Doran Vale (the game won't let them receive this item "
        .. "(usually: not nearby when the boss died))", row.skippedText)
    end)

    it("skips a trial and a holder who already received it", function()
      setup({ reserves = { [1] = { holder("Ashla Brightwater", "SR"),
          holder("Doran Vale", "HR", { trial = true }), holder("Mirel Stone", "HR") } },
        awards = { { key = "k1", boss = "luc", item = 1, char = "Mirel Stone", user = "mirelstone",
          method = "HR", voided = false } } })
      drop({ { id = 1 } })
      local row = ns.Popup.Build().rows[1]
      assert.are.equal("Ashla Brightwater", row.winner)
      assert.are.equal("Skipped: Doran Vale (trial: shown, doesn't roll); "
        .. "Mirel Stone (hard reserve already received)", row.skippedText)
    end)

    it("passes the site's own block reason on as given", function()
      local row = build({ [1] = { holder("Ashla Brightwater", "SR"),
        holder("Doran Vale", "HR", { blocked = "at the win limit" }) } }, { { id = 1 } }).rows[1]
      assert.are.equal("Skipped: Doran Vale (at the win limit)", row.skippedText)
    end)

    it("reads an open roll when everyone is skipped", function()
      local row = build({ [1] = { holder("Kessa Moorfield", "HR") } }, { { id = 1 } }).rows[1]
      assert.are.same({ "open", "No one else reserved it · everyone can roll" }, { row.mode, row.text })
      assert.are.equal("Skipped: Kessa Moorfield (not in raid)", row.skippedText)
    end)

    it("reads an item on no boss's table as an open roll off the loot list", function()
      local row = build({}, { { id = 99 } }).rows[1]
      assert.are.equal("Not on the raid's loot list · everyone can roll", row.text)
    end)

    it("resolves two copies in turn", function()
      local m = build({ [6] = { holder("Bram Ironvein", "HR"), holder("Mirel Stone", "SR"),
        holder("Tovin Hale", "SR") } }, { { id = 6 }, { id = 6 } })
      local one, two = m.rows[1], m.rows[2]
      assert.are.same({ "Copy 1 of 2", "Hard reserve", "Bram Ironvein" }, { one.copy, one.label, one.winner })
      assert.are.same({ "Copy 2 of 2", "Soft reserve roll-off" }, { two.copy, two.label })
      assert.are.same({ "Mirel Stone", "Tovin Hale" }, two.contenders)
      assert.are.equal("Mirel Stone, Tovin Hale · Copy 1 goes to the hard reserve", two.text)
      assert.are.same({}, two.skipped)
    end)

    it("gives two copies of a single reserve: the second is an open roll", function()
      local m = build({ [6] = { holder("Bram Ironvein", "HR") } }, { { id = 6 }, { id = 6 } })
      assert.are.equal("Bram Ironvein", m.rows[1].winner)
      assert.are.same({ "open", "Copy 1 goes to the hard reserve · everyone can roll" },
        { m.rows[2].mode, m.rows[2].text })
    end)

    it("holds a name that shows as Unknown for a re-check", function()
      local m = build({ [1] = { holder("Ashla Brightwater", "HR") } },
        { { id = 1, candidates = { "Masterlooter", "Unknown" } } })
      local row = m.rows[1]
      assert.is_true(m.recheck)
      assert.are.same({}, row.skipped)
      assert.is_truthy(row.unavailable:find("hasn't loaded yet", 1, true))
      assert.are.same({ "Give to Unknown", false }, { row.buttons[1].text, row.buttons[1].enabled })
    end)
  end)

  describe("the worst case", function()
    local function worst()
      local fixed = { "Ashla Brightwater", "Doran Vale", "Bram Ironvein", "Mirel Stone", "Tovin Hale" }
      local group = { "Masterlooter" }
      for _, n in ipairs(fixed) do group[#group + 1] = n end
      for _, n in ipairs(names("Raider", 34)) do group[#group + 1] = n end
      local hr, sr = {}, {}
      for _, n in ipairs(names("Raider", 5)) do hr[#hr + 1] = holder(n, "HR") end
      for i, n in ipairs(names("Raider", 8)) do sr[i] = holder(n, "SR") end
      -- Raiders A to E hold item 1 hard, A to H hold item 2 soft (A to E hold both).
      setup({ reserves = { [1] = hr, [2] = sr, [6] = { holder("Bram Ironvein", "HR"),
        holder("Mirel Stone", "SR"), holder("Tovin Hale", "SR") } } }, group)
      drop({ { id = 1 }, { id = 2 }, { id = 6 }, { id = 6 }, { id = 3 }, { id = 4 } })
      return ns.Popup.Build()
    end

    it("lists all six items whichever page of the loot window shows", function()
      local m = worst()
      assert.are.equal(6, m.count)
      assert.are.equal(6, #m.rows)
      assert.are.same({ 1, 2, 6, 6, 3, 4 }, (function()
        local ids = {}
        for i, r in ipairs(m.rows) do ids[i] = r.item end
        return ids
      end)())
      assert.are.equal("Hard reserve roll-off", m.rows[1].label)
      assert.are.equal(5, #m.rows[1].contenders)
      assert.are.equal("Soft reserve roll-off", m.rows[2].label)
      assert.are.equal(8, #m.rows[2].contenders)
      assert.are.equal("Copy 2 of 2", m.rows[4].copy)
      assert.are.equal("open", m.rows[5].mode)
    end)
  end)

  describe("the boss", function()
    local function corpse(guid)
      drop({ { id = 3, sourceGuid = guid }, { id = 6, sourceGuid = guid } })
      return ns.Popup.Build()
    end

    it("is the one the item's table gives, picked or not", function()
      setup({ bosses = { { id = "luc", name = "Lucifron", trash = false, items = { 3 } },
        { id = "tra", name = "Trash", trash = true, items = {} } } })
      drop({ { id = 3 } })
      local m = ns.Popup.Build()
      assert.is_true(m.boss.resolved)
      assert.is_nil(m.boss.notice)
      assert.are.equal("luc", m.boss.id)
    end)

    it("asks when the corpse isn't clearly one boss, and greys Give and D/B until picked", function()
      setup({ reserves = { [3] = { holder("Ashla Brightwater", "HR") } },
        bosses = { { id = "luc", name = "Lucifron", trash = false, items = { 3, 6 } },
          { id = "mag", name = "Magmadar", trash = false, items = { 3, 6 } },
          { id = "tra", name = "Trash", trash = true, items = {} } } })
      -- Two kills at the same moment: the corpse can't be told apart.
      ns.db.attribution = { raid00001 = { kills = { luc = 1792000000, mag = 1792000000 }, pulls = {},
        corpses = { other = 1792000100 } } }
      local m = corpse("other")
      assert.is_false(m.boss.resolved)
      assert.are.equal("Trash", m.boss.name)
      assert.are.equal("These items drop from more than one boss. Pick the boss before awarding.",
        m.boss.notice)
      assert.are.equal("Which boss dropped this?", m.boss.menuTitle)
      assert.are.equal("Loot · Trash", m.title)
      local killed = date("%H:%M", 1792000000)
      assert.are.same({ { id = "luc", name = "Lucifron", selected = false, killed = killed },
        { id = "mag", name = "Magmadar", selected = false, killed = killed },
        { id = "tra", name = "Trash", selected = true } }, m.boss.menu)
      local give = m.rows[1].buttons
      assert.are.same({ "Give to Ashla Brightwater", false, "D/B: choose ▾", false },
        { give[1].text, give[1].enabled, give[2].text, give[2].enabled })
      assert.is_true(m.rows[2].buttons[1].enabled) -- calling a roll needs no boss
    end)

    it("enables them once a boss is picked, Trash too, and forgets it with the loot window", function()
      setup({ reserves = { [3] = { holder("Ashla Brightwater", "HR") } },
        bosses = { { id = "luc", name = "Lucifron", trash = false, items = { 3 } },
          { id = "mag", name = "Magmadar", trash = false, items = { 3 } },
          { id = "tra", name = "Trash", trash = true, items = {} } } })
      drop({ { id = 3, sourceGuid = "x" } })
      assert.is_false(ns.Popup.Build().boss.resolved)
      assert.is_true(ns.Popup.PickBoss("tra"))
      local m = ns.Popup.Build()
      assert.are.same({ true, "tra", "Trash", true }, { m.boss.resolved, m.boss.id, m.boss.name,
        m.rows[1].buttons[1].enabled })
      assert.is_nil(m.boss.notice)
      assert.is_true(ns.Popup.PickBoss("mag"))
      assert.are.equal("Loot · Magmadar", ns.Popup.Build().title)
      assert.are.same({ nil, "not a boss of this raid" }, { ns.Popup.PickBoss("nobody") })
      wow.closeLoot()
      drop({ { id = 3, sourceGuid = "x" } })
      assert.is_false(ns.Popup.Build().boss.resolved)
    end)
  end)

  describe("the foot line and no reserves", function()
    it("tells the raid, its date and when the text was copied and loaded", function()
      setup({})
      drop({ { id = 1 } })
      local m = ns.Popup.Build()
      local expected = "Reserves: Molten Core, " .. date("%a %d %b", 1792000000) .. " · copied "
        .. date("%H:%M", 1791990000) .. ", loaded " .. date("%H:%M", wow.state.time)
      assert.are.equal(expected, m.foot)
      assert.is_nil(m.notice)
    end)

    it("gives the no-reserves notice, a link to the Sync tab and open rolls with no snapshot", function()
      setup()
      drop({ { id = 1 }, { id = 2 } })
      local m = ns.Popup.Build()
      assert.are.equal("No reserves loaded, so every item is an open roll.", m.notice)
      assert.are.equal("Sync", m.syncLink)
      assert.are.equal("Reserves: none loaded", m.foot)
      for _, row in ipairs(m.rows) do
        assert.are.same({ "open", "No reserves loaded · everyone can roll", "Call open roll", true },
          { row.mode, row.text, row.buttons[1].text, row.buttons[1].enabled })
      end
    end)
  end)
end)
