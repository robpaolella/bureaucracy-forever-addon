local wow = require("spec.support.wow")

local NOW = 1792000000 -- the stand-in's clock at start

-- A raid snapshot as the helper writes it. id is its raid id; fields override the rest.
local function tree(id, fields)
  local t = {
    formatVersion = 1, raid = id, code = "S" .. id:sub(-5):upper(), env = "staging",
    name = "Molten Core", startsAt = NOW, durationMin = 240, instance = 409,
    generated = 1791990000,
    addon = { version = "0.0.0", url = "https://example.invalid/addon" },
    bosses = {}, reserves = {}, awards = {},
  }
  for k, v in pairs(fields or {}) do t[k] = v end
  return t
end

-- The helper's inbox holding these raid entries ({ snapshot, catchup }).
local function inbox(entries)
  return { formatVersion = 1, written = NOW - 60, raids = entries }
end

-- The game writes saved data to disk and reads it back: a copy, not the same table.
local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[copy(k)] = copy(v) end
  return out
end

-- A /reload, or a later login, with the helper's file as given (nil: the placeholder).
local function reload(file)
  return wow.start({ saved = { BureaucracyForeverDB = copy(BureaucracyForeverDB) }, inbox = file })
end

-- Each loaded raid as "id origin", soonest first.
local function loaded(ns)
  local list = {}
  for i, raid in ipairs(ns.Raids.Status()) do list[i] = raid.id .. " " .. raid.origin end
  return list
end

local function inboxStatus(ns)
  return select(3, ns.Raids.Status())
end

