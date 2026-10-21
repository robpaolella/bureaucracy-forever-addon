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
