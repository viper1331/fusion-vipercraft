local TomTheme = require("ui.toms.theme")
local TomLayout = require("ui.toms.layout")
local TomComponents = require("ui.toms.components")

local M = {}
-- Manual force switch for local debugging from this module.
local TOMS_DEBUG_DEFAULT = false

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
      laserEnergy = formatEnergy(state.laserEnergy),
      laserMax = formatEnergy(state.laserMax),
      laserNeed = formatEnergy(state.laserThresholdRaw),
      laserCount = laserCount,
      laserActiveCount = activeLasers,
      laserCharging = state.laserChargeOn == true,
      laserActive = state.laserLineOn == true,
      energyPct = clamp(asNumber(state.energyPct, 0), 0, 100),
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
    return diag
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
      border = theme.palette.border,
      headerBg = theme.palette.panelHeader,
      headerText = theme.palette.textPrimary,
    })
    ui.drawStatusBadge(bounds, 0, model.statusText, model.statusTone)
    ui.drawLabelValue(bounds, 2, "Core", state.reactorFormed and "FORMED" or "UNFORMED", state.reactorFormed and theme.palette.ok or theme.palette.warning, theme.palette.textMuted)
    ui.drawLabelValue(bounds, 3, "Injection", tostring(model.injectionRate) .. " mB/t", state.injectionWritable and theme.palette.info or theme.palette.textMuted, theme.palette.textMuted)
    ui.drawLabelValue(bounds, 4, "Fuel Mode", model.fuelMode, theme.palette.info, theme.palette.textMuted)
    ui.drawLabelValue(bounds, 5, "Fuel Flow", model.fuelFlow, theme.palette.info, theme.palette.textMuted)
    ui.drawLabelValue(bounds, 6, "Hohlraum", model.hohlraum, state.hohlraumPresent and theme.palette.ok or theme.palette.warning, theme.palette.textMuted)
  end

  local function drawTemperaturePanel(ui, bounds, theme, model)
    ui.drawPanel(bounds, "TEMPERATURES", {
      bg = theme.palette.panelBg,
      border = theme.palette.warning,
      headerBg = theme.palette.panelHeaderAlt,
      headerText = theme.palette.textPrimary,
    })
    ui.drawLabelValue(bounds, 0, "Plasma", model.plasmaTemp, theme.palette.warning, theme.palette.textMuted)
    ui.drawLabelValue(bounds, 1, "Structure", model.caseTemp, theme.palette.critical, theme.palette.textMuted)
    ui.drawLabelValue(bounds, 2, "Ignition", "300.0 C", theme.palette.info, theme.palette.textMuted)
  end

  local function drawStatusPanel(ui, bounds, theme, model)
    ui.drawPanel(bounds, "STATUS / DEBUG", {
      bg = theme.palette.panelBg,
      border = theme.palette.border,
      headerBg = theme.palette.panelHeaderAlt,
      headerText = theme.palette.textPrimary,
    })
    local row = 0
    ui.drawLabelValue(bounds, row, "Phase", model.phase, model.phaseTone, theme.palette.textMuted)
    row = row + 1
    ui.drawLabelValue(bounds, row, "Output", model.monitorName, theme.palette.info, theme.palette.textMuted)
    row = row + 1
    ui.drawLabelValue(bounds, row, "Backend", model.backendName, theme.palette.info, theme.palette.textMuted)
    row = row + 1
    ui.drawLabelValue(bounds, row, "Control", model.allowControl and "ENABLED" or "LOCKED", model.allowControl and theme.palette.warning or theme.palette.ok, theme.palette.textMuted)
    row = row + 1
    ui.drawLabelValue(bounds, row, "Action", model.lastAction, theme.palette.textPrimary, theme.palette.textMuted)
    row = row + 1

    if #model.blockers > 0 then
      for i = 1, math.min(#model.blockers, math.max(1, bounds.h - (row + 4))) do
        ui.drawLabelValue(bounds, row, "[NO]", model.blockers[i], theme.palette.critical, theme.palette.textMuted)
        row = row + 1
      end
    elseif #model.warnings > 0 then
      for i = 1, math.min(#model.warnings, math.max(1, bounds.h - (row + 4))) do
        ui.drawLabelValue(bounds, row, "[!]", model.warnings[i], theme.palette.warning, theme.palette.textMuted)
        row = row + 1
      end
    else
      ui.drawLabelValue(bounds, row, "[OK]", "No active warning", theme.palette.ok, theme.palette.textMuted)
    end
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
  end

  local function drawRuntimePanel(ui, bounds, theme, model)
    ui.drawPanel(bounds, "RUNTIME", {
      bg = theme.palette.panelBg,
      border = theme.palette.border,
      headerBg = theme.palette.panelHeaderAlt,
      headerText = theme.palette.textPrimary,
    })

    local laserRatio = clamp(asNumber(state.laserPct, 0) / 100, 0, 1)
    local gridRatio = clamp(asNumber(state.energyPct, 0) / 100, 0, 1)
    ui.drawHorizontalBar(bounds, 0, laserRatio, theme.palette.ok, theme.palette.panelBgRaised, "LAS CHARGE")
    ui.drawHorizontalBar(bounds, 1, gridRatio, theme.palette.energy, theme.palette.panelBgRaised, "GRID LEVEL")
    ui.drawLabelValue(bounds, 3, "Laser Energy", model.laserEnergy, theme.palette.info, theme.palette.textMuted)
    ui.drawLabelValue(bounds, 4, "Laser Max", model.laserMax, theme.palette.info, theme.palette.textMuted)
    ui.drawLabelValue(bounds, 5, "Need", model.laserNeed, theme.palette.warning, theme.palette.textMuted)
    ui.drawLabelValue(bounds, 6, "Production", model.passiveGeneration, theme.palette.info, theme.palette.textMuted)
    ui.drawLabelValue(bounds, 7, "Steam", model.steamProduction, theme.palette.info, theme.palette.textMuted)
  end

  local function drawIoPanel(ui, bounds, theme, model)
    ui.drawPanel(bounds, "REAL I/O", {
      bg = theme.palette.panelBg,
      border = theme.palette.border,
      headerBg = theme.palette.panelHeaderAlt,
      headerText = theme.palette.textPrimary,
    })
    if type(api.drawIoPanel) == "function" and state.currentView ~= "setup" then
      local ioInner = inset(bounds, 1, 1, 1, 1)
      api.drawIoPanel(ioInner)
      return
    end
    ui.drawLabelValue(bounds, 0, "Monitor", model.monitorName, theme.palette.info, theme.palette.textMuted)
    ui.drawLabelValue(bounds, 1, "Backend", model.backendName, theme.palette.info, theme.palette.textMuted)
    ui.drawLabelValue(bounds, 2, "Output", asText(api.getCurrentInputSource and api.getCurrentInputSource() or "monitor", "monitor"), theme.palette.info, theme.palette.textMuted)
  end

  local function drawEventsPanel(ui, bounds, theme, model)
    ui.drawPanel(bounds, "EVENT LOG", {
      bg = theme.palette.panelBg,
      border = theme.palette.border,
      headerBg = theme.palette.panelHeaderAlt,
      headerText = theme.palette.textPrimary,
    })
    local slots = math.max(1, bounds.h - 4)
    if #model.events == 0 then
      ui.drawLabelValue(bounds, 0, "-", "No runtime event", theme.palette.textMuted, theme.palette.textMuted)
      return
    end
    for i = 1, math.min(slots, #model.events) do
      ui.drawLabelValue(bounds, i - 1, tostring(i), asText(model.events[i], "..."), theme.palette.info, theme.palette.textMuted)
    end
  end

  local function drawControlSummary(ui, bounds, theme, model)
    ui.drawPanel(bounds, "CONTROL MODE", {
      bg = theme.palette.panelBg,
      border = theme.palette.border,
      headerBg = theme.palette.panelHeaderAlt,
      headerText = theme.palette.textPrimary,
    })
    ui.drawLabelValue(bounds, 0, "Master", state.autoMaster and "AUTO" or "MANUAL", state.autoMaster and theme.palette.ok or theme.palette.warning, theme.palette.textMuted)
    ui.drawLabelValue(bounds, 1, "Fusion", state.fusionAuto and "AUTO" or "MANUAL", state.fusionAuto and theme.palette.ok or theme.palette.warning, theme.palette.textMuted)
    ui.drawLabelValue(bounds, 2, "Charge", state.chargeAuto and "AUTO" or "MANUAL", state.chargeAuto and theme.palette.ok or theme.palette.warning, theme.palette.textMuted)
    ui.drawLabelValue(bounds, 3, "Laser", model.laserState, model.laserTone, theme.palette.textMuted)
  end

  local function computeDiagnosticLayout(width, height, theme)
    local root = rect(1, 1, width, height)
    local headerH = math.max(3, math.min(4, theme.sizes.headerHeight + 2))
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

    drawSimplePanel(ui, d.reactor, "Reactor", theme.palette.border or colors.lightBlue, theme.palette.panelBg or colors.black)
    ui.drawLabelValue(d.reactor, 0, "Global", model.statusText, model.statusTone, theme.palette.textMuted)
    ui.drawLabelValue(d.reactor, 1, "Phase", model.phase, model.phaseTone, theme.palette.textMuted)
    ui.drawLabelValue(d.reactor, 2, "Core", state.reactorFormed and "FORMED" or "UNFORMED", state.reactorFormed and theme.palette.ok or theme.palette.warning, theme.palette.textMuted)
    ui.drawLabelValue(d.reactor, 3, "Injection", tostring(model.injectionRate) .. " mB/t", theme.palette.info, theme.palette.textMuted)
    ui.drawLabelValue(d.reactor, 4, "Fuel", model.fuelMode, theme.palette.info, theme.palette.textMuted)
    ui.drawLabelValue(d.reactor, 5, "Hohlraum", model.hohlraum, state.hohlraumPresent and theme.palette.ok or theme.palette.warning, theme.palette.textMuted)

    drawSimplePanel(ui, d.temperatures, "Temperatures", theme.palette.warning or colors.orange, theme.palette.panelBg or colors.black)
    ui.drawLabelValue(d.temperatures, 0, "Plasma", model.plasmaTemp, theme.palette.warning, theme.palette.textMuted)
    ui.drawLabelValue(d.temperatures, 1, "Case", model.caseTemp, theme.palette.critical, theme.palette.textMuted)
    ui.drawLabelValue(d.temperatures, 2, "Ignition", "300.0 C", theme.palette.info, theme.palette.textMuted)
    ui.drawLabelValue(d.temperatures, 3, "Laser Need", model.laserNeed, theme.palette.warning, theme.palette.textMuted)
    ui.drawLabelValue(d.temperatures, 4, "Warnings", tostring(#model.warnings), #model.warnings > 0 and theme.palette.warning or theme.palette.ok, theme.palette.textMuted)
    ui.drawLabelValue(d.temperatures, 5, "Blockers", tostring(#model.blockers), #model.blockers > 0 and theme.palette.critical or theme.palette.ok, theme.palette.textMuted)

    drawSimplePanel(ui, d.laser, "Laser / Power", theme.palette.ok or colors.lime, theme.palette.panelBg or colors.black)
    ui.drawLabelValue(d.laser, 0, "Laser State", model.laserState, model.laserTone, theme.palette.textMuted)
    ui.drawLabelValue(d.laser, 1, "Laser Count", tostring(model.laserCount), theme.palette.info, theme.palette.textMuted)
    ui.drawLabelValue(d.laser, 2, "Laser Ready", tostring(model.laserActiveCount) .. "/" .. tostring(model.laserCount), theme.palette.ok, theme.palette.textMuted)
    ui.drawLabelValue(d.laser, 3, "Laser Pct", tostring(model.laserPct) .. "%", model.laserTone, theme.palette.textMuted)
    ui.drawLabelValue(d.laser, 4, "Laser E", model.laserEnergy, theme.palette.info, theme.palette.textMuted)
    ui.drawLabelValue(d.laser, 5, "Laser Max", model.laserMax, theme.palette.info, theme.palette.textMuted)
    ui.drawLabelValue(d.laser, 6, "Grid", model.energyKnown and string.format("%.0f%%", model.energyPct) or "N/A", theme.palette.energy, theme.palette.textMuted)
    ui.drawLabelValue(d.laser, 7, "Redraw", tostring(diagState.redrawCount), theme.palette.info, theme.palette.textMuted)
    ui.drawLabelValue(d.laser, 8, "Sync", tostring(diagState.syncCount), theme.palette.info, theme.palette.textMuted)
    ui.drawLabelValue(d.laser, 9, "Fallback", diagState.fallbackAfterTom and "YES" or "NO", diagState.fallbackAfterTom and theme.palette.warning or theme.palette.ok, theme.palette.textMuted)

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

  local function render(source, surface, width, height)
    local theme = TomTheme.build(width, height)
    local rootUi = TomComponents.new({
      target = term.current(),
      width = width,
      height = height,
      theme = theme,
    })
    local model = runtimeModel(theme)
    local diag = ensureTomRenderDiag()
    diag.redrawCount = diag.redrawCount + 1
    diag.lastSource = tostring(source or "unknown")
    diag.lastSurface = tostring(hw.monitorName or source or "unknown")
    diag.lastW = tonumber(width) or 0
    diag.lastH = tonumber(height) or 0

    local simpleMode = (state.tomUiDiagnosticMode == true) or (TOMS_DEBUG_DEFAULT == true)
    local layout = nil
    if simpleMode then
      layout = computeDiagnosticLayout(width, height, theme)
      diag.renderPath = "tom_simple_diag"
      diag.windowAllowed = false
      diag.windowUsed = false
      diag.lastRenderType = "TOM_DIRECT_NO_WINDOWS"
      rootUi.drawBackdrop(layout.root or rect(1, 1, width, height))
      drawSimpleDiagnostic(rootUi, width, height, theme, model, source, "TOM_DIRECT_NO_WINDOWS")
      if type(api.buildButtons) == "function" and type(api.drawButtons) == "function" then
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
      return layout
    end

    layout = TomLayout.compute(width, height, theme, state.currentView)
    diag.renderPath = "tom_full"
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

    local useWindows = source == "monitor"
      and type(surface) == "table"
      and type(surface.createWindow) == "function"
      and theme.density ~= "small"
    diag.windowAllowed = useWindows == true
    diag.windowUsed = false
    diag.lastRenderType = useWindows and "TOM_WINDOWS" or "TOM_DIRECT"
    logDebug("Tom render path", {
      source = tostring(source),
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
            logWarn("Tom area draw failed", { err = tostring(errDraw) })
          end
          return
        end
      end
      drawFn(rootUi, bounds)
    end

    drawArea(layout.columns.left, function(ui, localBounds)
      local localLayout = {
        left = splitVertical(inset(localBounds, 1, 1, 1, 1), {
          { key = "reactor", weight = 4 },
          { key = "temperatures", weight = 3 },
          { key = "status", weight = 5 },
        }, theme.spacing.sectionGap),
      }
      drawReactorPanel(ui, localLayout.left.reactor, theme, model)
      drawTemperaturePanel(ui, localLayout.left.temperatures, theme, model)
      drawStatusPanel(ui, localLayout.left.status, theme, model)
    end)

    drawArea(layout.columns.center, function(ui, localBounds)
      local localLayout = {
        center = splitVertical(inset(localBounds, 1, 1, 1, 1), {
          { key = "laser", weight = 4 },
          { key = "core", weight = 10 },
          { key = "runtime", weight = 4 },
        }, theme.spacing.sectionGap),
      }
      drawLaserPanel(ui, localLayout.center.laser, theme, model)
      ui.drawPanel(localLayout.center.core, "REACTOR CORE", {
        bg = theme.palette.panelBg,
        border = theme.palette.borderStrong,
        headerBg = theme.palette.panelHeaderAlt,
        headerText = theme.palette.textPrimary,
      })
      local coreInner = inset(localLayout.center.core, 1, 1, 1, 1)
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
      drawRuntimePanel(ui, localLayout.center.runtime, theme, model)
    end)

    drawArea(layout.columns.right, function(ui, localBounds)
      local localLayout = {
        right = splitVertical(inset(localBounds, 1, 1, 1, 1), {
          { key = "io", weight = 5 },
          { key = "events", weight = 4 },
          { key = "debug", weight = 3 },
        }, theme.spacing.sectionGap),
      }
      drawIoPanel(ui, localLayout.right.io, theme, model)
      drawEventsPanel(ui, localLayout.right.events, theme, model)
      drawControlSummary(ui, localLayout.right.debug, theme, model)
    end)

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

    rootUi.drawHeader(layout.header, headerLeft, headerCenter, headerRight, model.phaseTone, warningTone)
    rootUi.drawFooter(layout.controls.statusBounds or layout.footer, footerSegments)
    return layout
  end

  return {
    render = render,
  }
end

return M
