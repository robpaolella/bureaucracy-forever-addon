local wow = require("spec.support.wow")

local function link(id) return "|cffa335ee|Hitem:" .. id .. "::::::::60:::::|h[Item " .. id .. "]|h|r" end

local function holder(char, kind)
  return { user = char:lower():gsub("%s", ""), char = char, kind = kind, trial = false }
end

local function tree(fields)
  local t = {
    formatVersion = 1, raid = "raid00001", code = "SMC001", env = "staging", name = "Molten Core",
    startsAt = 1792000000, durationMin = 240, generated = 1791990000,
    addon = { version = "0.1.0", url = "https://example.invalid/addon" },
    bosses = {
      { id = "boss-lucif", name = "Lucifron", trash = false, items = { 1, 2, 3, 4 } },
      { id = "boss-magma", name = "Magmadar", trash = false, items = { 4 } },
      { id = "boss-trash", name = "Trash", trash = true, items = {} },
    },
    reserves = {
      [1] = { holder("Ashla Brightwater", "HR") },
      [2] = { holder("Doran Vale", "SR"), holder("Ashla Brightwater", "SR") },
    },
    awards = {},
  }
  for k, v in pairs(fields or {}) do t[k] = v end
  return t
end

local LEAD = "You gave %s to |cffffffff%s|r from the game's loot menu. How was it won?"

