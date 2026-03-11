local M = {}

function M.getMonitorCandidates(peripheralApi, getTypeOf, safePeripheral)
  local monitors = {}
  for _, name in ipairs(peripheralApi.getNames()) do
    if getTypeOf(name) == "monitor" then
      local obj = safePeripheral(name)
      local w, h = 0, 0
      if obj and type(obj.getSize) == "function" then
        local ok, mw, mh = pcall(obj.getSize)
        if ok then
          w, h = mw, mh
        end
      end
      table.insert(monitors, { name = name, obj = obj, w = w, h = h })
    end
  end
  table.sort(monitors, function(a, b) return a.name < b.name end)
  return monitors
end

function M.hasMethods(obj, methods, minCount)
  if not obj then return false end
  local count = 0
  for _, methodName in ipairs(methods) do
    if type(obj[methodName]) == "function" then
      count = count + 1
    end
  end
  return count >= (minCount or 1)
end

function M.detectBestPeripheral(peripheralApi, preferredName, safePeripheral, validator)
  local p = safePeripheral(preferredName)
  if p and validator(p, preferredName) then
    return p, preferredName
  end

  for _, name in ipairs(peripheralApi.getNames()) do
    local obj = safePeripheral(name)
    if obj and validator(obj, name) then
      return obj, name
    end
  end

  return nil, nil
end

return M
