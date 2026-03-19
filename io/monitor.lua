local function loadDisplayBackend()
  local function tryLoadFromPath(path)
    if type(path) ~= "string" or path == "" then
      return nil
    end
    if not (fs and type(fs.exists) == "function" and fs.exists(path) and (not fs.isDir or not fs.isDir(path))) then
      return nil
    end
    if type(dofile) ~= "function" then
      return nil
    end
    local ok, mod = pcall(dofile, path)
    if ok and type(mod) == "table" then
      return mod
    end
    return nil
  end

  local function collectCandidatePaths()
    local out = {
      "io/display_backend.lua",
      "/io/display_backend.lua",
      "../io/display_backend.lua",
    }

    if type(shell) == "table" and type(shell.getRunningProgram) == "function"
      and fs and type(fs.getDir) == "function" and type(fs.combine) == "function" then
      local running = tostring(shell.getRunningProgram() or "")
      local runningDir = fs.getDir(running)
      if runningDir ~= "" then
        out[#out + 1] = fs.combine(runningDir, "io/display_backend.lua")
        out[#out + 1] = fs.combine(runningDir, "../io/display_backend.lua")
      end
    end

    if type(debug) == "table" and type(debug.getinfo) == "function"
      and fs and type(fs.getDir) == "function" and type(fs.combine) == "function" then
      local info = debug.getinfo(1, "S")
      local source = info and info.source or ""
      if type(source) == "string" and source:sub(1, 1) == "@" then
        local thisPath = source:sub(2)
        local thisDir = fs.getDir(thisPath)
        if thisDir ~= "" then
          out[#out + 1] = fs.combine(thisDir, "display_backend.lua")
        end
      end
    end

    return out
  end

  if type(require) == "function" then
    local ok, mod = pcall(require, "io.display_backend")
    if ok and type(mod) == "table" then
      return mod
    end
  end

  local seen = {}
  for _, path in ipairs(collectCandidatePaths()) do
    if not seen[path] then
      seen[path] = true
      local mod = tryLoadFromPath(path)
      if mod then
        return mod
      end
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

local function logInfo(logger, message, meta)
  if type(logger) == "table" and type(logger.info) == "function" then
    logger.info(message, meta)
  end
end

local function logWarn(logger, message, meta)
  if type(logger) == "table" and type(logger.warn) == "function" then
    logger.warn(message, meta)
  end
end

local function logDebug(logger, message, meta)
  if type(logger) == "table" and type(logger.debug) == "function" then
    logger.debug(message, meta)
  end
end

local function normalizeCandidateShape(candidate, fallbackName, fallbackObj)
  if type(candidate) ~= "table" then
    return nil
  end
  local obj = candidate.obj or fallbackObj
  if not obj then
    return nil
  end
  local kind = candidate.kind or candidate.backend or "cc_monitor"
  return {
    name = candidate.name or fallbackName,
    obj = obj,
    kind = kind,
    backend = candidate.backend or kind,
    touchEvent = candidate.touchEvent or "monitor_touch",
    w = candidate.w,
    h = candidate.h,
  }
end

local function resolveMonitorCandidate(hw, provided, getTypeOf)
  if type(provided) == "table" and provided.obj == hw.monitor then
    return normalizeCandidateShape(provided, hw.monitorName, hw.monitor)
  end
  if not hw.monitor then
    return nil
  end
  local detected = DisplayBackend.detectCandidate(hw.monitorName, hw.monitor, getTypeOf)
  return normalizeCandidateShape(detected, hw.monitorName, hw.monitor)
end

function M.setupMonitor(nativeTerm, hw, CFG, C, chosenCandidate, getTypeOf, logger)
  local outputMode = string.lower(tostring((CFG and CFG.displayOutput) or "monitor"))

  hw.displaySurface = nil
  hw.monitorBackend = "terminal"
  hw.monitorTouchEvent = "monitor_touch"
  hw.monitorTouchMapper = nil

  if type(term) == "table" and type(term.redirect) == "function" then
    pcall(term.redirect, nativeTerm)
  end

  if hw.monitor then
    local candidate = resolveMonitorCandidate(hw, chosenCandidate, getTypeOf) or {
      name = hw.monitorName,
      obj = hw.monitor,
      kind = "cc_monitor",
      backend = "cc_monitor",
      touchEvent = "monitor_touch",
    }

    local surface, meta = DisplayBackend.createSurface(candidate, CFG)
    hw.displaySurface = surface or hw.monitor

    hw.monitorBackend = (meta and meta.kind) or candidate.kind or "cc_monitor"
    hw.monitorTouchEvent = (meta and meta.touchEvent) or candidate.touchEvent or "monitor_touch"
    hw.monitorTouchMapper = meta and meta.mapPixel or nil

    if candidate.kind and hw.monitorBackend and candidate.kind ~= hw.monitorBackend then
      logWarn(logger, "Display backend downgraded", {
        expected = candidate.kind,
        selected = hw.monitorBackend,
        monitor = candidate.name or hw.monitorName or "unknown",
      })
    end

    local setTextScale = hw.monitor and hw.monitor.setTextScale
    if (candidate.kind == "cc_monitor" or hw.monitorBackend == "cc_monitor")
      and type(setTextScale) == "function" then
      pcall(setTextScale, hw.monitor, CFG and CFG.monitorScale)
    end

    if type(hw.displaySurface.setBackgroundColor) == "function" then
      pcall(hw.displaySurface.setBackgroundColor, C.bg)
    end
    if type(hw.displaySurface.setTextColor) == "function" then
      pcall(hw.displaySurface.setTextColor, C.text)
    end
    if type(hw.displaySurface.clear) == "function" then
      pcall(hw.displaySurface.clear)
    end
    if type(hw.displaySurface.flush) == "function" then
      pcall(hw.displaySurface.flush)
    end
    if type(hw.displaySurface.getSize) == "function" then
      local okSize, w, h = pcall(hw.displaySurface.getSize)
      if okSize then
        logDebug(logger, "Display surface active", {
          backend = hw.monitorBackend or "unknown",
          width = tostring(w or 0),
          height = tostring(h or 0),
        })
      end
    end

    if outputMode == "monitor" then
      pcall(term.redirect, hw.displaySurface)
    end
    logInfo(logger, "Monitor backend ready", {
      monitor = candidate.name or hw.monitorName or "unknown",
      backend = hw.monitorBackend or "unknown",
      touch = hw.monitorTouchEvent or "monitor_touch",
      output = outputMode,
    })
  else
    logWarn(logger, "Monitor backend disabled: no monitor peripheral")
  end

  if type(term) == "table" and type(term.setCursorBlink) == "function" then
    pcall(term.setCursorBlink, false)
  end
  return true
end

return M
