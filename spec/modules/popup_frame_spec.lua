local wow = require("spec.support.wow")

local function link(id) return "|cffa335ee|Hitem:" .. id .. "::::::::60:::::|h[Item " .. id .. "]|h|r" end

local function holder(char, kind, fields)
  fields = fields or {}
  return { user = fields.user or char:lower():gsub("%s", ""), char = char, kind = kind,
    trial = fields.trial or false }
end

local function tree(fields)
  local t = {
    formatVersion = 1, raid = "raid00001", code = "MC0001", env = "staging", name = "Molten Core",
    startsAt = 1792000000, durationMin = 240, generated = 1791990000,
    addon = { version = "0.1.0", url = "https://example.invalid/addon" },
    bosses = {
      { id = "luc", name = "Lucifron", trash = false, items = { 1, 2, 3, 6 } },
      { id = "tra", name = "Trash", trash = true, items = {} },
    },
    reserves = {}, awards = {},
  }
  for k, v in pairs(fields or {}) do t[k] = v end
  return t
end

describe("PopupFrame", function()
  local ns, pf

  local GROUP

  local function setup(fields, group)
    ns = wow.start()
    pf = ns.PopupFrame
    GROUP = group or { "Masterlooter", "Ashla Brightwater", "Doran Vale", "Bram Ironvein", "Mirel Stone" }
    wow.state.group = GROUP
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
      it.candidates = it.candidates or GROUP
    end
    wow.openLoot(items)
  end

  local function shownRows()
    local list = {}
    for _, row in ipairs(pf.rows()) do
      if row:IsShown() then list[#list + 1] = row end
    end
    return list
  end

  describe("showing and closing", function()
    it("shows for the loot master and closes with the loot window", function()
      setup({})
      drop({ { id = 1 } })
      assert.is_true(pf.frame:IsShown())
      wow.closeLoot()
      assert.is_false(pf.frame:IsShown())
    end)

    it("does not show for another officer, or when it is not a guild run", function()
      setup({})
      wow.state.lootMethod = { "master", 2, 0 }
      drop({ { id = 1 } })
      assert.is_false(pf.frame:IsShown())
      wow.state.lootMethod = { "master", 0, 0 }
      assert.is_true(ns.Selection.ChooseOff())
      drop({ { id = 1 } })
      assert.is_false(pf.frame:IsShown())
    end)

    it("stays shut for the loot window once the officer closes it, and comes back for the next", function()
      setup({})
      drop({ { id = 1 } })
      local close = pf.frame.close
      close.scripts.OnClick() -- the click runs the button's own script, then the add-on's hook
      for _, hook in ipairs(close.hooks.OnClick) do hook() end
      assert.is_false(pf.frame:IsShown())
      wow.closeLoot()
      drop({ { id = 1 } })
      assert.is_true(pf.frame:IsShown())
    end)
  end)

  describe("the states", function()
    it("draws a typical corpse (popup-typical)", function()
      setup({ reserves = { [1] = { holder("Ashla Brightwater", "HR") },
        [2] = { holder("Doran Vale", "SR") } } })
      drop({ { id = 1 }, { id = 2 }, { id = 3 } })
      assert.are.equal("Loot · Lucifron", pf.frame.title:GetText())
      assert.are.equal("3 items", pf.frame.count:GetText())
      assert.are.equal("Lucifron ▾", pf.frame.boss.label:GetText())
      local rows = shownRows()
      assert.are.equal(3, #rows)
      assert.are.same({ "HARD RESERVE", "Ashla Brightwater", "Give to Ashla Brightwater" },
        { rows[1].badgeText:GetText(), rows[1].beside:GetText(), rows[1].primary.label:GetText() })
      assert.are.same({ "SOFT RESERVE", "Give to Doran Vale" },
        { rows[2].badgeText:GetText(), rows[2].primary.label:GetText() })
      assert.are.same({ "OPEN ROLL", "Nobody reserved it · everyone can roll", "Call open roll" },
        { rows[3].badgeText:GetText(), rows[3].beside:GetText(), rows[3].primary.label:GetText() })
      for _, row in ipairs(rows) do
        assert.are.equal("D/B: choose ▾", row.db.label:GetText())
        assert.is_true(row.primary:IsEnabled() and row.db:IsEnabled())
      end
      assert.are.equal(link(1), rows[1].title:GetText())
      assert.is_truthy(pf.frame.foot:GetText():find("Reserves: Molten Core", 1, true))
      assert.is_false(pf.frame.notice:IsShown())
    end)

    it("lists every item with its contenders and skipped holders (popup-crowded, popup-page2)", function()
      local hr = {}
      for i = 1, 4 do hr[i] = holder("Raider " .. string.char(64 + i), "HR") end
      hr[#hr + 1] = holder("Kessa Moorfield", "HR")
      local group = { "Masterlooter", "Bram Ironvein", "Mirel Stone", "Doran Vale" }
      for i = 1, 4 do group[#group + 1] = "Raider " .. string.char(64 + i) end
      setup({ reserves = { [1] = hr, [6] = { holder("Bram Ironvein", "HR"), holder("Mirel Stone", "SR"),
        holder("Doran Vale", "SR") } } }, group)
      drop({ { id = 1 }, { id = 2 }, { id = 3 }, { id = 4 }, { id = 6 }, { id = 6 } })
      local rows = shownRows()
      assert.are.equal(6, #rows)
      assert.are.equal("6 items", pf.frame.count:GetText())
      assert.are.equal("HARD RESERVE ROLL-OFF", rows[1].badgeText:GetText())
      assert.are.equal("Raider A, Raider B, Raider C, Raider D", rows[1].detail:GetText())
      assert.are.equal("Skipped: Kessa Moorfield (not in raid)", rows[1].skipped:GetText())
      assert.are.equal("Call roll (4)", rows[1].primary.label:GetText())
      assert.are.equal(link(6) .. " · Copy 2 of 2", rows[6].title:GetText())
      assert.are.equal("Mirel Stone, Doran Vale · Copy 1 goes to the hard reserve", rows[6].detail:GetText())
      for i = 2, #rows do -- each row sits below the one before, so none is hidden under another
        assert.is_true(rows[i].points[1].y < rows[i - 1].points[1].y)
      end
    end)

    it("asks which boss, with Give and D/B greyed until one is picked (popup-boss)", function()
      setup({ reserves = { [3] = { holder("Ashla Brightwater", "HR") } },
        bosses = { { id = "luc", name = "Lucifron", trash = false, items = { 3, 6 } },
          { id = "mag", name = "Magmadar", trash = false, items = { 3, 6 } },
          { id = "tra", name = "Trash", trash = true, items = {} } } })
      ns.db.attribution = { raid00001 = { kills = { luc = 1792000000, mag = 1792000000 }, pulls = {},
        corpses = { other = 1792000100 } } }
      drop({ { id = 3, sourceGuid = "other" }, { id = 2, sourceGuid = "other" } })
      assert.are.equal("Loot · Trash", pf.frame.title:GetText())
      assert.are.equal("These items drop from more than one boss. Pick the boss before awarding.",
        pf.frame.notice:GetText())
      local row = shownRows()[1]
      assert.is_false(row.primary:IsEnabled())
      assert.is_false(row.db:IsEnabled())
      assert.is_true(shownRows()[2].primary:IsEnabled()) -- an open roll needs no boss
      assert.is_false(pf.menu:IsShown())
      pf.frame.boss.scripts.OnClick()
      assert.is_true(pf.menu:IsShown())
      assert.are.equal("Which boss dropped this?", pf.menu.title:GetText())
      pf.pickEntries()[2].scripts.OnClick()
      assert.is_false(pf.menu:IsShown())
      assert.are.equal("Loot · Magmadar", pf.frame.title:GetText())
      assert.is_false(pf.frame.notice:IsShown())
      row = shownRows()[1]
      assert.is_true(row.primary:IsEnabled() and row.db:IsEnabled())
    end)

    it("enables Give and D/B once Trash is picked", function()
      setup({ reserves = { [3] = { holder("Ashla Brightwater", "HR") } },
        bosses = { { id = "luc", name = "Lucifron", trash = false, items = { 3 } },
          { id = "mag", name = "Magmadar", trash = false, items = { 3 } },
          { id = "tra", name = "Trash", trash = true, items = {} } } })
      drop({ { id = 3 } })
      assert.is_false(shownRows()[1].primary:IsEnabled())
      pf.frame.boss.scripts.OnClick()
      pf.pickEntries()[3].scripts.OnClick()
      assert.are.equal("Trash ▾", pf.frame.boss.label:GetText())
      assert.is_true(shownRows()[1].primary:IsEnabled())
    end)

    it("says no reserves are loaded and links to the Sync tab (popup-no-reserves)", function()
      setup()
      drop({ { id = 1 }, { id = 2 } })
      assert.are.equal("No reserves loaded, so every item is an open roll.", pf.frame.notice:GetText())
      assert.are.equal("Load reserves", pf.frame.link.label:GetText())
      assert.are.equal("Reserves: none loaded", pf.frame.foot:GetText())
      for _, row in ipairs(shownRows()) do
        assert.are.equal("OPEN ROLL", row.badgeText:GetText())
        assert.are.equal("No reserves loaded · everyone can roll", row.beside:GetText())
        assert.are.equal("Call open roll", row.primary.label:GetText())
      end
      pf.frame.link.scripts.OnClick()
      assert.are.equal("Sync", ns.UI.selected)
      assert.is_true(ns.UI.tabs.Sync:GetParent():IsShown())
    end)

    it("hides rows left over from a longer corpse", function()
      setup({})
      drop({ { id = 1 }, { id = 2 }, { id = 3 } })
      wow.closeLoot()
      drop({ { id = 1 } })
      assert.are.equal(1, #shownRows())
      assert.are.equal("1 item", pf.frame.count:GetText())
    end)
  end)

  describe("names still loading", function()
    it("asks again after a wait and shows the winner once the name loads", function()
      setup({ reserves = { [1] = { holder("Ashla Brightwater", "HR") } } })
      drop({ { id = 1, candidates = { "Masterlooter", "Unknown" } } })
      local row = shownRows()[1]
      assert.are.equal("Give to Unknown", row.primary.label:GetText())
      assert.is_false(row.primary:IsEnabled())
      wow.advance(1)
      assert.are.equal("Give to Unknown", shownRows()[1].primary.label:GetText()) -- still loading
      wow.state.loot[1].candidates = { "Masterlooter", "Ashla Brightwater" }
      wow.advance(1)
      row = shownRows()[1]
      assert.are.equal("Give to Ashla Brightwater", row.primary.label:GetText())
      assert.is_true(row.primary:IsEnabled())
      wow.advance(5) -- nothing left to wait for
      assert.are.equal("Give to Ashla Brightwater", shownRows()[1].primary.label:GetText())
    end)

    it("stops asking when the loot window closes", function()
      setup({ reserves = { [1] = { holder("Ashla Brightwater", "HR") } } })
      drop({ { id = 1, candidates = { "Masterlooter", "Unknown" } } })
      wow.closeLoot()
      wow.state.loot = { { link = link(1), quality = 4, candidates = GROUP } }
      wow.advance(5)
      assert.is_false(pf.frame:IsShown())
    end)
  end)

  describe("giving (#38)", function()
    local function raid()
      setup({ code = "SA0001", reserves = { [1] = { holder("Ashla Brightwater", "HR") },
        [2] = { holder("Doran Vale", "SR") } },
        bosses = { { id = "lb_lucifron", name = "Lucifron", trash = false, items = { 1, 2, 3 } },
          { id = "lb_trash", name = "Trash", trash = true, items = {} } } })
    end

    local function click(button)
      wow.click(function() button.scripts.OnClick(button) end)
    end

    it("starts a roll-off on a Call roll or Call open roll click", function()
      setup({ code = "SA0001", reserves = { [1] = { holder("Ashla Brightwater", "HR"),
        holder("Doran Vale", "HR") } },
        bosses = { { id = "lb_lucifron", name = "Lucifron", trash = false, items = { 1, 2, 3 } },
          { id = "lb_trash", name = "Trash", trash = true, items = {} } } })
      drop({ { id = 1 }, { id = 3 } })
      local rows = shownRows()
      assert.are.equal("Call roll (2)", rows[1].primary.label:GetText())
      click(rows[1].primary)
      assert.are.equal(1, #wow.sent)
      assert.is_truthy(wow.sent[1].text:find("Ashla Brightwater and Doran Vale (hard reserve)", 1, true))
      assert.is_truthy(ns.Rolls.Result(1, 1))
      ns.Rolls.End(1, 1)
      click(shownRows()[2].primary)
      assert.is_truthy(wow.sent[2].text:find("everyone /roll", 1, true))
      assert.are.same({}, wow.gives)
    end)

    it("posts no roll call in a boss fight", function()
      setup({ code = "SA0001", reserves = { [1] = { holder("Ashla Brightwater", "HR"),
        holder("Doran Vale", "HR") } },
        bosses = { { id = "lb_lucifron", name = "Lucifron", trash = false, items = { 1, 2, 3 } },
          { id = "lb_trash", name = "Trash", trash = true, items = {} } } })
      drop({ { id = 1 } })
      local button = shownRows()[1].primary
      wow.bossFight(true)
      click(button)
      assert.are.same({}, wow.sent)
      assert.is_nil(ns.Rolls.Result(1, 1))
    end)

    it("hands out on a click and shows the row waiting for the game (handout-waiting)", function()
      raid()
      drop({ { id = 1 }, { id = 2 }, { id = 3 } })
      click(shownRows()[1].primary)
      assert.are.same({ { slot = 1, candidate = 2 } }, wow.gives)
      assert.are.equal(1, #wow.sent)
      local row = shownRows()[1]
      assert.are.equal("Handing out to Ashla Brightwater…", row.handout:GetText())
      assert.are.equal("Announced in raid chat. Waiting for the game to confirm (a few seconds).",
        row.handoutNote:GetText())
      -- In the design's bordered box, below the badge, holding the spinner and both lines.
      local box = row.box
      assert.is_true(box:IsShown())
      assert.are.same({ row, 40, -40 }, { box.points[1].relativeTo, box.points[1].x, box.points[1].y })
      for _, part in ipairs({ row.spinner, row.handout, row.handoutNote }) do
        assert.are.equal(box, part.points[1].relativeTo)
      end
      assert.are.equal(500, box:GetWidth())
      assert.is_true(box:GetHeight() > -row.handoutNote.points[1].y + 12)
      assert.is_true(row:GetHeight() >= 40 + box:GetHeight())
      assert.is_false(row.primary:IsShown() or row.db:IsShown())
      assert.are.equal("Ashla Brightwater", row.beside:GetText())
      local other = shownRows()[2] -- the other rows keep their buttons
      assert.is_true(other.primary:IsShown() and other.primary:IsEnabled())
      -- The game confirms: the slot empties and the row goes.
      wow.fire("LOOT_SLOT_CLEARED", 1)
      table.remove(wow.state.loot, 1)
      wow.fire("CHAT_MSG_LOOT", "Ashla Brightwater receives loot: " .. link(1) .. ".")
      assert.are.equal(2, #shownRows())
      assert.are.equal("Give to Doran Vale", shownRows()[1].primary.label:GetText())
      assert.is_false(shownRows()[1].box:IsShown())
    end)

    it("redraws instead of giving when the winner changed since the draw", function()
      setup({ code = "SA0001",
        reserves = { [1] = { holder("Ashla Brightwater", "HR"), holder("Doran Vale", "SR") } },
        bosses = { { id = "lb_lucifron", name = "Lucifron", trash = false, items = { 1 } },
          { id = "lb_trash", name = "Trash", trash = true, items = {} } } })
      drop({ { id = 1 } })
      assert.are.equal("Give to Ashla Brightwater", shownRows()[1].primary.label:GetText())
      wow.state.loot[1].candidates = { "Masterlooter", "Doran Vale" }
      click(shownRows()[1].primary)
      assert.are.same({}, wow.gives)
      assert.are.equal("Give to Doran Vale", shownRows()[1].primary.label:GetText())
    end)

    it("gives the buttons back when the game doesn't confirm", function()
      raid()
      drop({ { id = 1 } })
      click(shownRows()[1].primary)
      wow.advance(ns.Tracking.confirmWait)
      local row = shownRows()[1]
      assert.is_false(row.box:IsShown())
      assert.is_true(row.primary:IsShown())
    end)

    it("greys award and roll buttons in a fight, says why, enables them after (popup-fight)", function()
      raid()
      drop({ { id = 1 }, { id = 2 }, { id = 3 } })
      wow.bossFight(true)
      assert.are.equal("Boss fight in progress. The game locks chat for add-ons, so awards wait until"
        .. " it ends.", pf.frame.fight:GetText())
      assert.is_true(pf.frame.fight:IsShown())
      local rows = shownRows()
      for _, row in ipairs(rows) do
        assert.is_false(row.primary:IsEnabled())
        assert.is_false(row.db:IsEnabled())
      end
      rows[1].primary.scripts.OnEnter(rows[1].primary)
      assert.are.same({ "Chat is locked until the fight ends" }, _G.GameTooltip.lines)
      click(rows[1].primary)
      assert.are.same({}, wow.gives)
      assert.are.same({}, wow.sent)
      wow.bossFight(false)
      assert.is_false(pf.frame.fight:IsShown())
      for _, row in ipairs(shownRows()) do assert.is_true(row.primary:IsEnabled() and row.db:IsEnabled()) end
      _G.GameTooltip.lines = {}
      shownRows()[1].primary.scripts.OnEnter(shownRows()[1].primary)
      assert.are.same({}, _G.GameTooltip.lines) -- no tooltip once the fight is over
    end)

    it("keeps an unavailable winner's button greyed and unclickable, with why (popup-unavailable)", function()
      raid()
      drop({ { id = 1, candidates = { "Masterlooter", "Unknown" } } })
      local row = shownRows()[1]
      assert.are.equal("Give to Unknown", row.primary.label:GetText())
      assert.is_false(row.primary:IsEnabled())
      assert.are.equal("Ashla Brightwater's name hasn't loaded yet (shown as \"Unknown\")."
        .. " Try again in a moment.", row.skipped:GetText())
      click(row.primary)
      assert.are.same({}, wow.gives)
      assert.are.same({}, wow.sent)
    end)
  end)

  describe("disenchant/bank (#39)", function()
    local function raid(group)
      setup({ code = "SA0001", reserves = { [1] = { holder("Ashla Brightwater", "HR") } },
        bosses = { { id = "lb_lucifron", name = "Lucifron", trash = false, items = { 1, 2, 3 } },
          { id = "lb_trash", name = "Trash", trash = true, items = {} } } }, group)
    end

    local function click(button, mouseButton)
      wow.click(function() button.scripts.OnClick(button, mouseButton or "LeftButton") end)
    end

    local function shownEntries()
      local list = {}
      for _, entry in ipairs(pf.dbEntries()) do
        if entry:IsShown() then list[#list + 1] = entry end
      end
      return list
    end

    local function entryNamed(name)
      for _, entry in ipairs(shownEntries()) do
        if entry.label:GetText() == name then return entry end
      end
    end

    it("opens the list on a click with no pick; choosing a name remembers it and gives nothing", function()
      raid()
      drop({ { id = 1 } })
      local db = shownRows()[1].db
      assert.are.equal("D/B: choose ▾", db.label:GetText())
      db.scripts.OnEnter(db)
      assert.are.same({ "Disenchant/bank: choose the character to give to." }, _G.GameTooltip.lines)
      click(db)
      assert.is_true(pf.dbList:IsShown())
      assert.are.equal("Disenchant/bank: give to", pf.dbList.title:GetText())
      assert.are.equal("Remembered for this raid.", pf.dbList.note:GetText())
      assert.is_false(pf.dbList.more:IsShown())
      local names = {}
      for i, entry in ipairs(shownEntries()) do
        names[i] = entry.label:GetText()
        assert.is_false(entry.tick:IsShown())
      end
      assert.are.same({ "Ashla Brightwater", "Bram Ironvein", "Doran Vale", "Masterlooter", "Mirel Stone" },
        names)
      click(entryNamed("Doran Vale"))
      assert.is_false(pf.dbList:IsShown())
      assert.are.same({}, wow.gives)
      assert.are.same({}, wow.sent)
      assert.are.equal("D/B: Doran ▾", shownRows()[1].db.label:GetText())
      -- Opened again, the pick is ticked.
      click(shownRows()[1].db, "RightButton")
      assert.is_true(entryNamed("Doran Vale").tick:IsShown())
      assert.is_false(entryNamed("Mirel Stone").tick:IsShown())
    end)

    it("gives to the pick on a click; right-click or Shift-click opens the list instead", function()
      raid()
      drop({ { id = 1 }, { id = 2 } })
      ns.Popup.SetDBPick("Doran Vale")
      pf.Refresh()
      local db = shownRows()[1].db
      _G.GameTooltip.lines = {}
      db.scripts.OnEnter(db)
      assert.are.same({ "Disenchant/bank: give to Doran Vale. Right-click or Shift-click to choose someone"
        .. " else." }, _G.GameTooltip.lines)
      click(db, "RightButton")
      assert.is_true(pf.dbList:IsShown())
      assert.are.same({}, wow.gives)
      click(db, "RightButton") -- a second right-click closes it
      assert.is_false(pf.dbList:IsShown())
      wow.state.shift = true
      click(db)
      assert.is_true(pf.dbList:IsShown())
      assert.are.same({}, wow.gives)
      wow.state.shift = false
      click(db)
      assert.is_false(pf.dbList:IsShown())
      assert.are.same({ { slot = 1, candidate = 3 } }, wow.gives)
      assert.are.equal(1, #wow.sent)
      assert.is_truthy(wow.sent[1].text:find("→ disenchant/bank <BF1;A;SA0001;", 1, true))
      local row = shownRows()[1]
      assert.are.equal("Handing out to Doran Vale…", row.handout:GetText())
      assert.is_false(row.db:IsShown())
      -- The next row is one click too.
      click(shownRows()[2].db)
      assert.are.equal(2, #wow.gives)
    end)

    it("shows twelve names and scrolls the rest (popup-db)", function()
      local group = { "Masterlooter" }
      for i = 1, 24 do group[#group + 1] = string.format("Member %02d", i) end
      raid(group)
      drop({ { id = 1 } })
      ns.Popup.SetDBPick("Member 02")
      pf.Refresh()
      click(shownRows()[1].db, "RightButton")
      assert.are.equal(12, #shownEntries())
      assert.are.equal("Masterlooter", shownEntries()[1].label:GetText())
      assert.is_true(shownEntries()[3].tick:IsShown())
      assert.is_true(pf.dbList.more:IsShown())
      assert.is_truthy(pf.dbList.more:GetText():find("13 more · scroll", 1, true))
      pf.dbList.scripts.OnMouseWheel(pf.dbList, -1)
      assert.are.equal("Member 01", shownEntries()[1].label:GetText())
      assert.is_truthy(pf.dbList.more:GetText():find("12 more · scroll", 1, true))
      for _ = 1, 30 do pf.dbList.scripts.OnMouseWheel(pf.dbList, -1) end
      assert.are.equal("Member 13", shownEntries()[1].label:GetText())
      assert.is_truthy(pf.dbList.more:GetText():find("13 more · scroll", 1, true)) -- now above
      assert.is_truthy(pf.dbList.more:GetText():find("Arrow-Up", 1, true))
      click(entryNamed("Member 20"))
      assert.are.equal("Member 20", ns.Popup.DBPick())
      assert.are.same({}, wow.gives)
    end)

    it("says why on the row when the pick can't receive the item", function()
      raid()
      drop({ { id = 1, candidates = { "Masterlooter", "Ashla Brightwater" } } })
      ns.Popup.SetDBPick("Doran Vale")
      pf.Refresh()
      click(shownRows()[1].db)
      assert.are.same({}, wow.gives)
      assert.are.equal("The game won't let Doran Vale receive this item (usually: not nearby when the boss"
        .. " died). Right-click D/B to choose someone else.", shownRows()[1].skipped:GetText())
    end)

    it("is greyed in a boss fight, says why, and closes an open list", function()
      raid()
      drop({ { id = 1 } })
      ns.Popup.SetDBPick("Doran Vale")
      pf.Refresh()
      click(shownRows()[1].db, "RightButton")
      assert.is_true(pf.dbList:IsShown())
      wow.bossFight(true)
      local db = shownRows()[1].db
      assert.is_false(db:IsEnabled())
      assert.is_false(pf.dbList:IsShown())
      _G.GameTooltip.lines = {}
      db.scripts.OnEnter(db)
      assert.are.same({ "Chat is locked until the fight ends" }, _G.GameTooltip.lines)
      click(db)
      click(db, "RightButton")
      assert.is_false(pf.dbList:IsShown())
      assert.are.same({}, wow.gives)
      assert.are.same({}, wow.sent)
    end)
  end)
end)
