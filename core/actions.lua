-- core/actions.lua
-- Actions runtime, sequences et automatismes.

local M = {}

function M.build(api)
  local state = api.state
  local CFG = api.CFG

  local relayWrite = api.relayWrite
  local pushEvent = api.pushEvent
  local log = api.log or {}
  local logDebug = type(log.debug) == "function" and log.debug or function() end
  local logInfo = type(log.info) == "function" and log.info or function() end
  local logWarn = type(log.warn) == "function" and log.warn or function() end

  local runtimeAlerts = api.runtimeAlerts

  local actions = {}

  function actions.setLaserCharge(on)
    if state.laserChargeOn == on then return end
    relayWrite("laser_charge", on)
    state.laserChargeOn = on
    state.lastAction = on and "Charge laser ON" or "Charge laser OFF"
    pushEvent(state.lastAction)
    logInfo("Laser charge line toggled", { on = on and "true" or "false" })
  end

  function actions.fireLaser()
    if not state.ignitionSequencePending then
      state.lastAction = "Pulse LAS bloque (hors ignition)"
      pushEvent("Pulse LAS blocked")
      logWarn("Laser pulse blocked: ignition sequence not pending")
      return false
    end

    -- Une fois la fusion engagee, on bloque les pulses manuels
    -- pour eviter de consommer un nouveau hohlraum.
    if state.ignition then
      state.lastAction = "Pulse LAS bloque (reacteur actif)"
      pushEvent("Pulse LAS blocked")
      logWarn("Laser pulse blocked: reactor already ignited")
      return false
    end

    if not state.hohlraumPresent then
      state.lastAction = "Pulse LAS bloque (hohlraum absent)"
      pushEvent("Pulse LAS blocked")
      logWarn("Laser pulse blocked: hohlraum missing")
      return false
    end

    if CFG.actions.laser_fire and relayWrite("laser_fire", true) then
      state.lastLaserPulseAt = os.clock()
      state.lastAction = "Pulse LAS"
      pushEvent("Pulse LAS")
      logInfo("Laser pulse fired")
      return true
    else
      state.lastAction = "Laser pulse non cable"
      pushEvent("Pulse LAS FAIL")
      logWarn("Laser pulse failed: relay not wired")
      return false
    end
  end

  function actions.openDTFuel(on)
    if state.dtOpen == on then return end
    if CFG.actions.dt_fuel then
      relayWrite("dt_fuel", on)
    end
    state.dtOpen = on
    state.lastAction = on and "DT OPEN" or "DT CLOSED"
    pushEvent(state.lastAction)
    logDebug("DT fuel line changed", { on = on and "true" or "false" })
  end

  function actions.openDeuterium(on)
    if state.dOpen == on then return end
    if CFG.actions.deuterium then
      relayWrite("deuterium", on)
    end
    state.dOpen = on
    pushEvent(on and "D line OPEN" or "D line CLOSED")
    logDebug("Deuterium line changed", { on = on and "true" or "false" })
  end

  function actions.openTritium(on)
    if state.tOpen == on then return end
    if CFG.actions.tritium then
      relayWrite("tritium", on)
    end
    state.tOpen = on
    pushEvent(on and "T line OPEN" or "T line CLOSED")
    logDebug("Tritium line changed", { on = on and "true" or "false" })
  end

  function actions.openSeparatedGases(on)
    actions.openDeuterium(on)
    actions.openTritium(on)
    state.lastAction = on and "Ouverture tanks separes" or "Fermeture tanks separes"
  end

  function actions.hardStop(reason)
    actions.openDTFuel(false)
    actions.openSeparatedGases(false)
    actions.setLaserCharge(false)
    state.ignitionSequencePending = false
    state.status = reason or "EMERGENCY STOP"
    state.alert = "DANGER"
    state.lastAction = "Arret securite"
    pushEvent("Emergency stop")
    logWarn("Emergency stop", { reason = reason or "unspecified" })
  end

  function actions.startReactorSequence()
    state.ignitionChecklist = runtimeAlerts.getIgnitionChecklist()
    state.ignitionBlockers = runtimeAlerts.getIgnitionBlockers()

    if state.ignitionSequencePending then
      state.status = "FIRING"
      logWarn("Start sequence ignored: already pending")
      return false
    end

    if not runtimeAlerts.canIgnite() then
      state.status = "BLOCKED"
      state.lastAction = "Ignition refused"
      pushEvent("Ignition refused")
      logWarn("Ignition blocked by runtime alerts")
      return false
    end

    if not state.hohlraumPresent then
      state.status = "BLOCKED"
      state.lastAction = "Ignition refusee: hohlraum absent"
      pushEvent("Ignition refused (hohlraum)")
      logWarn("Ignition blocked: hohlraum missing")
      return false
    end

    state.ignitionSequencePending = true
    state.lastIgnitionAttempt = os.clock()
    actions.openDTFuel(false)
    sleep(0.15)
    if not actions.fireLaser() then
      state.ignitionSequencePending = false
      state.status = "BLOCKED"
      state.lastAction = "Ignition refusee: pulse LAS"
      pushEvent("Ignition failed")
      logWarn("Ignition failed: LAS pulse failure")
      return false
    end
    state.status = "FIRING"
    state.lastAction = "Start sequence"
    pushEvent("Ignition start sequence")
    logInfo("Ignition sequence started")
    return true
  end

  function actions.stopReactorSequence(reason)
    actions.openDTFuel(false)
    actions.openSeparatedGases(false)
    actions.setLaserCharge(false)
    state.ignitionSequencePending = false
    state.status = reason or "ARRET"
    state.lastAction = "Arret commande"
    pushEvent("Reactor stop sequence")
    logInfo("Reactor stop sequence", { reason = reason or "manual" })
  end

  function actions.triggerAutomaticIgnitionSequence()
    return actions.startReactorSequence()
  end

  function actions.autoChargeLaser()
    if not state.chargeAuto then return end

    if state.laserPct >= CFG.laserChargeStopPct then
      if state.laserChargeOn then actions.setLaserCharge(false) end
    elseif state.laserPct <= CFG.laserChargeStartPct then
      if not state.laserChargeOn then actions.setLaserCharge(true) end
    end
  end

  function actions.autoFusionControl()
    if not state.fusionAuto then return end

    if not state.reactorFormed then
      state.status = "BLOCKED"
      actions.openDTFuel(false)
      actions.openSeparatedGases(false)
      return
    end

    if (not state.ignition) and (not state.ignitionSequencePending) and runtimeAlerts.isLaserReady() then
      actions.triggerAutomaticIgnitionSequence()
      return
    end

    if state.energyKnown then
      if state.energyPct <= CFG.energyLowPct then
        if state.ignition and not state.dtOpen then
          actions.openDTFuel(true)
          actions.openSeparatedGases(false)
          state.status = "Energie basse : D-T actif"
        elseif not state.ignition then
          state.status = state.ignitionSequencePending and "Ignition en attente" or "Attente seuil LAS"
        end
      elseif state.energyPct >= CFG.energyHighPct and state.ignition then
        actions.openDTFuel(false)
        actions.openSeparatedGases(false)
        state.status = "Energie pleine : stop injection"
      else
        if state.ignition and not runtimeAlerts.isRuntimeFuelOk() then
          state.status = "RUNNING / STARVED"
        else
          state.status = state.ignition and ("RUNNING / " .. runtimeAlerts.getRuntimeFuelMode()) or "READY"
        end
      end
    else
      if not state.ignition and not state.ignitionSequencePending and runtimeAlerts.isLaserReady() then
        actions.triggerAutomaticIgnitionSequence()
      else
        if state.ignition and not runtimeAlerts.isRuntimeFuelOk() then
          state.status = "RUNNING / STARVED"
        else
          state.status = state.ignition and ("RUNNING / " .. runtimeAlerts.getRuntimeFuelMode()) or (state.ignitionSequencePending and "FIRING" or "READY")
        end
      end
    end
  end

  function actions.autoGasSanity()
    if not state.gasAuto then return end
    if (not state.ignition) and state.dtOpen and (state.dOpen or state.tOpen) then
      actions.openSeparatedGases(false)
    end
  end

  function actions.autoSafety()
    if not state.autoMaster then return end
    if CFG.emergencyStopIfReactorMissing and not state.reactorPresent then
      actions.hardStop("Reactor absent")
    end
  end

  function actions.fullAuto()
    if not state.autoMaster then
      runtimeAlerts.updateAlerts()
      logDebug("fullAuto skipped: autoMaster off")
      return
    end
    actions.autoSafety()
    actions.autoChargeLaser()
    actions.autoFusionControl()
    actions.autoGasSanity()
    runtimeAlerts.updateAlerts()
  end

  return actions
end

return M
