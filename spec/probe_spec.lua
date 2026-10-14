-- luacheck: globals BFProbeDB
-- Tests for BF Probe v5's lines test (the throwaway add-on in spec/probe/), run in the game
-- stand-in. The stand-in blocks every chat line sent from a timer, so these show the "blocked"
-- path and the no-group and no-rights cases. Whether the game itself lets party, raid and
-- raid warning lines through is what the beta test decides.
local wow = require("spec.support.wow")

describe("BF Probe v5 /bfprobe lines", function()
  local group

  local function lines() return table.concat(wow.printed, "\n") end

  local function logged()
    return table.concat(BFProbeDB.log, "\n")
  end

  before_each(function()
    wow.start()
    group = { raid = false, party = false, leader = false, assistant = false }
    _G.IsInRaid = function() return group.raid end
    _G.IsInGroup = function() return group.raid or group.party end
    _G.UnitIsGroupLeader = function() return group.leader end
    _G.UnitIsGroupAssistant = function() return group.assistant end
    _G.IsInInstance = function() return false, "none" end
    _G.GetInstanceInfo = function() return "Eastern Kingdoms" end
    _G.InCombatLockdown = function() return false end
    _G.UnitFullName = function() return "Konvett", "Konvett" end
    local chunk = assert(loadfile("spec/probe/BFProbe.lua"))
    chunk("BFProbe")
    wow.fire("ADDON_LOADED", "BFProbe")
    wow.printed = {}
  end)

  after_each(function()
    for _, name in ipairs({ "IsInRaid", "IsInGroup", "UnitIsGroupLeader", "UnitIsGroupAssistant",
      "IsInInstance", "GetInstanceInfo", "InCombatLockdown", "UnitFullName", "BFProbeDB" }) do
      _G[name] = nil
    end
  end)

  it("says so, and sends nothing, when not in a party or raid", function()
    wow.slash("/bfprobe lines")
    wow.advance(5)
    assert.matches("aren.t in a party or raid", lines())
    assert.are.same({}, wow.sent)
    assert.are.same({}, wow.blocked)
    assert.matches("nothing to send", logged())
  end)

  it("tries a party line from the timer, and logs it blocked", function()
    group.party = true
    wow.slash("/bfprobe lines")
    wow.advance(2)
    assert.are.same({}, wow.blocked)
    wow.advance(1)
    assert.are.same({ "SendChatMessage" }, wow.blocked)
    assert.matches("party line: blocked", lines())
    assert.matches("LINES_PARTY ; party line; call ok true; blocked", logged())
    assert.matches("ADDON_ACTION_BLOCKED", logged())
  end)

  it("tries a raid line and a raid warning for a raid leader", function()
    group.raid, group.leader = true, true
    wow.slash("/bfprobe lines")
    wow.advance(3)
    assert.are.same({ "SendChatMessage", "SendChatMessage" }, wow.blocked)
    assert.matches("raid line: blocked", lines())
    assert.matches("raid warning: blocked", lines())
    assert.matches("LINES_RAID_WARNING", logged())
  end)

  it("allows the raid warning for an assistant", function()
    group.raid, group.assistant = true, true
    wow.slash("/bfprobe lines")
    wow.advance(3)
    assert.matches("raid warning: blocked", lines())
  end)

  it("skips the raid warning, and says why, without raid rights", function()
    group.raid = true
    wow.slash("/bfprobe lines")
    assert.matches("no raid warning is tried", lines())
    wow.advance(3)
    assert.are.same({ "SendChatMessage" }, wow.blocked)
    assert.matches("raid line: blocked", lines())
    assert.is_nil(lines():match("raid warning: "))
    assert.matches("no raid warning is tried", logged())
  end)

  it("reports an error from the game call instead of raising it", function()
    group.party = true
    _G.C_ChatInfo.SendChatMessage = function() error("boom") end
    wow.slash("/bfprobe lines")
    wow.advance(3)
    assert.matches("party line: error: .*boom", lines())
  end)

  it("lists the command in the help", function()
    wow.slash("/bfprobe")
    assert.matches("/bfprobe lines", lines())
  end)
end)
