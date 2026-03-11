local M = {}

function M.parseVersion(version)
  local a, b, c = tostring(version or "0.0.0"):match("^(%d+)%.(%d+)%.(%d+)$")
  return tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0
end

function M.compareVersions(localV, remoteV)
  local la, lb, lc = M.parseVersion(localV)
  local ra, rb, rc = M.parseVersion(remoteV)
  if ra ~= la then return ra > la and 1 or -1 end
  if rb ~= lb then return rb > lb and 1 or -1 end
  if rc ~= lc then return rc > lc and 1 or -1 end
  return 0
end

return M
