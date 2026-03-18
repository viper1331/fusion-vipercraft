local function loadDisplayBackend()
  if type(require) == "function" then
    local ok, mod = pcall(require, "io.display_backend")
    if ok and type(mod) == "table" then
      return mod
    end
  end

  if type(dofile) == "function" and fs and type(fs.exists) == "function" and fs.exists("io/display_backend.lua") then
    local ok, mod = pcall(dofile, "io/display_backend.lua")
    if ok and type(mod) == "table" then
      return mod
    end
  end

  return {
    detectCandidate = function()
      return nil
    end,
    createSurface = function(candidate)
      return candidate and candidate.obj or nil, {
        kind = "cc_monitor",
        touchEvent = "monitor_touch",
        mapPixel = nil,
      }
    end,
  }
end

local DisplayBackend = loadDisplayBackend()

local M = {}

local function resolveMonitorCandidate(hw, provided, getTypeOf)
  if type(provided) == "table" and provided.obj == hw.monitor then
    return provided
  end
  if not hw.monitor then
    return nil
  end
  return DisplayBackend.detectCandidate(hw.monitorName, hw.monitor, getTypeOf)
end

function M.setupMonitor(nativeTerm, hw, CFG, C, chosenCandidate, getTypeOf)
  local outputMode = string.lower(tostring((CFG and CFG.displayOutput) or "monitor"))

  hw.displaySurface = nil
  hw.monitorBackend = "terminal"
  hw.monitorTouchEvent = "monitor_touch"
  hw.monitorTouchMapper = nil

  term.redirect(nativeTerm)

  if hw.monitor then
    local candidate = resolveMonitorCandidate(hw, chosenCandidate, getTypeOf) or {
      name = hw.monitorName,
      obj = hw.monitor,
      kind = "cc_monitor",
      touchEvent = "monitor_touch",
    }

    local surface, meta = DisplayBackend.createSurface(candidate, CFG)
    hw.displaySurface = surface or hw.monitor

    hw.monitorBackend = (meta and meta.kind) or candidate.kind or "cc_monitor"
    hw.monitorTouchEvent = (meta and meta.touchEvent) or candidate.touchEvent or "monitor_touch"
    hw.monitorTouchMapper = meta and meta.mapPixel or nil

    if (candidate.kind == "cc_monitor" or hw.monitorBackend == "cc_monitor")
      and type(hw.monitor.setTextScale) == "function" then
      pcall(hw.monitor.setTextScale, CFG and CFG.monitorScale)
    end

    pcall(hw.displaySurface.setBackgroundColor, C.bg)
    pcall(hw.displaySurface.setTextColor, C.text)
    pcall(hw.displaySurface.clear)
    if type(hw.displaySurface.flush) == "function" then
      pcall(hw.displaySurface.flush)
    end

    if outputMode == "monitor" then
      term.redirect(hw.displaySurface)
    end
  end

  term.setCursorBlink(false)
  return true
end

return M
