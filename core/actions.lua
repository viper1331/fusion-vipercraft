-- core/actions.lua
-- Actions runtime, sequences et automatismes.

local M = {}

function M.build(api)
  local state = api.state
  local CFG = api.CFG

  local relayWrite = api.relayWrite
  local pushEvent = api.pushEvent

  local runtimeAlerts = api.runtimeAlerts

  local actions = {}

  function actions.setLaserCharge(on)
    if state.laserChargeOn == on then return end
    relayWrite("laser_charge", on)
    state.laserChargeOn = on
    state.lastAction = on and "Charge laser ON" or "Charge laser OFF"
    pushEvent(state.lastAction)
  end

  function actions.fireLaser()
    if CFG.actions.laser_fire and relayWrite("laser_fire", true) then
      state.lastAction = "Pulse LAS"
      pushEvent("Pulse LAS")
    else
      state.lastAction = "Laser pulse non cable"
      pushEvent("Pulse LAS FAIL")
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
  end

  function actions.openDeuterium(on)
    if state.dOpen == on then return end
    if CFG.actions.deuterium then
      relayWrite("deuterium", on)
    end
    state.dOpen = on
    pushEvent(on and "D line OPEN" or "D line CLOSED")
  end

  function actions.openTritium(on)
    if state.tOpen == on then return end
    if CFG.actions.tritium then
      relayWrite("tritium", on)
    end
    state.tOpen = on
    pushEvent(on and "T line OPEN" or "T line CLOSED")
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
  end

  function actions.startReactorSequence()
    state.ignitionChecklist = runtimeAlerts.getIgnitionChecklist()
    state.ignitionBlockers = runtimeAlerts.getIgnitionBlockers()

    if state.ignitionSequencePending then
      state.status = "FIRING"
      return false
    end

    if not runtimeAlerts.canIgnite() then
      state.status = "BLOCKED"
      state.lastAction = "Ignition refused"
      pushEvent("Ignition refused")
      return false
    end

    state.ignitionSequencePending = true
    state.lastIgnitionAttempt = os.clock()
    actions.openDTFuel(false)
    sleep(0.15)
    actions.fireLaser()
    state.status = "FIRING"
    state.lastAction = "Start sequence"
    pushEvent("Ignition start sequence")
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

    if (not state.ignition) and (not state.ignitionSequencePending) and state.laserEnergy >= CFG.ignitionLaserEnergyThreshold then
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
          state.status = state.ignitionSequencePending and "Ignition en attente" or "Attente seuil 2.0G"
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
      if not state.ignition and not state.ignitionSequencePending and state.laserEnergy >= CFG.ignitionLaserEnergyThreshold then
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
