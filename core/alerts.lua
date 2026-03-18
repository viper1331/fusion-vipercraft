-- core/alerts.lua
-- Calcul des alertes runtime et phases reactor.

local M = {}
local CoreEnergy = require("core.energy")

function M.build(api)
  local state = api.state
  local hw = api.hw
  local CFG = api.CFG
  local C = api.C

  local contains = api.contains
  local toNumber = api.toNumber
  local CoreReactor = api.CoreReactor

  local runtime = {}

  local function isRelayMappedAndPresent(actionName)
    local action = type(CFG.actions) == "table" and CFG.actions[actionName] or nil
    if type(action) ~= "table" then return false end
    if type(action.relay) ~= "string" or action.relay == "" then return false end
    return hw.relays[action.relay] ~= nil
  end

  local function currentEnergyUnit()
    return CoreEnergy.sanitizeUnit(CFG.energyUnit, "j")
  end

  local function laserSourceUnit()
    return CoreEnergy.sanitizeUnit(state.laserEnergySourceUnit, currentEnergyUnit())
  end

  local function formatEnergyThreshold(joules)
    return CoreEnergy.formatEnergyFromJ(toNumber(joules, 0), currentEnergyUnit(), {
      compact = true,
      decimals = 0,
    })
  end

  function runtime.getLaserThresholdRaw()
    local thresholdJ = toNumber(CFG and CFG.ignitionLaserEnergyThreshold, 0)
    return CoreEnergy.thresholdFromJToSource(thresholdJ, laserSourceUnit())
  end

  function runtime.isLaserReady()
    return toNumber(state.laserEnergy, 0) >= runtime.getLaserThresholdRaw()
  end

  function runtime.getRuntimeFuelMode()
    local dt = state.dtOpen == true
    local d = state.dOpen == true
    local t = state.tOpen == true

    if dt and not d and not t then return "DT" end
    if (not dt) and d and t then return "D+T" end
    if dt and (d or t) then return "HYBRID" end
    return "STARVED"
  end

  function runtime.isRuntimeFuelOk()
    return (state.dOpen and state.tOpen) or state.dtOpen
  end

  function runtime.reactorPhase()
    if state.alert == "DANGER" then return "SAFE STOP" end
    if not state.reactorPresent then return "OFFLINE" end
    if not state.reactorFormed then return "UNFORMED" end
    if state.ignition then
      if runtime.isRuntimeFuelOk() then
        local mode = runtime.getRuntimeFuelMode()
        return mode == "HYBRID" and "RUNNING / HYBRID" or ("RUNNING / " .. mode)
      end
      return "RUNNING / STARVED"
    end
    if #state.ignitionBlockers > 0 then return "BLOCKED" end
    if state.ignitionSequencePending then return "FIRING" end
    if state.laserChargeOn or state.laserLineOn then return "CHARGING" end

    local thresholdRaw = runtime.getLaserThresholdRaw()
    local laserEnergy = toNumber(state.laserEnergy, 0)
    if thresholdRaw > 0 and laserEnergy >= thresholdRaw then return "READY" end

    return "READY"
  end

  function runtime.phaseColor(phase)
    if contains(phase, "RUNNING") and not contains(phase, "STARVED") then return C.ok end
    if phase == "RUNNING" or phase == "IGNITED" then return C.ok end
    if phase == "READY" then return C.warn end
    if phase == "CHARGING" or phase == "FIRING" then return C.warn end
    if phase == "SAFE STOP" or phase == "OFFLINE" or phase == "UNFORMED" or phase == "BLOCKED" or contains(phase, "STARVED") then return C.bad end
    return C.dim
  end

  function runtime.getIgnitionChecklist()
    local thresholdLabel = formatEnergyThreshold(CFG.ignitionLaserEnergyThreshold)
    return {
      { key = "LAS >= " .. thresholdLabel, ok = runtime.isLaserReady(), wait = state.laserPresent },
      { key = "T LOCK OPEN", ok = state.tOpen },
      { key = "D LOCK OPEN", ok = state.dOpen },
      { key = "HOHLRAUM OK", ok = state.hohlraumPresent },
      { key = "REACTOR FORMED", ok = state.reactorPresent and state.reactorFormed },
      { key = "SAFETY OK", ok = #state.safetyWarnings == 0 and state.alert ~= "DANGER" },
    }
  end

  function runtime.getIgnitionBlockers()
    local blockers = {}
    for _, item in ipairs(runtime.getIgnitionChecklist()) do
      if not item.ok then
        table.insert(blockers, item.key)
      end
    end
    return blockers
  end

  function runtime.canIgnite()
    if not CoreReactor.canIgnite(state) then return false end
    return #runtime.getIgnitionBlockers() == 0
  end

  function runtime.computeSafetyWarnings()
    local warnings = {}
    local critical = false

    if not state.reactorPresent then
      table.insert(warnings, "REACTOR ABSENT")
      critical = true
    elseif not state.reactorFormed then
      table.insert(warnings, "REACTOR UNFORMED")
    end

    if (not state.ignition) and (not runtime.isLaserReady()) then
      table.insert(warnings, "LAS BELOW " .. formatEnergyThreshold(CFG.ignitionLaserEnergyThreshold))
    end
    if state.ignition then
      if not runtime.isRuntimeFuelOk() then
        table.insert(warnings, "RUNTIME FUEL FAIL")
        table.insert(warnings, "NO FUEL FLOW")
        table.insert(warnings, "STARVED")
      end
    else
      if not state.tOpen then table.insert(warnings, "TANK T CLOSED") end
      if not state.dOpen then table.insert(warnings, "TANK D CLOSED") end
      if not state.hohlraumPresent then table.insert(warnings, "HOHLRAUM ABSENT") end
    end

    if not hw.readerRoles.deuterium or not hw.readerRoles.tritium then
      table.insert(warnings, "FUEL SENSOR FAIL")
    end
    if (not hw.readerRoles.inventory) and (#(hw.readerRoles.active or {}) == 0) then
      table.insert(warnings, "READER AUX FAIL")
    end

    if not isRelayMappedAndPresent("laser_charge")
      or not isRelayMappedAndPresent("deuterium")
      or not isRelayMappedAndPresent("tritium") then
      table.insert(warnings, "CONTROL LINE FAIL")
      critical = true
    end

    if (not state.ignition) and #state.ignitionBlockers > 0 then
      table.insert(warnings, "IGNITION BLOCKED")
    end

    if #hw.readerRoles.unknown > 0 then table.insert(warnings, "FALLBACK DETECTION") end
    return warnings, critical
  end

  function runtime.updateAlerts()
    state.ignitionChecklist = runtime.getIgnitionChecklist()
    state.ignitionBlockers = runtime.getIgnitionBlockers()
    local warnings, critical = runtime.computeSafetyWarnings()
    state.safetyWarnings = warnings
    local preStartBlocked = (not state.ignition) and (#state.ignitionBlockers > 0)
    if critical then
      state.alert = "DANGER"
    elseif #warnings > 0 or preStartBlocked or (state.energyKnown and state.energyPct <= CFG.energyLowPct) then
      state.alert = "WARN"
    elseif state.ignition then
      state.alert = "OK"
    else
      state.alert = "INFO"
    end
  end

  return runtime
end

return M
