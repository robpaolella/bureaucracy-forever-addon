local wow = require("spec.support.wow")

local NOW = 1792000000
local ZOE, BO = "Zoé Brûlé", "Bo Marsh"
local MC = { name = "Molten Core", id = 409, type = "raid" }
local ONY = { name = "Onyxia's Lair", id = 249, type = "raid" }
local ZG = { name = "Zul'Gurub", id = 309, type = "raid" }
local OUTSIDE = { name = "Eastern Kingdoms", id = 0, type = "none" }

local function holder(user, char, kind)
  return { user = user, char = char, kind = kind, trial = false }
end

-- A raid's snapshot as the site's tree; fields override the rest. Molten Core, under way.
local function raidTree(id, fields)
  local tree = {
    formatVersion = 1, raid = id, code = "S" .. id:sub(-5):upper(), env = "staging", name = "Molten Core",
    startsAt = NOW - 1800, durationMin = 240, instance = 409, generated = NOW - 10000,
    addon = { version = "0.0.0", url = "https://example.invalid/addon" },
    bosses = {}, awards = {},
    reserves = { [100] = { holder("u1", "Ashla Brightwater", "HR"), holder("u2", "Doran Vale", "SR") } },
  }
  for k, v in pairs(fields or {}) do tree[k] = v end
  return tree
end

local MC_RAID = raidTree("raid00001")
local ONY_RAID = raidTree("raid00002", { name = "Onyxia's Lair", instance = 249, startsAt = NOW + 7200 })
local MC_TWO = raidTree("raid00003", { name = "Molten Core: second team", startsAt = NOW - 900 })

local function day(tree) return os.date("%a %d %b", tree.startsAt) end
local function white(text) return "|cffffffff" .. text .. "|r" end
local function matches(text) return text .. " |cff40ff40Matches|r" end

