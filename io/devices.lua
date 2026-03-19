local function loadDisplayBackend()
  local function tryLoadFromPath(path)
    if type(path) ~= "string" or path == "" then
      return nil
    end
    if not (fs and type(fs.exists) == "function" and fs.exists(path) and (not fs.isDir or not fs.isDir(path))) then
      return nil
    end
    if type(dofile) ~= "function" then
      return nil
    end
    local ok, mod = pcall(dofile, path)
    if ok and type(mod) == "table" then
      return mod
    end
    return nil
  end

  local function collectCandidatePaths()
    local out = {
      "io/display_backend.lua",
      "/io/display_backend.lua",
      "../io/display_backend.lua",
    }

    if type(shell) == "table" and type(shell.getRunningProgram) == "function"
      and fs and type(fs.getDir) == "function" and type(fs.combine) == "function" then
      local running = tostring(shell.getRunningProgram() or "")
      local runningDir = fs.getDir(running)
      if runningDir ~= "" then
        out[#out + 1] = fs.combine(runningDir, "io/display_backend.lua")
        out[#out + 1] = fs.combine(runningDir, "../io/display_backend.lua")
      end
    end

    if type(debug) == "table" and type(debug.getinfo) == "function"
      and fs and type(fs.getDir) == "function" and type(fs.combine) == "function" then
      local info = debug.getinfo(1, "S")
      local source = info and info.source or ""
      if type(source) == "string" and source:sub(1, 1) == "@" then
        local thisPath = source:sub(2)
        local thisDir = fs.getDir(thisPath)
        if thisDir ~= "" then
          out[#out + 1] = fs.combine(thisDir, "display_backend.lua")
        end
      end
    end

    return out
  end

  if type(require) == "function" then
    local ok, mod = pcall(require, "io.display_backend")
    if ok and type(mod) == "table" then
      return mod
    end
  end

  local seen = {}
  for _, path in ipairs(collectCandidatePaths()) do
    if not seen[path] then
      seen[path] = true
      local mod = tryLoadFromPath(path)
      if mod then
        return mod
      end
    end
  end

  return {
    detectCandidate = function(name, obj, getTypeOf)
      if not obj then return nil end
      local ptype = type(getTypeOf) == "function" and tostring(getTypeOf(name) or "") or ""
      if ptype == "monitor" then
        local w, h = 0, 0
        if type(obj.getSize) == "function" then
          local ok, mw, mh = pcall(obj.getSize)
          if ok then
            w = tonumber(mw) or 0
            h = tonumber(mh) or 0
          end
        end
        return {
          name = name,
          obj = obj,
          kind = "cc_monitor",
          touchEvent = "monitor_touch",
          w = w,
          h = h,
        }
      end
      return nil
    end,
  }
end

local DisplayBackend = loadDisplayBackend()

local M = {}
local lastScanSignature = nil

local function logDebug(logger, message, meta)
  if type(logger) == "table" and type(logger.debug) == "function" then
    logger.debug(message, meta)
  end
end

local function logInfo(logger, message, meta)
  if type(logger) == "table" and type(logger.info) == "function" then
    logger.info(message, meta)
  end
end

local function logWarn(logger, message, meta)
  if type(logger) == "table" and type(logger.warn) == "function" then
    logger.warn(message, meta)
  end
end

local function contains(haystack, needle)
  return tostring(haystack or ""):lower():find(tostring(needle or ""):lower(), 1, true) ~= nil
end

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

function M.getMonitorCandidates(peripheralApi, getTypeOf, safePeripheral, logger)
  local monitors = {}
  local diagnostics = {
    scanned = 0,
    tomCandidates = 0,
    ccCandidates = 0,
    tomRejected = 0,
    tomRejectReasons = {},
    tomRejectSamples = {},
  }

  for _, name in ipairs(getSortedPeripheralNames(peripheralApi)) do
    diagnostics.scanned = diagnostics.scanned + 1
    local obj = safePeripheral(name)
    if obj then
      local ptype = type(getTypeOf) == "function" and tostring(getTypeOf(name) or "") or ""
      local candidate, rejectReason = DisplayBackend.detectCandidate(name, obj, getTypeOf)
      if candidate then
        local backend = candidate.kind or "cc_monitor"
        table.insert(monitors, {
          name = name,
          obj = obj,
          w = candidate.w or 0,
          h = candidate.h or 0,
          backend = backend,
          touchEvent = candidate.touchEvent or "monitor_touch",
        })
        if backend == "toms_gpu" then
          diagnostics.tomCandidates = diagnostics.tomCandidates + 1
          logInfo(logger, "Tom backend candidate detected", {
            name = name,
            type = ptype,
            width = tostring(candidate.w or 0),
            height = tostring(candidate.h or 0),
          })
        else
          diagnostics.ccCandidates = diagnostics.ccCandidates + 1
        end
      else
        local tomHint = contains(ptype, "tm_")
          or contains(ptype, "tom")
          or contains(ptype, "gpu")
          or contains(name, "tm_")
          or contains(name, "tom")
          or contains(name, "gpu")
        if tomHint then
          diagnostics.tomRejected = diagnostics.tomRejected + 1
          local key = tostring(rejectReason or "unknown")
          diagnostics.tomRejectReasons[key] = (diagnostics.tomRejectReasons[key] or 0) + 1
          if #diagnostics.tomRejectSamples < 3 then
            diagnostics.tomRejectSamples[#diagnostics.tomRejectSamples + 1] = name .. ":" .. key
          end
        end
      end
    end
  end
  local backendPriority = {
    toms_gpu = 1,
    cc_monitor = 2,
  }
  table.sort(monitors, function(a, b)
    local pa = backendPriority[a.backend] or 99
    local pb = backendPriority[b.backend] or 99
    if pa ~= pb then
      return pa < pb
    end
    return a.name < b.name
  end)

  local reasonParts = {}
  for reason, count in pairs(diagnostics.tomRejectReasons) do
    reasonParts[#reasonParts + 1] = tostring(reason) .. "=" .. tostring(count)
  end
  table.sort(reasonParts)

  logInfo(logger, "Display candidates listed", {
    total = tostring(#monitors),
    toms_gpu = tostring(diagnostics.tomCandidates),
    cc_monitor = tostring(diagnostics.ccCandidates),
    scanned = tostring(diagnostics.scanned),
  })
  if diagnostics.tomRejected > 0 and diagnostics.tomCandidates == 0 then
    logWarn(logger, "Tom backend candidate rejected", {
      count = tostring(diagnostics.tomRejected),
      reasons = table.concat(reasonParts, ","),
      samples = table.concat(diagnostics.tomRejectSamples, ","),
    })
  else
    logDebug(logger, "Display backend diagnostics", {
      tomRejected = tostring(diagnostics.tomRejected),
      reasons = table.concat(reasonParts, ","),
    })
  end

  return monitors, diagnostics
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

local function rankLaserPeripherals(peripheralApi, preferredName, safePeripheral, getTypeOf, contains)
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

    if includes(ptype, "laser_amplifier")
      or includes(name, "laser_amplifier")
      or includes(ptype, "laseramplifier")
      or includes(name, "laseramplifier")
      or includes(ptype, "laser amplifier")
      or includes(name, "laser amplifier") then
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

  local ranked = {}
  for _, name in ipairs(getSortedPeripheralNames(peripheralApi)) do
    local obj = safePeripheral(name)
    if obj then
      local score = scoreCandidate(name, obj)
      if score then
        ranked[#ranked + 1] = {
          name = name,
          obj = obj,
          score = score,
          ptype = tostring(getTypeOf(name) or ""),
        }
      end
    end
  end

  table.sort(ranked, function(a, b)
    if a.score == b.score then
      return a.name < b.name
    end
    return a.score > b.score
  end)

  return ranked
end

function M.listLaserPeripherals(peripheralApi, preferredName, safePeripheral, getTypeOf, contains)
  local ranked = rankLaserPeripherals(peripheralApi, preferredName, safePeripheral, getTypeOf, contains)
  local out = {}
  for i = 1, #ranked do
    out[i] = {
      name = ranked[i].name,
      obj = ranked[i].obj,
      score = ranked[i].score,
      ptype = ranked[i].ptype,
    }
  end
  return out
end

function M.detectBestLaserPeripheral(peripheralApi, preferredName, safePeripheral, getTypeOf, contains)
  local ranked = rankLaserPeripherals(peripheralApi, preferredName, safePeripheral, getTypeOf, contains)
  if #ranked == 0 then
    return nil, nil
  end
  return ranked[1].obj, ranked[1].name
end

function M.scanPeripherals(peripheralApi, hw, cfg, safePeripheral, getTypeOf, contains, logger)
  hw.reactor, hw.reactorName = M.detectBestPeripheral(peripheralApi, cfg.preferredReactor, safePeripheral, function(obj)
    return M.hasMethods(obj, { "isIgnited", "getPlasmaTemperature", "getPlasmaTemp", "getPlasmaHeat", "getCaseTemperature", "getCasingTemperature" }, 2)
  end)
  if hw.reactorName then cfg.preferredReactor = hw.reactorName end

  hw.logic, hw.logicName = M.detectBestPeripheral(peripheralApi, cfg.preferredLogicAdapter, safePeripheral, function(obj)
    return M.hasMethods(obj, { "isFormed", "isIgnited", "getPlasmaTemperature", "getPlasmaTemp", "getPlasmaHeat", "getIgnitionTemperature", "getIgnitionTemp", "getCaseTemperature", "getCasingTemperature" }, 3)
  end)
  if hw.logicName then cfg.preferredLogicAdapter = hw.logicName end

  local laserCandidates = M.listLaserPeripherals(peripheralApi, cfg.preferredLaser, safePeripheral, getTypeOf, contains)
  hw.lasers = laserCandidates
  hw.laser = laserCandidates[1] and laserCandidates[1].obj or nil
  hw.laserName = laserCandidates[1] and laserCandidates[1].name or nil
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

  local relayCount = 0
  for _ in pairs(hw.relays or {}) do relayCount = relayCount + 1 end

  local signature = table.concat({
    hw.reactorName or "none",
    hw.logicName or "none",
    hw.laserName or "none",
    tostring(#(hw.lasers or {})),
    hw.inductionName or "none",
    tostring(relayCount),
    tostring(#(hw.blockReaders or {})),
  }, "|")

  if signature ~= lastScanSignature then
    lastScanSignature = signature
    logInfo(logger, "Peripheral topology changed", {
      reactor = hw.reactorName or "none",
      logic = hw.logicName or "none",
      laser = hw.laserName or "none",
      lasers = tostring(#(hw.lasers or {})),
      induction = hw.inductionName or "none",
      relays = tostring(relayCount),
      readers = tostring(#(hw.blockReaders or {})),
    })
  end
end

return M
