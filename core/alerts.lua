-- core/alerts.lua
-- Calcul des alertes runtime et phases reactor.
-- Cette version evite les faux positifs d'ignition lies a l'etat "LAS OFF"
-- en se basant sur l'energie reellement exploitable.

local M = {}
local CoreEnergy = require("core.energy")

function M.build(api)
  local state = api.state
  local hw = api.hw
  local CFG = api.CFG
  local C = api.C
  local MIN_LASER_IGNITION_FE = 1000000000

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

  local function formatLaserThreshold()
    return CoreEnergy.formatScaled(MIN_LASER_IGNITION_FE, "FE", {
      compact = true,
      decimals = 2,
    })
  end

  local function toFe(value, sourceUnit)
    local energyJ = CoreEnergy.toJ(toNumber(value, 0), sourceUnit)
    return CoreEnergy.fromJ(energyJ, "fe")
  end

  local function getLaserThresholdJ()
    return CoreEnergy.toJ(MIN_LASER_IGNITION_FE, "fe")
  end

  function runtime.getLaserThresholdRaw()
    local thresholdJ = getLaserThresholdJ()
    return CoreEnergy.thresholdFromJToSource(thresholdJ, laserSourceUnit())
  end

  function runtime.getLaserState()
    local thresholdRaw = runtime.getLaserThresholdRaw()
    local energyRaw = toNumber(state.laserEnergy, 0)
    local sourceUnit = laserSourceUnit()
    local energyFe = toFe(energyRaw, sourceUnit)
    local present = state.laserPresent == true
    local ready = present and energyFe >= MIN_LASER_IGNITION_FE
    local chargingSignal = (state.laserChargeOn == true) or (state.laserLineOn == true)
    local status = "ABSENT"

    if not present then
      status = "ABSENT"
    elseif ready then
      status = "READY"
    elseif chargingSignal then
      status = "CHARGING"
    else
      status = "INSUFFICIENT"
    end

    local labelByStatus = {
      ABSENT = "LASER ABSENT",
      CHARGING = "LAS CHARGE INSUFFICIENT",
      READY = "LAS CHARGE READY",
      INSUFFICIENT = "LAS CHARGE INSUFFICIENT",
    }

    local shortByStatus = {
      ABSENT = "ABS",
      CHARGING = "CHG",
      READY = "READY",
      INSUFFICIENT = "LOW",
    }

    return {
      status = status,
      present = present,
      ready = ready,
      charging = chargingSignal,
      energyRaw = energyRaw,
      energyFe = energyFe,
      thresholdRaw = thresholdRaw,
      thresholdFe = MIN_LASER_IGNITION_FE,
      label = labelByStatus[status] or status,
      short = shortByStatus[status] or status,
    }
  end

  function runtime.isLaserReady()
    return runtime.getLaserState().ready
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

  local function getCriticalIgnitionBlockers()
    local blockers = {}
    local laser = runtime.getLaserState()
    local thresholdLabel = formatLaserThreshold()

    if not laser.present then
      table.insert(blockers, "LASER ABSENT")
    elseif not laser.ready then
      table.insert(blockers, "LAS CHARGE BELOW " .. thresholdLabel)
    end

    if not state.tOpen then table.insert(blockers, "T LOCK CLOSED") end
    if not state.dOpen then table.insert(blockers, "D LOCK CLOSED") end
    if not state.hohlraumPresent then table.insert(blockers, "HOHLRAUM ABSENT") end

    if not state.reactorPresent then
      table.insert(blockers, "REACTOR ABSENT")
    elseif not state.reactorFormed then
      table.insert(blockers, "REACTOR UNFORMED")
    end

    if not isRelayMappedAndPresent("laser_charge")
      or not isRelayMappedAndPresent("deuterium")
      or not isRelayMappedAndPresent("tritium") then
      table.insert(blockers, "CONTROL LINE FAIL")
    end

    return blockers
  end

  function runtime.reactorPhase()
    local laser = runtime.getLaserState()
    if state.alert == "DANGER" and (not state.ignition) then return "SAFE STOP" end
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

    if laser.status == "CHARGING" then return "CHARGING" end
    if laser.status == "READY" then return "READY" end
    if laser.status == "ABSENT" then return "LASER ABSENT" end
    if laser.status == "INSUFFICIENT" then return "CHARGE LOW" end
    return "CHARGE LOW"
  end

  function runtime.phaseColor(phase)
    if contains(phase, "RUNNING") and not contains(phase, "STARVED") then return C.ok end
    if phase == "RUNNING" or phase == "IGNITED" then return C.ok end
    if phase == "READY" or phase == "CHARGING" or phase == "FIRING" or phase == "CHARGE LOW" then return C.warn end
    if phase == "LASER IDLE" then return C.dim end
    if phase == "SAFE STOP" or phase == "OFFLINE" or phase == "UNFORMED" or phase == "BLOCKED"
      or phase == "LASER ABSENT" or contains(phase, "STARVED") then
      return C.bad
    end
    return C.dim
  end

  function runtime.getIgnitionChecklist()
    local thresholdLabel = formatLaserThreshold()
    local laser = runtime.getLaserState()
    local laserItem
    if not laser.present then
      laserItem = { key = "LASER PRESENT", ok = false, wait = false }
    else
      laserItem = { key = "LAS >= " .. thresholdLabel, ok = laser.ready, wait = (not laser.ready) and laser.charging }
    end

    return {
      laserItem,
      { key = "T LOCK OPEN", ok = state.tOpen },
      { key = "D LOCK OPEN", ok = state.dOpen },
      { key = "HOHLRAUM OK", ok = state.hohlraumPresent },
      { key = "REACTOR FORMED", ok = state.reactorPresent and state.reactorFormed },
    }
  end

  function runtime.getIgnitionBlockers()
    return getCriticalIgnitionBlockers()
  end

  function runtime.canIgnite()
    if not CoreReactor.canIgnite(state) then return false end
    return #getCriticalIgnitionBlockers() == 0
  end

  function runtime.computeSafetyWarnings()
    local warnings = {}
    local critical = false
    local laser = runtime.getLaserState()

    if not state.reactorPresent then
      table.insert(warnings, "REACTOR ABSENT")
      critical = true
    elseif not state.reactorFormed then
      table.insert(warnings, "REACTOR UNFORMED")
    end

    if not state.ignition then
      local thresholdLabel = formatLaserThreshold()
      if laser.status == "ABSENT" then
        table.insert(warnings, "LASER ABSENT")
      elseif not laser.ready then
        local msg = "LAS CHARGE INSUFFICIENT (< " .. thresholdLabel .. ")"
        if laser.charging then
          msg = msg .. " CHG " .. string.format("%3.0f%%", toNumber(state.laserPct, 0))
        end
        table.insert(warnings, msg)
      end
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

    if #hw.readerRoles.unknown > 0 then
      table.insert(warnings, "FALLBACK DETECTION")
    end

    return warnings, critical
  end

  function runtime.updateAlerts()
    local laser = runtime.getLaserState()
    state.laserState = laser.status
    state.laserStatusText = laser.short
    state.laserReady = laser.ready
    state.laserThresholdRaw = laser.thresholdRaw

    state.ignitionChecklist = runtime.getIgnitionChecklist()
    state.ignitionBlockers = getCriticalIgnitionBlockers()

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
