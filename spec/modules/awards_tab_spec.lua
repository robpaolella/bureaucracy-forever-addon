local wow = require("spec.support.wow")

local RAID = "raid00001"
local T0 = 1792000000

local function clock(at) return date("%H:%M", at) end
local function grey(text) return "|cff808080" .. text .. "|r" end
local AMBER_NC = "|cffffa000NOT CONFIRMED|r"

-- A loaded, chosen raid with two bosses.
local function chooseRaid(ns)
  local tree = {
    formatVersion = 1, raid = RAID, code = "MC0001", env = "staging", name = "Molten Core",
    startsAt = T0, durationMin = 240, generated = T0 - 100,
    addon = { version = "0.1.0", url = "https://example.invalid/addon" },
    bosses = { { id = "b1", name = "Lucifron", trash = false, items = { 100 } },
      { id = "b2", name = "Magmadar", trash = false, items = { 101 } } },
    reserves = {}, awards = {},
  }
  ns.Raids.Load(assert(ns.Snapshot.Validate(tree, "0.1.0")), "pasted")
  assert(ns.Selection.ChooseRaid(RAID))
end

local function award(ns, fields)
  local record = { key = "k" .. math.random(1e9), raid = RAID, boss = "b1", item = 100, char = "Ana Vale",
    method = "HR", at = T0 + 60, state = "confirmed", stateAt = T0 + 60 }
  for k, v in pairs(fields) do record[k] = v end
  ns.db.awards = ns.db.awards or {}
  ns.db.awards[RAID] = ns.db.awards[RAID] or {}
  table.insert(ns.db.awards[RAID], record)
end

local function open(ns)
  ns.UI.Toggle()
  return ns.UI.awards
end

