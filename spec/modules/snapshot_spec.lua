local wow = require("spec.support.wow")

-- The worked snapshot of ADDON-SPEC.md 3.3, as one line (its line breaks don't matter).
local EXAMPLE = (([[
{
  formatVersion = 1, raid = "cm9xr2k4a0001", code = "SA0001", env = "staging",
  name = "Molten Core - sample", startsAt = 1792000000, durationMin = 240,
  instance = 409, generated = 1791990000,
  addon = { version = "0.1.0",
    url = "https://github.com/robpaolella/bureaucracy-forever-addon/releases/latest" },
  bosses = {
    { id = "lb_lucifron", name = "Lucifron", trash = false, items = { 16800, 16805 } },
    { id = "lb_magmadar", name = "Magmadar", trash = false, items = { 16796, 16805 } },
    { id = "lb_trash", name = "Trash", trash = true, items = { 17011, 18861 } },
  },
  reserves = {
    [16805] = {
      { user = "u_ana", char = "Ana Vale", kind = "HR", trial = false },
      { user = "u_bo", char = "Bo Marsh", kind = "SR", trial = false },
      { user = "u_cy", char = "Cy Orchard", kind = "SR", trial = true },
    },
    [16796] = {
      { user = "u_bo", char = "Bo Marsh", kind = "HR", trial = false, blocked = "win-limit" },
    },
  },
  awards = {
    { key = "site-0001abcd", boss = "lb_trash", item = 18861, char = "Dee Holt",
      user = "u_dee", method = "OPEN_ROLL", roll = 64, voided = false },
  },
}
]]):gsub("%s*\n%s*", " ")):match("^%s*(.-)%s*$")

-- The example with one plain-text substitution, such as dropping a field.
local function edit(from, to)
  local start, finish = EXAMPLE:find(from, 1, true)
  assert(start, "the example has no " .. from)
  return EXAMPLE:sub(1, start - 1) .. to .. EXAMPLE:sub(finish + 1)
end

local function paste(text) return "BFSNAP1:1/1:" .. text end

-- Cuts text into n pasted parts, numbered in order.
local function cut(text, n)
  local size, parts = math.ceil(#text / n), {}
  for i = 1, n do
    parts[i] = string.format("BFSNAP1:%d/%d:%s", i, n, text:sub((i - 1) * size + 1, i * size))
  end
  return parts
end

describe("Sync.ReadPasted", function()
  local ns, Sync

  before_each(function()
    ns = wow.start()
    ns.version = "0.1.0"
    Sync = ns.Sync
  end)

  local function refused(pasted, pattern)
    local snapshot, err = Sync.ReadPasted(pasted)
    assert.is_nil(snapshot)
    assert.is_string(err)
    if pattern then assert.is_truthy(err:find(pattern, 1, true), err) end
    return err
  end

  it("reads the spec's worked snapshot exactly as Lua would", function()
    local snapshot, notice = Sync.ReadPasted(paste(EXAMPLE))
    -- Lua runs the literal here only to give the expected value; the add-on never does.
    assert.are.same(assert(loadstring("return " .. EXAMPLE))(), snapshot)
    assert.is_nil(notice)
    assert.are.equal("win-limit", snapshot.reserves[16796][1].blocked)
  end)

  it("reads pasted text whose lines are in one string, with the game's line endings", function()
    local parts = cut(EXAMPLE, 3)
    assert.is_table(Sync.ReadPasted(table.concat(parts, "\r\n") .. "\n"))
  end)

  describe("parts", function()
    it("accepts two parts only once both arrive, in either order", function()
      local parts = cut(EXAMPLE, 2)
      assert.are.equal("Still waiting for part 2 of 2. Paste the rest to load the raid.",
        refused({ parts[1] }))
      refused({ parts[2] }, "part 1 of 2")
      assert.is_table(Sync.ReadPasted({ parts[1], parts[2] }))
      assert.is_table(Sync.ReadPasted({ parts[2], parts[1] }))
    end)

    it("names every missing part, and counts the rest past five", function()
      local parts = cut(EXAMPLE, 9)
      refused({ parts[1], parts[4] }, "parts 2, 3, 5, 6, 7 and 2 more of 9")
    end)

    it("returns the missing part numbers from the assembler", function()
      local _, _, missing = ns.Snapshot.Assemble({ cut(EXAMPLE, 3)[2] })
      assert.are.same({ 1, 3 }, missing)
    end)

    it("accepts the same part pasted twice", function()
      local parts = cut(EXAMPLE, 2)
      assert.is_table(Sync.ReadPasted({ parts[1], parts[1], parts[2] }))
    end)

    it("refuses parts from different copies", function()
      local parts = cut(EXAMPLE, 2)
      refused({ parts[1], cut(EXAMPLE, 3)[2] }, "different copies")
      refused({ parts[1], "BFSNAP1:1/2:{}", parts[2] }, "different copies")
    end)

    it("refuses text that isn't the reserves text, and nothing at all", function()
      refused("hello", "isn't the reserves text")
      refused({ paste(EXAMPLE), "a stray line" }, "isn't the reserves text")
      refused("BFSNAP2:1/1:{}", "isn't the reserves text")
      refused({ "", "  " }, "Paste the reserves text")
    end)

    it("refuses impossible part numbers", function()
      refused("BFSNAP1:0/1:{}", "damaged")
      refused("BFSNAP1:3/2:{}", "damaged")
      refused("BFSNAP1:1/0:{}", "damaged")
      refused("BFSNAP1:1/999999999:{}", "damaged")
    end)
  end)

  describe("versions", function()
    it("refuses a newer formatVersion, saying to update the add-on", function()
      local err = refused(paste(edit("formatVersion = 1", "formatVersion = 2")), "Update the add-on")
      assert.is_falsy(err:find("Version", 1, true), err)
    end)

    it("adds the notice to the refusal when the snapshot names a newer add-on", function()
      local text = edit("formatVersion = 1", "formatVersion = 2"):gsub('"0%.1%.0"', '"0.2.0"')
      refused(paste(text), "Update the add-on, then paste it again. Version 0.2.0 of the add-on is out "
        .. "(you have 0.1.0). Download it from https://github.com/robpaolella/bureaucracy-forever-addon"
        .. "/releases/latest.")
    end)

    it("loads a snapshot naming a newer add-on, with the notice", function()
      ns.version = "0.0.9"
      local snapshot, notice = Sync.ReadPasted(paste(EXAMPLE))
      assert.is_table(snapshot)
      assert.are.equal("Version 0.1.0 of the add-on is out (you have 0.0.9). Download it from "
        .. "https://github.com/robpaolella/bureaucracy-forever-addon/releases/latest.", notice)
    end)

    it("refuses a formatVersion it doesn't know", function()
      refused(paste(edit("formatVersion = 1", "formatVersion = 0")), "formatVersion")
    end)

    it("compares versions as dotted numbers, ignoring a suffix", function()
      local IsNewer = ns.Snapshot.IsNewer
      assert.is_true(IsNewer("0.10.0", "0.9.1"))
      assert.is_true(IsNewer("1.0.1", "1.0"))
      assert.is_true(IsNewer("0.1.0", "0.0.0-dev"))
      assert.is_false(IsNewer("1.0.0-beta", "1.0.0"))
      assert.is_false(IsNewer("1.0.0", "1.0.0"))
      assert.is_false(IsNewer("0.9.9", "1.0.0"))
      assert.is_false(IsNewer("two", "1.0.0"))
      assert.is_false(IsNewer("2.0.0", nil))
      assert.is_false(IsNewer("2..0", "1.0.0"))
    end)

    it("shows a | in the notice as text, not as a game code", function()
      local notice = ns.Snapshot.UpdateNotice({ version = "2.0.0", url = "x|cffff0000y" }, "1.0.0")
      assert.is_truthy(notice:find("x||cffff0000y", 1, true))
    end)
  end)

  describe("fields", function()
    it("loads a raid with no instance", function()
      local snapshot = Sync.ReadPasted(paste(edit("instance = 409, ", "")))
      assert.is_table(snapshot)
      assert.is_nil(snapshot.instance)
    end)

    it("keeps a boss row's encounter, and leaves it absent when there is none", function()
      local snapshot = Sync.ReadPasted(paste(edit('name = "Lucifron", trash = false,',
        'name = "Lucifron", trash = false, encounter = 663,')))
      assert.are.equal(663, snapshot.bosses[1].encounter)
      assert.is_nil(snapshot.bosses[2].encounter)
    end)

    it("refuses an encounter that is not a whole number", function()
      local from = 'name = "Lucifron", trash = false,'
      refused(paste(edit(from, from .. ' encounter = "663",')), "bosses 1, encounter has the wrong type")
      refused(paste(edit(from, from .. " encounter = 6.5,")), "whole numbers")
    end)

    it("ignores unknown fields, leaving them out of the snapshot", function()
      local text = edit("formatVersion = 1,", 'formatVersion = 1, colour = "red", extra = { 1, { a = 2 } },')
      text = text:gsub('trial = true }', 'trial = true, mood = "keen" }')
      local snapshot = Sync.ReadPasted(paste(text))
      assert.are.same(assert(loadstring("return " .. EXAMPLE))(), snapshot)
    end)

    it("accepts an award with no user or roll, and a disenchant with no character", function()
      local snapshot = Sync.ReadPasted(paste(edit(
        'char = "Dee Holt", user = "u_dee", method = "OPEN_ROLL", roll = 64,',
        'method = "DISENCHANT_BANK",')))
      assert.are.same({ key = "site-0001abcd", boss = "lb_trash", item = 18861,
        method = "DISENCHANT_BANK", voided = false }, snapshot.awards[1])
    end)

    it("accepts a raid with no loot table", function()
      local text = edit(EXAMPLE:match("bosses = %b{}"), "bosses = {}")
      text = text:gsub("reserves = %b{}", "reserves = {}"):gsub("awards = %b{}", "awards = {}")
      assert.is_table(Sync.ReadPasted(paste(text)))
    end)

    it("refuses a missing required field, naming it", function()
      refused(paste(edit("durationMin = 240, ", "")), "durationMin is missing")
      refused(paste(edit('char = "Dee Holt", ', "")), "awards 1, char is missing")
      refused(paste(edit('kind = "SR", trial = true', 'kind = "SR"')), "reserves 16805 3, trial is missing")
      refused(paste(edit(' url = "https://github.com/robpaolella/bureaucracy-forever-addon/releases/latest"',
        "")), "addon, url is missing")
    end)

    it("refuses a value of the wrong type", function()
      refused(paste(edit("durationMin = 240", 'durationMin = "240"')), "durationMin has the wrong type")
      refused(paste(edit('env = "staging"', 'env = "dev"')), "env has the wrong type")
      refused(paste(edit('kind = "HR"', 'kind = "MS"')), "kind has the wrong type")
      refused(paste(edit("trash = true", "trash = 1")), "bosses 3, trash has the wrong type")
      refused(paste(edit('"OPEN_ROLL"', '"TYPO"')), "awards 1, method has the wrong type")
      refused(paste(edit("roll = 64", "roll = 101")), "awards 1, roll has the wrong type")
      refused(paste(edit("roll = 64", "roll = 0")), "awards 1, roll has the wrong type")
      refused(paste(edit("items = { 17011, 18861 }", 'items = { 17011, "18861" }')), "items 2")
      refused(paste(edit("bosses = {", "bosses = { [5] = {}, ")), "bosses should be a list")
      refused(paste(edit("[16796] = {", "x = {")), "reserves should be keyed by item number")
      refused(paste(edit("[16796] = {", '[16796] = "Bo", [1] = {')), "reserves 16796 should be a list")
      refused(paste("{ 1, 2 }"), "formatVersion is missing")
      refused(paste('"just text"'), "isn't a raid snapshot")
    end)

    it("refuses a float, with no rounding", function()
      refused(paste(edit("durationMin = 240", "durationMin = 240.5")), "whole numbers")
      refused(paste(edit("durationMin = 240", "durationMin = 2e2")), "whole numbers")
      refused(paste(edit("durationMin = 240", "durationMin = 0x10")), "whole numbers")
    end)
  end)

  describe("the grammar", function()
    local Parse

    before_each(function() Parse = ns.Snapshot.Parse end)

    it("reads every kind of value and both kinds of key", function()
      assert.are.same({ 1, -2, true, false, "a", { x = { [7] = "y" } } },
        Parse(' { 1 , -2,true,false, "a", { x = { [ 7 ] = "y" } }, } '))
      assert.are.same({}, Parse("{}"))
      assert.are.equal(9007199254740991, Parse("9007199254740991"))
      assert.are.equal(-9007199254740991, Parse("-9007199254740991"))
    end)

    it("reads only the allowed escapes", function()
      assert.are.equal('a\\b"c\nd\195\171', Parse([["a\\b\"c\010d\195\171"]]))
      for _, bad in ipairs({ [["\n"]], [["\x41"]], [["\65"]], [["\256"]], [["\z"]], [["\]] }) do
        local value, err = Parse(bad)
        assert.is_nil(value, bad)
        assert.is_string(err, bad)
      end
    end)

    it("refuses unescaped bytes outside printable ASCII in a string", function()
      assert.is_nil(Parse('"Zo\195\171"'))
      assert.is_nil(Parse('"a\tb"'))
    end)

    it("refuses anything outside the grammar", function()
      for _, bad in ipairs({
        "", "{", "}", "{ 1 2 }", "{ ,}", "{ a }", "{ a = }", "{ [1.5] = 1 }", '{ ["a"] = 1 }',
        "{ a = 1; b = 2 }", "nil", "{ a = nil }", "- 1", "--x\n{}", "{} {}", "'single'",
        "[[long]]", "{ a = 1, a = 2 }", "{ [1] = 1, 2 }", "9007199254740992", "12345678901234567",
        "truex", "{ true = 1 }", '"no end',
      }) do
        local value, err = Parse(bad)
        assert.is_nil(value, bad)
        assert.is_truthy(err and err:find("The reserves text is damaged near character", 1, true), bad)
      end
    end)
  end)

  describe("limits", function()
    it("allows depth 8 and refuses depth 9", function()
      assert.is_table(Sync.ReadPasted(paste(edit("formatVersion = 1,",
        "formatVersion = 1, extra = {{{{{{{}}}}}}},"))))
      refused(paste(edit("formatVersion = 1,", "formatVersion = 1, extra = {{{{{{{{}}}}}}}},")),
        "deeper than 8 levels")
    end)

    it("allows a 200-byte string and refuses a 201-byte one", function()
      assert.is_table(Sync.ReadPasted(paste(edit("Molten Core - sample", ("a"):rep(200)))))
      refused(paste(edit("Molten Core - sample", ("a"):rep(201))), "longer than 200 characters")
      -- An escape counts as the one byte it stands for.
      assert.is_table(Sync.ReadPasted(paste(edit("Molten Core - sample", ("\\010"):rep(200)))))
    end)

    it("refuses text over 200,000 bytes, and allows it at the limit", function()
      local fill = 200000 - #EXAMPLE
      assert.is_table(Sync.ReadPasted(cut(EXAMPLE:sub(1, -2) .. (" "):rep(fill) .. "}", 29)))
      refused(cut(EXAMPLE:sub(1, -2) .. (" "):rep(fill + 1) .. "}", 29), "over 200,000 characters")
      assert.is_nil(ns.Snapshot.Parse(("1"):rep(200001)))
    end)

    it("refuses a whole number past the safe range in validation too", function()
      local tree = assert(loadstring("return " .. EXAMPLE))()
      tree.durationMin = 2 ^ 60
      local snapshot, err = ns.Snapshot.Validate(tree, "1.0.0")
      assert.is_nil(snapshot)
      assert.is_truthy(err:find("durationMin has the wrong type", 1, true), err)
    end)
  end)

  describe("text holding Lua code", function()
    after_each(function() _G.HACKED = nil end)

    it("keeps code inside a string as text, never running it", function()
      local code = "]] HACKED = true --[[ ]=] print(1)"
      local snapshot = Sync.ReadPasted(paste(edit("Molten Core - sample", code)))
      assert.are.equal(code, snapshot.name)
      assert.is_nil(_G.HACKED)
    end)

    it("refuses code outside a string, never running it", function()
      local guard = function() error("the add-on tried to run text") end
      local saved = { loadstring = _G.loadstring, load = _G.load, dofile = _G.dofile }
      _G.loadstring, _G.load, _G.dofile = guard, guard, guard
      local ok, err = pcall(function()
        refused(paste(edit('name = "Molten Core - sample"', "name = (function() HACKED = true end)()")),
          "damaged")
        refused(paste(edit("durationMin = 240", "durationMin = os.time()")), "damaged")
        refused(paste('{ formatVersion = 1 } HACKED = true'), "damaged")
        refused(paste(edit('"Molten Core - sample"', '"a" .. "b"')), "damaged")
      end)
      _G.loadstring, _G.load, _G.dofile = saved.loadstring, saved.load, saved.dofile
      assert(ok, err)
      assert.is_nil(_G.HACKED)
    end)
  end)

  it("changes no saved data", function()
    Sync.ReadPasted(paste(EXAMPLE))
    Sync.ReadPasted("BFSNAP1:1/2:{")
    assert.are.same({}, BureaucracyForeverDB)
  end)
end)
