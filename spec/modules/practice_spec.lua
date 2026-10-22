local wow = require("spec.support.wow")

describe("PracticeReserves (#107)", function()
  local P
  local GROUP = { "Masterlooter", "Ashla Brightwater", "Doran Vale", "Bram Ironvein", "Mirel Stone",
    "Tovin Hale" }

  before_each(function() P = wow.start().PracticeReserves end)

  local function has(list, name)
    for _, n in ipairs(list) do
      if n == name then return true end
    end
    return false
  end

  local function kinds(made)
    local counts = { HR = 0, SR = 0 }
    for _, h in ipairs(made.holders) do counts[h.kind] = counts[h.kind] + 1 end
    return counts
  end

  it("goes through every case over a run of drops, and starts the cycle again", function()
    local seen = {}
    for drop = 0, #P.CASES - 1 do seen[#seen + 1] = P.Generate(GROUP, drop).case end
    assert.are.same({ "hr-single", "hr-multi", "sr", "skipped", "copies", "open" }, seen)
    assert.are.equal("hr-single", P.Generate(GROUP, #P.CASES).case)
  end)

  it("gives one hard reserve holder, several, soft reserve holders and none", function()
    assert.are.same({ HR = 1, SR = 0 }, kinds(P.Generate(GROUP, 0)))
    assert.are.same({ HR = 3, SR = 0 }, kinds(P.Generate(GROUP, 1)))
    assert.are.same({ HR = 0, SR = 2 }, kinds(P.Generate(GROUP, 2)))
    assert.are.same({}, P.Generate(GROUP, 5).holders)
  end)

  it("uses only people in the group, with user ids that match no real user", function()
    for drop = 0, 11 do
      for _, h in ipairs(P.Generate(GROUP, drop).holders) do
        assert.is_true(has(GROUP, h.char))
        assert.are.equal("practice-" .. h.char:lower(), h.user)
        assert.is_false(h.trial)
      end
    end
  end)

  it("leaves the absent holder out of the roster, the can't-receive one out of the candidates", function()
    local made = P.Generate(GROUP, 3)
    assert.are.equal("skipped", made.case)
    local absent, cannot = made.holders[1].char, made.holders[2].char
    assert.is_true(has(GROUP, absent))
    assert.is_true(has(GROUP, cannot))
    assert.is_false(has(made.roster, absent))
    assert.is_true(has(made.candidates, absent))
    assert.is_true(has(made.roster, cannot))
    assert.is_false(has(made.candidates, cannot))
    assert.are.equal(5, #made.roster)
    assert.are.equal(5, #made.candidates)
  end)

  it("lets the rules skip those two holders with their own reasons", function()
    local ns = wow.start()
    local made = ns.PracticeReserves.Generate(GROUP, 3)
    local resolved = ns.Rules.Resolve({ item = 1, reserves = { [1] = made.holders }, roster = made.roster,
      candidates = made.candidates })
    local reasons = {}
    for _, s in ipairs(resolved.skipped) do reasons[s.char] = s.reason end
    assert.are.same({ [made.holders[1].char] = "not in raid",
      [made.holders[2].char] = "cannot receive" }, reasons)
    assert.are.equal("sr", resolved.mode)
  end)

  it("gives two hard reserve holders and copies = 2 for the several copies case", function()
    local made = P.Generate(GROUP, 4)
    assert.are.equal("copies", made.case)
    assert.are.same({ HR = 2, SR = 0 }, kinds(made))
    assert.are.equal(2, made.copies)
    assert.is_nil(P.Generate(GROUP, 0).copies)
  end)

  it("skips a case the group is too small for, and gives a solo player the open roll", function()
    assert.are.equal("sr", P.Generate({ "Solo", "Duo" }, 1).case) -- several HR needs three members
    assert.are.equal("hr-single", P.Generate({ "Solo" }, 0).case)
    for drop = 0, 11 do
      local made = P.Generate({ "Solo" }, drop)
      assert.is_truthy(made.case == "hr-single" or made.case == "sr" or made.case == "open")
    end
    assert.are.equal("open", P.Generate({ "Solo" }, 3).case)
    assert.are.equal("open", P.Generate({ "Solo" }, 4).case)
    assert.are.same({}, P.Generate({ "Solo" }, 4).holders)
  end)

  it("with two members skips to the next case it can fill and keeps holders distinct", function()
    local made = P.Generate({ "Solo", "Duo" }, 3)
    assert.are.equal("skipped", made.case)
    assert.are.equal(2, #made.holders)
    assert.are_not.equal(made.holders[1].char, made.holders[2].char)
  end)
end)

describe("Test drop (#108)", function()
  local ns
  local GROUP = { "Masterlooter", "Ashla Brightwater", "Doran Vale", "Bram Ironvein", "Mirel Stone",
    "Tovin Hale" }

  -- Starts as an ordinary raid member (not the loot master), practice mode on, no raid loaded.
  local function setup(group)
    ns = wow.start()
    wow.state.group = group or GROUP
    wow.state.groupIsRaid = group == nil or #group > 5
    wow.state.lootMethod = { "group", 0, 0 }
    wow.slash("/bf practice")
    wow.printed = {}
  end

  local function open()
    assert.is_true(assert(ns.TestDrop.Open()))
    return ns.Popup.Build()
  end

  local function click(fn, ...)
    local args, results = { ... }, nil
    wow.click(function() results = { fn(unpack(args)) } end)
    return unpack(results)
  end

  local function modes()
    local seen = {}
    for _ = 1, 6 do
      local m = open()
      seen[#seen + 1] = #m.rows .. ":" .. m.rows[1].mode .. ":" .. m.rows[1].action
    end
    return seen
  end

  local function sentLines()
    local lines = {}
    for _, s in ipairs(wow.sent) do lines[#lines + 1] = s.text end
    return lines
  end

  it("shows the pop-up with no loot window, titled and bannered as designed", function()
    setup()
    assert.are.equal(0, GetNumLootItems())
    local m = open()
    assert.are.equal("[Practice] Loot · Test drop", m.title)
    assert.are.equal("Test drop: no corpse, reserves are made up, nothing is handed out or sent to the site.",
      m.notice)
    assert.is_nil(m.syncLink)
    assert.are.equal("Test drop", m.boss.name)
    assert.is_true(m.practice)
    assert.is_true(ns.TestDrop.IsOpen())
  end)

  it("draws the pop-up and closes it with its X", function()
    setup()
    open()
    local frame = ns.PopupFrame.frame
    assert.is_true(frame:IsShown())
    assert.are.equal("[Practice] Loot · Test drop", frame.title:GetText())
    wow.click(function() frame.close.hooks.OnClick[1](frame.close) end)
    assert.is_false(ns.TestDrop.IsOpen())
    assert.are.same({ nil, "not loot master" }, { ns.Popup.Build() })
  end)

  it("walks #107's cases click by click, two copies in the copies case, then starts again", function()
    setup()
    local expected = { "1:hr:give", "1:hr:roll", "1:sr:roll", "1:sr:give", "2:hr:roll", "1:open:openroll" }
    assert.are.same(expected, modes())
    assert.are.same(expected, modes())
  end)

  it("opens as a non-loot-master, with the raid selection ignored or not a guild run", function()
    setup()
    assert.is_true(ns.Selection.ChooseOff())
    local m = open()
    assert.are.equal("Test drop", m.boss.name)
    wow.state.lootMethod = { "master", 2, 0 }
    assert.is_table(ns.Popup.Build())
  end)

  it("works in a group of one and out of a group", function()
    setup({ "Masterlooter" })
    local m = open()
    assert.are.equal("1:hr:give", #m.rows .. ":" .. m.rows[1].mode .. ":" .. m.rows[1].action)
    local seen = {}
    for _ = 1, 6 do
      m = open()
      seen[#seen + 1] = m.rows[1].action
    end
    assert.is_truthy(seen[1])
    wow.state.group = nil
    wow.state.groupIsRaid = false
    assert.is_table(open())
  end)

  it("refuses while the game's own loot window is open, and when practice mode is off", function()
    setup()
    wow.openLoot({ { link = "|Hitem:5|h[A]|h", quality = 4, candidates = GROUP } })
    assert.are.same({ nil, "window" }, { ns.TestDrop.Open() })
    assert.are.equal(1, #wow.printed)
    wow.closeLoot()
    wow.slash("/bf practice")
    assert.are.same({ nil, "not practice" }, { ns.TestDrop.Open() })
  end)

  it("ends when practice mode goes off or the game opens a loot window", function()
    setup()
    open()
    wow.slash("/bf practice")
    assert.is_false(ns.TestDrop.IsOpen())
    wow.slash("/bf practice")
    open()
    wow.openLoot({ { link = "|Hitem:5|h[A]|h", quality = 4, candidates = GROUP } })
    assert.is_false(ns.TestDrop.IsOpen())
    assert.are.equal(1, GetNumLootItems())
  end)

  it("hands out a hard reserve: records a practice award with no raid, announces it, confirms it", function()
    setup()
    local m = open()
    local row = m.rows[1]
    local attempt = assert(click(ns.Popup.Give, row.slot, row.item, row.winner))
    assert.is_true(attempt.announced)
    assert.are.equal("Handing out to " .. row.winner .. "…", ns.Popup.Build().rows[1].handout.text)
    local key = attempt.awardKey
    local award = ns.Records.Get(key)
    assert.is_true(award.practice)
    assert.is_nil(award.raid)
    assert.are.equal("announced", award.state)
    wow.advance(ns.TestDrop.confirmAfter)
    assert.are.equal("confirmed", ns.Records.Get(key).state)
    assert.is_false(ns.TestDrop.IsOpen()) -- the last item left, so the window closed, as the game's does
    assert.are.same({}, wow.gives)
    assert.are.equal(1, #wow.sent)
    assert.are.equal("[Practice] ", wow.sent[1].text:sub(1, 11))
  end)

  it("does the same with a raid selected, and still records no raid", function()
    setup()
    local tree = { formatVersion = 1, raid = "raid00001", code = "MC0001", env = "staging",
      name = "Molten Core", startsAt = 1792000000, durationMin = 240, generated = 1791990000,
      addon = { version = "0.1.0", url = "https://example.invalid/addon" },
      bosses = { { id = "luc", name = "Lucifron", trash = false, items = { 1 } } }, reserves = {},
      awards = {} }
    ns.Raids.Load(assert(ns.Snapshot.Validate(tree, "0.1.0")), "pasted")
    assert(ns.Selection.ChooseRaid("raid00001"))
    local before = #wow.addonMessages
    local m = open()
    assert.are.equal("Test drop", m.boss.name)
    local row = m.rows[1]
    local attempt = assert(click(ns.Popup.Give, row.slot, row.item, row.winner))
    assert.is_nil(ns.Records.Get(attempt.awardKey).raid)
    assert.are.same({}, ns.Raids.Awards("raid00001"))
    assert.is_nil(wow.sent[1].text:match("MC0001"))
    wow.advance(ns.TestDrop.confirmAfter)
    assert.are.equal("confirmed", ns.Records.Get(attempt.awardKey).state)
    assert.are.equal(before, #wow.addonMessages)
  end)

  it("hands out when the run is not a guild run, and sends nothing to the officers", function()
    setup()
    assert.is_true(ns.Selection.ChooseOff())
    local m = open()
    local row = m.rows[1]
    local before = #wow.addonMessages
    local attempt = assert(click(ns.Popup.Give, row.slot, row.item, row.winner))
    wow.advance(ns.TestDrop.confirmAfter)
    assert.are.equal("confirmed", ns.Records.Get(attempt.awardKey).state)
    assert.are.equal(before, #wow.addonMessages)
  end)

  it("runs a roll-off with a [Practice] call, then hands out to the roller", function()
    setup()
    open()
    local m = open() -- the next case: several hard reserve holders
    local row = m.rows[1]
    assert.are.equal("roll", row.action)
    click(ns.Rolls.Start, row.slot, row.item)
    assert.are.equal("[Practice] Roll for ", wow.sent[#wow.sent].text:sub(1, 20))
    wow.fire("CHAT_MSG_SYSTEM", row.contenders[1] .. " rolls 40 (1-100)")
    wow.fire("CHAT_MSG_SYSTEM", row.contenders[2] .. " rolls 90 (1-100)")
    wow.fire("CHAT_MSG_SYSTEM", row.contenders[3] .. " rolls 90 (1-100)")
    local rolled = ns.Popup.Build().rows[1]
    assert.is_truthy(rolled.rolls.warning)
    click(ns.Rolls.Reroll, row.slot, row.item)
    assert.are.equal("[Practice] Tie for ", wow.sent[#wow.sent].text:sub(1, 19))
    wow.fire("CHAT_MSG_SYSTEM", row.contenders[2] .. " rolls 10 (1-100)")
    wow.fire("CHAT_MSG_SYSTEM", row.contenders[3] .. " rolls 20 (1-100)")
    rolled = ns.Popup.Build().rows[1]
    local button = rolled.buttons[1]
    assert.are.equal("rollgive", button.action)
    local attempt = assert(click(ns.Popup.Give, row.slot, row.item, button.winner, button.roll))
    for _, line in ipairs(sentLines()) do assert.are.equal("[Practice] ", line:sub(1, 11)) end
    assert.is_true(ns.Records.Get(attempt.awardKey).practice)
    wow.advance(ns.TestDrop.confirmAfter)
    assert.are.equal("confirmed", ns.Records.Get(attempt.awardKey).state)
  end)

  it("runs an open roll in a group of one", function()
    setup({ "Masterlooter" })
    local m
    for _ = 1, 6 do
      m = open()
      if m.rows[1].action == "openroll" then break end
    end
    local row = m.rows[1]
    assert.are.equal("openroll", row.action)
    click(ns.Rolls.Start, row.slot, row.item)
    assert.are.equal("[Practice] Open roll for ", wow.sent[#wow.sent].text:sub(1, 25))
    wow.fire("CHAT_MSG_SYSTEM", "Masterlooter rolls 77 (1-100)")
    local button = ns.Popup.Build().rows[1].buttons[1]
    assert.are.equal("Give to Masterlooter (77)", button.text)
    local attempt = assert(click(ns.Popup.Give, row.slot, row.item, button.winner, button.roll))
    wow.advance(ns.TestDrop.confirmAfter)
    assert.are.equal("confirmed", ns.Records.Get(attempt.awardKey).state)
  end)

  it("hands both copies out in the copies case, each to a different holder", function()
    setup()
    local m
    for _ = 1, 5 do m = open() end
    assert.are.equal(2, #m.rows)
    assert.are.same({ "Copy 1 of 2", "Copy 2 of 2" }, { m.rows[1].copy, m.rows[2].copy })
    local first = m.rows[1]
    click(ns.Rolls.Start, first.slot, first.item)
    wow.fire("CHAT_MSG_SYSTEM", first.contenders[1] .. " rolls 50 (1-100)")
    wow.fire("CHAT_MSG_SYSTEM", first.contenders[2] .. " rolls 10 (1-100)")
    local button = ns.Popup.Build().rows[1].buttons[1]
    assert(click(ns.Popup.Give, first.slot, first.item, button.winner, button.roll))
    wow.advance(ns.TestDrop.confirmAfter)
    local second = ns.Popup.Build().rows[1] -- the first copy left the window
    assert.are.equal(2, second.slot)
    assert.are.equal("give", second.action) -- the first copy's winner no longer counts
    local winners = { button.winner, second.winner }
    assert(click(ns.Popup.Give, second.slot, second.item, second.winner))
    wow.advance(ns.TestDrop.confirmAfter)
    assert.are_not.equal(winners[1], winners[2])
    assert.are.equal(0, #ns.Tracking.Pending())
  end)

  it("hands to disenchant/bank with the Test drop's own pick, never saved", function()
    setup()
    open()
    local row = ns.Popup.Build().rows[1]
    assert(ns.Popup.SetDBPick("Doran Vale"))
    assert.is_nil(ns.db.dbPick)
    local attempt = assert(click(ns.Popup.GiveDB, row.slot, row.item, "Doran Vale"))
    assert.is_true(ns.Records.Get(attempt.awardKey).practice)
    assert.is_nil(ns.Records.Get(attempt.awardKey).raid)
    wow.advance(ns.TestDrop.confirmAfter)
    open()
    assert.is_nil(ns.Popup.DBPick())
  end)

  it("undoes a confirmed Test drop award with a [Practice] undo line, as a non-loot-master too", function()
    setup()
    local row = open().rows[1]
    local attempt = assert(click(ns.Popup.Give, row.slot, row.item, row.winner))
    wow.advance(ns.TestDrop.confirmAfter)
    ns.TestDrop.Close()
    local before = #wow.sent
    local ops = #wow.addonMessages
    local op = assert(click(ns.Popup.Undo, attempt.awardKey))
    assert.is_true(op.practice)
    assert.is_true(ns.Records.Get(attempt.awardKey).voided)
    assert.are.equal(ops, #wow.addonMessages)
    assert.are.equal(before + 1, #wow.sent)
    assert.are.equal("[Practice] ", wow.sent[#wow.sent].text:sub(1, 11))
  end)

  it("leaves a real award alone: Undo still needs the loot master", function()
    setup()
    local op = assert(ns.Records.Award({ item = 5, char = "Doran Vale", method = "HR", noRaid = true }))
    assert.is_true(ns.Records.Confirm(op.id) ~= nil)
    assert.are.same({ nil, "not loot master" }, { click(ns.Popup.Undo, op.id) })
  end)

  it("never reaches the game's GiveMasterLoot, even after the window closes mid-hand-out", function()
    setup()
    local row = open().rows[1]
    local attempt = assert(click(ns.Popup.Give, row.slot, row.item, row.winner))
    ns.TestDrop.Close()
    wow.advance(ns.TestDrop.confirmAfter)
    assert.are.same({}, wow.gives)
    assert.are.equal("confirmed", ns.Records.Get(attempt.awardKey).state)
  end)

  it("sends every chat line with [Practice] in front", function()
    setup()
    for _ = 1, 6 do
      local row = open().rows[1]
      if row.action == "give" then
        assert(click(ns.Popup.Give, row.slot, row.item, row.winner))
      else
        click(ns.Rolls.Start, row.slot, row.item)
      end
      wow.advance(ns.TestDrop.confirmAfter)
    end
    assert.is_true(#wow.sent >= 6)
    for _, line in ipairs(sentLines()) do assert.are.equal("[Practice] ", line:sub(1, 11)) end
  end)
end)
