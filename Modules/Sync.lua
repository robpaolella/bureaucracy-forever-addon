-- Sync: reserves in and awards out, by pasted text, the helper's inbox and officers' add-ons.
local _, ns = ...

local Sync = {}
ns.Sync = Sync

-- The site's pasted reserves text (spec 3.2): every line pasted so far, as a string or a list.
-- Returns the validated snapshot and the update notice (nil when none), or nil and an error
-- for the officer. Stores nothing: the caller loads it (Raids.Load).
function Sync.ReadPasted(pasted)
  local Snapshot = ns.Snapshot
  local text, err = Snapshot.Assemble(pasted)
  if not text then return nil, err end
  local tree
  tree, err = Snapshot.Parse(text)
  if tree == nil then return nil, err end
  local snapshot
  snapshot, err = Snapshot.Validate(tree, ns.version)
  if not snapshot then return nil, err end
  return snapshot, Snapshot.UpdateNotice(snapshot.addon, ns.version)
end

-- Whether the operation is, or names, a practice award: these are never copied out (spec 12).
local function isPractice(op)
  if op.practice then return true end
  local award = op.key and ns.Records.Get(op.key)
  return award ~= nil and award.practice == true
end

-- The copy-out text for a loaded raid (spec 12): the header, one operation text per line in the
-- order they happened, and E;<count>. Returns the text and the number of operation lines, or
-- nil and why. Practice records are left out and not counted.
function Sync.CopyOut(raidId)
  if raidId == nil then
    return nil, "Awards made with no raid can't be copied until they are attached to a raid."
  end
  local snapshot = ns.Raids.Get(raidId)
  if not snapshot then
    return nil, "That raid isn't loaded, so its code and environment are unknown."
  end
  local lines = { string.format("BFOUT1;%s;%s;%s", ns.OpText.Escape(raidId),
    ns.OpText.Escape(snapshot.code), ns.OpText.Escape(snapshot.env)) }
  for _, op in ipairs(ns.Records.Ops(raidId)) do
    if not isPractice(op) then lines[#lines + 1] = ns.OpText.Encode(op) end
  end
  local count = #lines - 1
  if count == 0 then return nil, "Nothing to copy: this raid has no awards to send." end
  lines[#lines + 1] = "E;" .. count
  return table.concat(lines, "\n"), count
end
