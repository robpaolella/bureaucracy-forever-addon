-- Reads the release workflow and the draft script: they create drafts only, never publish, and
-- the draft job runs one at a time with write access that no other job has.
local function read(path)
  local file = assert(io.open(path, "rb"))
  local text = file:read("*a")
  file:close()
  return text
end

local workflow = read(".github/workflows/release.yml")

-- The lines of one job, up to the next job.
local function job(name)
  local start = "\n  " .. name .. ":\n"
  local block = workflow:match(start .. "(.-)\n  %S") or workflow:match(start .. "(.*)$")
  return assert(block, "no job " .. name)
end

describe("the release workflow", function()
  local draft = job("draft")

  it("drafts only after a merge to main, and dry-runs otherwise", function()
    assert.matches("on:\n  push:\n    branches: %[main%]\n", workflow)
    assert.matches("if: github.event_name == 'push'", draft, 1, true)
    assert.matches("run: lua5.1 release/main.lua draft\n", draft, 1, true)
    local dry = job("dry%-run")
    assert.matches("if: github.event_name != 'push'", dry, 1, true)
    assert.matches("run: lua5.1 release/main.lua dry-run\n", dry, 1, true)
    assert.is_nil(dry:find("contents: write", 1, true))
  end)

  it("serializes the draft job and never cancels a run half-way", function()
    assert.matches("concurrency:\n      group: release%-draft\n      cancel%-in%-progress: false\n", draft)
  end)

  it("gives write access to the draft job only", function()
    assert.matches("\npermissions:\n  contents: read\n", workflow)
    assert.matches("permissions:\n      contents: write\n", draft)
    local _, writes = workflow:gsub("contents: write", "")
    assert.equal(1, writes)
  end)

  it("builds the pushed commit, so the draft targets it", function()
    -- No `ref:` on checkout: HEAD is the merged commit, and Draft.lua targets HEAD's SHA.
    assert.is_nil(draft:find("ref:", 1, true))
    local script = read("release/Draft.lua")
    assert.matches('call%(env, "git", "rev%-parse", "HEAD"%)', script)
    assert.matches('"%-%-draft", "%-%-target", head,', script)
  end)

  it("has no publish step anywhere", function()
    for _, path in ipairs({ ".github/workflows/release.yml", "release/Draft.lua", "release/main.lua" }) do
      -- Publishing is `gh release edit --draft=false` or a PATCH setting draft to false.
      local text = read(path)
      for _, banned in ipairs({ "release edit", "draft=false", "draft: false", "PATCH", "-X POST" }) do
        assert.is_nil(text:find(banned, 1, true), path .. " has " .. banned)
      end
    end
    local _, creates = read("release/Draft.lua"):gsub('"release", "create"', "")
    assert.equal(1, creates)
  end)
end)
