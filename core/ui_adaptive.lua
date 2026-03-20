local M = {}

local function nowClock()
  if type(os) == "table" and type(os.clock) == "function" then
    return os.clock()
  end
  return 0
end

function M.ensure(state)
  if type(state) ~= "table" then
    return {}
  end
  if type(state.uiAdaptive) ~= "table" then
    state.uiAdaptive = {}
  end
  local adaptive = state.uiAdaptive
  if type(adaptive.bySource) ~= "table" then
    adaptive.bySource = {}
  end
  adaptive.reflowCount = tonumber(adaptive.reflowCount) or 0
  adaptive.resizeTriggerCount = tonumber(adaptive.resizeTriggerCount) or 0
  adaptive.backendSwitchCount = tonumber(adaptive.backendSwitchCount) or 0
  adaptive.lastReason = tostring(adaptive.lastReason or "none")
  adaptive.lastEvent = tostring(adaptive.lastEvent or "none")
  adaptive.lastEventAt = tonumber(adaptive.lastEventAt) or 0
  adaptive.density = tostring(adaptive.density or "unknown")
  adaptive.layoutMode = tostring(adaptive.layoutMode or "unknown")
  adaptive.forceReflow = adaptive.forceReflow == true
  return adaptive
end

function M.markForced(state, reason, eventName)
  local adaptive = M.ensure(state)
  adaptive.forceReflow = true
  adaptive.lastReason = tostring(reason or "forced")
  adaptive.lastEvent = tostring(eventName or "forced")
  adaptive.lastEventAt = nowClock()
  return adaptive
end

function M.markResizeEvent(state, eventName)
  local adaptive = M.markForced(state, eventName, eventName)
  adaptive.resizeTriggerCount = (tonumber(adaptive.resizeTriggerCount) or 0) + 1
  return adaptive
end

function M.beginSurfaceDraw(state, hw, source, variant, width, height, frameId, drawForceReflow)
  local adaptive = M.ensure(state)
  local sourceKey = tostring(source or "terminal")
  local currentBackend = tostring((type(hw) == "table" and hw.monitorBackend) or "terminal")
  local currentFamily = tostring((type(hw) == "table" and hw.monitorBackendFamily) or "terminal_fallback")
  local currentMonitor = tostring((type(hw) == "table" and hw.monitorName) or "none")
  local slot = type(adaptive.bySource[sourceKey]) == "table" and adaptive.bySource[sourceKey] or {}

  local signature = table.concat({
    sourceKey,
    tostring(variant or "cc"),
    currentBackend,
    currentFamily,
    currentMonitor,
    tostring(width or 0),
    tostring(height or 0),
  }, "|")

  local reasons = {}
  local reflowTriggered = false
  if drawForceReflow == true or adaptive.forceReflow == true then
    reflowTriggered = true
    reasons[#reasons + 1] = tostring(adaptive.lastReason or "forced")
  end
  if tostring(slot.signature or "") ~= signature then
    reflowTriggered = true
    reasons[#reasons + 1] = "surface_metrics_changed"
  end
  if tostring(slot.backend or "") ~= currentBackend
    or tostring(slot.family or "") ~= currentFamily
    or tostring(slot.monitor or "") ~= currentMonitor then
    adaptive.backendSwitchCount = (tonumber(adaptive.backendSwitchCount) or 0) + 1
    reasons[#reasons + 1] = "backend_surface_changed"
  end

  if reflowTriggered then
    adaptive.reflowCount = (tonumber(adaptive.reflowCount) or 0) + 1
  end

  slot.signature = signature
  slot.backend = currentBackend
  slot.family = currentFamily
  slot.monitor = currentMonitor
  slot.w = tonumber(width) or 0
  slot.h = tonumber(height) or 0
  slot.lastReflowFrame = tonumber(frameId) or 0
  adaptive.bySource[sourceKey] = slot

  adaptive.lastSource = sourceKey
  adaptive.lastW = slot.w
  adaptive.lastH = slot.h
  adaptive.lastBackend = currentBackend
  adaptive.lastFamily = currentFamily
  adaptive.lastMonitor = currentMonitor

  return {
    sourceKey = sourceKey,
    backend = currentBackend,
    family = currentFamily,
    monitor = currentMonitor,
    reflowTriggered = reflowTriggered,
    reflowReason = (#reasons > 0) and table.concat(reasons, ",") or "none",
    reflowCount = adaptive.reflowCount,
    resizeTriggerCount = adaptive.resizeTriggerCount,
    backendSwitchCount = adaptive.backendSwitchCount,
  }
end

function M.setLayoutState(state, density, layoutMode)
  local adaptive = M.ensure(state)
  adaptive.density = tostring(density or adaptive.density or "unknown")
  adaptive.layoutMode = tostring(layoutMode or adaptive.layoutMode or "unknown")
  return adaptive
end

function M.finishDraw(state, drawForceReflow)
  local adaptive = M.ensure(state)
  adaptive.forceReflow = false
  if drawForceReflow == true then
    adaptive.lastReason = "none"
  end
  return adaptive
end

return M
