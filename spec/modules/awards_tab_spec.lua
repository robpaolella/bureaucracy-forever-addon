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
    it("is marked, with the three change buttons drawn greyed and doing nothing", function()
      chooseRaid(ns)
      award(ns, { state = "not-confirmed" })
      local tab = open(ns)
      assert.are.equal("Ana Vale " .. AMBER_NC, lines(tab)[2][3])
      local buttons = shownButtons(tab)
      assert.are.same({ "Try again", "Someone else", "Not handed out" },
        { buttons[1].label:GetText(), buttons[2].label:GetText(), buttons[3].label:GetText() })
      for _, b in ipairs(buttons) do
        assert.is_false(b:IsEnabled())
        assert.is_nil(b.scripts.OnClick)
        assert.is_nil(b.scripts.OnEnter)
      end
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

    it("shows the same rows under the banner, the buttons still greyed", function()
      local tab = open(ns)
      assert.is_true(tab.banner:IsShown())
      assert.are.equal("Only the loot master (Konvett) can change awards.", tab.banner:GetText())
      assert.are.equal(2, #lines(tab))
      assert.are.equal(3, #shownButtons(tab))
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