describe("the helper's inbox", function()
  it("loads every raid in it as an inbox raid, with each one's catch-up", function()
    local catchup = { formatVersion = 1, raid = "raid00001", awards = {} }
    local ns = wow.start({ inbox = inbox({
      { snapshot = tree("raid00001"), catchup = catchup },
      { snapshot = tree("raid00002", { startsAt = NOW + 3600 }) },
    }) })
    assert.are.same({ "raid00001 inbox", "raid00002 inbox" }, loaded(ns))
    assert.are.same(catchup, ns.Inbox.Catchup("raid00001"))
    assert.is_nil(ns.Inbox.Catchup("raid00002"))
    assert.are.same({ present = true, readAt = NOW, problems = {} }, inboxStatus(ns))
    assert.are.same({}, wow.printed)
  end)

  it("skips and reports an entry it can't read, and loads the others", function()
    local ns = wow.start({ inbox = inbox({
      { snapshot = tree("raid00001") },
      { snapshot = tree("raid00002", { env = "test" }), catchup = {} },
      "not a raid",
      { snapshot = tree("raid00001", { name = "Again" }) },
      { snapshot = tree("raid00005", { formatVersion = 2 }) },
      { snapshot = tree("raid00006") },
    }) })
    assert.are.same({ "raid00001 inbox", "raid00006 inbox" }, loaded(ns))
    assert.are.equal("Molten Core", ns.Raids.Get("raid00001").name)
    assert.is_nil(ns.Inbox.Catchup("raid00002"))
    local problems = {
      "Raid 2 in the helper's file wasn't loaded: it isn't valid: env has the wrong type.",
      "Raid 3 in the helper's file wasn't loaded: it isn't a raid.",
      "Raid 4 in the helper's file wasn't loaded: the raid is listed twice.",
      "Raid 5 in the helper's file wasn't loaded: it needs a newer version of the add-on. "
        .. "Update the add-on.",
    }
    assert.are.same(problems, inboxStatus(ns).problems)
    assert.are.equal(#problems, #wow.printed)
    for i, problem in ipairs(problems) do assert.is_truthy(wow.printed[i]:find(problem, 1, true)) end
    assert.is_true(ns.Inbox.HelperPresent())
  end)

  it("changes nothing when the inbox is missing or empty", function()
    local ns = wow.start({ inbox = inbox({ { snapshot = tree("raid00001") } }) })
    ns.Raids.Load(ns.Snapshot.Validate(tree("raid00002"), "0.0.1"), "pasted")
    assert.is_true(ns.Selection.ChooseRaid("raid00001"))
    local before = copy(BureaucracyForeverDB)

    ns = reload()
    assert.are.same(before, ns.db)
    assert.is_false(ns.Inbox.HelperPresent())
    assert.are.same({ present = false, problems = {} }, inboxStatus(ns))
    assert.are.same({}, wow.printed)
  end)

  it("clears the inbox raids on raids = {} and keeps pasted ones", function()
    local ns = wow.start({ inbox = inbox({ { snapshot = tree("raid00001") },
      { snapshot = tree("raid00002") } }) })
    ns.Raids.Load(ns.Snapshot.Validate(tree("raid00002", { generated = 1 }), "0.0.1"), "pasted")
    ns.Raids.Load(ns.Snapshot.Validate(tree("raid00003"), "0.0.1"), "pasted")

    ns = reload(inbox({}))
    assert.are.same({ "raid00002 pasted", "raid00003 pasted" }, loaded(ns))
    assert.is_true(ns.Inbox.HelperPresent())
  end)

  it("drops a raid that has left the inbox and loads one that is new", function()
    wow.start({ inbox = inbox({ { snapshot = tree("raid00001") } }) })
    local ns = reload(inbox({ { snapshot = tree("raid00002") } }))
    assert.are.same({ "raid00002 inbox" }, loaded(ns))
  end)

  it("uses the later generated of a pasted and an inbox copy of one raid", function()
    local ns = wow.start()
    ns.Raids.Load(ns.Snapshot.Validate(tree("raid00001", { generated = 200, name = "Pasted" }), "0.0.1"),
      "pasted")
    ns = reload(inbox({ { snapshot = tree("raid00001", { generated = 100, name = "Inbox" }) } }))
    assert.are.equal("Pasted", ns.Raids.Get("raid00001").name)

    ns = reload(inbox({ { snapshot = tree("raid00001", { generated = 300, name = "Inbox" }) } }))
    assert.are.equal("Inbox", ns.Raids.Get("raid00001").name)
    assert.are.same({ "raid00001 inbox" }, loaded(ns))
  end)

  it("clears the selection with a notice when the selected raid leaves, keeping its awards", function()
    local ns = wow.start({ inbox = inbox({ { snapshot = tree("raid00001") },
      { snapshot = tree("raid00002") } }) })
    wow.state.player = "Ana Vale"
    assert.is_true(ns.Selection.ChooseRaid("raid00001"))
    ns.db.awards = { raid00001 = { { key = "k1", item = 16805, char = "Ana Vale", method = "HR" } } }

    ns = reload(inbox({ { snapshot = tree("raid00002") } }))
    assert.are.same({ "none", nil, nil }, { ns.db.activeBy, ns.db.activeRaid, ns.db.chosenBy })
    local notice = "The selected raid (S00001) is no longer loaded. Choose the raid in the Sync tab."
    assert.are.same({ notice }, inboxStatus(ns).problems)
    assert.is_truthy(wow.printed[1]:find(notice, 1, true))
    assert.are.equal(1, #ns.Raids.Awards("raid00001"))
  end)

  it("keeps the selected raid when it leaves the inbox but is still pasted", function()
    local ns = wow.start({ inbox = inbox({ { snapshot = tree("raid00001") } }) })
    ns.Raids.Load(ns.Snapshot.Validate(tree("raid00001"), "0.0.1"), "pasted")
    assert.is_true(ns.Selection.ChooseRaid("raid00001"))

    ns = reload(inbox({}))
    assert.are.same({ "chosen", "raid00001" }, { ns.db.activeBy, ns.db.activeRaid })
    assert.are.same({}, wow.printed)
  end)

  it("still loads its raids on a run that is not a guild run, and stays not a guild run", function()
    local ns = wow.start()
    assert.is_true(ns.Selection.ChooseOff())

    ns = reload(inbox({ { snapshot = tree("raid00001") } }))
    assert.are.same({ "raid00001 inbox" }, loaded(ns))
    assert.are.equal("off", ns.db.activeBy)
    assert.is_true(ns.Selection.IsQuiet())
  end)

  it("loads nothing from a file that fails as a whole, keeping the inbox raids it had", function()
    wow.start({ inbox = inbox({ { snapshot = tree("raid00001") } }) })
    local bad = {
      { { formatVersion = 2, written = NOW, raids = { { snapshot = tree("raid00002") } } },
        "The helper's file has a format this add-on doesn't read; update the add-on, so no raids "
          .. "were loaded from it." },
      { { formatVersion = 1, written = NOW, raids = { [2] = { snapshot = tree("raid00002") } } },
        "The helper's file has no list of raids, so no raids were loaded from it." },
      { { formatVersion = 1, written = NOW, raids = "raids" },
        "The helper's file has no list of raids, so no raids were loaded from it." },
      { { formatVersion = 1, raids = {} },
        "The helper's file has no time it was written, so no raids were loaded from it." },
      { { formatVersion = 1, written = math.huge, raids = {} },
        "The helper's file has no time it was written, so no raids were loaded from it." },
      { "inbox", "The helper's file isn't an inbox, so no raids were loaded from it." },
    }
    for _, case in ipairs(bad) do
      local ns = reload(case[1])
      assert.are.same({ "raid00001 inbox" }, loaded(ns))
      assert.are.same({ present = false, problems = { case[2] } }, inboxStatus(ns))
      assert.is_false(ns.Inbox.HelperPresent())
      assert.is_truthy(wow.printed[1]:find(case[2], 1, true))
    end
  end)

  it("exposes when it was read through the status read", function()
    local ns = wow.start()
    assert.is_nil(inboxStatus(ns).readAt)
    wow.state.time = NOW + 500
    ns.Inbox.Read(inbox({}))
    assert.are.equal(NOW + 500, inboxStatus(ns).readAt)
  end)
end)

describe("the suggested raid", function()
  local ns

  -- Loads these inbox raids: each { id, startsAt, durationMin, instance (false for none) }.
  local function raids(list)
    local entries = {}
    for i, r in ipairs(list) do
      local fields = { startsAt = r[2], durationMin = r[3] or 240, instance = r[4] or 409 }
      entries[i] = { snapshot = tree(r[1], fields) }
      if r[4] == false then entries[i].snapshot.instance = nil end
    end
    ns = wow.start({ inbox = inbox(entries) })
  end

  local HOUR = 3600

  it("is the one candidate", function()
    raids({ { "raid00001", NOW - HOUR }, { "raid00002", NOW, 60, 249 } })
    assert.are.equal("raid00001", ns.Selection.Suggest(409))
    assert.are.equal("raid00002", ns.Selection.Suggest(249))
    assert.are.equal("none", ns.Selection.ActiveBy())
  end)

  it("prefers a raid under way over one not started", function()
    raids({ { "raid00001", NOW + HOUR }, { "raid00002", NOW - HOUR } })
    assert.are.equal("raid00002", ns.Selection.Suggest(409))
  end)

  it("picks the soonest raid not started", function()
    raids({ { "raid00001", NOW + 5 * HOUR }, { "raid00002", NOW + 2 * HOUR },
      { "raid00003", NOW + 9 * HOUR } })
    assert.are.equal("raid00002", ns.Selection.Suggest(409))
  end)

  it("hands over to the next raid once the first has ended", function()
    raids({ { "raid00001", NOW - 4 * HOUR + 1 }, { "raid00002", NOW + HOUR } })
    assert.are.equal("raid00001", ns.Selection.Suggest(409))
    wow.state.time = NOW + 1
    assert.are.equal("raid00002", ns.Selection.Suggest(409))
  end)

  it("gives none for two raids under way, or two not started with the same start", function()
    raids({ { "raid00001", NOW - HOUR }, { "raid00002", NOW }, { "raid00003", NOW + HOUR } })
    assert.is_nil(ns.Selection.Suggest(409))
    raids({ { "raid00001", NOW + HOUR }, { "raid00002", NOW + HOUR } })
    assert.is_nil(ns.Selection.Suggest(409))
  end)

  it("gives none with no candidate", function()
    raids({ { "raid00001", NOW, 240, 249 } })
    assert.is_nil(ns.Selection.Suggest(409))
    assert.is_nil(ns.Selection.Suggest(nil))
    raids({})
    assert.is_nil(ns.Selection.Suggest(409))
  end)

  it("gives none for a raid that has ended", function()
    raids({ { "raid00001", NOW - 4 * HOUR } })
    assert.is_nil(ns.Selection.Suggest(409))
  end)

  it("gives none for a raid more than 12 hours away, and suggests it at 12 hours", function()
    raids({ { "raid00001", NOW + 12 * HOUR + 1 } })
    assert.is_nil(ns.Selection.Suggest(409))
    wow.state.time = NOW + 1
    assert.are.equal("raid00001", ns.Selection.Suggest(409))
  end)

  it("never suggests a raid with no instance", function()
    raids({ { "raid00001", NOW, 240, false } })
    assert.is_nil(ns.Raids.Get("raid00001").instance)
    assert.is_nil(ns.Selection.Suggest(409))
  end)

  it("reads the instance the player is in from the game", function()
    ns = wow.start()
    assert.are.same({ 0, "Eastern Kingdoms" }, { ns.Selection.Instance() })
    wow.state.instance = { name = "Molten Core", type = "raid", id = 409 }
    assert.are.same({ 409, "Molten Core" }, { ns.Selection.Instance() })
  end)
end)
