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
