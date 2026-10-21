local wow = require("spec.support.wow")

-- Known values from a standard CRC-32 (IEEE, as zlib's crc32 gives).
describe("Digest", function()
  local Digest

  before_each(function()
    Digest = wow.start().Digest
  end)

  local known = {
    { "", 0x00000000 },
    { "a", 0xe8b7be43 },
    { "123456789", 0xcbf43926 },
    { "The quick brown fox jumps over the lazy dog", 0x414fa339 },
    { "aw-9d2f6h1j", 0xdff3b5fb },
    { "Zoé Brûlé", 0xb3e4cb30 },
    { "\255", 0xff000000 },
  }
  for _, case in ipairs(known) do
    it("gives the CRC-32 of " .. string.format("%q", case[1]), function()
      assert.are.equal(case[2], Digest.Crc32(case[1]))
    end)
  end

  it("is 00000000 for no ids", function()
    assert.are.equal("00000000", Digest.Of({}))
  end)

  it("is one id's CRC-32 as eight lower-case hex digits", function()
    assert.are.equal("dff3b5fb", Digest.Of({ "aw-9d2f6h1j" }))
    assert.are.equal("711b79dd", Digest.Of({ "aw-6k1m4v8z" }))
  end)

  it("sums modulo 2^32, wrapping past it", function()
    -- 4fdb61fd + d6d23047 = 1 26ad9244.
    assert.are.equal("26ad9244", Digest.Of({ "aw-00000001", "aw-00000002" }))
  end)

  it("doesn't depend on the order of the ids", function()
    local ids = { "aw-9d2f6h1j", "rp-3n7b5x0c", "aw-6k1m4v8z" }
    assert.are.equal(Digest.Of(ids), Digest.Of({ ids[3], ids[1], ids[2] }))
    assert.are_not.equal(Digest.Of(ids), Digest.Of({ ids[1], ids[2] }))
  end)
end)
