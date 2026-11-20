local name, ns = ...
-- Compat: flavor detection lives here and nowhere else. Every other
-- file asks Compat (ns.FLAVOR, ns.IS_RETAIL, ns.IS_FOREVER) or probes
-- a capability; nothing checks WOW_PROJECT_ID, GetBuildInfo, or the
-- Interface version outside this file.
local project = WOW_PROJECT_ID
local mainline = WOW_PROJECT_MAINLINE
local camelot = WOW_PROJECT_CAMELOT
if type(camelot) ~= "number" then
  camelot = 18
end
ns.IS_RETAIL = project ~= nil and project == mainline
ns.IS_FOREVER = project ~= nil and project == camelot
if not ns.IS_RETAIL and not ns.IS_FOREVER and type(GetBuildInfo) == "function" then
  local ok, interface = pcall(function()
    return select(4, GetBuildInfo())
  end)
  if ok and interface == 16001 then
    ns.IS_FOREVER = true
  end
end
if not ns.IS_RETAIL and not ns.IS_FOREVER and type(C_AddOns) == "table" then
  if type(C_AddOns.GetAddOnInterfaceVersion) == "function" then
    local ok, v = pcall(C_AddOns.GetAddOnInterfaceVersion, name)
    if ok and type(v) == "number" and v < 20000 then
      ns.IS_FOREVER = true
    end
  end
end
ns.FLAVOR = ns.IS_FOREVER and "forever" or "retail"

-- The one-line reader, kept here so callers never detect flavor
-- themselves.
function ns.clientFlavor()
  return ns.FLAVOR
end

-- Capability first: if the API exists, use it. Branch on flavor only
-- for what no existence check can decide.
function ns.hasAPI(table_, fname)
  return type(table_) == "table" and type(table_[fname]) == "function"
end

-- Feature matrix: everything here runs on both clients; a missing API
-- degrades silently behind a presence gate, never an error.
--   send wrapper .... Shared (C_ChatInfo.SendChatMessage)
--   race default .... Shared (UnitRace, GUID switch)
--   settings ........ Shared (native Settings, retried at login)
--   secrets ......... Shared (canaccessvalue fail-open)
