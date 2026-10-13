-- Release logic: works out the next version and the officers' release notes from the pull
-- requests merged since the last release. Plain data in, plain data out, no network and no game
-- calls. It lives in release/, not the add-on folder, and is not in the .toc, so the game never
-- loads it and it never counts as a file-list change. The release workflow (#29) fetches the
-- data and calls Release.plan.
local Release = {}

-- Rank of each bump, so the highest wins.
local NONE, FIX, FEATURE, BREAKING = 0, 1, 2, 3

local function trim(text) return (text:gsub("^%s+", ""):gsub("%s+$", "")) end

-- "feat(ui)!: add a thing" -> "feat", true. Not a Conventional Commit -> "other", false.
local function parseTitle(title)
  local kind, bang = (title or ""):match("^%s*(%a+)%b()(!?):")
  if not kind then kind, bang = (title or ""):match("^%s*(%a+)(!?):") end
  if not kind then return "other", false end
  return kind:lower(), bang == "!"
end

local function hasBreakingFooter(body)
  for line in ((body or "") .. "\n"):gmatch("(.-)\r?\n") do
    if line:match("^BREAKING[ %-]CHANGE:") then return true end
  end
  return false
end

-- The PR's `Release note:` line, or nil when missing, empty or "none".
local function releaseNote(body)
  for line in ((body or "") .. "\n"):gmatch("(.-)\r?\n") do
    local text = line:match("^%s*[Rr]elease [Nn]ote:%s*(.-)%s*$")
    if text then
      if text == "" or text:lower():gsub("%.$", "") == "none" then return nil end
      return text
    end
  end
  return nil
end

-- One entry per distinct pull request (by number), in first-seen order. An item with no
-- `number` is a commit with no pull request: it counts by its subject (`title`), with no note.
local function classify(items)
  local seen, out = {}, {}
  for _, item in ipairs(items or {}) do
    local key = item.number and ("pr" .. item.number) or nil
    if not (key and seen[key]) then
      if key then seen[key] = true end
      local kind, bang = parseTitle(item.title)
      local hasPr = item.number ~= nil
      local breaking = bang or (hasPr and hasBreakingFooter(item.body))
      local rank = NONE
      if breaking then rank = BREAKING
      elseif kind == "feat" then rank = FEATURE
      elseif kind == "fix" then rank = FIX end
      out[#out + 1] = {
        title = trim(item.title or ""), kind = kind, rank = rank, breaking = breaking and true or false,
        note = hasPr and releaseNote(item.body) or nil,
      }
    end
  end
  return out
end

local function parseVersion(version)
  local major, minor, patch = tostring(version or ""):match("^v?(%d+)%.(%d+)%.(%d+)$")
  if not major then return nil end
  return tonumber(major), tonumber(minor), tonumber(patch)
end

-- Next version after `previous` ("1.2.3" or "v1.2.3"; nil when nothing is published yet),
-- or nil when nothing merged calls for a release.
function Release.nextVersion(previous, items)
  if previous == nil then return "1.0.0" end
  local major, minor, patch = parseVersion(previous)
  if not major then error("not a version: " .. tostring(previous), 2) end
  local top = NONE
  for _, entry in ipairs(classify(items)) do
    if entry.rank > top then top = entry.rank end
  end
  if top == BREAKING then return (major + 1) .. ".0.0" end
  if top == FEATURE then return major .. "." .. (minor + 1) .. ".0" end
  if top == FIX then return major .. "." .. minor .. "." .. (patch + 1) end
  return nil
end

-- True when the two .toc file lists hold different files (load order alone doesn't count).
function Release.fileListChanged(oldFiles, newFiles)
  local set, count = {}, 0
  for _, file in ipairs(oldFiles or {}) do
    if not set[file] then set[file] = true; count = count + 1 end
  end
  local seen = {}
  for _, file in ipairs(newFiles or {}) do
    if not seen[file] then
      seen[file] = true
      if not set[file] then return true end
      count = count - 1
    end
  end
  return count ~= 0
end

Release.REWORD_MARK = " (needs a release note: Robert to reword)"

-- The notes text, in Markdown, plus a list of the entries that fell back to their title.
function Release.notes(previous, items, oldFiles, newFiles)
  local before, new, fixed, reword = {}, {}, {}, {}

  if previous == nil then
    before[#before + 1] = "This is the first release: a fresh install, nothing to update."
  elseif Release.fileListChanged(oldFiles, newFiles) then
    before[#before + 1] = "Close the game completely and start it again after updating: "
      .. "this update adds or removes files."
  else
    before[#before + 1] = "Type /reload in the game after updating. No restart needed."
  end

  for _, entry in ipairs(classify(items)) do
    local wanted = entry.rank > NONE or entry.note ~= nil
    if wanted then
      local text = entry.note
      if not text then
        text = entry.title .. Release.REWORD_MARK
        reword[#reword + 1] = entry.title
      end
      local target = new
      if entry.breaking then target = before
      elseif entry.kind == "fix" then target = fixed end
      target[#target + 1] = "- " .. text
    end
  end

  local function section(lines, heading)
    if #lines == 0 then return nil end
    return "## " .. heading .. "\n" .. table.concat(lines, "\n")
  end
  local parts = {}
  for _, group in ipairs({ { before, "Before you update" }, { new, "New" }, { fixed, "Fixed" } }) do
    parts[#parts + 1] = section(group[1], group[2])
  end
  return table.concat(parts, "\n\n") .. "\n", reword
end

-- Everything the workflow needs. `input`: previous (last published version or nil), items (PRs
-- as { number, title, body }; commits with no PR as { title }), oldFiles, newFiles (the .toc
-- file lists then and now). Returns { version, notes, reword }; nil when no release is due.
function Release.plan(input)
  local version = Release.nextVersion(input.previous, input.items)
  if not version then return nil end
  local notes, reword = Release.notes(input.previous, input.items, input.oldFiles, input.newFiles)
  return { version = version, notes = notes, reword = reword }
end

return Release