-- The text of every drawn piece, per line: a heading alone, or a row's cells.
local function lines(tab)
  local out = {}
  for _, line in ipairs(tab.shown) do
    if line.heading then
      out[#out + 1] = { line.heading:GetText() }
    else
      out[#out + 1] = { line.time:GetText(), line.item:GetText(), line.winner:GetText(),
        line.how:GetText(), line.roll:GetText(), line.note:GetText() }
    end
  end
  return out
end

local function shownButtons(tab)
  local out = {}
  for _, b in ipairs(tab.buttons) do
    if b:IsShown() then out[#out + 1] = b end
  end
  return out
end

describe("the Awards tab", function()
  local ns

  before_each(function()
    ns = wow.start()
    wow.state.lootMethod = { "master", 0, 0 }
    wow.state.group = { "Masterlooter" }
    wow.state.items[100] = { name = "Choker", link = "|cffa335ee[Choker]|r", icon = 1 }
  end)

  describe("with nothing to list", function()
    it("explains what will appear", function()
      chooseRaid(ns)
      local tab = open(ns)
      assert.is_true(tab.title:IsShown())
      assert.are.equal("No awards yet this raid", tab.title:GetText())
      assert.are.equal("Items you hand out with the pop-up, or from the game's loot menu, show up here "
        .. "with the time, boss, winner and how they won.", tab.hint:GetText())
      assert.is_false(tab.scroll:IsShown())
      assert.is_false(tab.summary:IsShown())
    end)

    it("explains the same with no raid chosen", function()
      local tab = open(ns)
      assert.is_true(tab.title:IsShown())
      assert.are.same({}, tab.shown)
    end)

    it("is the first tab shown, so it draws on opening and when selected again", function()
      chooseRaid(ns)
      local tab = open(ns)
      award(ns, {})
      ns.UI.tabButtons.Reserves.scripts.OnClick()
      ns.UI.tabButtons.Awards.scripts.OnClick()
      assert.are.equal(2, #tab.shown)
    end)
  end)

  describe("the list", function()
    it("groups by boss, in time order inside each, with the columns' text", function()
      chooseRaid(ns)
      award(ns, { boss = "b2", item = 101, char = "Bo Marsh", method = "SR", at = T0 + 600 })
      award(ns, { boss = "b1", char = "Cy Dune", method = "OPEN_ROLL", roll = 91, at = T0 + 200 })
      award(ns, { boss = "b1", char = "Ana Vale", method = "HR", at = T0 + 100 })
      local tab = open(ns)
      assert.are.same({
        { "Lucifron · 2 items" },
        { grey(clock(T0 + 100)), "|T1:14|t |cffa335ee[Choker]|r", "Ana Vale", "Hard reserve", "", "" },
        { grey(clock(T0 + 200)), "|T1:14|t |cffa335ee[Choker]|r", "Cy Dune", "Open roll", "91", "" },
        { "Magmadar · 1 item" },
        { grey(clock(T0 + 600)), "Item 101", "Bo Marsh", "Soft reserve", "", "" },
      }, lines(tab))
      assert.is_true(tab.scroll:IsShown())
      assert.is_false(tab.title:IsShown())
    end)

    it("names the disenchant method and an award with no boss under Other", function()
      chooseRaid(ns)
      award(ns, { method = "DISENCHANT_BANK" })
      ns.db.awards[RAID][1].boss = nil
      local shown = lines(open(ns))
      assert.are.equal("Other · 1 item", shown[1][1])
      assert.are.equal("Disenchant/bank", shown[2][4])
    end)

    it("sums up the awards and the ones not confirmed, naming only counts that exist", function()
      chooseRaid(ns)
      award(ns, {})
      local tab = open(ns)
      assert.are.equal("1 award", tab.summary:GetText())
      award(ns, { state = "not-confirmed" })
      award(ns, {})
      ns.UI.RefreshAwards()
      assert.are.equal("3 awards · 1 not confirmed", tab.summary:GetText())
    end)

    it("leaves voided and practice awards out of the count", function()
      chooseRaid(ns)
      award(ns, {})
      award(ns, { voided = true })
      award(ns, { practice = true })
      assert.are.equal("1 award", open(ns).summary:GetText())
    end)
  end)

  describe("a voided award", function()
    it("is struck through and shows its reason", function()
      chooseRaid(ns)
      award(ns, { voided = true, voidReason = "wrong winner", voidedAt = T0 + 120 })
      local tab = open(ns)
      local row = lines(tab)[2]
      assert.are.equal(grey("Ana Vale"), row[3])
      assert.are.equal(grey("Hard reserve"), row[4])
      assert.are.equal("wrong winner", row[6])
      assert.is_true(tab.strikes[1]:IsShown())
      assert.are.equal(0, #shownButtons(tab))
    end)

    it("shows when it was undone when no reason was given", function()
      chooseRaid(ns)
      award(ns, { voided = true, voidedAt = T0 + 120 })
      assert.are.equal("Undone " .. clock(T0 + 120), lines(open(ns))[2][6])
    end)

    it("draws no line through a standing award", function()
      chooseRaid(ns)
      award(ns, {})
      local tab = open(ns)
      assert.is_nil(tab.strikes[1])
    end)
  end)

  describe("a not confirmed award", function()
    it("is marked, with the loot master's three choices", function()
      chooseRaid(ns)
      award(ns, { state = "not-confirmed" })
      local tab = open(ns)
      assert.are.equal("Ana Vale " .. AMBER_NC, lines(tab)[2][3])
      assert.are.equal(0, #shownButtons(tab))
      local buttons = tab.shown[2].choices
      assert.are.same({ "Try again", "Someone else", "Not handed out" },
        { buttons[1].label:GetText(), buttons[2].label:GetText(), buttons[3].label:GetText() })
    end)

    it("draws no buttons for a confirmed award, nor for a voided one", function()
      chooseRaid(ns)
      award(ns, {})
      award(ns, { state = "not-confirmed", voided = true })
      assert.are.equal(0, #shownButtons(open(ns)))
    end)
  end)

  describe("the practice awards", function()
    it("sit apart in a group at the foot, closed until opened", function()
      chooseRaid(ns)
      award(ns, {})
      award(ns, { practice = true, at = T0 + 10 })
      award(ns, { practice = true, at = T0 + 20, method = "OPEN_ROLL", roll = 77 })
      local tab = open(ns)
      local shown = lines(tab)
      assert.are.equal(3, #shown)
      assert.are.equal("+ Practice awards (2) · never sent to the guild site", shown[3][1])
      assert.is_true(tab.practiceToggle:IsShown())
      wow.click(function() tab.practiceToggle.scripts.OnClick() end)
      shown = lines(tab)
      assert.are.equal(5, #shown)
      assert.are.equal("- Practice awards (2) · never sent to the guild site", shown[3][1])
      assert.are.equal("77", shown[5][5])
      assert.are.equal("|cffffa000Practice|r", shown[4][6])
      wow.click(function() tab.practiceToggle.scripts.OnClick() end)
      assert.are.equal(3, #lines(tab))
    end)

    it("alone still draw the list, with the group and no summary counts", function()
      chooseRaid(ns)
      award(ns, { practice = true })
      local tab = open(ns)
      assert.are.equal("", tab.summary:GetText())
      assert.are.equal(1, #lines(tab))
      assert.is_false(tab.title:IsShown())
    end)
  end)

  describe("for another officer", function()
    before_each(function()
      wow.state.group = { "Masterlooter", "Konvett" }
      wow.state.groupIsRaid = true
      wow.state.lootMethod = { "master", nil, 2 }
      chooseRaid(ns)
      award(ns, { state = "not-confirmed" })
    end)

    it("shows the same rows under the banner, the buttons still greyed and doing nothing", function()
      local tab = open(ns)
      assert.is_true(tab.banner:IsShown())
      assert.are.equal("Only the loot master (Konvett) can change awards.", tab.banner:GetText())
      assert.are.equal(2, #lines(tab))
      local buttons = shownButtons(tab)
      assert.are.same({ "Try again", "Someone else", "Not handed out" },
        { buttons[1].label:GetText(), buttons[2].label:GetText(), buttons[3].label:GetText() })
      for _, b in ipairs(buttons) do
        assert.is_false(b:IsEnabled())
        assert.is_nil(b.scripts.OnClick)
        assert.is_nil(b.scripts.OnEnter)
      end
      assert.is_nil(tab.shown[2].choices)
    end)

    it("has the banner no more once this player is the loot master", function()
      local tab = open(ns)
      wow.state.lootMethod = { "master", 0, 0 }
      wow.fire("PARTY_LOOT_METHOD_CHANGED")
      assert.is_false(tab.banner:IsShown())
    end)
  end)

  describe("the footer's loot master line", function()
    it("names the loot master, marking this player", function()
      open(ns)
      assert.are.equal("Loot master: Masterlooter (you)", ns.UI.awards.footer:GetText())
    end)

    it("names another officer without the mark", function()
      wow.state.group = { "Masterlooter", "Konvett" }
      wow.state.groupIsRaid = true
      wow.state.lootMethod = { "master", nil, 2 }
      open(ns)
      assert.are.equal("Loot master: Konvett", ns.UI.awards.footer:GetText())
    end)

    it("says so when master loot is off, and the list still shows", function()
      wow.state.lootMethod = { "group", 0, 0 }
      chooseRaid(ns)
      award(ns, {})
      local tab = open(ns)
      assert.are.equal("No loot master (master loot is off)", tab.footer:GetText())
      assert.is_false(tab.banner:IsShown())
      assert.are.equal(2, #lines(tab))
    end)

    it("follows the loot method while another tab is open", function()
      open(ns)
      ns.UI.tabButtons.Sync.scripts.OnClick()
      wow.state.lootMethod = { "group", 0, 0 }
      wow.fire("PARTY_LOOT_METHOD_CHANGED")
      assert.are.equal("No loot master (master loot is off)", ns.UI.awards.footer:GetText())
    end)
  end)
end)

-- The loot master's choices on a not confirmed row (#101): the pop-up's three, from the Awards tab.
describe("the Awards tab's not confirmed choices", function()
  local ns
  local LINK = "|cffa335ee|Hitem:100::::::::60:::::|h[Choker]|h|r"
  local GROUP = { "Masterlooter", "Ana Vale", "Bo Marsh" }
  local function holder(char, kind) return { user = char:lower():gsub("%s", ""), char = char, kind = kind,
    trial = false } end

  -- A fresh session, as after a /reload: only the saved data survives, so no hand-out is followed.
  local function session(saved)
    ns = wow.start(saved and { saved = { BureaucracyForeverDB = saved } } or nil)
    wow.state.group, wow.state.groupIsRaid = GROUP, true
    wow.state.lootMethod = { "master", 0, 0 }
    wow.state.items[100] = { name = "Choker", link = LINK, icon = 1 }
  end

  local function drop()
    wow.openLoot({ { id = 100, link = LINK, quality = 4, sourceGuid = "corpse1", candidates = GROUP } })
  end

  local function click(button)
    wow.click(function() button.scripts.OnClick(button) end)
  end

  -- Choker handed to Ana Vale from the pop-up, not confirmed by the game, then a /reload. Returns
  -- the tab, opened, with the loot window closed.
  local function unconfirmed()
    session()
    local tree = {
      formatVersion = 1, raid = RAID, code = "SA0001", env = "staging", name = "Molten Core",
      startsAt = T0, durationMin = 240, generated = T0 - 100,
      addon = { version = "0.1.0", url = "https://example.invalid/addon" },
      bosses = { { id = "lb_lucifron", name = "Lucifron", trash = false, items = { 100 } } },
      reserves = { [100] = { holder("Ana Vale", "HR"), holder("Bo Marsh", "SR") } }, awards = {},
    }
    ns.Raids.Load(assert(ns.Snapshot.Validate(tree, "0.1.0")), "pasted")
    assert(ns.Selection.ChooseRaid(RAID))
    drop()
    assert(ns.Popup.PickBoss("lb_lucifron"))
    wow.click(function() assert(ns.Popup.Give(1, 100, "Ana Vale")) end)
    wow.advance(ns.Tracking.confirmWait)
    wow.closeLoot()
    session(BureaucracyForeverDB)
    assert.are.same({}, ns.Tracking.Pending())
    ns.UI.Toggle()
    return ns.UI.awards
  end

  local function keyOf(char)
    for _, a in ipairs(ns.Raids.Awards(RAID)) do
      if a.char == char and not a.voided then return a.key end
    end
  end

  -- The drawn line of the award row naming char.
  local function rowOf(tab, char)
    for _, line in ipairs(tab.shown) do
      if line.winner and line.winner:GetText():find(char, 1, true) then return line end
    end
  end

  local function enabled(buttons)
    local out = {}
    for i, b in ipairs(buttons) do out[i] = b:IsEnabled() end
    return out
  end

  -- What a refusal must leave alone: the records, the hand-outs and raid chat.
  local function unchanged(fn)
    local before = { #ns.Raids.Awards(RAID), ns.Records.Get(keyOf("Ana Vale")).state, #wow.gives, #wow.sent }
    fn()
    assert.are.same(before, { #ns.Raids.Awards(RAID), ns.Records.Get(keyOf("Ana Vale")).state, #wow.gives,
      #wow.sent })
  end

  it("are enabled for the loot master, after a /reload, with no refusal", function()
    local tab = unconfirmed()
    local row = rowOf(tab, "Ana Vale")
    assert.are.same({ true, true, true }, enabled(row.choices))
    assert.is_nil(row.refusal)
  end)

  it("Try again hands the item to the same winner again; confirmed once the game says so", function()
    local tab = unconfirmed()
    drop()
    local sent = #wow.sent
    click(rowOf(tab, "Ana Vale").choices[1])
    assert.are.same({ { slot = 1, candidate = 2 } }, wow.gives)
    assert.are.equal(sent, #wow.sent)
    wow.fire("LOOT_SLOT_CLEARED", 1)
    wow.fire("CHAT_MSG_LOOT", "Ana Vale receives loot: " .. LINK .. ".")
    assert.are.equal("confirmed", ns.Records.Get(keyOf("Ana Vale")).state)
    local row = rowOf(tab, "Ana Vale")
    assert.are.equal("Ana Vale", row.winner:GetText())
    assert.is_nil(row.choices)
  end)

  it("Not handed out works with the loot window closed: the award is voided and the undo line posted",
    function()
      local tab = unconfirmed()
      local key = keyOf("Ana Vale")
      local sent = #wow.sent
      click(rowOf(tab, "Ana Vale").choices[3])
      assert.is_true(ns.Records.Get(key).voided)
      assert.are.equal(sent + 1, #wow.sent)
      assert.is_truthy(wow.sent[#wow.sent].text:find("Undo:", 1, true))
      local row = rowOf(tab, "Ana Vale")
      assert.is_true(row.voided)
      assert.is_nil(row.choices)
      assert.are.equal(0, #shownButtons(tab))
    end)

  it("Give to someone else opens the list in the row, built from the award alone; Back closes it", function()
    local tab = unconfirmed()
    click(rowOf(tab, "Ana Vale").choices[2])
    local row = rowOf(tab, "Ana Vale")
    assert.is_nil(row.choices)
    local list = row.list
    assert.is_true(list:IsShown())
    assert.are.equal(list, tab.list)
    assert.are.equal("Give " .. LINK .. " to someone else", list.title:GetText())
    assert.are.same({ "Bo Marsh", "SOFT RESERVE", true }, { list.entries[1].name:GetText(),
      list.entries[1].method:GetText(), list.entries[1].give:IsShown() })
    assert.is_nil(list.entries[2])
    assert.are.equal("Posts one correction line: Correction: " .. LINK .. " → their name, not Ana Vale.",
      list.hint:GetText())
    assert.are.same({ tab.child, 48 }, { list.points[1].relativeTo, list.points[1].x })
    click(list.back)
    assert.is_false(tab.list:IsShown())
    assert.are.same({ true, true, true }, enabled(rowOf(tab, "Ana Vale").choices))
  end)

  it("Give to someone else's list moves the rows below it down", function()
    local tab = unconfirmed()
    local other = { key = "k2", raid = RAID, boss = "lb_lucifron", item = 100, char = "Bo Marsh",
      method = "SR",
      at = T0 + 999999999, state = "confirmed", stateAt = T0 }
    table.insert(ns.db.awards[RAID], other)
    ns.UI.RefreshAwards()
    local before = rowOf(tab, "Bo Marsh").item.points[1].y
    click(rowOf(tab, "Ana Vale").choices[2])
    local list = tab.list
    -- The list takes the three buttons' place (20 high and a 4 gap) and grows the row by the rest.
    assert.are.equal(before - (list:GetHeight() - 24), rowOf(tab, "Bo Marsh").item.points[1].y)
  end)

  it("giving to a listed person hands it out, posts the one correction line and replaces the award",
    function()
      local tab = unconfirmed()
      local key = keyOf("Ana Vale")
      drop()
      click(rowOf(tab, "Ana Vale").choices[2])
      local sent = #wow.sent
      click(tab.list.entries[1].give)
      assert.are.equal(sent + 1, #wow.sent)
      assert.is_truthy(wow.sent[#wow.sent].text:find("Correction:", 1, true))
      assert.are.same({ { slot = 1, candidate = 3 } }, wow.gives)
      assert.is_true(ns.Records.Get(key).voided)
      assert.is_false(tab.list:IsShown())
      assert.is_true(rowOf(tab, "Ana Vale").voided)
      assert.are.equal("Bo Marsh", rowOf(tab, "Bo Marsh").winner:GetText())
    end)

  it("only one list is open at a time across two not confirmed rows", function()
    local tab = unconfirmed()
    local second = { key = "k2", raid = RAID, boss = "lb_lucifron", item = 100, char = "Bo Marsh",
      method = "SR",
      at = T0 + 999999999, state = "not-confirmed", stateAt = T0 }
    table.insert(ns.db.awards[RAID], second)
    ns.UI.RefreshAwards()
    click(rowOf(tab, "Ana Vale").choices[2])
    assert.is_truthy(rowOf(tab, "Ana Vale").list)
    click(rowOf(tab, "Bo Marsh").choices[2])
    assert.is_truthy(rowOf(tab, "Bo Marsh").list)
    assert.is_nil(rowOf(tab, "Ana Vale").list)
    assert.are.same({ true, true, true }, enabled(rowOf(tab, "Ana Vale").choices))
  end)

  describe("refused", function()
    it("Try again with the loot window closed says so on the row", function()
      local tab = unconfirmed()
      unchanged(function() click(rowOf(tab, "Ana Vale").choices[1]) end)
      local row = rowOf(tab, "Ana Vale")
      assert.are.equal("The loot window is closed. Open it to hand the item out.", row.refusal:GetText())
      assert.is_true(row.refusal:IsShown())
      assert.are.equal("Not confirmed choice tryagain for " .. LINK .. " refused: window",
        ns.log[#ns.log].text)
      assert.are.same({ true, true, true }, enabled(row.choices))
    end)

    it("Give with the item gone from the loot window says so, the list staying open", function()
      local tab = unconfirmed()
      click(rowOf(tab, "Ana Vale").choices[2])
      wow.openLoot({ { id = 101, link = "|cffa335ee|Hitem:101::::::::60:::::|h[Ring]|h|r", quality = 4,
        sourceGuid = "corpse2", candidates = GROUP } })
      unchanged(function() click(tab.list.entries[1].give) end)
      local row = rowOf(tab, "Ana Vale")
      assert.are.equal("The item isn't in the loot window now.", row.refusal:GetText())
      assert.is_true(row.list:IsShown())
    end)

    it("while a hand-out still waits for the game, says so", function()
      local tab = unconfirmed()
      drop()
      click(rowOf(tab, "Ana Vale").choices[1])
      unchanged(function() click(rowOf(tab, "Ana Vale").choices[3]) end)
      assert.are.equal("A hand-out of it is still waiting for the game.",
        rowOf(tab, "Ana Vale").refusal:GetText())
    end)

    it("in a boss fight greys Someone else and Not handed out with the pop-up's tooltip; Try again works",
      function()
        local tab = unconfirmed()
        drop()
        wow.bossFight(true)
        local row = rowOf(tab, "Ana Vale")
        assert.are.same({ true, false, false }, enabled(row.choices))
        assert.is_nil(row.choices[1].tip)
        for i = 2, 3 do
          assert.are.equal("Posts a line, so it waits until the boss fight ends", row.choices[i].tip)
          row.choices[i].scripts.OnEnter(row.choices[i])
          assert.are.same({ "Posts a line, so it waits until the boss fight ends" }, GameTooltip.lines)
        end
        unchanged(function() click(row.choices[3]) end)
        click(row.choices[1])
        assert.are.equal(1, #wow.gives)
        wow.bossFight(false)
      end)

    it("in a boss fight the tab hasn't redrawn for yet, says chat is locked", function()
      local tab = unconfirmed()
      wow.state.chatLockdown = true
      unchanged(function() click(rowOf(tab, "Ana Vale").choices[3]) end)
      local row = rowOf(tab, "Ana Vale")
      assert.are.equal("Chat is locked in the boss fight. Try again works now; the other two wait until it"
        .. " ends.", row.refusal:GetText())
      assert.are.same({ true, false, false }, enabled(row.choices))
    end)

    it("for a player no longer the loot master, the row then greyed", function()
      local tab = unconfirmed()
      drop()
      wow.state.lootMethod = { "master", nil, 2 }
      unchanged(function() click(rowOf(tab, "Ana Vale").choices[1]) end)
      local row = rowOf(tab, "Ana Vale")
      assert.is_nil(row.choices)
      assert.are.equal(3, #shownButtons(tab))
      assert.are.equal("Only the loot master can hand items out.", row.refusal:GetText())
    end)

    it("for an award settled meanwhile, and the row redraws as settled", function()
      local tab = unconfirmed()
      local key = keyOf("Ana Vale")
      assert(ns.Records.Void(key, { reason = "wrong winner" }))
      local sent = #wow.sent
      click(rowOf(tab, "Ana Vale").choices[3])
      assert.are.equal(sent, #wow.sent)
      local row = rowOf(tab, "Ana Vale")
      assert.is_true(row.voided)
      assert.is_nil(row.choices)
      assert.is_nil(row.refusal)
    end)

    it("clears once the loot window closes", function()
      local tab = unconfirmed()
      drop()
      wow.state.loot[1].candidates = { "Masterlooter", "Bo Marsh" }
      click(rowOf(tab, "Ana Vale").choices[1])
      assert.are.equal("The game won't let them receive it now (usually: not nearby when the boss died).",
        rowOf(tab, "Ana Vale").refusal:GetText())
      wow.closeLoot()
      assert.is_nil(rowOf(tab, "Ana Vale").refusal)
    end)
  end)

  it("a not confirmed Disenchant/bank award names no winner and needs a D/B pick", function()
    local tab = unconfirmed()
    local db = { key = "kdb", raid = RAID, boss = "lb_lucifron", item = 100, method = "DISENCHANT_BANK",
      at = T0 + 999999999, state = "not-confirmed", stateAt = T0 }
    table.insert(ns.db.awards[RAID], db)
    drop()
    local line
    for _, l in ipairs(tab.shown) do if l.how and l.how:GetText() == "Disenchant/bank" then line = l end end
    assert.are.same({ true, true, true }, enabled(line.choices))
    click(line.choices[1])
    for _, l in ipairs(tab.shown) do if l.how and l.how:GetText() == "Disenchant/bank" then line = l end end
    assert.are.equal("No disenchant/bank character is chosen for this raid. Choose one with D/B first.",
      line.refusal:GetText())
    click(line.choices[2])
    assert.is_truthy(tab.list.hint:GetText():find("not disenchant/bank.", 1, true))
  end)

  it("a not confirmed practice award has the same choices in the practice group", function()
    local tab = unconfirmed()
    local key = keyOf("Ana Vale")
    ns.Records.Get(key).practice = true
    ns.UI.RefreshAwards()
    assert.is_nil(rowOf(tab, "Ana Vale"))
    wow.click(function() tab.practiceToggle.scripts.OnClick() end)
    click(rowOf(tab, "Ana Vale").choices[3])
    assert.is_true(ns.Records.Get(key).voided)
    assert.is_true(rowOf(tab, "Ana Vale").voided)
  end)

  it("closes the list when the tab is drawn without its row", function()
    local tab = unconfirmed()
    click(rowOf(tab, "Ana Vale").choices[2])
    ns.db.awards[RAID][1].practice = true
    ns.UI.RefreshAwards()
    assert.is_false(tab.list:IsShown())
    assert.is_nil(tab.elseOpen)
  end)
end)
