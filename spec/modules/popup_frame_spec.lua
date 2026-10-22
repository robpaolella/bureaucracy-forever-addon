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

    it("marks practice mode in the title and the foot, redrawn when it switches (practice)", function()
      setup({ reserves = { [1] = { holder("Ashla Brightwater", "HR") } } })
      drop({ { id = 1 } })
      wow.slash("/bf practice")
      assert.are.equal("[Practice] Loot · Lucifron", pf.frame.title:GetText())
      assert.is_truthy(pf.frame.foot:GetText():find("^Reserves: Molten Core.* · |cffffd100practice|r$"))
      wow.slash("/bf practice")
      assert.are.equal("Loot · Lucifron", pf.frame.title:GetText())
      assert.is_nil(pf.frame.foot:GetText():find("practice", 1, true))
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

    it("swaps the waiting box for the not confirmed choices when the game doesn't confirm", function()
      raid()
      drop({ { id = 1 } })
      click(shownRows()[1].primary)
      wow.advance(ns.Tracking.confirmWait)
      local row = shownRows()[1]
      assert.is_false(row.box:IsShown())
      assert.is_false(row.primary:IsShown() or row.db:IsShown())
      assert.is_true(row.ncBox:IsShown())
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

  describe("not confirmed (#95)", function()
    local RESERVES = { [1] = { holder("Ashla Brightwater", "HR"), holder("Doran Vale", "SR"),
      holder("Mirel Stone", "SR"), holder("Tovin Hale", "SR") } }

    local function click(button)
      wow.click(function() button.scripts.OnClick(button) end)
    end

    -- Item 1 given to Ashla and not confirmed; Mirel isn't in the raid. Returns the row.
    local function unconfirmed()
      setup({ code = "SA0001", reserves = RESERVES,
        bosses = { { id = "lb_lucifron", name = "Lucifron", trash = false, items = { 1, 2, 3 } },
          { id = "lb_trash", name = "Trash", trash = true, items = {} } } },
        { "Masterlooter", "Ashla Brightwater", "Doran Vale", "Tovin Hale" })
      drop({ { id = 1 }, { id = 2 } })
      click(shownRows()[1].primary)
      wow.advance(ns.Tracking.confirmWait)
      return shownRows()[1]
    end

    local function texts(box)
      local list = {}
      for i, b in ipairs(box.buttons) do list[i] = { b.label:GetText(), b:IsEnabled() } end
      return list
    end

    it("draws the design's state: the message, three buttons and the hint, no row buttons", function()
      local row = unconfirmed()
      local box = row.ncBox
      assert.is_true(box:IsShown())
      assert.is_false(row.box:IsShown() or row.list:IsShown() or row.primary:IsShown() or row.db:IsShown())
      assert.are.equal("The game didn't confirm that Ashla Brightwater got it. They may be too far away, or"
        .. " their bags are full.", box.text:GetText())
      assert.are.same({ { "Try again", true }, { "Give to someone else", true }, { "Not handed out", true } },
        texts(box))
      assert.are.equal("Try again posts nothing. Give to someone else posts one correction line, and Not"
        .. " handed out posts an undo line. If you close this, it waits in the Awards tab as"
        .. " \"not confirmed\".", box.hint:GetText())
      assert.is_true(box.warnEdge:GetHeight() > box.text:GetStringHeight())
      assert.is_true(box.buttons[1].points[1].y < -box.warnEdge:GetHeight())
      assert.are.equal("", box.refusal:GetText())
      assert.is_false(box.refusal:IsShown())
      assert.are.same({ row, 40 }, { box.points[1].relativeTo, box.points[1].x })
      assert.is_true(row:GetHeight() >= 40 + box:GetHeight())
      -- The other rows are unaffected.
      assert.are.equal("Call open roll", shownRows()[2].primary.label:GetText())
    end)

    it("Try again hands out once more, posts nothing and shows the waiting box", function()
      local row = unconfirmed()
      local sent, gives = #wow.sent, #wow.gives
      click(row.ncBox.buttons[1])
      assert.are.equal(gives + 1, #wow.gives)
      assert.are.equal(sent, #wow.sent)
      row = shownRows()[1]
      assert.is_true(row.box:IsShown())
      assert.is_false(row.ncBox:IsShown())
    end)

    it("Not handed out voids the award, posts the undo line and clears the state", function()
      local row = unconfirmed()
      click(row.ncBox.buttons[3])
      assert.are.equal(2, #wow.sent)
      assert.is_truthy(wow.sent[2].text:find("Undo:", 1, true))
      assert.is_false(shownRows()[1].ncBox:IsShown())
      assert.is_true(shownRows()[1].primary:IsShown())
    end)

    it("Give to someone else opens the list: contenders, methods, not in raid greyed (give-else)", function()
      local row = unconfirmed()
      click(row.ncBox.buttons[2])
      row = shownRows()[1]
      local list = row.list
      assert.is_true(list:IsShown())
      assert.is_false(row.ncBox:IsShown())
      assert.are.equal("Give " .. link(1) .. " to someone else", list.title:GetText())
      local e1, e2, e3 = list.entries[1], list.entries[2], list.entries[3]
      assert.are.same({ "Doran Vale", "SOFT RESERVE", true, true }, { e1.name:GetText(), e1.method:GetText(),
        e1.give:IsShown(), e1.give:IsEnabled() })
      assert.are.same({ "Mirel Stone", "not in raid", false }, { e2.name:GetText(), e2.method:GetText(),
        e2.give:IsShown() })
      assert.are.same({ "Tovin Hale", "SOFT RESERVE", true }, { e3.name:GetText(), e3.method:GetText(),
        e3.give:IsShown() })
      assert.is_nil(list.entries[4])
      -- Each method sits on a badge and each name has a separator line; the greyed one has no badge.
      assert.are.same({ true, false, true }, { e1.badge:IsShown(), e2.badge:IsShown(), e3.badge:IsShown() })
      assert.is_true(e1.line:IsShown() and e3.line:IsShown())
      assert.is_false(list.empty:IsShown())
      assert.are.equal("Posts one correction line: Correction: " .. link(1)
        .. " → their name, not Ashla Brightwater.", list.hint:GetText())
      assert.is_true(row:GetHeight() >= 40 + list:GetHeight())
    end)

    it("Back closes the list; choosing a name hands out, posts the correction line and closes it", function()
      local row = unconfirmed()
      click(row.ncBox.buttons[2])
      click(row.list.back)
      assert.is_true(shownRows()[1].ncBox:IsShown())
      click(row.ncBox.buttons[2])
      click(row.list.entries[1].give)
      assert.is_truthy(wow.sent[2].text:find("Correction:", 1, true))
      assert.are.equal(1, wow.gives[2].slot)
      row = shownRows()[1]
      assert.is_false(row.list:IsShown() or row.ncBox:IsShown())
      assert.is_true(row.box:IsShown())
    end)

    it("the list ends with the Disenchant/bank line: the pick's name and Give (give-else, #96)", function()
      local row = unconfirmed()
      -- Tovin also holds a soft reserve: the line must still give as Disenchant/bank.
      assert.is_true(ns.Popup.SetDBPick("Tovin Hale"))
      click(row.ncBox.buttons[2])
      local list = shownRows()[1].list
      local db = list.db
      assert.are.same({ "Disenchant/bank", "Tovin Hale", true, true, true },
        { db.label:GetText(), db.name:GetText(), db.name:IsShown(), db.give:IsShown(), db.give:IsEnabled() })
      assert.are.equal("Give", db.give.label:GetText())
      -- It sits below the last reserve holder, inside the box, above the hint.
      local last = list.entries[3].name.points[1].y
      assert.is_true(db.label.points[1].y < last)
      assert.is_true(list.hint.points[1].y < db.label.points[1].y)
      click(db.give)
      assert.are.same({ slot = 1, candidate = 4 }, wow.gives[2])
      assert.is_truthy(wow.sent[2].text:find("→ disenchant/bank, not Ashla Brightwater <", 1, true))
      local key = ns.Records.Ops("raid00001")[3].award.id
      assert.are.equal("DISENCHANT_BANK", ns.Records.Get(key).method)
      row = shownRows()[1]
      assert.is_false(row.list:IsShown() or row.ncBox:IsShown())
      assert.is_true(row.box:IsShown())
    end)

    it("the open roll line calls the roll; its Give replaces the award (give-else, #118)", function()
      local row = unconfirmed()
      assert.is_true(ns.Popup.SetDBPick("Tovin Hale"))
      click(row.ncBox.buttons[2])
      local list = shownRows()[1].list
      local open = list.open
      assert.are.same({ "Open roll", "everyone can roll", "Call open roll", true, true },
        { open.label:GetText(), open.text:GetText(), open.call.label:GetText(), open.call:IsShown(),
          open.call:IsEnabled() })
      -- It sits between the last reserve holder and the Disenchant/bank line, as the design draws it.
      assert.is_true(open.label.points[1].y < list.entries[3].name.points[1].y)
      assert.is_true(list.db.label.points[1].y < open.label.points[1].y)
      click(open.call)
      assert.are.equal("Open roll for " .. link(1) .. ": everyone /roll", wow.sent[2].text)
      wow.fire("CHAT_MSG_SYSTEM", "Doran Vale rolls 87 (1-100)")
      row = shownRows()[1]
      assert.is_false(row.list:IsShown())
      assert.is_true(row.rollBox:IsShown() and row.ncBox:IsShown())
      assert.are.equal("Rolls (everyone)", row.rollBox.heading:GetText())
      assert.are.same({ "Give to Doran Vale (87)", true },
        { row.primary.label:GetText(), row.primary:IsEnabled() })
      assert.is_false(row.db:IsShown())
      assert.are.equal("not-confirmed", ns.Records.Get(ns.Records.Ops("raid00001")[1].id).state)
      click(row.primary)
      assert.are.equal(3, #wow.sent)
      assert.is_truthy(wow.sent[3].text:find("^Correction: .* → Doran Vale %(open roll, 87%), not Ashla"))
      local replace = ns.Records.Ops("raid00001")[3]
      assert.are.same({ "replace", "OPEN_ROLL", 87 },
        { replace.type, replace.award.method, replace.award.roll })
      row = shownRows()[1]
      assert.is_true(row.box:IsShown())
      assert.is_false(row.rollBox:IsShown() or row.ncBox:IsShown())
    end)

    it("a hidden roll's name button replaces the award with the typed roll (#118)", function()
      local row = unconfirmed()
      click(row.ncBox.buttons[2])
      click(shownRows()[1].list.open.call)
      wow.fire("CHAT_MSG_SYSTEM", wow.secret)
      row = shownRows()[1]
      row.rollBox.rollEdit:SetText("64")
      local doran
      for _, b in ipairs(row.rollBox.hiddenNames) do
        if b.pick == "Doran Vale" then doran = b end
      end
      click(doran)
      local replace = ns.Records.Ops("raid00001")[3]
      assert.are.same({ "replace", "Doran Vale", 64 },
        { replace.type, replace.award.char, replace.award.roll })
    end)

    it("greys Call open roll in a boss fight, with the fight tooltip", function()
      local row = unconfirmed()
      click(row.ncBox.buttons[2])
      wow.bossFight(true)
      local open = shownRows()[1].list.open
      assert.is_false(open.call:IsEnabled())
      assert.are.equal("Posts a line, so it waits until the boss fight ends", open.call.tip)
      click(open.call)
      assert.are.equal(1, #wow.sent)
      wow.bossFight(false)
    end)

    it("with no D/B pick, the line is greyed, \"choose first\", and its Give does nothing", function()
      local row = unconfirmed()
      click(row.ncBox.buttons[2])
      local db = shownRows()[1].list.db
      assert.are.same({ "Disenchant/bank: choose first", false, true, false },
        { db.label:GetText(), db.name:IsShown(), db.give:IsShown(), db.give:IsEnabled() })
      assert.are.equal("Disenchant/bank: choose the character to give to.", db.give.tip)
      click(db.give)
      assert.are.equal(1, #wow.gives)
      assert.are.equal(1, #wow.sent)
    end)

    it("keeps the list open on a refused Give and shows why, naming the pick", function()
      local row = unconfirmed()
      assert.is_true(ns.Popup.SetDBPick("Tovin Hale"))
      click(row.ncBox.buttons[2])
      assert.is_false(shownRows()[1].list.refusal:IsShown())
      wow.state.loot[1].candidates = { "Masterlooter", "Ashla Brightwater", "Doran Vale" }
      click(shownRows()[1].list.db.give)
      local list = shownRows()[1].list
      assert.is_true(list:IsShown())
      assert.are.equal("The game won't let Tovin Hale receive this item (usually: not nearby when the boss"
        .. " died). Right-click D/B to choose someone else.", list.refusal:GetText())
      assert.is_true(list.refusal:IsShown())
      assert.is_true(list.hint.points[1].y < list.refusal.points[1].y)
      assert.are.equal(1, #wow.gives)
      assert.are.equal(1, #wow.sent)
    end)

    it("greys the Disenchant/bank line's Give in a boss fight, with the fight tooltip", function()
      local row = unconfirmed()
      assert.is_true(ns.Popup.SetDBPick("Tovin Hale"))
      click(row.ncBox.buttons[2])
      wow.bossFight(true)
      local db = shownRows()[1].list.db
      assert.are.same({ "Tovin Hale", false }, { db.name:GetText(), db.give:IsEnabled() })
      assert.are.equal("Posts a line, so it waits until the boss fight ends", db.give.tip)
      click(db.give)
      assert.are.equal(1, #wow.gives)
      wow.bossFight(false)
    end)

    it("draws no Disenchant/bank line for a Disenchant/bank award", function()
      setup({ code = "SA0001", reserves = RESERVES,
        bosses = { { id = "lb_lucifron", name = "Lucifron", trash = false, items = { 1, 2, 3 } },
          { id = "lb_trash", name = "Trash", trash = true, items = {} } } },
        { "Masterlooter", "Ashla Brightwater", "Doran Vale", "Tovin Hale" })
      assert.is_true(ns.Popup.SetDBPick("Doran Vale"))
      drop({ { id = 1 } })
      click(shownRows()[1].db)
      wow.advance(ns.Tracking.confirmWait)
      click(shownRows()[1].ncBox.buttons[2])
      local list = shownRows()[1].list
      assert.is_false(list.db.label:IsShown() or list.db.give:IsShown() or list.db.line:IsShown())
      assert.are.equal("Ashla Brightwater", list.entries[1].name:GetText())
    end)

    it("shows why a choice was refused in the row", function()
      local row = unconfirmed()
      wow.state.loot[1].candidates = { "Masterlooter", "Doran Vale" }
      click(row.ncBox.buttons[1])
      row = shownRows()[1]
      assert.are.equal("The game won't let them receive it now (usually: not nearby when the boss died).",
        row.ncBox.refusal:GetText())
      assert.is_true(row.ncBox.refusal:IsShown())
      assert.are.equal(1, #wow.gives)
    end)

    it("greys the buttons that post a line in a boss fight, and draws them again after", function()
      local row = unconfirmed()
      click(row.ncBox.buttons[2])
      wow.bossFight(true)
      row = shownRows()[1]
      assert.is_false(row.list.entries[1].give:IsEnabled())
      click(row.list.back)
      assert.are.same({ { "Try again", true }, { "Give to someone else", false },
        { "Not handed out", false } }, texts(shownRows()[1].ncBox))
      local sent = #wow.sent
      click(shownRows()[1].ncBox.buttons[3])
      assert.are.equal(sent, #wow.sent)
      click(shownRows()[1].ncBox.buttons[1])
      assert.are.equal(2, #wow.gives)
      wow.bossFight(false)
    end)

    it("clears the state when the game confirms late", function()
      local row = unconfirmed()
      wow.fire("LOOT_SLOT_CLEARED", 1)
      wow.fire("CHAT_MSG_LOOT", "Ashla Brightwater receives loot: " .. link(1) .. ".")
      assert.is_false(row.ncBox:IsShown())
      assert.is_true(shownRows()[1].primary:IsShown())
    end)

    it("leaves the award not confirmed when the pop-up closes", function()
      unconfirmed()
      local key = ns.Popup.Build().rows[1].notConfirmed.key
      wow.fire("LOOT_CLOSED")
      assert.is_false(pf.frame:IsShown())
      assert.are.equal("not-confirmed", ns.Records.Get(key).state)
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

  describe("the roll list (#90)", function()
    local function click(button)
      wow.click(function() button.scripts.OnClick(button) end)
    end

    local function roll(name, n)
      wow.fire("CHAT_MSG_SYSTEM", name .. " rolls " .. n .. " (1-100)")
    end

    local function called()
      setup({ code = "SA0001", reserves = { [1] = { holder("Ashla Brightwater", "HR"),
        holder("Doran Vale", "HR"), holder("Mirel Stone", "HR") } },
        bosses = { { id = "lb_lucifron", name = "Lucifron", trash = false, items = { 1, 2, 3 } },
          { id = "lb_trash", name = "Trash", trash = true, items = {} } } })
      drop({ { id = 1 } })
      click(shownRows()[1].primary)
    end

    it("draws the list and redraws as each roll arrives (roll-called)", function()
      called()
      local row = shownRows()[1]
      local box = row.rollBox
      assert.is_true(box:IsShown())
      assert.are.same({ "Rolls (hard reserve holders only)", "0 of 3 rolled" },
        { box.heading:GetText(), box.count:GetText() })
      assert.are.same({ "Give", false }, { row.primary.label:GetText(), row.primary:IsEnabled() })
      roll("Mirel Stone", 87)
      roll("Quill Ashby", 99)
      roll("Ashla Brightwater", 42)
      roll("Ashla Brightwater", 96)
      assert.are.equal("2 of 3 rolled", box.count:GetText())
      assert.are.same({ "Mirel Stone", "87", "●" },
        { box.names[1].name:GetText(), box.names[1].roll:GetText(), box.names[1].dot:GetText() })
      assert.are.same({ "Ashla Brightwater", "42", "○" },
        { box.names[2].name:GetText(), box.names[2].roll:GetText(), box.names[2].dot:GetText() })
      assert.are.same({ "Doran Vale", "waiting" },
        { box.names[3].name:GetText(), box.names[3].roll:GetText() })
      assert.are.equal("Quill Ashby (not eligible)", box.ignored[1].name:GetText())
      assert.are.same({ "99", true }, { box.ignored[1].roll:GetText(), box.ignored[1].strike:IsShown() })
      assert.are.equal("Ashla Brightwater (second roll, the first counts)", box.ignored[2].name:GetText())
      assert.are.same({ "Give to Mirel Stone (87)", true },
        { row.primary.label:GetText(), row.primary:IsEnabled() })
      assert.are.equal("or click another name", row.rollHint:GetText())
    end)

    it("moves the pick on a click on a name, and gives to it", function()
      called()
      roll("Mirel Stone", 87)
      roll("Ashla Brightwater", 42)
      click(shownRows()[1].rollBox.names[2])
      local row = shownRows()[1]
      assert.are.equal("Give to Ashla Brightwater (42)", row.primary.label:GetText())
      click(row.primary)
      assert.are.equal(1, #wow.gives)
      local award = ns.Records.Ops("raid00001")[1]
      assert.are.same({ "Ashla Brightwater", 42, "HR" }, { award.char, award.roll, award.method })
      assert.is_false(shownRows()[1].rollBox:IsShown())
      assert.is_true(shownRows()[1].box:IsShown()) -- handing out
    end)

    it("greys Give in a boss fight", function()
      called()
      roll("Mirel Stone", 87)
      wow.bossFight(true)
      local row = shownRows()[1]
      assert.is_false(row.primary:IsEnabled())
      click(row.primary)
      assert.are.same({}, wow.gives)
    end)

    it("draws the list in no row before a roll is called", function()
      setup({ code = "SA0001", reserves = { [1] = { holder("Ashla Brightwater", "HR"),
        holder("Doran Vale", "HR") } },
        bosses = { { id = "lb_lucifron", name = "Lucifron", trash = false, items = { 1, 2, 3 } },
          { id = "lb_trash", name = "Trash", trash = true, items = {} } } })
      drop({ { id = 1 } })
      assert.is_false(shownRows()[1].rollBox:IsShown())
      assert.are.equal("Call roll (2)", shownRows()[1].primary.label:GetText())
    end)
  end)
  describe("ties and hidden rolls (#102)", function()
    local function click(button)
      wow.click(function() button.scripts.OnClick(button) end)
    end

    local function roll(name, n)
      wow.fire("CHAT_MSG_SYSTEM", name .. " rolls " .. n .. " (1-100)")
    end

    local function called(id)
      setup({ code = "SA0001", reserves = { [1] = { holder("Ashla Brightwater", "HR"),
        holder("Doran Vale", "HR"), holder("Mirel Stone", "HR") } },
        bosses = { { id = "lb_lucifron", name = "Lucifron", trash = false, items = { 1, 2, 3 } },
          { id = "lb_trash", name = "Trash", trash = true, items = {} } } })
      drop({ { id = id or 1 } })
      click(shownRows()[1].primary)
    end

    local function tie()
      called()
      roll("Doran Vale", 87)
      roll("Mirel Stone", 87)
      roll("Ashla Brightwater", 40)
    end

    local function hidden(id)
      called(id)
      wow.fire("CHAT_MSG_SYSTEM", wow.secret)
      return shownRows()[1].rollBox
    end

    it("draws a tie: the warning bar, the tied names, Re-roll the tie and its line (roll-tie)", function()
      tie()
      local box = shownRows()[1].rollBox
      assert.are.equal("Tie at 87: Doran Vale and Mirel Stone", box.warn:GetText())
      assert.is_true(box.warn:IsShown())
      assert.are.same({ "Doran Vale", "Mirel Stone", "Ashla Brightwater" },
        { box.names[1].name:GetText(), box.names[2].name:GetText(), box.names[3].name:GetText() })
      assert.are.same({ "Re-roll the tie", true }, { box.reroll.label:GetText(), box.reroll:IsEnabled() })
      local hint = box.rerollHint:GetText()
      assert.is_truthy(hint:find("Doran Vale and Mirel Stone, roll again", 1, true))
      assert.are.equal("Posts: Tie for", hint:sub(1, 14))
      assert.are.same({ "Give", false },
        { shownRows()[1].primary.label:GetText(), shownRows()[1].primary:IsEnabled() })
    end)

    it("re-rolls the tie on a click, and the list returns to the roll-called list", function()
      tie()
      local sent = #wow.sent
      click(shownRows()[1].rollBox.reroll)
      assert.are.equal(sent + 1, #wow.sent)
      assert.is_truthy(wow.sent[#wow.sent].text:find("Tie for", 1, true))
      local box = shownRows()[1].rollBox
      assert.is_false(box.warn:IsShown())
      assert.is_false(box.reroll:IsShown())
      assert.are.equal("Rolls (hard reserve holders only)", box.heading:GetText())
      assert.are.same({ "Doran Vale", "waiting" },
        { box.names[1].name:GetText(), box.names[1].roll:GetText() })
      roll("Doran Vale", 70)
      roll("Mirel Stone", 20)
      assert.are.equal("Give to Doran Vale (70)", shownRows()[1].primary.label:GetText())
    end)

    it("keeps the list as it was when Rolls refuses the re-roll, and logs it", function()
      tie()
      local reroll = ns.Rolls.Reroll
      ns.Rolls.Reroll = function() return nil, "no tie" end
      local before, sent = shownRows()[1].rollBox.warn:GetText(), #wow.sent
      click(shownRows()[1].rollBox.reroll)
      ns.Rolls.Reroll = reroll
      assert.are.equal(sent, #wow.sent)
      assert.are.equal(before, shownRows()[1].rollBox.warn:GetText())
      assert.is_true(shownRows()[1].rollBox.reroll:IsShown())
      assert.is_truthy(ns.log[#ns.log].text:find(" refused: no tie", 1, true))
      assert.is_truthy(ns.log[#ns.log].text:find("Re-roll for", 1, true))
    end)

    it("disables Re-roll the tie in a boss fight, with the tooltip", function()
      tie()
      wow.bossFight(true)
      local reroll = shownRows()[1].rollBox.reroll
      assert.is_false(reroll:IsEnabled())
      assert.are.equal("Chat is locked until the fight ends", reroll.tip)
      local sent = #wow.sent
      click(reroll)
      assert.are.equal(sent, #wow.sent)
    end)

    it("draws hidden rolls: the warning, the names as buttons and the roll box (roll-hidden)", function()
      local box = hidden()
      assert.are.equal("The game is hiding rolls from add-ons right now."
        .. " Watch chat, then click the winner.", box.warn:GetText())
      assert.are.same({ "Ashla Brightwater", "Doran Vale", "Mirel Stone" },
        { box.hiddenNames[1].label:GetText(), box.hiddenNames[2].label:GetText(),
          box.hiddenNames[3].label:GetText() })
      assert.is_true(box.hiddenNames[1]:IsEnabled())
      assert.are.equal("Their roll (optional):", box.rollLabel:GetText())
      assert.is_true(box.rollEdit:IsShown())
      local row = shownRows()[1]
      assert.is_false(row.primary:IsShown()) -- no Give button
      assert.is_true(row.db:IsShown())
      assert.is_false(box.names[1] and box.names[1]:IsShown() or false)
      assert.is_false(row.rollHint:IsShown())
    end)

    it("awards to a clicked name with the typed roll, and empties the box", function()
      local box = hidden()
      box.rollEdit:SetText("64")
      click(box.hiddenNames[3])
      assert.are.equal(1, #wow.gives)
      local award = ns.Records.Ops("raid00001")[1]
      assert.are.same({ "Mirel Stone", 64, "HR" }, { award.char, award.roll, award.method })
      assert.are.equal("", shownRows()[1].rollBox.rollEdit:GetText())
    end)

    it("refuses a bad roll with a message in the row and nothing handed out", function()
      local box = hidden()
      box.rollEdit:SetText("101")
      local sent = #wow.sent
      click(box.hiddenNames[1])
      assert.are.same({}, wow.gives)
      assert.are.equal(sent, #wow.sent)
      assert.are.equal("Their roll must be a whole number from 1 to 100.",
        shownRows()[1].rollBox.note:GetText())
      assert.are.equal("101", shownRows()[1].rollBox.rollEdit:GetText())
    end)

    it("refuses an open roll with the box empty, and says so", function()
      local box = hidden(3)
      assert.are.equal("Their roll (needed for an open roll):", box.rollLabel:GetText())
      click(box.hiddenNames[1])
      assert.are.same({}, wow.gives)
      assert.are.equal("Type their roll first: an open roll needs it.",
        shownRows()[1].rollBox.note:GetText())
    end)

    it("disables the name buttons in a boss fight", function()
      local box = hidden()
      wow.bossFight(true)
      for i = 1, 3 do
        assert.is_false(box.hiddenNames[i]:IsEnabled())
        assert.are.equal("Chat is locked until the fight ends", box.hiddenNames[i].tip)
      end
      click(box.hiddenNames[1])
      assert.are.same({}, wow.gives)
    end)

    it("starts another item's roll box empty", function()
      local box = hidden()
      box.rollEdit:SetText("77")
      wow.closeLoot()
      called(2)
      wow.fire("CHAT_MSG_SYSTEM", wow.secret)
      assert.are.equal("", shownRows()[1].rollBox.rollEdit:GetText())
    end)
  end)
end)
