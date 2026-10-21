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
    wow.state.lootMethod = { "master", 0, 0 }
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

  it("gives a model only to the loot master", function()
    setup({})
    drop({ { id = 1 } })
    assert.is_table(ns.Popup.Build())
    wow.state.lootMethod = { "master", 2, 0 }
    assert.are.same({ nil, "not loot master" }, { ns.Popup.Build() })
    wow.state.lootMethod = { "group", 0, 0 }
    assert.are.same({ nil, "not loot master" }, { ns.Popup.Build() })
  end)

  it("finds the master looter in the raid roster by name", function()
    setup({})
    drop({ { id = 1 } })
    wow.state.lootMethod = { "master", 1, 1 }
    assert.is_table(ns.Popup.Build())
    wow.state.lootMethod = { "master", 2, 3 }
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

  describe("giving (#38)", function()
    local BOSSES = {
      { id = "lb_lucifron", name = "Lucifron", trash = false, items = { 1, 2, 3 } },
      { id = "lb_trash", name = "Trash", trash = true, items = {} },
    }
    local ANNOUNCED = "Announced in raid chat. Waiting for the game to confirm (a few seconds)."

    -- A raid whose code and boss ids make a valid chat line, unless fields say otherwise.
    local function raid(fields)
      local t = { code = "SA0001", bosses = BOSSES, reserves = { [1] = { holder("Ashla Brightwater", "HR") },
        [2] = { holder("Doran Vale", "SR") } } }
      for k, v in pairs(fields or {}) do t[k] = v end
      setup(t)
    end

    -- Clicks the slot's Give button as it was drawn just now.
    local function give(slot)
      local shown
      for _, row in ipairs((ns.Popup.Build() or { rows = {} }).rows) do
        if row.slot == slot then shown = row end
      end
      local result
      wow.click(function() result = { ns.Popup.Give(slot, shown and shown.item, shown and shown.winner) } end)
      return result[1], result[2]
    end

    local function confirm(slot, who)
      wow.fire("LOOT_SLOT_CLEARED", slot)
      wow.fire("CHAT_MSG_LOOT", who .. " receives loot: " .. wow.state.loot[slot].link .. ".")
    end

    it("hands out to the winner's candidate slot by name, posts the line and records it", function()
      raid()
      drop({ { id = 1, candidates = { "Doran Vale", "Masterlooter", "Ashla Brightwater" } } })
      local attempt = assert(give(1))
      assert.are.same({ { slot = 1, candidate = 3 } }, wow.gives)
      local award = ns.Records.Get(attempt.awardKey)
      assert.are.same({ "announced", "lb_lucifron", 1, "Ashla Brightwater", "ashlabrightwater", "HR",
        "Masterlooter" }, { award.state, award.boss, award.item, award.char, award.user, award.method,
        award.sender })
      assert.are.same({ { channel = "RAID", text = link(1) .. " → Ashla Brightwater (hard reserve) "
        .. "<BF1;A;SA0001;" .. attempt.awardKey .. ";1;ifron;HR;;Ashla Brightwater>" } }, wow.sent)
      assert.are.same({}, wow.blocked)
      confirm(1, "Ashla Brightwater")
      assert.are.equal("confirmed", ns.Records.Get(attempt.awardKey).state)
    end)

    it("announces a soft reserve as one, in party chat outside a raid", function()
      raid()
      wow.state.groupIsRaid = false
      wow.state.group = { "Masterlooter", "Doran Vale" }
      drop({ { id = 2 } })
      local attempt = assert(give(1))
      assert.are.equal("PARTY", wow.sent[1].channel)
      assert.is_truthy(wow.sent[1].text:find("→ Doran Vale (soft reserve) <BF1;A;SA0001;", 1, true))
      assert.are.equal("SR", ns.Records.Get(attempt.awardKey).method)
    end)

    it("shows the row as handing out until the game confirms, and refuses a second click", function()
      raid()
      drop({ { id = 1 }, { id = 2 } })
      give(1)
      local row = ns.Popup.Build().rows[1]
      assert.are.same({ { text = "Handing out to Ashla Brightwater…", note = ANNOUNCED }, {} },
        { row.handout, row.buttons })
      -- Its own award, just saved, doesn't turn the row into "already received".
      assert.are.same({ "hr", "Ashla Brightwater" }, { row.mode, row.text })
      assert.is_nil(row.skippedText)
      assert.is_nil(ns.Popup.Build().rows[2].handout)
      assert.are.same({ nil, "not ready" }, { give(1) })
      assert.are.equal(1, #wow.gives)
      assert.are.equal(1, #wow.sent)
      confirm(1, "Ashla Brightwater")
      assert.is_nil(ns.Popup.Build().rows[1].handout)
    end)

    it("does nothing if the winner changed after the button was drawn", function()
      raid({ reserves = { [1] = { holder("Ashla Brightwater", "HR"), holder("Doran Vale", "SR") } } })
      drop({ { id = 1 } })
      local shown = ns.Popup.Build().rows[1]
      assert.are.equal("Ashla Brightwater", shown.winner)
      wow.state.loot[1].candidates = { "Masterlooter", "Doran Vale" } -- Ashla can't receive it now
      local result
      wow.click(function() result = { ns.Popup.Give(1, shown.item, shown.winner) } end)
      assert.are.same({ nil, "changed" }, result)
      assert.are.same({}, wow.gives)
      assert.are.same({}, wow.sent)
      assert.is_nil(ns.Records.Ops("raid00001")[1])
    end)

    it("records the award as not confirmed when the game doesn't confirm in time", function()
      raid()
      drop({ { id = 1 } })
      local attempt = give(1)
      wow.advance(ns.Tracking.confirmWait - 1)
      assert.are.equal("announced", ns.Records.Get(attempt.awardKey).state)
      wow.advance(1)
      assert.are.equal("not-confirmed", ns.Records.Get(attempt.awardKey).state)
      assert.are.same({ "award", "not-confirmed" }, { ns.Records.Ops("raid00001")[1].type,
        ns.Records.Ops("raid00001")[2].type })
      assert.are.equal(1, #wow.sent)
      assert.is_nil(ns.Popup.Build().rows[1].handout)
    end)

    it("hands out and saves even when the line can't be built, and says so", function()
      raid({ code = "MC0001" }) -- not a valid raid code for a chat line
      drop({ { id = 1 } })
      local attempt = assert(give(1))
      assert.are.equal(1, #wow.gives)
      assert.are.same({}, wow.sent)
      assert.is_nil(attempt.announced)
      assert.are.equal("announced", ns.Records.Get(attempt.awardKey).state)
      assert.is_truthy(wow.printed[#wow.printed]:find("its raid chat line couldn't be posted", 1, true))
      assert.is_truthy(ns.log[#ns.log].text:find("raid code", 1, true))
      assert.are.equal("Not announced in raid chat: the line couldn't be posted. Waiting for the game to"
        .. " confirm (a few seconds).", ns.Popup.Build().rows[1].handout.note)
      confirm(1, "Ashla Brightwater")
      assert.are.equal("confirmed", ns.Records.Get(attempt.awardKey).state)
    end)

    it("waits out a boss fight: no hand-out or chat, buttons greyed with why (popup-fight)", function()
      raid()
      drop({ { id = 1 }, { id = 3 } })
      wow.bossFight(true)
      local m = ns.Popup.Build()
      assert.are.equal("Boss fight in progress. The game locks chat for add-ons, so awards wait until"
        .. " it ends.", m.fight)
      for _, row in ipairs(m.rows) do
        assert.are.same({ false, "Chat is locked until the fight ends" },
          { row.buttons[1].enabled, row.buttons[1].tooltip })
        assert.are.same({ false, "Chat is locked until the fight ends" },
          { row.buttons[2].enabled, row.buttons[2].tooltip })
      end
      assert.are.same({ nil, "fight" }, { give(1) })
      assert.are.same({}, wow.gives)
      assert.are.same({}, wow.sent)
      assert.is_nil(ns.Records.Ops("raid00001")[1])
      wow.bossFight(false)
      m = ns.Popup.Build()
      assert.is_nil(m.fight)
      assert.is_true(m.rows[1].buttons[1].enabled and m.rows[2].buttons[1].enabled)
      assert.is_nil(m.rows[1].buttons[1].tooltip)
      assert.is_truthy(give(1))
    end)

    it("counts the Encounter limit or chat lockdown as a fight, not the Combat or Map limits", function()
      raid()
      wow.state.limits = { Combat = true, Map = true }
      assert.is_false(ns.Popup.ChatLocked())
      wow.state.limits = { Encounter = true }
      assert.is_true(ns.Popup.ChatLocked())
      wow.state.limits = {}
      wow.state.chatLockdown = true
      assert.is_true(ns.Popup.ChatLocked())
    end)

    it("can't give to a winner whose name hasn't loaded (popup-unavailable)", function()
      raid()
      drop({ { id = 1, candidates = { "Masterlooter", "Unknown" } } })
      assert.are.same({ nil, "not ready" }, { give(1) })
      assert.are.same({}, wow.gives)
      assert.are.same({}, wow.sent)
      assert.is_nil(ns.Records.Ops("raid00001")[1])
    end)

    it("gives nothing for a roll, an open roll or before the boss is picked", function()
      raid({ bosses = { { id = "lb_lucifron", name = "Lucifron", trash = false, items = { 2 } },
        { id = "lb_magmadar", name = "Magmadar", trash = false, items = { 2 } },
        { id = "lb_trash", name = "Trash", trash = true, items = {} } } })
      drop({ { id = 2 }, { id = 3 } })
      assert.are.same({ nil, "not ready" }, { give(1) }) -- no boss picked yet
      assert.are.same({ nil, "not ready" }, { give(2) }) -- an open roll
      assert.are.same({}, wow.gives)
    end)

    describe("disenchant/bank (#39)", function()
      -- Clicks the slot's D/B button as it was drawn just now.
      local function giveDB(slot)
        local shown
        for _, row in ipairs((ns.Popup.Build() or { rows = {} }).rows) do
          if row.slot == slot then shown = row end
        end
        local result
        local button = shown and shown.buttons[2]
        wow.click(function()
          result = { ns.Popup.GiveDB(slot, shown and shown.item, button and button.pick) }
        end)
        return result[1], result[2]
      end

      it("lists the raid's members by name, with no pick yet (popup-db)", function()
        raid()
        drop({ { id = 1 } })
        local m = ns.Popup.Build()
        assert.are.same({ title = "Disenchant/bank: give to", note = "Remembered for this raid.",
          members = {
            { name = "Ashla Brightwater", selected = false }, { name = "Bram Ironvein", selected = false },
            { name = "Doran Vale", selected = false }, { name = "Masterlooter", selected = false },
            { name = "Mirel Stone", selected = false }, { name = "Tovin Hale", selected = false },
          } }, m.dbMenu)
        local db = m.rows[1].buttons[2]
        assert.are.same({ "D/B: choose ▾", "db", true, "Disenchant/bank: choose the character to give to." },
          { db.text, db.action, db.enabled, db.tooltip })
        assert.is_nil(db.pick)
      end)

      it("no pick gives nothing", function()
        raid()
        drop({ { id = 1 } })
        assert.are.same({ nil, "no pick" }, { giveDB(1) })
        assert.are.same({}, wow.gives)
        assert.are.same({}, wow.sent)
        assert.is_nil(ns.Records.Ops("raid00001")[1])
      end)

      it("choosing a name remembers it for the raid, ticks it and gives nothing", function()
        raid()
        drop({ { id = 1 } })
        assert.is_true(ns.Popup.SetDBPick("Doran Vale"))
        assert.are.same({}, wow.gives)
        assert.are.same({}, wow.sent)
        assert.are.same({ raid00001 = "Doran Vale" }, ns.db.dbPick)
        local m = ns.Popup.Build()
        local ticked = {}
        for _, member in ipairs(m.dbMenu.members) do
          if member.selected then ticked[#ticked + 1] = member.name end
        end
        assert.are.same({ "Doran Vale" }, ticked)
        local db = m.rows[1].buttons[2]
        assert.are.same({ "D/B: Doran ▾", "Doran Vale", true }, { db.text, db.pick, db.enabled })
        assert.are.equal("Disenchant/bank: give to Doran Vale. Right-click or Shift-click to choose someone"
          .. " else.", db.tooltip)
        assert.are.same({ nil, "not in raid" }, { ns.Popup.SetDBPick("Nobody Here") })
        assert.are.same({ raid00001 = "Doran Vale" }, ns.db.dbPick)
      end)

      it("keeps a pick per raid, and reads an old single pick as none", function()
        raid()
        ns.db.dbPick = "Doran Vale" -- an older shape: nothing wrote it, so it counts as no pick
        assert.is_nil(ns.Popup.DBPick())
        assert.is_true(ns.Popup.SetDBPick("Doran Vale"))
        ns.Raids.Load(assert(ns.Snapshot.Validate(tree({ raid = "raid00002" }), "0.1.0")), "pasted")
        assert(ns.Selection.ChooseRaid("raid00002"))
        assert.is_nil(ns.Popup.DBPick())
        assert.is_true(ns.Popup.SetDBPick("Mirel Stone"))
        assert(ns.Selection.ChooseRaid("raid00001"))
        assert.are.equal("Doran Vale", ns.Popup.DBPick())
        assert.are.same({ raid00001 = "Doran Vale", raid00002 = "Mirel Stone" }, ns.db.dbPick)
      end)

      it("hands out to the pick by name, records Disenchant/bank with no winner, posts the line", function()
        raid()
        drop({ { id = 1, candidates = { "Doran Vale", "Masterlooter", "Bram Ironvein" } } })
        ns.Popup.SetDBPick("Bram Ironvein")
        local attempt = assert(giveDB(1))
        assert.are.same({ { slot = 1, candidate = 3 } }, wow.gives)
        local award = ns.Records.Get(attempt.awardKey)
        assert.are.same({ "announced", "lb_lucifron", 1, "DISENCHANT_BANK", "Masterlooter" },
          { award.state, award.boss, award.item, award.method, award.sender })
        assert.is_nil(award.char)
        assert.is_nil(award.user)
        assert.are.same({ { channel = "RAID", text = link(1) .. " → disenchant/bank "
          .. "<BF1;A;SA0001;" .. attempt.awardKey .. ";1;ifron;DISENCHANT_BANK;;>" } }, wow.sent)
        assert.is_falsy(wow.sent[1].text:find("Bram", 1, true))
        local row = ns.Popup.Build().rows[1]
        assert.are.same({ { text = "Handing out to Bram Ironvein…", note = ANNOUNCED }, {} },
          { row.handout, row.buttons })
        assert.are.same({ nil, "not ready" }, { giveDB(1) })
        confirm(1, "Bram Ironvein")
        assert.are.equal("confirmed", ns.Records.Get(attempt.awardKey).state)
      end)

      it("remembers the pick, so the next item is one click too", function()
        raid()
        drop({ { id = 1 }, { id = 3 } })
        ns.Popup.SetDBPick("Mirel Stone")
        assert(giveDB(1))
        assert(giveDB(2))
        assert.are.equal(2, #wow.gives)
        assert.are.equal(2, #wow.sent)
      end)

      it("ends the row's roll-off, so the next roll can be called", function()
        raid({ reserves = { [1] = { holder("Ashla Brightwater", "HR"), holder("Doran Vale", "HR") },
          [2] = { holder("Bram Ironvein", "HR"), holder("Mirel Stone", "HR") } } })
        drop({ { id = 1 }, { id = 2 } })
        wow.click(function() assert(ns.Rolls.Start(1, 1)) end)
        ns.Popup.SetDBPick("Tovin Hale")
        assert(giveDB(1))
        local result
        wow.click(function() result = ns.Rolls.Start(2, 2) end)
        assert.is_truthy(result)
      end)

      it("hands nothing out to a pick who isn't a candidate, and the row says why", function()
        raid()
        drop({ { id = 1, candidates = { "Masterlooter", "Ashla Brightwater" } } })
        ns.Popup.SetDBPick("Doran Vale")
        assert.are.same({ nil, "not a candidate" }, { giveDB(1) })
        assert.are.same({}, wow.gives)
        assert.are.same({}, wow.sent)
        assert.is_nil(ns.Records.Ops("raid00001")[1])
        assert.are.equal("The game won't let Doran Vale receive this item (usually: not nearby when the boss"
          .. " died). Right-click D/B to choose someone else.", ns.Popup.Build().rows[1].dbNote)
        -- Left the raid: the row says that instead.
        wow.state.group = { "Masterlooter", "Ashla Brightwater" }
        assert.are.same({ nil, "not a candidate" }, { giveDB(1) })
        assert.are.equal("Doran Vale isn't in the raid. Right-click D/B to choose someone else.",
          ns.Popup.Build().rows[1].dbNote)
        -- A new pick clears the note, and so does the loot window closing.
        ns.Popup.SetDBPick("Ashla Brightwater")
        assert.is_nil(ns.Popup.Build().rows[1].dbNote)
        ns.Popup.SetDBPick("Masterlooter")
        wow.state.loot[1].candidates = { "Ashla Brightwater" }
        giveDB(1)
        wow.closeLoot()
        drop({ { id = 1 } })
        assert.is_nil(ns.Popup.Build().rows[1].dbNote)
      end)

      it("is greyed in a boss fight, before the boss is picked and while handing out", function()
        raid({ bosses = { { id = "lb_lucifron", name = "Lucifron", trash = false, items = { 2 } },
          { id = "lb_magmadar", name = "Magmadar", trash = false, items = { 2 } },
          { id = "lb_trash", name = "Trash", trash = true, items = {} } } })
        ns.Popup.SetDBPick("Doran Vale")
        drop({ { id = 2 } })
        assert.is_false(ns.Popup.Build().rows[1].buttons[2].enabled)
        assert.are.same({ nil, "not ready" }, { giveDB(1) })
        ns.Popup.PickBoss("lb_trash")
        wow.bossFight(true)
        assert.are.same({ nil, "fight" }, { giveDB(1) })
        wow.bossFight(false)
        assert(giveDB(1))
        assert.are.same({}, ns.Popup.Build().rows[1].buttons)
        assert.are.equal(1, #wow.gives)
      end)

      it("does nothing if the pick changed after the button was drawn", function()
        raid()
        drop({ { id = 1 } })
        ns.Popup.SetDBPick("Doran Vale")
        local result
        wow.click(function() result = { ns.Popup.GiveDB(1, 1, "Mirel Stone") } end)
        assert.are.same({ nil, "changed" }, result)
        assert.are.same({}, wow.gives)
      end)

      it("hands out and saves even when the line can't be built, and says so", function()
        raid({ code = "MC0001" }) -- not a valid raid code for a chat line
        drop({ { id = 1 } })
        ns.Popup.SetDBPick("Doran Vale")
        local attempt = assert(giveDB(1))
        assert.are.equal(1, #wow.gives)
        assert.are.same({}, wow.sent)
        assert.is_nil(attempt.announced)
        assert.are.equal("DISENCHANT_BANK", ns.Records.Get(attempt.awardKey).method)
        assert.is_truthy(wow.printed[#wow.printed]:find("is being handed to Doran Vale to disenchant or"
          .. " bank, but its raid chat line couldn't be posted.", 1, true))
      end)

      it("with no raid loaded, keeps the pick only until the game closes", function()
        setup()
        drop({ { id = 1 } })
        assert.is_true(ns.Popup.SetDBPick("Doran Vale"))
        assert.is_nil(ns.db.dbPick)
        local m = ns.Popup.Build()
        assert.are.same({ "D/B: Doran ▾", "Remembered until you close the game." },
          { m.rows[1].buttons[2].text, m.dbMenu.note })
      end)
    end)

    describe("when the game doesn't confirm (#12)", function()
      local GROUP = { "Masterlooter", "Ashla Brightwater", "Doran Vale", "Bram Ironvein", "Tovin Hale" }

      -- Gives item 1 (Ashla's hard reserve) and lets the wait run out. Returns the award key.
      local function unconfirmed(fields, group)
        raid(fields)
        wow.state.group = group or wow.state.group
        drop({ { id = 1 } })
        local attempt = assert(give(1))
        wow.advance(ns.Tracking.confirmWait)
        wow.state.time = wow.state.time + 10
        assert.are.equal("not-confirmed", ns.Records.Get(attempt.awardKey).state)
        return attempt.awardKey
      end

      local function click(fn, ...)
        local args, result = { ... }, nil
        wow.click(function() result = { fn(unpack(args)) } end)
        return result[1], result[2]
      end

      -- What a refusal must leave as it was: hand-outs, chat lines and records.
      local function unchanged(key, gives)
        assert.are.equal(gives, #wow.gives)
        assert.are.equal(1, #wow.sent)
        assert.are.equal(2, #ns.Records.Ops("raid00001"))
        local award = ns.Records.Get(key)
        assert.are.same({ "not-confirmed", nil }, { award.state, award.voided })
      end

      describe("the not confirmed row (#95)", function()
        local RESERVES = { [1] = { holder("Ashla Brightwater", "HR"), holder("Doran Vale", "SR"),
          holder("Mirel Stone", "SR"), holder("Tovin Hale", "SR", { trial = true }) } }

        local function row1() return ns.Popup.Build().rows[1] end

        it("shows the three choices in place of the buttons, keeping the winner", function()
          local key = unconfirmed({ reserves = RESERVES }, GROUP)
          local row = row1()
          assert.are.same({ "Ashla Brightwater", "give", "Ashla Brightwater" },
            { row.winner, row.action, row.text })
          assert.are.same({}, row.buttons)
          assert.is_nil(row.handout)
          local nc = row.notConfirmed
          assert.are.equal(key, nc.key)
          assert.are.equal("The game didn't confirm that Ashla Brightwater got it. They may be too far away,"
            .. " or their bags are full.", nc.text)
          assert.are.equal("Try again posts nothing. Give to someone else posts one correction line, and"
            .. " Not handed out posts an undo line. If you close this, it waits in the Awards tab as"
            .. " \"not confirmed\".", nc.hint)
          assert.are.same({ { "Try again", "tryagain", true }, { "Give to someone else", "giveelse", true },
            { "Not handed out", "nothandedout", true } }, (function()
            local list = {}
            for i, b in ipairs(nc.buttons) do list[i] = { b.text, b.action, b.enabled } end
            return list
          end)())
        end)

        it("names who the hand-out went to for a Disenchant/bank award", function()
          raid()
          drop({ { id = 1 } })
          ns.Popup.SetDBPick("Bram Ironvein")
          wow.click(function() assert(ns.Popup.GiveDB(1, 1, "Bram Ironvein")) end)
          wow.advance(ns.Tracking.confirmWait)
          assert.is_truthy(row1().notConfirmed.text:find("confirm that Bram Ironvein got it", 1, true))
        end)

        it("lists the other contenders with their methods, greying one not in the raid", function()
          unconfirmed({ reserves = RESERVES }, GROUP)
          local list = row1().notConfirmed.list
          assert.are.equal("Give " .. link(1) .. " to someone else", list.title)
          assert.are.same({
            { "Doran Vale", "Soft reserve", true, true, nil },
            { "Mirel Stone", "Soft reserve", false, false, "not in raid" },
          }, (function()
            local out = {}
            for i, p in ipairs(list.people) do
              out[i] = { p.char, p.method, p.available, p.enabled, p.reason }
            end
            return out
          end)())
          assert.is_nil(list.empty)
          assert.are.equal("Posts one correction line: Correction: " .. link(1)
            .. " → their name, not Ashla Brightwater.", list.hint)
        end)

        it("says so when nobody else reserved it, and draws no open roll line", function()
          unconfirmed(nil, GROUP)
          local list = row1().notConfirmed.list
          assert.are.same({}, list.people)
          assert.are.equal("No one else reserved it.", list.empty)
        end)

        it("waits on the lines in a boss fight, but leaves Try again", function()
          unconfirmed({ reserves = RESERVES }, GROUP)
          wow.bossFight(true)
          local nc = row1().notConfirmed
          assert.are.same({ true, false, false }, { nc.buttons[1].enabled, nc.buttons[2].enabled,
            nc.buttons[3].enabled })
          assert.are.equal("Posts a line, so it waits until the boss fight ends", nc.buttons[2].tooltip)
          assert.is_nil(nc.buttons[1].tooltip)
          assert.are.same({ false, "Posts a line, so it waits until the boss fight ends" },
            { nc.list.people[1].enabled, nc.list.people[1].tooltip })
          wow.bossFight(false)
          assert.is_true(row1().notConfirmed.buttons[2].enabled)
        end)

        it("shows why a choice was refused until the next one or the window closing", function()
          local key = unconfirmed({ reserves = RESERVES }, GROUP)
          ns.Popup.Refused(key, "window")
          assert.are.equal("The loot window is closed. Open it to hand the item out.",
            row1().notConfirmed.refusal)
          ns.Popup.Refused(key, "fight")
          assert.is_truthy(row1().notConfirmed.refusal:find("Chat is locked in the boss fight", 1, true))
          ns.Popup.Refused(key, "something new")
          assert.are.equal("It couldn't be done (something new).", row1().notConfirmed.refusal)
          ns.Popup.Refused(key, nil)
          assert.is_nil(row1().notConfirmed.refusal)
          ns.Popup.Refused(key, "changed")
          wow.fire("LOOT_CLOSED")
          drop({ { id = 1 } })
          assert.is_nil(row1().notConfirmed.refusal)
        end)

        it("shows the row waiting again after Try again, and the state again if it fails again", function()
          local key = unconfirmed({ reserves = RESERVES }, GROUP)
          assert(click(ns.Popup.TryAgain, key))
          assert.is_nil(row1().notConfirmed)
          assert.is_table(row1().handout)
          wow.advance(ns.Tracking.confirmWait)
          assert.is_table(row1().notConfirmed)
          assert.is_nil(row1().handout)
        end)

        it("clears the state when the game confirms late", function()
          local key = unconfirmed({ reserves = RESERVES }, GROUP)
          wow.fire("LOOT_SLOT_CLEARED", 1)
          wow.fire("CHAT_MSG_LOOT", "Ashla Brightwater receives loot: " .. link(1) .. ".")
          assert.are.equal("confirmed", ns.Records.Get(key).state)
          assert.is_nil(row1().notConfirmed)
        end)

        it("clears the state when the award is voided", function()
          local key = unconfirmed({ reserves = RESERVES }, GROUP)
          assert(click(ns.Popup.NotHandedOut, key))
          assert.is_nil(row1().notConfirmed)
        end)

        it("shows it only on the row holding the same item", function()
          unconfirmed({ reserves = RESERVES }, GROUP)
          wow.state.loot[1].link = link(2)
          assert.is_nil(row1().notConfirmed)
        end)
      end)

      describe("a Disenchant/bank award (#39)", function()
        -- Gives item 1 to the D/B pick and lets the wait run out. Returns the award key.
        local function unconfirmedDB(fields)
          raid(fields)
          drop({ { id = 1 } })
          ns.Popup.SetDBPick("Bram Ironvein")
          local attempt
          wow.click(function() attempt = assert(ns.Popup.GiveDB(1, 1, "Bram Ironvein")) end)
          wow.advance(ns.Tracking.confirmWait)
          assert.are.equal("not-confirmed", ns.Records.Get(attempt.awardKey).state)
          return attempt.awardKey
        end

        it("tries again to the same character, even after the pick changed", function()
          local key = unconfirmedDB()
          ns.Popup.SetDBPick("Doran Vale")
          local attempt = assert(click(ns.Popup.TryAgain, key))
          assert.are.same({ slot = 1, candidate = 4 }, wow.gives[2])
          assert.are.equal("Bram Ironvein", attempt.winner)
          assert.are.equal(1, #wow.sent)
          confirm(1, "Bram Ironvein")
          assert.are.equal("confirmed", ns.Records.Get(key).state)
        end)

        it("after a /reload, tries again to its own raid's pick, not the selected raid's", function()
          local key = unconfirmedDB()
          ns.Raids.Load(assert(ns.Snapshot.Validate(tree({ raid = "raid00002", code = "SA0002" }), "0.1.0")),
            "pasted")
          assert(ns.Selection.ChooseRaid("raid00002", true))
          ns.Popup.SetDBPick("Doran Vale")
          local group = wow.state.group
          ns = wow.start({ saved = { BureaucracyForeverDB = BureaucracyForeverDB } })
          wow.state.group, wow.state.groupIsRaid, wow.state.lootMethod = group, true, { "master", 0, 0 }
          assert.are.equal("Doran Vale", ns.Popup.DBPick())
          drop({ { id = 1 } })
          local attempt = assert(click(ns.Popup.TryAgain, key))
          assert.are.same({ "Bram Ironvein", { slot = 1, candidate = 4 } }, { attempt.winner, wow.gives[1] })
        end)

        it("after a /reload with no pick saved for its raid, gives nothing", function()
          local key = unconfirmedDB()
          BureaucracyForeverDB.dbPick = nil
          local group = wow.state.group
          ns = wow.start({ saved = { BureaucracyForeverDB = BureaucracyForeverDB } })
          wow.state.group, wow.state.groupIsRaid, wow.state.lootMethod = group, true, { "master", 0, 0 }
          drop({ { id = 1 } })
          assert.are.same({ nil, "no pick" }, { click(ns.Popup.TryAgain, key) })
          assert.are.same({}, wow.gives)
        end)

        it("voids it with the undo line that names no winner", function()
          local key = unconfirmedDB()
          local op = assert(click(ns.Popup.NotHandedOut, key))
          assert.is_true(ns.Records.Get(key).voided)
          assert.are.same({ channel = "RAID", text = "Undo: " .. link(1) .. " is no longer going to"
            .. " disenchant/bank <BF1;V;SA0001;" .. op.id .. ";" .. key .. ">" }, wow.sent[2])
        end)

        it("gives it to a reserve holder instead, correcting disenchant/bank", function()
          local key = unconfirmedDB()
          local attempt = assert(click(ns.Popup.GiveElse, key, "Ashla Brightwater"))
          assert.is_truthy(wow.sent[2].text:find("→ Ashla Brightwater (hard reserve), not disenchant/bank <",
            1, true))
          assert.are.equal("HR", ns.Records.Get(attempt.awardKey).method)
        end)

        it("tells the officer when the undo or correction line can't be built", function()
          local key = unconfirmedDB({ code = "MC0001" })
          assert(click(ns.Popup.GiveElse, key, "Ashla Brightwater"))
          assert.is_truthy(wow.printed[#wow.printed]:find("instead of disenchant/bank, but its raid chat", 1,
            true))
          key = unconfirmedDB({ code = "MC0001" })
          assert(click(ns.Popup.NotHandedOut, key))
          assert.is_truthy(wow.printed[#wow.printed]:find("is no longer going to disenchant/bank, but", 1,
            true))
        end)
      end)

      it("stays not confirmed when the loot window closes with no choice made", function()
        local key = unconfirmed()
        wow.closeLoot()
        assert.are.equal("not-confirmed", ns.Records.Get(key).state)
      end)

      it("still confirms the award when the game confirms late", function()
        local key = unconfirmed()
        confirm(1, "Ashla Brightwater")
        assert.are.equal("confirmed", ns.Records.Get(key).state)
        assert.are.equal("confirm", ns.Records.Ops("raid00001")[3].type)
      end)

      it("tries again: hands out to the same winner, posts nothing, records nothing new", function()
        local key = unconfirmed()
        local attempt = assert(click(ns.Popup.TryAgain, key))
        assert.are.same({ key, true }, { attempt.awardKey, attempt.announced })
        assert.are.same({ slot = 1, candidate = 2 }, wow.gives[2])
        assert.are.equal(1, #wow.sent)
        assert.are.equal(2, #ns.Records.Ops("raid00001"))
        assert.are.equal("Handing out to Ashla Brightwater…", ns.Popup.Build().rows[1].handout.text)
        confirm(1, "Ashla Brightwater")
        assert.are.equal("confirmed", ns.Records.Get(key).state)
      end)

      it("tries again in a boss fight, since it posts nothing", function()
        local key = unconfirmed()
        wow.bossFight(true)
        assert.is_truthy(click(ns.Popup.TryAgain, key))
        assert.are.equal(2, #wow.gives)
      end)

      it("finds the item when the reopened loot window lists it in another slot", function()
        local key = unconfirmed()
        wow.closeLoot()
        drop({ { id = 3 }, { id = 1 } })
        assert.is_truthy(click(ns.Popup.TryAgain, key))
        assert.are.same({ slot = 2, candidate = 2 }, wow.gives[2])
      end)

      it("refuses the hand-outs with the loot window closed or the item gone, and says so", function()
        local key = unconfirmed()
        wow.closeLoot()
        assert.are.same({ nil, "window" }, { click(ns.Popup.TryAgain, key) })
        assert.are.equal("Open the loot window to hand it out.", wow.printed[#wow.printed]:match(":|r (.*)$"))
        assert.are.same({ nil, "window" }, { click(ns.Popup.GiveElse, key, "Doran Vale") })
        unchanged(key, 1)
        drop({ { id = 3 } })
        assert.are.same({ nil, "changed" }, { click(ns.Popup.TryAgain, key) })
        assert.are.same({ nil, "changed" }, { click(ns.Popup.GiveElse, key, "Doran Vale") })
        unchanged(key, 1)
      end)

      it("refuses to try again when the winner can't receive the item now", function()
        local key = unconfirmed()
        wow.state.loot[1].candidates = { "Masterlooter", "Doran Vale" }
        assert.are.same({ nil, "not a candidate" }, { click(ns.Popup.TryAgain, key) })
        unchanged(key, 1)
      end)

      it("refuses every choice while a retry waits for the game, and again once it gives up", function()
        local key = unconfirmed()
        assert.is_truthy(click(ns.Popup.TryAgain, key))
        assert.are.same({ nil, "handing out" }, { click(ns.Popup.TryAgain, key) })
        assert.are.same({ nil, "handing out" }, { click(ns.Popup.GiveElse, key, "Doran Vale") })
        assert.are.same({ nil, "handing out" }, { click(ns.Popup.NotHandedOut, key) })
        assert.are.same({ nil, "handing out" }, { ns.Popup.GiveElseList(key) })
        assert.are.equal(2, #wow.gives)
        assert.are.equal(1, #wow.sent)
        assert.are.equal(2, #ns.Records.Ops("raid00001"))
        wow.advance(ns.Tracking.confirmWait)
        assert.is_truthy(click(ns.Popup.NotHandedOut, key))
      end)

      it("refuses every choice for an award not waiting as not confirmed", function()
        raid()
        drop({ { id = 1 } })
        local key = assert(give(1)).awardKey
        for _, fn in ipairs({ ns.Popup.TryAgain, ns.Popup.NotHandedOut }) do
          assert.are.same({ nil, "not unconfirmed" }, { click(fn, key) })
        end
        assert.are.same({ nil, "not unconfirmed" }, { click(ns.Popup.GiveElse, key, "Doran Vale") })
        assert.are.same({ nil, "not unconfirmed" }, { ns.Popup.GiveElseList(key) })
        assert.are.same({ nil, "not unconfirmed" }, { click(ns.Popup.TryAgain, "aw-nosuchkey") })
      end)

      describe("give to someone else", function()
        local RESERVES = { [1] = { holder("Ashla Brightwater", "HR"), holder("Doran Vale", "SR"),
          holder("Mirel Stone", "SR"), holder("Tovin Hale", "SR", { trial = true }),
          holder("Bram Ironvein", "SR") } }

        -- Ashla's award not confirmed, in a raid without Mirel.
        local function setupList()
          return unconfirmed({ reserves = RESERVES }, GROUP)
        end

        it("lists the item's other holders with their methods, greying who isn't in the raid", function()
          raid({ reserves = RESERVES })
          wow.state.group = GROUP
          -- Bram has the item already, from an earlier copy.
          assert(ns.Records.Award({ boss = "lb_lucifron", item = 1, char = "Bram Ironvein",
            user = "bramironvein", method = "SR" }))
          drop({ { id = 1 } })
          local key = assert(give(1)).awardKey
          wow.advance(ns.Tracking.confirmWait)
          assert.are.same({
            { char = "Doran Vale", user = "doranvale", method = "SR", available = true },
            { char = "Mirel Stone", user = "mirelstone", method = "SR", available = false,
              reason = "not in raid" },
          }, ns.Popup.GiveElseList(key))
        end)

        it("lists a hard reserve first, and leaves out a holder the site blocked", function()
          raid({ reserves = { [1] = { holder("Doran Vale", "SR"), holder("Ashla Brightwater", "HR"),
            holder("Bram Ironvein", "HR"), holder("Tovin Hale", "SR", { blocked = "left the guild" }) } } })
          -- Bram can't receive it at first, so Ashla is the one hard reserve; then he can.
          drop({ { id = 1, candidates = { "Masterlooter", "Ashla Brightwater", "Doran Vale" } } })
          local key = assert(give(1)).awardKey
          wow.advance(ns.Tracking.confirmWait)
          wow.state.loot[1].candidates = wow.state.group
          assert.are.same({
            { char = "Bram Ironvein", user = "bramironvein", method = "HR", available = true },
            { char = "Doran Vale", user = "doranvale", method = "SR", available = true },
          }, ns.Popup.GiveElseList(key))
          local attempt = assert(click(ns.Popup.GiveElse, key, "Bram Ironvein"))
          assert.are.equal("HR", ns.Records.Get(attempt.awardKey).method)
        end)

        it("greys a holder the game won't let receive the item", function()
          local key = setupList()
          wow.state.loot[1].candidates = { "Masterlooter", "Ashla Brightwater", "Doran Vale" }
          local list = ns.Popup.GiveElseList(key)
          assert.are.same({ "Bram Ironvein", "SR", false, "cannot receive" },
            { list[3].char, list[3].method, list[3].available, list[3].reason })
          assert.are.same({ nil, "cannot receive" }, { click(ns.Popup.GiveElse, key, "Bram Ironvein") })
          unchanged(key, 1)
        end)

        it("hands out, records the replacement and posts the one correction line", function()
          local key = setupList()
          local attempt = assert(click(ns.Popup.GiveElse, key, "Doran Vale"))
          assert.are.same({ slot = 1, candidate = 3 }, wow.gives[2])
          local old, new = ns.Records.Get(key), ns.Records.Get(attempt.awardKey)
          assert.are.same({ true, attempt.awardKey }, { old.voided, old.replacedBy })
          assert.are.same({ "announced", "Doran Vale", "doranvale", "SR", "lb_lucifron", key },
            { new.state, new.char, new.user, new.method, new.boss, new.replaces })
          local replace = ns.Records.Ops("raid00001")[3]
          assert.are.equal("replace", replace.type)
          assert.are.same({ channel = "RAID", text = "Correction: " .. link(1)
            .. " → Doran Vale (soft reserve), not Ashla Brightwater <BF1;R;SA0001;" .. replace.id .. ";"
            .. key .. ";" .. attempt.awardKey .. ";1;ifron;SR;;Doran Vale>" }, wow.sent[2])
          assert.is_true(attempt.announced)
          confirm(1, "Doran Vale")
          assert.are.equal("confirmed", ns.Records.Get(attempt.awardKey).state)
        end)

        it("records the replacement even when the line can't be built, and says so", function()
          local key = unconfirmed({ code = "MC0001", reserves = RESERVES }, GROUP)
          local attempt = assert(click(ns.Popup.GiveElse, key, "Doran Vale"))
          assert.are.equal(2, #wow.gives)
          assert.are.equal(0, #wow.sent)
          assert.is_nil(attempt.announced)
          assert.are.same({ true, "Doran Vale" }, { ns.Records.Get(key).voided,
            ns.Records.Get(attempt.awardKey).char })
          assert.is_truthy(wow.printed[#wow.printed]:find("is being handed to Doran Vale instead of Ashla"
            .. " Brightwater, but its raid chat line couldn't be posted", 1, true))
          assert.is_truthy(ns.log[#ns.log].text:find("Correction line for .* not posted: the raid code"))
        end)

        it("refuses who isn't in the raid or on the list, and waits out a boss fight", function()
          local key = setupList()
          assert.are.same({ nil, "not in raid" }, { click(ns.Popup.GiveElse, key, "Mirel Stone") })
          assert.are.same({ nil, "not a contender" }, { click(ns.Popup.GiveElse, key, "Tovin Hale") })
          assert.are.same({ nil, "not a contender" }, { click(ns.Popup.GiveElse, key, "Ashla Brightwater") })
          wow.bossFight(true)
          assert.are.same({ nil, "fight" }, { click(ns.Popup.GiveElse, key, "Doran Vale") })
          unchanged(key, 1)
          wow.bossFight(false)
          assert.is_truthy(click(ns.Popup.GiveElse, key, "Doran Vale"))
        end)

        it("starts the line with [Practice] for a practice award", function()
          local key = setupList()
          ns.Records.Get(key).practice = true
          assert.is_truthy(click(ns.Popup.GiveElse, key, "Doran Vale"))
          assert.is_truthy(wow.sent[2].text:find("^%[Practice%] Correction: "))
          assert.is_truthy(wow.sent[2].text:find("<BF1P;R;", 1, true))
        end)
      end)

      describe("the Disenchant/bank line (#96)", function()
        local RESERVES = { [1] = { holder("Ashla Brightwater", "HR"), holder("Doran Vale", "SR") } }

        -- Ashla's award not confirmed, with Bram as the raid's D/B pick. Returns the award key.
        local function setupDB()
          local key = unconfirmed({ reserves = RESERVES }, GROUP)
          assert.is_true(ns.Popup.SetDBPick("Bram Ironvein"))
          return key
        end

        local function dbLine() return ns.Popup.Build().rows[1].notConfirmed.list.db end

        it("shows the line with the pick's name after the reserve holders", function()
          setupDB()
          local list = ns.Popup.Build().rows[1].notConfirmed.list
          assert.are.equal("Doran Vale", list.people[1].char)
          assert.are.same({ label = "Disenchant/bank", pick = "Bram Ironvein", enabled = true }, list.db)
        end)

        it("with no pick, greys the line and gives nothing", function()
          local key = unconfirmed({ reserves = RESERVES }, GROUP)
          assert.are.same({ label = "Disenchant/bank: choose first", enabled = false,
            tooltip = "Disenchant/bank: choose the character to give to." }, dbLine())
          assert.are.same({ nil, "no pick" }, { click(ns.Popup.GiveElseDB, key, nil) })
          unchanged(key, 1)
          -- The pick chosen with another row's D/B button shows at once.
          assert.is_true(ns.Popup.SetDBPick("Bram Ironvein"))
          assert.are.same({ "Disenchant/bank", "Bram Ironvein", true },
            { dbLine().label, dbLine().pick, dbLine().enabled })
        end)

        it("hands out to the pick, records the replacement and posts the one correction line", function()
          local key = setupDB()
          local attempt = assert(click(ns.Popup.GiveElseDB, key, "Bram Ironvein"))
          assert.are.same({ slot = 1, candidate = 4 }, wow.gives[2])
          local old, new = ns.Records.Get(key), ns.Records.Get(attempt.awardKey)
          assert.are.same({ true, attempt.awardKey }, { old.voided, old.replacedBy })
          assert.are.same({ "announced", "DISENCHANT_BANK", "lb_lucifron", key },
            { new.state, new.method, new.boss, new.replaces })
          assert.is_nil(new.char)
          assert.is_nil(new.user)
          local replace = ns.Records.Ops("raid00001")[3]
          assert.are.equal("replace", replace.type)
          assert.are.equal(2, #wow.sent)
          assert.are.equal("RAID", wow.sent[2].channel)
          assert.are.equal("Correction: " .. link(1) .. " → disenchant/bank, not Ashla Brightwater"
            .. " <BF1;R;SA0001;" .. replace.id .. ";" .. key .. ";" .. attempt.awardKey
            .. ";1;ifron;DISENCHANT_BANK;;>",
            wow.sent[2].text)
          assert.is_true(attempt.announced)
          confirm(1, "Bram Ironvein")
          assert.are.equal("confirmed", ns.Records.Get(attempt.awardKey).state)
        end)

        it("gives through the row's choice and clears the refusal", function()
          local key = setupDB()
          ns.Popup.Refused(key, "window")
          assert.is_truthy(click(ns.Popup.Choose, key, "givedb", "Bram Ironvein"))
          assert.is_nil(ns.Popup.Refusal(key))
          assert.are.equal("DISENCHANT_BANK", ns.Records.Get(ns.Records.Get(key).replacedBy).method)
        end)

        it("is hidden for a Disenchant/bank award, leaving the reserve holders", function()
          raid({ reserves = RESERVES })
          wow.state.group = GROUP
          drop({ { id = 1 } })
          assert.is_true(ns.Popup.SetDBPick("Bram Ironvein"))
          local key
          wow.click(function() key = assert(ns.Popup.GiveDB(1, 1, "Bram Ironvein")).awardKey end)
          wow.advance(ns.Tracking.confirmWait)
          local nc = ns.Popup.Build().rows[1].notConfirmed
          assert.is_nil(nc.list.db)
          assert.are.same({ "Ashla Brightwater", "Doran Vale" },
            { nc.list.people[1].char, nc.list.people[2].char })
          assert.are.same({ "Try again", "Give to someone else", "Not handed out" },
            { nc.buttons[1].text, nc.buttons[2].text, nc.buttons[3].text })
          assert.are.same({ nil, "already db" }, { click(ns.Popup.GiveElseDB, key, "Bram Ironvein") })
          unchanged(key, 1)
        end)

        it("waits out a boss fight: the line's Give is greyed with the fight tooltip", function()
          local key = setupDB()
          wow.bossFight(true)
          assert.are.same({ label = "Disenchant/bank", pick = "Bram Ironvein", enabled = false,
            tooltip = "Posts a line, so it waits until the boss fight ends" }, dbLine())
          assert.are.same({ nil, "fight" }, { click(ns.Popup.GiveElseDB, key, "Bram Ironvein") })
          unchanged(key, 1)
          wow.bossFight(false)
          assert.is_truthy(click(ns.Popup.GiveElseDB, key, "Bram Ironvein"))
        end)

        it("refuses with the loot window closed or the item gone, and changes nothing", function()
          local key = setupDB()
          wow.closeLoot()
          assert.are.same({ nil, "window" }, { click(ns.Popup.GiveElseDB, key, "Bram Ironvein") })
          unchanged(key, 1)
          drop({ { id = 3 } })
          assert.are.same({ nil, "changed" }, { click(ns.Popup.GiveElseDB, key, "Bram Ironvein") })
          unchanged(key, 1)
        end)

        it("refuses an award confirmed late meanwhile, handing nothing out", function()
          local key = setupDB()
          confirm(1, "Ashla Brightwater")
          drop({ { id = 1 } })
          assert.are.same({ nil, "not unconfirmed" }, { click(ns.Popup.GiveElseDB, key, "Bram Ironvein") })
          assert.are.equal(1, #wow.gives)
          assert.are.equal(1, #wow.sent)
          assert.is_nil(ns.Records.Get(key).voided)
        end)

        it("refuses a pick who can't receive it or isn't in the raid, naming them in the row", function()
          local key = setupDB()
          wow.state.loot[1].candidates = { "Masterlooter", "Ashla Brightwater", "Doran Vale" }
          local function choose() return click(ns.Popup.Choose, key, "givedb", "Bram Ironvein") end
          assert.are.same({ nil, "not a candidate" }, { choose() })
          assert.are.equal("The game won't let Bram Ironvein receive this item (usually: not nearby when the"
            .. " boss died). Right-click D/B to choose someone else.",
            ns.Popup.Build().rows[1].notConfirmed.refusal)
          wow.state.group = { "Masterlooter", "Ashla Brightwater", "Doran Vale" }
          assert.are.same({ nil, "not a candidate" }, { choose() })
          assert.are.equal("Bram Ironvein isn't in the raid. Right-click D/B to choose someone else.",
            ns.Popup.Refusal(key))
          unchanged(key, 1)
        end)

        it("refuses when the pick changed after the line was drawn", function()
          local key = setupDB()
          assert.are.same({ nil, "pick changed" }, { click(ns.Popup.GiveElseDB, key, "Doran Vale") })
          unchanged(key, 1)
        end)

        it("records the replacement even when the line can't be built, and says so", function()
          local key = unconfirmed({ code = "MC0001", reserves = RESERVES }, GROUP)
          assert.is_true(ns.Popup.SetDBPick("Bram Ironvein"))
          local attempt = assert(click(ns.Popup.GiveElseDB, key, "Bram Ironvein"))
          assert.are.equal(2, #wow.gives)
          assert.are.equal(0, #wow.sent)
          assert.is_nil(attempt.announced)
          assert.are.same({ true, "DISENCHANT_BANK" }, { ns.Records.Get(key).voided,
            ns.Records.Get(attempt.awardKey).method })
          assert.is_truthy(wow.printed[#wow.printed]:find("is being handed to Bram Ironvein to disenchant or"
            .. " bank instead of Ashla Brightwater, but its raid chat line couldn't be posted", 1, true))
        end)
      end)

      describe("not handed out", function()
        it("voids the award and posts its undo line, with no loot window needed", function()
          local key = unconfirmed()
          wow.closeLoot()
          local op = assert(click(ns.Popup.NotHandedOut, key))
          assert.are.same({ "void", "not handed out" }, { op.type, op.reason })
          assert.is_true(ns.Records.Get(key).voided)
          assert.are.same({ channel = "RAID", text = "Undo: " .. link(1) .. " is no longer awarded to Ashla"
            .. " Brightwater <BF1;V;SA0001;" .. op.id .. ";" .. key .. ">" }, wow.sent[2])
          assert.are.equal(1, #wow.gives)
        end)

        it("starts the line with [Practice] for a practice award", function()
          local key = unconfirmed()
          ns.Records.Get(key).practice = true
          assert.is_truthy(click(ns.Popup.NotHandedOut, key))
          assert.is_truthy(wow.sent[2].text:find("^%[Practice%] Undo: "))
        end)

        it("waits out a boss fight", function()
          local key = unconfirmed()
          wow.bossFight(true)
          assert.are.same({ nil, "fight" }, { click(ns.Popup.NotHandedOut, key) })
          unchanged(key, 1)
        end)

        it("voids even when the line can't be built, and says so", function()
          local key = unconfirmed({ code = "MC0001" })
          assert.is_truthy(click(ns.Popup.NotHandedOut, key))
          assert.is_true(ns.Records.Get(key).voided)
          assert.are.equal(0, #wow.sent)
          assert.is_truthy(wow.printed[#wow.printed]:find("is no longer awarded to Ashla Brightwater, but its"
            .. " raid chat line couldn't be posted", 1, true))
          assert.is_truthy(ns.log[#ns.log].text:find("Undo line for .* not posted: the raid code"))
        end)

        it("tells the officer when the game confirms it after all, and keeps the void", function()
          local key = unconfirmed()
          assert.is_truthy(click(ns.Popup.NotHandedOut, key))
          confirm(1, "Ashla Brightwater")
          local award = ns.Records.Get(key)
          assert.are.same({ true, "not-confirmed" }, { award.voided, award.state })
          assert.is_truthy(wow.printed[#wow.printed]:find("got " .. link(1) .. " after all", 1, true))
        end)
      end)

      describe("in practice mode (#17)", function()
        local function practice() wow.slash("/bf practice") end
        local function practiceOps()
          local marks = {}
          for i, op in ipairs(ns.Records.Ops("raid00001")) do marks[i] = op.practice or false end
          return marks
        end

        it("marks the award and its follow-ups practice, and its line [Practice]", function()
          raid()
          practice()
          drop({ { id = 1 } })
          local attempt = assert(give(1))
          assert.is_true(ns.Records.Get(attempt.awardKey).practice)
          assert.are.equal("[Practice] " .. link(1) .. " → Masterlooter (hard reserve) <BF1P;A;SA0001;"
            .. attempt.awardKey .. ";1;ifron;HR;;Masterlooter>", wow.sent[1].text)
          confirm(1, "Masterlooter")
          assert.are.same({ true, true }, practiceOps())
        end)

        it("marks a D/B award practice", function()
          raid()
          practice()
          drop({ { id = 1 } })
          assert.is_true(ns.Popup.SetDBPick("Doran Vale"))
          local attempt = assert(click(ns.Popup.GiveDB, 1, 1, "Doran Vale"))
          assert.is_true(ns.Records.Get(attempt.awardKey).practice)
          assert.is_truthy(wow.sent[1].text:find("^%[Practice%] .*<BF1P;A;SA0001;"))
        end)

        it("marks nothing and posts no [Practice] with it off", function()
          raid()
          drop({ { id = 1 }, { id = 2 } })
          assert.is_false(ns.Popup.Build().practice)
          assert.is_truthy(give(1))
          assert.is_true(ns.Popup.SetDBPick("Doran Vale"))
          assert.is_truthy(click(ns.Popup.GiveDB, 2, 2, "Doran Vale"))
          assert.are.same({ false, false }, practiceOps())
          for _, sent in ipairs(wow.sent) do
            assert.is_nil(sent.text:find("Practice", 1, true))
            assert.is_nil(sent.text:find("BF1P", 1, true))
          end
        end)

        it("marks a not confirmed practice award's choices practice", function()
          raid({ reserves = { [1] = { holder("Ashla Brightwater", "HR"), holder("Doran Vale", "SR") } } })
          practice()
          -- Item 2 has three made-up hard reserve holders; a D/B award is the one to replace.
          drop({ { id = 1 }, { id = 2 } })
          assert.is_true(ns.Popup.SetDBPick("Masterlooter"))
          local key = assert(click(ns.Popup.GiveDB, 2, 2, "Masterlooter")).awardKey
          wow.advance(ns.Tracking.confirmWait)
          local attempt = assert(click(ns.Popup.GiveElse, key, "Doran Vale"))
          assert.is_true(ns.Records.Get(attempt.awardKey).practice)
          assert.is_truthy(wow.sent[2].text:find("^%[Practice%] Correction: .*<BF1P;R;"))
          wow.advance(ns.Tracking.confirmWait)
          assert.is_truthy(click(ns.Popup.NotHandedOut, attempt.awardKey))
          assert.is_truthy(wow.sent[3].text:find("^%[Practice%] Undo: .*<BF1P;V;"))
          assert.are.same({ true, true, true, true, true }, practiceOps())
        end)

        it("applies a switch to the next hand-out only: an award made keeps its mark", function()
          raid()
          practice()
          drop({ { id = 1 }, { id = 2 } })
          local first = assert(give(1))
          practice() -- off, with the pop-up open
          assert.is_false(ns.Popup.Build().practice)
          local second = assert(give(2))
          assert.is_true(ns.Records.Get(first.awardKey).practice)
          assert.is_nil(ns.Records.Get(second.awardKey).practice)
          assert.is_nil(wow.sent[2].text:find("Practice", 1, true))
          -- The practice award's undo stays practice, and the real one's real, whichever way it is now.
          wow.advance(ns.Tracking.confirmWait)
          practice() -- on again
          assert.is_truthy(click(ns.Popup.NotHandedOut, second.awardKey))
          assert.is_truthy(wow.sent[3].text:find("^Undo: .*<BF1;V;"))
          practice() -- off
          assert.is_truthy(click(ns.Popup.NotHandedOut, first.awardKey))
          assert.is_truthy(wow.sent[4].text:find("^%[Practice%] Undo: .*<BF1P;V;"))
        end)

        it("leaves its awards out of the copy-out for the site", function()
          raid()
          practice()
          drop({ { id = 1 }, { id = 2 } })
          local first = assert(give(1))
          confirm(1, "Ashla Brightwater")
          assert.are.same({ nil, "Nothing to copy: this raid has no awards to send." },
            { ns.Sync.CopyOut("raid00001") })
          practice()
          local second = assert(give(2))
          local text, count = ns.Sync.CopyOut("raid00001")
          assert.are.equal(1, count)
          assert.is_truthy(text:find(second.awardKey, 1, true))
          assert.is_nil(text:find(first.awardKey, 1, true))
        end)

        it("puts [Practice] in the title", function()
          raid()
          drop({ { id = 1 } })
          assert.are.equal("Loot · Lucifron", ns.Popup.Build().title)
          practice()
          local m = ns.Popup.Build()
          assert.are.same({ true, "[Practice] Loot · Lucifron" }, { m.practice, m.title })
        end)
      end)
    end)
  end)

  describe("the roll list (#90)", function()
    local BOSSES = {
      { id = "lb_lucifron", name = "Lucifron", trash = false, items = { 1, 2, 3 } },
      { id = "lb_trash", name = "Trash", trash = true, items = {} },
    }

    -- Item 1: hard reserved by four; item 2: soft reserved by two; item 3: nobody.
    local function raid(candidates)
      setup({ code = "SA0001", bosses = BOSSES, reserves = {
        [1] = { holder("Ashla Brightwater", "HR"), holder("Doran Vale", "HR"), holder("Mirel Stone", "HR"),
          holder("Tovin Hale", "HR") },
        [2] = { holder("Bram Ironvein", "SR"), holder("Mirel Stone", "SR") } } })
      drop({ { id = 1, candidates = candidates }, { id = 2 }, { id = 3 } })
      assert(ns.Popup.PickBoss("lb_lucifron"))
    end

    local function call(slot)
      wow.click(function() assert(ns.Rolls.Start(slot, slot)) end)
    end

    local function roll(name, n, range)
      wow.fire("CHAT_MSG_SYSTEM", name .. " rolls " .. n .. " " .. (range or "(1-100)"))
    end

    local function row(slot) return ns.Popup.Build().rows[slot] end

    local function give(slot)
      local button = row(slot).buttons[1]
      local result
      wow.click(function()
        result = { ns.Popup.Give(slot, row(slot).item, button.winner, button.roll) }
      end)
      return result[1], result[2]
    end

    it("has no roll list before the roll is called", function()
      raid()
      assert.is_nil(row(1).rolls)
      assert.are.equal("Call roll (4)", row(1).buttons[1].text)
    end)

    it("lists the rolls highest first, then who is waiting, and pre-selects the highest", function()
      raid()
      call(1)
      roll("Mirel Stone", 87)
      roll("Quill Ashby", 99)
      roll("Ashla Brightwater", 42)
      roll("Ashla Brightwater", 96)
      local r = row(1)
      assert.are.same({ "Rolls (hard reserve holders only)", "2 of 4 rolled", "or click another name" },
        { r.rolls.heading, r.rolls.count, r.rolls.hint })
      assert.are.same({
        { name = "Mirel Stone", roll = 87, waiting = false, selected = true },
        { name = "Ashla Brightwater", roll = 42, waiting = false, selected = false },
        { name = "Doran Vale", waiting = true, selected = false },
        { name = "Tovin Hale", waiting = true, selected = false },
      }, r.rolls.entries)
      assert.are.same({ { name = "Quill Ashby", roll = 99, reason = "not eligible" },
        { name = "Ashla Brightwater", roll = 96, reason = "second roll, the first counts" } },
        r.rolls.ignored)
      assert.are.same({ "Give to Mirel Stone (87)", "rollgive", true },
        { r.buttons[1].text, r.buttons[1].action, r.buttons[1].enabled })
    end)

    it("heads a soft reserve roll-off and an open roll by who may roll", function()
      raid()
      call(2)
      ns.Rolls.End(2, 2)
      call(3)
      assert.are.equal("Rolls (soft reserve holders only)", row(2).rolls.heading)
      assert.are.equal("Rolls (everyone)", row(3).rolls.heading)
    end)

    it("follows a roll that arrives, and a click on another name moves the pick", function()
      raid()
      call(1)
      roll("Doran Vale", 30)
      assert.are.equal("Give to Doran Vale (30)", row(1).buttons[1].text)
      roll("Mirel Stone", 70)
      assert.are.equal("Give to Mirel Stone (70)", row(1).buttons[1].text)
      assert.is_true(ns.Popup.PickWinner(1, 1, "Doran Vale"))
      assert.are.equal("Give to Doran Vale (30)", row(1).buttons[1].text)
      assert.is_true(row(1).rolls.entries[2].selected)
      roll("Ashla Brightwater", 99) -- a better roll doesn't take the pick away
      assert.are.equal("Give to Doran Vale (30)", row(1).buttons[1].text)
      assert.are.same({ nil, "not listed" }, { ns.Popup.PickWinner(1, 1, "Nobody") })
      assert.are.same({ nil, "not ready" }, { ns.Popup.PickWinner(2, 2, "Doran Vale") })
    end)

    it("pre-selects nobody on a tie or a hidden roll, and Give waits for a click", function()
      raid()
      call(1)
      roll("Doran Vale", 50)
      roll("Mirel Stone", 50)
      assert.are.same({ "Give", false }, { row(1).buttons[1].text, row(1).buttons[1].enabled })
      assert.are.same({ nil, "not ready" }, { give(1) })
      assert.is_true(ns.Popup.PickWinner(1, 1, "Mirel Stone"))
      assert.are.same({ "Give to Mirel Stone (50)", true },
        { row(1).buttons[1].text, row(1).buttons[1].enabled })
      ns.Rolls.End(1, 1)
      call(2)
      wow.fire("CHAT_MSG_SYSTEM", wow.secret)
      assert.are.same({ nil, "not ready" }, { give(2) })
      assert.is_true(row(2).buttons[1].hidden) -- hidden rolls have no Give button (#102)
    end)

    it("gives to the winner, recording the roll and the method in the award and its line", function()
      raid()
      call(1)
      roll("Mirel Stone", 87)
      roll("Doran Vale", 12)
      local attempt = assert(give(1))
      assert.are.same({ { slot = 1, candidate = 5 } }, wow.gives)
      local award = ns.Records.Get(attempt.awardKey)
      assert.are.same({ "Mirel Stone", "mirelstone", "HR", 87 },
        { award.char, award.user, award.method, award.roll })
      assert.is_truthy(wow.sent[#wow.sent].text:find("<BF1;A;SA0001;" .. attempt.awardKey
        .. ";1;ifron;HR;87;Mirel Stone>", 1, true))
      assert.are.same({}, row(1).buttons)
    end)

    it("gives the name that was clicked, with its own roll", function()
      raid()
      call(1)
      roll("Mirel Stone", 87)
      roll("Doran Vale", 12)
      assert(ns.Popup.PickWinner(1, 1, "Doran Vale"))
      local attempt = assert(give(1))
      local award = ns.Records.Get(attempt.awardKey)
      assert.are.same({ "Doran Vale", 12 }, { award.char, award.roll })
    end)

    it("records a soft reserve roll as SR and an open roll as OPEN_ROLL with its number", function()
      raid()
      call(2)
      roll("Mirel Stone", 55)
      assert.are.same({ "SR", 55 }, (function()
        local a = ns.Records.Get(assert(give(2)).awardKey)
        return { a.method, a.roll }
      end)())
      ns.Rolls.End(2, 2)
      call(3)
      roll("Bram Ironvein", 91)
      local award = ns.Records.Get(assert(give(3)).awardKey)
      assert.are.same({ "OPEN_ROLL", 91, "Bram Ironvein" }, { award.method, award.roll, award.char })
      assert.is_truthy(wow.sent[#wow.sent].text:find("(open roll, 91)", 1, true))
    end)

    it("refuses when the button changed after it was drawn", function()
      raid()
      call(1)
      roll("Doran Vale", 30)
      local shown = row(1).buttons[1]
      roll("Mirel Stone", 70)
      local result
      wow.click(function() result = { ns.Popup.Give(1, 1, shown.winner, shown.roll) } end)
      assert.are.same({ nil, "changed" }, result)
      assert.are.same({}, wow.gives)
    end)

    it("disables the buttons in a boss fight, with the tooltip", function()
      raid()
      call(1)
      roll("Mirel Stone", 87)
      wow.bossFight(true)
      local button = row(1).buttons[1]
      assert.are.same({ false, "Chat is locked until the fight ends" }, { button.enabled, button.tooltip })
      assert.are.same({ nil, "fight" }, { give(1) })
      assert.are.same({}, wow.gives)
    end)

    it("won't give to a roller the game can't hand it to", function()
      raid({ "Masterlooter", "Ashla Brightwater", "Doran Vale" })
      call(3)
      roll("Quill Ashby", 80)
      local r = row(3)
      assert.is_false(r.buttons[1].enabled)
      assert.is_truthy(r.rolls.unavailable:find("Quill Ashby can't be given it", 1, true))
      assert.are.same({ nil, "not ready" }, { give(3) })
      assert.are.same({}, wow.gives)
    end)

    it("clears the pick with the loot window", function()
      raid()
      call(1)
      roll("Doran Vale", 30)
      roll("Mirel Stone", 70)
      assert(ns.Popup.PickWinner(1, 1, "Doran Vale"))
      wow.closeLoot()
      raid()
      call(1)
      roll("Doran Vale", 30)
      roll("Mirel Stone", 70)
      assert.are.equal("Give to Mirel Stone (70)", row(1).buttons[1].text)
    end)

    describe("ties and hidden rolls (#102)", function()
      local function tie()
        raid()
        call(1)
        roll("Doran Vale", 87)
        roll("Mirel Stone", 87)
        roll("Tovin Hale", 20)
      end

      local function hide(slot)
        call(slot)
        wow.fire("CHAT_MSG_SYSTEM", wow.secret)
      end

      local function giveHidden(slot, name, text)
        local result
        wow.click(function()
          result = { ns.Popup.GiveHidden(slot, row(slot).item, name, text) }
        end)
        return result[1], result[2]
      end

      it("shows a tie with the tied names marked and the line a re-roll posts", function()
        tie()
        local list = row(1).rolls
        assert.are.equal("Tie at 87: Doran Vale and Mirel Stone", list.warning)
        assert.are.same({ true, true, nil, nil },
          { list.entries[1].tied, list.entries[2].tied, list.entries[3].tied, list.entries[4].tied })
        assert.are.same({ "Re-roll the tie", "reroll", true,
          "Posts: Tie for " .. row(1).link .. ": Doran Vale and Mirel Stone, roll again" },
          { list.reroll.text, list.reroll.action, list.reroll.enabled, list.reroll.hint })
        assert.is_nil(list.hidden)
      end)

      it("shortens the posted line when many players tie, as the re-roll does", function()
        raid()
        call(3)
        for i = 1, 40 do roll("Playerwithalongname" .. string.char(64 + i % 26 + 1) .. i, 50) end
        local list = row(3).rolls
        local posted = ns.Rolls.RerollLine(3, 3)
        assert.is_truthy(posted:find("more", 1, true))
        assert.are.equal("Posts: " .. posted, list.reroll.hint)
      end)

      it("has no tie warning without a tie", function()
        raid()
        call(1)
        roll("Doran Vale", 87)
        roll("Mirel Stone", 50)
        assert.is_nil(row(1).rolls.warning)
        assert.is_nil(row(1).rolls.reroll)
      end)

      it("keeps tied names clickable, and Give follows a click", function()
        tie()
        assert.is_false(row(1).buttons[1].enabled)
        assert.is_true(ns.Popup.PickWinner(1, 1, "Doran Vale"))
        assert.are.same({ "Give to Doran Vale (87)", true },
          { row(1).buttons[1].text, row(1).buttons[1].enabled })
      end)

      it("disables the re-roll button in a boss fight, with the tooltip", function()
        tie()
        wow.bossFight(true)
        local reroll = row(1).rolls.reroll
        assert.are.same({ false, "Chat is locked until the fight ends" }, { reroll.enabled, reroll.tooltip })
      end)

      it("shows hidden rolls with a warning, the names, and no Give button", function()
        raid()
        hide(1)
        local list = row(1).rolls
        assert.are.equal("The game is hiding rolls from add-ons right now."
          .. " Watch chat, then click the winner.", list.hidden.warning)
        assert.are.equal("Their roll (optional):", list.hidden.label)
        local shown = {}
        for i, e in ipairs(list.entries) do shown[i] = e.name end
        assert.are.same({ "Ashla Brightwater", "Doran Vale", "Mirel Stone", "Tovin Hale" }, shown)
        assert.is_true(row(1).buttons[1].hidden)
        assert.is_false(row(1).buttons[1].enabled)
        assert.is_true(row(1).buttons[2].enabled) -- Disenchant/bank stays
        assert.is_nil(list.reroll)
      end)

      it("names the players in the loot window for a hidden open roll, and needs their roll", function()
        raid()
        hide(3)
        local shown = {}
        for i, e in ipairs(row(3).rolls.entries) do shown[i] = e.name end
        assert.are.same({ "Masterlooter", "Ashla Brightwater", "Doran Vale", "Bram Ironvein", "Mirel Stone",
          "Tovin Hale" }, shown)
        assert.are.equal("Their roll (needed for an open roll):", row(3).rolls.hidden.label)
      end)

      it("awards to the clicked name with the typed roll", function()
        raid()
        hide(1)
        local attempt = assert(giveHidden(1, "Mirel Stone", " 64 "))
        local award = ns.Records.Get(attempt.awardKey)
        assert.are.same({ "Mirel Stone", "HR", 64 }, { award.char, award.method, award.roll })
        assert.are.same({ { slot = 1, candidate = 5 } }, wow.gives)
        assert.is_truthy(wow.sent[#wow.sent].text:find(";HR;64;Mirel Stone>", 1, true))
      end)

      it("awards with no roll for a hard or soft reserve roll", function()
        raid()
        hide(2)
        local attempt = assert(giveHidden(2, "Bram Ironvein", ""))
        local award = ns.Records.Get(attempt.awardKey)
        assert.are.same({ "SR", nil }, { award.method, award.roll })
      end)

      it("awards an open roll with its number", function()
        raid()
        hide(3)
        local attempt = assert(giveHidden(3, "Bram Ironvein", "91"))
        local award = ns.Records.Get(attempt.awardKey)
        assert.are.same({ "OPEN_ROLL", 91 }, { award.method, award.roll })
        assert.are.equal(1, #ns.Records.Ops(ns.Selection.Status().activeRaid))
      end)

      it("refuses an open roll with no number, handing out, recording and posting nothing", function()
        raid()
        hide(3)
        local sent = #wow.sent
        assert.are.same({ nil, "roll needed" }, { giveHidden(3, "Bram Ironvein", "") })
        assert.are.same({}, wow.gives)
        assert.are.equal(sent, #wow.sent)
        assert.are.same({}, ns.Records.Ops(ns.Selection.Status().activeRaid))
        assert.are.equal("Type their roll first: an open roll needs it.", row(3).rolls.hidden.note)
      end)

      it("refuses a roll that isn't a whole number from 1 to 100", function()
        raid()
        hide(1)
        local sent = #wow.sent
        for _, text in ipairs({ "0", "101", "-5", "12.5", "abc", "1e2" }) do
          assert.are.same({ nil, "bad roll" }, { giveHidden(1, "Mirel Stone", text) })
        end
        assert.are.same({}, wow.gives)
        assert.are.equal(sent, #wow.sent)
        assert.are.equal("Their roll must be a whole number from 1 to 100.", row(1).rolls.hidden.note)
        assert(giveHidden(1, "Mirel Stone", "100"))
      end)

      it("clears the refusal note once an award goes through", function()
        raid()
        hide(1)
        giveHidden(1, "Mirel Stone", "0")
        assert(giveHidden(1, "Mirel Stone", "5"))
        wow.closeLoot()
        raid()
        hide(1)
        assert.is_nil(row(1).rolls.hidden.note)
      end)

      it("refuses a name that isn't listed, and when the rolls aren't hidden", function()
        raid()
        hide(1)
        assert.are.same({ nil, "not listed" }, { giveHidden(1, "Nobody", "5") })
        assert.are.same({ nil, "not ready" }, { giveHidden(2, "Bram Ironvein", "5") })
        tie()
        assert.are.same({ nil, "not ready" }, { giveHidden(1, "Doran Vale", "5") })
      end)

      it("disables the name buttons in a boss fight", function()
        raid()
        hide(1)
        wow.bossFight(true)
        for _, e in ipairs(row(1).rolls.entries) do
          assert.are.same({ false, "Chat is locked until the fight ends" }, { e.enabled, e.tooltip })
        end
        assert.are.same({ nil, "fight" }, { giveHidden(1, "Mirel Stone", "5") })
        assert.are.same({}, wow.gives)
      end)
    end)
  end)
  describe("made-up reserves in practice mode (#107)", function()
    local function rows(model) return model.rows end

    it("gives each drop a case, from the group, like real reserves", function()
      setup({ code = "SA0001", bosses = tree().bosses, reserves = {} })
      wow.slash("/bf practice")
      drop({ { id = 1 }, { id = 2 }, { id = 3 }, { id = 4 }, { id = 5 }, { id = 6 } })
      local r = rows(ns.Popup.Build())
      assert.are.same({ "give", "Masterlooter" }, { r[1].action, r[1].winner })
      assert.are.same({ "roll", "hr" }, { r[2].action, r[2].mode })
      assert.are.same({ "roll", "sr" }, { r[3].action, r[3].mode })
      assert.are.same({ "give", "Tovin Hale", "sr" }, { r[4].action, r[4].winner, r[4].mode })
      assert.are.same({ "roll", "hr" }, { r[5].action, r[5].mode })
      assert.are.same("openroll", r[6].action)
    end)

    it("shows the absent and can't-receive holders as skipped, with the rules' reasons", function()
      setup({ code = "SA0001", bosses = tree().bosses, reserves = {} })
      wow.slash("/bf practice")
      drop({ { id = 1 }, { id = 2 }, { id = 3 }, { id = 4 } })
      local row = rows(ns.Popup.Build())[4]
      assert.are.same({ { name = "Bram Ironvein", reason = "not in raid" },
        { name = "Mirel Stone", reason = "the game won't let them receive this item (usually: not nearby"
          .. " when the boss died)" } }, row.skipped)
    end)

    it("keeps a window's made-up reserves on every redraw, and moves on with the next window", function()
      setup({ code = "SA0001", bosses = tree().bosses, reserves = {} })
      wow.slash("/bf practice")
      drop({ { id = 1 }, { id = 2 } })
      local first = rows(ns.Popup.Build())
      assert.are.same(first, rows(ns.Popup.Build()))
      wow.closeLoot()
      drop({ { id = 1 } })
      -- Item 1 was drop 0 in the first window; in the second it is drop 2.
      assert.are.equal("sr", rows(ns.Popup.Build())[1].mode)
    end)

    it("works with no raid loaded and hides the no reserves notice", function()
      setup()
      wow.slash("/bf practice")
      drop({ { id = 1 }, { id = 6 } })
      local model = ns.Popup.Build()
      assert.is_nil(model.notice)
      assert.is_nil(model.syncLink)
      assert.are.equal("give", model.rows[1].action)
      assert.are_not.equal("No reserves loaded", model.rows[2].note)
    end)

    it("can hand out with no raid loaded", function()
      setup()
      wow.slash("/bf practice")
      drop({ { id = 1 } })
      local row = ns.Popup.Build().rows[1]
      local attempt
      wow.click(function() attempt = ns.Popup.Give(row.slot, row.item, row.winner) end)
      assert.is_truthy(attempt)
      assert.is_true(ns.Records.Get(attempt.awardKey).practice)
    end)

    it("stays silent on a group chosen as not a guild run", function()
      setup({ code = "SA0001", bosses = tree().bosses, reserves = {} })
      wow.slash("/bf practice")
      assert.is_true(ns.Selection.ChooseOff())
      drop({ { id = 1 } })
      assert.are.same({ nil, "not a guild run" }, { ns.Popup.Build() })
    end)

    it("lists the made-up holders for Give to someone else", function()
      setup({ code = "SA0001", bosses = tree().bosses, reserves = {} })
      wow.slash("/bf practice")
      drop({ { id = 1 }, { id = 2 }, { id = 3 }, { id = 4 } })
      local row = ns.Popup.Build().rows[4]
      local attempt
      wow.click(function() attempt = ns.Popup.Give(row.slot, row.item, row.winner) end)
      wow.advance(ns.Tracking.confirmWait)
      assert.are.same({
        { char = "Bram Ironvein", user = "practice-bram ironvein", method = "HR", available = false,
          reason = "not in raid" },
        { char = "Mirel Stone", user = "practice-mirel stone", method = "HR", available = false,
          reason = "cannot receive" },
      }, ns.Popup.GiveElseList(attempt.awardKey))
    end)

    it("uses the drop's real reserves with practice mode off", function()
      setup({ code = "SA0001", bosses = tree().bosses,
        reserves = { [1] = { holder("Ashla Brightwater", "HR") } } })
      drop({ { id = 1 } })
      local row = ns.Popup.Build().rows[1]
      assert.are.same({ "give", "Ashla Brightwater" }, { row.action, row.winner })
    end)

    it("gives a solo player the open roll", function()
      setup({}, { "Masterlooter" })
      wow.slash("/bf practice")
      drop({ { id = 1, candidates = { "Masterlooter" } }, { id = 2, candidates = { "Masterlooter" } },
        { id = 3, candidates = { "Masterlooter" } }, { id = 4, candidates = { "Masterlooter" } },
        { id = 5, candidates = { "Masterlooter" } } })
      for _, row in ipairs(rows(ns.Popup.Build())) do assert.is_truthy(row.action) end
      assert.are.equal("openroll", rows(ns.Popup.Build())[4].action)
    end)
  end)
end)

-- Undo on a confirmed award (#40), from the Awards tab: the cases the tab's tests don't reach.
describe("Popup.Undo", function()
  local ns
  local LINK = "|cffa335ee|Hitem:1::::::::60:::::|h[Item 1]|h|r"

  before_each(function()
    ns = wow.start()
    wow.state.group = { "Masterlooter", "Ashla Brightwater" }
    wow.state.groupIsRaid = true
    wow.state.lootMethod = { "master", 0, 0 }
    wow.state.items[1] = { name = "Item 1", link = LINK, icon = 1 }
    ns.Raids.Load(assert(ns.Snapshot.Validate(tree({ code = "SA0001",
      reserves = { [1] = { holder("Ashla Brightwater", "HR") } } }), "0.1.0")), "pasted")
    assert(ns.Selection.ChooseRaid("raid00001"))
  end)

  local function given(fields)
    return assert(ns.Records.Award(fields or { boss = "luc", item = 1, char = "Ashla Brightwater",
      method = "HR" })).id
  end

  local function undo(key)
    local result
    wow.click(function() result = { ns.Popup.Choose(key, "undo") } end)
    return result
  end

  it("refuses an award not confirmed, announced or already voided, changing nothing", function()
    local announced = given()
    local unconfirmed = given()
    assert(ns.Records.NotConfirmed(unconfirmed))
    local voided = given()
    assert(ns.Records.Confirm(voided))
    assert(ns.Records.Void(voided, { reason = "traded" }))
    for _, key in ipairs({ announced, unconfirmed, voided }) do
      assert.are.same({ nil, "not undoable" }, undo(key))
      assert.are.equal("Only a confirmed award can be undone.", ns.Popup.Refusal(key))
    end
    assert.is_nil(ns.Records.Get(announced).voided)
    assert.are.equal("traded", ns.Records.Get(voided).voidReason)
    assert.are.equal(0, #wow.sent)
    assert.is_truthy(ns.log[#ns.log].text:find("^Undo for .* refused: not undoable"))
  end)

  it("refuses while a hand-out of it still waits for the game", function()
    wow.openLoot({ { id = 1, link = LINK, quality = 4, sourceGuid = "corpse1",
      candidates = wow.state.group } })
    wow.click(function() assert(ns.Popup.Give(1, 1, "Ashla Brightwater")) end)
    local key = ns.Raids.Awards("raid00001")[1].key
    assert(ns.Records.Confirm(key))
    local sent = #wow.sent
    assert.are.same({ nil, "handing out" }, undo(key))
    assert.is_nil(ns.Records.Get(key).voided)
    assert.are.equal(sent, #wow.sent)
  end)

  it("in a boss fight refuses with the Undo wording; the button is greyed with the pop-up's tooltip",
    function()
      local key = given()
      assert(ns.Records.Confirm(key))
      wow.bossFight(true)
      assert.are.same({ enabled = false, tooltip = "Posts a line, so it waits until the boss fight ends" },
        ns.Popup.UndoButton(key))
      assert.are.same({ nil, "undo fight" }, undo(key))
      assert.are.equal("Chat is locked in the boss fight. Undo waits until it ends.", ns.Popup.Refusal(key))
      wow.bossFight(false)
      assert.are.same({ enabled = true }, ns.Popup.UndoButton(key))
    end)

  it("undoes a confirmed award, clearing an earlier refusal; Undone with no reason", function()
    local key = given()
    assert(ns.Records.Confirm(key))
    wow.state.chatLockdown = true
    undo(key)
    wow.state.chatLockdown = false
    local op = assert(undo(key)[1])
    assert.are.same({ "void", nil }, { op.type, op.reason })
    assert.is_nil(ns.Popup.Refusal(key))
    assert.are.same({ channel = "RAID", text = "Undo: " .. LINK .. " is no longer awarded to Ashla"
      .. " Brightwater <BF1;V;SA0001;" .. op.id .. ";" .. key .. ">" }, wow.sent[#wow.sent])
  end)

  it("undoes a Disenchant/bank award with the line naming no winner", function()
    local key = given({ boss = "luc", item = 1, method = "DISENCHANT_BANK" })
    assert(ns.Records.Confirm(key))
    assert.is_truthy(undo(key)[1])
    assert.are.equal("Undo: " .. LINK .. " is no longer going to disenchant/bank",
      wow.sent[#wow.sent].text:match("^(.-) <BF1;"))
  end)
end)
