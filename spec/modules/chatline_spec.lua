local wow = require("spec.support.wow")

describe("OpText.BuildLine", function()
  local build
  local NONE = {} -- stands for a field the test clears
  local LINK = "|cffa335ee|Hitem:16805::::::::60:::::::|h[Felheart Gloves]|h|r"

  before_each(function()
    build = wow.start().OpText.BuildLine
  end)

  local function award(extra)
    local data = { raid = "SA0001", key = "aw-9d2f6h1j", item = 16805, link = LINK, boss = "lb_lucifron",
      method = "HR", roll = 91, winner = "Zoé Brûlé" }
    for k, v in pairs(extra or {}) do
      if v == NONE then v = nil end
      data[k] = v
    end
    return data
  end

  local function correction(extra)
    local data = award({ id = "rp-3n7b5x0c", key = "aw-9d2f6h1j", newKey = "aw-6k1m4v8z", method = "SR",
      roll = 77, winner = "Bo Marsh", oldWinner = "Zoé Brûlé" })
    for k, v in pairs(extra or {}) do
      if v == NONE then v = nil end
      data[k] = v
    end
    return data
  end

  local function undo(extra)
    local data = { raid = "SA0001", id = "vd-2s9t4w7y", key = "aw-9d2f6h1j", link = LINK,
      winner = "Zoé Brûlé" }
    for k, v in pairs(extra or {}) do
      if v == NONE then v = nil end
      data[k] = v
    end
    return data
  end

  describe("human wording and the spec's machine parts (9.7)", function()
    it("award, hard reserve", function()
      assert.are.equal(LINK .. " → Zoé Brûlé (hard reserve) "
        .. "<BF1;A;SA0001;aw-9d2f6h1j;16805;ifron;HR;91;Zoé Brûlé>",
        build("award", award()))
    end)

    it("award, soft reserve", function()
      assert.are.equal(LINK .. " → Bo Marsh (soft reserve) "
        .. "<BF1;A;SA0001;aw-9d2f6h1j;16805;ifron;SR;;Bo Marsh>",
        build("award", award({ method = "SR", roll = NONE, winner = "Bo Marsh" })))
    end)

    it("award, open roll with its number", function()
      assert.are.equal(LINK .. " → Bo Marsh (open roll, 87) "
        .. "<BF1;A;SA0001;aw-9d2f6h1j;16805;ifron;OPEN_ROLL;87;Bo Marsh>",
        build("award", award({ method = "OPEN_ROLL", roll = 87, winner = "Bo Marsh" })))
    end)

    it("award, disenchant/bank with no winner", function()
      assert.are.equal(LINK .. " → disenchant/bank <BF1;A;SA0001;aw-9d2f6h1j;16805;ifron;DISENCHANT_BANK;;>",
        build("award", award({ method = "DISENCHANT_BANK", roll = NONE, winner = NONE })))
    end)

    it("a practice line starts [Practice] and uses BF1P", function()
      assert.are.equal("[Practice] " .. LINK .. " → Zoé Brûlé (hard reserve) "
        .. "<BF1P;A;SA0001;aw-9d2f6h1j;16805;ifron;HR;91;Zoé Brûlé>",
        build("award", award({ practice = true })))
    end)

    it("undo", function()
      assert.are.equal("Undo: " .. LINK .. " is no longer awarded to Zoé Brûlé "
        .. "<BF1;V;SA0001;vd-2s9t4w7y;aw-9d2f6h1j>",
        build("undo", undo()))
    end)

    it("undo of a disenchant/bank", function()
      assert.are.equal("Undo: " .. LINK .. " is no longer going to disenchant/bank "
        .. "<BF1;V;SA0001;vd-2s9t4w7y;aw-9d2f6h1j>", build("undo", undo({ winner = NONE })))
    end)

    it("correction carries the whole new award", function()
      assert.are.equal("Correction: " .. LINK .. " → Bo Marsh (soft reserve), not Zoé Brûlé "
        .. "<BF1;R;SA0001;rp-3n7b5x0c;aw-9d2f6h1j;aw-6k1m4v8z;16805;ifron;SR;77;Bo Marsh>",
        build("correction", correction()))
    end)

    it("correction to disenchant/bank", function()
      assert.are.equal("Correction: " .. LINK .. " → disenchant/bank, not Zoé Brûlé "
        .. "<BF1;R;SA0001;rp-3n7b5x0c;aw-9d2f6h1j;aw-6k1m4v8z;16805;ifron;DISENCHANT_BANK;;>",
        build("correction", correction({ method = "DISENCHANT_BANK", roll = NONE, winner = NONE })))
    end)

    it("correction away from disenchant/bank", function()
      assert.are.equal("Correction: " .. LINK .. " → Bo Marsh (open roll, 50), not disenchant/bank "
        .. "<BF1;R;SA0001;rp-3n7b5x0c;aw-9d2f6h1j;aw-6k1m4v8z;16805;ifron;OPEN_ROLL;50;Bo Marsh>",
        build("correction", correction({ method = "OPEN_ROLL", roll = 50, oldWinner = NONE })))
    end)

    it("keeps the last five characters of the boss id, lower-case", function()
      assert.is_truthy(build("award", award({ boss = "LB_LUCIFRON" })):find(";ifron;", 1, true))
    end)

    it("escapes ; and % in a winner's machine field but not in the human part", function()
      local line = build("award", award({ winner = "A;b%c" }))
      assert.is_truthy(line:find("→ A;b%c (hard reserve)", 1, true))
      assert.is_truthy(line:find(";HR;91;A%3Bb%25c>", 1, true))
    end)
  end)

  describe("what can't be built", function()
    local function refused(operation, data, pattern)
      local line, reason = build(operation, data)
      assert.is_nil(line)
      assert.is_truthy(reason:find(pattern))
    end

    it("a winner with <, > or | in the name", function()
      for _, bad in ipairs({ "A<b", "A>b", "A|b" }) do
        refused("award", award({ winner = bad }), "plain text")
        refused("undo", undo({ winner = bad }), "plain text")
        refused("correction", correction({ oldWinner = bad }), "plain text")
      end
    end)

    it("an open roll with no roll number", function()
      refused("award", award({ method = "OPEN_ROLL", roll = NONE }), "roll number")
    end)

    it("a method other than HR, SR, open roll or disenchant/bank", function()
      refused("award", award({ method = "MAIN_SPEC" }), "MAIN_SPEC")
      refused("correction", correction({ method = "OFF_SPEC" }), "OFF_SPEC")
      refused("award", award({ method = "NOPE" }), "NOPE")
      refused("award", award({ method = NONE }), "not built")
    end)

    it("a key or id over 24 characters", function()
      local long = string.rep("a", 25)
      refused("award", award({ key = long }), "over 24")
      refused("undo", undo({ id = long }), "over 24")
      refused("correction", correction({ newKey = long }), "over 24")
      assert.is_string(build("award", award({ key = string.rep("a", 24) })))
    end)

    it("bad fields", function()
      refused("award", award({ raid = "X00001" }), "raid code")
      refused("award", award({ key = NONE }), "key")
      refused("award", award({ item = 0 }), "item id")
      refused("award", award({ item = 12345678 }), "item id")
      refused("award", award({ item = 99 }), "does not match")
      refused("award", award({ roll = 101 }), "roll")
      refused("award", award({ winner = NONE }), "winner is missing")
      refused("award", award({ method = "DISENCHANT_BANK", roll = NONE }), "no winner")
      refused("award", award({ boss = "abc" }), "boss")
      refused("award", award({ link = NONE }), "link")
      refused("correction", correction({ newKey = "aw-9d2f6h1j" }), "equals")
      refused("undo", undo({ link = "[no link]" }), "item link")
      refused("recall", award(), "unknown operation")
    end)
  end)

  describe("giving way to 255 bytes (9.1a)", function()
    -- A link padded so the full line is just over 255 bytes, then each step is needed in turn.
    local function padded(_, size)
      return LINK:gsub("%[Felheart Gloves%]", "[" .. string.rep("x", size) .. "]")
    end

    -- The largest padding for which the line still has a given wording, found by trying sizes.
    local function firstSizeWhere(operation, data, wanted)
      for size = 1, 200 do
        data.link = padded(nil, size)
        local line = build(operation, data)
        if line and line:find(wanted, 1, true) then return size, line end
      end
    end

    local function machineOf(line) return line:match("<BF1.->$") end

    local function steps(operation, data)
      local seen, last = {}, nil
      for size = 1, 200 do
        data.link = padded(nil, size)
        local line = build(operation, data)
        local human = line and line:gsub(" <BF1.->$", "")
        if human then
          local shape = human:gsub("%[x+%]", "[]")
          if shape ~= last then seen[#seen + 1] = { shape = shape, line = line, size = size } end
          last = shape
        end
      end
      return seen
    end

    local function shapes(operation, data)
      local out = {}
      for _, step in ipairs(steps(operation, data)) do out[#out + 1] = step.shape end
      return out
    end

    local ITEM = "|cffa335ee|Hitem:16805::::::::60:::::::|h[]|h|r"

    it("a correction loses ' not old', then the parenthesis, then the name, then the label", function()
      -- Shapes are listed from the smallest link up, so the fullest wording comes first.
      local got = shapes("correction", correction({ oldWinner = string.rep("Q", 30) }))
      assert.are.same({
        "Correction: " .. ITEM .. " → Bo Marsh (soft reserve), not " .. string.rep("Q", 30),
        "Correction: " .. ITEM .. " → Bo Marsh (soft reserve)",
        "Correction: " .. ITEM .. " → Bo Marsh",
        "Correction: " .. ITEM,
        ITEM,
      }, got)
    end)

    it("an award loses the parenthesis, then the name", function()
      assert.are.same({
        ITEM .. " → Zoé Brûlé (hard reserve)",
        ITEM .. " → Zoé Brûlé",
        ITEM,
      }, shapes("award", award({ winner = "Zoé Brûlé" })))
    end)

    it("an undo loses the name, then the label", function()
      assert.are.same({
        "Undo: " .. ITEM .. " is no longer awarded to Zoé Brûlé",
        "Undo: " .. ITEM,
        ITEM,
      }, shapes("undo", undo()))
    end)

    it("a disenchant/bank award loses its words at the name step", function()
      assert.are.same({ ITEM .. " → disenchant/bank", ITEM },
        shapes("award", award({ method = "DISENCHANT_BANK", roll = NONE, winner = NONE })))
    end)

    it("an undo of a disenchant/bank loses its words at the name step, then the label", function()
      assert.are.same({
        "Undo: " .. ITEM .. " is no longer going to disenchant/bank",
        "Undo: " .. ITEM,
        ITEM,
      }, shapes("undo", undo({ winner = NONE })))
    end)

    it("corrections to and from disenchant/bank lose ' not …' first, then the name step", function()
      assert.are.same({
        "Correction: " .. ITEM .. " → disenchant/bank, not " .. string.rep("Q", 30),
        "Correction: " .. ITEM .. " → disenchant/bank",
        "Correction: " .. ITEM,
        ITEM,
      }, shapes("correction", correction({ method = "DISENCHANT_BANK", roll = NONE, winner = NONE,
        oldWinner = string.rep("Q", 30) })))
      assert.are.same({
        "Correction: " .. ITEM .. " → Bo Marsh (soft reserve), not disenchant/bank",
        "Correction: " .. ITEM .. " → Bo Marsh (soft reserve)",
        "Correction: " .. ITEM .. " → Bo Marsh",
        "Correction: " .. ITEM,
        ITEM,
      }, shapes("correction", correction({ oldWinner = NONE })))
    end)

    it("never shortens the machine part, and every line is at most 255 bytes", function()
      local data = correction({ oldWinner = string.rep("Q", 30) })
      local full = build("correction", correction({ oldWinner = string.rep("Q", 30) }))
      local machine = machineOf(full)
      for _, step in ipairs(steps("correction", data)) do
        assert.are.equal(machine, machineOf(step.line))
        assert.is_true(#step.line <= 255)
      end
    end)

    it("keeps [Practice] and returns nil when even that can't fit", function()
      local data = correction({ practice = true, link = padded(nil, 120) })
      local line, reason = build("correction", data)
      assert.is_nil(line)
      assert.is_truthy(reason:find("255"))
      data.link = padded(nil, 1)
      assert.are.equal("[Practice] ", build("correction", data):sub(1, 11))
      local size, shortest = firstSizeWhere("award", award({ practice = true }), "[Practice] |cffa")
      assert.is_number(size)
      assert.are.equal("[Practice] ", shortest:sub(1, 11))
    end)

    it("returns nil with a reason when the link alone is too long", function()
      local line, reason = build("award", award({ link = padded(nil, 250) }))
      assert.is_nil(line)
      assert.is_truthy(reason:find("255"))
    end)
  end)
end)
