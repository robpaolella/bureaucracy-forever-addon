local wow = require("spec.support.wow")

local VERSION_LINE = "|cff33ff99Bureaucracy:|r version "

local function item(name)
  return { link = "[" .. name .. "]", name = name, quality = 4, quantity = 1, candidates = { "Alice" } }
end

describe("the officers' window", function()
  local ns

  before_each(function() ns = wow.start() end)

  it("saves nothing until the officer changes something", function()
    assert.are.same({}, ns.db)
  end)

  it("starts closed, titled and with three tabs", function()
    assert.is_false(ns.UI.window:IsShown())
    for _, name in ipairs({ "Awards", "Reserves", "Sync" }) do
      assert.are.equal(name, ns.UI.tabButtons[name].label:GetText())
      assert.is_table(ns.UI.tabs[name])
    end
    assert.is_table(ns.UI.footer)
  end)

  it("opens and closes with /bf", function()
    wow.slash("/bf")
    assert.is_true(ns.UI.window:IsShown())
    wow.slash("/bf")
    assert.is_false(ns.UI.window:IsShown())
    assert.are.same({}, wow.printed)
  end)

  it("prints the .toc's version for /bf version", function()
    local metadata = wow.readToc()
    wow.slash("/bf version")
    assert.are.same({ VERSION_LINE .. metadata.Version .. "." }, wow.printed)
    assert.is_false(ns.UI.window:IsShown())
  end)

  it("lists the commands for one it doesn't know", function()
    wow.slash("/bf nonsense")
    assert.are.equal(1, #wow.printed)
    assert.is_truthy(wow.printed[1]:find("/bf version", 1, true))
    assert.is_false(ns.UI.window:IsShown())
  end)

  it("closes with Escape", function()
    assert.are.same({ "BureaucracyForeverWindow" }, _G.UISpecialFrames)
  end)

  it("shows the Awards tab first, then the tab clicked, each with its placeholder", function()
    local buttons = ns.UI.tabButtons
    assert.are.equal("Awards", ns.UI.selected)
    assert.is_true(ns.UI.tabs.Awards:IsShown())
    assert.is_false(ns.UI.tabs.Reserves:IsShown())
    assert.is_false(ns.UI.tabs.Sync:IsShown())
    assert.is_true(buttons.Awards.selected)
    buttons.Sync.scripts.OnClick()
    assert.are.equal("Sync", ns.UI.selected)
    assert.is_false(ns.UI.tabs.Awards:IsShown())
    assert.is_true(ns.UI.tabs.Sync:IsShown())
    assert.is_false(buttons.Awards.selected)
    assert.is_true(buttons.Sync.selected)
    buttons.Reserves.scripts.OnClick()
    assert.is_true(ns.UI.tabs.Reserves:IsShown())
    assert.is_false(ns.UI.tabs.Sync:IsShown())
    for _, content in pairs(ns.UI.tabs) do assert.is_string(content.placeholder:GetText()) end
  end)

  it("loads when the client has only the templates and fonts it has confirmed", function()
    -- The stand-in refuses any other template or font name, as the game does.
    assert.are.same({ BasicFrameTemplateWithInset = true }, wow.knownTemplates)
    assert.has_error(function() _G.CreateFrame("Frame", nil, nil, "CharacterFrameTabButtonTemplate") end)
    assert.are.equal("BasicFrameTemplateWithInset", ns.UI.window.template)
  end)
end)

describe("the minimap button", function()
  local ns

  before_each(function() ns = wow.start() end)

  local function hover()
    ns.UI.button.scripts.OnEnter(ns.UI.button)
    return _G.GameTooltip.lines
  end

  it("says no raid is loaded and how to use it", function()
    assert.are.same({
      "Bureaucracy Forever", "No raids loaded.", "Click: open the window", "Drag: move the button",
    }, hover())
    ns.UI.button.scripts.OnLeave()
  end)

  it("counts hand-outs not confirmed, in singular and plural", function()
    wow.openLoot({ item("Choker"), item("Ring") })
    wow.click(function() ns.Tracking.Give(1, 1) end)
    assert.are.same({
      "Bureaucracy Forever", "No raids loaded.", "1 hand-out not confirmed",
      "Click: open the window", "Drag: move the button",
    }, hover())
    assert.is_true(ns.UI.badge:IsShown())
    assert.are.equal(1, ns.UI.badge.text:GetText())
    wow.click(function() ns.Tracking.Give(2, 1) end)
    assert.are.equal("2 hand-outs not confirmed", hover()[3])
  end)

  it("keeps counting a hand-out that timed out", function()
    wow.openLoot({ item("Choker") })
    wow.click(function() ns.Tracking.Give(1, 1) end)
    wow.advance(ns.Tracking.confirmWait)
    assert.are.equal("1 hand-out not confirmed", hover()[3])
    assert.is_true(ns.UI.badge:IsShown())
    assert.are.equal(1, ns.UI.badge.text:GetText())
  end)

  it("hides the badge when nothing is waiting", function()
    assert.is_false(ns.UI.badge:IsShown())
    wow.openLoot({ item("Choker") })
    wow.click(function() ns.Tracking.Give(1, 1) end)
    hover()
    assert.is_true(ns.UI.badge:IsShown())
    wow.fire("LOOT_SLOT_CLEARED", 1)
    wow.fire("CHAT_MSG_LOOT", "Alice receives loot: [Choker].")
    assert.is_false(ns.UI.badge:IsShown())
  end)

  it("opens and closes the window on a click", function()
    ns.UI.button.scripts.OnClick()
    assert.is_true(ns.UI.window:IsShown())
    ns.UI.button.scripts.OnClick()
    assert.is_false(ns.UI.window:IsShown())
  end)

  it("follows the cursor while dragged, and keeps the spot", function()
    local button = ns.UI.button
    -- The minimap's centre is (1300, 800): a cursor straight above it puts the button at 90 degrees.
    wow.state.cursor = { 1300, 900 }
    button.scripts.OnDragStart(button)
    button.scripts.OnUpdate()
    local point = button.points[1]
    assert.is_true(math.abs(point.x) < 1e-6)
    assert.is_true(point.y > 0)
    wow.state.cursor = { 1200, 800 }
    button.scripts.OnDragStop(button)
    assert.is_nil(button.scripts.OnUpdate)
    assert.are.near(math.pi, ns.db.ui.minimap.angle, 1e-6)
    assert.is_true(button.points[1].x < 0)
  end)

  it("shows and hides with /bf minimap", function()
    wow.slash("/bf minimap")
    assert.is_false(ns.UI.button:IsShown())
    assert.is_true(ns.db.ui.minimap.hidden)
    wow.slash("/bf minimap")
    assert.is_true(ns.UI.button:IsShown())
  end)
end)

describe("what the window remembers", function()
  local screen
  before_each(function() screen = nil end)

  local function reload(ns)
    return wow.start({ saved = { BureaucracyForeverDB = ns.db }, screen = screen })
  end

  it("keeps the window's spot and whether it was open across /reload", function()
    local ns = wow.start()
    wow.slash("/bf")
    local window = ns.UI.window
    window.center = { 1000, 300 } -- the officer drags it
    window.scripts.OnDragStop(window)
    ns = reload(ns)
    assert.is_true(ns.UI.window:IsShown())
    local x, y = ns.UI.window:GetCenter()
    assert.are.same({ 1000, 300 }, { x, y })
  end)

  it("stays closed across /reload if it was closed", function()
    local ns = wow.start()
    wow.slash("/bf")
    wow.slash("/bf")
    ns = reload(ns)
    assert.is_false(ns.UI.window:IsShown())
  end)

  it("keeps the button's spot and whether it was hidden", function()
    local ns = wow.start()
    wow.state.cursor = { 1200, 800 }
    ns.UI.button.scripts.OnDragStart(ns.UI.button)
    ns.UI.button.scripts.OnDragStop(ns.UI.button)
    wow.slash("/bf minimap")
    ns = reload(ns)
    assert.is_false(ns.UI.button:IsShown())
    assert.are.near(math.pi, ns.db.ui.minimap.angle, 1e-6)
    assert.is_true(ns.UI.button.points[1].x < 0)
  end)

  it("puts the window back in the default spot when the saved one is off the screen", function()
    local ns = wow.start()
    ns.db.ui = { window = { x = 5000, y = 0 } } -- saved on a bigger screen
    ns = reload(ns)
    local x, y = ns.UI.window:GetCenter()
    assert.are.same({ 960, 540 }, { x, y })
    ns.db.ui = { window = { x = 0, y = -900 } }
    ns = reload(ns)
    assert.are.same({ 960, 540 }, { ns.UI.window:GetCenter() })
    -- The centre is on the screen but the 640 wide window would stick out 100 pixels.
    screen = { width = 1440, height = 900 }
    ns.db.ui = { window = { x = 500, y = 0 } }
    ns = reload(ns)
    assert.are.same({ 720, 450 }, { ns.UI.window:GetCenter() })
    -- A spot that fits exactly is kept.
    ns.db.ui = { window = { x = 400, y = 0 } }
    ns = reload(ns)
    assert.are.same({ 1120, 450 }, { ns.UI.window:GetCenter() })
  end)

  it("ignores saved spots that aren't numbers", function()
    local ns = wow.start()
    ns.db.ui = { window = { x = "left", y = 0 }, minimap = { angle = 0 / 0 } }
    ns = reload(ns)
    assert.are.same({ 960, 540 }, { ns.UI.window:GetCenter() })
    assert.is_true(ns.UI.button:IsShown())
  end)
end)

local function holder(user, char, kind, extra)
  local h = { user = user, char = char, kind = kind, trial = false }
  for k, v in pairs(extra or {}) do h[k] = v end
  return h
end

-- A raid with two bosses and trash, loaded and chosen. Item 100 and 101 drop from Lucifron,
-- 101 also from Magmadar, 102 from Trash; 103 is reserved but on no boss.
local function chooseRaid(ns, fields)
  local tree = {
    formatVersion = 1, raid = "raid00001", code = "MC0001", env = "staging", name = "Molten Core",
    startsAt = 1792000000, durationMin = 240, generated = 1791990000,
    addon = { version = "0.1.0", url = "https://example.invalid/addon" },
    bosses = {
      { id = "b1", name = "Lucifron", trash = false, items = { 100, 101, 104 } },
      { id = "b2", name = "Magmadar", trash = false, items = { 101, 105 } },
      { id = "b3", name = "Trash", trash = true, items = { 102 } },
    },
    reserves = {
      [100] = { holder("u1", "Ashla Brightwater", "HR"), holder("u2", "Doran Vale", "SR"),
        holder("u3", "Kessa Moorfield", "SR") },
      [101] = { holder("u1", "Ashla Brightwater", "HR"), holder("u4", "Lyra Dawnmere", "HR",
        { trial = true }) },
      [102] = { holder("u2", "Doran Vale", "SR") },
      [103] = { holder("u5", "Pell Harrow", "SR") },
      [104] = {},
    },
    awards = {},
  }
  for k, v in pairs(fields or {}) do tree[k] = v end
  local snapshot = assert(ns.Snapshot.Validate(tree, "0.1.0"))
  ns.Raids.Load(snapshot, "pasted")
  assert(ns.Selection.ChooseRaid(tree.raid))
end

local function names(ns)
  ns.UI.Toggle()
  ns.UI.tabButtons.Reserves.scripts.OnClick()
  return ns.UI.reserves.shown
end

local function texts(shown)
  local out = {}
  for _, line in ipairs(shown) do
    if line.heading then
      out[#out + 1] = { line.heading:GetText() }
    else
      out[#out + 1] = { line.item:GetText(), line.hr:GetText(), line.sr:GetText() }
    end
  end
  return out
end

local TICK = "|TInterface\\Buttons\\UI-CheckBox-Check:12|t"
local function grey(text) return "|cff808080" .. text .. "|r" end

describe("the Reserves tab", function()
  local ns

  before_each(function()
    ns = wow.start()
    wow.state.group = { "Masterlooter", "Ashla Brightwater", "Doran Vale", "Lyra Dawnmere" }
    wow.state.groupIsRaid = true
    wow.state.items[100] = { name = "Choker", link = "|cffa335ee[Choker]|r", icon = 12345 }
  end)

  it("groups reserved items by boss, with hard and soft names, in the snapshot's order", function()
    chooseRaid(ns)
    local lines = texts(names(ns))
    assert.are.same({ "Lucifron" }, lines[1])
    assert.are.same({ "|T12345:14|t |cffa335ee[Choker]|r", "Ashla Brightwater",
      "Doran Vale, " .. grey("Kessa Moorfield") }, lines[2])
    -- An item the game hasn't told the add-on about yet shows its number.
    assert.are.equal("Item 101", lines[3][1])
    assert.are.same({ "Magmadar" }, lines[4])
    assert.are.equal("Item 101", lines[5][1]) -- an item on two bosses appears under each
    assert.are.same({ "Trash" }, lines[6])
    assert.are.equal("Item 102", lines[7][1])
    assert.are.same({ "Other" }, lines[8]) -- reserved, but on no boss
    assert.are.equal("Item 103", lines[9][1])
    assert.are.equal(9, #lines) -- Item 104 has no holders, boss Magmadar's 105 no reserves
  end)

  it("shows '-' for a column nobody reserved in", function()
    chooseRaid(ns)
    local lines = texts(names(ns))
    assert.are.equal(grey("-"), lines[7][2]) -- trash: no hard reserve
    assert.are.equal(grey("-"), lines[3][3]) -- item 101: no soft reserve
  end)

  it("greys holders who are not in the group, matching names without a realm", function()
    chooseRaid(ns)
    names(ns)
    wow.state.group = { "Masterlooter-Realm", "Ashla Brightwater-Realm" }
    ns.UI.RefreshReserves()
    local lines = texts(ns.UI.reserves.shown)
    assert.are.equal("Ashla Brightwater", lines[2][2])
    assert.are.equal(grey("Doran Vale") .. ", " .. grey("Kessa Moorfield"), lines[2][3])
  end)

  it("uses the party when the group is not a raid, and the player alone when ungrouped", function()
    chooseRaid(ns)
    wow.state.groupIsRaid = false
    wow.state.group = { "Masterlooter", "Ashla Brightwater" }
    assert.are.equal("Ashla Brightwater", texts(names(ns))[2][2])
    wow.state.group = {}
    ns.UI.RefreshReserves()
    assert.are.equal(grey("Ashla Brightwater"), texts(ns.UI.reserves.shown)[2][2])
  end)

  it("ticks a holder who received the item, from the baseline or the raid's own awards", function()
    chooseRaid(ns, { awards = {
      { key = "k1", boss = "b1", item = 100, char = "Ashla Brightwater", user = "u1", method = "HR",
        voided = false },
    } })
    ns.db.awards = { raid00001 = {
      { key = "k2", boss = "b3", item = 102, char = "Doran Vale", user = "u2", method = "SR",
        voided = false },
    } }
    local lines = texts(names(ns))
    assert.are.equal("Ashla Brightwater " .. TICK, lines[2][2])
    assert.are.equal("Doran Vale, " .. grey("Kessa Moorfield"), lines[2][3]) -- only item 100 spent
    assert.are.equal("Doran Vale " .. TICK, lines[7][3])
  end)

  it("does not tick a voided award", function()
    chooseRaid(ns, { awards = {
      { key = "k1", boss = "b1", item = 100, char = "Ashla Brightwater", user = "u1", method = "HR",
        voided = true },
    } })
    assert.are.equal("Ashla Brightwater", texts(names(ns))[2][2])
  end)

  it("marks trial holders and keeps them in the list", function()
    chooseRaid(ns)
    assert.are.equal("Ashla Brightwater, Lyra Dawnmere " .. grey("(trial)"), texts(names(ns))[3][2])
  end)

  it("greys an absent trial holder", function()
    chooseRaid(ns)
    names(ns)
    wow.state.group = { "Masterlooter" }
    ns.UI.RefreshReserves()
    assert.are.equal(grey("Ashla Brightwater") .. ", " .. grey("Lyra Dawnmere") .. " " .. grey("(trial)"),
      texts(ns.UI.reserves.shown)[3][2])
  end)

  it("keeps a name's own bars from becoming colour codes", function()
    wow.state.group = { "Masterlooter", "Evil|cffff0000Red" }
    chooseRaid(ns, { reserves = { [100] = { holder("u1", "Evil|cffff0000Red", "HR") } } })
    assert.are.equal("Evil||cffff0000Red", texts(names(ns))[2][2])
  end)

  it("shows the raid, its date, the player count and the reserve count", function()
    chooseRaid(ns)
    names(ns)
    local when = date("%a %d %b", 1792000000)
    -- Five distinct players hold seven reserves; Ashla and Doran each hold two.
    assert.are.equal("Molten Core, " .. when .. " · 5 players · 7 reserves", ns.UI.reserves.header:GetText())
  end)

  it("counts one player and one reserve in the singular", function()
    chooseRaid(ns, { reserves = { [100] = { holder("u1", "Ashla Brightwater", "HR") } } })
    names(ns)
    assert.is_truthy(ns.UI.reserves.header:GetText():find("1 player · 1 reserve$"))
  end)

  it("has a key for received, grey and trial", function()
    chooseRaid(ns)
    names(ns)
    assert.are.equal(TICK .. " received     Grey: not in raid     (trial): shown, doesn't roll",
      ns.UI.reserves.key:GetText())
    assert.is_true(ns.UI.reserves.key:IsShown())
  end)

  it("shows the column headings and no empty state with a raid chosen", function()
    chooseRaid(ns)
    names(ns)
    assert.is_true(ns.UI.reserves.columns:IsShown())
    assert.is_false(ns.UI.reserves.title:IsShown())
    assert.is_false(ns.UI.reserves.toSync:IsShown())
  end)

  it("is read only: nothing in it takes a click but the way to Sync", function()
    chooseRaid(ns)
    names(ns)
    local clickable = {}
    for _, frame in ipairs({ ns.UI.reserves.scroll, ns.UI.reserves.child, ns.UI.reserves.columns }) do
      if frame.scripts.OnClick then clickable[#clickable + 1] = frame end
    end
    assert.are.same({}, clickable)
  end)

  it("scrolls with the mouse wheel and stays within the list", function()
    chooseRaid(ns)
    names(ns)
    local scroll = ns.UI.reserves.scroll
    scroll.scripts.OnMouseWheel(scroll, 1) -- up, already at the top
    assert.are.equal(0, scroll:GetVerticalScroll())
    scroll.scripts.OnMouseWheel(scroll, -1)
    assert.are.equal(40, scroll:GetVerticalScroll())
    for _ = 1, 100 do scroll.scripts.OnMouseWheel(scroll, -1) end
    assert.are.equal(scroll:GetVerticalScrollRange(), scroll:GetVerticalScroll())
  end)

  describe("with nothing to show", function()
    local function empty()
      names(ns)
      local r = ns.UI.reserves
      return { r.title:GetText(), r.hint:GetText() }, r
    end

    it("says no raid is chosen yet and points to Sync, with none chosen", function()
      local text, r = empty()
      assert.are.same({ "No raid chosen yet", "No raid is chosen yet. Pick one in the Sync tab." }, text)
      assert.is_true(r.toSync:IsShown())
      assert.are.equal("Go to Sync", r.toSync.label:GetText())
      for _, piece in ipairs({ r.key, r.header, r.columns, r.scroll }) do assert.is_false(piece:IsShown()) end
      r.toSync.scripts.OnClick()
      assert.are.equal("Sync", ns.UI.selected)
    end)

    it("says the same when the run is not a guild run", function()
      chooseRaid(ns)
      ns.Selection.ChooseOff()
      assert.are.equal("No raid chosen yet", empty()[1])
    end)

    it("says the same when the chosen raid has not loaded yet", function()
      ns.Selection.Apply("MC0001", 100, "Officer")
      assert.are.equal("No raid chosen yet", empty()[1])
    end)

    it("explains a raid nobody reserved in, and points to Sync", function()
      chooseRaid(ns, { reserves = {} })
      local text, r = empty()
      assert.are.same({ "No reserves in this raid", "Nobody has reserved an item for Molten Core."
        .. " Load the raid's latest reserves in the Sync tab." }, text)
      assert.is_true(r.toSync:IsShown())
    end)

    it("fills the list again once a raid is chosen", function()
      empty()
      chooseRaid(ns)
      ns.UI.Select("Awards")
      ns.UI.Select("Reserves")
      assert.is_true(ns.UI.reserves.scroll:IsShown())
      assert.is_false(ns.UI.reserves.title:IsShown())
      assert.are.equal(9, #ns.UI.reserves.shown)
    end)
  end)

  it("draws when the window opens on the tab, and not while it is closed", function()
    chooseRaid(ns)
    ns.UI.Select("Reserves")
    assert.are.same({}, ns.UI.reserves.shown) -- window closed: nothing drawn yet
    ns.UI.Toggle()
    assert.are.equal(9, #ns.UI.reserves.shown)
  end)

  it("redraws, once, after a burst of roster and item news", function()
    chooseRaid(ns)
    names(ns)
    wow.state.group = { "Masterlooter" }
    wow.state.items[101] = { name = "Ring", link = "[Ring]", icon = 1 }
    for _ = 1, 3 do wow.fire("GROUP_ROSTER_UPDATE") end
    wow.fire("GET_ITEM_INFO_RECEIVED", 101)
    assert.are.equal("Item 101", texts(ns.UI.reserves.shown)[3][1])
    wow.advance(0.2)
    local lines = texts(ns.UI.reserves.shown)
    assert.are.equal("|T1:14|t [Ring]", lines[3][1])
    assert.are.equal(grey("Ashla Brightwater"), lines[2][2])
  end)

  it("reuses its rows when the list gets shorter", function()
    chooseRaid(ns)
    names(ns)
    local before = #ns.UI.reserves.items
    chooseRaid(ns, { raid = "raid00002", code = "MC0002",
      reserves = { [100] = { holder("u1", "Ashla", "HR") } } })
    ns.UI.RefreshReserves()
    assert.are.equal(2, #ns.UI.reserves.shown)
    assert.are.equal(before, #ns.UI.reserves.items)
    assert.is_false(ns.UI.reserves.items[before]:IsShown())
  end)
end)

describe("the item tooltips", function()
  local ns

  -- The older client hook: GameTooltip's item script, run as the game does after an item shows.
  local function hover(id)
    local tip = _G.GameTooltip
    tip.lines, tip.item = {}, id and ("|cffa335ee|Hitem:" .. id .. "::::::::60|h[Item]|h|r")
    for _, fn in ipairs(tip.hooks.OnTooltipCleared) do fn(tip) end
    for _, fn in ipairs(tip.hooks.OnTooltipSetItem) do fn(tip) end
    return tip.lines
  end

  before_each(function()
    ns = wow.start()
    wow.state.group = { "Masterlooter", "Ashla Brightwater" }
    wow.state.groupIsRaid = true
  end)

  it("adds the hard and soft reserve names to an item somebody reserved", function()
    chooseRaid(ns)
    wow.state.group = { "Masterlooter", "Ashla Brightwater", "Lyra Dawnmere" }
    assert.are.same({
      " ", "Bureaucracy reserves",
      "Hard: Ashla Brightwater, Lyra Dawnmere " .. grey("(trial)"),
      "Soft: " .. grey("none"),
    }, hover(101))
  end)

  it("greys absent holders and ticks the ones who received it", function()
    chooseRaid(ns, { awards = {
      { key = "k1", boss = "b1", item = 100, char = "Ashla Brightwater", user = "u1", method = "HR",
        voided = false },
    } })
    local lines = hover(100)
    assert.are.equal("Hard: Ashla Brightwater " .. TICK, lines[3])
    assert.are.equal("Soft: " .. grey("Doran Vale") .. ", " .. grey("Kessa Moorfield"), lines[4])
  end)

  it("also adds the names to a clicked item link", function()
    chooseRaid(ns)
    local tip = _G.ItemRefTooltip
    tip.item, tip.lines = "|Hitem:100::::::::60|h[Item]|h", {}
    for _, fn in ipairs(tip.hooks.OnTooltipSetItem) do fn(tip) end
    assert.are.same({ " ", "Bureaucracy reserves",
      "Hard: Ashla Brightwater",
      "Soft: " .. grey("Doran Vale") .. ", " .. grey("Kessa Moorfield") }, tip.lines)
  end)

  it("adds nothing for an item nobody reserved, or one with an empty list", function()
    chooseRaid(ns)
    assert.are.same({}, hover(999))
    assert.are.same({}, hover(104))
  end)

  it("adds nothing with no raid chosen, no raid loaded or not a guild run", function()
    assert.are.same({}, hover(100))
    chooseRaid(ns)
    ns.Selection.ChooseOff()
    assert.are.same({}, hover(100))
  end)

  it("adds nothing for a tooltip that is not an item", function()
    chooseRaid(ns)
    assert.are.same({}, hover(nil))
  end)

  it("adds the lines once if the game runs the item script twice", function()
    chooseRaid(ns)
    local tip = _G.GameTooltip
    hover(100)
    for _, fn in ipairs(tip.hooks.OnTooltipSetItem) do fn(tip) end
    assert.are.equal(4, #tip.lines)
  end)

  it("hooks the client's own tooltip processor when it has one", function()
    local calls = {}
    _G.TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) calls[#calls + 1] = { kind, fn } end }
    _G.Enum = { TooltipDataType = { Item = 0 } }
    finally(function() _G.TooltipDataProcessor, _G.Enum = nil, nil end)
    ns = wow.start()
    wow.state.group = { "Masterlooter", "Ashla Brightwater" }
    wow.state.groupIsRaid = true
    chooseRaid(ns)
    assert.are.equal(1, #calls)
    assert.are.equal(0, calls[1][1])
    assert.is_nil(_G.GameTooltip.hooks) -- the old script isn't hooked as well
    local tip = _G.GameTooltip
    tip.lines = {}
    calls[1][2](tip, { id = 100 })
    assert.are.equal("Bureaucracy reserves", tip.lines[2])
    tip.lines = {}
    calls[1][2](tip, { id = 999 })
    calls[1][2](tip, nil)
    assert.are.same({}, tip.lines)
  end)
end)