describe("the outside hand-out question", function()
  local ns, O

  -- The loot master in a raid, Molten Core loaded and selected.
  local function setup()
    ns = wow.start()
    O = ns.OutsideHandout
    wow.state.group = { "Masterlooter", "Ashla Brightwater", "Doran Vale", "Bram Ironvein" }
    wow.state.groupIsRaid = true
    wow.state.lootMethod = { "master", 0, 0 }
    ns.Raids.Load(assert(ns.Snapshot.Validate(tree(), "0.1.0")), "pasted")
    assert(ns.Selection.ChooseRaid("raid00001"))
    for _ = 1, 30 do wow.advance(1) end
    wow.addonMessages = {}
  end
  before_each(setup)

  local function drop(ids, quality)
    local items = {}
    for i, id in ipairs(ids) do
      items[i] = { link = link(id), quality = quality or 4, sourceGuid = "corpse1",
        candidates = wow.state.group }
    end
    wow.openLoot(items)
  end

  -- The game's own menu hands slot's item to winner: the slot clears and the loot line comes.
  local function giveFromMenu(slot, winner)
    wow.fire("LOOT_SLOT_CLEARED", slot)
    wow.fire("LOOT_SLOT_CLEARED", slot)
    wow.fire("CHAT_MSG_LOOT", winner .. " receives loot: " .. wow.state.loot[slot].link .. ".")
  end

  local function frame() return O.frame end

  -- What the question shows: lead, the choices ({ on, label }), the roll, the boss, hint, buttons.
  local function view()
    local f = frame()
    if not f:IsShown() then return nil end
    local choices = {}
    for i, r in ipairs(f.rows) do
      choices[i] = { r.radio:GetText() == ns.UI.parts.RADIO[true], r.label:GetText() }
    end
    local boss
    if f.boss:IsShown() then
      local entries = {}
      for _, e in ipairs(f.menu.entries) do
        if e:IsShown() then entries[#entries + 1] = e.label:GetText() end
      end
      boss = { button = f.boss.label:GetText(), title = f.menu.title:GetText(), entries = entries }
    end
    return { lead = f.lead:GetText(), choices = choices, roll = f.roll:GetText(), boss = boss,
      hint = f.hint:GetText(),
      buttons = { { f.record.label:GetText(), f.record:IsEnabled() },
        { f.later.label:GetText(), f.later:IsEnabled() } } }
  end

  local function click(b) wow.click(function() b.scripts.OnClick(b) end) end
  local function choose(i) click(frame().rows[i]) end
  local function typeRoll(text)
    frame().roll:SetText(text)
    frame().roll.scripts.OnTextChanged(frame().roll, true)
  end
  local function record() click(frame().record) end
  local function later() click(frame().later) end
  local function recordEnabled() return frame().record:IsEnabled() end

  local function awards() return ns.Raids.Awards("raid00001") end

  -- The operations sent to the group once the queue has run: { type, id }.
  local function sentOps()
    for _ = 1, 60 do wow.advance(1) end
    local whole, order = {}, {}
    for _, message in ipairs(wow.addonMessages) do
      local chunk = message.text:find("^O;") and assert(ns.Sync.ParseChunk(message.text))
      if chunk then
        if not whole[chunk.msgid] then
          whole[chunk.msgid] = {}
          order[#order + 1] = chunk.msgid
        end
        whole[chunk.msgid][chunk.n] = chunk.piece
      end
    end
    local ops = {}
    for i, msgid in ipairs(order) do
      local op = assert(ns.OpText.Decode(table.concat(whole[msgid])))
      ops[i] = { op.type, op.id }
    end
    return ops
  end

  it("asks about a hand-out at the threshold, as the design draws it, pre-filled Hard reserve", function()
    drop({ 1 })
    wow.state.lootThreshold = 4
    giveFromMenu(1, "Ashla Brightwater")
    assert.are.same({
      lead = LEAD:format(link(1), "Ashla Brightwater"),
      choices = { { true, "Hard reserve |cff808080(they hard-reserved it)|r" }, { false, "Soft reserve" },
        { false, "Open roll, roll:" }, { false, "Disenchant/bank" } },
      roll = "", hint = "Recording it posts the award line in raid chat.",
      buttons = { { "Record and announce", true }, { "Later", true } },
    }, view())
    assert.are.same({}, awards())
    assert.are.same({}, wow.sent)
  end)

  it("ignores a hand-out below the threshold", function()
    drop({ 1 }, 3)
    wow.state.lootThreshold = 4
    giveFromMenu(1, "Ashla Brightwater")
    assert.is_nil(view())
    assert.is_nil(O.Shown())
    assert.are.same({}, O.Unanswered())
  end)

  it("pre-fills Soft reserve for a soft reserve holder", function()
    drop({ 2 })
    giveFromMenu(1, "Doran Vale")
    assert.are.same({ { false, "Hard reserve" }, { true, "Soft reserve |cff808080(they soft-reserved it)|r" },
      { false, "Open roll, roll:" }, { false, "Disenchant/bank" } }, view().choices)
    assert.is_true(recordEnabled())
  end)

  it("pre-fills Open roll with an empty box when the winner holds no reserve for the item", function()
    drop({ 2 })
    giveFromMenu(1, "Bram Ironvein")
    local v = view()
    assert.are.same({ { false, "Hard reserve" }, { false, "Soft reserve" }, { true, "Open roll, roll:" },
      { false, "Disenchant/bank" } }, v.choices)
    assert.are.equal("", v.roll)
    assert.is_false(recordEnabled())
  end)

  it("enables Record for an open roll only with a whole number from 1 to 100", function()
    drop({ 3 })
    giveFromMenu(1, "Bram Ironvein")
    for _, text in ipairs({ "", "0", "101", "1.5", "abc", " ", "-5" }) do
      typeRoll(text)
      assert.is_false(recordEnabled(), "enabled for '" .. text .. "'")
    end
    for _, text in ipairs({ "1", "100", "42" }) do
      typeRoll(text)
      assert.is_true(recordEnabled(), "disabled for '" .. text .. "'")
    end
    -- Another choice needs no roll; typing a roll chooses Open roll again.
    typeRoll("abc")
    choose(4)
    assert.is_true(recordEnabled())
    typeRoll("7")
    assert.is_true(view().choices[3][1])
  end)

  it("records one confirmed award under the loot window's boss, posts its line and sends it", function()
    drop({ 1, 2 })
    giveFromMenu(1, "Ashla Brightwater")
    record()
    local list = awards()
    assert.are.equal(1, #list)
    local a = list[1]
    assert.are.same({ "boss-lucif", 1, "Ashla Brightwater", "ashlabrightwater", "HR", "confirmed" },
      { a.boss, a.item, a.char, a.user, a.method, a.state })
    assert.are.equal(1, #wow.sent)
    local expected = ns.OpText.BuildLine("award", { raid = "SMC001", key = a.key, item = 1, link = link(1),
      boss = "boss-lucif", method = "HR", winner = "Ashla Brightwater" })
    assert.are.same({ text = expected, channel = "RAID" }, wow.sent[1])
    local ops = sentOps()
    assert.are.equal(2, #ops)
    assert.are.same({ "award", a.key }, ops[1])
    assert.are.equal("confirm", ops[2][1])
    assert.is_nil(view())
  end)

  it("records an open roll with its roll, and disenchant/bank with no winner", function()
    drop({ 3, 1 })
    giveFromMenu(1, "Bram Ironvein")
    giveFromMenu(2, "Doran Vale")
    typeRoll("87")
    record()
    choose(4)
    record()
    local list = awards()
    assert.are.same({ "OPEN_ROLL", 87, "Bram Ironvein" }, { list[1].method, list[1].roll, list[1].char })
    assert.are.same({ "DISENCHANT_BANK", nil, nil }, { list[2].method, list[2].roll, list[2].char })
    assert.matches("(open roll, 87)", wow.sent[1].text, 1, true)
    assert.matches("→ disenchant", wow.sent[2].text:lower(), 1, true)
  end)

  it("records in the raid of the hand-out, though another raid is chosen before the answer", function()
    ns.Raids.Load(assert(ns.Snapshot.Validate(tree({ raid = "raid00002", code = "SMC002" }), "0.1.0")),
      "pasted")
    drop({ 1 })
    giveFromMenu(1, "Ashla Brightwater")
    assert(ns.Selection.ChooseRaid("raid00002"))
    record()
    assert.are.equal(1, #awards())
    assert.are.same({}, ns.Raids.Awards("raid00002"))
    assert.matches("<BF1;A;SMC001;", wow.sent[1].text, 1, true)
  end)

  it("holds the award as no raid when none was loaded at the hand-out, though one is chosen after", function()
    ns = wow.start()
    O = ns.OutsideHandout
    wow.state.group = { "Masterlooter", "Ashla Brightwater" }
    wow.state.groupIsRaid = true
    wow.state.lootMethod = { "master", 0, 0 }
    drop({ 1 })
    giveFromMenu(1, "Ashla Brightwater")
    assert.is_nil(view().boss)
    ns.Raids.Load(assert(ns.Snapshot.Validate(tree(), "0.1.0")), "pasted")
    assert(ns.Selection.ChooseRaid("raid00001"))
    -- No reserves were loaded at the hand-out: Open roll, as the pop-up would have said.
    assert.is_true(view().choices[3][1])
    typeRoll("40")
    record()
    assert.are.same({}, awards())
    assert.are.equal(1, #ns.db.noRaid)
    assert.are.same({ "Ashla Brightwater", "OPEN_ROLL", 40 },
      { ns.db.noRaid[1].char, ns.db.noRaid[1].method, ns.db.noRaid[1].roll })
  end)

  it("keeps the question open and says so when the award can't be recorded", function()
    drop({ 1 })
    giveFromMenu(1, "Ashla Brightwater")
    ns.Records.Award = function() return nil, "key-conflict" end
    record()
    assert.is_table(view())
    assert.are.same({}, wow.sent)
    assert.are.equal("|cff33ff99Bureaucracy:|r The award of " .. link(1)
      .. " to Ashla Brightwater couldn't be recorded. Type /bf log for why.", wow.printed[#wow.printed])
    assert.are.same({}, sentOps())
  end)

  describe("with no loot window open", function()
    local function handOutClosed()
      drop({ 1 })
      wow.fire("LOOT_SLOT_CLEARED", 1)
      wow.closeLoot()
      wow.fire("CHAT_MSG_LOOT", "Ashla Brightwater receives loot: " .. link(1) .. ".")
    end

    it("asks for the boss with the pop-up's menu, none picked, and Record waits for one", function()
      handOutClosed()
      assert.are.same({ button = "Choose ▾", title = "Which boss dropped this?",
        entries = { "   Lucifron", "   Magmadar", "   Trash" } }, view().boss)
      assert.is_false(recordEnabled())
      click(frame().boss)
      assert.is_true(frame().menu:IsShown())
      click(frame().menu.entries[2])
      assert.are.same({ button = "Magmadar ▾", title = "Which boss dropped this?",
        entries = { "   Lucifron", "> Magmadar", "   Trash" } }, view().boss)
      assert.is_false(frame().menu:IsShown())
      assert.is_true(recordEnabled())
      record()
      assert.are.equal("boss-magma", awards()[1].boss)
      assert.matches("<BF1;A;SMC001;[^;]+;1;magma;HR;;Ashla Brightwater>", wow.sent[1].text)
    end)

    it("asks for the boss when the window's items point to more than one boss", function()
      drop({ 4 })
      giveFromMenu(1, "Ashla Brightwater")
      assert.are.equal("Choose ▾", view().boss.button)
    end)
  end)

  it("Later saves, posts and sends nothing, and keeps the hand-out in the session's list", function()
    drop({ 1 })
    giveFromMenu(1, "Ashla Brightwater")
    later()
    assert.is_nil(view())
    assert.are.same({}, awards())
    assert.are.same({}, wow.sent)
    assert.are.same({}, sentOps())
    local list = O.Unanswered()
    assert.are.equal(1, #list)
    assert.are.same({ "Ashla Brightwater", link(1), 1, "boss-lucif", wow.state.time },
      { list[1].winner, list[1].link, list[1].item, list[1].boss, list[1].at })
  end)

  it("Escape closes it as Later does", function()
    drop({ 1 })
    giveFromMenu(1, "Ashla Brightwater")
    frame():Hide()
    assert.are.equal(1, #O.Unanswered())
    assert.is_nil(O.Shown())
  end)

  it("answering one put off reopens it, and it leaves the list", function()
    drop({ 1 })
    giveFromMenu(1, "Ashla Brightwater")
    later()
    O.Ask(O.Unanswered()[1])
    assert.are.equal(LEAD:format(link(1), "Ashla Brightwater"), view().lead)
    assert.are.same({}, O.Unanswered())
    record()
    assert.are.equal("boss-lucif", awards()[1].boss)
  end)

  it("asks about several hand-outs one at a time, in order", function()
    drop({ 1, 2, 3 })
    giveFromMenu(1, "Ashla Brightwater")
    giveFromMenu(2, "Doran Vale")
    giveFromMenu(3, "Bram Ironvein")
    assert.are.equal(LEAD:format(link(1), "Ashla Brightwater"), view().lead)
    assert.are.equal(2, #O.Waiting())
    record()
    assert.are.equal(LEAD:format(link(2), "Doran Vale"), view().lead)
    later()
    assert.are.equal(LEAD:format(link(3), "Bram Ironvein"), view().lead)
    typeRoll("12")
    record()
    assert.is_nil(view())
    assert.are.equal(2, #awards())
    assert.are.equal(1, #O.Unanswered())
    assert.are.equal(2, #wow.sent)
  end)

  it("records, asks, keeps and sends nothing when the run is not a guild run", function()
    assert.is_true(ns.Selection.ChooseOff())
    for _ = 1, 30 do wow.advance(1) end
    wow.addonMessages = {}
    drop({ 1 })
    giveFromMenu(1, "Ashla Brightwater")
    assert.is_nil(view())
    assert.are.same({}, O.Waiting())
    assert.are.same({}, O.Unanswered())
    assert.are.same({}, wow.sent)
    assert.are.same({}, sentOps())
    assert.are.same({}, awards())
  end)

  it("keeps nothing when the run stops being a guild run while asked", function()
    drop({ 1, 2 })
    giveFromMenu(1, "Ashla Brightwater")
    giveFromMenu(2, "Doran Vale")
    assert.is_true(ns.Selection.ChooseOff())
    later()
    assert.is_nil(view())
    assert.are.same({}, O.Unanswered())
    assert.are.same({}, O.Waiting())
  end)

  describe("in a boss fight", function()
    it("holds the question until the fight ends", function()
      drop({ 1 })
      wow.bossFight(true)
      giveFromMenu(1, "Ashla Brightwater")
      assert.is_nil(view())
      assert.are.equal(1, #O.Waiting())
      wow.bossFight(false)
      assert.are.equal(LEAD:format(link(1), "Ashla Brightwater"), view().lead)
      record()
      assert.are.equal(1, #wow.sent)
    end)

    it("puts back a question open when a fight starts, first in line, with its picked boss", function()
      drop({ 1 })
      wow.fire("LOOT_SLOT_CLEARED", 1)
      wow.closeLoot()
      wow.fire("CHAT_MSG_LOOT", "Ashla Brightwater receives loot: " .. link(1) .. ".")
      click(frame().boss)
      click(frame().menu.entries[1])
      wow.bossFight(true)
      assert.is_nil(view())
      wow.bossFight(false)
      assert.are.equal("Lucifron ▾", view().boss.button)
      assert.is_true(recordEnabled())
    end)

    it("posts nothing while chat is locked", function()
      drop({ 1 })
      giveFromMenu(1, "Ashla Brightwater")
      wow.state.chatLockdown = true
      assert.are.same({ nil, "fight" }, { O.Record() })
      assert.are.same({}, awards())
      assert.is_table(view())
    end)
  end)
  describe("kept until recorded (#137)", function()
    local function saved() return ns.db.outside and ns.db.outside["raid00001"] or {} end

    -- A /reload: the same saved data, a fresh session in the same raid group.
    local function reload()
      local db = ns.db
      ns = wow.start({ saved = { BureaucracyForeverDB = db } })
      O = ns.OutsideHandout
      wow.state.group = { "Masterlooter", "Ashla Brightwater", "Doran Vale", "Bram Ironvein" }
      wow.state.groupIsRaid = true
      wow.state.lootMethod = { "master", 0, 0 }
      for _ = 1, 30 do wow.advance(1) end
      wow.addonMessages = {}
    end

    local function quiet()
      assert.are.same({}, wow.sent)
      assert.are.same({}, sentOps())
    end

    it("saves a hand-out as soon as its question is open, and lists it only once set aside", function()
      drop({ 1 })
      giveFromMenu(1, "Ashla Brightwater")
      assert.are.equal(1, #saved())
      assert.are.same({ "Ashla Brightwater", link(1), 1, "boss-lucif" },
        { saved()[1].winner, saved()[1].link, saved()[1].item, saved()[1].boss })
      assert.are.same({}, O.Unanswered())
      later()
      assert.are.equal(1, #saved())
      assert.are.equal(1, #O.Unanswered())
      quiet()
    end)

    it("saves one waiting behind another and one held by a boss fight", function()
      drop({ 1, 2, 3 })
      giveFromMenu(1, "Ashla Brightwater")
      giveFromMenu(2, "Doran Vale")
      assert.are.equal(2, #saved())
      assert.are.same({}, O.Unanswered())
      wow.bossFight(true)
      giveFromMenu(3, "Bram Ironvein")
      assert.are.equal(3, #saved())
      assert.are.same({}, O.Unanswered())
      quiet()
    end)

    it("keeps each one through a reload, lists it, and asks nothing by itself", function()
      drop({ 1, 2, 3 })
      giveFromMenu(1, "Ashla Brightwater")
      giveFromMenu(2, "Doran Vale")
      later()
      wow.bossFight(true)
      giveFromMenu(3, "Bram Ironvein")
      reload()
      assert.is_nil(view())
      assert.are.same({}, O.Waiting())
      local list = O.Unanswered()
      assert.are.equal(3, #list)
      assert.are.same({ link(1), link(2), link(3) }, { list[1].link, list[2].link, list[3].link })
    end)

    it("leaves an open or waiting question out of the list, and asking one again saves no second copy",
      function()
        drop({ 1, 2 })
        giveFromMenu(1, "Ashla Brightwater")
        giveFromMenu(2, "Doran Vale")
        later()
        local h = O.Unanswered()[1]
        assert.are.equal(link(1), h.link)
        O.Ask(h)
        assert.are.equal(2, #saved())
        assert.are.equal(1, #O.Waiting())
        assert.are.equal(link(2), O.Shown().handout.link)
        assert.are.same({}, O.Unanswered())
        later()
        assert.are.equal(link(1), O.Shown().handout.link)
        later()
        assert.are.equal(2, #saved())
        assert.are.equal(2, #O.Unanswered())
      end)

    it("records one from its first question, posts one line, sends it and drops the saved entry", function()
      drop({ 1 })
      giveFromMenu(1, "Ashla Brightwater")
      record()
      assert.are.same({}, saved())
      assert.is_nil(ns.db.outside["raid00001"])
      assert.are.equal(1, #awards())
      assert.are.equal(1, #wow.sent)
      assert.are.same({ "award", "confirm" }, { sentOps()[1][1], sentOps()[2][1] })
      assert.are.same({}, O.Unanswered())
    end)

    it("records one asked again after Later, and one loaded after a reload", function()
      drop({ 1, 2 })
      giveFromMenu(1, "Ashla Brightwater")
      giveFromMenu(2, "Doran Vale")
      later()
      O.Ask(O.Unanswered()[1])
      later()
      later()
      O.Ask(O.Unanswered()[1])
      record()
      assert.are.equal(1, #saved())
      assert.are.equal(1, #awards())
      reload()
      assert.are.equal(1, #O.Unanswered())
      O.Ask(O.Unanswered()[1])
      assert.are.equal(1, #saved())
      assert.is_truthy(view().lead:find("Item 2", 1, true))
      typeRoll("40")
      record()
      assert.are.same({}, saved())
      assert.are.same({}, O.Unanswered())
      assert.are.equal(2, #ns.Raids.Awards("raid00001"))
      assert.are.equal(1, #wow.sent)
    end)

    it("keeps a no-raid hand-out in memory only: listed after Later, gone after a reload", function()
      ns = wow.start()
      O = ns.OutsideHandout
      wow.state.group = { "Masterlooter", "Ashla Brightwater", "Doran Vale", "Bram Ironvein" }
      wow.state.groupIsRaid = true
      wow.state.lootMethod = { "master", 0, 0 }
      for _ = 1, 30 do wow.advance(1) end
      drop({ 1 })
      giveFromMenu(1, "Ashla Brightwater")
      assert.is_nil(ns.db.outside)
      assert.are.same({}, O.Unanswered())
      later()
      assert.is_nil(ns.db.outside)
      assert.are.equal(1, #O.Unanswered())
      reload()
      assert.are.same({}, O.Unanswered())
    end)
  end)
end)
