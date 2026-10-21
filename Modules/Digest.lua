-- Digest: what an add-on holds for a raid, as H sends it (ADDON-SPEC.md 10.2; #20). The sum,
-- modulo 2^32, of the CRC-32 of every operation id held, as eight lower-case hex digits. Lua 5.1
-- has no bit library, so the CRC-32 is plain arithmetic on whole numbers below 2^32.
local _, ns = ...

local Digest = {}
ns.Digest = Digest

local TWO32 = 4294967296
local POLY = 0xEDB88320 -- CRC-32 (IEEE), reflected

-- The exclusive or of two whole numbers below 2^32.
local function xor(a, b)
  local result, bit = 0, 1
  while a > 0 or b > 0 do
    if a % 2 ~= b % 2 then result = result + bit end
    a, b, bit = math.floor(a / 2), math.floor(b / 2), bit * 2
  end
  return result
end

local TABLE = {}
for n = 0, 255 do
  local c = n
  for _ = 1, 8 do
    if c % 2 == 1 then c = xor(math.floor(c / 2), POLY) else c = math.floor(c / 2) end
  end
  TABLE[n] = c
end

-- The CRC-32 of the text's bytes, as a number.
function Digest.Crc32(text)
  local crc = TWO32 - 1
  for i = 1, #text do
    crc = xor(TABLE[xor(crc % 256, text:byte(i))], math.floor(crc / 256))
  end
  return TWO32 - 1 - crc
end

-- The digest of a list of operation ids: eight lower-case hex digits.
function Digest.Of(ids)
  local sum = 0
  for _, id in ipairs(ids) do sum = (sum + Digest.Crc32(id)) % TWO32 end
  -- Two halves: "%x" of a number past 2^31 depends on the C long, 32 bits on some builds.
  return string.format("%04x%04x", math.floor(sum / 65536), sum % 65536)
end
