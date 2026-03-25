local M = {}
local TomAssets = require("ui.toms.assets")

function M.asNumber(value, fallback)
  local n = tonumber(value)
  if n == nil then
    return fallback or 0
  end
  return n
end

function M.asText(value, fallback)
  local out = tostring(value or "")
  if out == "" then
    return tostring(fallback or "N/A")
  end
  return out
end

function M.clamp(value, lo, hi)
  if value < lo then
    return lo
  end
  if value > hi then
    return hi
  end
  return value
end

function M.build(options)
  options = type(options) == "table" and options or {}
  local state = assert(options.state, "state is required")
  local hw = assert(options.hw, "hw is required")
  local CFG = type(options.CFG) == "table" and options.CFG or {}
  local C = type(options.C) == "table" and options.C or {}

  local function phaseText()
    if type(options.reactorPhase) == "function" then
      return tostring(options.reactorPhase())
    end
    return M.asText(state.status, "INIT")
  end

  local function phaseTone()
    if type(options.phaseColor) == "function" then
      return options.phaseColor(phaseText())
    end
    return C.info
  end

  local function laserTone(theme)
    local palette = type(theme) == "table" and type(theme.palette) == "table" and theme.palette or {}
    local st = tostring(state.laserState or "ABSENT")
    if st == "READY" then return palette.ok end
    if st == "CHARGING" then return palette.warning end
    if st == "INSUFFICIENT" then return palette.warning end
    if st == "ABSENT" then return palette.critical end
    return palette.textMuted
  end

  local function reactorVisualState()
    if not state.reactorPresent then return "warning" end
    if not state.reactorFormed then return "warning" end
    if state.ignition then return "active" end
    if state.laserReady and (#(state.ignitionBlockers or {}) == 0) then
      return "ready"
    end
    return "idle"
  end

  local function globalStatus()
    local blockers = type(state.ignitionBlockers) == "table" and state.ignitionBlockers or {}
    local warnings = type(state.safetyWarnings) == "table" and state.safetyWarnings or {}
    if #blockers > 0 then
      return "BLOCKED", C.bad
    end
    if state.ignition then
      return "RUNNING", C.ok
    end
    if #warnings > 0 then
      return "WARNING", C.warn
    end
    return "READY", C.info
  end

  local function formatTemperature(value, decimals)
    if type(options.formatTemperature) == "function" then
      return tostring(options.formatTemperature(value, { compact = true, decimals = decimals or 1 }))
    end
    return string.format("%.1f C", M.asNumber(value, 0))
  end

  local function formatEnergy(value)
    if type(options.formatEnergy) == "function" then
      return tostring(options.formatEnergy(value))
    end
    return M.asText(value, "N/A")
  end

  local function formatEnergyTick(value)
    if type(options.formatEnergyPerTick) == "function" then
      return tostring(options.formatEnergyPerTick(value))
    end
    return M.asText(value, "N/A")
  end

  return function(theme)
    local warnings = type(state.safetyWarnings) == "table" and state.safetyWarnings or {}
    local events = type(state.eventLog) == "table" and state.eventLog or {}
    local blockers = type(state.ignitionBlockers) == "table" and state.ignitionBlockers or {}
    local laserCount = TomAssets.resolveLaserModuleCount(CFG, state, 1)
    local activeLasers = 0
    if state.laserState == "READY" then
      activeLasers = laserCount
    elseif state.laserState == "CHARGING" then
      activeLasers = math.max(1, math.floor(laserCount / 2))
    end
    if not state.laserPresent then
      activeLasers = 0
    end

    local statusText, statusTone = globalStatus()
    local laserRatio = M.clamp(M.asNumber(state.laserPct, 0) / 100, 0, 1)
    local gridRatio = M.clamp(M.asNumber(state.energyPct, 0) / 100, 0, 1)
    return {
      phase = phaseText(),
      phaseTone = phaseTone(),
      laserTone = laserTone(theme),
      warnings = warnings,
      events = events,
      blockers = blockers,
      reactorState = reactorVisualState(),
      statusText = statusText,
      statusTone = statusTone,
      active = state.ignition == true,
      ignition = state.ignition == true,
      injectionRate = math.floor(M.asNumber(state.injectionRate, 0)),
      plasmaTemp = formatTemperature(state.plasmaTemp, 1),
      caseTemp = formatTemperature(state.caseTemp, 1),
      passiveGeneration = formatEnergyTick(state.passiveGeneration),
      steamProduction = string.format("%.1f mB/t", M.asNumber(state.steamProduction, 0)),
      fuelFlow = string.format("%.1f mB/t", M.asNumber(state.fuelFlowMbT, 0)),
      fuelMode = M.asText(type(options.getRuntimeFuelMode) == "function" and options.getRuntimeFuelMode() or "N/A", "N/A"),
      laserState = M.asText(state.laserStatusText or state.laserState, "ABS"),
      laserPct = M.clamp(math.floor(M.asNumber(state.laserPct, 0) + 0.5), 0, 999),
      laserRatio = laserRatio,
      laserEnergy = formatEnergy(state.laserEnergy),
      laserMax = formatEnergy(state.laserMax),
      laserNeed = formatEnergy(state.laserThresholdRaw),
      laserCount = laserCount,
      laserActiveCount = activeLasers,
      laserCharging = state.laserChargeOn == true,
      laserActive = state.laserLineOn == true,
      energyPct = M.clamp(M.asNumber(state.energyPct, 0), 0, 100),
      energyRatio = gridRatio,
      energyKnown = state.energyKnown == true,
      energyStored = formatEnergy(state.energyStored),
      energyMax = formatEnergy(state.energyMax),
      lastAction = M.asText(state.lastAction, "NONE"),
      monitorName = M.asText(hw.monitorName, "terminal"),
      backendName = M.asText(hw.monitorBackend, "cc_monitor"),
      tOpen = state.tOpen == true,
      dtOpen = state.dtOpen == true,
      dOpen = state.dOpen == true,
      hohlraum = state.hohlraumPresent and "PRESENT" or "MISSING",
      allowControl = CFG.allowControl == true,
      injectionWritable = state.injectionWritable == true,
    }
  end
end

return M
