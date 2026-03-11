local M = {}

function M.isValidVersion(version)
  if type(version) ~= "string" then return false end
  return version:match("^%d+%.%d+%.%d+$") ~= nil
end

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

function M.setUpdateState(updateState, status, checkResult, applyResult)
  updateState.status = status or updateState.status
  if checkResult then updateState.lastCheckResult = checkResult end
  if applyResult then updateState.lastApplyResult = applyResult end
end

function M.httpGetText(httpApi, trimText, updateState, url)
  if type(httpApi) ~= "table" or type(httpApi.get) ~= "function" then
    updateState.httpStatus = "DISABLED"
    return false, nil, "HTTP API disabled"
  end

  local ok, response = pcall(httpApi.get, url)
  if not ok or not response then
    updateState.httpStatus = "FAIL"
    return false, nil, "HTTP request failed"
  end

  local readOk, body = pcall(response.readAll)
  pcall(response.close)
  if not readOk then
    updateState.httpStatus = "FAIL"
    return false, nil, "Unable to read response"
  end

  if type(body) ~= "string" or #trimText(body) == 0 then
    updateState.httpStatus = "FAIL"
    return false, nil, "Empty response"
  end

  updateState.httpStatus = "OK"
  return true, body, nil
end

function M.validateVersionString(version)
  if not M.isValidVersion(version) then
    return false, "Version format must be MAJOR.MINOR.PATCH"
  end
  return true, nil
end

function M.validateLuaScript(text, trimText, contains)
  if type(text) ~= "string" then return false, "Not a string" end
  if #trimText(text) < 32 then return false, "Downloaded script is too short" end
  if not contains(text, "local CFG") and not contains(text, "state") then
    return false, "Invalid Lua signature"
  end
  return true, nil
end

function M.writeTextFile(fsApi, path, content)
  local h = fsApi.open(path, "w")
  if not h then return false, "Cannot open file for writing: " .. tostring(path) end
  h.write(content)
  h.close()
  return true, nil
end

function M.readTextFile(fsApi, path)
  if not fsApi.exists(path) then return false, nil, "File not found: " .. tostring(path) end
  local h = fsApi.open(path, "r")
  if not h then return false, nil, "Cannot open file: " .. tostring(path) end
  local text = h.readAll()
  h.close()
  return true, text, nil
end

return M
