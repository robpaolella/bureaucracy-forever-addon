-- Draft release: after a merge to main, works out the next release with Release.plan and
-- creates or refreshes the one draft release for it. It never publishes: Robert does. A dry run
-- only builds the zip. Every git and GitHub call goes through `env`, so tests can stub them;
-- release/main.lua passes the real ones. Like Release.lua, it is not in the .toc.
-- env.run(program, args) -> ok, output; env.wait(seconds); env.build(version) -> zip path;
-- env.log(text).
local Release = dofile("release/Release.lua")

local Draft = {}
Draft.TOC = "BureaucracyForever.toc"

-- Seconds to wait before the second, third and fourth try of a read-only GitHub lookup.
local RETRY_WAITS = { 2, 5, 20 }

-- A read-only GitHub lookup fails for a moment when GitHub does: try it up to four times, and
-- only on a failed exit (a call that exits 0 is never repeated, empty output included).
-- Never use it for a call that changes something: a repeat could delete twice or create twice.
local function runRead(env, program, args)
  local ok, out = env.run(program, args)
  for _, seconds in ipairs(RETRY_WAITS) do
    if ok then break end
    env.wait(seconds)
    ok, out = env.run(program, args)
  end
  return ok, out
end

local function call(env, program, ...)
  local args = { ... }
  local ok, out = env.run(program, args)
  if not ok then
    error(program .. " " .. table.concat(args, " ") .. " failed: " .. tostring(out), 0)
  end
  return out or ""
end

-- `call` for a read-only GitHub lookup: retried.
local function callRead(env, program, ...)
  local args = { ... }
  local ok, out = runRead(env, program, args)
  if not ok then
    error(program .. " " .. table.concat(args, " ") .. " failed: " .. tostring(out), 0)
  end
  return out or ""
end

local function trim(text) return (text:gsub("^%s+", ""):gsub("%s+$", "")) end

