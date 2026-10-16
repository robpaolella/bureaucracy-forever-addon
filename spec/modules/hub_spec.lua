local wow = require("spec.support.wow")

local RAID, OTHER = "cm9xr2k4a0001", "cm9xr2k4a0002"
local ZOE, BO = "Zoé Brûlé", "Bo Marsh"

local function snapshot(id)
  return {
    formatVersion = 1, raid = id, code = "S" .. id:sub(-5):upper(), env = "staging",
    name = "Molten Core", startsAt = 1792000000, durationMin = 240, generated = 1791990000,
    addon = { version = "0.1.0", url = "https://example.invalid/addon" },
    bosses = {}, reserves = {}, awards = {},
  }
end

-- Spec 10.5's worked example: Zoé Brûlé replaces award aw-9d2f6h1j, in two messages.
local EXAMPLE = {
  "O;k4m8q2;1/2;SA0001;Zoé Brûlé;R;rp-3n7b5x0c;aw-9d2f6h1j;1792001300;;aw-6k1m4v8z;" ..
    "cm9xr2lb30007k1x8q5t2n4pa;16805;Bo Marsh;cm9xr2u900042k1x8q5t2n4pa;SR;77;" ..
    "Traded after the roll%3B Zoé was awa",
  "O;k4m8q2;2/2;SA0001;Zoé Brûlé;y from the keyboard and Bo was next in line.;Zoé Brûlé;1792001300",
}

