local M = {}

local function getSortedPeripheralNames(peripheralApi)
  local names = peripheralApi.getNames() or {}
  table.sort(names)
  return names
end

local function methodCount(obj, methods)
  if not obj then return 0 end
  local count = 0
  for _, methodName in ipairs(methods) do
    if type(obj[methodName]) == "function" then
      count = count + 1
    end
  end
  return count
end

function M.getMonitorCandidates(peripheralApi, getTypeOf, safePeripheral)
  local monitors = {}
  for _, name in ipairs(getSortedPeripheralNames(peripheralApi)) do
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
  if type(preferredName) == "string" and preferredName ~= "" then
    local p = safePeripheral(preferredName)
    if p and validator(p, preferredName) then
      return p, preferredName
    end
  end

  for _, name in ipairs(getSortedPeripheralNames(peripheralApi)) do
    local obj = safePeripheral(name)
    if obj and validator(obj, name) then
      return obj, name
    end
  end

  return nil, nil
end

function M.detectBestLaserPeripheral(peripheralApi, preferredName, safePeripheral, getTypeOf, contains)
  local energyMethods = { "getEnergy", "getEnergyStored", "getStored", "getMaxEnergy", "getMaxEnergyStored", "getCapacity" }
  local ampMethods = { "getMinThreshold", "getMaxThreshold", "setMinThreshold", "setMaxThreshold", "getEnergyFilledPercentage" }

  local function includes(haystack, needle)
    if type(contains) == "function" then
      return contains(haystack, needle)
    end
    return tostring(haystack or ""):lower():find(tostring(needle or ""):lower(), 1, true) ~= nil
  end

  local function scoreCandidate(name, obj)
    if not M.hasMethods(obj, energyMethods, 2) then
      return nil
    end

    local ptype = tostring(getTypeOf(name) or "")
    local score = methodCount(obj, energyMethods)
    score = score + methodCount(obj, ampMethods)

    if includes(ptype, "laser_amplifier") or includes(name, "laser_amplifier") then
      score = score + 20
    elseif includes(ptype, "laser") or includes(name, "laser") then
      score = score + 8
    end

    if type(obj.getEnergyFilledPercentage) == "function" then
      score = score + 4
    end
    if type(obj.getMaxEnergy) == "function" then
      score = score + 3
    end

    if type(preferredName) == "string" and preferredName ~= "" and name == preferredName then
      score = score + 50
    end

    return score
  end

  local bestObj, bestName, bestScore = nil, nil, -1
  for _, name in ipairs(getSortedPeripheralNames(peripheralApi)) do
    local obj = safePeripheral(name)
    if obj then
      local score = scoreCandidate(name, obj)
      if score and score > bestScore then
        bestScore = score
        bestObj = obj
        bestName = name
      end
    end
  end

  return bestObj, bestName
end

function M.scanPeripherals(peripheralApi, hw, cfg, safePeripheral, getTypeOf, contains)
  hw.reactor, hw.reactorName = M.detectBestPeripheral(peripheralApi, cfg.preferredReactor, safePeripheral, function(obj)
    return M.hasMethods(obj, { "isIgnited", "getPlasmaTemperature", "getPlasmaTemp", "getPlasmaHeat", "getCaseTemperature", "getCasingTemperature" }, 2)
  end)
  if hw.reactorName then cfg.preferredReactor = hw.reactorName end

  hw.logic, hw.logicName = M.detectBestPeripheral(peripheralApi, cfg.preferredLogicAdapter, safePeripheral, function(obj)
    return M.hasMethods(obj, { "isFormed", "isIgnited", "getPlasmaTemperature", "getPlasmaTemp", "getPlasmaHeat", "getIgnitionTemperature", "getIgnitionTemp", "getCaseTemperature", "getCasingTemperature" }, 3)
  end)
  if hw.logicName then cfg.preferredLogicAdapter = hw.logicName end

  hw.laser, hw.laserName = M.detectBestLaserPeripheral(peripheralApi, cfg.preferredLaser, safePeripheral, getTypeOf, contains)
  if hw.laserName then cfg.preferredLaser = hw.laserName end

  hw.induction, hw.inductionName = M.detectBestPeripheral(peripheralApi, cfg.preferredInduction, safePeripheral, function(obj)
    return M.hasMethods(obj, { "isFormed", "getEnergy", "getMaxEnergy", "getEnergyFilledPercentage", "getEnergyNeeded", "getLastInput", "getLastOutput", "getTransferCap" }, 2)
  end)
  if hw.inductionName then cfg.preferredInduction = hw.inductionName end

  hw.relays = {}
  hw.blockReaders = {}
  for _, name in ipairs(getSortedPeripheralNames(peripheralApi)) do
    local ptype = getTypeOf(name)
    if ptype == "redstone_relay" then
      hw.relays[name] = safePeripheral(name)
    elseif ptype == "block_reader" or contains(name, "block_reader") then
      table.insert(hw.blockReaders, { name = name, obj = safePeripheral(name), role = "unknown", data = nil })
    end
  end
end

return M
