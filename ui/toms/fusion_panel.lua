local TomTheme = require("ui.toms.theme")
local TomLayout = require("ui.toms.layout")
local TomComponents = require("ui.toms.components")

local M = {}
-- Manual force switch for local debugging from this module.
local TOMS_DEBUG_DEFAULT = false
local TOMS_DEBUG_FILE = "logs/toms_debug.txt"
local TOMS_DEBUG_DIR = "logs"
local debugFileTargetCache = nil

local function resolveProgramRootDir()
  if type(fs) ~= "table" or type(fs.getDir) ~= "function" then
    return ""
  end

  if type(debug) == "table" and type(debug.getinfo) == "function" then
    local info = debug.getinfo(2, "S") or debug.getinfo(1, "S")
    local source = info and info.source or ""
    if type(source) == "string" and source:sub(1, 1) == "@" then
      local modulePath = source:sub(2):gsub("\\", "/")
      local moduleDir = fs.getDir(modulePath)
      local parentDir = fs.getDir(moduleDir)
      local rootDir = fs.getDir(parentDir)
      if type(rootDir) == "string" and rootDir ~= "" then
        return rootDir
      end
    end
  end

  if type(shell) == "table" and type(shell.getRunningProgram) == "function" then
    local running = tostring(shell.getRunningProgram() or "")
    if running ~= "" then
      local runningDir = fs.getDir(running)
      if type(runningDir) == "string" then
        return runningDir
      end
    end
  end

  return ""
end

local function getDebugFileTarget()
  if type(debugFileTargetCache) == "table" then
    return debugFileTargetCache
  end

  local target = {
    displayPath = TOMS_DEBUG_FILE,
    writeDir = TOMS_DEBUG_DIR,
    writeFile = TOMS_DEBUG_FILE,
    rootDir = "",
  }

  if type(fs) == "table" and type(fs.combine) == "function" then
    local rootDir = resolveProgramRootDir()
    target.rootDir = rootDir
    if rootDir ~= "" then
      target.writeDir = fs.combine(rootDir, TOMS_DEBUG_DIR)
      target.writeFile = fs.combine(rootDir, TOMS_DEBUG_FILE)
    end
  end

  debugFileTargetCache = target
  return target
end

local function asNumber(value, fallback)
  local n = tonumber(value)
  if n == nil then return fallback or 0 end
  return n
end

local function asText(value, fallback)
  local out = tostring(value or "")
  if out == "" then
    return tostring(fallback or "N/A")
  end
  return out
end

local function clamp(value, lo, hi)
  if value < lo then return lo end
  if value > hi then return hi end
  return value
end

local function rect(x, y, w, h)
  x = math.floor(tonumber(x) or 1)
  y = math.floor(tonumber(y) or 1)
  w = math.max(1, math.floor(tonumber(w) or 1))
  h = math.max(1, math.floor(tonumber(h) or 1))
  return { x = x, y = y, w = w, h = h, x2 = x + w - 1, y2 = y + h - 1 }
end

local function inset(bounds, left, top, right, bottom)
  local l = math.max(0, math.floor(tonumber(left) or 0))
  local t = math.max(0, math.floor(tonumber(top) or 0))
  local r = math.max(0, math.floor(tonumber(right) or l))
  local b = math.max(0, math.floor(tonumber(bottom) or t))
  local w = bounds.w - l - r
  local h = bounds.h - t - b
  if w < 1 then w = 1 end
  if h < 1 then h = 1 end
  local x = clamp(bounds.x + l, bounds.x, bounds.x2 - w + 1)
  local y = clamp(bounds.y + t, bounds.y, bounds.y2 - h + 1)
  return rect(x, y, w, h)
end

local function splitVertical(bounds, specs, gap)
  local out = {}
  local count = #specs
  if count <= 0 then return out end
  gap = math.max(0, math.floor(tonumber(gap) or 0))

  local usable = math.max(1, bounds.h - ((count - 1) * gap))
  local weightSum = 0
  for i = 1, count do
    weightSum = weightSum + math.max(0, tonumber(specs[i].weight) or 0)
  end
  if weightSum <= 0 then weightSum = count end

  local y = bounds.y
  local used = 0
  for i = 1, count do
    local h = math.floor((usable * math.max(0, tonumber(specs[i].weight) or 1)) / weightSum)
    if h < 1 then h = 1 end
    if i == count then
      h = math.max(1, (bounds.y + bounds.h) - y)
    end
    out[specs[i].key] = rect(bounds.x, y, bounds.w, h)
    y = y + h + gap
    used = used + h
  end
  if used < usable then
    local k = specs[count].key
    local last = out[k]
    out[k] = rect(last.x, last.y, last.w, last.h + (usable - used))
  end
  return out
end

