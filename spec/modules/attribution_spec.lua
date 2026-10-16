local wow = require("spec.support.wow")

local function loot(guid, ...)
  local items = {}
  for i, id in ipairs({ ... }) do
    items[i] = { link = "[" .. id .. "]", name = "Item " .. id, quality = 4, sourceGuid = guid }
  end
  wow.openLoot(items)
  wow.closeLoot()
end

local function tree(id)
  return {
    formatVersion = 1, raid = id, code = "MC0001", env = "staging", name = "Molten Core",
    startsAt = 1792000000, durationMin = 240, generated = 1791990000,
    addon = { version = "0.1.0", url = "https://example.invalid/addon" },
    bosses = {
      { id = "luc", name = "Lucifron", trash = false, items = { 1, 3 } },
      { id = "mag", name = "Magmadar", trash = false, items = { 2, 3 } },
      { id = "gar", name = "Baron Geddon", trash = false, items = { 4 } },
      { id = "tra", name = "Trash", trash = true, items = { 5 } },
    },
    reserves = {}, awards = {},
  }
end

describe("Attribution", function()
  local ns, A

  local function choose(fields)
    local t = tree("raid00001")
    for k, v in pairs(fields or {}) do t[k] = v end
    ns.Raids.Load(assert(ns.Snapshot.Validate(t, "0.1.0")), "pasted")
    assert(ns.Selection.ChooseRaid("raid00001"))
  end
  local function kill(name, success, id) wow.fire("ENCOUNTER_END", id or 1, name, 0, 5, success or 1) end
  local function pull(name) wow.fire("ENCOUNTER_START", 1, name, 0, 5) end

  before_each(function()
    ns = wow.start()
    A = ns.Attribution
  end)

  it("gives an item on one table that boss, killed or not", function()
    choose()
    assert.are.equal("gar", A.Suggest(4, "c1"))
  end)

  it("gives an item on several tables the latest kill, opened after it and before the next pull", function()
    choose()
    kill("Magmadar")
    wow.state.time = wow.state.time + 60
    kill("Lucifron")
    wow.state.time = wow.state.time + 60
    loot("c1", 3)
    assert.are.equal("luc", A.Suggest(3, "c1"))
  end)

  it("gives none when a pull began after the kill, or nothing was killed", function()
    choose()
    assert.is_nil((A.Suggest(3, "c0")))
    kill("Lucifron")
    wow.state.time = wow.state.time + 60
    pull("Magmadar")
    wow.state.time = wow.state.time + 60
    loot("c2", 3)
    assert.is_nil((A.Suggest(3, "c2")))
  end)

  it("works the spec's Lucifron and Magmadar example, and keeps a corpse's first attribution", function()
    choose()
    kill("Lucifron")
    wow.state.time = wow.state.time + 60
    loot("c1", 3)
    wow.state.time = wow.state.time + 240
    pull("Magmadar")
    kill("Magmadar", 0)
    wow.state.time = wow.state.time + 600
    loot("c2", 3)
    assert.is_nil((A.Suggest(3, "c2")))
    assert.is_false(A.Killed("mag"))
    wow.state.time = wow.state.time + 600
    loot("c1", 3) -- reopened: its first time stands, whatever happened since
    assert.are.equal("luc", A.Suggest(3, "c1"))
  end)

  it("gives an unlisted item the Trash row, or none without one, and says it is unlisted", function()
    choose()
    assert.are.same({ "tra", "unlisted" }, { A.Suggest(99, "c1") })
    assert.are.same({ "tra" }, { A.Suggest(5, "c1") })
    wow.start()
    ns = wow.ns
    A = ns.Attribution
    choose({ bosses = { { id = "luc", name = "Lucifron", trash = false, items = { 1 } } } })
    assert.are.same({ nil, "unlisted" }, { A.Suggest(99, "c1") })
  end)

  it("matches the boss name ignoring case and spaces", function()
    choose()
    kill("BARON  geddon")
    assert.is_true(A.Killed("gar"))
    kill("Trash")
    assert.is_false(A.Killed("tra"))
  end)

  describe("by encounter id", function()
    local function rows(...)
      choose({ bosses = { ... } })
    end
    local function boss(id, name, encounter)
      return { id = id, name = name, trash = false, items = { 1 }, encounter = encounter }
    end

    it("records the row whose encounter is the kill's id, whatever the name given", function()
      rows(boss("a", "Lucifron", 663), boss("b", "Magmadar", 664))
      kill("Lucifer (translated)", 1, 664)
      assert.is_true(A.Killed("b"))
      assert.is_false(A.Killed("a"))
    end)

    it("lets the id win over a name matching another row", function()
      rows(boss("a", "Lucifron", 663), boss("b", "Magmadar", 664))
      kill("Lucifron", 1, 664)
      assert.is_true(A.Killed("b"))
      assert.is_false(A.Killed("a"))
    end)

    it("falls back to the name among rows without an encounter when no id matches", function()
      rows(boss("a", "Lucifron", 663), boss("b", "Magmadar"))
      kill("magmadar", 1, 999)
      assert.is_true(A.Killed("b"))
      kill("Lucifron", 1, 999)
      assert.is_false(A.Killed("a"))
    end)

    it("records nothing for two rows with the same encounter, or a failed attempt", function()
      rows(boss("a", "Lucifron", 663), boss("b", "Lucifron", 663))
      kill("Lucifron", 1, 663)
      assert.is_false(A.Killed("a"))
      assert.is_false(A.Killed("b"))
      rows(boss("a", "Lucifron", 663))
      kill("Lucifron", 0, 663)
      assert.is_false(A.Killed("a"))
    end)

    it("never matches Trash by id", function()
      rows({ id = "t", name = "Trash", trash = true, items = { 1 }, encounter = 5 })
      kill("Trash", 1, 5)
      assert.is_false(A.Killed("t"))
    end)
  end)

  it("records no kill for a name matching no row or two rows, but counts the pull", function()
    choose({ bosses = {
      { id = "a", name = "Twin", trash = false, items = { 1, 2 } },
      { id = "b", name = "t win", trash = false, items = { 1, 2 } },
      { id = "c", name = "Other", trash = false, items = { 1 } },
    } })
    kill("Twin")
    kill("Nobody")
    assert.is_false(A.Killed("a"))
    assert.is_false(A.Killed("b"))
    assert.is_nil(ns.db.attribution)
    pull("Nobody")
    assert.are.same({}, ns.db.attribution.raid00001.kills)
    assert.are.equal(1, #ns.db.attribution.raid00001.pulls)
    assert.is_nil((A.Suggest(1, "c1")))
  end)

  it("records nothing and suggests nothing with no raid selected or off a guild run", function()
    pull("Lucifron")
    kill("Lucifron")
    loot("c1", 3)
    assert.is_nil(ns.db.attribution)
    choose()
    assert.is_true(ns.Selection.ChooseOff())
    pull("Lucifron")
    kill("Lucifron")
    loot("c1", 3)
    assert.is_nil(ns.db.attribution)
    assert.is_nil((A.Suggest(4, "c1")))
    assert.is_nil((A.Suggest(99, "c1")))
    assert.is_false(A.Killed("luc"))
  end)

  it("keeps kills, pulls and corpses across a /reload", function()
    choose()
    pull("Lucifron")
    kill("Lucifron")
    wow.state.time = wow.state.time + 5
    loot("c1", 3)
    local saved = BureaucracyForeverDB
    ns = wow.start({ saved = { BureaucracyForeverDB = saved } })
    A = ns.Attribution
    assert.is_true(A.Killed("luc"))
    assert.are.equal("luc", A.Suggest(3, "c1"))
    assert.are.equal(1, #ns.db.attribution.raid00001.pulls)
  end)
end)
