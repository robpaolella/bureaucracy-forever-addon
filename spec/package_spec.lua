-- Builds the release zip with release/build.sh, unpacks it and loads it in the game stand-in.
local wow = require("spec.support.wow")

local function shell(command)
  local handle = assert(io.popen(command .. " 2>&1; printf '\\n%s' $?"))
  local text = handle:read("*a")
  handle:close()
  local out, status = text:match("^(.*)\n(%d+)$")
  return out, status == "0"
end

describe("the release zip", function()
  local dir, zip

  setup(function()
    dir = shell("mktemp -d"):gsub("%s+$", "")
    local ok
    zip, ok = shell("sh release/build.sh 1.3.0 " .. dir)
    assert(ok, zip)
    zip = zip:gsub("%s+$", "")
  end)

  teardown(function() shell("rm -rf " .. dir) end)

  it("is named with the version", function()
    assert.equal(dir .. "/BureaucracyForever-1.3.0.zip", zip)
  end)

  it("holds one add-on folder with the .toc and exactly the files it lists", function()
    local _, files = wow.readToc()
    local expected = { ["BureaucracyForever/BureaucracyForever.toc"] = true }
    for _, file in ipairs(files) do expected["BureaucracyForever/" .. file:gsub("\\", "/")] = true end
    local listing = shell("unzip -Z1 " .. zip)
    for path in listing:gmatch("[^\n]+") do
      if not path:match("/$") then
        assert.is_true(expected[path], path .. " should not be in the zip")
        expected[path] = nil
      end
    end
    assert.same({}, expected)
  end)

  it("loads in the stand-in and reports the stamped version", function()
    local _, ok = shell("cd " .. dir .. " && unzip -q " .. zip)
    assert.is_true(ok)
    local root = shell("pwd"):gsub("%s+$", "")
    local script = [[local wow = require("spec.support.wow"); wow.start(); wow.slash("/bf version");]]
      .. [[ io.write(wow.printed[1], "\n")]]
    local out = shell("cd " .. dir .. "/BureaucracyForever && LUA_PATH='" .. root .. "/?.lua;;' lua5.1 -e '"
      .. script .. "'")
    assert.equal("|cff33ff99Bureaucracy:|r version 1.3.0.\n", out)
  end)

  it("leaves the .toc in git at the development version", function()
    assert.equal("0.0.0-dev", wow.readToc().Version)
  end)
end)
