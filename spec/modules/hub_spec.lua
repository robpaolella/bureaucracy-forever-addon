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
    assert.are.equal(2, #Records.Ops(RAID))
    -- A late copy after the message is whole starts a new one; once whole, Records replays it.
    receive(EXAMPLE[2])
    wow.advance(10)
    assert.are.same({ { ZOE, "Q;k4m8q2;1" } }, requests)
    receive(EXAMPLE[1])
    wow.advance(40)
    assert.are.equal(1, #requests)
    assert.are.equal(2, #Records.Ops(RAID))
    assert.are.same({}, wow.printed)
  end)

  -- A two-part award, then another version under the same msgid: part 1 differs, part 2 doesn't.
  for _, order in ipairs({ { 1, 2 }, { 2, 1 } }) do
    it("flags another version of a two-part message under a used msgid, parts in order "
      .. order[1] .. ", " .. order[2], function()
      local note = string.rep("Traded after the roll. ", 8)
      local first = Sync.EncodeOp(award({ note = note }), "SA0001", ZOE, "aaaaaa")
      local second = Sync.EncodeOp(award({ note = note, char = "Dee Holt" }), "SA0001", ZOE, "aaaaaa")
      assert.are.same({ 2, 2 }, { #first, #second })
      assert.are.equal(first[2], second[2])
      assert.are_not.equal(first[1], second[1])
      receive(first[1])
      receive(first[2])
      receive(second[order[1]])
      receive(second[order[2]])
      assert.are.equal("Ana Vale", Records.Get("aw-9d2f6h1j").char)
      assert.are.equal(1, #wow.printed)
      assert.is_truthy(wow.printed[1]:find("Ana Vale's item 16805 (aw-9d2f6h1j)", 1, true))
      wow.advance(40)
      assert.are.same({}, requests)
    end)
  end

  it("applies a different operation sent under a finished message's msgid", function()
    receive("O;aaaaaa;1/1;SA0001;Zoé Brûlé;" .. ns.OpText.Encode(award()))
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
      ["a type with no handler"] = function() receive("Z;SA0001;x") end,
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

  it("credits a forwarded operation to its author and saves the forwarder only as via", function()
    ns.Hub.Apply(award({ sender = "Somebody Else" }), RAID, ZOE, BO)
    ns.Hub.Apply({ type = "void", id = "vd-5b2n8c1w", key = "aw-9d2f6h1j", reason = "wrong winner",
      at = 1792001260 }, RAID, ZOE, BO)
    local held = Records.Get("aw-9d2f6h1j")
    assert.are.same({ ZOE, true }, { held.sender, held.voided })
    assert.are.same({ ["aw-9d2f6h1j"] = BO, ["vd-5b2n8c1w"] = BO }, ns.db.via)
    for _, op in ipairs(Records.Ops(RAID)) do assert.is_nil(op.via) end
    assert.is_nil(assert(Sync.CopyOut(RAID)):find(BO, 1, true))
    -- A direct copy arriving later is the same operation.
    send(award())
    assert.are.equal(2, #Records.Ops(RAID))
    assert.are.same({}, wow.printed)
  end)

  it("saves no via for a direct message", function()
    send(award())
    assert.is_nil(ns.db.via)
  end)

  it("applies an operation forwarded in a catch-up reply, credited to its author, with the forwarder as via",
    function()
      send(award({ sender = ZOE }), nil, ZOE, BO)
      send({ type = "confirm", id = "cf-1x8p4d2s", key = "aw-9d2f6h1j", at = 1792001204 }, nil, ZOE, BO)
      local ops = Records.Ops(RAID)
      local held = Records.Get("aw-9d2f6h1j")
      assert.are.same({ ZOE, "confirmed" }, { held.sender, held.state })
      assert.are.same({ ["aw-9d2f6h1j"] = BO, ["cf-1x8p4d2s"] = BO }, ns.db.via)
      assert.are.same({ ZOE, ZOE }, { Records.Author(ops[1]), Records.Author(ops[2]) })
      -- The same operations again, sent directly by their author, change nothing.
      send(award({ sender = ZOE }))
      send({ type = "confirm", id = "cf-1x8p4d2s", key = "aw-9d2f6h1j", at = 1792001204 })
      assert.are.equal(2, #Records.Ops(RAID))
      assert.are.same({ ["aw-9d2f6h1j"] = BO, ["cf-1x8p4d2s"] = BO }, ns.db.via)
      assert.are.same({}, wow.printed)
    end)

  describe("the end of a catch-up reply", function()
    it("is logged with its request and count, and changes no records", function()
      receive("D;r00001;3", BO)
      assert.is_true(logged("Bo Marsh answered catch-up request r00001 with 3 operations."))
      assert.are.same({}, Records.Ops(RAID))
    end)

    it("is logged and dropped when malformed", function()
      for _, body in ipairs({ "D;r00001;", "D;r00001", "D;R00001;1", "D;r0001;1", "D;r00001;1000",
        "D;r00001;-1", "D;r00001;1;2" }) do
        receive(body, BO)
      end
      assert.are.equal(7, #ns.log)
      assert.is_true(logged("dropped a malformed D message from Bo Marsh."))
      assert.are.same({}, wow.printed)
    end)
  end)

  describe("a resend request", function()
    it("goes to the connected listener with the sender, msgid and chunks", function()
      local got
      ns.Hub.onRequest = function(...) got = { ... } end
      receive("Q;k4m8q2;1,3", BO)
      assert.are.same({ BO, "k4m8q2", { 1, 3 } }, got)
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

describe("Hub sending", function()
  local ns, Records, Hub

  local function logged(text)
    for _, entry in ipairs(ns.log) do
      if entry.text:find(text, 1, true) then return true end
    end
    return false
  end

  local count = 0
  -- An award made on this add-on, as Records returns it.
  local function award(note)
    count = count + 1
    return (assert(Records.Award({ boss = "lb_lucifron", item = 16805, char = "Ana Vale", user = "u_ana",
      method = "HR", roll = 91, note = note, id = string.format("aw-%08d", count) })))
  end

  local function bodies()
    local list = {}
    for _, message in ipairs(wow.addonMessages) do list[#list + 1] = message.text end
    return list
  end

  before_each(function()
    ns = wow.start()
    Records, Hub = ns.Records, ns.Hub
    wow.state.player = "Rae Quill"
    -- Chosen before joining the group, so no S message is queued.
    ns.Raids.Load(assert(ns.Snapshot.Validate(snapshot(RAID), "0.1.0")), "pasted")
    assert.is_true(ns.Selection.ChooseRaid(RAID, true))
    wow.state.group, wow.state.groupIsRaid = { "Rae Quill", ZOE, BO }, true
  end)

  it("sends a burst of operations as BFLOOT1 messages to the raid, one a second", function()
    local ops = { award(), award(), award() }
    for _, op in ipairs(ops) do assert.is_true(Hub.SendOp(op, RAID)) end
    assert.are.equal(1, #wow.addonMessages)
    wow.advance(0.5)
    assert.are.equal(1, #wow.addonMessages)
    wow.advance(0.5)
    assert.are.equal(2, #wow.addonMessages)
    wow.advance(1)
    assert.are.equal(3, #wow.addonMessages)
    for i, message in ipairs(wow.addonMessages) do
      assert.are.same({ "BFLOOT1", "RAID" }, { message.prefix, message.channel })
      assert.is_nil(message.target)
      local chunk = assert(ns.Sync.ParseChunk(message.text))
      assert.are.same({ 1, 1, "SA0001", "Rae Quill" }, { chunk.n, chunk.total, chunk.raid, chunk.author })
      assert.are.equal(ns.OpText.Encode(ops[i]), chunk.piece)
    end
  end)

  it("sends to the party in a party, every chunk of a long operation", function()
    wow.state.groupIsRaid = false
    assert.is_true(Hub.SendOp(award(string.rep("Traded after the roll. ", 8)), RAID))
    wow.advance(1)
    assert.are.equal(2, #wow.addonMessages)
    assert.are.same({ "PARTY", "PARTY" }, { wow.addonMessages[1].channel, wow.addonMessages[2].channel })
    assert.is_truthy(wow.addonMessages[2].text:find("^O;%w+;2/2;"))
  end)

  it("sends nothing during a boss fight, then everything queued once it ends", function()
    Hub.SendOp(award(), RAID)
    Hub.SendOp(award(), RAID)
    wow.bossFight(true)
    Hub.SendOp(award(), RAID)
    wow.advance(1)
    wow.advance(60)
    assert.are.equal(1, #wow.addonMessages)
    wow.bossFight(false)
    assert.are.equal(2, #wow.addonMessages)
    wow.advance(1)
    assert.are.equal(3, #wow.addonMessages)
  end)

  it("keeps a message the game didn't send at the head, logs it once and tries again", function()
    local op = award()
    wow.state.sendResult = 3 -- AddonMessageThrottle
    Hub.SendOp(op, RAID)
    Hub.SendOp(award(), RAID)
    wow.advance(5)
    wow.advance(5)
    assert.are.same({}, wow.addonMessages)
    local failures = 0
    for _, entry in ipairs(ns.log) do
      if entry.text:find("didn't send a message (3)", 1, true) then failures = failures + 1 end
    end
    assert.are.equal(1, failures)
    wow.state.sendResult = nil
    wow.advance(5)
    assert.are.equal(1, #wow.addonMessages)
    assert.is_truthy(wow.addonMessages[1].text:find(op.id, 1, true))
    wow.advance(1)
    assert.are.equal(2, #wow.addonMessages)
  end)

  it("logs and keeps the record when the queue is full", function()
    local accepted, refused = 0, nil
    for _ = 1, 120 do
      local op = award()
      if Hub.SendOp(op, RAID) then accepted = accepted + 1 else refused = refused or op end
    end
    assert.is_truthy(refused)
    assert.is_true(logged("the sending queue is full, so " .. refused.id .. " wasn't sent"))
    assert.is_truthy(Records.Get(refused.id))
    wow.advance(0)
    for _ = 1, 150 do wow.advance(1) end
    assert.are.equal(accepted, #wow.addonMessages)
    assert.are.same({}, wow.printed)
  end)

  it("sends nothing outside a group, and drops what was waiting on leaving it", function()
    wow.state.group, wow.state.groupIsRaid = nil, false
    local op = award()
    assert.is_false(Hub.SendOp(op, RAID))
    assert.is_true(logged("not in a group, so " .. op.id .. " wasn't sent"))
    assert.is_truthy(Records.Get(op.id))
    wow.state.group, wow.state.groupIsRaid = { "Rae Quill", ZOE, BO }, true
    Hub.SendOp(award(), RAID)
    Hub.SendOp(award(), RAID)
    Hub.sendRequest(ZOE, "Q;k4m8q2;2")
    wow.state.group, wow.state.groupIsRaid = nil, false
    wow.advance(1)
    wow.advance(1)
    assert.is_true(logged("not in a group, so 2 messages weren't sent"))
    Hub.sendRequest(ZOE, "Q;k4m8q2;1")
    assert.is_true(logged("not in a group, so Q;k4m8q2;1 to Zoé Brûlé wasn't sent"))
    wow.advance(5)
    assert.are.equal(1, #wow.addonMessages)
  end)

  it("sends nothing for an operation with no loaded raid", function()
    assert.is_false(Hub.SendOp(award(), nil))
    assert.is_false(Hub.SendOp(award(), OTHER))
    assert.are.same({}, wow.addonMessages)
    assert.is_true(logged("has no loaded raid"))
  end)

  it("never sends again an operation applied from another officer", function()
    for _, body in ipairs(ns.Sync.EncodeOp({ type = "award", id = "aw-9d2f6h1j", boss = "lb_lucifron",
      item = 16805, char = "Ana Vale", user = "u_ana", method = "HR", roll = 91, sender = ZOE,
      at = 1792001200 }, "SA0001", ZOE)) do
      wow.fire("CHAT_MSG_ADDON", "BFLOOT1", body, "RAID", ZOE)
    end
    assert.is_truthy(Records.Get("aw-9d2f6h1j"))
    wow.advance(60)
    assert.are.same({}, wow.addonMessages)
  end)

  it("whispers a Q request's body, paced with the rest", function()
    Hub.SendOp(award(), RAID)
    wow.fire("CHAT_MSG_ADDON", "BFLOOT1", "O;k4m8q2;1/2;SA0001;Zoé Brûlé;K;x", "RAID", ZOE)
    wow.advance(10)
    assert.are.equal(2, #wow.addonMessages)
    assert.are.same({ prefix = "BFLOOT1", text = "Q;k4m8q2;2", channel = "WHISPER", target = ZOE },
      wow.addonMessages[2])
  end)

  describe("answers a Q request", function()
    local msgid, sent

    before_each(function()
      Hub.SendOp(award(string.rep("Traded after the roll. ", 8)), RAID)
      wow.advance(1)
      sent = bodies()
      msgid = sent[1]:match("^O;(%w+);")
    end)

    it("by whispering only the chunks named to the sender", function()
      wow.fire("CHAT_MSG_ADDON", "BFLOOT1", "Q;" .. msgid .. ";2", "WHISPER", BO)
      wow.advance(1)
      wow.advance(1)
      assert.are.equal(3, #wow.addonMessages)
      assert.are.same({ prefix = "BFLOOT1", text = sent[2], channel = "WHISPER", target = BO },
        wow.addonMessages[3])
    end)

    it("by logging a chunk it never had, and sending the others", function()
      wow.fire("CHAT_MSG_ADDON", "BFLOOT1", "Q;" .. msgid .. ";1,7", "WHISPER", BO)
      wow.advance(1)
      wow.advance(1)
      assert.are.same({ sent[1], sent[2], sent[1] }, bodies())
      assert.is_true(logged("asked for chunk 7 of " .. msgid))
    end)

    it("for the first of a full queue held through a boss fight", function()
      wow.bossFight(true)
      local first = award()
      assert.is_true(Hub.SendOp(first, RAID))
      for _ = 2, 100 do assert.is_true(Hub.SendOp(award(), RAID)) end
      assert.is_false(Hub.SendOp(award(), RAID))
      wow.bossFight(false)
      wow.advance(1)
      local firstId = wow.addonMessages[3].text:match("^O;(%w+);")
      assert.is_truthy(wow.addonMessages[3].text:find(first.id, 1, true))
      for _ = 1, 100 do wow.advance(1) end
      wow.fire("CHAT_MSG_ADDON", "BFLOOT1", "Q;" .. firstId .. ";1", "WHISPER", BO)
      wow.advance(1)
      assert.are.same({ wow.addonMessages[3].text, BO },
        { wow.addonMessages[#wow.addonMessages].text, wow.addonMessages[#wow.addonMessages].target })
    end)

    it("by logging a message it no longer holds, and sending nothing", function()
      wow.fire("CHAT_MSG_ADDON", "BFLOOT1", "Q;zzzzzz;1", "WHISPER", BO)
      -- A full queue's worth of operations later, the first is no longer held.
      for _ = 1, 100 do Hub.SendOp(award(), RAID) end
      for _ = 1, 100 do wow.advance(1) end
      wow.fire("CHAT_MSG_ADDON", "BFLOOT1", "Q;" .. msgid .. ";1", "WHISPER", BO)
      wow.advance(1)
      assert.are.equal(102, #wow.addonMessages)
      assert.is_true(logged("Bo Marsh asked again for zzzzzz, which is no longer held"))
      assert.is_true(logged("Bo Marsh asked again for " .. msgid .. ", which is no longer held"))
    end)
  end)
end)

describe("Hub officers and the selection", function()
  local ns, Hub, Selection
  local CY = "Cy Dunn"
  -- What this add-on holds for the loaded raid: nothing yet (#20).
  local HELD = "H;SA0001;1;0;00000000"

  local function logged(text)
    for _, entry in ipairs(ns.log) do
      if entry.text:find(text, 1, true) then return true end
    end
    return false
  end

  local function receive(body, sender, channel, prefix)
    wow.fire("CHAT_MSG_ADDON", prefix or "BFLOOT1", body, channel or "RAID", sender)
  end

  -- What the add-on sent, once the paced queue has run: { text, channel, target } each.
  local function sent()
    for _ = 1, 10 do wow.advance(1) end
    local list = {}
    for _, m in ipairs(wow.addonMessages) do list[#list + 1] = { m.text, m.channel, m.target } end
    return list
  end

  -- The game writes saved data to disk and reads it back: a copy, not the same table.
  local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[copy(k)] = copy(v) end
    return out
  end

  -- A fresh session for player in a raid group of group (the player first), with raid loaded.
  local function start(player, group, saved)
    ns = wow.start({ saved = saved })
    Hub, Selection = ns.Hub, ns.Selection
    wow.state.player = player or "Rae Quill"
    if not saved then ns.Raids.Load(assert(ns.Snapshot.Validate(snapshot(RAID), "0.1.0")), "pasted") end
    wow.state.group, wow.state.groupIsRaid = group, group ~= nil
  end

  local function status()
    local s = Selection.Status()
    return { s.activeBy, s.activeRaid, s.code, s.at, s.chosenBy }
  end

  before_each(function()
    start("Rae Quill", { "Rae Quill", ZOE, BO, CY })
  end)

  describe("P", function()
    it("is broadcast at login in a group", function()
      wow.fire("PLAYER_ENTERING_WORLD", true, false)
      assert.are.same({ { "P;1", "RAID" }, { HELD, "RAID" } }, sent())
    end)

    it("is broadcast on a /reload in a group, to a party in a party", function()
      wow.state.groupIsRaid = false
      wow.fire("PLAYER_ENTERING_WORLD", false, true)
      assert.are.same({ { "P;1", "PARTY" }, { HELD, "PARTY" } }, sent())
    end)

    it("is broadcast on joining a group, once, and not on zoning", function()
      wow.state.group, wow.state.groupIsRaid = nil, false
      wow.fire("PLAYER_ENTERING_WORLD", true, false)
      wow.fire("GROUP_ROSTER_UPDATE")
      assert.are.same({}, sent())
      wow.state.group, wow.state.groupIsRaid = { "Rae Quill", ZOE }, false
      wow.fire("GROUP_ROSTER_UPDATE")
      wow.state.group, wow.state.groupIsRaid = { "Rae Quill", ZOE, BO }, true
      wow.fire("GROUP_ROSTER_UPDATE")
      wow.fire("PLAYER_ENTERING_WORLD", false, false)
      -- The H waits its turn in the queue, and goes to the raid the party has become by then.
      assert.are.same({ { "P;1", "PARTY" }, { HELD, "RAID" } }, sent())
    end)

    it("from a new name is answered with a whispered P;0, the held selection, as it was made, and an H",
      function()
      assert.is_true(Selection.Apply("SA0001", 1792000100, BO))
      receive("P;1", ZOE)
      assert.are.same({ { "P;0", "WHISPER", ZOE }, { "S;SA0001;1792000100;Bo Marsh", "WHISPER", ZOE },
        { HELD, "WHISPER", ZOE } }, sent())
      assert.are.same({ ZOE }, Hub.Roster())
    end)

    it("is answered with no selection when no raid is chosen yet", function()
      receive("P;1", ZOE .. "-Realm")
      assert.are.same({ { "P;0", "WHISPER", ZOE }, { HELD, "WHISPER", ZOE } }, sent())
    end)

    it("from a name already seen is answered again, for an officer who reloaded", function()
      receive("P;1", ZOE)
      receive("P;1", ZOE)
      assert.are.equal(4, #sent())
      assert.are.same({ ZOE }, Hub.Roster())
    end)

    it("P;0 adds the name and is never answered", function()
      receive("P;0", BO, "WHISPER")
      assert.are.same({}, sent())
      assert.are.same({ BO }, Hub.Roster())
    end)

    it("is logged and dropped when malformed, or from outside the group", function()
      for _, body in ipairs({ "P;2", "P;", "P;1;x", "P" }) do receive(body, ZOE) end
      receive("P;1", "Stranger")
      assert.are.same({}, sent())
      assert.are.same({}, Hub.Roster())
      assert.is_true(logged("dropped a malformed P message from Zoé Brûlé"))
      assert.is_true(logged("Stranger, who isn't in the group"))
    end)

    it("a name that leaves the group leaves the roster", function()
      wow.fire("PLAYER_ENTERING_WORLD", false, true)
      receive("P;0", ZOE)
      receive("P;0", BO)
      wow.state.group = { "Rae Quill", BO, CY }
      wow.fire("GROUP_ROSTER_UPDATE")
      assert.are.same({ BO }, Hub.Roster())
    end)
  end)

  describe("the chooser", function()
    -- Each add-on in the group, as the players in users, hears P from the others and names the chooser.
    local function everyone(users, setup)
      local names = {}
      for _, player in ipairs(users) do
        start(player, { "Rae Quill", ZOE, BO, CY })
        setup()
        for _, other in ipairs(users) do
          if other ~= player then receive("P;0", other) end
        end
        names[#names + 1] = Hub.Chooser()
        assert.are.equal(Hub.Chooser() == player, Hub.IsChooser())
      end
      return names
    end

    it("is the loot master when master loot is on and they run the add-on", function()
      assert.are.same({ BO, BO, BO }, everyone({ "Rae Quill", ZOE, BO }, function()
        wow.state.lootMethod = { "master", 2, 3 }
        wow.state.groupLeader = ZOE
      end))
    end)

    it("is the raid leader when the loot master doesn't run the add-on", function()
      assert.are.same({ ZOE, ZOE, ZOE }, everyone({ "Rae Quill", ZOE, BO }, function()
        wow.state.lootMethod = { "master", 3, 4 }
        wow.state.groupLeader = ZOE
      end))
    end)

    it("is the raid leader when master loot is off", function()
      assert.are.same({ ZOE, ZOE }, everyone({ ZOE, BO }, function()
        wow.state.lootMethod = { "group", 0, 0 }
        wow.state.groupLeader = ZOE
      end))
    end)

    it("is the first add-on user by name, byte by byte, when neither runs it", function()
      assert.are.same({ BO, BO, BO }, everyone({ "Rae Quill", ZOE, BO }, function()
        wow.state.lootMethod = { "master", 3, 4 }
        wow.state.groupLeader = CY
      end))
      -- Byte order, not alphabetical: "Z" (0x5A) comes before "Å" (0xC3 0x85) and before "a".
      start("Ånne Holt", { "Ånne Holt", "Zed Ash", "abe Moss" })
      receive("P;0", "abe Moss")
      receive("P;0", "Zed Ash")
      assert.are.equal("Zed Ash", Hub.Chooser())
    end)

    it("is this player alone when no one else runs the add-on", function()
      wow.state.groupLeader = ZOE
      assert.are.equal("Rae Quill", Hub.Chooser())
      assert.is_true(Hub.IsChooser())
    end)

    it("reads the loot master and leader of a party", function()
      wow.state.groupIsRaid = false
      receive("P;0", ZOE)
      receive("P;0", BO)
      wow.state.groupLeader = ZOE
      assert.are.equal(ZOE, Hub.Chooser())
      wow.state.lootMethod = { "master", 2, 0 }
      assert.are.equal(BO, Hub.Chooser())
      wow.state.lootMethod = { "master", 0, 0 }
      assert.are.equal("Rae Quill", Hub.Chooser())
    end)
  end)

  describe("the chooser, with officers offline", function()
    before_each(function()
      start("Rae Quill", { "Rae Quill", ZOE, BO, CY })
      receive("P;0", ZOE)
      receive("P;0", BO)
    end)

    it("skips an offline loot master, then an offline raid leader", function()
      wow.state.lootMethod = { "master", 2, 3 }
      wow.state.groupLeader = ZOE
      assert.are.equal(BO, Hub.Chooser())
      wow.state.offline = { [BO] = true }
      assert.are.equal(ZOE, Hub.Chooser())
      wow.state.offline = { [BO] = true, [ZOE] = true }
      assert.are.equal("Rae Quill", Hub.Chooser())
    end)

    it("is the first online user by name when the leader and loot master are offline", function()
      wow.state.groupLeader = ZOE
      wow.state.offline = { [ZOE] = true }
      assert.are.equal(BO, Hub.Chooser())
    end)

    it("is this player when all others are offline, and never reads this player as offline", function()
      wow.state.groupLeader = ZOE
      wow.state.offline = { [ZOE] = true, [BO] = true, ["Rae Quill"] = true }
      assert.are.equal("Rae Quill", Hub.Chooser())
      assert.is_true(Hub.IsChooser())
      assert.are.same({}, Hub.Roster())
    end)

    it("counts an officer again on coming back online, without a new P", function()
      wow.state.groupLeader = ZOE
      wow.state.offline = { [ZOE] = true }
      assert.are.same({ BO }, Hub.Roster())
      wow.state.offline = nil
      assert.are.equal(ZOE, Hub.Chooser())
      assert.are.same({ BO, ZOE }, Hub.Roster())
    end)

    it("reads a party's online state with UnitIsConnected", function()
      wow.state.groupIsRaid = false
      wow.state.groupLeader = ZOE
      wow.state.offline = { [ZOE] = true }
      assert.are.equal(BO, Hub.Chooser())
    end)
  end)

  describe("S", function()
    it("is broadcast when this officer chooses a raid, not a guild run, or pastes", function()
      wow.state.time = 1792000100
      assert.is_true(Selection.ChooseRaid(RAID))
      assert.is_true(Selection.ChooseRaid(RAID))
      Selection.ChooseOff()
      assert.are.same({ { "S;SA0001;1792000100;Rae Quill", "RAID" }, { "S;-;1792000101;Rae Quill", "RAID" } },
        sent())
    end)

    it("is broadcast for a pasted raid", function()
      local text = "BFSNAP1:1/1:{ formatVersion = 1, raid = \"" .. OTHER .. "\", code = \"SA0002\", "
        .. "env = \"staging\", name = \"Onyxia\", startsAt = 1792000000, durationMin = 120, "
        .. "generated = 1791990000, addon = { version = \"0.0.1\", url = \"u\" }, bosses = {}, "
        .. "reserves = {}, awards = {} }"
      assert.are.equal(OTHER, (Selection.Paste(text)))
      assert.are.same({ { "S;SA0002;1792000000;Rae Quill", "RAID" } }, sent())
    end)

    it("sends nothing when the choice is made outside a group", function()
      wow.state.group, wow.state.groupIsRaid = nil, false
      Selection.ChooseRaid(RAID)
      assert.are.same({}, sent())
      assert.are.same({}, ns.log)
    end)

    for _, case in ipairs({ { "a raid code", RAID }, { "not a guild run", "off" } }) do
      it("round-trips " .. case[1] .. " with an accented name", function()
        start(ZOE, { ZOE, "Rae Quill" })
        if case[2] == "off" then Selection.ChooseOff() else Selection.ChooseRaid(RAID) end
        local body = sent()[1][1]
        local held = status()
        start("Rae Quill", { "Rae Quill", ZOE })
        receive(body, ZOE)
        assert.are.same(held, status())
        assert.are.equal(ZOE, Selection.Status().chosenBy)
      end)
    end

    it("fits 255 bytes and round-trips with the longest escaped name", function()
      local longest = string.rep(";", 24)
      assert.is_true(Selection.Apply("SA0001", 9999999999, longest))
      local body = Hub.SelectionBody()
      assert.are.equal("S;SA0001;9999999999;" .. string.rep("%3B", 24), body)
      assert.is_true(#"BFLOOT1" + 1 + #body <= 255)
      start("Rae Quill", { "Rae Quill", ZOE })
      receive(body, ZOE)
      assert.are.equal(longest, Selection.Status().chosenBy)
    end)

    it("received goes through Selection.Apply and is never sent again", function()
      local calls = {}
      local real = Selection.Apply
      Selection.Apply = function(...)
        calls[#calls + 1] = { ... }
        return real(...)
      end
      receive("S;SA0001;1792000100;Bo Marsh", BO)
      assert.are.same({ { "SA0001", 1792000100, BO } }, calls)
      assert.are.same({ "chosen", RAID, "SA0001", 1792000100, BO }, status())
      assert.are.same({}, sent())
    end)

    it("ends the same on two add-ons that get two crossing choices in opposite orders", function()
      local pairsOf = {
        { "S;SA0001;1792000200;Bo Marsh", "S;-;1792000100;Zoé Brûlé" },     -- the later at wins
        { "S;SA0001;1792000100;Bo Marsh", "S;-;1792000100;Zoé Brûlé" },     -- a tie: the later name
      }
      for _, crossing in ipairs(pairsOf) do
        local results = {}
        for _, order in ipairs({ { 1, 2 }, { 2, 1 } }) do
          start()
          wow.state.group, wow.state.groupIsRaid = { "Rae Quill", ZOE, BO }, true
          for _, i in ipairs(order) do
            receive(crossing[i], crossing[i]:match(";([^;]+)$"))
          end
          results[#results + 1] = status()
        end
        assert.are.same(results[1], results[2])
      end
      assert.are.same({ "off", nil, nil, 1792000100, ZOE }, status())
    end)

    it("repeated changes nothing", function()
      receive("S;SA0001;1792000100;Bo Marsh", BO)
      local held = copy(ns.db)
      receive("S;SA0001;1792000100;Bo Marsh", BO)
      assert.are.same(held, ns.db)
    end)

    it("for a raid not loaded is held, and a code two raids share is shown", function()
      receive("S;SZZZZZ;1792000100;Bo Marsh", BO)
      assert.are.same({ "chosen", nil, "SZZZZZ", 1792000100, BO }, status())
      local twin = snapshot(OTHER)
      twin.code = "SA0001"
      ns.Raids.Load(assert(ns.Snapshot.Validate(twin, "0.1.0")), "pasted")
      receive("S;SA0001;1792000200;Bo Marsh", BO)
      assert.are.same({ "chosen", nil, "SA0001" }, { status()[1], status()[2], status()[3] })
      assert.is_truthy(wow.printed[1]:find("Two loaded raids have the code SA0001", 1, true))
    end)

    describe("changes nothing", function()
      local cases = {
        ["from outside the group"] = { "S;SA0001;1792000100;Bo Marsh", "Stranger" },
        ["with a higher prefix number"] = { "S;SA0001;1792000100;Bo Marsh", BO, "BFLOOT2" },
      }
      for _, body in ipairs({ "S;SA0001;soon;Bo Marsh", "S;sa0001;1792000100;Bo Marsh", "S;SA001;1;Bo Marsh",
        "S;SA0001;1792000100;", "S;SA0001;1792000100;Bo%ZZ", "S;SA0001;1792000100;Bo;x", "S;;1;Bo Marsh",
        "S;SA0001;17920001000;Bo Marsh", "S;SA0001;1792000100;Bo>Marsh" }) do
        cases["for " .. body] = { body, BO, nil, "dropped a malformed S message from Bo Marsh" }
      end
      for name, case in pairs(cases) do
        it(name, function()
          receive(case[1], case[2], nil, case[3])
          assert.are.same({ "none" }, status())
          if case[4] then assert.is_true(logged(case[4])) end
          if case[3] then
            assert.are.equal(1, #wow.printed)
            assert.is_truthy(wow.printed[1]:find("update Bureaucracy Forever", 1, true))
          else
            assert.are.same({}, wow.printed)
          end
        end)
      end
    end)

    it("this officer's waits through a boss fight in the queue, then is sent", function()
      wow.bossFight(true)
      Selection.ChooseRaid(RAID)
      assert.are.same({}, sent())
      wow.bossFight(false)
      assert.are.equal("S;SA0001;", sent()[1][1]:sub(1, 9))
    end)

    it("this officer's, and the answers to P, are queued even when the queue is full", function()
      wow.bossFight(true)
      for i = 1, 100 do
        assert.is_true(Hub.SendOp(assert(ns.Records.Award({ boss = "lb_lucifron", item = 16805,
          char = "Ana Vale", user = "u_ana", method = "HR", id = string.format("aw-%08d", i) })), RAID))
      end
      Selection.ChooseOff()
      receive("P;1", ZOE)
      wow.bossFight(false)
      for _ = 1, 110 do wow.advance(1) end
      local last = {}
      for i = #wow.addonMessages - 3, #wow.addonMessages do last[#last + 1] = wow.addonMessages[i].text end
      assert.are.same({ "S;-;1792000000;Rae Quill", "P;0", "S;-;1792000000;Rae Quill",
        HELD }, last)
    end)

    it("and P keep flowing while not a guild run", function()
      wow.state.time = 1792000100
      Selection.ChooseOff()
      assert.is_true(Selection.IsQuiet())
      receive("P;1", ZOE)
      assert.are.same({ { "S;-;1792000100;Rae Quill", "RAID" }, { "P;0", "WHISPER", ZOE },
        { "S;-;1792000100;Rae Quill", "WHISPER", ZOE }, { HELD, "WHISPER", ZOE } }, sent())
      receive("S;SA0001;1792000200;Zoé Brûlé", ZOE)
      assert.are.same({ "chosen", RAID }, { status()[1], status()[2] })
    end)
  end)

  describe("the group", function()
    it("left clears the roster and the selection, and a new group starts fresh", function()
      wow.fire("PLAYER_ENTERING_WORLD", false, true)
      receive("P;0", ZOE)
      Selection.ChooseRaid(RAID)
      sent()
      wow.state.group, wow.state.groupIsRaid = nil, false
      wow.fire("GROUP_ROSTER_UPDATE")
      assert.are.same({}, Hub.Roster())
      assert.are.same({ "none" }, status())
      wow.state.group, wow.state.groupIsRaid = { "Rae Quill", BO }, false
      wow.fire("GROUP_ROSTER_UPDATE")
      local list = sent()
      assert.are.same({ { "P;1", "PARTY" }, { HELD, "PARTY" } }, { list[4], list[5] })
      assert.are.same({ "none" }, status())
    end)

    it("left drops what was queued for it, so a quick new group gets none of it", function()
      wow.fire("PLAYER_ENTERING_WORLD", false, true)
      Selection.ChooseOff()
      wow.state.group, wow.state.groupIsRaid = nil, false
      wow.fire("GROUP_ROSTER_UPDATE")
      wow.state.group, wow.state.groupIsRaid = { "Rae Quill", BO }, true
      wow.fire("GROUP_ROSTER_UPDATE")
      assert.are.same({ { "P;1", "RAID" }, { "P;1", "RAID" }, { HELD, "RAID" } }, sent())
      assert.is_true(logged("not in a group, so 2 messages weren't sent"))
    end)

    it("clears a saved selection at login outside a group", function()
      Selection.ChooseRaid(RAID)
      start("Rae Quill", nil, { BureaucracyForeverDB = copy(ns.db) })
      assert.are.equal("chosen", Selection.ActiveBy())
      wow.fire("PLAYER_ENTERING_WORLD", true, false)
      assert.are.same({ "none" }, status())
    end)

    for _, case in ipairs({ { "in the same group", { "Rae Quill", ZOE } }, { "outside a group", nil } }) do
      it("keeps a saved selection on a /reload " .. case[1], function()
        Selection.ChooseRaid(RAID)
        local held = status()
        start("Rae Quill", case[2], { BureaucracyForeverDB = copy(ns.db) })
        wow.fire("PLAYER_ENTERING_WORLD", false, true)
        wow.fire("GROUP_ROSTER_UPDATE")
        assert.are.same(held, status())
      end)
    end

    it("keeps a saved selection at login in a group", function()
      Selection.ChooseRaid(RAID)
      local held = status()
      start("Rae Quill", { "Rae Quill", ZOE }, { BureaucracyForeverDB = copy(ns.db) })
      wow.fire("PLAYER_ENTERING_WORLD", true, false)
      assert.are.same(held, status())
      assert.are.same({ { "P;1", "RAID" }, { HELD, "RAID" } }, sent())
    end)
  end)
end)

-- Three officers' add-ons in one 40-player raid. The stand-in runs one add-on at a time, so each
-- officer's turn is a session on their own saved data: it takes in what the others sent, every
-- message twice (all in reverse order, then in order), then makes its own operations and sends them.
describe("Hub across a whole raid", function()
  local OFFICERS = { ZOE, "Rae Quill", BO }
  local FIRST = { "Ana", "Søren", "Ægir", "Chloë", "Íñigo", "Maël", "Åsa", "Björk", "José", "Ðana" }
  local LAST = { "Vale", "Brûlé", "Østby", "Straße" }
  local players, dbs, inbox, ns

  local function turn(officer, make)
    ns = wow.start({ saved = { BureaucracyForeverDB = dbs[officer] } })
    wow.state.player = officer
    if not dbs[officer] then
      ns.Raids.Load(assert(ns.Snapshot.Validate(snapshot(RAID), "0.1.0")), "pasted")
      assert.is_true(ns.Selection.ChooseRaid(RAID, true))
    end
    wow.state.group, wow.state.groupIsRaid = players, true
    local messages = inbox[officer]
    local function deliver(m) wow.fire("CHAT_MSG_ADDON", "BFLOOT1", m[2], "RAID", m[1]) end
    for i = #messages, 1, -1 do deliver(messages[i]) end
    for _, m in ipairs(messages) do deliver(m) end
    inbox[officer] = {}
    for _, op in ipairs(make and make(ns.Records) or {}) do assert.is_true(ns.Hub.SendOp(op, RAID)) end
    for _ = 1, 120 do wow.advance(1) end
    for _, message in ipairs(wow.addonMessages) do
      -- Nothing was missing, so no one asked again; every message went to the whole raid.
      assert.are.same({ "BFLOOT1", "RAID" }, { message.prefix, message.channel })
      for _, other in ipairs(OFFICERS) do
        if other ~= officer then table.insert(inbox[other], { officer, message.text }) end
      end
    end
    -- No officer saw a conflict or a notice.
    assert.are.same({}, wow.printed)
    dbs[officer] = BureaucracyForeverDB
    return ns
  end

  -- Awards to players from to to, of the 40, by the officer whose turn it is.
  local function awards(from, to)
    return function(Records)
      local ops = {}
      for i = from, to do
        -- Every fifth award has a note long enough to need two messages.
        local note = i % 5 == 0 and string.rep("Trés bien; ", 14) or nil
        -- Players i and i + 20 get copies of one item.
        ops[#ops + 1] = assert(Records.Award({ boss = "lb_lucifron", item = 16800 + i % 20, char = players[i],
          user = "u_" .. i, method = i % 2 == 0 and "SR" or "HR", roll = i, note = note }))
      end
      return ops
    end
  end

  local function keyOf(Records, char)
    for _, op in ipairs(Records.Ops(RAID)) do
      if op.type == "award" and op.char == char then return op.id end
    end
  end

  -- What an add-on holds, by id, in no particular order.
  local function held(addon)
    local ops, records = {}, {}
    for _, op in ipairs(addon.Records.Ops(RAID)) do
      assert.is_nil(ops[op.id], "held twice: " .. op.id)
      ops[op.id] = op
    end
    for _, record in ipairs(addon.Raids.Awards(RAID)) do
      assert.is_nil(records[record.key], "held twice: " .. record.key)
      records[record.key] = record
    end
    return ops, records
  end

  before_each(function()
    players, dbs, inbox = {}, {}, {}
    for _, officer in ipairs(OFFICERS) do inbox[officer] = {} end
    for i = 1, 40 - #OFFICERS do
      players[i] = FIRST[(i - 1) % #FIRST + 1] .. " " .. LAST[math.floor((i - 1) / #FIRST) + 1]
    end
    for _, officer in ipairs(OFFICERS) do players[#players + 1] = officer end
  end)

  it("syncs every award and void between three add-ons, with nothing lost or doubled", function()
    assert.are.equal(40, #players)
    turn(ZOE, awards(1, 14))
    turn("Rae Quill", awards(15, 27))
    -- A name outside the group sends too, among the officers' messages.
    local stranger = turn(BO, awards(28, 40))
    for _, body in ipairs(stranger.Sync.EncodeOp({ type = "void", id = "vd-stranger1",
      key = keyOf(stranger.Records, players[1]), at = 1792001300 }, "SA0001", "Stray Wolf")) do
      table.insert(inbox[ZOE], { "Stray Wolf", body })
    end
    -- Then each officer voids, replaces or confirms awards the others made.
    local zoe = turn(ZOE, function(Records)
      return {
        assert(Records.Void(keyOf(Records, players[15]), { reason = "wrong winner" })),
        assert(Records.Confirm(keyOf(Records, players[28]))),
        (assert(Records.Replace(keyOf(Records, players[29]), { boss = "lb_lucifron", item = 16829,
          char = players[30], user = "u_30", method = "SR", roll = 77 }))),
      }
    end)
    local logged = false
    for _, entry in ipairs(zoe.log) do
      logged = logged or entry.text:find("Stray Wolf, who isn't in the group", 1, true) ~= nil
    end
    assert.is_true(logged)
    turn("Rae Quill", function(Records)
      return {
        assert(Records.Void(keyOf(Records, players[2]), { reason = "traded back" })),
        (assert(Records.NotConfirmed(keyOf(Records, players[3])))),
      }
    end)
    turn(BO, function(Records)
      return { (assert(Records.Void(keyOf(Records, players[16])))) }
    end)
    -- Last turns take in what is still waiting.
    local addons = { turn(ZOE), turn("Rae Quill"), turn(BO) }

    local ops, records = held(addons[1])
    local count = 0
    for _ in pairs(ops) do count = count + 1 end
    -- 40 awards, 3 voids, a confirm, a not-confirmed and a replace (its new award inside it).
    assert.are.equal(46, count)
    for i = 2, 3 do
      local others, otherRecords = held(addons[i])
      assert.are.same(ops, others)
      assert.are.same(records, otherRecords)
    end

    local Records = addons[1].Records
    local function record(i) return records[keyOf(Records, players[i])] end
    for i = 1, 40 do
      assert.are.equal(i <= 14 and ZOE or i <= 27 and "Rae Quill" or BO, record(i).sender)
    end
    assert.is_nil(record(1).voided)
    assert.are.same({ true, true, true }, { record(2).voided, record(15).voided, record(16).voided })
    -- The other copies of the voided awards' items stand, each its own award.
    for _, i in ipairs({ 2, 15, 16 }) do
      local copy = record(i + 20)
      assert.are_not.equal(record(i).key, copy.key)
      assert.are.equal(record(i).item, copy.item)
      assert.is_nil(copy.voided)
    end
    assert.are.same({ "not-confirmed", "confirmed" }, { record(3).state, record(28).state })
    assert.is_true(record(29).voided)
    local replacement = records[record(29).replacedBy]
    assert.are.same({ players[30], ZOE }, { replacement.char, replacement.sender })
    assert.is_nil(ops["vd-stranger1"])
  end)
end)

-- Catch-up (spec 10.2, 10.4; #20): H says what an add-on holds, a differing H is answered with a C
-- of every id held, and a whole C is handed to Hub.onCatchUp with the ids its sender lacks.
describe("Hub catch-up", function()
  local ns, Hub, Sync

  local function receive(body, sender, channel)
    wow.fire("CHAT_MSG_ADDON", "BFLOOT1", body, channel or "RAID", sender)
  end

  -- What the add-on sent, once the paced queue has run: { text, channel, target } each.
  local function sent()
    for _ = 1, 20 do wow.advance(1) end
    local list = {}
    for _, m in ipairs(wow.addonMessages) do list[#list + 1] = { m.text, m.channel, m.target } end
    return list
  end

  local function logged(text)
    for _, entry in ipairs(ns.log) do
      if entry.text:find(text, 1, true) then return true end
    end
    return false
  end

  local function load(id)
    ns.Raids.Load(assert(ns.Snapshot.Validate(snapshot(id), "0.1.0")), "pasted")
  end

  -- An award held for the raid, made on this add-on.
  local function award(id, raidId)
    assert(ns.Records.Award({ boss = "lb_lucifron", item = 16805, char = "Ana Vale", user = "u_ana",
      method = "HR", id = id, raid = raidId or RAID }))
  end

  local function held(ids, code)
    return "H;" .. (code or "SA0001") .. ";1;" .. #ids .. ";" .. ns.Digest.Of(ids)
  end

  -- The ids of the C bodies in list, joined, after checking they make one whole request to target.
  local function requested(list, target)
    local pieces, reqid = {}, nil
    for n, m in ipairs(list) do
      assert.are.same({ "WHISPER", target }, { m[2], m[3] })
      local chunk = assert(Sync.ParseRequest(m[1]))
      reqid = reqid or chunk.msgid
      assert.are.same({ reqid, n, #list, "SA0001" }, { chunk.msgid, chunk.n, chunk.total, chunk.raid })
      pieces[n] = chunk.piece
    end
    return assert(Sync.ParseIds(table.concat(pieces))), reqid
  end

  local calls
  before_each(function()
    ns = wow.start()
    Hub, Sync = ns.Hub, ns.Sync
    wow.state.player = "Rae Quill"
    wow.state.group, wow.state.groupIsRaid = { "Rae Quill", ZOE, BO }, true
    load(RAID)
    calls = {}
    local onCatchUp = Hub.onCatchUp
    Hub.onCatchUp = function(...)
      calls[#calls + 1] = { ... }
      return onCatchUp(...)
    end
  end)

  describe("H", function()
    it("is sent at login and on a /reload for every loaded raid, with the count and digest held", function()
      load(OTHER)
      award("aw-00000001")
      award("aw-00000002")
      wow.fire("PLAYER_ENTERING_WORLD", false, true)
      assert.are.same({ { "P;1", "RAID" }, { held({ "aw-00000001", "aw-00000002" }), "RAID" },
        { held({}, "SA0002"), "RAID" } }, sent())
      assert.are.equal("H;SA0001;1;2;26ad9244", sent()[2][1])
    end)

    it("is sent on loading a snapshot in a group", function()
      wow.fire("PLAYER_ENTERING_WORLD", true, false)
      sent()
      load(OTHER)
      assert.are.same({ held({}, "SA0002"), "RAID" }, sent()[3])
      assert.are.equal(3, #sent())
    end)

    it("isn't sent on loading a snapshot outside a group, or before login, which sends it once", function()
      wow.state.group, wow.state.groupIsRaid = nil, false
      wow.fire("PLAYER_ENTERING_WORLD", true, false)
      load(OTHER)
      assert.are.same({}, sent())
      ns = wow.start({ saved = { BureaucracyForeverDB = BureaucracyForeverDB } })
      wow.state.group, wow.state.groupIsRaid = { "Rae Quill", ZOE }, false
      load(OTHER)
      assert.are.same({}, sent())
      wow.fire("PLAYER_ENTERING_WORLD", false, true)
      assert.are.same({ { "P;1", "PARTY" }, { held({}), "PARTY" }, { held({}, "SA0002"), "PARTY" } }, sent())
    end)

    it("is sent on joining a group", function()
      wow.state.group, wow.state.groupIsRaid = nil, false
      wow.fire("PLAYER_ENTERING_WORLD", true, false)
      wow.state.group = { "Rae Quill", ZOE }
      wow.fire("GROUP_ROSTER_UPDATE")
      assert.are.same({ { "P;1", "PARTY" }, { held({}), "PARTY" } }, sent())
    end)

    it("that differs is answered with a whispered C of every id held, chunked", function()
      local ids = {}
      for i = 1, 30 do
        ids[i] = string.format("aw-%08d", i)
        award(ids[i])
      end
      load(OTHER)
      award("aw-elsewher", OTHER)
      receive(held({ "aw-00000001" }), ZOE)
      local list = sent()
      assert.are.equal(3, #list) -- 30 ids of 11 bytes and 29 commas: 359 bytes
      assert.are.same(ids, (requested(list, ZOE)))
    end)

    it("that differs is answered with a C of no ids by an add-on holding none", function()
      receive(held({ "aw-00000001" }), ZOE)
      local list = sent()
      assert.are.equal(1, #list)
      assert.are.same({}, (requested(list, ZOE)))
    end)

    it("that matches, in any order, is answered with nothing", function()
      award("aw-00000001")
      award("aw-00000002")
      receive(held({ "aw-00000002", "aw-00000001" }), ZOE)
      receive(held({}, "SA0002"), ZOE)
      assert.are.same({}, sent())
    end)

    it("for a raid that isn't loaded is ignored", function()
      receive("H;SZZZZZ;1;1;dff3b5fb", ZOE)
      assert.are.same({}, sent())
      assert.is_true(logged("ignored Zoé Brûlé's H for raid SZZZZZ: not loaded."))
    end)

    it("is dropped when malformed", function()
      for _, body in ipairs({ "H;SA0001;1;1;DFF3B5FB", "H;SA0001;1;1;dff3b5f", "H;;1;1;dff3b5fb",
        "H;SA0001;1;dff3b5fb", "H;SA0001;x;1;dff3b5fb", "H;SA0001;1;1;dff3b5fb;x" }) do
        receive(body, ZOE)
      end
      assert.are.same({}, sent())
      assert.is_true(logged("dropped a malformed H message from Zoé Brûlé"))
    end)

    it("answered in a boss fight holds the C until the fight ends", function()
      wow.bossFight(true)
      receive(held({ "aw-00000001" }), ZOE)
      assert.are.same({}, sent())
      wow.bossFight(false)
      assert.are.equal(1, #sent())
    end)

    it("answered with a C that doesn't fit the queue sends none of it, and logs it", function()
      wow.bossFight(true)
      for i = 1, 100 do
        local op = assert(ns.Records.Award({ boss = "lb_lucifron", item = 16805, char = "Ana Vale",
          user = "u_ana", method = "HR", id = string.format("aw-%08d", i), raid = RAID }))
        assert.is_true(Hub.SendOp(op, RAID))
      end
      receive(held({}), ZOE)
      assert.is_true(logged("the sending queue is full, so the catch-up request to Zoé Brûlé wasn't sent."))
      wow.bossFight(false)
      for _ = 1, 110 do wow.advance(1) end
      assert.are.equal(100, #wow.addonMessages)
    end)

    it("a C chunk asked for again is resent", function()
      receive(held({ "aw-00000001" }), ZOE)
      local list = sent()
      local _, reqid = requested(list, ZOE)
      receive("Q;" .. reqid .. ";1", ZOE, "WHISPER")
      assert.are.same({ list[1][1], "WHISPER", ZOE }, sent()[2])
    end)
  end)

  describe("C", function()
    local function request(ids, reqid, code)
      return Sync.EncodeRequest(ids, code or "SA0001", reqid or "r00001")
    end

    it("rebuilt from its chunks, in any order, hands over the ids its sender lacks", function()
      local theirs = {}
      for i = 1, 30 do
        theirs[i] = string.format("aw-%08d", i)
        if i % 10 ~= 0 then award(theirs[i]) end
      end
      award("aw-mine0001")
      award("aw-mine0002")
      local bodies = request(theirs)
      assert.are.equal(3, #bodies)
      receive(bodies[3], ZOE, "WHISPER")
      receive(bodies[1], ZOE, "WHISPER")
      assert.are.same({}, calls)
      receive(bodies[1], ZOE, "WHISPER")
      receive(bodies[2], ZOE, "WHISPER")
      assert.are.same({ { ZOE, "r00001", RAID, { "aw-mine0001", "aw-mine0002" } } }, calls)
      assert.is_true(logged("Zoé Brûlé asked to catch up (r00001) on raid " .. RAID
        .. "; they lack 2: aw-mine0001, aw-mine0002."))
    end)

    it("from an add-on holding none hands over every id held", function()
      award("aw-00000001")
      receive(request({})[1], ZOE, "WHISPER")
      assert.are.same({ { ZOE, "r00001", RAID, { "aw-00000001" } } }, calls)
    end)

    it("from an add-on holding all hands over none, and is answered with nothing", function()
      award("aw-00000001")
      receive(request({ "aw-00000001", "aw-notmine1" })[1], ZOE, "WHISPER")
      assert.are.same({ { ZOE, "r00001", RAID, {} } }, calls)
      assert.are.same({}, sent())
    end)

    it("with a chunk missing asks for it again after 10 seconds", function()
      local requests = {}
      Hub.sendRequest = function(target, body) requests[#requests + 1] = { target, body } end
      local ids = {}
      for i = 1, 20 do ids[i] = string.format("aw-%08d", i) end
      local bodies = request(ids)
      receive(bodies[1], ZOE, "WHISPER")
      wow.advance(10)
      assert.are.same({ { ZOE, "Q;r00001;2" } }, requests)
      receive(bodies[2], ZOE, "WHISPER")
      assert.are.equal(1, #calls)
    end)

    it("arriving paced over more than 40 seconds is rebuilt, with nothing asked again", function()
      local requests = {}
      Hub.sendRequest = function(target, body) requests[#requests + 1] = { target, body } end
      local ids = {}
      for i = 1, 600 do ids[i] = string.format("aw-%08d", i) end
      local bodies = request(ids)
      assert.are.equal(45, #bodies)
      for _, body in ipairs(bodies) do
        receive(body, ZOE, "WHISPER")
        wow.advance(1)
      end
      assert.are.same({ { ZOE, "r00001", RAID, {} } }, calls)
      assert.are.same({}, requests)
    end)

    it("asks again 10 seconds after the last new chunk, and drops 40 seconds after it", function()
      local requests = {}
      Hub.sendRequest = function(target, body) requests[#requests + 1] = { target, body } end
      local ids = {}
      for i = 1, 50 do ids[i] = string.format("aw-%08d", i) end
      local bodies = request(ids)
      receive(bodies[1], ZOE, "WHISPER")
      wow.advance(8)
      receive(bodies[2], ZOE, "WHISPER")
      wow.advance(9)
      assert.are.same({}, requests)
      wow.advance(1)
      assert.are.same({ { ZOE, "Q;r00001;3,4" } }, requests)
      for _ = 1, 29 do wow.advance(1) end
      assert.are.equal(3, #requests)
      assert.is_false(logged("dropped Zoé Brûlé's message r00001"))
      wow.advance(1)
      assert.is_true(logged("dropped Zoé Brûlé's message r00001 (chunks still missing)"))
    end)

    it("from two senders, or under an O's msgid, is kept apart", function()
      local op = Sync.EncodeOp({ type = "confirm", id = "cf-00000001", key = "aw-00000001", at = 1792000100 },
        "SA0001", BO, "r00001")
      local ids = {}
      for i = 1, 20 do ids[i] = string.format("aw-%08d", i) end
      local bodies = request(ids)
      receive(bodies[1], ZOE, "WHISPER")
      receive(op[1], BO)
      receive(request(ids)[1], BO, "WHISPER")
      receive(bodies[2], ZOE, "WHISPER")
      -- Bo's O was recorded whole, so Zoé lacks it; Bo's own C is still missing a chunk.
      assert.are.same({ { ZOE, "r00001", RAID, { "cf-00000001" } } }, calls)
    end)

    -- The operations of a reply's O whispers to target, as { id, author, msgid } each in order,
    -- checking they are whole, then the D's body; anything after the D is in rest.
    local function reply(list, target)
      local ops, pieces, rest = {}, {}, {}
      local done
      for _, m in ipairs(list) do
        if done then
          rest[#rest + 1] = m
        else
          assert.are.same({ "WHISPER", target }, { m[2], m[3] })
          if m[1]:sub(1, 2) == "D;" then
            done = m[1]
          else
            local chunk = assert(Sync.ParseChunk(m[1]))
            assert.are.equal("SA0001", chunk.raid)
            pieces[#pieces + 1] = chunk.piece
            if chunk.n == chunk.total then
              local op = assert(ns.OpText.Decode(table.concat(pieces)))
              ops[#ops + 1] = { op.id, chunk.author, chunk.msgid }
              pieces = {}
            end
          end
        end
      end
      assert.are.same({}, pieces)
      return ops, done, rest
    end

    describe("is answered", function()
      local LONG = string.rep("Trés bien; ", 14)

      -- Records held here: Rae's award, Zoé's and Bo's received directly (Bo's with two chunks),
      -- Bo's void of Zoé's, received directly, and Rae's confirm.
      local function hold()
        award("aw-rae00001")
        ns.Hub.Apply({ type = "award", id = "aw-zoe00001", boss = "lb_lucifron", item = 16806,
          char = "Ana Vale", user = "u_ana", method = "SR", at = 1792000100 }, RAID, ZOE)
        ns.Hub.Apply({ type = "award", id = "aw-bo000001", boss = "lb_lucifron", item = 16807,
          char = "Ana Vale", user = "u_ana", method = "SR", note = LONG, at = 1792000200 }, RAID, BO)
        ns.Hub.Apply({ type = "void", id = "vd-bo000001", key = "aw-zoe00001", at = 1792000300 }, RAID, BO)
        assert(ns.Records.Confirm("aw-rae00001", { id = "cf-rae00001" }))
      end

      it("with a whisper of each operation its sender lacks, by its author, in order, then D and the count",
        function()
          hold()
          receive(request({ "aw-zoe00001" })[1], ZOE, "WHISPER")
          local ops, done, rest = reply(sent(), ZOE)
          assert.are.same({ { "aw-rae00001", "Rae Quill" }, { "aw-bo000001", BO }, { "vd-bo000001", BO },
            { "cf-rae00001", "Rae Quill" } }, { { ops[1][1], ops[1][2] }, { ops[2][1], ops[2][2] },
            { ops[3][1], ops[3][2] }, { ops[4][1], ops[4][2] } })
          assert.are.same({ 4, "D;r00001;4", {} }, { #ops, done, rest })
          assert.is_false(logged("operations weren't sent"))
        end)

      it("with chunks of the reply sent again when asked", function()
        hold()
        receive(request({})[1], ZOE, "WHISPER")
        local list = sent()
        local ops = reply(list, ZOE)
        receive("Q;" .. ops[3][3] .. ";2", ZOE, "WHISPER")
        local again = sent()
        assert.are.equal("O;" .. ops[3][3] .. ";2/2", list[4][1]:sub(1, 12))
        assert.are.same({ list[4][1], "WHISPER", ZOE }, again[#again])
      end)

      it("by two add-ons alike, and applying both replies, in any number, leaves one list", function()
        hold()
        receive(request({})[1], ZOE, "WHISPER")
        local list = sent()
        -- Zoé's add-on, holding none, gets the same reply from Rae and from Bo.
        local zoe = wow.start()
        wow.state.player = ZOE
        wow.state.group, wow.state.groupIsRaid = { "Rae Quill", ZOE, BO }, true
        zoe.Raids.Load(assert(zoe.Snapshot.Validate(snapshot(RAID), "0.1.0")), "pasted")
        for _, forwarder in ipairs({ "Rae Quill", BO, "Rae Quill" }) do
          for _, m in ipairs(list) do receive(m[1], forwarder, "WHISPER") end
        end
        local ids, vias = {}, {}
        for n, op in ipairs(zoe.Records.Ops(RAID)) do
          ids[n], vias[n] = op.id, zoe.Records.Via(op.id)
        end
        assert.are.same({ "aw-rae00001", "aw-zoe00001", "aw-bo000001", "vd-bo000001", "cf-rae00001" }, ids)
        -- Rae's own operations came from Rae directly; the others were forwarded.
        assert.are.same({ [2] = "Rae Quill", [3] = "Rae Quill", [4] = "Rae Quill" }, vias)
        local ops = zoe.Records.Ops(RAID)
        assert.are.same({ "Rae Quill", ZOE, BO, BO, "Rae Quill" }, { zoe.Records.Author(ops[1]),
          zoe.Records.Author(ops[2]), zoe.Records.Author(ops[3]), zoe.Records.Author(ops[4]),
          zoe.Records.Author(ops[5]) })
        assert.are.same({ true, "confirmed" }, { zoe.Records.Get("aw-zoe00001").voided,
          zoe.Records.Get("aw-rae00001").state })
        assert.are.same({}, wow.printed)
        -- Nothing received was sent on.
        for _ = 1, 20 do wow.advance(1) end
        assert.are.same({}, wow.addonMessages)
      end)

      it("with only the whole operations that fit the queue, the D counted, then an H, and logs it",
        function()
          hold()
          wow.bossFight(true)
          local ids = { "aw-zoe00001" }
          for i = 1, 95 do
            local op = assert(ns.Records.Award({ boss = "lb_lucifron", item = 16805, char = "Ana Vale",
              user = "u_ana", method = "HR", id = string.format("aw-%08d", i), raid = RAID }))
            assert.is_true(Hub.SendOp(op, RAID))
            ids[#ids + 1] = op.id
          end
          -- Zoé lacks Rae's award, Bo's two-chunk award, the void and the confirm: 5 chunks, with 4
          -- places left in the queue once the D has its own.
          for _, body in ipairs(request(ids)) do receive(body, ZOE, "WHISPER") end
          assert.is_true(logged("the sending queue is full, so 1 of 4 operations weren't sent to Zoé Brûlé; "
            .. "they are sent when Zoé Brûlé asks again."))
          wow.bossFight(false)
          for _ = 1, 100 do wow.advance(1) end
          local list = sent()
          assert.are.equal(101, #list)
          local ops, done, rest = reply({ unpack(list, 96) }, ZOE)
          assert.are.same({ "aw-rae00001", "aw-bo000001", "vd-bo000001" },
            { ops[1][1], ops[2][1], ops[3][1] })
          assert.are.same({ 3, "D;r00001;3" }, { #ops, done })
          local mine = {}
          for n, op in ipairs(ns.Records.Ops(RAID)) do mine[n] = op.id end
          assert.are.same({ { held(mine), "WHISPER", ZOE } }, rest)
        end)

      it("with nothing but an H, logged, when not even one operation and the D fit the queue", function()
        hold()
        wow.bossFight(true)
        local ids = { "aw-zoe00001", "aw-bo000001", "vd-bo000001", "cf-rae00001" }
        for i = 1, 99 do
          local op = assert(ns.Records.Award({ boss = "lb_lucifron", item = 16805, char = "Ana Vale",
            user = "u_ana", method = "HR", id = string.format("aw-%08d", i), raid = RAID }))
          assert.is_true(Hub.SendOp(op, RAID))
          ids[#ids + 1] = op.id
        end
        for _, body in ipairs(request(ids)) do receive(body, ZOE, "WHISPER") end
        assert.is_true(logged("the sending queue is full, so the catch-up reply to Zoé Brûlé wasn't sent."))
        wow.bossFight(false)
        for _ = 1, 110 do wow.advance(1) end
        -- An H follows the queue, so Zoé asks again once it has drained, and gets the award.
        local list = sent()
        local mine = {}
        for n, op in ipairs(ns.Records.Ops(RAID)) do mine[n] = op.id end
        assert.are.same({ 100, { held(mine), "WHISPER", ZOE } }, { #list, list[100] })
        for _, body in ipairs(request(ids, "r00002")) do receive(body, ZOE, "WHISPER") end
        local ops, done, rest = reply({ unpack(sent(), 101) }, ZOE)
        assert.are.same({ "aw-rae00001", "D;r00002;1", {} }, { ops[1][1], done, rest })
      end)
    end)

    it("for a raid that isn't loaded is ignored", function()
      receive(request({}, nil, "SZZZZZ")[1], ZOE, "WHISPER")
      assert.are.same({}, calls)
      assert.is_true(logged("ignored Zoé Brûlé's message for raid SZZZZZ: not loaded."))
    end)

    it("is dropped when malformed, or when its whole list holds an id that isn't valid", function()
      receive("C;r00001;SA0001;1/1;aw 1", ZOE, "WHISPER")
      receive("C;r00002;SA0001;1/1;short", ZOE, "WHISPER")
      assert.are.same({}, calls)
      assert.is_true(logged("dropped a malformed C message from Zoé Brûlé"))
      assert.is_true(logged("dropped Zoé Brûlé's message r00002 (malformed)"))
    end)
  end)
end)

-- Catch-up between add-ons (spec 10.4, #114): officers take turns, each a session of their own
-- add-on with its saved data; a message goes to every officer present, or, whispered, to its target.
describe("Hub catch-up between officers", function()
  local OFFICERS = { ZOE, "Rae Quill", BO }
  local dbs, inbox, present, logs, sentBy, count

  -- One session of officer's add-on. It takes in what waits for it, then options.make's operations
  -- (sent unless options.unsent), and sends for 150 seconds. options.login fires the login or
  -- /reload; options.solo leaves it out of the group.
  local function turn(officer, options)
    options = options or {}
    local ns = wow.start({ saved = { BureaucracyForeverDB = dbs[officer] } })
    wow.state.player = officer
    if not dbs[officer] then
      ns.Raids.Load(assert(ns.Snapshot.Validate(snapshot(RAID), "0.1.0")), "pasted")
      assert.is_true(ns.Selection.ChooseRaid(RAID, true))
    end
    wow.state.group, wow.state.groupIsRaid = not options.solo and OFFICERS or {}, not options.solo
    if options.login ~= nil then wow.fire("PLAYER_ENTERING_WORLD", options.login) end
    -- Who asked this add-on to catch up, this session.
    local asked = {}
    for _, m in ipairs(inbox[officer]) do
      if m[2]:sub(1, 2) == "C;" then asked[m[1]] = true end
      wow.fire("CHAT_MSG_ADDON", "BFLOOT1", m[2], m[3], m[1])
    end
    inbox[officer] = {}
    for _, op in ipairs(options.make and options.make(ns.Records) or {}) do
      if not options.unsent then assert.is_true(ns.Hub.SendOp(op, RAID)) end
    end
    for _ = 1, 150 do wow.advance(1) end
    for _, m in ipairs(wow.addonMessages) do
      local chunk = m.text:sub(1, 2) == "O;" and assert(ns.Sync.ParseChunk(m.text))
      if chunk and chunk.author ~= officer then
        -- A received operation is sent on only in a whisper, to who asked for it.
        assert.are.same({ "WHISPER", true }, { m.channel, asked[m.target] or false })
      end
      table.insert(sentBy[officer], m)
      for _, other in ipairs(OFFICERS) do
        if other ~= officer and present[other] and (m.channel ~= "WHISPER" or m.target == other) then
          table.insert(inbox[other], { officer, m.text, m.channel })
        end
      end
    end
    for _, entry in ipairs(ns.log) do table.insert(logs[officer], entry.text) end
    for _, line in ipairs(wow.printed) do assert.is_nil(line:find("different version", 1, true)) end
    dbs[officer] = BureaucracyForeverDB
    return ns
  end

  -- Turns for every officer present until no message waits.
  local function settle()
    for _ = 1, 20 do
      local waiting = false
      for _, officer in ipairs(OFFICERS) do
        if present[officer] and #inbox[officer] > 0 then
          waiting = true
          turn(officer)
        end
      end
      if not waiting then return end
    end
    error("still sending after 20 rounds")
  end

  -- n awards, made by the officer whose turn it is.
  local function awards(n)
    return function(Records)
      local ops = {}
      for _ = 1, n do
        count = count + 1
        ops[#ops + 1] = assert(Records.Award({ boss = "lb_lucifron", item = 16800 + count % 20,
          char = "Ana Vale", user = "u_" .. count, method = "SR", roll = count,
          note = count % 5 == 0 and string.rep("Trés bien; ", 14) or nil }))
      end
      return ops
    end
  end

  -- What officer's add-on holds now, by id: its operations, records and each operation's author.
  local function holding(officer)
    local ns = wow.start({ saved = { BureaucracyForeverDB = dbs[officer] } })
    wow.state.player = officer
    local ops, records, authors = {}, {}, {}
    for _, op in ipairs(ns.Records.Ops(RAID)) do
      ops[op.id], authors[op.id] = op, ns.Records.Author(op)
    end
    for _, record in ipairs(ns.Raids.Awards(RAID)) do records[record.key] = record end
    return ops, records, authors, ns
  end

  local function size(map)
    local n = 0
    for _ in pairs(map) do n = n + 1 end
    return n
  end

  -- Checks every officer named (all by default) holds the same expected number of operations.
  local function sameEverywhere(expected, officers)
    officers = officers or OFFICERS
    local ops, records, authors = holding(officers[1])
    assert.are.equal(expected, size(ops))
    for i = 2, #officers do
      local others, otherRecords, otherAuthors = holding(officers[i])
      assert.are.same(ops, others)
      assert.are.same(records, otherRecords)
      assert.are.same(authors, otherAuthors)
    end
    return ops, authors
  end

  local function logged(officer, text)
    for _, line in ipairs(logs[officer]) do
      if line:find(text, 1, true) then return true end
    end
    return false
  end

  before_each(function()
    dbs, inbox, present, logs, sentBy, count = {}, {}, {}, {}, {}, 0
    for _, officer in ipairs(OFFICERS) do inbox[officer], logs[officer], sentBy[officer] = {}, {}, {} end
  end)

  it("brings a late officer the same list as the others, from two replies alike", function()
    present[ZOE], present["Rae Quill"] = true, true
    turn(ZOE, { make = awards(6) })
    turn("Rae Quill", { make = awards(5) })
    turn(ZOE, { make = function(Records)
      local first = Records.Ops(RAID)[7].id
      return { assert(Records.Void(first, { reason = "wrong winner" })), (assert(Records.Confirm(first))) }
    end })
    turn("Rae Quill", { make = function(Records)
      local first = Records.Ops(RAID)[1].id
      return { (assert(Records.Replace(first, { boss = "lb_lucifron", item = 16801, char = "Bo Marsh",
        user = "u_bo", method = "SR", roll = 70 }))) }
    end })
    settle()
    -- Bo awarded one item before joining the group, so it was never sent.
    turn(BO, { solo = true, unsent = true, make = awards(1) })
    present[BO] = true
    turn(BO, { login = true })
    settle()

    local ops, authors = sameEverywhere(15)
    local makers = {}
    for _, officer in ipairs(OFFICERS) do
      for _, m in ipairs(sentBy[officer]) do
        local chunk = m.text:sub(1, 2) == "O;" and m.channel ~= "WHISPER" and wow.ns.Sync.ParseChunk(m.text)
        if chunk then makers[chunk.author] = true end
      end
    end
    for id in pairs(ops) do
      assert.is_truthy(authors[id] == ZOE or authors[id] == "Rae Quill" or authors[id] == BO)
    end
    assert.are.same({ [ZOE] = true, ["Rae Quill"] = true }, makers)
    -- Both Zoé and Rae answered Bo, with the same operations; each forwarded copy keeps its forwarder.
    local answered = {}
    for _, officer in ipairs({ ZOE, "Rae Quill" }) do
      for _, m in ipairs(sentBy[officer]) do
        if m.target == BO and m.text:sub(1, 2) == "D;" then answered[officer] = m.text:match("(%d+)$") end
      end
    end
    assert.are.same({ [ZOE] = "14", ["Rae Quill"] = "14" }, answered)
    local _, _, _, bo = holding(BO)
    for id in pairs(ops) do
      local via = bo.Records.Via(id)
      if via then assert.are_not.equal(authors[id], via) end
    end
    -- Bo's own award reached the others from Bo, when they asked for it.
    local _, _, _, rae = holding("Rae Quill")
    for id, author in pairs(authors) do
      if author == BO then assert.is_nil(rae.Records.Via(id)) end
    end
  end)

  it("brings an officer who reloads mid-run what was sent while away", function()
    for _, officer in ipairs(OFFICERS) do present[officer] = true end
    turn(ZOE, { make = awards(4) })
    turn(BO, { make = awards(3) })
    settle()
    -- Rae reloads: what is sent meanwhile never reaches her.
    present["Rae Quill"] = false
    turn(ZOE, { make = awards(3) })
    turn(BO, { make = function(Records)
      local zoes = Records.Ops(RAID)[1].id
      return { assert(Records.Void(zoes, { reason = "traded" })),
        (assert(Records.NotConfirmed(Records.Ops(RAID)[2].id))) }
    end })
    settle()
    present["Rae Quill"] = true
    turn("Rae Quill", { login = false })
    settle()
    local _, authors = sameEverywhere(12)
    local _, _, _, rae = holding("Rae Quill")
    -- Zoé answered first: her own awards came direct, Bo's void and not-confirmed forwarded by her.
    local forwarded = {}
    for id, author in pairs(authors) do
      local via = rae.Records.Via(id)
      if via then forwarded[#forwarded + 1] = author .. " via " .. via end
    end
    assert.are.same({ "Bo Marsh via Zoé Brûlé", "Bo Marsh via Zoé Brûlé" }, forwarded)
  end)

  it("sends a reply larger than the queue in rounds until the lists match", function()
    present[ZOE] = true
    turn(ZOE, { solo = true, unsent = true, make = awards(130) })
    present["Rae Quill"] = true
    turn("Rae Quill", { login = true })
    settle()
    sameEverywhere(130, { ZOE, "Rae Quill" })
    assert.is_true(logged(ZOE, "operations weren't sent to Rae Quill; they are sent when Rae Quill asks "
      .. "again."))
    local replies = {}
    for _, m in ipairs(sentBy[ZOE]) do
      if m.text:sub(1, 2) == "D;" then replies[#replies + 1] = tonumber(m.text:match("(%d+)$")) end
    end
    assert.is_true(#replies >= 2)
    local total = 0
    for _, n in ipairs(replies) do total = total + n end
    assert.are.equal(130, total)
  end)
end)
