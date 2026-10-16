local wow = require("spec.support.wow")

describe("OpText", function()
  local OpText

  before_each(function()
    OpText = wow.start().OpText
  end)

  local award = {
    type = "award", id = "aw-7f3k2m9q", boss = "lb_lucifron", item = 16805, char = "Ana Vale",
    user = "u_ana", method = "HR", roll = 91, sender = "Rae Quill", at = 1792001200,
  }

  it("escapes % ; < > | and control bytes as %XX, and leaves accents alone", function()
    assert.are.equal("100%25%3B%3C%3E%7C%0A%7F%09 Zoë", OpText.Escape("100%;<>|\n\127\t Zoë"))
    assert.are.equal("", OpText.Escape(nil))
  end)

  it("writes an award with empty optional fields and an empty practice field", function()
    assert.are.equal("A;aw-7f3k2m9q;lb_lucifron;16805;Ana Vale;u_ana;HR;91;;Rae Quill;1792001200;",
      OpText.Encode(award))
  end)

  it("marks practice as 1", function()
    local practice = { type = "confirm", id = "cf-1x8p4d2s", key = "aw-7f3k2m9q", at = 5, practice = true }
    assert.are.equal("K;cf-1x8p4d2s;aw-7f3k2m9q;5;1", OpText.Encode(practice))
  end)

  it("writes not-confirmed and void", function()
    assert.are.equal("N;nc-12345678;aw-7f3k2m9q;7;",
      OpText.Encode({ type = "not-confirmed", id = "nc-12345678", key = "aw-7f3k2m9q", at = 7 }))
    assert.are.equal("V;vd-5b2n8c1w;aw-8d3c5n2a;wrong winner;1792001260;",
      OpText.Encode({ type = "void", id = "vd-5b2n8c1w", key = "aw-8d3c5n2a",
        reason = "wrong winner", at = 1792001260 }))
  end)

  it("writes a replace with its own fields, then the new award's, taking the replace's practice", function()
    local new = { id = "aw-2h6j9z4b", boss = "lb_lucifron", item = 16805, char = "Bo Marsh",
      user = "u_bo", method = "SR", roll = 77, sender = "Rae Quill", at = 1792001300 }
    assert.are.equal(
      "R;rp-9c4v6t0e;aw-7f3k2m9q;1792001300;;aw-2h6j9z4b;" ..
      "lb_lucifron;16805;Bo Marsh;u_bo;SR;77;;Rae Quill;1792001300",
      OpText.Encode({ type = "replace", id = "rp-9c4v6t0e", key = "aw-7f3k2m9q", at = 1792001300,
        award = new }))
  end)

  it("refuses an unknown type", function()
    assert.has_error(function() OpText.Encode({ type = "bogus" }) end)
  end)

  describe("Decode", function()
    local new = { id = "aw-2h6j9z4b", boss = "lb_lucifron", item = 16805, char = "Bo Marsh",
      user = "u_bo", method = "SR", roll = 77, sender = "Rae Quill", at = 1792001300 }

    local ops = {
      award = award,
      ["an award with accents, a note to escape and no user or roll"] = { type = "award",
        id = "aw-3k9d2m1x", boss = "lb_trash", item = 17011, char = "Zoé Brûlé", method = "OPEN_ROLL",
        note = "100% <sure>; |cffff0000 not a colour|r\nline two", sender = "Zoé Brûlé", at = 1 },
      confirm = { type = "confirm", id = "cf-1x8p4d2s", key = "aw-7f3k2m9q", at = 5, practice = true },
      ["not-confirmed"] = { type = "not-confirmed", id = "nc-12345678", key = "aw-7f3k2m9q", at = 7 },
      void = { type = "void", id = "vd-5b2n8c1w", key = "aw-8d3c5n2a", reason = "wrong winner;", at = 9 },
      ["void with no reason"] = { type = "void", id = "vd-5b2n8c1x", key = "aw-8d3c5n2a", at = 9 },
      replace = { type = "replace", id = "rp-9c4v6t0e", key = "aw-7f3k2m9q", at = 1792001300,
        practice = true, award = new },
    }

    for name, op in pairs(ops) do
      it("gives back the same " .. name, function()
        local text = OpText.Encode(op)
        local decoded = assert(OpText.Decode(text))
        assert.are.same(op, decoded)
        assert.are.equal(text, OpText.Encode(decoded))
      end)
    end

    it("keeps identical item copies apart by their ids", function()
      local copy = {}
      for k, v in pairs(award) do copy[k] = v end
      copy.id = "aw-7f3k2m9r"
      assert.are.same(award, OpText.Decode(OpText.Encode(award)))
      assert.are.same(copy, OpText.Decode(OpText.Encode(copy)))
    end)

    local malformed = {
      ["an unknown type"] = "X;aw-7f3k2m9q;aw-1;5;",
      ["an empty text"] = "",
      ["a field too few"] = "K;cf-1x8p4d2s;aw-7f3k2m9q;5",
      ["a field too many"] = "K;cf-1x8p4d2s;aw-7f3k2m9q;5;;",
      ["a replace missing its award's time"] =
        "R;rp-9c4v6t0e;aw-7f3k2m9q;1;;aw-2h6j9z4b;lb_x;16805;Bo Marsh;u_bo;SR;77;;Rae Quill",
      ["a % with no hex digits"] = "V;vd-5b2n8c1w;aw-8d3c5n2a;100%;9;",
      ["a % with one hex digit"] = "V;vd-5b2n8c1w;aw-8d3c5n2a;%4;9;",
      ["a % with a non-hex digit"] = "V;vd-5b2n8c1w;aw-8d3c5n2a;%4G;9;",
      ["a raw byte that is always escaped"] = "V;vd-5b2n8c1w;aw-8d3c5n2a;a|b;9;",
      ["a raw control byte"] = "V;vd-5b2n8c1w;aw-8d3c5n2a;a\tb;9;",
      ["bad UTF-8"] = "V;vd-5b2n8c1w;aw-8d3c5n2a;caf\233;9;",
      ["bad UTF-8 from an escape"] = "V;vd-5b2n8c1w;aw-8d3c5n2a;caf%E9;9;",
      ["a cut UTF-8 character"] = "V;vd-5b2n8c1w;aw-8d3c5n2a;caf\195;9;",
      ["an overlong UTF-8 form"] = "V;vd-5b2n8c1w;aw-8d3c5n2a;\192\175;9;",
      ["a UTF-16 surrogate"] = "V;vd-5b2n8c1w;aw-8d3c5n2a;\237\160\128;9;",
      ["a practice field other than 1"] = "K;cf-1x8p4d2s;aw-7f3k2m9q;5;yes",
      ["a time that isn't a whole number"] = "K;cf-1x8p4d2s;aw-7f3k2m9q;5.5;",
      ["an item that isn't a number"] = "A;aw-7f3k2m9q;lb_x;item;Ana Vale;u_ana;HR;91;;Rae Quill;1;",
      ["a negative roll"] = "A;aw-7f3k2m9q;lb_x;16805;Ana Vale;u_ana;HR;-1;;Rae Quill;1;",
    }

    for name, text in pairs(malformed) do
      it("reports " .. name .. " as malformed", function()
        local op, err = OpText.Decode(text)
        assert.is_nil(op)
        assert.are.equal("malformed", err)
      end)
    end

    it("accepts valid UTF-8 of every length", function()
      assert.is_true(OpText.ValidUtf8("a é € 𐍈"))
      assert.is_false(OpText.ValidUtf8("\244\144\128\128"))
    end)
  end)
end)