function M.build(api)
  local state = assert(api.state, "state is required")
  local hw = assert(api.hw, "hw is required")
  local C = assert(api.C, "C is required")
  local CFG = type(api.CFG) == "table" and api.CFG or {}
  local log = type(api.log) == "table" and api.log or {}

  local function logWarn(message, meta)
    if type(log.warn) == "function" then
      log.warn(message, meta)
    end
  end
  local function logInfo(message, meta)
    if type(log.info) == "function" then
      log.info(message, meta)
    end
  end
  local function logDebug(message, meta)
    if type(log.debug) == "function" then
      log.debug(message, meta)
    end
  end

  local function phaseText()
    if type(api.reactorPhase) == "function" then
      return tostring(api.reactorPhase())
    end
    return asText(state.status, "INIT")
  end

  local function phaseTone()
    if type(api.phaseColor) == "function" then
      return api.phaseColor(phaseText())
    end
    return C.info
  end

  local function laserTone(theme)
    local st = tostring(state.laserState or "ABSENT")
    if st == "READY" then return theme.palette.ok end
    if st == "CHARGING" then return theme.palette.warning end
    if st == "INSUFFICIENT" then return theme.palette.warning end
    if st == "ABSENT" then return theme.palette.critical end
    return theme.palette.textMuted
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
    if type(api.formatTemperature) == "function" then
      return tostring(api.formatTemperature(value, { compact = true, decimals = decimals or 1 }))
    end
    return string.format("%.1f C", asNumber(value, 0))
  end

  local function formatEnergy(value)
    if type(api.formatEnergy) == "function" then
      return tostring(api.formatEnergy(value))
    end
    return asText(value, "N/A")
  end

  local function formatEnergyTick(value)
    if type(api.formatEnergyPerTick) == "function" then
      return tostring(api.formatEnergyPerTick(value))
    end
    return asText(value, "N/A")
  end

  local function runtimeModel(theme)
    local warnings = type(state.safetyWarnings) == "table" and state.safetyWarnings or {}
    local events = type(state.eventLog) == "table" and state.eventLog or {}
    local blockers = type(state.ignitionBlockers) == "table" and state.ignitionBlockers or {}
    local laserCount = math.max(1, math.floor(tonumber(state.laserDetectedCount or state.laserCount or 1) or 1))
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
    local laserRatio = clamp(asNumber(state.laserPct, 0) / 100, 0, 1)
    local gridRatio = clamp(asNumber(state.energyPct, 0) / 100, 0, 1)
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
      injectionRate = math.floor(asNumber(state.injectionRate, 0)),
      plasmaTemp = formatTemperature(state.plasmaTemp, 1),
      caseTemp = formatTemperature(state.caseTemp, 1),
      passiveGeneration = formatEnergyTick(state.passiveGeneration),
      steamProduction = string.format("%.1f mB/t", asNumber(state.steamProduction, 0)),
      fuelFlow = string.format("%.1f mB/t", asNumber(state.fuelFlowMbT, 0)),
      fuelMode = asText(type(api.getRuntimeFuelMode) == "function" and api.getRuntimeFuelMode() or "N/A", "N/A"),
      laserState = asText(state.laserStatusText or state.laserState, "ABS"),
      laserPct = clamp(math.floor(asNumber(state.laserPct, 0) + 0.5), 0, 999),
      laserRatio = laserRatio,
      laserEnergy = formatEnergy(state.laserEnergy),
      laserMax = formatEnergy(state.laserMax),
      laserNeed = formatEnergy(state.laserThresholdRaw),
      laserCount = laserCount,
      laserActiveCount = activeLasers,
      laserCharging = state.laserChargeOn == true,
      laserActive = state.laserLineOn == true,
      energyPct = clamp(asNumber(state.energyPct, 0), 0, 100),
      energyRatio = gridRatio,
      energyKnown = state.energyKnown == true,
      energyStored = formatEnergy(state.energyStored),
      energyMax = formatEnergy(state.energyMax),
      lastAction = asText(state.lastAction, "NONE"),
      monitorName = asText(hw.monitorName, "terminal"),
      backendName = asText(hw.monitorBackend, "cc_monitor"),
      tOpen = state.tOpen == true,
      dtOpen = state.dtOpen == true,
      dOpen = state.dOpen == true,
      hohlraum = state.hohlraumPresent and "PRESENT" or "MISSING",
      allowControl = CFG.allowControl == true,
    }
  end

  local function ensureTomRenderDiag()
    if type(state.tomRenderDiag) ~= "table" then
      state.tomRenderDiag = {}
    end
    local diag = state.tomRenderDiag
    diag.redrawCount = tonumber(diag.redrawCount) or 0
    diag.syncCount = tonumber(diag.syncCount) or 0
    diag.windowAllowed = diag.windowAllowed == true
    diag.windowUsed = diag.windowUsed == true
    diag.renderPath = tostring(diag.renderPath or "none")
    diag.lastSource = tostring(diag.lastSource or "none")
    diag.lastSurface = tostring(diag.lastSurface or "none")
    diag.lastW = tonumber(diag.lastW) or 0
    diag.lastH = tonumber(diag.lastH) or 0
    diag.fallbackAfterTom = diag.fallbackAfterTom == true
    diag.windowAllowed = diag.windowAllowed == true
    diag.windowUsed = diag.windowUsed == true
    diag.lastRenderType = tostring(diag.lastRenderType or "none")
    diag.lastSyncMethod = tostring(diag.lastSyncMethod or "none")
    diag.lastRenderError = tostring(diag.lastRenderError or "")
    if type(diag.errors) ~= "table" then
      diag.errors = {}
    end
    if type(diag.lastLayout) ~= "table" then
      diag.lastLayout = {}
    end
    if type(diag.detectedTomGpus) ~= "table" then
      diag.detectedTomGpus = {}
    end
    if type(diag.detectedDisplays) ~= "table" then
      diag.detectedDisplays = {}
    end
    if type(diag.debugBypass) ~= "table" then
      diag.debugBypass = {}
    end
    local debugTarget = getDebugFileTarget()
    diag.debugFilePath = debugTarget.displayPath
    diag.debugFileResolvedPath = debugTarget.writeFile
    return diag
  end

  local function pushDiagError(diag, message)
    if type(diag) ~= "table" then
      return
    end
    if type(diag.errors) ~= "table" then
      diag.errors = {}
    end
    local text = tostring(message or "")
    if text == "" then
      return
    end
    diag.errors[#diag.errors + 1] = text
    local limit = 24
    if #diag.errors > limit then
      table.remove(diag.errors, 1)
    end
  end

  local function rectText(bounds)
    if type(bounds) ~= "table" then
      return "N/A"
    end
    return string.format("x=%d y=%d w=%d h=%d", tonumber(bounds.x) or 0, tonumber(bounds.y) or 0, tonumber(bounds.w) or 0, tonumber(bounds.h) or 0)
  end

  local function addLine(lines, label, value)
    lines[#lines + 1] = string.format("%-24s %s", tostring(label or "-"), tostring(value or ""))
  end

  local function writeTomDebugSnapshot(diag, model, source, width, height)
    local fsApi = _G and _G.fs
    if type(fsApi) ~= "table" then
      diag.debugFileLastStatus = "fs_unavailable"
      return false, "fs_unavailable"
    end
    local debugTarget = getDebugFileTarget()

    local okWrite, errWrite = pcall(function()
      if not fsApi.exists(debugTarget.writeDir) then
        fsApi.makeDir(debugTarget.writeDir)
      end

      local handle = fsApi.open(debugTarget.writeFile, "w")
      if not handle then
        error("open_failed")
      end

      local lines = {}
      local now = (type(os) == "table" and type(os.date) == "function") and os.date("%Y-%m-%d %H:%M:%S") or "N/A"
      local launchAt = tostring(state.launchTimestamp or now)
      local launchArgs = type(state.launchArgs) == "table" and table.concat(state.launchArgs, " ") or ""
      local selectedRelayName = (((type(CFG.actions) == "table" and type(CFG.actions.laser_fire) == "table") and CFG.actions.laser_fire.relay)
        or ((type(CFG.actions) == "table" and type(CFG.actions.laser_charge) == "table") and CFG.actions.laser_charge.relay)
        or "N/A")
      local selectedRelaySide = (((type(CFG.actions) == "table" and type(CFG.actions.laser_fire) == "table") and CFG.actions.laser_fire.side)
        or ((type(CFG.actions) == "table" and type(CFG.actions.laser_charge) == "table") and CFG.actions.laser_charge.side)
        or "N/A")
      local methodMatches = type(state.runtimeMethodMatches) == "table" and state.runtimeMethodMatches or {}
      local layout = type(diag.lastLayout) == "table" and diag.lastLayout or {}
      local renderErrors = type(diag.errors) == "table" and diag.errors or {}
      local surfaceCtx = type(diag.surfaceContext) == "table" and diag.surfaceContext or {}
      local useWindows = diag.windowAllowed == true
      local usedWindows = diag.windowUsed == true
      local debugEnabled = state.tomUiDiagnosticMode == true or TOMS_DEBUG_DEFAULT == true
      local directDraw = tostring(diag.lastRenderType or ""):find("DIRECT", 1, true) ~= nil

      lines[#lines + 1] = "TOMS DEBUG RUNTIME REPORT"
      lines[#lines + 1] = "========================================"
      addLine(lines, "Generated at", now)
      addLine(lines, "Launch timestamp", launchAt)
      addLine(lines, "Program version", tostring(state.update and state.update.localVersion or "N/A"))
      addLine(lines, "Launch arguments", launchArgs ~= "" and launchArgs or "(none)")
      addLine(lines, "Debug file (display)", tostring(debugTarget.displayPath))
      addLine(lines, "Debug file (resolved)", tostring(debugTarget.writeFile))
      addLine(lines, "Selected GPU", tostring(hw.monitorName or "N/A"))
      addLine(lines, "Selected backend", tostring(hw.monitorBackend or "N/A"))
      addLine(lines, "Selected backend family", tostring(hw.monitorBackendFamily or "N/A"))
      addLine(lines, "Selected wrapper", tostring(hw.monitorWrapperType or "N/A"))
      addLine(lines, "Selected classic monitor", tostring(diag.selectedClassicMonitor or "N/A"))
      addLine(lines, "Selected keyboard", tostring(hw.keyboardName or "N/A"))
      addLine(lines, "Selected redstone relay", tostring(selectedRelayName))
      addLine(lines, "Selected relay side", tostring(selectedRelaySide))
      addLine(lines, "Selected reactor", tostring(hw.reactorName or hw.logicName or "N/A"))
      addLine(lines, "Selected laser", tostring(hw.laserName or "N/A"))
      addLine(lines, "Runtime dimensions", string.format("%dx%d", tonumber(width) or 0, tonumber(height) or 0))
      addLine(lines, "Runtime source", tostring(surfaceCtx.renderSource or source or "unknown"))
      lines[#lines + 1] = ""

      lines[#lines + 1] = "[SURFACE PIPELINE]"
      addLine(lines, "Render backend", tostring(surfaceCtx.backend or hw.monitorBackend or "N/A"))
      addLine(lines, "Render backend family", tostring(surfaceCtx.backendFamily or hw.monitorBackendFamily or "N/A"))
      addLine(lines, "Render wrapper", tostring(surfaceCtx.wrapperType or hw.monitorWrapperType or "N/A"))
      addLine(lines, "Input source", tostring(surfaceCtx.inputSource or source or "N/A"))
      addLine(lines, "Render source label", tostring(surfaceCtx.renderSource or source or "N/A"))
      addLine(lines, "Source changed", tostring((surfaceCtx.inputSource or "") ~= (surfaceCtx.renderSource or "")))
      addLine(lines, "Render surface type", tostring(surfaceCtx.renderSurfaceType or "N/A"))
      addLine(lines, "Display surface type", tostring(surfaceCtx.displaySurfaceType or "N/A"))
      addLine(lines, "Native surface type", tostring(surfaceCtx.nativeSurfaceType or "N/A"))
      addLine(lines, "Display dimensions", tostring(surfaceCtx.displayWidth or 0) .. "x" .. tostring(surfaceCtx.displayHeight or 0))
      addLine(lines, "Native dimensions", tostring(surfaceCtx.nativeWidth or 0) .. "x" .. tostring(surfaceCtx.nativeHeight or 0))
      addLine(lines, "Wrapped dimensions", tostring(surfaceCtx.wrappedWidth or 0) .. "x" .. tostring(surfaceCtx.wrappedHeight or 0))
      addLine(lines, "Usable area", tostring(surfaceCtx.runtimeArea or 0))
      addLine(lines, "Monitor conversion", tostring(surfaceCtx.monitorConversion == true))
      addLine(lines, "Surface created at", tostring(surfaceCtx.wrappedPath or "N/A"))
      addLine(lines, "Renderer call path", tostring(surfaceCtx.sourcePath or "N/A"))
      addLine(lines, "Source resolved by", tostring(surfaceCtx.sourceResolvedBy or "N/A"))
      addLine(lines, "Term redirected to", tostring(surfaceCtx.termRedirectTarget or "N/A"))
      lines[#lines + 1] = ""

      lines[#lines + 1] = "[MODE]"
      addLine(lines, "Debug mode", debugEnabled and "enabled" or "disabled")
      addLine(lines, "Render type", tostring(diag.lastRenderType or "N/A"))
      addLine(lines, "Draw mode", directDraw and "direct draw" or "normal draw")
      addLine(lines, "Windows allowed", useWindows and "on" or "off")
      addLine(lines, "Windows used", usedWindows and "on" or "off")
      addLine(lines, "createWindow used", usedWindows and "yes" or "no")
      addLine(lines, "Redraw count", tostring(diag.redrawCount or 0))
      addLine(lines, "Sync count", tostring(diag.syncCount or 0))
      addLine(lines, "Last sync method", tostring(diag.lastSyncMethod or "N/A"))
      addLine(lines, "Fallback after Tom", diag.fallbackAfterTom and "yes" or "no")
      lines[#lines + 1] = ""

      lines[#lines + 1] = "[DETECTED TOM GPUS]"
      local tomGpus = type(diag.detectedTomGpus) == "table" and diag.detectedTomGpus or {}
      addLine(lines, "Count", tostring(#tomGpus))
      if #tomGpus == 0 then
        lines[#lines + 1] = "  - none detected"
      else
        for index, gpu in ipairs(tomGpus) do
          local blocksW = tonumber(gpu.blocksW) or 0
          local blocksH = tonumber(gpu.blocksH) or 0
          local pxW = tonumber(gpu.pixelsW) or 0
          local pxH = tonumber(gpu.pixelsH) or 0
          local wrappedW = tonumber(gpu.wrappedW) or 0
          local wrappedH = tonumber(gpu.wrappedH) or 0
          local gridW = tonumber(gpu.gridW) or 0
          local gridH = tonumber(gpu.gridH) or 0
          local scaleX = tonumber(gpu.scaleX) or 0
          local scaleY = tonumber(gpu.scaleY) or 0
          local scaleText = "N/A"
          if scaleX > 0 and scaleY > 0 then
            scaleText = tostring(scaleX) .. "x" .. tostring(scaleY)
          elseif tonumber(gpu.targetSize) and tonumber(gpu.targetSize) > 0 then
            scaleText = tostring(tonumber(gpu.targetSize))
          end
          lines[#lines + 1] = string.format("  #%d name=%s", index, tostring(gpu.name or "unknown"))
          lines[#lines + 1] = string.format("     native=%dx%d wrapped=%dx%d area=%s",
            pxW,
            pxH,
            wrappedW,
            wrappedH,
            tostring(gpu.runtimeArea or 0))
          lines[#lines + 1] = string.format("     blocks=%dx%d scale=%s grid=%dx%d backend=%s",
            blocksW,
            blocksH,
            scaleText,
            gridW,
            gridH,
            tostring(gpu.backend or "toms_gpu"))
          lines[#lines + 1] = string.format("     setSize tried=%s applied=%s mode=%s",
            tostring(gpu.setSizeTried == true),
            tostring(gpu.setSizeApplied == true),
            tostring(gpu.setSizeMode or "none"))
        end
      end
      lines[#lines + 1] = ""

      lines[#lines + 1] = "[DETECTED CLASSIC MONITORS]"
      local classicDisplays = {}
      for _, display in ipairs(type(diag.detectedDisplays) == "table" and diag.detectedDisplays or {}) do
        if tostring(display.backend or "") == "cc_monitor" then
          classicDisplays[#classicDisplays + 1] = display
        end
      end
      addLine(lines, "Count", tostring(#classicDisplays))
      if #classicDisplays == 0 then
        lines[#lines + 1] = "  - none detected"
      else
        for index, display in ipairs(classicDisplays) do
          lines[#lines + 1] = string.format("  #%d name=%s", index, tostring(display.name or "unknown"))
          lines[#lines + 1] = string.format("     native=%dx%d wrapped=%dx%d area=%s",
            tonumber(display.pixelsW) or tonumber(display.blocksW) or 0,
            tonumber(display.pixelsH) or tonumber(display.blocksH) or 0,
            tonumber(display.wrappedW) or tonumber(display.blocksW) or 0,
            tonumber(display.wrappedH) or tonumber(display.blocksH) or 0,
            tostring(display.runtimeArea or 0))
        end
      end
      lines[#lines + 1] = ""

      lines[#lines + 1] = "[LAYOUT]"
      addLine(lines, "Density", tostring(layout.density or "N/A"))
      addLine(lines, "Layout mode", tostring(layout.mode or "N/A"))
      addLine(lines, "Header", rectText(layout.header))
      addLine(lines, "Reactor", rectText(layout.reactor))
      addLine(lines, "Temperatures", rectText(layout.temperatures))
      addLine(lines, "Laser", rectText(layout.laser))
      addLine(lines, "Status", rectText(layout.status))
      addLine(lines, "Footer", rectText(layout.footer))
      lines[#lines + 1] = ""

      lines[#lines + 1] = "[MATCHED METHODS]"
      addLine(lines, "plasma", tostring(methodMatches.plasma or "N/A"))
      addLine(lines, "case", tostring(methodMatches.case or "N/A"))
      addLine(lines, "injection", tostring(methodMatches.injection or "N/A"))
      addLine(lines, "active", tostring(methodMatches.active or "N/A"))
      addLine(lines, "passive", tostring(methodMatches.passive or "N/A"))
      addLine(lines, "steam", tostring(methodMatches.steam or "N/A"))
      addLine(lines, "fuel", tostring(methodMatches.fuel or "N/A"))
      addLine(lines, "laser energy", tostring(methodMatches.laserEnergy or "N/A"))
      addLine(lines, "laser max", tostring(methodMatches.laserMax or "N/A"))
      lines[#lines + 1] = ""

      lines[#lines + 1] = "[CONTROLS]"
      addLine(lines, "allow_control", tostring(CFG.allowControl == true))
      addLine(lines, "pulse available", tostring(type(CFG.actions) == "table" and type(CFG.actions.laser_fire) == "table" and CFG.actions.laser_fire.relay ~= nil))
      addLine(lines, "injection control available", tostring(state.injectionWritable == true))
      lines[#lines + 1] = ""

      lines[#lines + 1] = "[BYPASS CONFIRMATION]"
      addLine(lines, "normal layout bypassed", tostring(diag.debugBypass.layoutNormal == true))
      addLine(lines, "components bypassed", tostring(diag.debugBypass.components == true))
      addLine(lines, "windows bypassed", tostring(diag.debugBypass.windows == true))
      addLine(lines, "legacy render bypassed", tostring(diag.debugBypass.legacy == true))
      addLine(lines, "debug wrapper parity", tostring(surfaceCtx.wrapperType or ""):find("toms_native", 1, true) and "true" or "false")
      lines[#lines + 1] = ""

      lines[#lines + 1] = "[LAST FRAME SUMMARY]"
      addLine(lines, "status", tostring(model.statusText or "N/A"))
      addLine(lines, "phase", tostring(model.phase or "N/A"))
      addLine(lines, "plasma", tostring(model.plasmaTemp or "N/A"))
      addLine(lines, "case", tostring(model.caseTemp or "N/A"))
      addLine(lines, "laser", tostring(model.laserState or "N/A") .. " " .. tostring(model.laserPct or 0) .. "%")
      addLine(lines, "grid", model.energyKnown and string.format("%.0f%%", tonumber(model.energyPct) or 0) or "N/A")
      addLine(lines, "action", tostring(model.lastAction or "N/A"))
      lines[#lines + 1] = ""

      lines[#lines + 1] = "[RENDER ERRORS]"
      if tostring(diag.lastRenderError or "") ~= "" then
        lines[#lines + 1] = "  - " .. tostring(diag.lastRenderError)
      end
      if #renderErrors == 0 and tostring(diag.lastRenderError or "") == "" then
        lines[#lines + 1] = "  - none"
      else
        for i = 1, #renderErrors do
          lines[#lines + 1] = "  - " .. tostring(renderErrors[i] or "")
        end
      end

      handle.write(table.concat(lines, "\n"))
      handle.close()
    end)

    if not okWrite then
      diag.debugFileLastStatus = "write_failed"
      diag.debugFileLastError = tostring(errWrite)
      return false, tostring(errWrite)
    end
    diag.debugFileLastStatus = "ok"
    diag.debugFileLastError = ""
    diag.debugFileResolvedPath = debugTarget.writeFile
    return true, nil
  end

  local function makeTomNativeCanvas(surface, width, height, diag)
    local w = math.max(1, math.floor(tonumber(width) or 1))
    local h = math.max(1, math.floor(tonumber(height) or 1))
    local lineH = math.max(8, math.floor(math.max(8, h) * 0.024))
    local palette = {
      bg = 0xFF0B1020,
      panel = 0xFF101A33,
      panelHeader = 0xFF16375E,
      border = 0xFF4AA3FF,
      text = 0xFFE8F4FF,
      muted = 0xFFA7BDD9,
      ok = 0xFF6DDE7B,
      warn = 0xFFF5C04C,
      bad = 0xFFF46969,
      info = 0xFF66CCFF,
    }

    local function callSafe(methodName, ...)
      local fn = type(surface) == "table" and surface[methodName] or nil
      if type(fn) ~= "function" then
        return false
      end
      local ok, err = pcall(fn, ...)
      if not ok then
        pushDiagError(diag, "native_" .. tostring(methodName) .. "_failed:" .. tostring(err))
      end
      return ok
    end

    local function callVariants(methodName, variants)
      for _, args in ipairs(variants or {}) do
        if callSafe(methodName, table.unpack(args)) then
          return true
        end
      end
      return false
    end

    local function clampRect(x, y, rw, rh)
      local x1 = math.floor(tonumber(x) or 1)
      local y1 = math.floor(tonumber(y) or 1)
      local ww = math.max(0, math.floor(tonumber(rw) or 0))
      local hh = math.max(0, math.floor(tonumber(rh) or 0))
      if ww <= 0 or hh <= 0 then
        return nil
      end
      local x2 = x1 + ww - 1
      local y2 = y1 + hh - 1
      if x2 < 1 or y2 < 1 or x1 > w or y1 > h then
        return nil
      end
      if x1 < 1 then x1 = 1 end
      if y1 < 1 then y1 = 1 end
      if x2 > w then x2 = w end
      if y2 > h then y2 = h end
      local cw = (x2 - x1) + 1
      local ch = (y2 - y1) + 1
      if cw <= 0 or ch <= 0 then
        return nil
      end
      return x1, y1, cw, ch
    end

    local function fillRect(x, y, rw, rh, color)
      local x1, y1, cw, ch = clampRect(x, y, rw, rh)
      if not x1 then return end
      local x2 = x1 + cw - 1
      local y2 = y1 + ch - 1
      if callVariants("filledRectangle", {
        { x1, y1, cw, ch, color },
        { x1, y1, x2, y2, color },
      }) then return end
      if callVariants("fillRect", {
        { x1, y1, cw, ch, color },
        { x1, y1, x2, y2, color },
      }) then return end
      if x1 == 1 and y1 == 1 and cw >= w and ch >= h and callSafe("fill", color) then
        return
      end
    end

    local function drawText(x, y, text, color, bgColor)
      local xx = math.floor(tonumber(x) or 1)
      local yy = math.floor(tonumber(y) or 1)
      local raw = tostring(text or "")
      if raw == "" then return end
      if yy < 1 or yy > h then return end
      local textWidth = #raw
      if type(surface) == "table" and type(surface.getTextLength) == "function" then
        local okLen, len = pcall(surface.getTextLength, raw)
        if okLen and tonumber(len) then
          textWidth = math.max(1, math.floor(tonumber(len)))
        end
      end
      if bgColor ~= nil then
        fillRect(xx, yy, math.max(1, textWidth), lineH, bgColor)
      end
      if callVariants("drawText", {
        { xx, yy, raw, color },
        { raw, xx, yy, color },
        { xx, yy, raw },
        { raw, xx, yy },
      }) then return end
      callVariants("drawString", {
        { xx, yy, raw, color },
        { raw, xx, yy, color },
        { xx, yy, raw },
        { raw, xx, yy },
      })
    end

    local function sync()
      if callSafe("sync") then return end
      if callSafe("flush") then return end
      callSafe("update")
    end

    return {
      w = w,
      h = h,
      lineH = lineH,
      palette = palette,
      fillRect = fillRect,
      drawText = drawText,
      sync = sync,
    }
  end

  local function computeNativeDiagnosticLayout(width, height)
    local w = math.max(1, math.floor(tonumber(width) or 1))
    local h = math.max(1, math.floor(tonumber(height) or 1))
    local margin = math.max(4, math.floor(math.min(w, h) * 0.02))
    local gap = math.max(3, math.floor(margin * 0.6))
    local headerH = math.max(34, math.floor(h * 0.12))
    local footerH = math.max(36, math.floor(h * 0.13))
    if headerH + footerH + (margin * 2) >= h then
      headerH = math.max(24, math.floor(h * 0.10))
      footerH = math.max(24, math.floor(h * 0.10))
    end
    local contentY = margin + headerH + gap
    local contentH = math.max(20, h - contentY - footerH - margin - gap)
    local usableW = math.max(20, w - (margin * 2) - (gap * 2))
    local colW = math.max(8, math.floor(usableW / 3))
    local leftW = colW
    local centerW = colW
    local rightW = math.max(8, usableW - leftW - centerW)
    local leftX = margin
    local midX = leftX + leftW + gap
    local rightX = midX + centerW + gap

    local function mkRect(x, y, rw, rh)
      return {
        x = math.floor(x),
        y = math.floor(y),
        w = math.max(1, math.floor(rw)),
        h = math.max(1, math.floor(rh)),
      }
    end

    return {
      mode = "diagnostic_native_pixels",
      density = "native",
      root = mkRect(1, 1, w, h),
      header = mkRect(margin, margin, w - (margin * 2), headerH),
      reactor = mkRect(leftX, contentY, leftW, contentH),
      temperatures = mkRect(midX, contentY, centerW, contentH),
      laser = mkRect(rightX, contentY, rightW, contentH),
      status = nil,
      footer = mkRect(margin, h - footerH - margin + 1, w - (margin * 2), footerH),
    }
  end

  local function drawNativePanel(canvas, bounds, title, tone)
    local p = canvas.palette
    canvas.fillRect(bounds.x, bounds.y, bounds.w, bounds.h, p.panel)
    canvas.fillRect(bounds.x, bounds.y, bounds.w, 2, p.border)
    canvas.fillRect(bounds.x + 1, bounds.y + 1, math.max(1, bounds.w - 2), math.max(1, canvas.lineH), tone or p.panelHeader)
    canvas.drawText(bounds.x + 4, bounds.y + 2, string.upper(tostring(title or "")), p.text, nil)
  end

  local function drawNativeKV(canvas, bounds, row, label, value, valueTone)
    local p = canvas.palette
    local y = bounds.y + canvas.lineH + 5 + (row * canvas.lineH)
    if y > (bounds.y + bounds.h - canvas.lineH) then
      return
    end
    local labelX = bounds.x + 4
    local valueX = bounds.x + math.max(80, math.floor(bounds.w * 0.45))
    canvas.drawText(labelX, y, tostring(label or "-"), p.muted, nil)
    canvas.drawText(valueX, y, tostring(value or "N/A"), valueTone or p.text, nil)
  end

  local function drawNativeDiagnostic(surface, width, height, model, source, diag)
    local canvas = makeTomNativeCanvas(surface, width, height, diag)
    local p = canvas.palette
    local layout = computeNativeDiagnosticLayout(canvas.w, canvas.h)

    canvas.fillRect(layout.root.x, layout.root.y, layout.root.w, layout.root.h, p.bg)

    drawNativePanel(canvas, layout.header, "TOMS DEBUG MODE", p.panelHeader)
    canvas.drawText(layout.header.x + 4, layout.header.y + canvas.lineH + 4, "SOURCE: " .. tostring(source or "unknown"), p.info, nil)
    canvas.drawText(layout.header.x + 4, layout.header.y + (canvas.lineH * 2) + 4, "GPU: " .. tostring(hw.monitorName or "N/A"), p.info, nil)
    canvas.drawText(layout.header.x + math.max(120, math.floor(layout.header.w * 0.55)), layout.header.y + canvas.lineH + 4, string.format("RUNTIME: %dx%d", canvas.w, canvas.h), p.warn, nil)
    canvas.drawText(layout.header.x + 4, layout.header.y + (canvas.lineH * 3) + 4, "DEBUG FILE: " .. TOMS_DEBUG_FILE, p.text, nil)

    drawNativePanel(canvas, layout.reactor, "Reactor", p.panelHeader)
    drawNativeKV(canvas, layout.reactor, 0, "Global", model.statusText, p.ok)
    drawNativeKV(canvas, layout.reactor, 1, "Phase", model.phase, p.info)
    drawNativeKV(canvas, layout.reactor, 2, "Core", state.reactorFormed and "FORMED" or "UNFORMED", state.reactorFormed and p.ok or p.warn)
    drawNativeKV(canvas, layout.reactor, 3, "Injection", tostring(model.injectionRate) .. " mB/t", p.info)
    drawNativeKV(canvas, layout.reactor, 4, "Fuel", model.fuelMode, p.info)
    drawNativeKV(canvas, layout.reactor, 5, "Hohlraum", model.hohlraum, state.hohlraumPresent and p.ok or p.warn)

    drawNativePanel(canvas, layout.temperatures, "Temperatures", p.warn)
    drawNativeKV(canvas, layout.temperatures, 0, "Plasma", model.plasmaTemp, p.warn)
    drawNativeKV(canvas, layout.temperatures, 1, "Case", model.caseTemp, p.bad)
    drawNativeKV(canvas, layout.temperatures, 2, "Ignition", "300.0 C", p.info)
    drawNativeKV(canvas, layout.temperatures, 3, "Blockers", tostring(#model.blockers), (#model.blockers > 0) and p.bad or p.ok)
    drawNativeKV(canvas, layout.temperatures, 4, "Warnings", tostring(#model.warnings), (#model.warnings > 0) and p.warn or p.ok)

    drawNativePanel(canvas, layout.laser, "Laser / Power", p.ok)
    drawNativeKV(canvas, layout.laser, 0, "Laser State", model.laserState, p.ok)
    drawNativeKV(canvas, layout.laser, 1, "Laser Pct", tostring(model.laserPct) .. "%", p.ok)
    drawNativeKV(canvas, layout.laser, 2, "Laser E", model.laserEnergy, p.info)
    drawNativeKV(canvas, layout.laser, 3, "Laser Max", model.laserMax, p.info)
    drawNativeKV(canvas, layout.laser, 4, "Grid", model.energyKnown and string.format("%.0f%%", model.energyPct) or "N/A", p.info)
    drawNativeKV(canvas, layout.laser, 5, "Redraw", tostring(diag.redrawCount or 0), p.info)
    drawNativeKV(canvas, layout.laser, 6, "Sync", tostring(diag.syncCount or 0), p.info)

    drawNativePanel(canvas, layout.footer, "Controls", p.panelHeader)
    canvas.drawText(layout.footer.x + 4, layout.footer.y + canvas.lineH + 4, "REFRESH | LASER PULSE | INJ - | INJ + | QUIT | UI DIAG", p.text, nil)
    canvas.drawText(layout.footer.x + 4, layout.footer.y + (canvas.lineH * 2) + 4, "DIRECT TOM GPU | NO WINDOWS | LAYOUT/COMPONENTS BYPASSED", p.info, nil)

    canvas.sync()
    return layout
  end

  local function buildLegacyLayout(layout, theme)
    return {
      mode = layout.legacy.mode,
      top = layout.legacy.top,
      bottom = layout.legacy.bottom,
      height = layout.legacy.height,
      width = layout.legacy.width,
      tooSmall = false,
      uiScale = theme.scale,
      left = layout.legacy.left,
      center = layout.legacy.center,
      right = layout.legacy.right,
      stack = layout.stacked and true or nil,
      tomFooterControls = true,
      tomDensity = theme.density,
    }
  end

  local function drawReactorPanel(ui, bounds, theme, model)
    ui.drawPanel(bounds, "REACTOR", {
      bg = theme.palette.panelBg,
      border = theme.palette.borderStrong,
      headerBg = theme.palette.panelHeader,
      headerText = theme.palette.textPrimary,
    })
    ui.drawStatusBadge(bounds, 0, model.active and "ACTIVE" or "IDLE", model.active and theme.palette.ok or theme.palette.warning)
    ui.drawLabelValue(bounds, 2, "Ignited", model.ignition and "YES" or "NO", model.ignition and theme.palette.ok or theme.palette.warning, theme.palette.textMuted)
    ui.drawLabelValue(bounds, 3, "Core", state.reactorFormed and "FORMED" or "UNFORMED", state.reactorFormed and theme.palette.ok or theme.palette.warning, theme.palette.textMuted)
    ui.drawLabelValue(bounds, 4, "Injection", tostring(model.injectionRate) .. " mB/t", state.injectionWritable and theme.palette.info or theme.palette.textMuted, theme.palette.textMuted)
    ui.drawLabelValue(bounds, 5, "Passive", model.passiveGeneration, theme.palette.info, theme.palette.textMuted)
    ui.drawLabelValue(bounds, 6, "Steam", model.steamProduction, theme.palette.info, theme.palette.textMuted)
    ui.drawLabelValue(bounds, 7, "Fuel", model.fuelFlow, theme.palette.info, theme.palette.textMuted)
    ui.drawLabelValue(bounds, 8, "Mode", model.fuelMode, theme.palette.info, theme.palette.textMuted)
    ui.drawLabelValue(bounds, 9, "Hohlraum", model.hohlraum, state.hohlraumPresent and theme.palette.ok or theme.palette.warning, theme.palette.textMuted)
  end

  local function drawTemperaturePanel(ui, bounds, theme, model)
    ui.drawPanel(bounds, "TEMPERATURES", {
      bg = theme.palette.panelBg,
      border = theme.palette.warning,
      headerBg = theme.palette.panelHeaderAlt,
      headerText = theme.palette.textPrimary,
    })
    ui.drawLabelValue(bounds, 0, "Plasma", model.plasmaTemp, theme.palette.warning, theme.palette.textMuted)
    ui.drawLabelValue(bounds, 1, "Case", model.caseTemp, theme.palette.critical, theme.palette.textMuted)
    ui.drawLabelValue(bounds, 2, "Target", "300.0 C", theme.palette.info, theme.palette.textMuted)
    local tempState = model.ignition and "RUNNING" or (model.blockers[1] and "BLOCKED" or "STANDBY")
    local tempTone = model.ignition and theme.palette.ok or (model.blockers[1] and theme.palette.critical or theme.palette.warning)
    ui.drawStatusBadge(bounds, 4, tempState, tempTone)
  end

  local function drawLaserPanel(ui, bounds, theme, model)
    ui.drawPanel(bounds, "LASER / POWER", {
      bg = theme.palette.panelBg,
      border = theme.palette.ok,
      headerBg = theme.palette.panelHeaderAlt,
      headerText = theme.palette.textPrimary,
    })
    local inner = inset(bounds, 1, 1, 1, 1)
    ui.drawLaserStack(inner, {
      count = model.laserCount,
      activeCount = model.laserActiveCount,
      pct = model.laserPct,
      state = model.laserState,
      tone = model.laserTone,
      charging = model.laserCharging,
    })
    ui.drawGauge(bounds, 6, model.laserRatio, {
      fg = model.laserTone,
      bg = theme.palette.panelBgRaised,
      label = "LAS " .. tostring(model.laserPct) .. "%",
      thickness = theme.sizes.gaugeThickness,
    })
    ui.drawGauge(bounds, 8, model.energyKnown and model.energyRatio or 0, {
      fg = theme.palette.energy,
      bg = theme.palette.panelBgRaised,
      label = model.energyKnown and ("GRID " .. string.format("%.0f%%", model.energyPct)) or "GRID N/A",
      thickness = theme.sizes.gaugeThickness,
    })
    ui.drawLabelValue(bounds, 10, "Current", model.laserEnergy, theme.palette.info, theme.palette.textMuted)
    ui.drawLabelValue(bounds, 11, "Capacity", model.laserMax, theme.palette.info, theme.palette.textMuted)
    ui.drawLabelValue(bounds, 12, "Need", model.laserNeed, theme.palette.warning, theme.palette.textMuted)
  end

  local function drawStatusPanel(ui, bounds, theme, model)
    ui.drawPanel(bounds, "STATUS / DEBUG", {
      bg = theme.palette.panelBg,
      border = theme.palette.border,
      headerBg = theme.palette.panelHeaderAlt,
      headerText = theme.palette.textPrimary,
    })
    ui.drawLabelValue(bounds, 0, "Global", model.statusText, model.statusTone, theme.palette.textMuted)
    ui.drawLabelValue(bounds, 1, "Phase", model.phase, model.phaseTone, theme.palette.textMuted)
    ui.drawLabelValue(bounds, 2, "Backend", model.backendName, theme.palette.info, theme.palette.textMuted)
    ui.drawLabelValue(bounds, 3, "Display", model.monitorName, theme.palette.info, theme.palette.textMuted)
    ui.drawLabelValue(bounds, 4, "Control", model.allowControl and "UNLOCKED" or "LOCKED", model.allowControl and theme.palette.warning or theme.palette.ok, theme.palette.textMuted)
    ui.drawLabelValue(bounds, 5, "Action", model.lastAction, theme.palette.textPrimary, theme.palette.textMuted)
    local statusLabel = "No blocking reason"
    local statusTone = theme.palette.ok
    if #model.blockers > 0 then
      statusLabel = model.blockers[1]
      statusTone = theme.palette.critical
    elseif #model.warnings > 0 then
      statusLabel = model.warnings[1]
      statusTone = theme.palette.warning
    end
    ui.drawLabelValue(bounds, 7, "Reason", statusLabel, statusTone, theme.palette.textMuted)

    local slots = math.max(0, bounds.h - 14)
    local eventRows = math.min(slots, 3, #model.events)
    if eventRows > 0 then
      ui.drawSectionTitle(bounds, 9, "Recent events", theme.palette.info)
      for i = 1, eventRows do
        ui.drawLabelValue(bounds, 9 + i, tostring(i), asText(model.events[i], "..."), theme.palette.textMuted, theme.palette.textMuted)
      end
    end
  end

  local function computeDiagnosticLayout(width, height, theme)
    local root = rect(1, 1, width, height)
    local headerH = math.max(4, math.min(5, theme.sizes.headerHeight + 3))
    local footerH = math.max(4, math.min(6, theme.sizes.footerHeight))
    local header = rect(1, 1, width, headerH)
    local footer = rect(1, height - footerH + 1, width, footerH)
    local content = rect(1, header.y2 + 1, width, math.max(1, footer.y - (header.y2 + 1)))
    local contentInner = inset(content, 1, 1, 1, 1)
    local colGap = 1
    local usableW = contentInner.w - (colGap * 2)
    if usableW < 3 then usableW = 3 end
    local baseW = math.floor(usableW / 3)
    if baseW < 8 then baseW = 8 end
    local leftW = baseW
    local midW = baseW
    local rightW = math.max(8, usableW - leftW - midW)
    local leftX = contentInner.x
    local midX = leftX + leftW + colGap
    local rightX = midX + midW + colGap
    local panelY = contentInner.y
    local panelH = contentInner.h

    return {
      root = root,
      header = header,
      footer = footer,
      reactor = rect(leftX, panelY, leftW, panelH),
      temperatures = rect(midX, panelY, midW, panelH),
      laser = rect(rightX, panelY, rightW, panelH),
      controls = inset(footer, 1, 1, 1, 1),
      footerStatus = rect(footer.x + 1, footer.y, math.max(1, footer.w - 2), 1),
    }
  end

  local function drawSimplePanel(ui, bounds, title, border, bg)
    ui.safeFrame(bounds, border, bg)
    ui.safeFilledRect(bounds.x + 1, bounds.y + 1, math.max(1, bounds.w - 2), 1, border)
    ui.safeText(bounds.x + 2, bounds.y + 1, string.upper(title), colors.white, border, math.max(1, bounds.w - 4), "left")
  end

  local function drawSimpleKV(ui, bounds, row, label, value, valueColor, mutedColor)
    local maxRows = math.max(1, bounds.h - 3)
    if row < 0 or row >= maxRows then
      return
    end
    local y = bounds.y + 2 + row
    local labelW = math.max(8, math.min(12, math.floor(bounds.w * 0.36)))
    local valueW = math.max(1, bounds.w - labelW - 4)
    ui.safeText(bounds.x + 2, y, tostring(label or "-"), mutedColor, nil, labelW, "left")
    ui.safeText(bounds.x + 2 + labelW + 1, y, tostring(value or "N/A"), valueColor, nil, valueW, "left")
  end

  local function drawSimpleDiagnostic(ui, width, height, theme, model, source, renderType)
    local diagState = ensureTomRenderDiag()
    local d = computeDiagnosticLayout(width, height, theme)
    local bg = theme.palette.bgRoot or colors.black
    ui.safeFilledRect(d.root.x, d.root.y, d.root.w, d.root.h, bg)

    local title = "TOMS DEBUG MODE"
    local sizeText = tostring(width) .. "x" .. tostring(height)
    local surfaceText = "SRC " .. tostring(source) .. " | GPU " .. tostring(model.monitorName)
    ui.safeFilledRect(d.header.x, d.header.y, d.header.w, d.header.h, theme.palette.panelHeader or colors.blue)
    ui.safeText(d.header.x + 2, d.header.y, title, theme.palette.textPrimary or colors.white, theme.palette.panelHeader, math.max(1, d.header.w - 4), "left")
    ui.safeText(d.header.x + 2, d.header.y + 1, surfaceText, theme.palette.info or colors.cyan, theme.palette.panelHeader, math.max(1, d.header.w - 4), "left")
    ui.safeText(d.header.x + 2, d.header.y + 1, "GPU " .. sizeText, theme.palette.warning or colors.orange, theme.palette.panelHeader, math.max(1, d.header.w - 4), "right")
    if d.header.h >= 3 then
      ui.safeText(d.header.x + 2, d.header.y + 2, "RENDER " .. tostring(renderType or "TOM_DIRECT"), theme.palette.textMuted or colors.lightGray, theme.palette.panelHeader, math.max(1, d.header.w - 4), "left")
    end
    if d.header.h >= 4 then
      ui.safeText(d.header.x + 2, d.header.y + 3, "DEBUG FILE: " .. TOMS_DEBUG_FILE, theme.palette.info or colors.cyan, theme.palette.panelHeader, math.max(1, d.header.w - 4), "left")
    end

    drawSimplePanel(ui, d.reactor, "Reactor", theme.palette.border or colors.lightBlue, theme.palette.panelBg or colors.black)
    drawSimpleKV(ui, d.reactor, 0, "Global", model.statusText, model.statusTone, theme.palette.textMuted)
    drawSimpleKV(ui, d.reactor, 1, "Phase", model.phase, model.phaseTone, theme.palette.textMuted)
    drawSimpleKV(ui, d.reactor, 2, "Core", state.reactorFormed and "FORMED" or "UNFORMED", state.reactorFormed and theme.palette.ok or theme.palette.warning, theme.palette.textMuted)
    drawSimpleKV(ui, d.reactor, 3, "Injection", tostring(model.injectionRate) .. " mB/t", theme.palette.info, theme.palette.textMuted)
    drawSimpleKV(ui, d.reactor, 4, "Fuel", model.fuelMode, theme.palette.info, theme.palette.textMuted)
    drawSimpleKV(ui, d.reactor, 5, "Hohlraum", model.hohlraum, state.hohlraumPresent and theme.palette.ok or theme.palette.warning, theme.palette.textMuted)

    drawSimplePanel(ui, d.temperatures, "Temperatures", theme.palette.warning or colors.orange, theme.palette.panelBg or colors.black)
    drawSimpleKV(ui, d.temperatures, 0, "Plasma", model.plasmaTemp, theme.palette.warning, theme.palette.textMuted)
    drawSimpleKV(ui, d.temperatures, 1, "Case", model.caseTemp, theme.palette.critical, theme.palette.textMuted)
    drawSimpleKV(ui, d.temperatures, 2, "Ignition", "300.0 C", theme.palette.info, theme.palette.textMuted)
    drawSimpleKV(ui, d.temperatures, 3, "Laser Need", model.laserNeed, theme.palette.warning, theme.palette.textMuted)
    drawSimpleKV(ui, d.temperatures, 4, "Warnings", tostring(#model.warnings), #model.warnings > 0 and theme.palette.warning or theme.palette.ok, theme.palette.textMuted)
    drawSimpleKV(ui, d.temperatures, 5, "Blockers", tostring(#model.blockers), #model.blockers > 0 and theme.palette.critical or theme.palette.ok, theme.palette.textMuted)

    drawSimplePanel(ui, d.laser, "Laser / Power", theme.palette.ok or colors.lime, theme.palette.panelBg or colors.black)
    drawSimpleKV(ui, d.laser, 0, "Laser State", model.laserState, model.laserTone, theme.palette.textMuted)
    drawSimpleKV(ui, d.laser, 1, "Laser Count", tostring(model.laserCount), theme.palette.info, theme.palette.textMuted)
    drawSimpleKV(ui, d.laser, 2, "Laser Ready", tostring(model.laserActiveCount) .. "/" .. tostring(model.laserCount), theme.palette.ok, theme.palette.textMuted)
    drawSimpleKV(ui, d.laser, 3, "Laser Pct", tostring(model.laserPct) .. "%", model.laserTone, theme.palette.textMuted)
    drawSimpleKV(ui, d.laser, 4, "Laser E", model.laserEnergy, theme.palette.info, theme.palette.textMuted)
    drawSimpleKV(ui, d.laser, 5, "Laser Max", model.laserMax, theme.palette.info, theme.palette.textMuted)
    drawSimpleKV(ui, d.laser, 6, "Grid", model.energyKnown and string.format("%.0f%%", model.energyPct) or "N/A", theme.palette.energy, theme.palette.textMuted)
    drawSimpleKV(ui, d.laser, 7, "Redraw", tostring(diagState.redrawCount), theme.palette.info, theme.palette.textMuted)
    drawSimpleKV(ui, d.laser, 8, "Sync", tostring(diagState.syncCount), theme.palette.info, theme.palette.textMuted)
    drawSimpleKV(ui, d.laser, 9, "Fallback", diagState.fallbackAfterTom and "YES" or "NO", diagState.fallbackAfterTom and theme.palette.warning or theme.palette.ok, theme.palette.textMuted)

    ui.safeFilledRect(d.footer.x, d.footer.y, d.footer.w, d.footer.h, theme.palette.panelHeaderAlt or colors.gray)
    ui.safeFilledRect(d.footer.x, d.footer.y, d.footer.w, 1, theme.palette.borderStrong or colors.cyan)
    ui.safeText(d.footer.x + 2, d.footer.y, "CONTROLS: REFRESH | LASER PULSE | INJ - | INJ + | QUIT | UI DIAG", theme.palette.textPrimary, theme.palette.panelHeaderAlt, math.max(1, d.footer.w - 4), "left")
    ui.safeText(d.footer.x + 2, d.footer.y + 1, "NO WINDOWS | DIRECT SURFACE DRAW | PIPELINE CHECK", theme.palette.info, theme.palette.panelHeaderAlt, math.max(1, d.footer.w - 4), "left")

    state.controlBounds = {
      x = d.controls.x,
      y = math.min(d.controls.y2, d.controls.y + 1),
      w = d.controls.w,
      h = math.max(1, d.controls.h - 1),
    }

    return d
  end

  local function drawLegacyView(view, legacyLayout)
    if view == "diagnostic" and type(api.drawDiagnosticView) == "function" then
      api.drawDiagnosticView(legacyLayout)
      return true
    end
    if view == "update" and type(api.drawUpdateView) == "function" then
      api.drawUpdateView(legacyLayout)
      return true
    end
    if view == "config" and type(api.drawConfigView) == "function" then
      api.drawConfigView(legacyLayout)
      return true
    end
    if view == "setup" and type(api.drawSetupView) == "function" then
      api.drawSetupView(legacyLayout)
      return true
    end
    return false
  end

  local function render(source, surface, width, height, renderCtx)
    renderCtx = type(renderCtx) == "table" and renderCtx or {}
    local theme = TomTheme.build(width, height)
    local model = runtimeModel(theme)
    local diag = ensureTomRenderDiag()
    diag.redrawCount = diag.redrawCount + 1
    diag.lastSource = tostring(source or "unknown")
    diag.lastSurface = tostring(hw.monitorName or source or "unknown")
    diag.lastW = tonumber(width) or 0
    diag.lastH = tonumber(height) or 0
    if type(diag.detectedDisplays) == "table" and (diag.selectedClassicMonitor == nil or diag.selectedClassicMonitor == "") then
      for _, display in ipairs(diag.detectedDisplays) do
        if tostring(display.backend or "") == "cc_monitor" then
          diag.selectedClassicMonitor = tostring(display.name or "")
          break
        end
      end
    end
    diag.surfaceContext = {
      backend = tostring(renderCtx.backend or hw.monitorBackend or "unknown"),
      backendFamily = tostring(renderCtx.backendFamily or hw.monitorBackendFamily or "unknown"),
      wrapperType = tostring(renderCtx.wrapperType or hw.monitorWrapperType or "unknown"),
      inputSource = tostring(renderCtx.inputSource or source or "unknown"),
      renderSource = tostring(renderCtx.renderSource or source or "unknown"),
      renderSurfaceType = tostring(type(surface)),
      displaySurfaceType = tostring(type(renderCtx.displaySurface)),
      nativeSurfaceType = tostring(type(renderCtx.nativeSurface)),
      displayWidth = tonumber(renderCtx.displayWidth) or 0,
      displayHeight = tonumber(renderCtx.displayHeight) or 0,
      wrappedWidth = tonumber(renderCtx.displayWidth) or tonumber(width) or 0,
      wrappedHeight = tonumber(renderCtx.displayHeight) or tonumber(height) or 0,
      nativeWidth = tonumber(renderCtx.nativeWidth) or 0,
      nativeHeight = tonumber(renderCtx.nativeHeight) or 0,
      runtimeArea = tonumber(renderCtx.runtimeArea) or (math.max(0, (tonumber(width) or 0) * (tonumber(height) or 0))),
      monitorConversion = renderCtx.monitorConversion == true,
      sourcePath = tostring(renderCtx.sourcePath or "ui.toms.fusion_panel.render"),
      wrappedPath = tostring(renderCtx.wrappedPath or "unknown"),
      sourceResolvedBy = tostring(renderCtx.sourceResolvedBy or "ui.toms.fusion_panel.render"),
      termRedirectTarget = tostring(renderCtx.termRedirectTarget or "term.current"),
    }

    local simpleMode = (state.tomUiDiagnosticMode == true) or (TOMS_DEBUG_DEFAULT == true)
    local layout = nil
    local usedNativeDebug = false
    if simpleMode then
      if renderCtx.useNativeDebug == true and type(surface) == "table" then
        usedNativeDebug = true
        layout = drawNativeDiagnostic(surface, width, height, model, source, diag)
      else
        local rootUi = TomComponents.new({
          target = term.current(),
          width = width,
          height = height,
          theme = theme,
        })
        layout = computeDiagnosticLayout(width, height, theme)
        rootUi.drawBackdrop(layout.root or rect(1, 1, width, height))
        drawSimpleDiagnostic(rootUi, width, height, theme, model, source, "TOM_DIRECT_NO_WINDOWS")
      end
      diag.renderPath = "tom_simple_diag"
      diag.windowAllowed = false
      diag.windowUsed = false
      diag.lastRenderType = "TOM_DIRECT_NO_WINDOWS"
      diag.debugBypass = {
        layoutNormal = true,
        components = true,
        windows = true,
        legacy = true,
      }
      diag.lastLayout = {
        mode = "diagnostic_direct",
        density = theme.density,
        header = layout.header,
        reactor = layout.reactor,
        temperatures = layout.temperatures,
        laser = layout.laser,
        status = nil,
        footer = layout.footer,
      }
      if type(layout) ~= "table" then
        layout = computeDiagnosticLayout(width, height, theme)
      end
      if (not usedNativeDebug) and type(api.buildButtons) == "function" and type(api.drawButtons) == "function" then
        api.buildButtons(buildLegacyLayout({
          legacy = {
            mode = "standard",
            top = 1,
            bottom = height,
            height = height,
            width = width,
            left = rect(1, 1, math.max(1, math.floor(width / 3)), height),
            center = rect(1, 1, math.max(1, math.floor(width / 3)), height),
            right = rect(1, 1, width, height),
          },
          stacked = false,
        }, theme))
        api.drawButtons(api.getCurrentInputSource and api.getCurrentInputSource() or "monitor")
      end
      if diag.redrawCount <= 2 or (diag.redrawCount % 20 == 0) then
        logInfo("Tom diagnostic draw", {
          source = diag.lastSource,
          width = tostring(diag.lastW),
          height = tostring(diag.lastH),
          createWindow = "false",
          redraw = tostring(diag.redrawCount),
          sync = tostring(diag.syncCount),
          surface = tostring(diag.lastSurface),
        })
      end
      local okSnapshot, errSnapshot = writeTomDebugSnapshot(diag, model, source, width, height)
      if not okSnapshot and (diag.redrawCount <= 2 or (diag.redrawCount % 10 == 0)) then
        logWarn("Tom debug snapshot write failed", { err = tostring(errSnapshot) })
      end
      return layout
    end

    layout = TomLayout.compute(width, height, theme, state.currentView)
    diag.renderPath = "tom_full"
    diag.debugBypass = {
      layoutNormal = false,
      components = false,
      windows = false,
      legacy = false,
    }
    diag.lastLayout = {
      mode = "normal",
      density = layout.density or theme.density,
      header = layout.header,
      reactor = layout.left and layout.left.reactor or nil,
      temperatures = layout.left and layout.left.temperatures or nil,
      laser = layout.center and layout.center.laser or nil,
      status = layout.left and layout.left.status or nil,
      footer = layout.footer,
    }
    local rootUi = TomComponents.new({
      target = term.current(),
      width = width,
      height = height,
      theme = theme,
    })
    rootUi.drawBackdrop(layout.root or rect(1, 1, width, height))

    if layout.tooSmall then
      local y = math.max(2, math.floor(height / 2))
      rootUi.safeText(2, y - 1, "Display too small", theme.palette.critical, theme.palette.bgRoot, math.max(4, width - 2), "center")
      rootUi.safeText(2, y, "Need at least " .. tostring(layout.minW) .. "x" .. tostring(layout.minH), theme.palette.warning, theme.palette.bgRoot, math.max(4, width - 2), "center")
      return layout
    end

    local warning = model.warnings[1] or "NONE"
    local warningTone = warning == "NONE" and theme.palette.info or theme.palette.warning
    local headerLeft = "FUSION SUPERVISOR"
    local headerCenter = model.phase
    local headerRight = model.statusText .. " | " .. asText(warning, "NONE")

    local footerSegments = {
      { text = "ACT " .. model.lastAction, tone = theme.palette.textMuted },
      { text = "LAS " .. model.laserState .. " " .. tostring(model.laserPct) .. "%", tone = model.laserTone },
      { text = "GRID " .. (model.energyKnown and string.format("%3.0f%%", model.energyPct) or "N/A"), tone = theme.palette.energy },
      { text = "MON " .. model.monitorName, tone = theme.palette.info },
    }
    local legacyLayout = buildLegacyLayout(layout, theme)

    rootUi.drawHeader(layout.header, headerLeft, headerCenter, headerRight, model.phaseTone, warningTone)
    rootUi.drawFooter(layout.controls.statusBounds or layout.footer, footerSegments)

    if state.choosingMonitor and type(api.drawMonitorSelection) == "function" then
      api.drawMonitorSelection(legacyLayout)
      rootUi.drawHeader(layout.header, headerLeft, headerCenter, headerRight, model.phaseTone, warningTone)
      rootUi.drawFooter(layout.controls.statusBounds or layout.footer, footerSegments)
      return layout
    end

    local view = tostring(state.currentView or "supervision")
    if view ~= "supervision" and view ~= "manual" and view ~= "induction" then
      if drawLegacyView(view, legacyLayout) then
        rootUi.drawHeader(layout.header, headerLeft, headerCenter, headerRight, model.phaseTone, warningTone)
        rootUi.drawFooter(layout.controls.statusBounds or layout.footer, footerSegments)
        return layout
      end
    end

    local inputSource = tostring(renderCtx.inputSource or source or "monitor")
    local useWindows = inputSource == "monitor"
      and type(surface) == "table"
      and type(surface.createWindow) == "function"
      and theme.density ~= "small"
    diag.windowAllowed = useWindows == true
    diag.windowUsed = false
    diag.lastRenderType = useWindows and "TOM_WINDOWS" or "TOM_DIRECT"
    logDebug("Tom render path", {
      source = tostring(source),
      inputSource = tostring(inputSource),
      width = tostring(width),
      height = tostring(height),
      createWindow = tostring(useWindows),
      renderType = tostring(diag.lastRenderType),
      redraw = tostring(diag.redrawCount),
    })

    local function drawArea(bounds, drawFn)
      if useWindows and bounds.w >= 14 and bounds.h >= 6 then
        local okWin, win = pcall(surface.createWindow, bounds.x, bounds.y, bounds.w, bounds.h)
        if okWin and type(win) == "table" then
          diag.windowUsed = true
          local prev = term.current()
          term.redirect(win)
          local localUi = TomComponents.new({
            target = win,
            width = bounds.w,
            height = bounds.h,
            theme = theme,
          })
          local okDraw, errDraw = pcall(drawFn, localUi, rect(1, 1, bounds.w, bounds.h))
          if type(win.flush) == "function" then
            pcall(win.flush)
          elseif type(win.sync) == "function" then
            pcall(win.sync)
          end
          term.redirect(prev)
          if not okDraw then
            pushDiagError(diag, "window_draw_failed:" .. tostring(errDraw))
            logWarn("Tom area draw failed", { err = tostring(errDraw) })
          end
          return
        end
        pushDiagError(diag, "create_window_failed:" .. tostring(bounds.w) .. "x" .. tostring(bounds.h))
      end
      drawFn(rootUi, bounds)
    end

    local panels = layout.panels or {}

    if type(panels.reactor) == "table" then
      drawArea(panels.reactor, function(ui, localBounds)
        drawReactorPanel(ui, localBounds, theme, model)
      end)
    end

    if type(panels.temperatures) == "table" then
      drawArea(panels.temperatures, function(ui, localBounds)
        drawTemperaturePanel(ui, localBounds, theme, model)
      end)
    end

    if type(panels.laser) == "table" then
      drawArea(panels.laser, function(ui, localBounds)
        drawLaserPanel(ui, localBounds, theme, model)
      end)
    end

    if type(panels.status) == "table" then
      drawArea(panels.status, function(ui, localBounds)
        drawStatusPanel(ui, localBounds, theme, model)
      end)
    end

    if type(panels.core) == "table" then
      drawArea(panels.core, function(ui, localBounds)
        ui.drawPanel(localBounds, "REACTOR CORE", {
          bg = theme.palette.panelBg,
          border = theme.palette.borderStrong,
          headerBg = theme.palette.panelHeaderAlt,
          headerText = theme.palette.textPrimary,
        })
        local coreInner = inset(localBounds, 1, 1, 1, 1)
        ui.drawReactorCore(coreInner, {
          tick = state.tick or 0,
          reactorState = model.reactorState,
          ignition = model.ignition,
          laserActive = model.laserActive,
          laserCharging = model.laserCharging,
          laserLabel = "LAS " .. tostring(model.laserPct) .. "%",
          plasmaTemp = model.plasmaTemp,
          caseTemp = model.caseTemp,
          tOpen = model.tOpen,
          dtOpen = model.dtOpen,
          dOpen = model.dOpen,
        })
      end)
    end

    local controlsBounds = layout.controls.buttonBounds
    rootUi.drawPanel(controlsBounds, "CONTROLS", {
      bg = theme.palette.panelBg,
      border = theme.palette.border,
      headerBg = theme.palette.panelHeaderAlt,
      headerText = theme.palette.textPrimary,
    })

    local controlsInner = inset(controlsBounds, 1, 1, 1, 1)
    local controlsOffsetY = (controlsInner.h >= 2) and 1 or 0
    state.controlBounds = {
      x = controlsInner.x,
      y = controlsInner.y + controlsOffsetY,
      w = controlsInner.w,
      h = math.max(1, controlsInner.h - controlsOffsetY),
    }

    if type(api.buildButtons) == "function" and type(api.drawButtons) == "function" then
      api.buildButtons(legacyLayout)
      api.drawButtons(api.getCurrentInputSource and api.getCurrentInputSource() or "monitor")
    end

    if controlsInner.h >= 2 then
      rootUi.safeText(
        controlsInner.x + 1,
        controlsInner.y,
        "ACTIONS: REFRESH | LASER PULSE | INJECTION | QUIT",
        theme.palette.textMuted,
        nil,
        math.max(1, controlsInner.w - 2),
        "left"
      )
    end

    rootUi.drawHeader(layout.header, headerLeft, headerCenter, headerRight, model.phaseTone, warningTone)
    rootUi.drawFooter(layout.controls.statusBounds or layout.footer, footerSegments)
    return layout
  end

  return {
    render = render,
  }
end

return M
