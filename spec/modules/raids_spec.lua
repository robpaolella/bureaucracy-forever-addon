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

-- The game writes saved data to disk and reads it back: a copy, not the same table.
local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[copy(k)] = copy(v) end
  return out
end

local function reload()
  return wow.start({ saved = { BureaucracyForeverDB = copy(BureaucracyForeverDB) } })
end

local function ids(status)
  local list = {}
  for i, raid in ipairs(status) do list[i] = raid.id end
  return list
end

describe("Raids", function()
  local ns, Raids

  before_each(function()
    ns = wow.start()
    Raids = ns.Raids
  end)

  it("keeps loaded raids, their env and load time across a save and reload", function()
    -- A raid pasted as the site's text, then one from the inbox.
    local pasted = assert(ns.Sync.ReadPasted("BFSNAP1:1/1:"
      .. "{ formatVersion = 1, raid = \"cm9xr2k4a0001\", code = \"SA0001\", env = \"staging\", "
      .. "name = \"Molten Core\", startsAt = 1792000000, durationMin = 240, generated = 1791990000, "
      .. "addon = { version = \"0.0.1\", url = \"u\" }, bosses = {}, reserves = {}, awards = {} }"))
    assert.are.equal("cm9xr2k4a0001", Raids.Load(pasted, "pasted"))
    wow.state.time = 1792000500
    Raids.Load(snapshot(ns, "cm9xr2k4b0002", { env = "production", code = "PB0002", startsAt = 1792100000 }),
      "inbox")

    ns = reload()
    local status = ns.Raids.Status()
    assert.are.same({
      { id = "cm9xr2k4a0001", code = "SA0001", name = "Molten Core", env = "staging", startsAt = 1792000000,
        durationMin = 240, generated = 1791990000, loadedAt = 1792000000, origin = "pasted",
        pasted = true, inbox = false },
      { id = "cm9xr2k4b0002", code = "PB0002", name = "Molten Core", env = "production", instance = 409,
        startsAt = 1792100000, durationMin = 240, generated = 1791990000, loadedAt = 1792000500,
        origin = "inbox", pasted = false, inbox = true },
    }, status)
    assert.are.equal("production", ns.Raids.Get("cm9xr2k4b0002").env)
  end)

  it("holds a pasted and an inbox copy of one raid and uses the later generated", function()
    Raids.Load(snapshot(ns, "raid00001", { generated = 100, name = "Pasted" }), "pasted")
    Raids.Load(snapshot(ns, "raid00001", { generated = 200, name = "Inbox" }), "inbox")
    local raid = Raids.Status()[1]
    assert.are.same({ "Inbox", "inbox", 200, true, true },
      { raid.name, raid.origin, raid.generated, raid.pasted, raid.inbox })

    Raids.Load(snapshot(ns, "raid00001", { generated = 300, name = "Pasted again" }), "pasted")
    assert.are.equal("Pasted again", Raids.Get("raid00001").name)
  end)

  it("uses the pasted copy when both copies have the same generated", function()
    Raids.Load(snapshot(ns, "raid00001", { name = "Inbox" }), "inbox")
    Raids.Load(snapshot(ns, "raid00001", { name = "Pasted" }), "pasted")
    assert.are.equal("Pasted", Raids.Get("raid00001").name)
    assert.are.equal("pasted", Raids.Status()[1].origin)
  end)

  it("replaces a held pasted copy when the raid is pasted again", function()
    Raids.Load(snapshot(ns, "raid00001", { generated = 200, name = "First" }), "pasted")
    wow.state.time = 1792000900
    Raids.Load(snapshot(ns, "raid00001", { generated = 100, name = "Second" }), "pasted")
    assert.are.same({ "Second", 100, 1792000900 },
      { Raids.Status()[1].name, Raids.Status()[1].generated, Raids.Status()[1].loadedAt })
    assert.are.equal(1, #Raids.Status())
  end)

  it("calls the after-load hook with the raid id", function()
    local heard = {}
    Raids.afterLoad = function(id) heard[#heard + 1] = { id, Raids.Get(id) ~= nil } end
    Raids.Load(snapshot(ns, "raid00001"), "pasted")
    Raids.ReplaceInbox({ snapshot(ns, "raid00002") })
    assert.are.same({ { "raid00001", true }, { "raid00002", true } }, heard)
  end)

  it("removes a pasted raid from the store and the status", function()
    Raids.Load(snapshot(ns, "raid00001"), "pasted")
    Raids.Load(snapshot(ns, "raid00002"), "pasted")
    assert.is_true(Raids.Remove("raid00001"))
    assert.are.same({ "raid00002" }, ids(Raids.Status()))
    assert.is_nil(ns.db.raids.raid00001)
    assert.is_nil(Raids.Get("raid00001"))
    assert.are.same({ nil, "not pasted" }, { Raids.Remove("raid00001") })
  end)

  it("leaves the inbox copy loaded when the pasted copy is removed", function()
    Raids.Load(snapshot(ns, "raid00001", { generated = 200, name = "Pasted" }), "pasted")
    Raids.Load(snapshot(ns, "raid00001", { generated = 100, name = "Inbox" }), "inbox")
    assert.is_true(Raids.Remove("raid00001"))
    local raid = Raids.Status()[1]
    assert.are.same({ "Inbox", "inbox", false, true }, { raid.name, raid.origin, raid.pasted, raid.inbox })
    assert.are.same({ nil, "not pasted" }, { Raids.Remove("raid00001") })
  end)

  it("keeps a raid whose removal the hook refuses, and passes the confirmation on", function()
    local asked = {}
    Raids.beforeRemove = function(id, confirmed)
      asked[#asked + 1] = { id, confirmed or false }
      if not confirmed then return "needs confirmation" end
    end
    Raids.Load(snapshot(ns, "raid00001"), "pasted")
    assert.are.same({ nil, "needs confirmation" }, { Raids.Remove("raid00001") })
    assert.are.same({ "raid00001" }, ids(Raids.Status()))
    assert.is_true(Raids.Remove("raid00001", true))
    assert.are.same({}, Raids.Status())
    assert.are.same({ { "raid00001", false }, { "raid00001", true } }, asked)
  end)

  it("replaces all inbox copies, keeps pasted ones and reports the raids added and gone", function()
    Raids.Load(snapshot(ns, "raid00001"), "pasted")
    Raids.Load(snapshot(ns, "raid00001", { generated = 1791999999 }), "inbox")
    Raids.Load(snapshot(ns, "raid00002"), "inbox")
    Raids.Load(snapshot(ns, "raid00003"), "inbox")

    local added, left = Raids.ReplaceInbox({ snapshot(ns, "raid00003"), snapshot(ns, "raid00004") })
    assert.are.same({ "raid00004" }, added)
    assert.are.same({ "raid00002" }, left)
    assert.are.same({ "raid00001", "raid00003", "raid00004" }, ids(Raids.Status()))
    assert.are.equal("pasted", Raids.Status()[1].origin)

    added, left = Raids.ReplaceInbox({})
    assert.are.same({}, added)
    assert.are.same({ "raid00003", "raid00004" }, left)
    local raid = Raids.Status()[1]
    assert.are.same({ "raid00001", true, false }, { raid.id, raid.pasted, raid.inbox })
    assert.are.equal(1, #Raids.Status())
  end)

  it("finds the one loaded raid with a code", function()
    Raids.Load(snapshot(ns, "raid0aa001"), "pasted")
    Raids.Load(snapshot(ns, "raid0bb002"), "inbox")
    local id, found = Raids.FindByCode("sbb002")
    assert.are.equal("raid0bb002", id)
    assert.are.equal("raid0bb002", found.raid)
    assert.is_nil(Raids.FindByCode("SCC003"))
  end)

  it("finds neither raid, with a notice, when two loaded raids share a code", function()
    Raids.Load(snapshot(ns, "raid0aa001"), "pasted")
    Raids.Load(snapshot(ns, "raidxaa001"), "inbox")
    local id, notice = Raids.FindByCode("SAA001")
    assert.is_nil(id)
    assert.are.equal("Two loaded raids have the code SAA001. Choose the raid in the Sync tab.", notice)
  end)

  it("reads the environment of the selected raid, and none without one", function()
    Raids.Load(snapshot(ns, "raid00001", { env = "production", code = "P00001" }), "pasted")
    assert.is_nil(Raids.Env())
    ns.db.activeRaid = "raid00002"
    assert.is_nil(Raids.Env())
    ns.db.activeRaid = "raid00001"
    assert.are.equal("production", Raids.Env())
  end)

  it("reads the saved award lists, voided awards included", function()
    assert.are.same({}, Raids.Awards("raid00001"))
    assert.are.same({}, Raids.NoRaidAwards())
    assert.is_false(Raids.HasAwards("raid00001"))
    local voided = { key = "k1", item = 16805, char = "Ana Vale", method = "HR", voided = true }
    local held = { key = "k2", item = 16800, char = "Bo Marsh", method = "SR", voided = false }
    ns.db.awards = { raid00001 = { voided } }
    ns.db.noRaid = { held }
    assert.are.same({ voided }, Raids.Awards("raid00001"))
    assert.is_true(Raids.HasAwards("raid00001"))
    assert.is_false(Raids.HasAwards("raid00002"))
    assert.are.same({ held }, Raids.NoRaidAwards())
  end)
end)