local function lines(text)
  local out = {}
  for line in text:gmatch("[^\r\n]+") do out[#out + 1] = line end
  return out
end

-- The files a .toc lists, as the game reads them: every line that isn't blank or a comment.
function Draft.tocFiles(text)
  local files = {}
  for _, line in ipairs(lines(text)) do
    if not line:match("^#") and line:match("%S") then files[#files + 1] = (line:gsub("%s+$", "")) end
  end
  return files
end

-- The pull request behind a commit: the one whose merge made it, else a merged one, else an open
-- one (a dry run on a pull request's branch). Printed as number, title, then the body.
local PULL_JQ = [[(map(select(.merge_commit_sha == "%s")) + map(select(.merged_at)) + .)[0]
  | if . == null then "" else "\(.number)\n\(.title)\n\(.body // "")" end]]

-- The repo's merged pull requests by merge commit SHA, from one paged list: a squash-merged
-- commit is found here without a call of its own. Each record starts with an RS character (\30).
local MERGED_JQ = [[.[] | select(.merged_at and .merge_commit_sha)
  | "\u001e\(.merge_commit_sha)\n\(.number)\n\(.title)\n\(.body // "")"]]

local function mergedBySha(env, cache)
  if cache.merged then return cache.merged end
  local out = callRead(env, "gh", "api", "--paginate", "repos/{owner}/{repo}/pulls?state=closed&per_page=100",
    "--jq", MERGED_JQ)
  local merged = {}
  for record in out:gmatch("\30([^\30]*)") do
    local sha, number, title, body = record:match("^(%x+)\n(%d+)\n([^\n]*)\n(.*)$")
    if sha then merged[sha] = { number = tonumber(number), title = title, body = (body:gsub("\n$", "")) } end
  end
  cache.merged = merged
  return merged
end

local function item(env, sha, cache)
  -- Only a commit the list doesn't know (open pull request, merge-commit merge, none) asks for itself.
  local found = mergedBySha(env, cache)[sha]
  if found then return found end
  local out = callRead(env, "gh", "api", "repos/{owner}/{repo}/commits/" .. sha .. "/pulls",
    "--jq", PULL_JQ:format(sha))
  local number, title, body = out:match("^(%d+)\n([^\n]*)\n?(.*)$")
  if number then return { number = tonumber(number), title = title, body = (body:gsub("\n$", "")) } end
  -- A commit with no pull request counts by its subject.
  return { title = trim(call(env, "git", "log", "-1", "--format=%s", sha)) }
end

-- Release.plan's input for the commits after `previous` (a tag, or nil) up to `ref`, oldest first.
local function planInput(env, previous, ref, cache)
  local items = {}
  local range = previous and (previous .. ".." .. ref) or ref
  for _, sha in ipairs(lines(call(env, "git", "rev-list", "--no-merges", "--reverse", range))) do
    cache[sha] = cache[sha] or item(env, sha, cache)
    items[#items + 1] = cache[sha]
  end
  return {
    previous = previous,
    items = items,
    oldFiles = previous and Draft.tocFiles(call(env, "git", "show", previous .. ":" .. Draft.TOC)) or nil,
    newFiles = Draft.tocFiles(call(env, "git", "show", ref .. ":" .. Draft.TOC)),
  }
end

local function isAncestor(env, older, newer)
  return (env.run("git", { "merge-base", "--is-ancestor", older, newer }))
end

local function drafts(env)
  local out = callRead(env, "gh", "api", "--paginate", "repos/{owner}/{repo}/releases",
    "--jq", [[.[] | select(.draft) | "\(.id) \(.tag_name) \(.target_commitish)"]])
  local list = {}
  for _, line in ipairs(lines(out)) do
    local id, tag, target = line:match("^(%d+) (%S+) (%S+)$")
    if id then list[#list + 1] = { id = id, tag = tag, target = target } end
  end
  return list
end

local function isSha(text) return text:match("^%x+$") ~= nil and #text == 40 end

local function logPlan(env, plan)
  env.log("Next version: " .. plan.version .. "\n\n" .. plan.notes)
  for _, title in ipairs(plan.reword) do env.log("Needs a release note: " .. title) end
end

-- The last published release's tag, from GitHub, or nil.
local function lastPublished(env)
  local tag = trim(callRead(env, "gh", "release", "list", "--exclude-drafts", "--exclude-pre-releases",
    "--limit", "1", "--json", "tagName", "--jq", [[.[0].tagName // ""]]))
  return tag ~= "" and tag or nil
end

-- Whether `tag` exists on GitHub (the checkout may not have it yet): ok, taken.
local function tagOnGitHub(env, tag)
  local ok, found = runRead(env, "gh", { "api", "repos/{owner}/{repo}/git/matching-refs/tags/" .. tag,
    "--jq", '.[] | select(.ref == "refs/tags/' .. tag .. '") | .ref' })
  return ok, ok and trim(found or "") ~= "", found
end

-- Asks GitHub whether `tag` is free right before creating its draft: a lookup that fails stops
-- the run, so it never creates a draft it couldn't check.
local function isTaken(env, tag)
  local ok, taken, out = tagOnGitHub(env, tag)
  if not ok then
    error("Couldn't check whether " .. tag .. " was published during this run, so no draft was made. "
      .. "Re-run this run, or the next merge drafts it. GitHub said: " .. tostring(out), 0)
  end
  return taken
end

-- mode "draft" (after a merge to main) or "dry-run". Returns what happened: { status, version, zip }.
function Draft.run(env, mode)
  local head = trim(call(env, "git", "rev-parse", "HEAD"))
  local previous = lastPublished(env)
  local cache = {}
  local plan = Release.plan(planInput(env, previous, head, cache))
  if plan then logPlan(env, plan) end

  if mode == "dry-run" then
    local version = plan and plan.version or ("dev-" .. head:sub(1, 7))
    if not plan then env.log("No release due. The zip is named " .. version .. ".") end
    return { status = "dry-run", version = version, zip = env.build(version) }
  end

  if not plan then
    env.log("No release due: any draft is left as it is.")
    return { status = "none" }
  end
  local tag = "v" .. plan.version
  if trim(call(env, "git", "tag", "--list", tag)) ~= "" then
    error(tag .. " is already taken. Tags are never reused: publish a newer release instead.", 0)
  end

  local existing = drafts(env)
  for _, draft in ipairs(existing) do
    -- A re-run of an older merge must not move the draft back.
    if isSha(draft.target) and draft.target ~= head and isAncestor(env, head, draft.target) then
      env.log("The draft is from a newer merge: left as it is.")
      return { status = "newer", version = plan.version }
    end
  end
  -- Nothing since the draft's commit changes the release: leave it, with any edits Robert made.
  local draft = existing[1]
  if #existing == 1 and draft.tag == tag and isSha(draft.target) and isAncestor(env, draft.target, head) then
    local before = Release.plan(planInput(env, previous, draft.target, cache))
    if before and before.version == plan.version and before.notes == plan.notes then
      env.log("The draft for " .. tag .. " is up to date: left as it is.")
      return { status = "unchanged", version = plan.version }
    end
  end

  -- Replace, so there is only ever one draft. The tag is made when Robert publishes, on `head`.
  local zip = env.build(plan.version)
  for _, old in ipairs(existing) do
    -- Robert may have published it since the list: look again right before deleting.
    local path = "repos/{owner}/{repo}/releases/" .. old.id
    if trim(callRead(env, "gh", "api", path, "--jq", ".draft")) ~= "true" then
      env.log(old.tag .. " was published during this run: the next merge drafts the release after it.")
      return { status = "published", version = plan.version }
    end
    call(env, "gh", "api", "-X", "DELETE", path)
    -- GitHub can't delete only if still a draft, so a publish in the moment before the delete is
    -- caught here: publishing made the tag, and deleting the release keeps it.
    local restore = "To restore it: run the Release workflow by hand on the tag " .. old.tag
      .. " for the zip, then on GitHub, Releases, Draft a new release, choose tag " .. old.tag
      .. ", attach the zip and publish."
    local ok, taken = tagOnGitHub(env, old.tag)
    if not ok then
      error("Deleted the draft " .. old.tag .. " but couldn't check whether it had just been published. "
        .. "If the Releases page has no " .. old.tag .. " but its tag exists, it was. " .. restore, 0)
    end
    if taken then
      error(old.tag .. " was published just as this run replaced its draft, so the release was deleted. "
        .. "Its tag is kept. " .. restore, 0)
    end
  end
  -- Robert may have published the version since the run read GitHub, even with no draft left to
  -- delete: ask GitHub, not the checkout, and work the plan out once more from what he published.
  local latest = lastPublished(env)
  if isTaken(env, tag) or latest ~= previous then
    previous = latest ~= previous and latest or tag
    env.log(previous .. " was published during this run: working out the release after it.")
    -- The checkout was fetched before it was published, so it lacks the tag.
    local ref = "refs/tags/" .. previous
    callRead(env, "git", "fetch", "--no-tags", "origin", ref .. ":" .. ref)
    plan = Release.plan(planInput(env, previous, head, cache))
    if not plan then
      env.log("No release due since " .. previous .. ".")
      return { status = "none" }
    end
    logPlan(env, plan)
    tag = "v" .. plan.version
    if isTaken(env, tag) then
      error(tag .. " was also published during this run, so no draft was made. "
        .. "The next merge drafts the release after it.", 0)
    end
    zip = env.build(plan.version)
  end
  call(env, "gh", "release", "create", tag, zip, "--draft", "--target", head,
    "--title", tag, "--notes", plan.notes)
  env.log("Draft " .. tag .. " is ready for Robert to publish.")
  return { status = "created", version = plan.version, zip = zip }
end

return Draft
