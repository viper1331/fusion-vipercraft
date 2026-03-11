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

function M.scanPeripherals(peripheralApi, hw, cfg, safePeripheral, getTypeOf, contains)
  hw.reactor, hw.reactorName = M.detectBestPeripheral(peripheralApi, cfg.preferredReactor, safePeripheral, function(obj)
    return M.hasMethods(obj, { "isIgnited", "getPlasmaTemperature", "getPlasmaTemp", "getPlasmaHeat", "getCaseTemperature", "getCasingTemperature" }, 2)
  end)

  hw.logic, hw.logicName = M.detectBestPeripheral(peripheralApi, cfg.preferredLogicAdapter, safePeripheral, function(obj)
    return M.hasMethods(obj, { "isFormed", "isIgnited", "getPlasmaTemperature", "getPlasmaTemp", "getPlasmaHeat", "getIgnitionTemperature", "getIgnitionTemp", "getCaseTemperature", "getCasingTemperature" }, 3)
  end)

  hw.laser, hw.laserName = M.detectBestPeripheral(peripheralApi, cfg.preferredLaser, safePeripheral, function(obj)
    return M.hasMethods(obj, { "getEnergy", "getEnergyStored", "getStored", "getMaxEnergy", "getMaxEnergyStored", "getCapacity" }, 2)
  end)

  hw.induction, hw.inductionName = M.detectBestPeripheral(peripheralApi, cfg.preferredInduction, safePeripheral, function(obj)
    return M.hasMethods(obj, { "isFormed", "getEnergy", "getMaxEnergy", "getEnergyFilledPercentage", "getEnergyNeeded", "getLastInput", "getLastOutput", "getTransferCap" }, 2)
  end)

  hw.relays = {}
  hw.blockReaders = {}
  for _, name in ipairs(peripheralApi.getNames()) do
    local ptype = getTypeOf(name)
    if ptype == "redstone_relay" then
      hw.relays[name] = safePeripheral(name)
    elseif ptype == "block_reader" or contains(name, "block_reader") then
      table.insert(hw.blockReaders, { name = name, obj = safePeripheral(name), role = "unknown", data = nil })
    end
  end
end

return M
