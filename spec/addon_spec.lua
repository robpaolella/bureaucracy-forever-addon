local wow = require("spec.support.wow")

describe("the add-on", function()
  it("loads its files in .toc order and handles ADDON_LOADED without errors", function()
    local ns = wow.start()
    assert.are.equal("BureaucracyForever", ns.name)
    for _, module in ipairs({ "Rules", "Records", "Tracking", "Sync", "UI" }) do
      assert.is_table(ns[module], module)
    end
    assert.are.same({}, BureaucracyForeverDB)
    assert.are.equal(BureaucracyForeverDB, ns.db)
  end)

  it("keeps the saved data from an earlier session", function()
    local saved = { awards = { "kept" } }
    local ns = wow.start({ saved = { BureaucracyForeverDB = saved } })
    assert.are.equal(saved, ns.db)
    wow.start()
    assert.are.same({}, BureaucracyForeverDB)
  end)

  it("ignores ADDON_LOADED for other add-ons", function()
    local ns = wow.start()
    ns.db = nil
    wow.fire("ADDON_LOADED", "SomeOtherAddOn")
    assert.is_nil(ns.db)
  end)
end)

describe("the .toc", function()
  local metadata, files = wow.readToc()

  it("targets the WoW Forever client and saves the add-on's data", function()
    assert.are.equal("16001", metadata.Interface)
    assert.are.equal("BureaucracyForeverDB", metadata.SavedVariables)
  end)

  it("lists the helper's inbox file, which ships as a placeholder", function()
    -- The game reads a new file only after a full restart, so the inbox is listed from the start.
    local listed = false
    for _, file in ipairs(files) do listed = listed or file == "Inbox.lua" end
    assert.is_true(listed)
    local handle = assert(io.open("Inbox.lua", "rb"))
    local text = handle:read("*a")
    handle:close()
    -- The game reports a zero-byte file as an error at login, so it ships one comment line.
    assert.is_truthy(text:match("%S"))
    local before = {}
    for name in pairs(_G) do before[name] = true end
    assert(loadstring(text, "Inbox.lua"))()
    for name in pairs(_G) do assert.is_true(before[name], name .. " was defined by Inbox.lua") end
    assert.is_nil(_G.BureaucracyLootInbox)
  end)

  it("lists every Lua file in the add-on, and only files that exist", function()
    local listed = {}
    for _, file in ipairs(files) do
      listed[file:gsub("\\", "/")] = true
      assert.is_truthy(io.open((file:gsub("\\", "/"))), file .. " is listed but missing")
    end
    -- spec/ and release/ (the release logic) are not part of the add-on.
    local found = io.popen(
      [[find . -name "*.lua" -not -path "./spec/*" -not -path "./release/*" -not -path "./.*"]])
    for path in found:lines() do
      path = path:gsub("^%./", "")
      assert.is_true(listed[path] == true, path .. " is not in the .toc")
    end
    found:close()
  end)
end)
