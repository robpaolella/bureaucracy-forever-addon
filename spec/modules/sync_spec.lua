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

describe("Sync's O messages", function()
  local ns, Sync, OpText

  before_each(function()
    ns = wow.start()
    Sync, OpText = ns.Sync, ns.OpText
  end)

  -- The whole message the game counts: the prefix, a separator and the body.
  local function size(body) return #(Sync.PREFIX .. "\t" .. body) end

  -- Parses every body and decodes the joined pieces, as a receiver holding all chunks would.
  local function receive(bodies)
    local pieces = {}
    for n, body in ipairs(bodies) do
      local chunk = assert(Sync.ParseChunk(body))
      assert.are.same({ n, #bodies }, { chunk.n, chunk.total })
      pieces[n] = chunk.piece
    end
    return assert(OpText.Decode(table.concat(pieces)))
  end

  local example = { type = "replace", id = "rp-3n7b5x0c", key = "aw-9d2f6h1j", at = 1792001300,
    award = { id = "aw-6k1m4v8z", boss = "cm9xr2lb30007k1x8q5t2n4pa", item = 16805, char = "Bo Marsh",
      user = "cm9xr2u900042k1x8q5t2n4pa", method = "SR", roll = 77,
      note = "Traded after the roll; Zoé was away from the keyboard and Bo was next in line.",
      sender = "Zoé Brûlé", at = 1792001300 } }

  it("encodes the spec's worked example (10.5) to exactly its two messages", function()
    local bodies = Sync.EncodeOp(example, "SA0001", "Zoé Brûlé", "k4m8q2")
    assert.are.same({
      "O;k4m8q2;1/2;SA0001;Zoé Brûlé;R;rp-3n7b5x0c;aw-9d2f6h1j;1792001300;;aw-6k1m4v8z;" ..
        "cm9xr2lb30007k1x8q5t2n4pa;16805;Bo Marsh;cm9xr2u900042k1x8q5t2n4pa;SR;77;" ..
        "Traded after the roll%3B Zoé was awa",
      "O;k4m8q2;2/2;SA0001;Zoé Brûlé;y from the keyboard and Bo was next in line.;Zoé Brûlé;1792001300",
    }, bodies)
    assert.are.same({ 201, 109 }, { size(bodies[1]), size(bodies[2]) })
    assert.are.same(example, receive(bodies))
  end)

  it("sends an operation that fits as one chunk, 1/1, and gives it back", function()
    local op = { type = "confirm", id = "cf-1x8p4d2s", key = "aw-7f3k2m9q", at = 5 }
    local bodies = Sync.EncodeOp(op, "SA0001", "Rae Quill", "abc123")
    assert.are.same({ "O;abc123;1/1;SA0001;Rae Quill;K;cf-1x8p4d2s;aw-7f3k2m9q;5;" }, bodies)
    assert.are.same(op, receive(bodies))
  end)

  it("makes a new six-character msgid when none is given", function()
    local chunk = Sync.ParseChunk(Sync.EncodeOp(example, "SA0001", "Zoé Brûlé")[1])
    assert.matches("^[a-z0-9]+$", chunk.msgid)
    assert.are.equal(6, #chunk.msgid)
  end)

  it("cuts a long note of accents and escapes only between characters and escapes", function()
    -- Every offset of the escapes and two- and three-byte characters against the 160-byte cut.
    for shift = 0, 15 do
      local note = string.rep("x", shift) .. string.rep("é;€%ü|", 40)
      local op = { type = "void", id = "vd-5b2n8c1w", key = "aw-8d3c5n2a", reason = note, at = 9,
        practice = true }
      -- A long name: 51 bytes, with the header's other fields at their longest (spec 10.3: 80).
      local name = string.rep("Brûlé", 4) .. " " .. string.rep("Zoë", 5) .. "ab"
      local bodies = Sync.EncodeOp(op, "PZ9Z9Z", name, "zz99zz")
      assert.is_true(#bodies > 2)
      for _, body in ipairs(bodies) do
        local piece = Sync.ParseChunk(body).piece
        assert.is_true(#piece <= 160, "piece of " .. #piece)
        assert.is_true(size(body) < 241, "message of " .. size(body))
        assert.is_true(OpText.ValidUtf8(piece))
        assert.is_nil(piece:find("%%%x?$"), "piece ends inside an escape")
      end
      assert.are.same(op, receive(bodies))
    end
  end)

  it("escapes the raid and author, and gives them back", function()
    local chunk = Sync.ParseChunk(Sync.EncodeOp(example, "SA;001", "Zo|é", "abc123")[1])
    assert.are.same({ "SA;001", "Zo|é" }, { chunk.raid, chunk.author })
  end)

  local malformed = {
    ["another type"] = "Q;k4m8q2;1/2;SA0001;Zoé Brûlé;K;x",
    ["a missing piece"] = "O;k4m8q2;1/2;SA0001;Zoé Brûlé;",
    ["too few fields"] = "O;k4m8q2;1/2;SA0001",
    ["a missing count"] = "O;k4m8q2;SA0001;Zoé Brûlé;K;x",
    ["n of 0"] = "O;k4m8q2;0/2;SA0001;Zoé Brûlé;K;x",
    ["n over N"] = "O;k4m8q2;3/2;SA0001;Zoé Brûlé;K;x",
    ["a negative n"] = "O;k4m8q2;-1/2;SA0001;Zoé Brûlé;K;x",
    ["a msgid too short"] = "O;k4m8q;1/1;SA0001;Zoé Brûlé;K;x",
    ["a msgid too long"] = "O;k4m8q22;1/1;SA0001;Zoé Brûlé;K;x",
    ["a msgid with capitals"] = "O;K4M8Q2;1/1;SA0001;Zoé Brûlé;K;x",
    ["an empty raid"] = "O;k4m8q2;1/1;;Zoé Brûlé;K;x",
    ["an empty author"] = "O;k4m8q2;1/1;SA0001;;K;x",
    ["an author with a bad %"] = "O;k4m8q2;1/1;SA0001;Zo%;K;x",
    ["an author that isn't UTF-8"] = "O;k4m8q2;1/1;SA0001;Zo\233;K;x",
  }

  for name, body in pairs(malformed) do
    it("reports a body with " .. name .. " as malformed", function()
      local chunk, err = Sync.ParseChunk(body)
      assert.is_nil(chunk)
      assert.are.equal("malformed", err)
    end)
  end
end)
