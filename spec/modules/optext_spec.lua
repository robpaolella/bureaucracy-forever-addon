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
end)
