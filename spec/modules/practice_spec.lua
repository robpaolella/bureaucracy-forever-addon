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
