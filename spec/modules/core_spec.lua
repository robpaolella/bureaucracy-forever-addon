local wow = require("spec.support.wow")

local PREFIX = "|cff33ff99Bureaucracy:|r "

describe("the log", function()
  local ns

  before_each(function() ns = wow.start() end)

  it("says plainly that nothing is logged", function()
    wow.slash("/bf log")
    assert.are.same({ PREFIX .. "nothing has been logged this session." }, wow.printed)
  end)

  it("prints each entry with its time, oldest first", function()
    wow.state.time = os.time({ year = 2026, month = 10, day = 15, hour = 20, min = 5, sec = 9 })
    ns.Log("first")
    wow.state.time = wow.state.time + 61
    ns.Log("second")
    wow.slash("/bf log")
    assert.are.same({ PREFIX .. "20:05:09 first", PREFIX .. "20:06:10 second" }, wow.printed)
  end)

  it("keeps only the last 50 entries", function()
    for i = 1, 51 do ns.Log("entry " .. i) end
    assert.are.equal(50, #ns.log)
    wow.slash("/bf log")
    assert.are.equal(50, #wow.printed)
    assert.matches("entry 2$", wow.printed[1])
    assert.matches("entry 51$", wow.printed[50])
  end)

  it("starts empty each session", function()
    ns.Log("before")
    ns = wow.start()
    assert.are.same({}, ns.log)
  end)

  it("is listed in the help line", function()
    wow.slash("/bf nonsense")
    assert.is_truthy(wow.printed[1]:find("/bf log", 1, true))
  end)
end)

describe("practice mode (#17)", function()
  local ns
  local ON = PREFIX .. "Practice mode on: awards are marked [Practice] and nothing is sent to the guild site."
  local OFF = PREFIX .. "Practice mode off."

  -- A new session from the saved data: a login, or a /reload.
  local function restart(login)
    ns = wow.start({ saved = { BureaucracyForeverDB = BureaucracyForeverDB } })
    wow.fire("PLAYER_ENTERING_WORLD", login, not login)
  end

  before_each(function()
    ns = wow.start()
    wow.fire("PLAYER_ENTERING_WORLD", true, false)
  end)

  it("starts off", function()
    assert.is_false(ns.Practice())
    assert.is_false(ns.Rolls.IsPractice())
  end)

  it("is toggled by /bf practice, which says so in chat", function()
    wow.slash("/bf practice")
    assert.is_true(ns.Practice())
    assert.is_true(ns.Rolls.IsPractice())
    wow.slash("/bf practice")
    assert.is_false(ns.Practice())
    assert.are.same({ ON, OFF }, wow.printed)
  end)

  it("shares one switch with the window's checkbox", function()
    wow.click(function() ns.UI.practiceBox:GetScript("OnClick")(ns.UI.practiceBox) end)
    assert.is_true(ns.Practice())
    assert.are.same({ ON }, wow.printed)
    wow.slash("/bf practice")
    assert.is_false(ns.Practice())
    wow.slash("/bf practice")
    wow.click(function() ns.UI.practiceBox:GetScript("OnClick")(ns.UI.practiceBox) end)
    assert.is_false(ns.Practice())
    assert.are.same({ ON, OFF, ON, OFF }, wow.printed)
  end)

  it("survives a /reload and is off after a login", function()
    wow.slash("/bf practice")
    restart(false)
    assert.is_true(ns.Practice())
    restart(true)
    assert.is_false(ns.Practice())
    assert.is_nil(BureaucracyForeverDB.practice)
  end)

  it("draws the window's marker off after a login that found it on", function()
    wow.slash("/bf practice")
    restart(true)
    assert.are.equal("Bureaucracy Forever", ns.UI.title:GetText())
    assert.is_false(ns.UI.practiceBox.check:IsShown())
  end)

  it("is listed in the help line", function()
    wow.slash("/bf nonsense")
    assert.is_truthy(wow.printed[1]:find("/bf practice", 1, true))
  end)
end)
