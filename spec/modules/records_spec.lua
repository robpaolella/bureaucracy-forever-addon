local wow = require("spec.support.wow")

local RAID = "cm9xr2k4a0001"

local function snapshot(ns, id, fields)
  local tree = {
    formatVersion = 1, raid = id, code = "S" .. id:sub(-5):upper(), env = "staging",
    name = "Molten Core", startsAt = 1792000000, durationMin = 240, generated = 1791990000,
    addon = { version = "0.1.0", url = "https://example.invalid/addon" },
    bosses = {}, reserves = {}, awards = {},
  }
  for k, v in pairs(fields or {}) do tree[k] = v end
  return assert(ns.Snapshot.Validate(tree, "0.1.0"))
end

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[copy(k)] = copy(v) end
  return out
end

local function ana(fields)
  local f = {
    boss = "lb_lucifron", item = 16805, char = "Ana Vale", user = "u_ana", method = "HR", roll = 91,
  }
  for k, v in pairs(fields or {}) do f[k] = v end
  return f
end

describe("Records", function()
  local ns, Records

  -- Loads a raid and selects it, as pasting its snapshot does.
  local function selectRaid(id, fields)
    ns.Raids.Load(snapshot(ns, id or RAID, fields), "pasted")
    assert.is_true(ns.Selection.ChooseRaid(id or RAID, true))
  end

  before_each(function()
    ns = wow.start()
    Records = ns.Records
    wow.state.player = "Rae Quill"
  end)

  describe("award", function()
    it("records an announced award for the selected raid, with its env, practice mark and sender", function()
      selectRaid()
      local op, outcome = Records.Award(ana({ practice = true }))
      assert.are.equal("recorded", outcome)
      assert.is_true(Records.ValidId(op.id))
      assert.are.same({
        type = "award", id = op.id, formatVersion = 1, raid = RAID, env = "staging", practice = true,
        boss = "lb_lucifron", item = 16805, char = "Ana Vale", user = "u_ana", method = "HR", roll = 91,
        sender = "Rae Quill", at = 1792000000,
      }, op)
      assert.are.same({
        key = op.id, raid = RAID, env = "staging", practice = true, boss = "lb_lucifron", item = 16805,
        char = "Ana Vale", user = "u_ana", method = "HR", roll = 91, sender = "Rae Quill",
        at = 1792000000, state = "announced", stateAt = 1792000000,
      }, ns.Raids.Awards(RAID)[1])
      assert.are.same({ op }, Records.Ops(RAID))
    end)

    it("stores a sender given as Name-Realm as Name", function()
      selectRaid()
      wow.state.player = "Rae Quill-Forever"
      local own = Records.Award(ana())
      local given = Records.Award(ana({ sender = "Bo Marsh-Forever" }))
      assert.are.same({ "Rae Quill", "Bo Marsh" }, { own.sender, given.sender })
      assert.are.equal("Bo Marsh", Records.Get(given.id).sender)
    end)

    it("makes a new valid id for every operation", function()
      selectRaid()
      local seen = {}
      for _ = 1, 50 do
        local op = Records.Award(ana())
        assert.is_truthy(op.id:match("^aw%-" .. ("[a-z0-9]"):rep(8) .. "$"))
        assert.is_nil(seen[op.id])
        seen[op.id] = true
      end
    end)

    it("checks ids: 8 to 128 letters, digits, _ or -", function()
      assert.is_true(Records.ValidId("aw-7f3k2m9q"))
      assert.is_true(Records.ValidId("A_b-1234"))
      assert.is_false(Records.ValidId("aw-7f3k"))
      assert.is_false(Records.ValidId(("a"):rep(129)))
      assert.is_false(Records.ValidId("aw 7f3k2m9q"))
      selectRaid()
      assert.are.same({ nil, "bad id" }, { Records.Award(ana({ id = "short" })) })
      assert.are.same({ nil, "too long" }, { Records.Award(ana({ note = ("x"):rep(201) })) })
      assert.are.same({}, Records.Ops(RAID))
    end)

    it("replays the same operation and keeps the first of two payloads under one id", function()
      selectRaid()
      Records.Award(ana({ id = "aw-7f3k2m9q" }))
      assert.are.equal("replayed", select(2, Records.Award(ana({ id = "aw-7f3k2m9q" }))))
      -- Times aren't part of the payload (spec 4.2).
      local later = ana({ id = "aw-7f3k2m9q", at = 1792000099 })
      assert.are.equal("replayed", select(2, Records.Award(later)))
      assert.are.same({ nil, "key-conflict" },
        { Records.Award(ana({ id = "aw-7f3k2m9q", char = "Bo Marsh" })) })
      assert.are.equal(1, #ns.Raids.Awards(RAID))
      assert.are.equal("Ana Vale", Records.Get("aw-7f3k2m9q").char)
    end)
  end)

  describe("life cycle", function()
    local key

    before_each(function()
      selectRaid()
      key = Records.Award(ana()).id
    end)

    local function state() return Records.Get(key).state end

    it("confirms, or not, with the later at winning and a tie going to confirmed", function()
      local op, outcome = Records.Confirm(key, { at = 1792000010 })
      assert.are.same({ "recorded", "confirm", key, RAID, "staging" },
        { outcome, op.type, op.key, op.raid, op.env })
      assert.are.equal("confirmed", state())
      Records.NotConfirmed(key, { at = 1792000005 })
      assert.are.equal("confirmed", state())
      Records.NotConfirmed(key, { at = 1792000020 })
      assert.are.equal("not-confirmed", state())
      Records.Confirm(key, { at = 1792000020 })
      assert.are.equal("confirmed", state())
      Records.NotConfirmed(key, { at = 1792000020 })
      assert.are.equal("confirmed", state())
    end)

    it("voids from any state, keeps the award on the record, and a void always wins", function()
      Records.NotConfirmed(key)
      local op = Records.Void(key, { reason = "wrong winner" })
      assert.are.same({ "void", "wrong winner" }, { op.type, op.reason })
      Records.Void(key, { reason = "second" })
      Records.Confirm(key, { at = 1792000100 })
      local award = Records.Get(key)
      assert.are.same({ true, "wrong winner", 1792000000, "confirmed" },
        { award.voided, award.voidReason, award.voidedAt, award.state })
      assert.are.equal(1, #ns.Raids.Awards(RAID))
    end)

    it("replaces: voids the old key and records a new award with a new key that names it", function()
      Records.Confirm(key)
      local op, outcome = Records.Replace(key, { boss = "lb_lucifron", item = 16805, char = "Bo Marsh",
        user = "u_bo", method = "SR", roll = 77 })
      assert.are.equal("recorded", outcome)
      assert.are.same({ "replace", key, "award", RAID, "staging", "Rae Quill" },
        { op.type, op.key, op.award.type, op.award.raid, op.award.env, op.award.sender })
      assert.are_not.equal(op.id, op.award.id)
      assert.are_not.equal(key, op.award.id)
      local old, new = Records.Get(key), Records.Get(op.award.id)
      assert.are.same({ true, op.award.id }, { old.voided, old.replacedBy })
      assert.are.same({ "Bo Marsh", key, "announced" }, { new.char, new.replaces, new.state })
      assert.is_nil(new.voided)
      assert.are.equal(2, #ns.Raids.Awards(RAID))
      assert.are.equal(3, #Records.Ops(RAID))
    end)

    it("refuses a replacement that reuses a key, changing nothing", function()
      local other = Records.Award(ana({ char = "Dee Holt" })).id
      local ops = #Records.Ops(RAID)
      for _, id in ipairs({ key, other }) do
        assert.are.same({ nil, "key-conflict" },
          { Records.Replace(key, ana({ id = id, char = "Bo Marsh" })) })
      end
      assert.is_nil(Records.Get(key).voided)
      assert.are.same({ 2, ops }, { #ns.Raids.Awards(RAID), #Records.Ops(RAID) })
    end)

    it("knows a replacement's new award when it arrives again on its own", function()
      local new = ana({ id = "aw-2h6j9z4b", char = "Bo Marsh" })
      Records.Replace(key, new)
      assert.are.equal("replayed", select(2, Records.Award(new)))
      assert.are.same({ nil, "key-conflict" }, { Records.Award(ana({ id = "aw-2h6j9z4b" })) })
      assert.are.equal(2, #ns.Raids.Awards(RAID))
    end)

    it("takes a replacement whose new award arrived first", function()
      local new = ana({ id = "aw-2h6j9z4b", char = "Bo Marsh" })
      Records.Award(new)
      assert.are.equal("recorded", select(2, Records.Replace(key, new)))
      assert.are.same({ true, "aw-2h6j9z4b" }, { Records.Get(key).voided, Records.Get(key).replacedBy })
      assert.are.equal(2, #ns.Raids.Awards(RAID))
    end)

    it("gives a replacement the replaced award's practice mark", function()
      local practiceKey = Records.Award(ana({ practice = true })).id
      local op = Records.Replace(practiceKey, ana({ char = "Bo Marsh" }))
      assert.are.same({ true, true }, { op.practice, op.award.practice })
      assert.is_true(Records.Get(op.award.id).practice)
      assert.is_true(Records.Void(practiceKey).practice)
    end)
  end)

  describe("an operation naming a key not held yet", function()
    before_each(function() selectRaid() end)

    it("keeps a void until the award arrives, which is then recorded void", function()
      local _, outcome = Records.Void("aw-7f3k2m9q", { reason = "wrong winner" })
      assert.are.equal("pending", outcome)
      assert.is_nil(Records.Get("aw-7f3k2m9q"))
      assert.are.equal("recorded", select(2, Records.Award(ana({ id = "aw-7f3k2m9q" }))))
      local award = Records.Get("aw-7f3k2m9q")
      assert.are.same({ true, "wrong winner" }, { award.voided, award.voidReason })
    end)

    it("keeps confirm and not-confirmed until the award arrives", function()
      assert.are.equal("pending", select(2, Records.NotConfirmed("aw-7f3k2m9q", { at = 1792000030 })))
      assert.are.equal("pending", select(2, Records.Confirm("aw-7f3k2m9q", { at = 1792000010 })))
      Records.Award(ana({ id = "aw-7f3k2m9q" }))
      assert.are.equal("not-confirmed", Records.Get("aw-7f3k2m9q").state)
    end)

    it("keeps a replace, recording the new award when the original arrives", function()
      local op = Records.Replace("aw-7f3k2m9q", ana({ char = "Bo Marsh" }))
      assert.is_nil(Records.Get(op.award.id))
      Records.Award(ana({ id = "aw-7f3k2m9q" }))
      assert.is_true(Records.Get("aw-7f3k2m9q").voided)
      assert.are.equal("aw-7f3k2m9q", Records.Get(op.award.id).replaces)
    end)
  end)

  describe("no raid", function()
    local function assertNoRaid(op)
      assert.are.same({ nil, nil }, { op.raid, op.env })
      assert.are.same({ op.id }, { ns.Raids.NoRaidAwards()[1].key })
      assert.is_nil(ns.Raids.NoRaidAwards()[1].raid)
      assert.are.same({ op }, Records.Ops(nil))
      assert.is_nil(ns.db.awards)
    end

    it("holds an award as no raid when no raid is selected", function()
      ns.Raids.Load(snapshot(ns, RAID), "inbox")
      assertNoRaid(Records.Award(ana()))
    end)

    it("holds an award as no raid when the chosen raid isn't loaded yet", function()
      assert.is_true(ns.Selection.Apply("SA0001", 1792000000, "Bo Marsh"))
      assert.are.equal("chosen", ns.Selection.ActiveBy())
      assertNoRaid(Records.Award(ana()))
    end)

    it("attaches to the loaded raid, taking its raid id and env and keeping the keys", function()
      local award = Records.Award(ana())
      local confirm = Records.Confirm(award.id)
      local void = Records.Void("aw-7f3k2m9q")
      assert.are.same({ nil, "not loaded" }, { Records.Attach() })

      selectRaid(RAID, { env = "production", code = "PA0001" })
      Records.Award(ana({ id = "aw-7f3k2m9q" }))
      assert.is_nil(Records.Get("aw-7f3k2m9q").voided)
      assert.are.equal(1, Records.Attach())

      local attached, raidId = Records.Get(award.id)
      assert.are.same({ RAID, RAID, "production", "confirmed" },
        { raidId, attached.raid, attached.env, attached.state })
      assert.are.same({ RAID, "production" }, { confirm.raid, confirm.env })
      assert.are.equal(4, #Records.Ops(RAID))
      assert.is_true(Records.Get("aw-7f3k2m9q").voided)
      assert.are.same({}, ns.Raids.NoRaidAwards())
      assert.are.same({}, Records.Ops(nil))
      assert.are.same({ RAID, "production" }, { void.raid, void.env })
    end)
  end)

  describe("not a guild run", function()
    local key, before

    before_each(function()
      selectRaid()
      key = Records.Award(ana()).id
      ns.Selection.ChooseOff()
      before = copy(ns.db)
    end)

    it("records no new award, confirmation or attach, not even as no raid", function()
      local results = {
        { Records.Award(ana()) }, { Records.Confirm(key) }, { Records.NotConfirmed(key) },
        { Records.Void("aw-7f3k2m9q") }, { Records.Replace("aw-7f3k2m9q", ana()) },
        { Records.Attach(RAID) },
      }
      for _, result in ipairs(results) do assert.are.same({ nil, "quiet" }, result) end
      assert.are.same(before, ns.db)
      assert.is_nil(ns.db.noRaid)
      assert.is_nil(ns.db.noRaidOps)
    end)

    it("still voids and replaces an award made earlier (Robert, #7, 2026-10-15)", function()
      local void, outcome = Records.Void(key, { reason = "wrong winner" })
      assert.are.same({ "recorded", RAID }, { outcome, void.raid })
      local replace = Records.Replace(key, ana({ char = "Bo Marsh" }))
      local new, raidId = Records.Get(replace.award.id)
      assert.are.same({ RAID, "staging", key }, { raidId, new.env, new.replaces })
      assert.is_true(Records.Get(key).voided)
      assert.is_nil(ns.db.noRaid)
    end)
  end)

  it("keeps records through a save and reload", function()
    selectRaid()
    local key = Records.Award(ana()).id
    Records.Confirm(key)
    Records.Void("aw-7f3k2m9q")
    local before = copy(ns.db)

    ns = wow.start({ saved = { BureaucracyForeverDB = copy(BureaucracyForeverDB) } })
    assert.are.same(before.awards, ns.db.awards)
    assert.are.same(before.ops, ns.db.ops)
    assert.are.equal("confirmed", ns.Records.Get(key).state)
    -- The pending void still applies after the reload.
    ns.Records.Award(ana({ id = "aw-7f3k2m9q" }))
    assert.is_true(ns.Records.Get("aw-7f3k2m9q").voided)
  end)
  describe("merging the site's catch-up", function()
    local T = 1792000000

    -- A catch-up award (spec 3.4): Ana's HR award by default; fields override.
    local function site(key, fields)
      local a = { key = key, boss = "lb_lucifron", item = 16805, char = "Ana Vale", user = "u_ana",
        method = "HR", roll = 91, voided = false, state = "confirmed", at = T }
      for k, v in pairs(fields or {}) do a[k] = v end
      return a
    end

    local function catchup(awards, voids)
      return { formatVersion = 1, raid = RAID, env = "staging", generated = T,
        awards = awards or {}, voids = voids or {} }
    end

    local function merge(awards, voids)
      return Records.Merge(catchup(awards, voids))
    end

    before_each(function() selectRaid() end)

    it("adds the awards it doesn't hold in their state, with no operation; again changes nothing", function()
      local awards = {
        site("site-key-0001"),
        site("site-key-0002", { state = "manual", at = T + 5, practice = true }),
        site("site-key-0003", { voided = true, state = "not-confirmed", method = "DISENCHANT_BANK" }),
      }
      awards[3].char, awards[3].user = nil, nil
      assert.are.same({}, merge(awards))
      assert.are.same({
        key = "site-key-0001", raid = RAID, env = "staging", boss = "lb_lucifron", item = 16805,
        char = "Ana Vale", user = "u_ana", method = "HR", roll = 91, at = T, state = "confirmed",
        stateAt = T,
      }, Records.Get("site-key-0001"))
      local manual = Records.Get("site-key-0002")
      assert.are.same({ "manual", T + 5, true }, { manual.state, manual.stateAt, manual.practice })
      local voided = Records.Get("site-key-0003")
      assert.are.same({ true, "not-confirmed" }, { voided.voided, voided.state })
      assert.are.same({}, Records.Ops(RAID))
      local before = copy(ns.db)
      assert.are.same({}, merge(awards))
      assert.are.same(before, ns.db)
    end)

    it("counts a manual award for spending like any other", function()
      merge({ site("site-key-0001", { state = "manual" }) })
      local resolved = ns.Rules.Resolve({ item = 16805, awards = ns.Raids.Awards(RAID),
        reserves = { [16805] = { { user = "u_ana", char = "Ana Vale", kind = "HR", trial = false } } } })
      assert.are.same({ "open", ns.Rules.RECEIVED }, { resolved.mode, resolved.skipped[1].reason })
    end)

    it("keeps a void for an award it doesn't hold pending, until the award arrives", function()
      merge({}, { { key = "site-key-0001", reason = "wrong winner", at = T + 1 } })
      assert.is_nil(Records.Get("site-key-0001"))
      assert.are.same({}, Records.Ops(RAID))
      merge({ site("site-key-0001") })
      local award = Records.Get("site-key-0001")
      assert.are.same({ true, "wrong winner", T + 1 }, { award.voided, award.voidReason, award.voidedAt })
      -- An award from another officer (sync) takes a pending void the same way.
      merge({}, { { key = "aw-7f3k2m9q", at = T + 2 } })
      Records.Award(ana({ id = "aw-7f3k2m9q" }))
      assert.is_true(Records.Get("aw-7f3k2m9q").voided)
    end)

    it("saves a pending void in siteVoids, with its raid and environment, and nowhere else", function()
      merge({}, {
        { key = "site-key-0001", reason = "wrong winner", at = T + 1 },
        { key = "site-key-0002", at = T + 2 },
      })
      assert.are.same({
        ["site-key-0001"] = { raid = RAID, env = "staging", reason = "wrong winner", at = T + 1 },
        ["site-key-0002"] = { raid = RAID, env = "staging", at = T + 2 },
      }, ns.db.siteVoids)
      assert.are.same({}, Records.Ops(RAID))
      assert.is_nil(ns.db.noRaidOps)
      assert.is_nil(ns.Sync.CopyOut(RAID))
      Records.Award(ana())
      assert.is_nil(ns.Sync.CopyOut(RAID):find("site%-key%-000"))
    end)

    -- An award from another officer is Records.Award with its id (sync's receive path, #20).
    it("survives a reload and applies when another officer's award arrives, the raid not in the inbox",
      function()
      merge({}, { { key = "aw-7f3k2m9q", reason = "wrong winner", at = T + 1 } })
      ns = wow.start({ saved = { BureaucracyForeverDB = copy(BureaucracyForeverDB) } })
      Records = ns.Records
      assert.is_not_nil(ns.db.siteVoids["aw-7f3k2m9q"])
      ns.Raids.Load(snapshot(ns, RAID), "pasted")
      assert.is_true(ns.Selection.ChooseRaid(RAID, true))
      Records.Award(ana({ id = "aw-7f3k2m9q" }))
      local award = Records.Get("aw-7f3k2m9q")
      assert.are.same({ true, "wrong winner", T + 1 }, { award.voided, award.voidReason, award.voidedAt })
      assert.is_nil(ns.db.siteVoids["aw-7f3k2m9q"])
    end)

    it("loads saved data from before the field as no pending voids", function()
      local saved = copy(BureaucracyForeverDB)
      saved.siteVoids = nil
      ns = wow.start({ saved = { BureaucracyForeverDB = saved } })
      assert.is_nil(ns.db.siteVoids)
      assert.has_no.errors(function() ns.Records.Award(ana()) end)
    end)

    it("leaves the entry when the award has another raid or environment, or no raid", function()
      local other = catchup({}, { { key = "aw-7f3k2m9q", at = T + 1 } })
      other.raid = "cm9xr2k4a0002"
      Records.Merge(other)
      Records.Award(ana({ id = "aw-7f3k2m9q" }))
      assert.is_nil(Records.Get("aw-7f3k2m9q").voided)
      assert.is_not_nil(ns.db.siteVoids["aw-7f3k2m9q"])
      other = catchup({}, { { key = "aw-3q9k2m7f", at = T + 1 } })
      other.env = "production"
      Records.Merge(other)
      Records.Award(ana({ id = "aw-3q9k2m7f" }))
      assert.is_nil(Records.Get("aw-3q9k2m7f").voided)
      assert.is_not_nil(ns.db.siteVoids["aw-3q9k2m7f"])
      merge({}, { { key = "aw-9k2m7f3q", at = T + 1 } })
      ns.db.activeRaid = nil
      Records.Award(ana({ id = "aw-9k2m7f3q" }))
      assert.is_nil(Records.Get("aw-9k2m7f3q").voided)
      assert.is_not_nil(ns.db.siteVoids["aw-9k2m7f3q"])
    end)

    it("doesn't store a void whose award is held or already voided", function()
      local key = Records.Award(ana()).id
      Records.Void(key)
      merge({}, { { key = key, at = T + 1 } })
      merge({ site("site-key-0001") }, { { key = "site-key-0001", at = T + 1 } })
      assert.is_nil(ns.db.siteVoids)
      assert.is_true(Records.Get("site-key-0001").voided)
    end)

    it("applies a void the site holds pending to an award held", function()
      local key = Records.Award(ana()).id
      merge({}, { { key = key, at = T + 1 } })
      assert.are.same({ true, T + 1 }, { Records.Get(key).voided, Records.Get(key).voidedAt })
      assert.are.equal(1, #Records.Ops(RAID))
    end)

    it("applies an officer's operation waiting for the award when the catch-up brings it", function()
      Records.Void("site-key-0001", { reason = "mine" })
      merge({ site("site-key-0001") })
      assert.are.same({ true, "mine" }, { Records.Get("site-key-0001").voided,
        Records.Get("site-key-0001").voidReason })
    end)

    it("voids a held award voided on either side, keeping its state", function()
      local key = Records.Award(ana()).id
      Records.Confirm(key)
      merge({ site(key, { voided = true, state = "announced" }) })
      assert.are.same({ true, "confirmed" }, { Records.Get(key).voided, Records.Get(key).state })

      local other = Records.Award(ana()).id
      Records.Void(other)
      merge({ site(other, { at = T + 50 }) })
      assert.are.same({ true, "announced" }, { Records.Get(other).voided, Records.Get(other).state })
    end)

    it("advances a held announced award with the site's confirmation", function()
      local key = Records.Award(ana()).id
      merge({ site(key, { at = T + 10 }) })
      assert.are.same({ "confirmed", T + 10 }, { Records.Get(key).state, Records.Get(key).stateAt })
      assert.are.equal(1, #Records.Ops(RAID))
    end)

    it("takes the later at, a tie going to confirmed", function()
      local key = Records.Award(ana()).id
      Records.Confirm(key, { at = T + 10 })
      merge({ site(key, { state = "not-confirmed", at = T + 5 }) })
      assert.are.equal("confirmed", Records.Get(key).state)
      merge({ site(key, { state = "not-confirmed", at = T + 10 }) })
      assert.are.equal("confirmed", Records.Get(key).state)
      merge({ site(key, { state = "not-confirmed", at = T + 20 }) })
      assert.are.same({ "not-confirmed", T + 20 }, { Records.Get(key).state, Records.Get(key).stateAt })
      merge({ site(key, { state = "confirmed", at = T + 20 }) })
      assert.are.equal("confirmed", Records.Get(key).state)
    end)

    it("never lets announced or manual replace confirmed or not confirmed", function()
      local key = Records.Award(ana()).id
      Records.NotConfirmed(key, { at = T + 10 })
      merge({ site(key, { state = "announced", at = T + 99 }), site(key, { state = "manual", at = T + 99 }) })
      assert.are.same({ "not-confirmed", T + 10 }, { Records.Get(key).state, Records.Get(key).stateAt })
    end)

    it("lets the game's confirmation advance a manual award", function()
      merge({ site("site-key-0001", { state = "manual", at = T + 10 }) })
      Records.Confirm("site-key-0001", { at = T + 5 })
      assert.are.equal("confirmed", Records.Get("site-key-0001").state)
    end)

    it("keeps its own award on a conflicting field and returns the conflict", function()
      local key = Records.Award(ana()).id
      local before = copy(ns.db)
      local conflicts = merge({ site(key, { char = "Bo Marsh", item = 17000, voided = true }) })
      assert.are.same({ { "item", "char" }, key }, { conflicts[1].fields, conflicts[1].award.key })
      assert.are.equal(1, #conflicts)
      assert.are.same(before, ns.db)
    end)

    it("never records an award from the catch-up twice when an officer's copy arrives", function()
      merge({ site("site-key-0001", { voided = true }) })
      local before = copy(ns.db)
      assert.are.equal("replayed", select(2, Records.Award(ana({ id = "site-key-0001" }))))
      assert.are.same({ nil, "key-conflict" }, { Records.Award(ana({ id = "site-key-0001", item = 17000 })) })
      local replace = Records.Replace(Records.Award(ana()).id, ana({ id = "site-key-0001" }))
      assert.is_truthy(replace)
      assert.are.same(before.awards[RAID][1], Records.Get("site-key-0001"))
      assert.are.equal(2, #ns.Raids.Awards(RAID))
    end)

    it("merges into an award held as no raid instead of adding it twice", function()
      ns.db.activeRaid = nil
      local key = Records.Award(ana()).id
      merge({ site(key) })
      assert.are.same({ "confirmed", 0 }, { Records.Get(key).state, #ns.Raids.Awards(RAID) })
    end)

    it("deletes nothing the catch-up leaves out", function()
      local key = Records.Award(ana()).id
      local before = copy(ns.db)
      merge({})
      assert.are.same(before, ns.db)
      assert.is_truthy(Records.Get(key))
    end)

    it("merges nothing on a run that is not a guild run", function()
      assert.is_true(ns.Selection.ChooseOff())
      local before = copy(ns.db)
      local result = { merge({ site("site-key-0001") }, { { key = "aw-7f3k2m9q", at = T } }) }
      assert.are.same({ nil, "quiet" }, result)
      assert.are.same(before, ns.db)
      assert.is_true(ns.Selection.ChooseRaid(RAID, true))
      Records.Award(ana({ id = "aw-7f3k2m9q" }))
      assert.is_nil(Records.Get("aw-7f3k2m9q").voided)
    end)
  end)
end)
