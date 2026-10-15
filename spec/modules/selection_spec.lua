local wow = require("spec.support.wow")

-- A validated snapshot of a raid. id is its raid id; fields override the rest.
local function snapshot(ns, id, fields)
  local tree = {
    formatVersion = 1, raid = id, code = "S" .. id:sub(-5):upper(), env = "staging",
    name = "Molten Core", startsAt = 1792000000, durationMin = 240, instance = 409,
    generated = 1791990000,
    addon = { version = "0.1.0", url = "https://example.invalid/addon" },
    bosses = {}, reserves = {}, awards = {},
  }
  for k, v in pairs(fields or {}) do tree[k] = v end
  return assert(ns.Snapshot.Validate(tree, "0.1.0"))
end

-- The site's pasted reserves text for a raid.
local function pastedText(id, code)
  return "BFSNAP1:1/1:{ formatVersion = 1, raid = \"" .. id .. "\", code = \"" .. code .. "\", "
    .. "env = \"staging\", name = \"Onyxia\", startsAt = 1792000000, durationMin = 120, "
    .. "generated = 1791990000, addon = { version = \"0.0.1\", url = \"u\" }, bosses = {}, "
    .. "reserves = {}, awards = {} }"
end

-- The game writes saved data to disk and reads it back: a copy, not the same table.
local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[copy(k)] = copy(v) end
  return out
end

