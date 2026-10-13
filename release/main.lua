-- The release workflow's entry point, run from the repo root with the real git and gh:
--   lua5.1 release/main.lua draft     after a merge to main: create or refresh the draft release
--   lua5.1 release/main.lua dry-run   build the zip into dist/ only
-- gh needs GH_TOKEN, and GH_REPO outside a clone of the repo.
local Draft = dofile("release/Draft.lua")

local function quote(text) return "'" .. tostring(text):gsub("'", [['\'']]) .. "'" end

-- Runs a program; stderr goes straight to the log. Lua 5.1's popen gives no exit status, so the
-- shell prints it after the output.
local function run(program, args)
  local parts = { program }
  for _, arg in ipairs(args) do parts[#parts + 1] = quote(arg) end
  local handle = assert(io.popen(table.concat(parts, " ") .. "; printf '\\n%s' $?"))
  local text = handle:read("*a")
  handle:close()
  local out, status = text:match("^(.*)\n(%d+)$")
  return status == "0", out
end

local function log(text)
  print(text)
  local summary = os.getenv("GITHUB_STEP_SUMMARY")
  if summary then
    local file = assert(io.open(summary, "a"))
    file:write(text, "\n\n")
    file:close()
  end
end

local function build(version)
  local ok, out = run("sh", { "release/build.sh", version, "dist" })
  if not ok then error("building the zip failed: " .. out, 0) end
  return (out:gsub("%s+$", ""))
end

local mode = arg[1]
if mode ~= "draft" and mode ~= "dry-run" then
  io.stderr:write("usage: lua5.1 release/main.lua draft|dry-run\n")
  os.exit(2)
end
local ok, result = pcall(Draft.run, { run = run, build = build, log = log }, mode)
if not ok then
  io.stderr:write(tostring(result), "\n")
  os.exit(1)
end
