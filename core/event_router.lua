-- core/event_router.lua
-- Dispatch centralise des evenements runtime.

local M = {}
local CoreUiAdaptive = require("core.ui_adaptive")

local function unpackMonitorCoords(hw, p1, p2, p3, p4)
  if type(p1) == "string" then
    if hw.monitorName and p1 ~= hw.monitorName then
      return nil, nil
    end
    if type(p2) == "number" and type(p3) == "number" then
      return tonumber(p2), tonumber(p3)
    end
    if type(p3) == "number" and type(p4) == "number" then
      return tonumber(p3), tonumber(p4)
    end
    return tonumber(p2), tonumber(p3)
  end
  return tonumber(p1), tonumber(p2)
end

local function normalizeMonitorCoords(hw, x, y)
  if type(x) ~= "number" or type(y) ~= "number" then
    return nil, nil
  end

  local surface = hw.displaySurface or hw.monitor
  local sw, sh = nil, nil
  if surface and type(surface.getSize) == "function" then
    local ok, w, h = pcall(surface.getSize)
    if ok then
      sw = tonumber(w)
      sh = tonumber(h)
    end
  end

  if type(hw.monitorTouchMapper) == "function" and sw and sh and (x > sw or y > sh) then
    local okMap, mappedX, mappedY = pcall(hw.monitorTouchMapper, x, y)
    if okMap then
      x = tonumber(mappedX) or x
      y = tonumber(mappedY) or y
    end
  end

  return math.floor(x), math.floor(y)
end

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
    state.currentView = "config"
    api.pushEvent("View config")
  elseif ch == "7" then
    state.currentView = "setup"
    api.pushEvent("View setup")
  elseif ch == "8" then
    state.tomUiDiagnosticMode = not state.tomUiDiagnosticMode
    state.lastAction = state.tomUiDiagnosticMode and "Tom UI diag ON" or "Tom UI diag OFF"
    api.pushEvent(state.lastAction)
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

function M.route(ev, p1, p2, p3, p4, p5, api)
  local state = api.state
  local hw = api.hw
  local log = api.log or {}
  local logDebug = type(log.debug) == "function" and log.debug or function() end

  if ev == "char" then
    logDebug("Input char", { value = tostring(p1) })
    local ch = string.lower(p1)
    if state.choosingMonitor then
      handleMonitorSelectionChar(ch, api)
    else
      handleMainChar(ch, api)
    end
    return
  end

  if ev == "mouse_click" then
    logDebug("Mouse click", { source = "terminal", x = p2, y = p3, button = p1 })
    if p1 == 1 then
      api.handleClick(p2, p3, "terminal")
    end
    return
  end

  if ev == "monitor_touch" or ev == "tm_monitor_touch" then
    logDebug("Monitor touch event", { event = ev, backend = hw.monitorTouchEvent or "monitor_touch" })
    local x, y = unpackMonitorCoords(hw, p1, p2, p3, p4)
    x, y = normalizeMonitorCoords(hw, x, y)
    if x and y then
      api.handleClick(x, y, "monitor")
    end
    return
  end

  if ev == "tm_monitor_mouse_click" then
    local button, x, y = nil, nil, nil
    if type(p1) == "string" then
      if hw.monitorName and p1 ~= hw.monitorName then
        return
      end
      button = tonumber(p2)
      x = tonumber(p3)
      y = tonumber(p4)
    else
      button = tonumber(p1)
      x = tonumber(p2)
      y = tonumber(p3)
    end
    logDebug("TM monitor mouse click", {
      event = ev,
      button = tostring(button or 0),
      backend = hw.monitorTouchEvent or "monitor_touch",
    })
    x, y = normalizeMonitorCoords(hw, x, y)
    if (button == nil or button == 1) and x and y then
      api.handleClick(x, y, "monitor")
    end
    return
  end

  if ev == "monitor_resize" or ev == "term_resize" or ev == "tm_monitor_resize" then
    logDebug("Display resize", { event = ev })
    CoreUiAdaptive.markResizeEvent(state, ev)
    api.setupMonitor()
    state.uiDrawn = false
    return
  end

  if ev == "peripheral" or ev == "peripheral_detach" then
    logDebug("Peripheral topology changed", { event = ev, side = tostring(p1) })
    CoreUiAdaptive.markResizeEvent(state, ev)
    api.setupMonitor()
    state.uiDrawn = false
    if state.choosingMonitor then
      state.monitorList = api.getMonitorCandidates()
    end
    return
  end

  if ev ~= "timer" then
    logDebug("Unhandled event", { event = tostring(ev) })
  end
end

return M