describe("Hub", function()
  local ns, Records, Sync, requests

  local function receive(body, sender, prefix)
    wow.fire("CHAT_MSG_ADDON", prefix or "BFLOOT1", body, "RAID", sender or ZOE)
  end

  local function award(fields)
    local op = { type = "award", id = "aw-9d2f6h1j", boss = "lb_lucifron", item = 16805,
      char = "Ana Vale", user = "u_ana", method = "HR", roll = 91, sender = ZOE, at = 1792001200 }
    for k, v in pairs(fields or {}) do op[k] = v end
    return op
  end

  -- Sends an operation as O messages, as officer author's add-on would.
  local function send(op, code, author, sender)
    for _, body in ipairs(Sync.EncodeOp(op, code or "SA0001", author or ZOE)) do
      receive(body, sender or author)
    end
  end

  local function logged(text)
    for _, entry in ipairs(ns.log) do
      if entry.text:find(text, 1, true) then return true end
    end
    return false
  end

  before_each(function()
    ns = wow.start()
    Records, Sync = ns.Records, ns.Sync
    wow.state.player = "Rae Quill"
    wow.state.group, wow.state.groupIsRaid = { "Rae Quill", ZOE, BO }, true
    ns.Raids.Load(assert(ns.Snapshot.Validate(snapshot(RAID), "0.1.0")), "pasted")
    assert.is_true(ns.Selection.ChooseRaid(RAID, true))
    requests = {}
    ns.Hub.sendRequest = function(target, body) requests[#requests + 1] = { target, body } end
  end)

  it("registers BFLOOT1 to BFLOOT5", function()
    assert.are.same({ "BFLOOT1", "BFLOOT2", "BFLOOT3", "BFLOOT4", "BFLOOT5" }, wow.prefixes)
  end)

  it("applies spec 10.5's worked example once both messages have arrived", function()
    send(award())
    receive(EXAMPLE[1])
    assert.is_nil(Records.Get("aw-6k1m4v8z"))
    receive(EXAMPLE[2])
    local new = assert(Records.Get("aw-6k1m4v8z"))
    assert.are.same({ BO, ZOE, "aw-9d2f6h1j", RAID }, { new.char, new.sender, new.replaces, new.raid })
    assert.are.equal("Traded after the roll; Zoé was away from the keyboard and Bo was next in line.",
      new.note)
    assert.is_true(Records.Get("aw-9d2f6h1j").voided)
    assert.are.same({}, wow.printed)
  end)

  it("reassembles chunks out of order", function()
    send(award())
    receive(EXAMPLE[2])
    receive(EXAMPLE[1])
    assert.is_truthy(Records.Get("aw-6k1m4v8z"))
  end)

  it("changes nothing for a repeated chunk, before or after the message is whole", function()
    send(award())
    receive(EXAMPLE[1])
    receive(EXAMPLE[1])
    receive(EXAMPLE[2])
    receive(EXAMPLE[2])
    assert.are.equal(2, #Records.Ops(RAID))
    wow.advance(40)
    assert.are.same({}, requests)
  end)

  it("applies a different operation sent under a finished message's msgid", function()
    receive("O;aaaaaa;1/1;SA0001;Zoé Brûlé;" .. ns.OpText.Encode(award()))
    receive("O;aaaaaa;1/1;SA0001;Zoé Brûlé;" .. ns.OpText.Encode(award({ char = "Dee Holt" })))
    assert.are.equal("Ana Vale", Records.Get("aw-9d2f6h1j").char)
    assert.are.equal(1, #wow.printed)
    receive("O;aaaaaa;1/1;SA0001;Zoé Brûlé;" .. ns.OpText.Encode(award({ id = "aw-second01" })))
    assert.is_truthy(Records.Get("aw-second01"))
  end)

  it("asks for a missing chunk at 10, 20 and 30 seconds, then drops the message at 40", function()
    receive(EXAMPLE[1])
    wow.advance(9)
    assert.are.same({}, requests)
    wow.advance(1)
    assert.are.same({ { ZOE, "Q;k4m8q2;2" } }, requests)
    wow.advance(10)
    wow.advance(10)
    assert.are.equal(3, #requests)
    assert.is_false(logged("dropped Zoé Brûlé's message k4m8q2"))
    wow.advance(10)
    assert.are.equal(3, #requests)
    assert.is_true(logged("dropped Zoé Brûlé's message k4m8q2 (chunks still missing)"))
    receive(EXAMPLE[2])
    assert.is_nil(Records.Get("aw-6k1m4v8z"))
    assert.are.same({}, wow.printed)
  end)

  it("logs a resend request while nothing is connected to send it", function()
    ns.Hub.sendRequest = nil
    receive(EXAMPLE[1])
    wow.advance(10)
    assert.is_true(logged("Q;k4m8q2;2"))
  end)

  it("drops and logs a sender's oldest incomplete message when a fifth starts", function()
    local ids = { "aaaaa1", "aaaaa2", "aaaaa3", "aaaaa4", "aaaaa5" }
    for _, msgid in ipairs(ids) do receive("O;" .. msgid .. ";1/2;SA0001;Zoé Brûlé;K;x") end
    assert.is_true(logged("dropped Zoé Brûlé's message aaaaa1 (too many incomplete)"))
    assert.is_false(logged("message aaaaa2"))
    wow.advance(10)
    local asked = {}
    for _, request in ipairs(requests) do asked[#asked + 1] = request[2] end
    table.sort(asked)
    assert.are.same({ "Q;aaaaa2;2", "Q;aaaaa3;2", "Q;aaaaa4;2", "Q;aaaaa5;2" }, asked)
    assert.are.same({}, wow.printed)
  end)

  describe("doesn't apply, and logs without a chat line,", function()
    local cases = {
      ["a malformed message"] = function() receive("O;k4m8q2;1/1;SA0001") end,
      ["a malformed operation"] = function() receive("O;k4m8q2;1/1;SA0001;Zoé Brûlé;X;aw-9d2f6h1j") end,
      ["a sender outside the group"] = function() send(award(), nil, "Stranger") end,
      ["a raid not loaded"] = function() send(award(), "SZZZZZ") end,
      ["an author who isn't the sender"] = function() send(award(), nil, ZOE, BO) end,
      ["a type with no handler yet"] = function() receive("P;SA0001;x") end,
    }
    for name, act in pairs(cases) do
      it(name, function()
        local before = #ns.log
        act()
        assert.is_nil(Records.Get("aw-9d2f6h1j"))
        assert.are.equal(before + 1, #ns.log)
        assert.are.same({}, wow.printed)
      end)
    end
  end)

  it("accepts a sender named with a realm, and a member of a party", function()
    send(award(), nil, ZOE, ZOE .. "-Realm")
    assert.is_truthy(Records.Get("aw-9d2f6h1j"))
    wow.state.groupIsRaid = false
    send(award({ id = "aw-partyaw1", sender = BO }), nil, BO)
    assert.is_truthy(Records.Get("aw-partyaw1"))
  end)

  it("ignores its own messages echoed by the group", function()
    send(award({ sender = "Rae Quill" }), nil, "Rae Quill")
    assert.is_nil(Records.Get("aw-9d2f6h1j"))
    assert.are.same({}, ns.log)
  end)

  it("ignores a higher prefix with one update notice per number", function()
    receive(EXAMPLE[1], nil, "BFLOOT2")
    receive(EXAMPLE[2], nil, "BFLOOT2")
    receive(EXAMPLE[1], nil, "BFLOOT3")
    assert.are.equal(2, #wow.printed)
    assert.is_truthy(wow.printed[1]:find("update Bureaucracy Forever", 1, true))
    assert.is_truthy(wow.printed[2]:find("sync version 3", 1, true))
    wow.advance(40)
    assert.are.same({}, requests)
  end)

  it("records no new award while not a guild run, and logs it", function()
    ns.Selection.ChooseOff()
    send(award())
    assert.is_nil(Records.Get("aw-9d2f6h1j"))
    assert.is_true(logged("(quiet)"))
    assert.are.same({}, wow.printed)
  end)

  it("keeps the first of two awards with one id and prints one chat line naming it", function()
    send(award())
    send(award({ char = "Dee Holt" }))
    assert.are.equal("Ana Vale", Records.Get("aw-9d2f6h1j").char)
    assert.are.equal(1, #wow.printed)
    assert.is_truthy(wow.printed[1]:find("Ana Vale's item 16805 (aw-9d2f6h1j)", 1, true))
  end)

  it("applies an operation for a loaded raid that isn't selected to its own raid", function()
    ns.Raids.Load(assert(ns.Snapshot.Validate(snapshot(OTHER), "0.1.0")), "pasted")
    send(award(), "SA0002")
    assert.are.equal(OTHER, select(2, Records.Get("aw-9d2f6h1j")))
    assert.are.equal(1, #Records.Ops(OTHER))
    assert.are.same({}, Records.Ops(RAID))
  end)

  it("logs and doesn't apply a code two loaded raids share", function()
    local twin = snapshot(OTHER)
    twin.code = "SA0001"
    ns.Raids.Load(assert(ns.Snapshot.Validate(twin, "0.1.0")), "pasted")
    send(award())
    assert.is_nil(Records.Get("aw-9d2f6h1j"))
    assert.is_true(logged("Two loaded raids"))
  end)

  it("applies every operation type through Records, with the message's sender", function()
    local calls = {}
    for _, name in ipairs({ "Award", "Confirm", "NotConfirmed", "Void", "Replace" }) do
      local real = Records[name]
      Records[name] = function(...)
        calls[#calls + 1] = name
        return real(...)
      end
    end
    send(award({ sender = "Somebody Else" }))
    send({ type = "confirm", id = "cf-1x8p4d2s", key = "aw-9d2f6h1j", at = 1792001204 })
    send({ type = "not-confirmed", id = "nc-1x8p4d2s", key = "aw-9d2f6h1j", at = 1792001205 })
    send(award({ id = "aw-8d3c5n2a" }), nil, BO)
    send({ type = "void", id = "vd-5b2n8c1w", key = "aw-8d3c5n2a", reason = "wrong winner",
      at = 1792001260 }, nil, BO)
    receive(EXAMPLE[1])
    receive(EXAMPLE[2])
    assert.are.same({ "Award", "Confirm", "NotConfirmed", "Award", "Void", "Replace" }, calls)
    local ops = Records.Ops(RAID)
    assert.are.same({ "award", "confirm", "not-confirmed", "award", "void", "replace" },
      { ops[1].type, ops[2].type, ops[3].type, ops[4].type, ops[5].type, ops[6].type })
    assert.are.same({ ZOE, BO, ZOE }, { ops[1].sender, ops[4].sender, ops[6].award.sender })
    assert.are.same({ 1792001204, "wrong winner" }, { ops[2].at, ops[5].reason })
    assert.are.equal("not-confirmed", Records.Get("aw-9d2f6h1j").state)
    assert.is_true(Records.Get("aw-8d3c5n2a").voided)
  end)

  describe("a resend request", function()
    it("goes to the connected listener with the sender, msgid and chunks", function()
      local got
      ns.Hub.onRequest = function(...) got = { ... } end
      receive("Q;k4m8q2;1,3", BO)
      assert.are.same({ BO, "k4m8q2", { 1, 3 } }, got)
    end)

    it("is logged while nothing is connected", function()
      receive("Q;k4m8q2;2", BO)
      assert.is_true(logged("Bo Marsh asked again for k4m8q2"))
    end)

    it("is logged and dropped when malformed", function()
      local got
      ns.Hub.onRequest = function() got = true end
      for _, body in ipairs({ "Q;k4m8q2;", "Q;k4m8q2;0", "Q;k4m8q2;1,,2", "Q;K4M8Q2;1", "Q;k4m8q2;1," }) do
        receive(body, BO)
      end
      assert.is_nil(got)
      assert.are.equal(5, #ns.log)
      assert.are.same({}, wow.printed)
    end)
  end)
end)
