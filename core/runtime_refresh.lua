-- core/runtime_refresh.lua
-- Refresh cycle runtime (peripherals + mesures).

local M = {}
local CoreEnergy = require("core.energy")
local CoreTemperature = require("core.temperature")

function M.build(api)
  local state = api.state
  local hw = api.hw
  local CFG = api.CFG

  local tryMethods = api.tryMethods
  local safeCall = api.safeCall
  local toNumber = api.toNumber
  local clamp = api.clamp
  local normalizePortMode = api.normalizePortMode

  local scanPeripherals = api.scanPeripherals
  local scanBlockReaders = api.scanBlockReaders
  local readChemicalFromReader = api.readChemicalFromReader
  local readActiveFromReader = api.readActiveFromReader
  local readRelayOutputState = api.readRelayOutputState
  local ensureRelayLow = api.ensureRelayLow
  local refreshSetupDeviceStatus = api.refreshSetupDeviceStatus
  local pushEvent = api.pushEvent
  local log = api.log or {}
  local logDebug = type(log.debug) == "function" and log.debug or function() end
  local logInfo = type(log.info) == "function" and log.info or function() end
  local logWarn = type(log.warn) == "function" and log.warn or function() end

  local runtime = {}
  local previous = {}

  local function logTransition(key, value, message, level, meta)
    if previous[key] == nil then
      previous[key] = value
      return
    end
    if previous[key] == value then
      return
    end
    previous[key] = value
    if level == "warn" then
      logWarn(message, meta)
    else
      logInfo(message, meta)
    end
  end

  local function detectTemperatureSourceUnit(obj, fallback)
    if not obj then
      return CoreTemperature.sanitizeUnit(fallback, "k")
    end

    local ok, unit = tryMethods(obj, {
      "getTemperatureUnit",
      "getTempUnit",
      "getPlasmaTemperatureUnit",
      "getCaseTemperatureUnit",
    })

    if ok then
      return CoreTemperature.sourceUnitFromString(unit, fallback)
    end

    return CoreTemperature.sanitizeUnit(fallback, "k")
  end

  local function readLaser()
    local laserDevices = {}
    if type(hw.lasers) == "table" then
      for _, entry in ipairs(hw.lasers) do
        if type(entry) == "table" and entry.obj then
          laserDevices[#laserDevices + 1] = entry.obj
        elseif entry then
          laserDevices[#laserDevices + 1] = entry
        end
      end
    end
    if #laserDevices == 0 and hw.laser then
      laserDevices[1] = hw.laser
    end

    state.laserDetectedCount = #laserDevices
    state.laserPresent = #laserDevices > 0
    if not state.laserPresent then
      state.laserEnergy = 0
      state.laserMax = 1
      state.laserPct = 0
      state.laserEnergySourceUnit = "j"
      return
    end

    local laser = laserDevices[1]

    local function sourceUnit()
      local okUnit, unit = tryMethods(laser, { "getEnergyUnit", "getUnit", "getEnergyDisplayUnit", "getTransferUnit" })
      if okUnit then
        return CoreEnergy.sourceUnitFromString(unit, "j")
      end
      -- Fallback fixe en Joules: evite d'interpretter une mesure materielle
      -- dans l'unite d'affichage UI (J/FE).
      return "j"
    end

    local unit = sourceUnit()
    local _, e = tryMethods(laser, { "getEnergy", "getEnergyStored", "getStored" })
    local _, m = tryMethods(laser, { "getMaxEnergy", "getMaxEnergyStored", "getCapacity" })
    local okPct, pct = tryMethods(laser, { "getEnergyFilledPercentage", "getFilledPercentage" })

    state.laserEnergySourceUnit = unit
    state.laserEnergy = toNumber(e, 0)
    state.laserMax = toNumber(m, 0)

    if okPct then
      local rawPct = toNumber(pct, 0)
      if rawPct <= 1.0 then rawPct = rawPct * 100 end
      state.laserPct = clamp(rawPct, 0, 100)
    else
      state.laserPct = 0
    end

    if state.laserMax <= 0 then
      if state.laserPct > 0 then
        state.laserMax = math.max(1, (state.laserEnergy * 100) / state.laserPct)
      else
        state.laserMax = math.max(1, state.laserEnergy)
      end
    end

    if state.laserMax < state.laserEnergy then
      state.laserMax = state.laserEnergy
    end

    if not okPct then
      state.laserPct = clamp((state.laserEnergy * 100) / state.laserMax, 0, 100)
    end
  end

  local function parseHohlraumPayload(payload)
    local count = 0
    local name = nil

    if type(payload) == "table" then
      count = math.floor(toNumber(payload.count or payload.amount or payload.Count, 0))
      name = payload.name or payload.id or payload.displayName or payload.item or payload.itemName

      if type(payload.stack) == "table" then
        name = name or payload.stack.name or payload.stack.id or payload.stack.displayName
        if count <= 0 then
          count = math.floor(toNumber(payload.stack.count or payload.stack.amount, 0))
        end
      end

      if type(payload[1]) == "table" then
        local first = payload[1]
        name = name or first.name or first.id or first.displayName
        if count <= 0 then
          count = math.floor(toNumber(first.count or first.amount, 0))
        end
      end
    elseif type(payload) == "string" then
      name = payload
    end

    local lower = string.lower(tostring(name or ""))
    if count <= 0 and lower:find("hohlraum", 1, true) then
      count = 1
    end
    if count > 0 and (name == nil or tostring(name) == "") then
      name = "mekanismgenerators:hohlraum"
    end

    local present = false
    if count > 0 then
      if lower == "" or lower:find("hohlraum", 1, true) then
        present = true
      end
    end

    return present, math.max(0, count), tostring(name or "N/A")
  end

  local function detectHohlraumFromControllerInventory()
    if not hw.reactor then return false, 0, "N/A" end

    local total = 0
    local nameFound = nil

    local okList, listed = safeCall(hw.reactor, "list")
    if okList and type(listed) == "table" then
      for _, stack in pairs(listed) do
        if type(stack) == "table" then
          local name = tostring(stack.name or stack.id or "")
          local count = math.floor(toNumber(stack.count, 0))
          if count > 0 and string.lower(name):find("hohlraum", 1, true) then
            total = total + count
            nameFound = nameFound or name
          end
        end
      end
      if total > 0 then
        return true, total, tostring(nameFound or "mekanismgenerators:hohlraum")
      end
    end

    local okSize, size = safeCall(hw.reactor, "size")
    if okSize and type(size) == "number" and size > 0 then
      local maxSlots = math.floor(size)
      for slot = 1, maxSlots do
        local okDetail, detail = safeCall(hw.reactor, "getItemDetail", slot)
        if okDetail and type(detail) == "table" then
          local name = tostring(detail.name or detail.id or "")
          local count = math.floor(toNumber(detail.count, 0))
          if count > 0 and string.lower(name):find("hohlraum", 1, true) then
            total = total + count
            nameFound = nameFound or name
          end
        end
      end
      if total > 0 then
        return true, total, tostring(nameFound or "mekanismgenerators:hohlraum")
      end
    end

    return false, 0, "N/A"
  end

  local function readReactor()
    state.reactorPresent = hw.reactor ~= nil or hw.logic ~= nil
    -- Reset explicite: evite les valeurs stale si un appel peripherique echoue.
    state.ignition = false
    state.plasmaTemp = 0
    state.ignitionTemp = 0
    state.caseTemp = 0
    state.reactorTempSourceUnit = CoreTemperature.sanitizeUnit(state.reactorTempSourceUnit, "k")
    state.hohlraumPresent = false
    state.hohlraumCount = 0
    state.hohlraumName = "N/A"
    state.injectionRate = 0
    state.injectionMin = 0
    state.injectionMax = 98
    state.injectionWritable = false
    state.fuelFlowMbT = 0
    state.fuelFlowSource = "STARVED"
    state.fuelFlowDTMbT = 0
    state.fuelFlowDMbT = 0
    state.fuelFlowTMbT = 0

    local formed = false
    local formedFromLogic = false

    if hw.logic then
      state.reactorTempSourceUnit = detectTemperatureSourceUnit(hw.logic, state.reactorTempSourceUnit)

      local okFormed, logicFormed = tryMethods(hw.logic, { "isFormed", "getFormed" })
      if okFormed then
        formed = logicFormed == true
        formedFromLogic = true
      end

      local okIgn, ign = tryMethods(hw.logic, { "isIgnited" })
      if okIgn then state.ignition = (ign == true) end

      local okPlasma, plasma = tryMethods(hw.logic, { "getPlasmaTemperature", "getPlasmaTemp", "getPlasmaHeat" })
      if okPlasma then state.plasmaTemp = toNumber(plasma, 0) end

      local okIgnTemp, ignTemp = tryMethods(hw.logic, { "getIgnitionTemperature", "getIgnitionTemp" })
      if okIgnTemp then
        state.ignitionTemp = toNumber(ignTemp, 0)
        state.minTemp = state.ignitionTemp + 10000
      end

      local okCase, caseTemp = tryMethods(hw.logic, { "getCaseTemperature", "getCasingTemperature" })
      if okCase then state.caseTemp = toNumber(caseTemp, 0) end

      local okInjRate, injRate = tryMethods(hw.logic, { "getInjectionRate" })
      if okInjRate then
        state.injectionRate = math.floor(toNumber(injRate, 0) + 0.5)
      end
      state.injectionWritable = type(hw.logic.setInjectionRate) == "function"

      local okHohlraum, hohlraum = tryMethods(hw.logic, { "getHohlraum" })
      if okHohlraum then
        state.hohlraumPresent, state.hohlraumCount, state.hohlraumName = parseHohlraumPayload(hohlraum)
      elseif hw.reactor then
        state.hohlraumPresent, state.hohlraumCount, state.hohlraumName = detectHohlraumFromControllerInventory()
      end

      if not formedFromLogic then
        formed = state.ignition or state.plasmaTemp > 0
      end
    elseif hw.reactor then
      state.reactorTempSourceUnit = detectTemperatureSourceUnit(hw.reactor, state.reactorTempSourceUnit)

      local okIgn, ign = tryMethods(hw.reactor, { "isIgnited", "getIgnitionStatus" })
      state.ignition = okIgn and (ign == true or ign == "true") or false

      local okPlasma, plasma = tryMethods(hw.reactor, { "getPlasmaTemperature", "getPlasmaTemp", "getPlasmaHeat" })
      state.plasmaTemp = okPlasma and toNumber(plasma, 0) or 0

      local _, ignTemp = tryMethods(hw.reactor, { "getIgnitionTemperature", "getIgnitionTemp" })
      state.ignitionTemp = toNumber(ignTemp, 0)
      state.minTemp = state.ignitionTemp + 10000

      local _, caseTemp = tryMethods(hw.reactor, { "getCaseTemperature", "getCasingTemperature" })
      state.caseTemp = toNumber(caseTemp, 0)
      formed = state.ignition or state.plasmaTemp > 0

      local okInjRate, injRate = tryMethods(hw.reactor, { "getInjectionRate" })
      if okInjRate then
        state.injectionRate = math.floor(toNumber(injRate, 0) + 0.5)
      end
      state.injectionWritable = type(hw.reactor.setInjectionRate) == "function"

      local okHohlraum, hohlraum = tryMethods(hw.reactor, { "getHohlraum" })
      if okHohlraum then
        state.hohlraumPresent, state.hohlraumCount, state.hohlraumName = parseHohlraumPayload(hohlraum)
      else
        state.hohlraumPresent, state.hohlraumCount, state.hohlraumName = detectHohlraumFromControllerInventory()
      end
    else
      formed = false
    end

    state.injectionMin = math.max(0, math.floor(toNumber(state.injectionMin, 0)))
    state.injectionMax = math.max(state.injectionMin, math.floor(toNumber(state.injectionMax, 98)))
    state.injectionRate = clamp(math.floor(toNumber(state.injectionRate, 0)), state.injectionMin, state.injectionMax)
    state.hohlraumCount = math.max(0, math.floor(toNumber(state.hohlraumCount, 0)))

    state.reactorFormed = formed

    if state.ignition then
      state.ignitionSequencePending = false
    elseif state.ignitionSequencePending and ((os.clock() - state.lastIgnitionAttempt) > CFG.ignitionRetryDelay) then
      state.ignitionSequencePending = false
    end
  end

  local function readInductionStatus()
    state.inductionPresent = hw.induction ~= nil
    state.inductionFormed = false
    state.inductionEnergy = 0
    state.inductionMax = 1
    state.inductionPct = 0
    state.inductionNeeded = 0
    state.inductionInput = 0
    state.inductionOutput = 0
    state.inductionTransferCap = 0
    state.inductionCells = 0
    state.inductionProviders = 0
    state.inductionLength = 0
    state.inductionHeight = 0
    state.inductionWidth = 0
    state.inductionPortMode = "UNKNOWN"

    state.energyPresent = state.inductionPresent
    state.energyKnown = false
    state.energyStored = 0
    state.energyMax = 1
    state.energyPct = 0

    if not hw.induction then return end

    local okFormed, formed = safeCall(hw.induction, "isFormed")
    local okEnergy, energy = safeCall(hw.induction, "getEnergy")
    local okMax, maxEnergy = safeCall(hw.induction, "getMaxEnergy")
    local okPct, pct = safeCall(hw.induction, "getEnergyFilledPercentage")
    local _, needed = safeCall(hw.induction, "getEnergyNeeded")
    local _, lastInput = safeCall(hw.induction, "getLastInput")
    local _, lastOutput = safeCall(hw.induction, "getLastOutput")
    local _, transferCap = safeCall(hw.induction, "getTransferCap")
    local _, cells = safeCall(hw.induction, "getInstalledCells")
    local _, providers = safeCall(hw.induction, "getInstalledProviders")
    local _, length = safeCall(hw.induction, "getLength")
    local _, height = safeCall(hw.induction, "getHeight")
    local _, width = safeCall(hw.induction, "getWidth")
    local okPortMode, portMode = safeCall(hw.induction, "getMode")

    state.inductionFormed = okFormed and formed == true or false
    state.inductionEnergy = toNumber(energy, 0)
    state.inductionMax = math.max(1, toNumber(maxEnergy, 1))
    state.inductionNeeded = toNumber(needed, math.max(0, state.inductionMax - state.inductionEnergy))
    state.inductionInput = toNumber(lastInput, 0)
    state.inductionOutput = toNumber(lastOutput, 0)
    state.inductionTransferCap = toNumber(transferCap, 0)
    state.inductionCells = toNumber(cells, 0)
    state.inductionProviders = toNumber(providers, 0)
    state.inductionLength = toNumber(length, 0)
    state.inductionHeight = toNumber(height, 0)
    state.inductionWidth = toNumber(width, 0)
    state.inductionPortMode = okPortMode and normalizePortMode(portMode) or "UNKNOWN"

    if okPct then
      local rawPct = toNumber(pct, 0)
      if rawPct <= 1.0 then rawPct = rawPct * 100 end
      state.inductionPct = clamp(rawPct, 0, 100)
    else
      state.inductionPct = clamp((state.inductionEnergy * 100) / state.inductionMax, 0, 100)
    end

    state.energyKnown = okEnergy or okMax or okPct
    state.energyStored = state.inductionEnergy
    state.energyMax = state.inductionMax
    state.energyPct = state.inductionPct
  end

  local function readReaders()
    state.deuteriumName, state.deuteriumAmount = readChemicalFromReader(hw.readerRoles.deuterium)
    state.tritiumName, state.tritiumAmount = readChemicalFromReader(hw.readerRoles.tritium)

    local auxReader = hw.readerRoles.inventory or hw.readerRoles.active[1]
    if auxReader then
      state.auxPresent = true
      local active, rs = readActiveFromReader(auxReader)
      state.auxActive = active
      state.auxRedstone = rs
    else
      state.auxPresent = false
      state.auxActive = false
      state.auxRedstone = 0
    end

    state.laserLineOn = readRelayOutputState("laser_charge", false)
    state.dOpen = readRelayOutputState("deuterium", state.dOpen)
    state.tOpen = readRelayOutputState("tritium", state.tOpen)
  end

  local function updateFuelFlow()
    local injection = math.max(0, toNumber(state.injectionRate, 0))
    if not state.ignition then
      injection = 0
    end

    local dt = state.dtOpen == true
    local d = state.dOpen == true
    local t = state.tOpen == true

    state.fuelFlowMbT = 0
    state.fuelFlowSource = "STARVED"
    state.fuelFlowDTMbT = 0
    state.fuelFlowDMbT = 0
    state.fuelFlowTMbT = 0

    if dt and not d and not t then
      state.fuelFlowSource = "DT"
      state.fuelFlowDTMbT = injection
      state.fuelFlowMbT = injection
      return
    end

    if (not dt) and d and t then
      local split = injection * 0.5
      state.fuelFlowSource = "D+T"
      state.fuelFlowDMbT = split
      state.fuelFlowTMbT = split
      state.fuelFlowMbT = injection
      return
    end

    if dt and (d or t) then
      state.fuelFlowSource = "HYBRID"
      state.fuelFlowDTMbT = injection
      state.fuelFlowMbT = injection
      return
    end
  end

  function runtime.refreshAll()
    local wasIgnited = state.ignition
    scanPeripherals()
    scanBlockReaders()
    if type(ensureRelayLow) == "function" then
      -- Securite: la ligne LAS reste forcee a 0 hors pulse d'ignition.
      ensureRelayLow("laser_charge")
    end
    readLaser()
    readReactor()
    readInductionStatus()
    readReaders()
    updateFuelFlow()

    logTransition("reactorPresent", state.reactorPresent, "Reactor peripheral presence changed", "warn", {
      reactorPresent = state.reactorPresent and "true" or "false",
      reactor = hw.reactorName or "none",
      logic = hw.logicName or "none",
    })
    logTransition("reactorFormed", state.reactorFormed, "Reactor formed state changed", "info", {
      formed = state.reactorFormed and "true" or "false",
    })
    logTransition("ignition", state.ignition, "Reactor ignition state changed", state.ignition and "info" or "warn", {
      ignition = state.ignition and "true" or "false",
      plasmaTemp = tostring(state.plasmaTemp),
    })
    logTransition("laserPresent", state.laserPresent, "Laser peripheral presence changed", "warn", {
      laserPresent = state.laserPresent and "true" or "false",
      laser = hw.laserName or "none",
      count = tostring(state.laserDetectedCount or 0),
    })
    logTransition("inductionPresent", state.inductionPresent, "Induction peripheral presence changed", "warn", {
      inductionPresent = state.inductionPresent and "true" or "false",
      induction = hw.inductionName or "none",
    })
    logTransition("fuelFlowSource", state.fuelFlowSource, "Fuel flow mode changed", "info", {
      flow = state.fuelFlowSource,
      mbt = tostring(state.fuelFlowMbT),
    })

    if (not wasIgnited) and state.ignition then
      pushEvent("Reactor running")
    end

    if (state.tick or 0) % 120 == 0 then
      logDebug("Refresh summary", {
        ignition = state.ignition and "true" or "false",
        laserPct = string.format("%.1f", tonumber(state.laserPct or 0)),
        energyPct = string.format("%.1f", tonumber(state.energyPct or 0)),
        fuel = state.fuelFlowSource,
      })
    end

    refreshSetupDeviceStatus()
    state.tick = (state.tick or 0) + 1
  end

  return runtime
end

return M
