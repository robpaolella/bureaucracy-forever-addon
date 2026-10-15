local wow = require("spec.support.wow")

local RAID = "cm9xr2k4a0001"

local function snapshot(id)
  return {
    formatVersion = 1, raid = id, code = "S" .. id:sub(-5):upper(), env = "staging",
    name = "Molten Core", startsAt = 1792000000, durationMin = 240, generated = 1791990000,
    addon = { version = "0.1.0", url = "https://example.invalid/addon" },
    bosses = {}, reserves = {}, awards = {},
  }
end

describe("Sync.CopyOut", function()
  local ns, Records

  local function award(fields)
    local f = {
      boss = "lb_lucifron", item = 16805, char = "Ana Vale", user = "u_ana", method = "HR", roll = 91,
    }
    for k, v in pairs(fields or {}) do f[k] = v end
    return Records.Award(f)
  end

  local function lines(text)
    local out = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do out[#out + 1] = line end
    return out
  end

  before_each(function()
    ns = wow.start()
    Records = ns.Records
    wow.state.player = "Rae Quill"
    ns.Raids.Load(assert(ns.Snapshot.Validate(snapshot(RAID), "0.1.0")), "pasted")
    assert.is_true(ns.Selection.ChooseRaid(RAID, true))
  end)

  it("builds the spec's worked example exactly", function()
    award({ id = "aw-7f3k2m9q", at = 1792001200 })
    Records.Confirm("aw-7f3k2m9q", { id = "cf-1x8p4d2s", at = 1792001204 })
    award({ id = "aw-8d3c5n2a", boss = "lb_trash", item = 17011, char = "Dee Holt", user = "u_dee",
      method = "OPEN_ROLL", roll = 64, at = 1792001230 })
    Records.Void("aw-8d3c5n2a", { id = "vd-5b2n8c1w", reason = "wrong winner", at = 1792001260 })
    Records.Replace("aw-7f3k2m9q", { id = "aw-2h6j9z4b", char = "Bo Marsh", user = "u_bo",
      method = "SR", roll = 77, boss = "lb_lucifron", item = 16805, at = 1792001300 },
      { id = "rp-9c4v6t0e", at = 1792001300 })
    local text, count = ns.Sync.CopyOut(RAID)
    assert.are.equal(5, count)
    assert.are.same({
      "BFOUT1;cm9xr2k4a0001;SA0001;staging",
      "A;aw-7f3k2m9q;lb_lucifron;16805;Ana Vale;u_ana;HR;91;;Rae Quill;1792001200;",
      "K;cf-1x8p4d2s;aw-7f3k2m9q;1792001204;",
      "A;aw-8d3c5n2a;lb_trash;17011;Dee Holt;u_dee;OPEN_ROLL;64;;Rae Quill;1792001230;",
      "V;vd-5b2n8c1w;aw-8d3c5n2a;wrong winner;1792001260;",
      "R;rp-9c4v6t0e;aw-7f3k2m9q;1792001300;;aw-2h6j9z4b;" ..
      "lb_lucifron;16805;Bo Marsh;u_bo;SR;77;;Rae Quill;1792001300",
      "E;5",
    }, lines(text))
  end)

  it("refuses the no-raid list, saying why", function()
    local text, reason = ns.Sync.CopyOut(nil)
    assert.is_nil(text)
    assert.is_truthy(reason:find("no raid", 1, true))
  end)

  it("refuses a raid that isn't loaded", function()
    local text, reason = ns.Sync.CopyOut("zzzzzzzzzzzzz")
    assert.is_nil(text)
    assert.is_truthy(reason:find("isn't loaded", 1, true))
  end)

  it("refuses a raid with nothing to copy", function()
    local text, reason = ns.Sync.CopyOut(RAID)
    assert.is_nil(text)
    assert.is_truthy(reason:find("Nothing to copy", 1, true))
  end)

  it("leaves out practice awards and what names them, and doesn't count them", function()
    local practice = award({ id = "aw-practice1", practice = true })
    Records.Confirm(practice.id, { id = "cf-practice1" })
    Records.Replace(practice.id, { id = "aw-practice2", boss = "b", item = 1, char = "X", method = "HR" },
      { id = "rp-practice1" })
    Records.Void("aw-practice2", { id = "vd-practice1" })
    local only = award({ id = "aw-real0001", at = 5 })
    local text, count = ns.Sync.CopyOut(RAID)
    assert.are.equal(1, count)
    assert.are.same({
      "BFOUT1;cm9xr2k4a0001;SA0001;staging",
      "A;" .. only.id .. ";lb_lucifron;16805;Ana Vale;u_ana;HR;91;;Rae Quill;5;",
      "E;1",
    }, lines(text))
  end)

  it("refuses a raid whose only awards are practice", function()
    award({ id = "aw-practice1", practice = true })
    local text, reason = ns.Sync.CopyOut(RAID)
    assert.is_nil(text)
    assert.is_truthy(reason:find("Nothing to copy", 1, true))
  end)

  it("keeps accents, escapes ; % and a newline in a note, writes identical copies as two lines", function()
    award({ id = "aw-copy0001", char = "Zoë", note = "50%; ok\nnext", at = 1 })
    award({ id = "aw-copy0002", char = "Zoë", note = "50%; ok\nnext", at = 1 })
    local text, count = ns.Sync.CopyOut(RAID)
    assert.are.equal(2, count)
    local out = lines(text)
    local tail = ";lb_lucifron;16805;Zoë;u_ana;HR;91;50%25%3B ok%0Anext;Rae Quill;1;"
    assert.are.equal("A;aw-copy0001" .. tail, out[2])
    assert.are.equal("A;aw-copy0002" .. tail, out[3])
    assert.are.equal("E;2", out[4])
  end)
end)
