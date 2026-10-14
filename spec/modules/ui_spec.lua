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
    assert.are.equal(3, ns.UI.window.numTabs)
    for index, name in ipairs({ "Awards", "Reserves", "Sync" }) do
      local tab = _G["BureaucracyForeverWindowTab" .. index]
      assert.are.equal(name, tab:GetText())
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
    assert.are.equal("Awards", ns.UI.selected)
    assert.is_true(ns.UI.tabs.Awards:IsShown())
    assert.is_false(ns.UI.tabs.Reserves:IsShown())
    assert.is_false(ns.UI.tabs.Sync:IsShown())
    _G.BureaucracyForeverWindowTab3.scripts.OnClick()
    assert.are.equal("Sync", ns.UI.selected)
    assert.are.equal(3, ns.UI.window.selectedTab)
    assert.is_false(ns.UI.tabs.Awards:IsShown())
    assert.is_true(ns.UI.tabs.Sync:IsShown())
    _G.BureaucracyForeverWindowTab2.scripts.OnClick()
    assert.is_true(ns.UI.tabs.Reserves:IsShown())
    assert.is_false(ns.UI.tabs.Sync:IsShown())
    for _, content in pairs(ns.UI.tabs) do assert.is_string(content.placeholder:GetText()) end
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
    wow.click(function() ns.Tracking.Give(2, 1) end)
    assert.are.equal("2 hand-outs not confirmed", hover()[3])
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
  local function reload(ns)
    return wow.start({ saved = { BureaucracyForeverDB = ns.db } })
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
  end)

  it("ignores saved spots that aren't numbers", function()
    local ns = wow.start()
    ns.db.ui = { window = { x = "left", y = 0 }, minimap = { angle = 0 / 0 } }
    ns = reload(ns)
    assert.are.same({ 960, 540 }, { ns.UI.window:GetCenter() })
    assert.is_true(ns.UI.button:IsShown())
  end)
end)