describe("Selection", function()
  local ns, Raids, Selection

  local function award(raidId)
    ns.db.awards = ns.db.awards or {}
    ns.db.awards[raidId] = { { key = "k1", item = 16805, char = "Ana Vale", method = "HR" } }
  end

  local function selection()
    return { ns.db.activeBy, ns.db.activeRaid, ns.db.chosenBy }
  end

  before_each(function()
    ns = wow.start()
    Raids, Selection = ns.Raids, ns.Selection
    wow.state.player = "Ana Vale"
    Raids.Load(snapshot(ns, "raid00001"), "pasted")
    Raids.Load(snapshot(ns, "raid00002"), "inbox")
  end)

  it("starts with no raid chosen", function()
    assert.are.equal("none", Selection.ActiveBy())
    assert.are.same({ activeBy = "none", waiting = false }, Selection.Status())
    assert.is_false(Selection.IsQuiet())
  end)

  it("asks before moving off a raid with awards, then changes", function()
    assert.is_true(Selection.ChooseRaid("raid00001"))
    award("raid00001")
    wow.state.player = "Bo Marsh"
    assert.are.same({ nil, "needs confirmation" }, { Selection.ChooseRaid("raid00002") })
    assert.are.same({ "chosen", "raid00001", "Ana Vale" }, selection())
    assert.is_true(Selection.ChooseRaid("raid00002", true))
    assert.are.same({ "chosen", "raid00002", "Bo Marsh" }, selection())
    assert.are.equal(1, #Raids.Awards("raid00001"))
  end)

  it("changes without asking when the selected raid has no awards", function()
    Selection.ChooseRaid("raid00001")
    award("raid00002")
    assert.is_true(Selection.ChooseRaid("raid00002"))
    assert.are.same({ "chosen", "raid00002", "Ana Vale" }, selection())
  end)

  it("never asks when the selected raid is chosen or pasted again", function()
    Selection.ChooseRaid("raid00001")
    award("raid00001")
    local at = ns.db.selectionAt
    wow.state.time = wow.state.time + 60
    assert.is_true(Selection.ChooseRaid("raid00001"))
    assert.are.equal(at, ns.db.selectionAt)

    local raidId, _, waiting = Selection.Paste(pastedText("raid00003", "S00003"))
    assert.are.same({ "raid00003", "needs confirmation" }, { raidId, waiting })
    assert.is_true(Selection.ChooseRaid("raid00003", true))
    award("raid00003")
    raidId, _, waiting = Selection.Paste(pastedText("raid00003", "S00003"))
    assert.are.same({ "raid00003" }, { raidId, waiting })
    assert.are.same({ "chosen", "raid00003", "Ana Vale" }, selection())
  end)

  it("refuses a raid that isn't loaded", function()
    assert.are.same({ nil, "not loaded" }, { Selection.ChooseRaid("raid00009") })
    assert.are.equal("none", Selection.ActiveBy())
  end)

  it("chooses not a guild run without asking, and a raid after it without asking", function()
    Selection.ChooseRaid("raid00001")
    award("raid00001")
    assert.is_true(Selection.ChooseOff())
    assert.are.same({ "off", nil, "Ana Vale" }, selection())
    assert.is_true(Selection.IsQuiet())
    assert.are.equal(1, #Raids.Awards("raid00001"))
    assert.is_true(Selection.ChooseRaid("raid00002"))
    assert.are.same({ "chosen", "raid00002", "Ana Vale" }, selection())
    assert.is_false(Selection.IsQuiet())
  end)

  it("keeps the selection across a save and reload, and the status read returns it", function()
    Selection.ChooseRaid("raid00002")
    ns = wow.start({ saved = { BureaucracyForeverDB = copy(BureaucracyForeverDB) } })
    local raids, status = ns.Raids.Status()
    assert.are.equal(2, #raids)
    assert.are.same({ activeRaid = "raid00002", activeBy = "chosen", chosenBy = "Ana Vale",
      at = 1792000000, code = "S00002", waiting = false }, status)
    assert.are.equal("chosen", ns.Selection.ActiveBy())
  end)

  it("removes a pasted raid with awards only when confirmed, keeping its awards", function()
    award("raid00001")
    assert.are.same({ nil, "needs confirmation" }, { Raids.Remove("raid00001") })
    assert.is_not_nil(Raids.Get("raid00001"))
    assert.is_true(Raids.Remove("raid00001", true))
    assert.is_nil(Raids.Get("raid00001"))
    assert.are.equal(1, #Raids.Awards("raid00001"))
  end)

  it("removes a pasted raid without awards at once", function()
    Raids.Load(snapshot(ns, "raid00003"), "pasted")
    assert.is_true(Raids.Remove("raid00003"))
    assert.is_nil(Raids.Get("raid00003"))
  end)

  it("sets none when the selected pasted raid is removed, but not while an inbox copy stays", function()
    Selection.ChooseRaid("raid00001")
    award("raid00001")
    assert.are.same({ nil, "needs confirmation" }, { Raids.Remove("raid00001") })
    assert.are.same({ "chosen", "raid00001", "Ana Vale" }, selection())
    assert.is_true(Raids.Remove("raid00001", true))
    assert.are.same({ "none", nil, nil }, selection())
    assert.are.equal(1, #Raids.Awards("raid00001"))

    Raids.Load(snapshot(ns, "raid00002"), "pasted")
    Selection.ChooseRaid("raid00002")
    assert.is_true(Raids.Remove("raid00002"))
    assert.are.same({ "chosen", "raid00002", "Ana Vale" }, selection())
  end)

  it("loads a pasted raid but waits to choose it when the current raid has awards", function()
    Selection.ChooseRaid("raid00001")
    award("raid00001")
    local raidId, notice, waiting = Selection.Paste(pastedText("raid00003", "S00003"))
    assert.are.same({ "raid00003", "needs confirmation" }, { raidId, waiting })
    assert.matches("is out", notice)
    assert.are.equal("Onyxia", Raids.Get("raid00003").name)
    assert.are.same({ "chosen", "raid00001", "Ana Vale" }, selection())
    assert.is_true(Selection.ChooseRaid(raidId, true))
    assert.are.same({ "chosen", "raid00003", "Ana Vale" }, selection())
  end)

  it("chooses a pasted raid at once when the current raid has no awards", function()
    local raidId, _, waiting = Selection.Paste(pastedText("raid00003", "S00003"))
    assert.are.same({ "raid00003", nil }, { raidId, waiting })
    assert.are.same({ "chosen", "raid00003", "Ana Vale" }, selection())
  end)

  it("returns the error for pasted text it can't read, and changes nothing", function()
    local raidId, err = Selection.Paste("not a snapshot")
    assert.is_nil(raidId)
    assert.is_string(err)
    assert.are.equal("none", Selection.ActiveBy())
  end)

  it("applies the group's choice only when its (at, by) is later, and never asks", function()
    Selection.ChooseRaid("raid00001")
    award("raid00001")
    local at = ns.db.selectionAt
    assert.is_true(Selection.Apply("s00002", at + 10, "Bo Marsh"))
    assert.are.same({ "chosen", "raid00002", "Bo Marsh" }, selection())
    -- A repeat and an older choice change nothing.
    assert.is_nil(Selection.Apply("S00002", at + 10, "Bo Marsh"))
    assert.is_nil(Selection.Apply("S00001", at + 5, "Zed Last"))
    assert.are.same({ "chosen", "raid00002", "Bo Marsh" }, selection())
    -- On a tie of at, the name decides, byte by byte.
    assert.is_nil(Selection.Apply("S00001", at + 10, "Ana Vale"))
    assert.is_true(Selection.Apply("S00001", at + 10, "Bo Marsi"))
    assert.are.same({ "chosen", "raid00001", "Bo Marsi" }, selection())
    assert.are.equal(at + 10, Selection.Status().at)
  end)

  it("sets not a guild run for the code -", function()
    assert.is_true(Selection.Apply("-", 1792000100, "Bo Marsh"))
    assert.are.same({ "off", nil, "Bo Marsh" }, selection())
    assert.is_true(Selection.IsQuiet())
  end)

  it("holds a choice for a raid not loaded and applies it when the raid loads", function()
    assert.is_true(Selection.Apply("S00003", 1792000100, "Bo Marsh"))
    assert.are.same({ "chosen", nil, "Bo Marsh" }, selection())
    assert.is_true(Selection.Status().waiting)
    Raids.Load(snapshot(ns, "raid00004"), "inbox")
    assert.is_nil(ns.db.activeRaid)
    Raids.ReplaceInbox({ snapshot(ns, "raid00003") })
    assert.are.same({ "chosen", "raid00003", "Bo Marsh" }, selection())
    assert.is_false(Selection.Status().waiting)
  end)

  it("selects neither raid, with a notice, when the code names two loaded raids", function()
    Raids.Load(snapshot(ns, "raidx00001"), "inbox")
    local applied, notice = Selection.Apply("S00001", 1792000100, "Bo Marsh")
    assert.is_true(applied)
    assert.are.equal("Two loaded raids have the code S00001. Choose the raid in the Sync tab.", notice)
    assert.are.same({ "chosen", nil, "Bo Marsh" }, selection())
  end)

  it("sets none with a notice when the selected raid goes away, and keeps its awards", function()
    Selection.ChooseRaid("raid00002")
    award("raid00002")
    assert.is_nil(Selection.RaidGone("raid00001"))
    assert.is_nil(Selection.RaidGone("raid00002"))
    local _, left = Raids.ReplaceInbox({})
    assert.are.same({ "raid00002" }, left)
    assert.are.equal("The selected raid (S00002) is no longer loaded. Choose the raid in the Sync tab.",
      Selection.RaidGone("raid00002"))
    assert.are.same({ "none", nil, nil }, selection())
    assert.are.equal(1, #Raids.Awards("raid00002"))
    -- An older choice from the group still doesn't apply.
    assert.is_nil(Selection.Apply("S00001", 1791999999, "Bo Marsh"))
  end)

  it("clears the selection and forgets the held choice", function()
    Selection.ChooseOff()
    Selection.Clear()
    assert.are.same({ activeBy = "none", waiting = false }, Selection.Status())
    assert.is_true(Selection.Apply("S00001", 1, "Bo Marsh"))
    assert.are.same({ "chosen", "raid00001", "Bo Marsh" }, selection())
  end)

  it("makes this officer's change later than the held choice, even with a slow clock", function()
    Selection.Apply("S00001", 1792000500, "Bo Marsh")
    Selection.ChooseRaid("raid00002")
    assert.are.equal(1792000501, Selection.Status().at)
    assert.is_nil(Selection.Apply("S00001", 1792000500, "Zed Last"))
  end)

  it("reads the selected raid's environment, and is quiet only when off", function()
    Raids.Load(snapshot(ns, "raid00005", { env = "production", code = "P00005" }), "pasted")
    assert.is_nil(Raids.Env())
    Selection.ChooseRaid("raid00005")
    assert.are.equal("production", Raids.Env())
    assert.is_false(Selection.IsQuiet())
    Selection.ChooseRaid("raid00001")
    assert.are.equal("staging", Raids.Env())
    Selection.ChooseOff()
    assert.is_nil(Raids.Env())
    assert.is_true(Selection.IsQuiet())
    Selection.Apply("S00003", Selection.Status().at + 1, "Bo Marsh")
    assert.is_false(Selection.IsQuiet())
  end)
end)
