local wow = require("spec.support.wow")

local URL = "https://github.com/robpaolella/bureaucracy-forever-addon/releases/latest"

local function tree(id, addon)
  return {
    formatVersion = 1, raid = id, code = "S" .. id:sub(-5):upper(), env = "staging", name = "Molten Core",
    startsAt = 1792000000, durationMin = 240, generated = 1791990000,
    addon = addon, bosses = {}, awards = {}, reserves = {},
  }
end

describe("the update notice", function()
  local ns, N

  before_each(function()
    ns = wow.start()
    N = ns.Notice
  end)

  local function load(version, id, origin)
    local snapshot = assert(ns.Snapshot.Validate(
      tree(id or "raid00001", { version = version, url = URL }), ns.version))
    ns.Raids.Load(snapshot, origin or "pasted")
  end

  local function texts()
    local out = { N.frame.lead.text, N.frame.hint.text, N.frame.link.text }
    for _, b in ipairs(N.frame.buttons) do
      if b:IsShown() then out[#out + 1] = b.label.text end
    end
    return table.concat(out, "\n")
  end

  it("shows the version, the copyable link and Close when the snapshot names a newer version", function()
    load("1.3.0")
    assert.is_true(N.frame:IsShown())
    assert.matches("|cffffffffBureaucracy Forever|r", N.frame.lead.text, 1, true)
    assert.matches("A newer .* is out: |cff40ff401.3.0|r %(you have 0.0.0%-dev%)%.", N.frame.lead.text)
    assert.equals("Copy the link (Ctrl+C), download it, replace the add-on folder, then /reload. "
      .. "The desktop helper updates it for you.", N.frame.hint.text)
    assert.equals(URL, N.frame.link.text)
    assert.is_true(N.frame.link:IsShown())
    assert.is_true(N.frame.link.focused)
    assert.is_true(N.frame.link.highlighted)
    assert.is_true(N.frame.icon:IsShown())
    assert.is_true(N.frame.buttons[1]:IsShown())
    assert.equals("Close", N.frame.buttons[1].label.text)
    assert.is_false(N.frame.buttons[2]:IsShown())
  end)

  it("puts the link back when it is typed in", function()
    load("1.3.0")
    N.frame.link:SetText("changed")
    N.frame.link.scripts.OnTextChanged(N.frame.link, true)
    assert.equals(URL, N.frame.link.text)
  end)

  it("shows nothing for the same version, an older one or an unreadable one", function()
    for _, version in ipairs({ "0.0.0", "0.0.0-dev", "garbage", "" }) do
      load(version)
    end
    assert.is_false(N.frame:IsShown())
  end)

  it("shows nothing when the snapshot is loaded from the inbox with no newer version", function()
    ns.Raids.ReplaceInbox({ assert(ns.Snapshot.Validate(tree("raid00001", { version = "0.0.0", url = URL }),
      ns.version)) })
    assert.is_false(N.frame:IsShown())
  end)

  it("shows for a snapshot from the inbox", function()
    ns.Raids.ReplaceInbox({ assert(ns.Snapshot.Validate(tree("raid00001", { version = "2.0.0", url = URL }),
      ns.version)) })
    assert.is_true(N.frame:IsShown())
    assert.matches("2.0.0", texts())
  end)

  it("shows for a pasted snapshot", function()
    ns.Selection.Paste("BFSNAP1:1/1:{ formatVersion = 1, raid = \"raid00002\", code = \"S00002\", "
      .. "env = \"staging\", name = \"Onyxia\", startsAt = 1792000000, durationMin = 120, "
      .. "generated = 1791990000, addon = { version = \"1.0.0\", url = \"" .. URL .. "\" }, "
      .. "bosses = {}, reserves = {}, awards = {} }")
    assert.is_true(N.frame:IsShown())
    assert.matches("1.0.0", N.frame.lead.text)
  end)

  it("closes with Close and stays closed for the same version", function()
    load("1.3.0")
    wow.click(function() N.frame.buttons[1].scripts.OnClick(N.frame.buttons[1]) end)
    assert.is_false(N.frame:IsShown())
    load("1.3.0", "raid00002")
    load("1.2.0", "raid00003")
    assert.is_false(N.frame:IsShown())
  end)

  it("shows again for a still newer version", function()
    load("1.3.0")
    N.frame.buttons[1].scripts.OnClick(N.frame.buttons[1])
    load("1.4.0", "raid00002")
    assert.is_true(N.frame:IsShown())
    assert.matches("1.4.0", N.frame.lead.text)
  end)

  it("shows again at the next login", function()
    load("1.3.0")
    ns = wow.start()
    N = ns.Notice
    load("1.3.0")
    assert.is_true(N.frame:IsShown())
  end)

  it("closes with Escape", function()
    load("1.3.0")
    local found = false
    for _, name in ipairs(UISpecialFrames) do
      if name == "BureaucracyForeverNotice" then found = true end
    end
    assert.is_true(found)
  end)

  describe("in a boss fight", function()
    it("waits until the fight ends, then shows once", function()
      wow.bossFight(true)
      load("1.3.0")
      assert.is_false(N.frame:IsShown())
      assert.is_not_nil(N.Pending())
      wow.bossFight(false)
      assert.is_true(N.frame:IsShown())
      assert.is_nil(N.Pending())
      N.frame.buttons[1].scripts.OnClick(N.frame.buttons[1])
      wow.fire("ENCOUNTER_END", 1, "Boss", 0, 5, 1)
      assert.is_false(N.frame:IsShown())
    end)

    it("shows only the newest version raised during the fight", function()
      wow.bossFight(true)
      load("1.3.0")
      load("1.4.0", "raid00002")
      wow.bossFight(false)
      assert.matches("1.4.0", N.frame.lead.text)
    end)

    it("shows nothing at the end of a fight when none is waiting", function()
      wow.bossFight(true)
      wow.bossFight(false)
      assert.is_false(N.frame:IsShown())
    end)
  end)

  describe("the shared window", function()
    it("draws a notice with its own buttons and runs the clicked one's action after closing", function()
      local ran
      N.Raise("handover", { lead = "You're now the loot master.", hint = "More.",
        buttons = { { label = "Open awards", onClick = function() ran = N.frame:IsShown() end },
          { label = "OK" } } })
      assert.is_false(N.frame.icon:IsShown())
      assert.is_false(N.frame.link:IsShown())
      assert.equals("Open awards", N.frame.buttons[1].label.text)
      assert.equals("OK", N.frame.buttons[2].label.text)
      N.frame.buttons[1].scripts.OnClick(N.frame.buttons[1])
      assert.is_false(ran)
      assert.is_false(N.frame:IsShown())
    end)
  end)
end)

describe("the loot master handover notice", function()
  local ns, N
  local ME = "Masterlooter"

  local function masterIs(index) -- raid index of the loot master; 0 is the player
    wow.state.lootMethod = { "master", index == 0 and 0 or nil, index }
    wow.fire("PARTY_LOOT_METHOD_CHANGED")
  end

  before_each(function()
    ns = wow.start()
    N = ns.Notice
    wow.state.group = { ME, "Konvett-Realm", "Other" }
    wow.state.groupIsRaid = true
    wow.state.lootMethod = { "master", nil, 2 }
    wow.fire("PLAYER_ENTERING_WORLD", false, false)
  end)

  local function addAwards(n)
    local snapshot = assert(ns.Snapshot.Validate({
      formatVersion = 1, raid = "raid00001", code = "SRAID1", env = "staging", name = "Molten Core",
      startsAt = 1792000000, durationMin = 240, generated = 1791990000,
      addon = { version = "0.0.0", url = URL }, bosses = {},
      awards = {}, reserves = {},
    }, ns.version))
    ns.Raids.Load(snapshot, "pasted")
    ns.db.activeRaid = "raid00001"
    ns.db.awards = { raid00001 = {} }
    for i = 1, n do ns.db.awards.raid00001[i] = { char = "X" } end
  end

  it("names the previous loot master and the awards held, with Open awards and OK", function()
    addAwards(12)
    masterIs(0)
    assert.is_true(N.frame:IsShown())
    assert.equals("|cffffffffYou're now the loot master.|r", N.frame.lead.text)
    assert.equals("Konvett's 12 awards are loaded as history. Your add-on now hands out and records "
      .. "awards, and other officers' add-ons follow you.", N.frame.hint.text)
    assert.is_false(N.frame.icon:IsShown())
    assert.equals("Open awards", N.frame.buttons[1].label.text)
    assert.equals("OK", N.frame.buttons[2].label.text)
  end)

  it("reads 0 with no raid selected, and 1 award in the singular", function()
    masterIs(0)
    assert.matches("Konvett's 0 awards", N.frame.hint.text)
    N.frame.buttons[2].scripts.OnClick(N.frame.buttons[2])
    wow.state.lootMethod = { "master", nil, 2 }
    wow.fire("PARTY_LOOT_METHOD_CHANGED")
    addAwards(1)
    masterIs(0)
    assert.matches("Konvett's 1 award is", N.frame.hint.text)
  end)

  it("shows nothing for a change to someone else", function()
    wow.state.lootMethod = { "master", nil, 3 }
    wow.fire("PARTY_LOOT_METHOD_CHANGED")
    assert.is_false(N.frame:IsShown())
  end)

  it("shows nothing when no loot master was seen before", function()
    wow.state.lootMethod = { "group", 0, 0 }
    ns = wow.start()
    wow.state.group = { ME, "Konvett" }
    wow.fire("PLAYER_ENTERING_WORLD", false, false)
    masterIs(0)
    assert.is_false(ns.Notice.frame:IsShown())
  end)

  it("Open awards opens the window on the Awards tab and closes the notice; OK closes it", function()
    masterIs(0)
    wow.click(function() N.frame.buttons[1].scripts.OnClick(N.frame.buttons[1]) end)
    assert.is_false(N.frame:IsShown())
    assert.is_true(ns.UI.window:IsShown())
    assert.equals("Awards", ns.UI.selected)
    masterIs(2)
    masterIs(0)
    N.frame.buttons[2].scripts.OnClick(N.frame.buttons[2])
    assert.is_false(N.frame:IsShown())
  end)

  it("still shows after a /reload, since the first look at the world seeds the memory", function()
    ns = wow.start()
    N = ns.Notice
    wow.state.group = { ME, "Konvett" }
    wow.state.groupIsRaid = true
    wow.state.lootMethod = { "master", nil, 2 }
    wow.fire("PLAYER_ENTERING_WORLD", false, true)
    masterIs(0)
    assert.is_true(N.frame:IsShown())
  end)

  it("keeps the last loot master when master loot goes off and on", function()
    wow.state.lootMethod = { "group", 0, 0 }
    wow.fire("PARTY_LOOT_METHOD_CHANGED")
    masterIs(0)
    assert.matches("Konvett's", N.frame.hint.text)
  end)

  it("forgets the previous loot master on leaving the group", function()
    wow.state.group = {}
    wow.fire("GROUP_ROSTER_UPDATE")
    wow.state.group = { ME, "Other" }
    wow.state.lootMethod = { "group", 0, 0 }
    wow.fire("GROUP_ROSTER_UPDATE")
    masterIs(0)
    assert.is_false(N.frame:IsShown())
  end)

  it("waits for the end of a boss fight, and the pop-up stays", function()
    wow.bossFight(true)
    wow.openLoot({ { link = "|cffa335ee|Hitem:1:::::::::::::|h[Choker]|h|r", name = "Choker", quality = 4,
      quantity = 1, candidates = { ME } } })
    masterIs(0)
    assert.is_false(N.frame:IsShown())
    assert.is_table(ns.Popup.Build())
    assert.equals("handover", N.Pending().key)
    wow.bossFight(false)
    assert.is_true(N.frame:IsShown())
    assert.equals("handover", N.Shown().key)
    assert.is_table(ns.Popup.Build())
  end)
end)

describe("the update notice at login", function()
  local function inboxWith(version)
    local snapshot = tree("raid00001", { version = version, url = URL })
    snapshot.instance = 409
    return { formatVersion = 1, written = 1791999940, raids = { { snapshot = snapshot } } }
  end

  it("shows when the inbox's raid names a newer version, though the inbox loads before the window", function()
    local ns = wow.start({ inbox = inboxWith("9.0.0") })
    local N = ns.Notice
    assert.equals("update", N.Shown().key)
    assert.is_true(N.frame:IsShown())
    assert.matches("is out: |cff40ff409.0.0|r", N.frame.lead.text, 1, true)
    assert.equals(URL, N.frame.link.text)
    assert.is_nil(N.Pending())
  end)

  it("does not raise a second notice for the same version from a pasted snapshot", function()
    local ns = wow.start({ inbox = inboxWith("9.0.0") })
    local N = ns.Notice
    N.frame:Hide()
    local snapshot = assert(ns.Snapshot.Validate(
      tree("raid00002", { version = "9.0.0", url = URL }), ns.version))
    ns.Raids.Load(snapshot, "pasted")
    assert.is_false(N.frame:IsShown())
    assert.is_nil(N.Pending())
  end)
end)
