local Draft = dofile("release/Draft.lua")

local TOC = "## Version: 0.0.0-dev\nCore.lua\nInbox.lua\n"

-- A stand-in for git and GitHub: a straight line of commits on main, published tags and drafts.
-- Each commit: { pr = { number, title, body } } or { subject }, plus toc to change the .toc.
local function repo(commits)
  local self = { commits = {}, releases = {}, published = {}, calls = {}, waits = {}, built = {}, nextId = 1 }
  local index = {}
  function self.add(commit)
    local sha = string.rep(string.format("%x", (#self.commits + 1) % 16), 40)
    commit.sha = sha
    commit.toc = commit.toc or (self.commits[#self.commits] or { toc = TOC }).toc
    self.commits[#self.commits + 1] = commit
    index[sha] = #self.commits
    self.head = sha
    return sha
  end
  for _, commit in ipairs(commits) do self.add(commit) end

  local function at(ref) return index[ref] or index[self.published[ref]] end
  function self.publish(tag) self.published[tag] = self.head; self.latest = tag end
  function self.drafts()
    local out = {}
    for _, release in ipairs(self.releases) do out[#out + 1] = release end
    return out
  end

  local function git(args)
    local cmd = args[1]
    if cmd == "rev-parse" then return true, self.head .. "\n" end
    if cmd == "rev-list" then
      local from, to = args[4]:match("^(.-)%.%.(.+)$")
      local first, out = from and at(from) + 1 or 1, {}
      for i = first, at(to or args[4]) do out[#out + 1] = self.commits[i].sha end
      return true, table.concat(out, "\n") .. "\n"
    end
    if cmd == "show" then return true, self.commits[at(args[2]:match("^(.-):"))].toc end
    if cmd == "log" then return true, (self.commits[at(args[4])].subject or "") .. "\n" end
    if cmd == "merge-base" then return at(args[3]) <= at(args[4]), "" end
    if cmd == "tag" then return true, self.published[args[3]] and (args[3] .. "\n") or "" end
  end

  local function gh(args)
    if args[1] == "release" and args[2] == "list" then return true, (self.latest or "") .. "\n" end
    if args[1] == "release" and args[2] == "create" then
      local release = { id = self.nextId, tag = args[3], asset = args[4], args = args }
      for i = 5, #args do
        if args[i] == "--target" then release.target = args[i + 1] end
        if args[i] == "--notes" then release.notes = args[i + 1] end
      end
      self.nextId = self.nextId + 1
      self.releases[#self.releases + 1] = release
      return true, ""
    end
    local tag = args[2]:match("^repos/{owner}/{repo}/git/matching%-refs/tags/(.+)$")
    if args[1] == "api" and tag then
      if self.tagLookupFails then return false, "HTTP 503" end
      return true, self.published[tag] and ("refs/tags/" .. tag .. "\n") or ""
    end
    if args[1] == "api" and args[2] == "-X" and args[3] == "DELETE" then
      local id = tonumber(args[4]:match("(%d+)$"))
      for i, release in ipairs(self.releases) do
        if release.id == id then
          table.remove(self.releases, i)
          if self.publishBeforeDelete then self.published[release.tag] = release.target end
          return true, ""
        end
      end
      return false, "HTTP 404"
    end
    local id = args[2]:match("^repos/{owner}/{repo}/releases/(%d+)$")
    if args[1] == "api" and id then
      for _, release in ipairs(self.releases) do
        if release.id == tonumber(id) then return true, tostring(not release.published) .. "\n" end
      end
      return false, "HTTP 404"
    end
    if args[1] == "api" and args[2] == "--paginate" then
      local out = {}
      for _, r in ipairs(self.releases) do
        if not r.published then out[#out + 1] = r.id .. " " .. r.tag .. " " .. r.target end
      end
      return true, table.concat(out, "\n") .. "\n"
    end
    local sha = args[2]:match("^repos/{owner}/{repo}/commits/(%x+)/pulls$")
    if sha then
      local pr = self.commits[at(sha)].pr
      if not pr then return true, "\n" end
      return true, pr[1] .. "\n" .. pr[2] .. "\n" .. (pr[3] or "") .. "\n"
    end
  end

  self.env = {
    run = function(program, args)
      self.calls[#self.calls + 1] = program .. " " .. table.concat(args, " ")
      if program == "git" then return git(args) end
      if program == "gh" then return gh(args) end
    end,
    wait = function(seconds) self.waits[#self.waits + 1] = seconds end,
    build = function(version)
      self.built[#self.built + 1] = version
      return "dist/BureaucracyForever-" .. version .. ".zip"
    end,
    log = function() end,
  }
  function self.run(mode)
    self.calls, self.waits, self.built = {}, {}, {}
    return Draft.run(self.env, mode or "draft")
  end
  -- Makes calls matching `pattern` fail their first `times` tries (nil: every try).
  function self.flaky(pattern, times)
    local run, left = self.env.run, times
    self.env.run = function(program, args)
      if (program .. " " .. table.concat(args, " ")):find(pattern) and (not left or left > 0) then
        self.calls[#self.calls + 1] = program .. " " .. table.concat(args, " ")
        if left then left = left - 1 end
        return false, "HTTP 502"
      end
      return run(program, args)
    end
  end
  function self.count(pattern)
    local n = 0
    for _, call in ipairs(self.calls) do
      if call:find(pattern) then n = n + 1 end
    end
    return n
  end
  function self.called(pattern)
    for _, call in ipairs(self.calls) do
      if call:find(pattern) then return true end
    end
    return false
  end
  return self
end

local function pr(number, title, note)
  return { pr = { number, title, "Release note: " .. (note or "none") } }
end

describe("Draft.run", function()
  local r
  before_each(function()
    r = repo({ pr(1, "feat: first", "The add-on.") })
    r.publish("v1.0.0")
  end)

  it("creates only a draft, targeting the commit it built", function()
    r.add(pr(2, "feat: awards window", "A window for awards."))
    assert.equal("created", r.run().status)
    assert.equal(1, #r.releases)
    local draft = r.releases[1]
    assert.equal("v1.1.0", draft.tag)
    assert.equal(r.head, draft.target)
    assert.equal("dist/BureaucracyForever-1.1.0.zip", draft.asset)
    assert.matches("- A window for awards.", draft.notes, 1, true)
    assert.is_true(r.called("^gh release create v1.1.0 .* %-%-draft "))
    assert.is_false(r.called("publish") or r.called("release edit") or r.called("draft=false"))
  end)

  it("leaves exactly one draft after a second run, and refreshes it", function()
    r.add(pr(2, "feat: awards window", "A window for awards."))
    r.run()
    r.add(pr(3, "fix: the window's close button", "The close button works."))
    assert.equal("created", r.run().status)
    assert.equal(1, #r.releases)
    assert.equal("v1.1.0", r.releases[1].tag)
    assert.equal(r.head, r.releases[1].target)
    assert.matches("The close button works.", r.releases[1].notes, 1, true)
  end)

  it("renames the draft and its zip when the next version changes", function()
    r.add(pr(2, "fix: a crash", "No more crash."))
    r.run()
    assert.equal("v1.0.1", r.releases[1].tag)
    r.add(pr(3, "feat: awards window", "A window for awards."))
    r.run()
    assert.equal(1, #r.releases)
    assert.equal("v1.1.0", r.releases[1].tag)
    assert.equal("dist/BureaucracyForever-1.1.0.zip", r.releases[1].asset)
  end)

  it("leaves the draft as it is after a merge that calls for no release", function()
    r.add(pr(2, "feat: awards window", "A window for awards."))
    r.run()
    local draft = r.releases[1]
    r.add(pr(3, "docs: tidy the readme"))
    assert.equal("unchanged", r.run().status)
    assert.equal(draft, r.releases[1])
    assert.is_false(r.called("DELETE") or r.called("release create"))
    assert.same({}, r.built)
  end)

  it("refreshes the draft when a merge changes the .toc's file list", function()
    r.add(pr(2, "feat: awards window", "A window for awards."))
    r.run()
    r.add({ pr = { 3, "refactor: split the core", "Release note: none" }, toc = TOC .. "Util.lua\n" })
    assert.equal("created", r.run().status)
    assert.matches("Close the game completely", r.releases[1].notes, 1, true)
  end)

  it("makes no draft when nothing since the last release calls for one", function()
    r.add(pr(2, "docs: tidy the readme"))
    assert.equal("none", r.run().status)
    assert.same({}, r.releases)
    assert.same({}, r.built)
  end)

  it("never moves a newer draft back to an older merge", function()
    r.add(pr(2, "feat: awards window", "A window for awards."))
    local older = r.head
    r.add(pr(3, "fix: a crash", "No more crash."))
    r.run()
    local draft = r.releases[1]
    r.head = older
    assert.equal("newer", r.run().status)
    assert.equal(draft, r.releases[1])
  end)

  it("clears stray drafts so only one is left", function()
    r.add(pr(2, "fix: a crash", "No more crash."))
    r.releases = {
      { id = 90, tag = "v1.0.1", target = "main" },
      { id = 91, tag = "v9.0.0", target = "main" },
    }
    r.nextId = 92
    r.run()
    assert.equal(1, #r.releases)
    assert.equal(92, r.releases[1].id)
  end)

  it("never deletes a draft Robert publishes while the run is building", function()
    r.add(pr(2, "feat: awards window", "A window for awards."))
    r.run()
    local draft = r.releases[1]
    r.add(pr(3, "fix: a crash", "No more crash."))
    r.env.build = function() draft.published = true; return "dist/x.zip" end
    assert.equal("published", r.run().status)
    assert.same({ draft }, r.releases)
    assert.is_false(r.called("DELETE") or r.called("release create"))
  end)

  it("fails loudly when Robert publishes in the moment before the delete", function()
    r.add(pr(2, "feat: awards window", "A window for awards."))
    r.run()
    r.add(pr(3, "fix: a crash", "No more crash."))
    r.publishBeforeDelete = true
    local ok, err = pcall(r.run)
    assert.is_false(ok)
    assert.matches("^v1%.1%.0 was published just as this run replaced its draft", err)
    assert.matches("To restore it", err, 1, true)
    assert.is_false(r.called("release create"))
  end)

  it("fails loudly when it can't check whether the deleted draft was published", function()
    r.add(pr(2, "feat: awards window", "A window for awards."))
    r.run()
    r.add(pr(3, "fix: a crash", "No more crash."))
    r.tagLookupFails = true
    local ok, err = pcall(r.run)
    assert.is_false(ok)
    assert.matches("couldn't check whether it had just been published", err, 1, true)
    assert.matches("To restore it", err, 1, true)
    assert.is_false(r.called("release create"))
  end)

  describe("when GitHub fails for a moment", function()
    before_each(function() r.add(pr(2, "fix: a crash", "No more crash.")) end)

    it("retries a read-only lookup that fails once, then succeeds", function()
      r.flaky("/pulls", 1)
      assert.equal("created", r.run().status)
      assert.same({ 2 }, r.waits)
    end)

    it("retries the other read-only lookups too", function()
      local patterns = { "release list", "api %-%-paginate", "releases/1 %-%-jq", "matching%-refs" }
      for _, pattern in ipairs(patterns) do
        local fresh = repo({ pr(1, "feat: first", "The add-on.") })
        fresh.publish("v1.0.0")
        fresh.add(pr(2, "fix: a crash", "No more crash."))
        fresh.run()
        fresh.add(pr(3, "fix: another", "Another fix."))
        fresh.flaky(pattern, 1)
        assert.equal("created", fresh.run().status, pattern)
        assert.same({ 2 }, fresh.waits, pattern)
      end
    end)

    it("gives the existing error after three tries, waiting 2s then 5s", function()
      r.flaky("/pulls")
      local ok, err = pcall(r.run)
      assert.is_false(ok)
      assert.matches("gh api repos/{owner}/{repo}/commits/", err, 1, true)
      assert.matches("failed: HTTP 502", err, 1, true)
      assert.equal(3, r.count("/pulls"))
      assert.same({ 2, 5 }, r.waits)
    end)

    it("keeps the tag check's own error after three tries", function()
      r.run()
      r.add(pr(3, "fix: another", "Another fix."))
      r.flaky("matching%-refs")
      local ok, err = pcall(r.run)
      assert.is_false(ok)
      assert.matches("couldn't check whether it had just been published", err, 1, true)
      assert.equal(3, r.count("matching%-refs"))
      assert.same({ 2, 5 }, r.waits)
      assert.is_false(r.called("release create"))
    end)

    it("does not retry a call that exits 0 with nothing printed", function()
      r.add({ subject = "fix: no pull request" })
      assert.equal("created", r.run().status)
      assert.same({}, r.waits)
      assert.equal(1, r.count("commits/" .. string.rep("3", 40) .. "/pulls"))
    end)

    it("tries a failing delete once", function()
      r.run()
      r.add(pr(3, "fix: another", "Another fix."))
      r.flaky("DELETE")
      assert.is_false((pcall(r.run)))
      assert.equal(1, r.count("DELETE"))
      assert.same({}, r.waits)
    end)

    it("tries a failing release create once", function()
      r.flaky("release create")
      assert.is_false((pcall(r.run)))
      assert.equal(1, r.count("release create"))
      assert.same({}, r.waits)
    end)
  end)

  it("refuses a version whose tag is already taken", function()
    r.add(pr(2, "fix: a crash", "No more crash."))
    r.published["v1.0.1"] = r.head
    assert.has_error(function() r.run() end,
      "v1.0.1 is already taken. Tags are never reused: publish a newer release instead.")
    assert.same({}, r.releases)
  end)

  it("makes the first release 1.0.0 and counts a commit with no PR by its subject", function()
    r = repo({ { subject = "Initial commit" }, pr(1, "feat: first", "The add-on.") })
    r.run()
    assert.equal("v1.0.0", r.releases[1].tag)
    assert.matches("This is the first release", r.releases[1].notes, 1, true)
  end)

  describe("as a dry run", function()
    it("builds the zip named with the next version and makes no release", function()
      r.add(pr(2, "feat: awards window", "A window for awards."))
      local result = r.run("dry-run")
      local zip = "dist/BureaucracyForever-1.1.0.zip"
      assert.same({ status = "dry-run", version = "1.1.0", zip = zip }, result)
      assert.same({}, r.releases)
      assert.is_false(r.called("DELETE") or r.called("release create"))
    end)

    it("names the zip after the commit when no release is due", function()
      r.add(pr(2, "docs: tidy the readme"))
      assert.equal("dev-" .. r.head:sub(1, 7), r.run("dry-run").version)
    end)
  end)
end)

describe("Draft.tocFiles", function()
  it("lists the files, not the metadata or blank lines", function()
    assert.same({ "Core.lua", "Modules\\UI.lua" },
      Draft.tocFiles("## Interface: 16001\r\n# a comment\n\nCore.lua  \nModules\\UI.lua"))
  end)
end)