describe("the raid question", function()
  local ns

  local function receive(body, sender)
    wow.fire("CHAT_MSG_ADDON", "BFLOOT1", body, "RAID", sender)
  end

  -- The session: player in a raid group with the others, the raids loaded, logged in outside.
  -- options: player, group, users (the others running the add-on), raids, leader, lootMethod.
  local function start(options)
    options = options or {}
    ns = wow.start()
    wow.state.player = options.player or "Konvett"
    wow.state.group = options.group or { wow.state.player, ZOE, BO }
    wow.state.groupIsRaid = options.groupIsRaid ~= false
    wow.state.groupLeader = options.leader or wow.state.player
    wow.state.lootMethod = options.lootMethod or { "master", 0, 0 }
    for _, tree in ipairs(options.raids or { MC_RAID, ONY_RAID }) do
      ns.Raids.Load(assert(ns.Snapshot.Validate(tree, "0.0.0")), "inbox")
    end
    wow.fire("PLAYER_ENTERING_WORLD", true, false)
    for _, name in ipairs(options.users or {}) do receive("P;0", name) end
  end

  -- A loading screen into instance, then the wait (5 seconds unless given).
  local function enter(instance, seconds, reloading)
    wow.state.instance = instance
    wow.fire("PLAYER_ENTERING_WORLD", false, reloading or false)
    wow.advance(seconds or 5)
  end

  local function frame() return ns.StartQuestion.frame end

  -- What the question shows: its texts, rows ({ picked, name, facts }) and buttons ({ label, enabled }).
  local function view()
    local f = frame()
    if not f:IsShown() then return nil end
    local rows, buttons = {}, {}
    for _, r in ipairs(f.rows) do
      if r:IsShown() then
        local on = r.radio:GetText() == ns.UI.parts.RADIO[true]
        rows[#rows + 1] = { on, r.name:GetText(), r.facts:GetText() }
      end
    end
    for _, b in ipairs(f.buttons) do
      if b:IsShown() then buttons[#buttons + 1] = { b.label:GetText(), b:IsEnabled() } end
    end
    return { title = f.title:GetText(), lead = f.lead:GetText(),
      hint = f.hint:IsShown() and f.hint:GetText() or nil,
      note = f.note:IsShown() and f.note.text:GetText() or nil, rows = rows, buttons = buttons }
  end

  local function press(label)
    for _, b in ipairs(frame().buttons) do
      if b:IsShown() and b.label:GetText() == label then
        assert.is_true(b:IsEnabled(), label .. " is disabled")
        return wow.click(function() b.scripts.OnClick(b) end)
      end
    end
    error("no button " .. label)
  end

  local function pick(i)
    local r = frame().rows[i]
    wow.click(function() r.scripts.OnClick(r) end)
  end

  local function selection() return { ns.db.activeBy, ns.db.activeRaid, ns.db.chosenBy } end

  local function selectionMessages()
    local list = {}
    for _, m in ipairs(wow.addonMessages) do
      if m.text:find("^S;") then list[#list + 1] = m.text end
    end
    return list
  end

  local function awards(raidId, count)
    ns.db.awards = ns.db.awards or {}
    ns.db.awards[raidId] = {}
    for i = 1, count do
      ns.db.awards[raidId][i] = { key = "k" .. i, item = 100, char = "Ashla", method = "HR" }
    end
  end

  local MC_ROW = { white(matches("Molten Core, " .. day(MC_RAID))),
    "Under way since " .. os.date("%H:%M", MC_RAID.startsAt) .. " · 2 players" }
  local ONY_ROW = { white("Onyxia's Lair, " .. day(ONY_RAID)),
    "Starts " .. os.date("%H:%M", ONY_RAID.startsAt) .. " · 2 players" }
  local OFF_ROW = { white("No, not a guild run"), "The add-on stays off until you leave the group" }
  local function picked(on, r) return { on, r[1], r[2] } end

  describe("on entering a raid instance in a raid group", function()
    it("asks the chooser after waiting 5 seconds, by a timer, drawing only (ask-raid)", function()
      start({ users = { ZOE } })
      wow.state.instance = MC
      wow.fire("PLAYER_ENTERING_WORLD", false, false)
      wow.advance(4.9)
      assert.is_nil(view())
      wow.advance(0.1)
      assert.are.same({
        title = "Is this a guild run?",
        lead = "You've entered " .. white("Molten Core") .. " with a raid group. If it's a guild run, "
          .. "pick its raid event. If not, choose the last option.",
        rows = { picked(true, MC_ROW), picked(false, ONY_ROW), picked(false, OFF_ROW) },
        buttons = { { "Start", true }, { "Decide later", true } },
      }, view())
      assert.are.same({}, wow.sent)
      assert.are.same({}, wow.blocked)
      assert.are.same({}, selectionMessages())
      assert.are.equal("none", ns.Selection.ActiveBy())
    end)

    it("chooses the picked raid on Start and shares it with the group", function()
      start({ users = { ZOE } })
      enter(MC)
      press("Start")
      assert.is_nil(view())
      assert.are.same({ "chosen", "raid00001", "Konvett" }, selection())
      assert.are.same({ "S;S00001;" .. NOW .. ";Konvett" }, selectionMessages())
      assert.are.same({}, wow.sent)
    end)

    it("can pick another raid instead of the suggestion", function()
      start()
      enter(MC)
      pick(2)
      assert.are.same({ picked(false, MC_ROW), picked(true, ONY_ROW), picked(false, OFF_ROW) }, view().rows)
      press("Start")
      assert.are.same({ "chosen", "raid00002", "Konvett" }, selection())
    end)

    it("pre-selects none when two raids for the instance are under way (ask-overlap)", function()
      start({ raids = { MC_RAID, MC_TWO, ONY_RAID } })
      enter(MC)
      local v = view()
      assert.are.equal("You've entered " .. white("Molten Core") .. " with a raid group. Two raid events for "
        .. "Molten Core are under way. Which one is this?", v.lead)
      assert.are.same({ picked(false, MC_ROW),
        { false, white(matches("Molten Core: second team, " .. day(MC_TWO))),
          "Under way since " .. os.date("%H:%M", MC_TWO.startsAt) .. " · 2 players" },
        picked(false, ONY_ROW), picked(false, OFF_ROW) }, v.rows)
      assert.are.same({ { "Start", false }, { "Decide later", true } }, v.buttons)
      pick(2)
      assert.are.same({ "Start", true }, view().buttons[1])
      press("Start")
      assert.are.same({ "chosen", "raid00003", "Konvett" }, selection())
    end)

    it("pre-selects none when two raids for the instance start at the same soonest time", function()
      local later = raidTree("raid00004", { name = "Onyxia's Lair: second team", instance = 249,
        startsAt = ONY_RAID.startsAt })
      start({ raids = { MC_RAID, ONY_RAID, later } })
      enter(ONY)
      local v = view()
      assert.are.equal("You've entered " .. white("Onyxia's Lair") .. " with a raid group. If it's a guild "
        .. "run, pick its raid event. If not, choose the last option.", v.lead)
      for i = 1, 4 do assert.is_false(v.rows[i][1]) end
      assert.are.same({ "Start", false }, v.buttons[1])
    end)

    it("names the instance and lists the raids anyway when none matches (ask-nomatch)", function()
      start()
      enter(ZG)
      assert.are.same({
        title = "Is this a guild run?",
        lead = "You've entered " .. white("Zul'Gurub") .. " with a raid group.",
        hint = "No raid event is set for Zul'Gurub (instance 309). If this is a custom raid, an officer can "
          .. "enter 309 as its In-game instance number on the guild site.",
        rows = { { false, white("Molten Core, " .. day(MC_RAID)), MC_ROW[2] }, picked(false, ONY_ROW),
          picked(false, OFF_ROW) },
        buttons = { { "Start", false }, { "Decide later", true } },
      }, view())
    end)

    it("says so when master loot is off (ask-fallback)", function()
      start({ lootMethod = { "group", 0, 0 } })
      enter(MC)
      assert.are.equal("You're asked because master loot is off and you lead the raid. Turn master loot on "
        .. "to hand out items with the pop-up.", view().note)
      assert.are.same(picked(true, MC_ROW), view().rows[1])
      start({ lootMethod = { "group", 0, 0 }, leader = "Cy Stone", group = { "Konvett", ZOE, "Cy Stone" } })
      enter(MC)
      assert.are.equal("You're asked because master loot is off. Turn master loot on to hand out items with "
        .. "the pop-up.", view().note)
    end)

    it("has no note when master loot is on", function()
      start()
      enter(MC)
      assert.is_nil(view().note)
    end)

    it("says there is no raid to choose when none is loaded", function()
      start({ raids = {} })
      enter(MC)
      assert.are.same({
        title = "Is this a guild run?",
        lead = "You've entered " .. white("Molten Core") .. " with a raid group. Is this a guild run?",
        hint = "There's no raid event to choose: no raids are loaded. If it's a guild run, choose Decide "
          .. "later, then choose the raid in the Sync tab once one loads.",
        rows = { picked(false, OFF_ROW) },
        buttons = { { "Start", false }, { "Decide later", true } },
      }, view())
      pick(1)
      press("Start")
      assert.are.same({ "off", nil, "Konvett" }, selection())
    end)

    it("records nothing for not a guild run, and never asks again in that group", function()
      start()
      enter(MC)
      pick(3)
      press("Start")
      assert.are.same({ "off", nil, "Konvett" }, selection())
      assert.are.same({ "S;-;" .. NOW .. ";Konvett" }, selectionMessages())
      enter(ONY)
      assert.is_nil(view())
    end)

    it("leaves the selection on Decide later, and asks again on the next entry, the same one too", function()
      start()
      enter(MC)
      press("Decide later")
      assert.is_nil(view())
      assert.are.equal("none", ns.Selection.ActiveBy())
      assert.are.same({}, selectionMessages())
      enter(OUTSIDE)
      assert.is_nil(view())
      enter(MC)
      assert.are.equal("Is this a guild run?", view().title)
    end)

    it("closes with Escape, changing nothing, as Decide later does", function()
      start()
      enter(MC)
      frame():Hide()
      assert.is_nil(ns.StartQuestion.Shown())
      assert.are.equal("none", ns.Selection.ActiveBy())
    end)
  end)

  describe("who is asked", function()
    -- Each add-on in the group, as the players in users, hears P from the others and enters.
    local function asked(users, options)
      local list = {}
      for _, player in ipairs(users) do
        local others = {}
        for _, other in ipairs(users) do
          if other ~= player then others[#others + 1] = other end
        end
        start({ player = player, group = { "Konvett", ZOE, BO, "Cy Stone" }, users = others,
          leader = options.leader, lootMethod = options.lootMethod })
        enter(MC)
        if view() then list[#list + 1] = player end
      end
      return list
    end

    local USERS = { "Konvett", ZOE, BO }

    it("is the loot master when master loot is on and they run the add-on", function()
      assert.are.same({ BO }, asked(USERS, { lootMethod = { "master", 2, 3 }, leader = ZOE }))
    end)

    it("is the raid leader when the loot master doesn't run it, or master loot is off", function()
      assert.are.same({ ZOE }, asked(USERS, { lootMethod = { "master", 3, 4 }, leader = ZOE }))
      assert.are.same({ ZOE }, asked(USERS, { lootMethod = { "group", 0, 0 }, leader = ZOE }))
    end)

    it("is the first add-on user by name when neither runs it", function()
      assert.are.same({ BO }, asked(USERS, { lootMethod = { "master", 3, 4 }, leader = "Cy Stone" }))
    end)

    it("is the new chooser, in the instance, when the one asked leaves the group", function()
      start({ group = { "Konvett", ZOE, BO }, users = { ZOE }, leader = ZOE, lootMethod = { "group", 0, 0 } })
      enter(MC)
      assert.is_nil(view())
      wow.state.group = { "Konvett", BO }
      wow.fire("GROUP_ROSTER_UPDATE")
      wow.advance(5)
      assert.are.equal("Is this a guild run?", view().title)
    end)

    it("asks after the wait on joining a raid group inside the instance", function()
      start({ groupIsRaid = false })
      wow.state.group = nil
      wow.fire("GROUP_ROSTER_UPDATE")
      enter(MC)
      assert.is_nil(view())
      wow.state.group, wow.state.groupIsRaid = { "Konvett", ZOE }, true
      wow.fire("GROUP_ROSTER_UPDATE")
      assert.is_nil(view())
      wow.advance(5)
      assert.are.equal("Is this a guild run?", view().title)
    end)

    it("closes the question when the player leaves the group, or another officer chooses", function()
      start({ users = { ZOE } })
      enter(MC)
      wow.state.group, wow.state.groupIsRaid = nil, false
      wow.fire("GROUP_ROSTER_UPDATE")
      assert.is_nil(view())
      start({ users = { ZOE } })
      enter(MC)
      receive("S;S00002;" .. (NOW + 1) .. ";" .. ZOE, ZOE)
      assert.is_nil(view())
      assert.are.same({ "chosen", "raid00002", ZOE }, selection())
    end)
  end)

  describe("asking again", function()
    -- Molten Core chosen with count awards, then a corpse run or another instance.
    local function chosen(count)
      start()
      enter(MC)
      press("Start")
      awards("raid00001", count or 0)
      wow.addonMessages = {}
    end

    it("in a different instance, with its raid pre-selected and the awards kept (ask-again)", function()
      chosen(12)
      enter(OUTSIDE)
      enter(ONY)
      assert.are.same({
        title = "Bureaucracy Forever",
        lead = "You've entered " .. white("Onyxia's Lair") .. ". Switch the raid to "
          .. white("Onyxia's Lair, " .. day(ONY_RAID)) .. "?",
        hint = "Your 12 Molten Core awards stay with that raid and are still sent to the site.",
        rows = {},
        buttons = { { "Switch", true }, { "Keep Molten Core", true }, { "Not a guild run", true } },
      }, view())
      press("Switch")
      assert.are.same({ "chosen", "raid00002", "Konvett" }, selection())
      assert.are.equal(12, #ns.Raids.Awards("raid00001"))
      assert.are.equal(1, #selectionMessages())
    end)

    it("says one award in the singular, and nothing with none", function()
      chosen(1)
      enter(ONY)
      assert.are.equal("Your 1 Molten Core award stays with that raid and is still sent to the site.",
        view().hint)
      press("Keep Molten Core")
      chosen(0)
      enter(ONY)
      assert.is_nil(view().hint)
    end)

    it("keeps the raid on Keep, and doesn't ask again on a corpse run there", function()
      chosen(12)
      enter(ONY)
      press("Keep Molten Core")
      assert.are.same({ "chosen", "raid00001", "Konvett" }, selection())
      assert.are.same({}, selectionMessages())
      enter(OUTSIDE)
      enter(ONY)
      assert.is_nil(view())
      enter(MC)
      enter(ONY)
      assert.is_truthy(view())
    end)

    it("still doesn't ask there after a /reload, then a corpse run", function()
      chosen(12)
      enter(ONY)
      press("Keep Molten Core")
      local db = ns.db
      ns = wow.start({ saved = { BureaucracyForeverDB = db } })
      wow.state.player, wow.state.group, wow.state.groupIsRaid = "Konvett", { "Konvett", ZOE, BO }, true
      wow.state.groupLeader, wow.state.lootMethod = "Konvett", { "master", 0, 0 }
      wow.state.instance = ONY
      wow.fire("PLAYER_ENTERING_WORLD", false, true)
      enter(OUTSIDE)
      enter(ONY)
      assert.is_nil(view())
      assert.are.same({ "chosen", "raid00001", "Konvett" }, selection())
    end)

    it("asks again there once the raid is changed", function()
      chosen(12)
      enter(ONY)
      press("Keep Molten Core")
      wow.state.time = NOW + 60
      ns.Selection.ChooseRaid("raid00002", true)
      ns.Selection.ChooseRaid("raid00001", true)
      enter(ONY)
      assert.are.equal("Bureaucracy Forever", view().title)
    end)

    it("says so when master loot is off", function()
      chosen(12)
      wow.state.lootMethod = { "group", 0, 0 }
      enter(ONY)
      assert.are.equal("You're asked because master loot is off and you lead the raid. Turn master loot on "
        .. "to hand out items with the pop-up.", view().note)
      press("Keep Molten Core")
      enter(ZG)
      assert.is_truthy(view().note)
    end)

    it("can make it not a guild run", function()
      chosen(12)
      enter(ONY)
      press("Not a guild run")
      assert.are.same({ "off", nil, "Konvett" }, selection())
    end)

    it("lists the raids when the new instance has no single suggestion", function()
      chosen(12)
      enter(ZG)
      local v = view()
      assert.are.same({ "Bureaucracy Forever",
        "You've entered " .. white("Zul'Gurub") .. ". Which raid event is this?",
        "No raid event is set for Zul'Gurub (instance 309). If this is a custom raid, an officer can enter "
        .. "309 as its In-game instance number on the guild site. Your 12 Molten Core awards stay "
        .. "with that raid and are still sent to the site." }, { v.title, v.lead, v.hint })
      assert.are.same({ { "Start", false }, { "Keep Molten Core", true } }, v.buttons)
      pick(2)
      press("Start")
      assert.are.same({ "chosen", "raid00002", "Konvett" }, selection())
    end)

    it("never after /reload, a corpse run or re-entering the same instance", function()
      chosen(12)
      enter(ONY, 5, true)
      assert.is_nil(view())
      wow.fire("GROUP_ROSTER_UPDATE")
      wow.advance(5)
      assert.is_nil(view())
      enter(OUTSIDE)
      enter(MC)
      assert.is_nil(view())
      enter(MC)
      assert.is_nil(view())
    end)

    it("never when the selected raid has no instance number, or isn't loaded here", function()
      local custom = raidTree("raid00001")
      custom.instance = nil
      start({ raids = { custom, ONY_RAID } })
      ns.Selection.ChooseRaid("raid00001")
      enter(ONY)
      assert.is_nil(view())
      ns.Selection.Apply("S00009", NOW + 5, ZOE)
      enter(MC)
      assert.is_nil(view())
    end)

    it("never in a dungeon or a party that isn't a raid group", function()
      start()
      enter({ name = "The Stockade", id = 34, type = "party" })
      assert.is_nil(view())
      start({ groupIsRaid = false, group = { "Konvett", ZOE } })
      enter(MC)
      assert.is_nil(view())
    end)

    it("keeps the selection when master loot is set later, and the new loot master isn't asked", function()
      start({ player = BO, users = { ZOE }, leader = ZOE, lootMethod = { "group", 0, 0 } })
      receive("S;S00001;" .. NOW .. ";" .. ZOE, ZOE)
      enter(MC)
      assert.is_nil(view())
      wow.state.lootMethod = { "master", 0, 0 }
      wow.fire("GROUP_ROSTER_UPDATE")
      wow.advance(5)
      enter(OUTSIDE)
      enter(MC)
      assert.is_nil(view())
      assert.are.same({ "chosen", "raid00001", ZOE }, selection())
    end)
  end)

  describe("from Choose a raid now (ask-gone)", function()
    it("lists only the raids still loaded, nothing picked", function()
      ns = wow.start({ inbox = { formatVersion = 1, written = NOW - 1000, raids = {
        { snapshot = MC_RAID }, { snapshot = ONY_RAID } } } })
      ns.Selection.ChooseRaid("raid00001")
      local db = ns.db
      ns = wow.start({ saved = { BureaucracyForeverDB = db },
        inbox = { formatVersion = 1, written = NOW, raids = { { snapshot = ONY_RAID } } } })
      wow.state.player = "Konvett"
      assert.are.equal("Choose a raid now", ns.UI.dialog.yes.label:GetText())
      wow.click(function() ns.UI.dialog.yes.scripts.OnClick() end)
      assert.is_false(ns.UI.dialog:IsShown())
      assert.are.same({
        title = "Is this a guild run?",
        lead = white("Molten Core, " .. day(MC_RAID)) .. " has left the helper's list. If this is still a "
          .. "guild run, pick its raid event. If not, choose the last option.",
        rows = { picked(false, ONY_ROW), picked(false, OFF_ROW) },
        buttons = { { "Start", false }, { "Decide later", true } },
      }, view())
      pick(1)
      press("Start")
      assert.are.same({ "chosen", "raid00002", "Konvett" }, selection())
      assert.is_nil(ns.Selection.Gone())
    end)
  end)
end)
