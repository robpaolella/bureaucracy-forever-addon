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

  it("closes with Escape, as does its dialog", function()
    assert.are.same({ "BureaucracyForeverWindow", "BureaucracyForeverDialog" }, _G.UISpecialFrames)
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

  it("marks the heading of a killed boss '· killed', and no other", function()
    chooseRaid(ns)
    wow.fire("ENCOUNTER_END", 1, "Lucifron", 0, 5, 1)
    local lines = texts(names(ns))
    assert.are.same({ "Lucifron · killed" }, lines[1])
    assert.are.same({ "Magmadar" }, lines[4])
    assert.are.same({ "Trash" }, lines[6])
    assert.are.same({ "Other" }, lines[8])
  end)

  it("adds the mark at once when a boss dies with the tab open", function()
    chooseRaid(ns)
    names(ns)
    wow.fire("ENCOUNTER_END", 1, "Lucifron", 0, 5, 1)
    assert.are.same({ "Lucifron · killed" }, texts(ns.UI.reserves.shown)[1])
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

-- A raid's snapshot as the site's tree; fields override the rest.
local function raidTree(id, fields)
  local tree = {
    formatVersion = 1, raid = id, code = "C" .. id:sub(-5):upper(), env = "staging", name = "Molten Core",
    startsAt = 1792000000, durationMin = 240, instance = 409, generated = 1791990000,
    addon = { version = "0.0.0", url = "https://example.invalid/addon" },
    bosses = {}, awards = {},
    reserves = { [100] = { holder("u1", "Ashla Brightwater", "HR"), holder("u2", "Doran Vale", "SR") },
      [101] = { holder("u1", "Ashla Brightwater", "SR") } },
  }
  for k, v in pairs(fields or {}) do tree[k] = v end
  return tree
end

-- A value written as the site writes its reserves text: a Lua table constructor.
local function serialize(value)
  if type(value) == "string" then return string.format("%q", value) end
  if type(value) ~= "table" then return tostring(value) end
  local parts = {}
  for k, v in pairs(value) do
    local key = type(k) == "string" and k or "[" .. k .. "]"
    parts[#parts + 1] = key .. " = " .. serialize(v)
  end
  return "{ " .. table.concat(parts, ", ") .. " }"
end

local function pasteText(id, fields)
  return "BFSNAP1:1/1:" .. serialize(raidTree(id, fields))
end

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = copy(v) end
  return out
end

local RELEASES = "https://github.com/robpaolella/bureaucracy-forever-addon/releases/latest"

describe("the Sync tab", function()
  local ns, sync
  local DAY = date("%a %d %b", 1792000000)

  local function open()
    ns.UI.Toggle()
    ns.UI.tabButtons.Sync.scripts.OnClick()
  end

  local function start(options)
    ns = wow.start(options)
    sync = ns.UI.sync
    wow.state.player = "Konvett"
    open()
  end

  local function paste(text)
    sync.box:SetText(text)
    wow.click(function() sync.load.scripts.OnClick() end)
  end

  local function status() return sync.status.kind, sync.status.text:GetText() end

  local function row(i)
    local r = sync.rows[i]
    return { r.name:GetText(), r.when:GetText(), r.instance:GetText(), r.counts:GetText(), r.awards:GetText(),
      r.pasted:GetText() }
  end

  local function awards(raidId, count)
    ns.db.awards = ns.db.awards or {}
    ns.db.awards[raidId] = {}
    for i = 1, count do
      ns.db.awards[raidId][i] = { key = "k" .. i, item = 100, char = "Ashla", method = "HR" }
    end
  end

  local function dialog()
    local d = ns.UI.dialog
    return { d.text:GetText(), d.hint:GetText(), d.yes.label:GetText(), d.no.label:GetText() }
  end

  before_each(function() start() end)

  describe("with nothing loaded", function()
    it("says no raids are loaded, with no table, and how to load one", function()
      assert.are.same({ "warn", "No raids loaded. The pop-up still works, but every item is an open roll." },
        { status() })
      assert.are.equal("Raid events", sync.raidsHeading:GetText())
      assert.is_false(sync.columns:IsShown())
      assert.are.same({}, sync.rows)
      assert.are.equal("|TInterface\\COMMON\\Indicator-Gray:12|t Desktop helper not running: paste "
        .. "reserves in and copy awards out below.", sync.helper:GetText())
      assert.are.equal("Reserves in", sync.inHeading:GetText())
      assert.are.equal("On the guild site, open the raid and choose |cffffffffCopy reserves|r. Paste it here "
        .. "with Ctrl+V (Cmd+V on Mac). Pasting chooses that raid for the group.", sync.inHint:GetText())
      assert.are.equal("Paste the reserves text here", sync.placeholder:GetText())
      assert.is_true(sync.placeholder:IsShown())
      assert.are.equal("Load", sync.load.label:GetText())
      assert.is_true(sync.load:IsShown())
      assert.is_true(sync.load:IsEnabled())
      assert.is_false(sync.resultNote:IsShown())
      assert.is_false(sync.link:IsShown())
    end)

    it("draws nothing while the window is closed", function()
      ns.UI.Toggle()
      ns.Raids.Load(assert(ns.Sync.ReadPasted(pasteText("raid00001"))), "pasted")
      ns.UI.RefreshSync()
      assert.are.same({}, sync.rows)
      ns.UI.Toggle()
      assert.are.equal(1, #sync.rows)
    end)
  end)

  describe("loading a paste", function()
    it("loads the raid, chooses it for the group, and says when it was copied and loaded", function()
      paste(pasteText("raid00001"))
      assert.are.same({ "chosen", "raid00001", "Konvett" },
        { ns.db.activeBy, ns.db.activeRaid, ns.db.chosenBy })
      assert.are.equal("good", sync.resultNote.kind)
      assert.are.equal("Loaded Molten Core, " .. DAY .. ". Copied from the site " .. date("%H:%M", 1791990000)
        .. ", loaded " .. date("%H:%M", 1792000000) .. ".", sync.resultNote.text:GetText())
      assert.are.equal("", sync.box:GetText())
      assert.is_true(sync.placeholder:IsShown())
      assert.are.same({ "good", "|cffffffffMolten Core, " .. DAY .. "|r · 2 players · 3 reserves · 0 awards\n"
        .. "Chosen when you pasted its reserves at " .. date("%H:%M", 1792000000) .. "." }, { status() })
      local at = date("%H:%M", 1792000000)
      assert.are.same({ "Molten Core " .. grey(DAY), "Under way since " .. at, "409", "2 · 3", grey("-"),
        grey("Pasted " .. at) }, row(1))
      assert.is_true(sync.rows[1].selected)
      assert.is_true(sync.rows[1].remove:IsShown())
      assert.is_true(sync.rows[1].remove:IsEnabled())
      assert.are.same({}, wow.blocked)
    end)

    it("adds the update notice when the site names a newer add-on", function()
      paste(pasteText("raid00001", { addon = { version = "9.0.0", url = "https://example.invalid/new" } }))
      assert.is_truthy(sync.resultNote.text:GetText():find(
        ". Version 9.0.0 of the add-on is out (you have 0.0.0-dev). Download it from "
          .. "https://example.invalid/new.",
        1, true))
    end)

    it("refuses a bad paste, changing nothing and keeping the text", function()
      paste(pasteText("raid00001"))
      local before = copy(ns.db)
      paste("hello")
      assert.are.same(before, ns.db)
      assert.are.equal("bad", sync.resultNote.kind)
      assert.are.equal("This isn't the reserves text from the site. Copy it again from the site. Nothing was "
        .. "loaded; your raids are unchanged.", sync.resultNote.text:GetText())
      assert.are.equal("hello", sync.box:GetText())
      assert.is_false(sync.link:IsShown())
      assert.are.equal(1, #sync.rows)
    end)

    it("refuses a newer format with the download link selected, changing nothing", function()
      local before = copy(ns.db)
      paste(pasteText("raid00001", { formatVersion = 2 }))
      assert.are.same(before, ns.db)
      assert.are.equal("This text needs a newer version of the add-on (you have 0.0.0-dev). Nothing was "
        .. "loaded; your raids are unchanged.", sync.resultNote.text:GetText())
      assert.are.equal("Download link:", sync.linkLabel:GetText())
      assert.is_true(sync.link:IsShown())
      assert.are.equal(RELEASES, sync.link:GetText())
      assert.is_true(sync.link.highlighted)
      assert.are.equal("Press Ctrl+C to copy the link, open it in your browser, replace the add-on folder, "
        .. "then /reload.", sync.linkHint:GetText())
      -- Typing in the link box puts the link back.
      sync.link:SetText("x")
      sync.link.scripts.OnTextChanged(sync.link, true)
      assert.are.equal(RELEASES, sync.link:GetText())
      -- The next good paste clears the refusal.
      paste(pasteText("raid00001"))
      assert.is_false(sync.link:IsShown())
      assert.are.equal("good", sync.resultNote.kind)
    end)

    it("replaces a raid already held with the new paste", function()
      paste(pasteText("raid00001"))
      awards("raid00001", 2)
      wow.state.time = 1792000600
      paste(pasteText("raid00001", { name = "Molten Core (updated)", generated = 1791999000,
        reserves = { [100] = { holder("u1", "Ashla Brightwater", "HR") } } }))
      assert.is_nil(ns.UI.dialog:IsShown() or nil)
      assert.are.equal(1, #sync.rows)
      assert.are.same({ "Molten Core (updated) " .. grey(DAY), "1 · 1", "2" },
        { row(1)[1], row(1)[4], row(1)[5] })
      assert.are.equal("raid00001", ns.db.activeRaid)
    end)

    it("chooses the pasted raid at once when the selected raid has no awards", function()
      paste(pasteText("raid00001"))
      paste(pasteText("raid00002", { name = "Onyxia's Lair", startsAt = 1792010000 }))
      assert.is_false(ns.UI.dialog:IsShown())
      assert.are.equal("raid00002", ns.db.activeRaid)
      assert.is_true(sync.rows[2].selected)
      assert.is_nil(sync.rows[1].selected)
    end)

    describe("when the selected raid has awards", function()
      before_each(function()
        paste(pasteText("raid00001"))
        awards("raid00001", 12)
        paste(pasteText("raid00002", { name = "Onyxia's Lair" }))
      end)

      it("asks first, with the raid still loaded and listed", function()
        assert.is_true(ns.UI.dialog:IsShown())
        assert.are.same({ "Switch the raid to |cffffffffOnyxia's Lair, " .. DAY .. "|r?",
          "You have 12 awards for Molten Core. They stay with that raid and are still sent to the site. "
            .. "Every officer in the group switches too.", "Switch", "Keep Molten Core" }, dialog())
        assert.are.equal("raid00001", ns.db.activeRaid)
        assert.are.equal(2, #sync.rows)
        assert.is_true(ns.UI.dialog.yes:IsEnabled())
        assert.is_true(ns.UI.dialog.no:IsEnabled())
      end)

      it("Keep leaves the selection as it was, and the pasted raid loaded", function()
        wow.click(function() ns.UI.dialog.no.scripts.OnClick() end)
        assert.is_false(ns.UI.dialog:IsShown())
        assert.are.equal("raid00001", ns.db.activeRaid)
        assert.is_table(ns.Raids.Get("raid00002"))
        assert.are.equal(2, #sync.rows)
      end)

      it("Switch chooses the pasted raid", function()
        wow.click(function() ns.UI.dialog.yes.scripts.OnClick() end)
        assert.is_false(ns.UI.dialog:IsShown())
        assert.are.equal("raid00002", ns.db.activeRaid)
        assert.is_truthy(select(2, status()):find("Chosen when you pasted its reserves", 1, true))
      end)

      it("says award and stays in the singular", function()
        awards("raid00001", 1)
        paste(pasteText("raid00002", { name = "Onyxia's Lair" }))
        assert.are.equal("You have 1 award for Molten Core. It stays with that raid and is still sent to the "
          .. "site. Every officer in the group switches too.", dialog()[2])
      end)
    end)
  end)

  describe("Awards out (copy awards)", function()
    local function award(fields)
      local f = { boss = "lb_lucifron", item = 16805, char = "Ana Vale", user = "u_ana", method = "HR",
        roll = 91 }
      for k, v in pairs(fields or {}) do f[k] = v end
      return ns.Records.Award(f)
    end
    local function countLine() return sync.outCount:GetText() end
    local function hover()
      ns.UI.button.scripts.OnEnter(ns.UI.button)
      return _G.GameTooltip.lines[2]
    end

    it("says nothing to copy, with Copy disabled and no picker, with nothing loaded", function()
      assert.are.equal("Awards out", sync.outHeading:GetText())
      assert.are.equal("Paste the text into |cffffffffImport awards|r on the raid's page on the guild site.",
        sync.outHint:GetText())
      assert.are.equal("Copy awards", sync.copy.label:GetText())
      assert.is_true(sync.copy:IsShown())
      assert.is_false(sync.copy:IsEnabled())
      assert.is_false(sync.outPick:IsShown())
      assert.are.equal("Nothing to copy yet.", countLine())
      assert.is_false(sync.outScroll:IsShown())
    end)

    it("says nothing to copy when the loaded raids have no awards", function()
      paste(pasteText("raid00001"))
      assert.is_false(sync.copy:IsEnabled())
      assert.is_false(sync.outPick:IsShown())
      assert.are.equal("Nothing to copy yet.", countLine())
    end)

    it("defaults to the selected raid and counts awards and undos", function()
      paste(pasteText("raid00001"))
      award({ id = "aw-00000001" })
      award({ id = "aw-00000002", item = 1 })
      ns.Records.Confirm("aw-00000001", { id = "cf-00000001" })
      ns.Records.Void("aw-00000002", { id = "vd-00000001" })
      ns.UI.RefreshSync()
      assert.is_true(sync.outPick:IsShown())
      assert.are.equal("Molten Core, " .. DAY .. " ▾", sync.outPick.label:GetText())
      assert.is_true(sync.copy:IsEnabled())
      assert.are.equal("2 awards, 1 undo. Practice awards are never included.", countLine())
    end)

    it("counts a replace as one award and one undo, and not a confirmation", function()
      paste(pasteText("raid00001"))
      award({ id = "aw-00000001" })
      ns.Records.Confirm("aw-00000001", { id = "cf-00000001" })
      ns.Records.Replace("aw-00000001", { id = "aw-00000002", boss = "lb_lucifron", item = 16805,
        char = "Bo Marsh", user = "u_bo", method = "SR" }, { id = "rp-00000001" })
      ns.UI.RefreshSync()
      assert.are.equal("2 awards, 1 undo. Practice awards are never included.", countLine())
    end)

    it("says award in the singular", function()
      paste(pasteText("raid00001"))
      award({ id = "aw-00000001" })
      ns.UI.RefreshSync()
      assert.are.equal("1 award, 0 undos. Practice awards are never included.", countLine())
    end)

    it("shows the copy-out text selected, matching Sync.CopyOut, when Copy awards is pressed", function()
      paste(pasteText("raid00001"))
      award({ id = "aw-00000001" })
      ns.UI.RefreshSync()
      assert.is_false(sync.outScroll:IsShown())
      sync.copy.scripts.OnClick()
      assert.is_true(sync.outScroll:IsShown())
      assert.is_true(sync.outNote:IsShown())
      assert.are.equal("The text is selected: press Ctrl+C (Cmd+C on Mac).", sync.outNote:GetText())
      assert.are.equal((ns.Sync.CopyOut("raid00001")), sync.out:GetText())
      assert.is_true(sync.out.focused)
      assert.is_true(sync.out.highlighted)
    end)

    it("puts the text back when it is typed in", function()
      paste(pasteText("raid00001"))
      award({ id = "aw-00000001" })
      ns.UI.RefreshSync()
      sync.copy.scripts.OnClick()
      local text = sync.out:GetText()
      sync.out:SetText("x")
      sync.out.scripts.OnTextChanged(sync.out, true)
      assert.are.equal(text, sync.out:GetText())
    end)

    describe("the raid menu", function()
      local function entries()
        local out = {}
        for i, b in ipairs(sync.menuEntries) do
          if b:IsShown() then out[i] = b.label:GetText() end
        end
        return out
      end

      before_each(function()
        paste(pasteText("raid00001"))
        award({ id = "aw-00000001" })
        paste(pasteText("raid00002", { name = "Onyxia's Lair" }))
        wow.click(function() ns.UI.dialog.yes.scripts.OnClick() end)
        paste(pasteText("raid00003", { name = "Blackwing Lair" }))
        award({ id = "aw-00000002", raid = "raid00003" })
        award({ id = "aw-practice1", raid = "raid00002", practice = true })
        ns.Selection.ChooseRaid("raid00002", true)
        ns.UI.RefreshSync()
      end)

      it("opens from the picker with a title and one entry per raid that gives text", function()
        assert.is_false(sync.menu:IsShown())
        sync.outPick.scripts.OnClick()
        assert.is_true(sync.menu:IsShown())
        assert.are.equal("Which raid's awards?", sync.menu.title:GetText())
        assert.are.same({ "   Molten Core, " .. DAY, "   Blackwing Lair, " .. DAY }, entries())
      end)

      it("offers nothing picked when the selected raid has no text", function()
        assert.are.equal("Choose a raid ▾", sync.outPick.label:GetText())
        assert.is_false(sync.copy:IsEnabled())
        assert.are.equal("Choose a raid to copy.", countLine())
      end)

      it("closes when the picker is pressed again", function()
        sync.outPick.scripts.OnClick()
        sync.outPick.scripts.OnClick()
        assert.is_false(sync.menu:IsShown())
      end)

      it("picks a raid: the menu closes, the picker names it and Copy awards enables", function()
        sync.outPick.scripts.OnClick()
        sync.menuEntries[2].scripts.OnClick()
        assert.is_false(sync.menu:IsShown())
        assert.are.equal("Blackwing Lair, " .. DAY .. " ▾", sync.outPick.label:GetText())
        assert.is_true(sync.copy:IsEnabled())
        sync.copy.scripts.OnClick()
        assert.are.equal((ns.Sync.CopyOut("raid00003")), sync.out:GetText())
        sync.outPick.scripts.OnClick()
        assert.are.same({ "   Molten Core, " .. DAY, "> Blackwing Lair, " .. DAY }, entries())
      end)

      it("closes with the window", function()
        sync.outPick.scripts.OnClick()
        ns.UI.window.scripts.OnHide()
        assert.is_false(sync.menu:IsShown())
      end)
    end)

    it("offers a raid made only of practice awards no more than one with none", function()
      paste(pasteText("raid00001"))
      award({ id = "aw-practice1", practice = true })
      ns.UI.RefreshSync()
      assert.is_false(sync.outPick:IsShown())
      assert.is_false(sync.copy:IsEnabled())
      assert.are.equal("Nothing to copy yet.", countLine())
    end)

    it("drops the shown text when its raid is removed", function()
      paste(pasteText("raid00001"))
      award({ id = "aw-00000001" })
      ns.UI.RefreshSync()
      sync.copy.scripts.OnClick()
      ns.Raids.Remove("raid00001", true)
      ns.UI.RefreshSync()
      assert.is_false(sync.outScroll:IsShown())
      assert.is_false(sync.copy:IsEnabled())
    end)

    describe("the minimap tooltip's raid line", function()
      it("names the selected raid", function()
        paste(pasteText("raid00001"))
        assert.are.equal("Molten Core, " .. DAY, hover())
      end)

      it("says no raids are loaded with none loaded", function()
        assert.are.equal("No raids loaded.", hover())
      end)

      it("says no raid is chosen with raids loaded and none chosen", function()
        paste(pasteText("raid00001"))
        ns.Selection.Clear()
        assert.are.equal("No raid chosen yet.", hover())
      end)

      it("says it is not a guild run when that was chosen", function()
        paste(pasteText("raid00001"))
        ns.Selection.ChooseOff()
        assert.are.equal("Not a guild run.", hover())
      end)

      it("says no raid is chosen when the chosen raid is not loaded", function()
        paste(pasteText("raid00001"))
        ns.Raids.Remove("raid00001", true)
        paste(pasteText("raid00002", { code = "ZZZZZ" }))
        ns.Selection.Clear()
        assert.are.equal("No raid chosen yet.", hover())
      end)
    end)
  end)

  describe("removing a pasted raid", function()
    it("removes one with no awards without asking, and clears the selection", function()
      paste(pasteText("raid00001"))
      wow.click(function() sync.rows[1].remove.scripts.OnClick(sync.rows[1].remove) end)
      assert.is_false(ns.UI.dialog:IsShown())
      assert.is_nil(ns.Raids.Get("raid00001"))
      assert.are.equal("none", ns.db.activeBy)
      assert.are.same({}, sync.rows)
      assert.are.equal("No raids loaded. The pop-up still works, but every item is an open roll.",
        select(2, status()))
    end)

    it("asks first for one with awards; Cancel keeps it, Remove drops it and keeps its awards", function()
      paste(pasteText("raid00001"))
      awards("raid00001", 12)
      local button = sync.rows[1].remove
      wow.click(function() button.scripts.OnClick(button) end)
      assert.are.same({ "Remove |cffffffffMolten Core, " .. DAY .. "|r?",
        "Its 12 awards stay saved.", "Remove", "Cancel" }, dialog())
      assert.is_true(ns.UI.dialog.yes:IsEnabled())
      assert.is_true(ns.UI.dialog.no:IsEnabled())
      wow.click(function() ns.UI.dialog.no.scripts.OnClick() end)
      assert.is_table(ns.Raids.Get("raid00001"))
      assert.are.equal("raid00001", ns.db.activeRaid)
      wow.click(function() button.scripts.OnClick(button) end)
      wow.click(function() ns.UI.dialog.yes.scripts.OnClick() end)
      assert.is_nil(ns.Raids.Get("raid00001"))
      assert.are.equal("none", ns.db.activeBy)
      assert.are.equal(12, #ns.db.awards.raid00001)
      assert.are.same({}, sync.rows)
    end)

    it("hides the Remove of a pasted raid listed after the helper's raids once it is gone", function()
      start({ inbox = { formatVersion = 1, written = 1791999000,
        raids = { { snapshot = raidTree("raid00001") } } } })
      paste(pasteText("raid00002", { startsAt = 1792010000 }))
      local button = sync.rows[2].remove
      wow.click(function() button.scripts.OnClick(button) end)
      assert.are.equal(1, #sync.rows)
      assert.is_false(button:IsShown())
    end)

    it("says award and stays in the singular", function()
      paste(pasteText("raid00001"))
      awards("raid00001", 1)
      wow.click(function() sync.rows[1].remove.scripts.OnClick(sync.rows[1].remove) end)
      assert.are.equal("Its 1 award stays saved.", dialog()[2])
    end)
  end)

  it("lists four raids, with no instance number and long names, Remove only on the pasted one", function()
    local long = "Zul'Gurub alt run (custom raid with a very long name)"
    local custom = raidTree("raid00003", { name = long, startsAt = 1792003600 })
    custom.instance = nil
    start({ inbox = { formatVersion = 1, written = 1791999000, raids = {
      { snapshot = raidTree("raid00001") },
      { snapshot = raidTree("raid00002", { name = "Onyxia's Lair", instance = 249, startsAt = 1792007200 }) },
      { snapshot = custom },
    } } })
    paste(pasteText("raid00004", { name = "Blackwing Lair", instance = 469, startsAt = 1791900000 }))
    local at = function(t) return date("%H:%M", t) end
    assert.are.equal(4, #sync.rows)
    assert.are.same({ "Blackwing Lair " .. grey(date("%a %d %b", 1791900000)), "Ended " .. at(1791914400),
      "469", "2 · 3", grey("-"), grey("Pasted " .. at(1792000000)) }, row(1))
    assert.are.same({ "Molten Core " .. grey(DAY), "Under way since " .. at(1792000000), "409" },
      { row(2)[1], row(2)[2], row(2)[3] })
    assert.are.same({ long .. " " .. grey(DAY), "Starts " .. at(1792003600), "|cffffa020None|r", "" },
      { row(3)[1], row(3)[2], row(3)[3], row(3)[6] })
    assert.are.equal("Starts " .. at(1792007200), row(4)[2])
    assert.is_table(sync.rows[1].remove)
    for i = 2, 4 do assert.is_nil(sync.rows[i].remove) end
    -- A choice on every row, the raid pasted last selected, and Not a guild run after them.
    assert.is_true(sync.rows[1].selected)
    for i = 2, 4 do assert.is_true(sync.rows[i].pick:IsShown()) end
    assert.is_true(sync.offPick:IsShown())
    assert.is_true(sync.rows[1].remove:GetFrameLevel() > sync.rows[1].pick:GetFrameLevel())
    for column, label in pairs({ name = "Raid event", when = "When", instance = "Instance",
      counts = "Players · reserves", awards = "Awards" }) do
      assert.are.equal(label, sync.headings[column]:GetText())
    end
    assert.are.equal("|TInterface\\COMMON\\Indicator-Green:12|t Desktop helper in use: raid events read at "
      .. at(1792000000) .. " (they update at login or /reload), and awards go to the site live.",
      sync.helper:GetText())
  end)

  describe("its status bar", function()
    it("names another officer who chose the raid, marked when they are the loot master", function()
      ns.Raids.Load(assert(ns.Sync.ReadPasted(pasteText("raid00001"))), "pasted")
      ns.Selection.Apply("C00001", 1792000300, "Ashla")
      ns.UI.RefreshSync()
      assert.are.equal("Chosen by Ashla at " .. date("%H:%M", 1792000300) .. ". Awards from this group go to "
        .. "this raid.", select(2, status()):match("\n(.*)$"))
      wow.state.group, wow.state.groupIsRaid = { "Konvett", "Ashla" }, true
      wow.state.lootMethod = { "master", 1, 2 }
      ns.UI.RefreshSync()
      assert.are.equal("Chosen by Ashla (loot master) at " .. date("%H:%M", 1792000300)
        .. ". Awards from this group go to this raid.", select(2, status()):match("\n(.*)$"))
    end)

    it("says when raids are loaded but none is chosen", function()
      ns.Raids.Load(assert(ns.Sync.ReadPasted(pasteText("raid00001"))), "pasted")
      ns.UI.RefreshSync()
      assert.are.same({ "warn", "No raid chosen yet. Awards are held as \"no raid\" until you choose one." },
        { status() })
    end)

    it("says when the run is not a guild run, and who chose it", function()
      ns.Selection.ChooseOff()
      ns.UI.RefreshSync()
      assert.are.equal("Not a guild run. The add-on is off for this group: no loot pop-up, no chat lines, "
        .. "nothing recorded. It turns back on when you leave the group.\nYou chose this at "
        .. date("%H:%M", 1792000000) .. ".", select(2, status()))
      ns.Selection.Apply("-", 1792000300, "Ashla")
      ns.UI.RefreshSync()
      assert.are.equal("Ashla chose this at " .. date("%H:%M", 1792000300) .. ".",
        select(2, status()):match("\n(.*)$"))
    end)

    it("says when the chosen raid isn't loaded here yet, and that it applies once it loads", function()
      ns.Selection.Apply("C00009", 1792000300, "Ashla")
      ns.UI.RefreshSync()
      assert.are.same({ "warn", "The chosen raid (C00009) isn't loaded here yet. Awards are held as "
        .. "\"no raid\" until it loads.\nChosen by Ashla at " .. date("%H:%M", 1792000300) .. ". It applies "
        .. "here once the raid loads: from the helper at login or /reload, or by pasting its reserves "
        .. "below." },
        { status() })
      paste(pasteText("raid00009", { code = "C00009" }))
      assert.are.equal("raid00009", ns.db.activeRaid)
      assert.are.equal("good", (status()))
    end)
  end)

  describe("choosing the raid", function()
    local function inbox(...)
      local raids = {}
      for i, tree in ipairs({ ... }) do raids[i] = { snapshot = tree } end
      return { inbox = { formatVersion = 1, written = 1791999000, raids = raids } }
    end
    local MC, ONY = raidTree("raid00001"),
      raidTree("raid00002", { name = "Onyxia's Lair", instance = 249, startsAt = 1792007200 })
    local RADIO_ON = "|TInterface\\Buttons\\UI-RadioButton:14:14:0:0:64:16:16:32:0:16|t"

    local function pick(i)
      local b = i == "off" and sync.offPick or sync.rows[i].pick
      assert.is_true(b:IsShown())
      wow.click(function() b.scripts.OnClick(b) end)
    end

    local function radios()
      local out = {}
      for i, r in ipairs(sync.rows) do out[i] = r.radio:GetText() == RADIO_ON end
      out[#out + 1] = sync.offRadio:GetText() == RADIO_ON
      return out
    end

    before_each(function()
      start(inbox(MC, ONY))
      wow.state.instance = { name = "Molten Core", type = "raid", id = 409 }
      ns.Selection.ChooseRaid("raid00001")
      ns.UI.RefreshSync()
    end)

    it("shows the chosen raid, a choice per row, Not a guild run last, and where you are", function()
      assert.are.same({ "good", "|cffffffffMolten Core, " .. DAY .. "|r · 2 players · 3 reserves · 0 awards\n"
        .. "Chosen by you at " .. date("%H:%M", 1792000000) .. ". Awards from this group go to this raid." },
        { status() })
      assert.are.same({ true, false, false }, radios())
      assert.is_false(sync.rows[1].pick:IsShown())
      assert.is_true(sync.rows[2].pick:IsShown())
      assert.is_true(sync.rows[2].pick:IsEnabled())
      assert.is_true(sync.offPick:IsShown())
      assert.are.equal("Not a guild run |cff808080· the add-on stays off until you leave the group|r",
        sync.offLabel:GetText())
      assert.are.equal("You're in Molten Core (instance 409).", sync.where:GetText())
      assert.are.equal("Choosing another raid changes it for every officer in the group.",
        sync.whereHint:GetText())
      -- It follows the player as they move.
      wow.state.instance = { name = "Ironforge", type = "none", id = 0 }
      wow.fire("ZONE_CHANGED_NEW_AREA")
      assert.are.equal("You're not in an instance.", sync.where:GetText())
      wow.state.instance = { name = "Onyxia's Lair", type = "raid", id = 249 }
      wow.fire("PLAYER_ENTERING_WORLD", false, false)
      assert.are.equal("You're in Onyxia's Lair (instance 249).", sync.where:GetText())
    end)

    it("changes the raid at once when the current raid has no awards (sync-switched)", function()
      wow.state.time = 1792001640
      pick(2)
      assert.is_false(ns.UI.dialog:IsShown())
      assert.are.same({ "chosen", "raid00002", "Konvett" },
        { ns.db.activeBy, ns.db.activeRaid, ns.db.chosenBy })
      assert.are.same({ false, true, false }, radios())
      assert.is_true(sync.rows[2].selected)
      assert.are.equal("Chosen by you at " .. date("%H:%M", 1792001640) .. ". Awards from this group go to "
        .. "this raid.", select(2, status()):match("\n(.*)$"))
    end)

    describe("when the current raid has awards (sync-switch)", function()
      before_each(function()
        awards("raid00001", 12)
        pick(2)
      end)

      it("asks first, changing nothing yet", function()
        assert.is_true(ns.UI.dialog:IsShown())
        assert.are.same({ "Switch the raid to |cffffffffOnyxia's Lair, " .. DAY .. "|r?",
          "You have 12 awards for Molten Core. They stay with that raid and are still sent to the site. "
            .. "Every officer in the group switches too.", "Switch", "Keep Molten Core" }, dialog())
        assert.is_true(ns.UI.dialog.yes:IsShown())
        assert.is_true(ns.UI.dialog.yes:IsEnabled())
        assert.is_true(ns.UI.dialog.no:IsEnabled())
        assert.are.equal("raid00001", ns.db.activeRaid)
      end)

      it("Keep changes nothing", function()
        wow.click(function() ns.UI.dialog.no.scripts.OnClick() end)
        assert.are.equal("raid00001", ns.db.activeRaid)
        assert.are.same({ true, false, false }, radios())
      end)

      it("Switch changes the raid and leaves the awards with theirs", function()
        wow.click(function() ns.UI.dialog.yes.scripts.OnClick() end)
        assert.are.equal("raid00002", ns.db.activeRaid)
        assert.are.equal(12, #ns.db.awards.raid00001)
        assert.are.same({ false, true, false }, radios())
        assert.are.equal("12", sync.rows[1].awards:GetText())
      end)
    end)

    it("marks it not a guild run without asking, even with awards; a raid can follow (sync-off)", function()
      awards("raid00001", 12)
      pick("off")
      assert.is_false(ns.UI.dialog:IsShown())
      assert.are.same({ "off", nil, "Konvett" }, { ns.db.activeBy, ns.db.activeRaid, ns.db.chosenBy })
      assert.are.equal("warn", (status()))
      assert.are.same({ false, false, true }, radios())
      assert.is_false(sync.offPick:IsShown())
      assert.is_true(sync.rows[1].pick:IsShown())
      assert.is_nil(sync.rows[1].selected)
      -- Undoing it is the raid question's (#53); a raid can still be chosen from the table.
      pick(1)
      assert.is_false(ns.UI.dialog:IsShown())
      assert.are.same({ "chosen", "raid00001" }, { ns.db.activeBy, ns.db.activeRaid })
    end)

    it("leaves every row open to choose when the raid is decided later (sync-undecided)", function()
      ns.Selection.Clear()
      ns.UI.RefreshSync()
      assert.are.same({ "warn", "No raid chosen yet. Awards are held as \"no raid\" until you choose one." },
        { status() })
      assert.are.same({ false, false, false }, radios())
      for i = 1, 2 do assert.is_true(sync.rows[i].pick:IsShown()) end
      assert.is_true(sync.offPick:IsShown())
      assert.is_false(sync.selected:IsShown())
    end)

    it("shows another officer's choice to a follower, who can still change it (sync-follower)", function()
      ns.Selection.Apply("C00002", ns.Selection.Status().at + 60, "Ashla")
      ns.UI.RefreshSync()
      assert.is_false(ns.UI.dialog:IsShown())
      assert.are.equal("Chosen by Ashla at " .. date("%H:%M", 1792000060) .. ". Awards from this group go to "
        .. "this raid.", select(2, status()):match("\n(.*)$"))
      assert.are.same({ false, true, false }, radios())
      pick(1)
      assert.are.same({ "raid00001", "Konvett" }, { ns.db.activeRaid, ns.db.chosenBy })
    end)

    it("shows the later of two crossing changes, ties by name", function()
      ns.Selection.Apply("C00002", 1792000500, "Bo")
      ns.Selection.Apply("C00001", 1792000500, "Ashla")
      ns.UI.RefreshSync()
      assert.are.same({ false, true, false }, radios())
      ns.Selection.Apply("C00001", 1792000500, "Cy")
      ns.UI.RefreshSync()
      assert.are.same({ true, false, false }, radios())
    end)
  end)

  describe("when the selected raid leaves the helper's list (sync-gone)", function()
    local ONY = raidTree("raid00002", { name = "Onyxia's Lair", instance = 249, startsAt = 1792007200 })
    local function saved(count)
      ns = wow.start({ inbox = { formatVersion = 1, written = 1791999000, raids = {
        { snapshot = raidTree("raid00001") }, { snapshot = ONY } } } })
      ns.Selection.ChooseRaid("raid00001")
      awards("raid00001", count)
      return copy(ns.db)
    end

    local function relog(db)
      ns = wow.start({ saved = { BureaucracyForeverDB = db },
        inbox = { formatVersion = 1, written = 1792000000, raids = { { snapshot = ONY } } } })
      sync = ns.UI.sync
      wow.state.player = "Konvett"
    end

    it("clears the selection with a notice that names the raid, and keeps its awards", function()
      relog(saved(12))
      assert.are.same({ "none", nil, nil }, { ns.db.activeBy, ns.db.activeRaid, ns.db.chosenBy })
      assert.is_true(ns.UI.dialog:IsShown())
      assert.are.same({ "|cffffffffMolten Core, " .. DAY .. "|r has left the helper's list: it was cancelled "
        .. "or has ended.",
        "Its 12 awards are kept and still sent to the site. You'll be asked which raid it is when you next "
          .. "enter a raid instance.",
        "", "OK" }, dialog())
      -- Choose a raid now opens the raid question (#53); until then the notice has OK alone.
      assert.is_false(ns.UI.dialog.yes:IsShown())
      assert.is_true(ns.UI.dialog.no:IsEnabled())
      wow.click(function() ns.UI.dialog.no.scripts.OnClick() end)
      assert.is_false(ns.UI.dialog:IsShown())
      assert.are.equal(12, #ns.db.awards.raid00001)
      open()
      assert.are.same({ "warn", "No raid chosen. Molten Core, " .. DAY .. " has left the helper's list. "
        .. "Awards are held as \"no raid\" until a raid is chosen." }, { status() })
      assert.are.equal(1, #sync.rows)
      assert.is_true(sync.rows[1].pick:IsShown())
      assert.is_true(sync.offPick:IsShown())
    end)

    it("says an award in the singular, and none", function()
      relog(saved(1))
      assert.are.equal("Its 1 award is kept and still sent to the site. You'll be asked which raid it is "
        .. "when you next enter a raid instance.",
        dialog()[2])
      relog(saved(0))
      assert.are.equal("It had no awards. You'll be asked which raid it is when you next enter a raid "
        .. "instance.", dialog()[2])
    end)

    it("shows the notice once, keeps the status until a raid is chosen, then drops it", function()
      relog(saved(0))
      local db = copy(ns.db)
      relog(db)
      assert.is_false(ns.UI.dialog:IsShown())
      open()
      assert.is_truthy(select(2, status()):find("has left the helper's list", 1, true))
      wow.click(function() sync.rows[1].pick.scripts.OnClick(sync.rows[1].pick) end)
      assert.are.equal("raid00002", ns.db.activeRaid)
      assert.is_nil(ns.Selection.Gone())
    end)
  end)
end)
