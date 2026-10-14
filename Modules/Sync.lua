-- Sync: reserves in and awards out, by pasted text, the helper's inbox and officers' add-ons.
local _, ns = ...

local Sync = {}
ns.Sync = Sync

-- The site's pasted reserves text (spec 3.2): every line pasted so far, as a string or a list.
-- Returns the validated snapshot and the update notice (nil when none), or nil and an error
-- for the officer. Stores nothing: loading the snapshot is the caller's (#47).
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
