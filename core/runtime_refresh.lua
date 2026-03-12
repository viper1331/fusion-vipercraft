-- core/runtime_refresh.lua
-- Refresh cycle runtime (peripherals + mesures).

local M = {}

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
  local refreshSetupDeviceStatus = api.refreshSetupDeviceStatus
  local pushEvent = api.pushEvent

  local runtime = {}

  local function detectReactorFormed()
    if hw.logic then
      local ok, formed = tryMethods(hw.logic, { "isFormed", "getFormed" })
      if ok then return formed == true end
    end

    if hw.reactor then
      local okPlasma, plasma = tryMethods(hw.reactor, { "getPlasmaTemperature", "getPlasmaTemp", "getPlasmaHeat" })
      local okIgn, ign = tryMethods(hw.reactor, { "isIgnited", "getIgnitionStatus" })
      if okPlasma and plasma ~= nil then return true end
      if okIgn and ign ~= nil then return true end
    end

    return false
  end

  local function readLaser()
    state.laserPresent = hw.laser ~= nil
    if not hw.laser then
      state.laserEnergy = 0
      state.laserMax = 1
      state.laserPct = 0
      return
    end

    local _, e = tryMethods(hw.laser, { "getEnergy", "getEnergyStored", "getStored" })
    local _, m = tryMethods(hw.laser, { "getMaxEnergy", "getMaxEnergyStored", "getCapacity" })

    state.laserEnergy = toNumber(e, 0)
    state.laserMax = math.max(1, toNumber(m, 1))
    state.laserPct = clamp((state.laserEnergy * 100) / state.laserMax, 0, 100)
  end

  local function readReactor()
    state.reactorPresent = hw.reactor ~= nil or hw.logic ~= nil
    state.reactorFormed = detectReactorFormed()

    if hw.logic then
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
    elseif hw.reactor then
      local okIgn, ign = tryMethods(hw.reactor, { "isIgnited", "getIgnitionStatus" })
      state.ignition = okIgn and (ign == true or ign == "true") or false

      local _, plasma = tryMethods(hw.reactor, { "getPlasmaTemperature", "getPlasmaTemp", "getPlasmaHeat" })
      state.plasmaTemp = toNumber(plasma, 0)

      local _, ignTemp = tryMethods(hw.reactor, { "getIgnitionTemperature", "getIgnitionTemp" })
      state.ignitionTemp = toNumber(ignTemp, 0)
      state.minTemp = state.ignitionTemp + 10000

      local _, caseTemp = tryMethods(hw.reactor, { "getCaseTemperature", "getCasingTemperature" })
      state.caseTemp = toNumber(caseTemp, 0)
    else
      state.ignition = false
      state.plasmaTemp = 0
      state.ignitionTemp = 0
      state.caseTemp = 0
    end

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

    state.laserLineOn = readRelayOutputState("laser_charge", state.laserChargeOn)
    state.dOpen = readRelayOutputState("deuterium", state.dOpen)
    state.tOpen = readRelayOutputState("tritium", state.tOpen)
  end

  function runtime.refreshAll()
    local wasIgnited = state.ignition
    scanPeripherals()
    scanBlockReaders()
    readLaser()
    readReactor()
    readInductionStatus()
    readReaders()
    if (not wasIgnited) and state.ignition then
      pushEvent("Reactor running")
    end
    refreshSetupDeviceStatus()
    state.tick = (state.tick or 0) + 1
  end

  return runtime
end

return M
