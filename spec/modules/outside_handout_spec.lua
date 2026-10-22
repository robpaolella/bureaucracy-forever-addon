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

    it("keeps a question open and one waiting through a reload, then records each as one award", function()
      drop({ 1, 2 })
      giveFromMenu(1, "Ashla Brightwater")
      giveFromMenu(2, "Doran Vale")
      assert.is_table(view())
      assert.are.equal(1, #O.Waiting())
      reload()
      assert.is_nil(view())
      assert.are.same({}, O.Waiting())
      assert.are.equal(2, #saved())
      assert.are.equal(2, #O.Unanswered())
      O.Ask(O.Unanswered()[1])
      O.Ask(O.Unanswered()[1])
      assert.are.equal(2, #saved())
      record()
      typeRoll("40")
      record()
      assert.are.same({}, saved())
      assert.are.equal(2, #ns.Raids.Awards("raid00001"))
      assert.are.equal(2, #wow.sent)
      local ops = sentOps()
      assert.are.same({ "award", "confirm", "award", "confirm" },
        { ops[1][1], ops[2][1], ops[3][1], ops[4][1] })
    end)

    it("records one asked again after Later: one award, one line, sent, no saved entry", function()
      drop({ 1 })
      giveFromMenu(1, "Ashla Brightwater")
      later()
      O.Ask(O.Unanswered()[1])
      record()
      assert.are.same({}, saved())
      assert.are.equal(1, #awards())
      assert.are.equal(1, #wow.sent)
      local ops = sentOps()
      assert.are.same({ "award", "confirm" }, { ops[1][1], ops[2][1] })
    end)

    it("records one loaded after a reload: one award, one line, sent, no saved entry", function()
      drop({ 1 })
      giveFromMenu(1, "Ashla Brightwater")
      reload()
      O.Ask(O.Unanswered()[1])
      record()
      assert.are.same({}, saved())
      assert.are.equal(1, #ns.Raids.Awards("raid00001"))
      assert.are.equal(1, #wow.sent)
      local ops = sentOps()
      assert.are.same({ "award", "confirm" }, { ops[1][1], ops[2][1] })
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
  describe("in the Awards tab (#143)", function()
    local ANSWER = "|cffffa000NEEDS AN ANSWER|r Given to %s from the game's loot menu"
    local function saved(raidId) return ns.db.outside and ns.db.outside[raidId or "raid00001"] end

    -- The game writes saved data to disk and reads it back: a copy, not the same table.
    local function copy(value)
      if type(value) ~= "table" then return value end
      local out = {}
      for k, v in pairs(value) do out[copy(k)] = copy(v) end
      return out
    end

    -- A /reload, or a later login, in the same raid group, with the helper's file as given.
    local function reload(inbox)
      ns = wow.start({ saved = { BureaucracyForeverDB = copy(ns.db) }, inbox = inbox })
      O = ns.OutsideHandout
      wow.state.group = { "Masterlooter", "Ashla Brightwater", "Doran Vale", "Bram Ironvein" }
      wow.state.groupIsRaid = true
      wow.state.lootMethod = { "master", 0, 0 }
      for _ = 1, 30 do wow.advance(1) end
      wow.addonMessages = {}
    end

    -- The helper's file holding these snapshots, naming no newer add-on.
    local function inboxOf(...)
      local raids = {}
      for i, t in ipairs({ ... }) do
        t.addon = { version = "0.0.0", url = "https://example.invalid/addon" }
        t.generated = t.generated + 1 -- the copy in use over the pasted one
        raids[i] = { snapshot = t }
      end
      return { formatVersion = 1, written = 1791999000, raids = raids }
    end

    -- The Awards tab as drawn last: opening the window draws it; nothing here redraws it.
    local function tab()
      if not ns.UI.window:IsShown() then ns.UI.Toggle() end
      return ns.UI.awards
    end

    -- Every drawn line: a heading alone, or a row's time, item, winner and its button's label.
    local function lines()
      local out = {}
      for _, line in ipairs(tab().shown) do
        if line.heading then out[#out + 1] = { line.heading:GetText() }
        else
          local b = line.answer or line.pick or line.undo
          out[#out + 1] = { line.time:GetText(), line.item:GetText(), line.winner:GetText(),
            b and b.label:GetText() or nil }
        end
      end
      return out
    end

    local function answers()
      local out = {}
      for _, line in ipairs(tab().shown) do
        if line.answerNeeded then out[#out + 1] = line end
      end
      return out
    end

    local function answer(i) click(answers()[i or 1].answer) end
    local function grey(text) return "|cff808080" .. text .. "|r" end

    -- A hand-out of item for winner in raidId, with no boss known, put off with Later.
    local function putOff(item, winner, raidId)
      O.Ask({ winner = winner, link = link(item), item = item, quantity = 1, at = time(),
        raid = raidId or "raid00001" })
      later()
    end

    it("lists one set aside in its boss's group in time order, counted as needing an answer", function()
      ns.db.awards = { raid00001 = {
        { key = "a1", raid = "raid00001", boss = "boss-lucif", item = 2, char = "Doran Vale", method = "SR",
          at = time() - 60, state = "confirmed", stateAt = time() - 60 },
        { key = "a2", raid = "raid00001", boss = "boss-lucif", item = 3, char = "Bram Ironvein",
          method = "OPEN_ROLL", roll = 50, at = time() + 60, state = "confirmed", stateAt = time() + 60 },
      } }
      drop({ 1 })
      local at = time()
      giveFromMenu(1, "Ashla Brightwater")
      later()
      assert.are.same({
        { "Lucifron · 3 items" },
        { grey(date("%H:%M", at - 60)), "Item 2", "Doran Vale", "Undo" },
        { grey(date("%H:%M", at)), "Item 1", ANSWER:format("Ashla Brightwater"), "Answer" },
        { grey(date("%H:%M", at + 60)), "Item 3", "Bram Ironvein", "Undo" },
      }, lines())
      assert.is_true(answers()[1].answer:IsEnabled())
      assert.are.equal("2 awards · 1 needs an answer", tab().summary:GetText())
    end)

    it("lists one with no boss known under Other, and a raid with only it isn't empty", function()
      putOff(1, "Ashla Brightwater")
      assert.are.same({ { "Other · 1 item" },
        { grey(date("%H:%M", time())), "Item 1", ANSWER:format("Ashla Brightwater"), "Answer" } }, lines())
      assert.are.equal("1 needs an answer", tab().summary:GetText())
      assert.is_false(tab().title:IsShown())
      assert.is_true(tab().scroll:IsShown())
    end)

    it("draws its row as the window opens on a reload, and none for an open, waiting or no-raid one",
      function()
        drop({ 1, 2 })
        giveFromMenu(1, "Ashla Brightwater")
        later()
        reload()
        assert.are.equal(1, #answers())
        O.Ask(O.Unanswered()[1])
        assert.are.equal(0, #answers())
        assert.is_true(tab().title:IsShown())
        later()
        assert.are.equal(1, #answers())
        drop({ 2 })
        giveFromMenu(1, "Doran Vale")
        O.Ask(O.Unanswered()[1])
        assert.are.equal(1, #O.Waiting())
        assert.are.equal(0, #answers())
        later()
        later()
        assert.are.equal(2, #answers())
        O.Ask({ winner = "Bram Ironvein", link = link(3), item = 3, quantity = 1, at = time() })
        later()
        assert.are.equal(3, #O.Unanswered())
        assert.are.equal(2, #answers())
      end)

    it("asks again from Answer with the same pre-fill and boss, then records it once", function()
      drop({ 1 })
      giveFromMenu(1, "Ashla Brightwater")
      local first = view()
      later()
      reload()
      answer()
      assert.are.same(first, view())
      assert.are.equal("boss-lucif", O.Shown().boss)
      assert.are.equal(0, #answers())
      record()
      assert.is_nil(saved())
      assert.are.equal(1, #awards())
      assert.are.equal("boss-lucif", awards()[1].boss)
      assert.are.equal(1, #wow.sent)
      local ops = sentOps()
      assert.are.same({ "award", "confirm" }, { ops[1][1], ops[2][1] })
      assert.are.equal(0, #answers())
      assert.are.equal("1 award", tab().summary:GetText())
    end)

    it("asks again with the boss picked before, and Later brings the row back as it was", function()
      putOff(1, "Ashla Brightwater")
      answer()
      O.PickBoss("boss-magma")
      later()
      local before = lines()
      assert.are.same({ "Magmadar · 1 item" }, before[1])
      answer()
      assert.are.equal("boss-magma", O.Shown().boss)
      assert.are.equal("Magmadar ▾", view().boss.button)
      later()
      assert.are.same(before, lines())
    end)

    it("asks from Answer only once a boss fight ends", function()
      putOff(1, "Ashla Brightwater")
      wow.bossFight(true)
      answer()
      assert.is_nil(view())
      assert.are.equal(0, #answers())
      wow.bossFight(false)
      assert.are.equal(link(1), O.Shown().handout.link)
    end)

    it("queues Answer behind a question already open", function()
      putOff(1, "Ashla Brightwater")
      drop({ 2 })
      giveFromMenu(1, "Doran Vale")
      answer()
      assert.are.equal(link(2), O.Shown().handout.link)
      assert.are.equal(link(1), O.Waiting()[1].link)
      assert.are.equal(0, #answers())
      later()
      assert.are.equal(link(1), O.Shown().handout.link)
    end)

    it("keeps Answer enabled once someone else is loot master, and records from it", function()
      putOff(1, "Ashla Brightwater")
      wow.state.lootMethod = { "master", nil, 2 }
      ns.UI.RefreshAwards()
      assert.is_true(tab().view.readOnly)
      assert.is_true(answers()[1].answer:IsEnabled())
      answer()
      O.PickBoss("boss-lucif")
      record()
      assert.are.equal(1, #awards())
      assert.is_nil(saved())
      assert.are.equal(0, #answers())
    end)

    it("shows no row on a run that is not a guild run, keeping it saved, and again once chosen", function()
      putOff(1, "Ashla Brightwater")
      assert(ns.Selection.ChooseOff())
      ns.UI.RefreshAwards() -- as going to the tab does
      assert.are.equal(0, #answers())
      assert.are.equal(1, #saved())
      assert(ns.Selection.ChooseRaid("raid00001"))
      ns.UI.RefreshAwards()
      assert.are.equal(1, #answers())
    end)

    it("shows only the selected raid's rows", function()
      ns.Raids.Load(assert(ns.Snapshot.Validate(tree({ raid = "raid00002", code = "SMC002" }), "0.1.0")),
        "pasted")
      putOff(1, "Ashla Brightwater")
      putOff(2, "Doran Vale", "raid00002")
      assert.are.equal(1, #answers())
      assert.are.equal("Item 1", answers()[1].item:GetText())
      assert(ns.Selection.ChooseRaid("raid00002"))
      ns.UI.RefreshAwards() -- as going to the tab does
      assert.are.equal(1, #answers())
      assert.are.equal("Item 2", answers()[1].item:GetText())
    end)

    describe("of a raid taken off the list", function()
      it("drops them when its last copy is removed", function()
        putOff(1, "Ashla Brightwater")
        assert(ns.Raids.Remove("raid00001"))
        assert.is_nil(saved())
        assert.are.same({}, O.Unanswered())
      end)

      it("keeps them when the pasted copy goes and the inbox's stays", function()
        putOff(1, "Ashla Brightwater")
        reload(inboxOf(tree()))
        assert(ns.Raids.Remove("raid00001"))
        assert.is_table(ns.Raids.Get("raid00001"))
        assert.are.equal(1, #saved())
      end)

      it("drops them when it leaves the inbox at a reload with no pasted copy, not another raid's", function()
        reload(inboxOf(tree(), tree({ raid = "raid00002", code = "SMC002" })))
        assert(ns.Raids.Remove("raid00001"))
        assert.is_table(ns.Raids.Get("raid00001"))
        putOff(1, "Ashla Brightwater")
        putOff(2, "Doran Vale", "raid00002")
        reload(inboxOf(tree({ raid = "raid00002", code = "SMC002" })))
        assert.is_nil(ns.Raids.Get("raid00001"))
        assert.is_nil(saved())
        assert.are.equal(1, #saved("raid00002"))
      end)

      it("drops a saved one whose raid isn't loaded at a reload", function()
        putOff(1, "Ashla Brightwater")
        ns.db.outside.raid00009 = { { winner = "Doran Vale", link = link(2), item = 2, quantity = 1,
          at = time(), raid = "raid00009" } }
        reload()
        assert.is_nil(saved("raid00009"))
        assert.are.equal(1, #saved())
      end)

      it("leaves an open question as it is: recording it fails as not loaded, and Later lets it go",
        function()
          drop({ 1 })
          giveFromMenu(1, "Ashla Brightwater")
          assert(ns.Raids.Remove("raid00001"))
          assert.is_table(view())
          assert.are.same({ nil, "not loaded" }, { O.Record() })
          assert.are.same({}, awards())
          assert.are.same({}, wow.sent)
          later()
          assert.is_nil(saved())
          assert.are.same({}, O.Unanswered())
        end)
    end)
  end)
end)


describe("practice mode's menu hand-out (#135)", function()
  local ns, O
  local MEMBERS = { "Masterlooter", "Ashla Brightwater", "Doran Vale", "Bram Ironvein" }
  local PRACTICE_LEAD = "[Practice] You gave %s to |cffffffff%s|r from the game's loot menu. How was it won?"

  local function click(b) wow.click(function() b.scripts.OnClick(b) end) end
  local function record() click(O.frame.record) end
  local function later() click(O.frame.later) end

  local function start()
    ns = wow.start()
    O = ns.OutsideHandout
    wow.state.group = MEMBERS
    wow.state.groupIsRaid = true
    wow.state.lootMethod = { "group", 0, 0 }
    for _ = 1, 30 do wow.advance(1) end
    wow.slash("/bf practice")
    wow.printed, wow.addonMessages, wow.sent = {}, {}, {}
  end
  before_each(start)

  -- Opens Test drops until the menu case comes; returns its holder's name.
  local function openMenu()
    for _ = 1, #ns.PracticeReserves.CASES do
      assert(ns.TestDrop.Open())
      local made = ns.Popup.MadeUp(ns.TestDrop.ITEM)
      if made.menu then return made.holders[1].char end
    end
    error("no menu case")
  end

  local function askedFor(winner)
    return PRACTICE_LEAD:format(ns.TestDrop.LINK, winner)
  end

  it("acts as a hand-out from the game's menu confirmAfter seconds after the Test drop opens", function()
    local winner = openMenu()
    wow.advance(ns.TestDrop.confirmAfter - 1)
    assert.is_nil(O.Shown())
    assert.is_true(ns.TestDrop.IsOpen())
    wow.advance(1)
    assert.is_false(ns.TestDrop.IsOpen())
    assert.are.same({}, wow.gives)
    assert.is_true(O.frame:IsShown())
    assert.are.equal(askedFor(winner), O.frame.lead:GetText())
    local shown = O.Shown()
    assert.are.same({ "SR", "testdrop", false }, { shown.method, shown.boss, shown.askBoss })
    assert.is_true(O.frame.rows[2].label:GetText():find("(they soft-reserved it)", 1, true) ~= nil)
    assert.is_false(O.frame.boss:IsShown())
    assert.are.same({ "Record and announce", true },
      { O.frame.record.label:GetText(), O.frame.record:IsEnabled() })
    assert.are.same({ "Later", true }, { O.frame.later.label:GetText(), O.frame.later:IsEnabled() })
  end)

  it("records one practice award with no raid, posts one [Practice] line and sends nothing", function()
    local winner = openMenu()
    wow.advance(ns.TestDrop.confirmAfter)
    record()
    local list = ns.Raids.NoRaidAwards()
    assert.are.equal(1, #list)
    local a = list[1]
    assert.are.same({ true, nil, "testdrop", "SR", "confirmed", winner, "practice-" .. winner:lower() },
      { a.practice, a.raid, a.boss, a.method, a.state, a.char, a.user })
    assert.are.equal(1, #wow.sent)
    assert.are.equal("[Practice] ", wow.sent[1].text:sub(1, 11))
    assert.are.equal(ns.OpText.BuildLine("award", { raid = "PTEST0", key = a.key, item = ns.TestDrop.ITEM,
      link = ns.TestDrop.LINK, boss = "testdrop", method = "SR", winner = winner, practice = true }),
      wow.sent[1].text)
    for _ = 1, 60 do wow.advance(1) end
    assert.are.same({}, wow.addonMessages)
    assert.are.same({}, wow.gives)
    assert.is_nil(O.Shown())
  end)

  it("asks and records though the run is not a guild run", function()
    assert.is_true(ns.Selection.ChooseOff())
    local winner = openMenu()
    wow.advance(ns.TestDrop.confirmAfter)
    assert.are.equal(askedFor(winner), O.frame.lead:GetText())
    record()
    assert.are.equal(1, #ns.Raids.NoRaidAwards())
    assert.are.equal(1, #wow.sent)
  end)

  it("leaves its practice award out of the Sync tab's no-raid list", function()
    openMenu()
    wow.advance(ns.TestDrop.confirmAfter)
    record()
    assert.are.equal(1, #ns.Raids.NoRaidAwards())
    assert.are.same({}, ns.Raids.RealNoRaidAwards())
  end)

  describe("put off with Later", function()
    local function row()
      local view = ns.UI.AwardsView()
      assert.is_nil(view.groups and view.groups[1])
      assert.are.equal(1, #view.practice.rows)
      return view.practice.rows[1]
    end

    it("is kept in memory only, listed in the practice group with any raid selected, Answer reopens it",
      function()
        local before = ns.db.outside
        local winner = openMenu()
        wow.advance(ns.TestDrop.confirmAfter)
        later()
        assert.is_false(O.frame:IsShown())
        assert.are.same(before, ns.db.outside)
        assert.is_nil(ns.db.outside and next(ns.db.outside))
        local r = row()
        assert.is_true(r.answerNeeded)
        assert.are.equal(winner, r.winner)
        -- the Test drop's window is long gone, and a raid is selected now
        assert.is_false(ns.TestDrop.IsOpen())
        ns.Raids.Load(assert(ns.Snapshot.Validate({
          formatVersion = 1, raid = "raid00009", code = "SMC009", env = "staging", name = "Other",
          startsAt = 1792000000, durationMin = 240, generated = 1791990000,
          addon = { version = "0.1.0", url = "https://example.invalid/addon" },
          bosses = { { id = "boss-a", name = "A", trash = false, items = { 1 } } }, reserves = {},
          awards = {},
        }, "0.1.0")), "pasted")
        assert.is_true(ns.Selection.ChooseRaid("raid00009"))
        row()
        wow.click(function() ns.OutsideHandout.Ask(r.handout) end)
        assert.are.equal(askedFor(winner), O.frame.lead:GetText())
        assert.are.equal("SR", O.Shown().method)
        record()
        assert.are.equal(1, #ns.Raids.NoRaidAwards())
        assert.are.same({}, ns.OutsideHandout.Unanswered())
      end)

    it("is listed, answered and recorded on a run that is not a guild run", function()
      assert.is_true(ns.Selection.ChooseOff())
      openMenu()
      wow.advance(ns.TestDrop.confirmAfter)
      later()
      assert.are.equal(1, #O.Unanswered())
      assert.is_true(row().answerNeeded)
      O.Ask(O.Unanswered()[1])
      record()
      assert.are.equal(1, #ns.Raids.NoRaidAwards())
    end)

    it("is drawn in the Awards tab with an Answer button", function()
      openMenu()
      wow.advance(ns.TestDrop.confirmAfter)
      later()
      ns.UI.Toggle()
      local tab = ns.UI.awards
      wow.click(function() tab.practiceToggle.scripts.OnClick() end)
      local answers = {}
      for _, line in ipairs(tab.shown) do
        if line.answerNeeded then answers[#answers + 1] = line end
      end
      assert.are.equal(1, #answers)
      assert.are.equal("Answer", answers[1].answer.label:GetText())
      click(answers[1].answer)
      assert.is_true(O.frame:IsShown())
    end)
  end)

  it("asks nothing when the officer gave the item from the pop-up first", function()
    openMenu()
    local m = ns.Popup.Build()
    local row = m.rows[1]
    wow.click(function() ns.Popup.Give(row.slot, row.item, row.winner) end)
    wow.advance(ns.TestDrop.confirmAfter + 1)
    assert.is_nil(O.Shown())
    assert.are.equal(1, #ns.Raids.NoRaidAwards())
  end)

  it("asks nothing when the Test drop was closed first", function()
    openMenu()
    ns.TestDrop.Close()
    wow.advance(ns.TestDrop.confirmAfter + 1)
    assert.is_nil(O.Shown())
    assert.is_false(O.frame:IsShown())
  end)

  it("drops the open, waiting and kept practice questions when practice mode goes off", function()
    openMenu()
    wow.advance(ns.TestDrop.confirmAfter)
    later()
    O.Ask(O.Unanswered()[1])
    O.Ask({ winner = "Doran Vale", link = ns.TestDrop.LINK, item = ns.TestDrop.ITEM, quantity = 1,
      at = time(), boss = "testdrop", practice = true, kind = "SR", user = "practice-doran vale" })
    assert.is_table(O.Shown())
    assert.are.equal(1, #O.Waiting())
    wow.slash("/bf practice")
    assert.is_nil(O.Shown())
    assert.is_false(O.frame:IsShown())
    assert.are.same({}, O.Waiting())
    assert.are.same({}, O.Unanswered())
    assert.is_nil(ns.UI.AwardsView().practice)
  end)

  it("drops a kept one too, and the ask refuses a practice hand-out with practice mode off", function()
    openMenu()
    wow.advance(ns.TestDrop.confirmAfter)
    later()
    local h = O.Unanswered()[1]
    wow.slash("/bf practice")
    assert.are.same({}, O.Unanswered())
    O.Ask(h)
    assert.is_nil(O.Shown())
  end)

  it("makes no hand-out with practice mode off, and asks about a real raid's outside hand-out", function()
    wow.slash("/bf practice")
    assert.are.same({ nil, "not practice" }, { ns.TestDrop.Open() })
    ns.Raids.Load(assert(ns.Snapshot.Validate({
      formatVersion = 1, raid = "raid00001", code = "SMC001", env = "staging", name = "Molten Core",
      startsAt = 1792000000, durationMin = 240, generated = 1791990000,
      addon = { version = "0.1.0", url = "https://example.invalid/addon" },
      bosses = { { id = "boss-lucif", name = "Lucifron", trash = false, items = { 1 } } },
      reserves = {}, awards = {},
    }, "0.1.0")), "pasted")
    assert.is_true(ns.Selection.ChooseRaid("raid00001"))
    wow.state.lootMethod = { "master", 0, 0 }
    local item = "|cffa335ee|Hitem:1::::::::60:::::|h[Item 1]|h|r"
    wow.openLoot({ { link = item, quality = 4, sourceGuid = "corpse1", candidates = MEMBERS } })
    wow.fire("LOOT_SLOT_CLEARED", 1)
    wow.fire("LOOT_SLOT_CLEARED", 1)
    wow.fire("CHAT_MSG_LOOT", "Ashla Brightwater receives loot: " .. item .. ".")
    assert.is_table(O.Shown())
    assert.is_nil(O.Shown().handout.practice)
    assert.are.equal("You gave", O.frame.lead:GetText():sub(1, 8))
  end)

  it("still drops a real outside hand-out on a quiet run, while practice mode is on", function()
    assert.is_true(ns.Selection.ChooseOff())
    O.Ask({ winner = "Doran Vale", link = ns.TestDrop.LINK, item = ns.TestDrop.ITEM, quantity = 1,
      at = time() })
    assert.is_nil(O.Shown())
    assert.are.same({}, O.Unanswered())
  end)
end)
