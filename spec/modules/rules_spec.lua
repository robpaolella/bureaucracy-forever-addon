local wow = require("spec.support.wow")

local ITEM = 18861

local function holder(user, char, kind, extra)
  local h = { user = user, char = char, kind = kind, trial = false }
  for k, v in pairs(extra or {}) do h[k] = v end
  return h
end

local function names(list)
  local out = {}
  for _, h in ipairs(list) do out[#out + 1] = h.char end
  return out
end

describe("Rules.Resolve", function()
  local Rules

  before_each(function()
    Rules = wow.start().Rules
  end)

  local function resolve(holders, extra)
    local args = { item = ITEM, reserves = { [ITEM] = holders }, awards = {} }
    for k, v in pairs(extra or {}) do args[k] = v end
    return Rules.Resolve(args)
  end

  it("goes to the open roll when nobody reserved it", function()
    local r = Rules.Resolve({ item = ITEM, reserves = {}, awards = {} })
    assert.are.equal("open", r.mode)
    assert.are.same({}, r.contenders)
  end)

  it("puts HR before SR", function()
    local r = resolve({ holder("u1", "Ann Lee", "SR"), holder("u2", "Bo Ray", "HR") })
    assert.are.equal("hr-single", r.mode)
    assert.are.same({ "Bo Ray" }, names(r.contenders))
  end)

  it("names several HR holders", function()
    local r = resolve({
      holder("u1", "Ann Lee", "HR"), holder("u2", "Bo Ray", "HR"), holder("u3", "Cy Dow", "SR") })
    assert.are.equal("hr-multi", r.mode)
    assert.are.same({ "Ann Lee", "Bo Ray" }, names(r.contenders))
  end)

  it("puts SR before an open roll", function()
    local r = resolve({ holder("u1", "Ann Lee", "SR"), holder("u2", "Bo Ray", "SR") })
    assert.are.equal("sr", r.mode)
    assert.are.same({ "Ann Lee", "Bo Ray" }, names(r.contenders))
  end)

  it("reads reserves keyed by the item id as a string", function()
    local reserves = { [tostring(ITEM)] = { holder("u1", "Ann Lee", "HR") } }
    local r = Rules.Resolve({ item = ITEM, reserves = reserves })
    assert.are.equal("hr-single", r.mode)
  end)

  it("spends a reserve once its user has the item, whatever the character", function()
    local holders = { holder("u1", "Ann Lee", "HR"), holder("u2", "Bo Ray", "SR") }
    local r = resolve(holders, { awards = { { key = "a1", item = ITEM, user = "u1", voided = false } } })
    assert.are.equal("sr", r.mode)
    assert.are.same({ "Bo Ray" }, names(r.contenders))
    assert.are.equal("already received", r.skipped[1].reason)
  end)

  it("spends every character of a user (alts)", function()
    local holders = { holder("u1", "Ann Lee", "HR"), holder("u1", "Ann Alt", "SR") }
    local r = resolve(holders, { awards = { { key = "a1", item = ITEM, user = "u1" } } })
    assert.are.equal("open", r.mode)
    assert.are.equal(2, #r.skipped)
  end)

  it("ignores awards of other items and awards with no user", function()
    local r = resolve({ holder("u1", "Ann Lee", "HR") }, { awards = {
      { key = "a1", item = 999, user = "u1" }, { key = "a2", item = ITEM } } })
    assert.are.equal("hr-single", r.mode)
  end)

  it("never lets trial holders roll, and shows them", function()
    local r = resolve({ holder("u1", "Ann Lee", "HR", { trial = true }), holder("u2", "Bo Ray", "SR") })
    assert.are.equal("sr", r.mode)
    assert.are.equal("trial", r.skipped[1].reason)
  end)

  it("skips a win-limit holder and tries the next tier", function()
    local r = resolve({
      holder("u1", "Ann Lee", "HR", { blocked = "win-limit" }), holder("u2", "Bo Ray", "SR") })
    assert.are.equal("sr", r.mode)
    assert.are.equal("win-limit", r.skipped[1].reason)
  end)

  it("treats an unknown blocked code as blocked and returns it as given", function()
    local r = resolve({ holder("u1", "Ann Lee", "HR", { blocked = "council-hold" }) })
    assert.are.equal("open", r.mode)
    assert.are.equal("council-hold", r.skipped[1].reason)
  end)

  it("skips holders not in the raid, matching names without the realm", function()
    local holders = { holder("u1", "Ann Lee", "HR"), holder("u2", "Bo Ray", "HR") }
    local r = resolve(holders, { roster = { "Bo Ray-Realm", "Cy Dow" } })
    assert.are.same({ "Bo Ray" }, names(r.contenders))
    assert.are.equal("not in raid", r.skipped[1].reason)
  end)

  it("skips holders the game won't let receive it", function()
    local holders = { holder("u1", "Ann Lee", "HR"), holder("u2", "Bo Ray", "SR") }
    local r = resolve(holders, { roster = { "Ann Lee", "Bo Ray" }, candidates = { "Bo Ray" } })
    assert.are.equal("sr", r.mode)
    assert.are.equal("cannot receive", r.skipped[1].reason)
  end)

  it("resolves two copies in turn with one HR holder", function()
    local holders = { holder("u1", "Ann Lee", "HR"), holder("u2", "Bo Ray", "SR") }
    local awards = {}
    local first = resolve(holders, { awards = awards })
    assert.are.equal("hr-single", first.mode)
    awards[#awards + 1] = { key = "a1", item = ITEM, user = first.contenders[1].user }
    local second = resolve(holders, { awards = awards })
    assert.are.equal("sr", second.mode)
    assert.are.same({ "Bo Ray" }, names(second.contenders))
  end)

  it("gives the reserve back when the award is voided (Undo)", function()
    local holders = { holder("u1", "Ann Lee", "HR") }
    local awards = { { key = "a1", item = ITEM, user = "u1" } }
    assert.are.equal("open", resolve(holders, { awards = awards }).mode)
    awards[1].voided = true
    assert.are.equal("hr-single", resolve(holders, { awards = awards }).mode)
  end)

  it("keeps a key voided when only one copy of it says so", function()
    local awards = {
      { key = "a1", item = ITEM, user = "u1", voided = true },
      { key = "a1", item = ITEM, user = "u1", voided = false },
    }
    assert.are.equal("hr-single", resolve({ holder("u1", "Ann Lee", "HR") }, { awards = awards }).mode)
  end)

  it("counts a key once between baseline and add-on awards", function()
    -- The same award in the baseline and the add-on's list spends only its own user.
    local awards = {
      { key = "a1", item = ITEM, user = "u1" },
      { key = "a1", item = ITEM, user = "u1" },
    }
    local r = resolve({ holder("u1", "Ann Lee", "HR"), holder("u2", "Bo Ray", "HR") }, { awards = awards })
    assert.are.same({ "Bo Ray" }, names(r.contenders))
  end)
end)
