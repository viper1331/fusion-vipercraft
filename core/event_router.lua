-- core/event_router.lua
-- Dispatch centralise des evenements runtime.

local M = {}

local function handleMonitorSelectionChar(ch, api)
  if ch == "1" then api.selectMonitorByIndex(1)
  elseif ch == "2" then api.selectMonitorByIndex(2)
  elseif ch == "3" then api.selectMonitorByIndex(3)
  elseif ch == "4" then api.selectMonitorByIndex(4)
  elseif ch == "q" or ch == "x" then api.stopMonitorSelection() end
end

local function handleMainChar(ch, api)
  local state = api.state

  if ch == "q" then
    state.running = false
  elseif ch == "a" then
    state.autoMaster = not state.autoMaster
    if not state.autoMaster then
      api.openDTFuel(false)
      api.openSeparatedGases(false)
      api.setLaserCharge(false)
      state.ignitionSequencePending = false
    end
  elseif ch == "z" then
    state.chargeAuto = not state.chargeAuto
  elseif ch == "f" then
    state.fusionAuto = not state.fusionAuto
  elseif ch == "g" then
    state.gasAuto = not state.gasAuto
  elseif ch == "m" then
    api.startMonitorSelection()
  elseif ch == "1" then
    state.currentView = "supervision"
    api.pushEvent("View supervision")
  elseif ch == "2" then
    state.currentView = "diagnostic"
    api.pushEvent("View diagnostic")
  elseif ch == "3" then
    state.currentView = "manual"
    api.pushEvent("View manual")
  elseif ch == "4" then
    state.currentView = "induction"
    api.pushEvent("View induction")
  elseif ch == "5" then
    state.currentView = "update"
    api.pushEvent("View update")
  elseif ch == "6" then
    state.currentView = "setup"
    api.pushEvent("View setup")
  elseif ch == "i" then
    api.triggerAutomaticIgnitionSequence()
  elseif ch == "l" then
    api.fireLaser()
  elseif ch == "o" then
    api.openDTFuel(true)
  elseif ch == "p" then
    api.openDTFuel(false)
  end
end

function M.route(ev, p1, p2, p3, api)
  local state = api.state
  local hw = api.hw

  if ev == "char" then
    local ch = string.lower(p1)
    if state.choosingMonitor then
      handleMonitorSelectionChar(ch, api)
    else
      handleMainChar(ch, api)
    end
    return
  end

  if ev == "mouse_click" then
    api.handleClick(p2, p3, "terminal")
    return
  end

  if ev == "monitor_touch" then
    if p1 == hw.monitorName then
      api.handleClick(p2, p3, "monitor")
    end
    return
  end

  if ev == "monitor_resize" or ev == "term_resize" then
    api.setupMonitor()
    state.uiDrawn = false
    return
  end

  if ev == "peripheral" or ev == "peripheral_detach" then
    api.setupMonitor()
    state.uiDrawn = false
    if state.choosingMonitor then
      state.monitorList = api.getMonitorCandidates()
    end
    return
  end
end

return M
