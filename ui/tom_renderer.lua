local TomDesign = require("ui.tom_design")
local TomLayout = require("ui.tom_layout")
local TomComponents = require("ui.tom_components")

local M = {}

local function clamp(value, lo, hi)
  if value < lo then return lo end
  if value > hi then return hi end
  return value
end

local function safeNumber(value, fallback)
  local n = tonumber(value)
  if n == nil then return fallback or 0 end
  return n
end

local function safeText(value, fallback)
  local txt = tostring(value or "")
  if txt == "" then
    return tostring(fallback or "N/A")
  end
  return txt
end

function M.build(api)
  local state = assert(api.state, "state is required")
  local hw = assert(api.hw, "hw is required")
  local CFG = assert(api.CFG, "CFG is required")
  local C = assert(api.C, "C is required")
  local writeAt = assert(api.writeAt, "writeAt is required")
  local fillArea = assert(api.fillArea, "fillArea is required")

  local shortText = type(api.shortText) == "function"
    and api.shortText
    or function(text, maxLen)
      text = tostring(text or "")
      maxLen = math.max(0, math.floor(tonumber(maxLen) or 0))
      if #text <= maxLen then return text end
      if maxLen <= 0 then return "" end
      return text:sub(1, maxLen)
    end

  local log = type(api.log) == "table" and api.log or nil

  local function logWarn(message, meta)
    if log and type(log.warn) == "function" then
      log.warn(message, meta)
    end
  end

  local function logDebug(message, meta)
    if log and type(log.debug) == "function" then
      log.debug(message, meta)
    end
  end

  local function formatTemp(value, decimals)
    if type(api.formatTemperature) == "function" then
      return tostring(api.formatTemperature(value, {
        compact = true,
        decimals = decimals or 1,
      }))
    end
    return string.format("%.1f C", tonumber(value) or 0)
  end

  local function formatEnergy(value)
    if type(api.formatEnergy) == "function" then
      return tostring(api.formatEnergy(value))
    end
    return tostring(value or "N/A")
  end

  local function formatEnergyRate(value)
    if type(api.formatEnergyPerTick) == "function" then
      return tostring(api.formatEnergyPerTick(value))
    end
    return tostring(value or "N/A")
  end

  local function phaseText()
    if type(api.reactorPhase) == "function" then
      return tostring(api.reactorPhase())
    end
    return safeText(state.status, "INIT")
  end

  local function phaseTone()
    if type(api.phaseColor) == "function" then
      return api.phaseColor(phaseText())
    end
    return C.info
  end

  local function laserTone()
    local st = tostring(state.laserState or "ABSENT")
    if st == "READY" then return C.ok end
    if st == "CHARGING" or st == "INSUFFICIENT" then return C.warn end
    if st == "ABSENT" then return C.bad end
    return C.dim
  end

  local function drawWindowed(source, surface, bounds, drawFn)
    local prev = term.current()
    local okDraw, errDraw
    local usedWindow = false

    if source == "monitor"
      and type(surface) == "table"
      and type(surface.createWindow) == "function"
      and bounds.w >= 8
      and bounds.h >= 4 then
      local okWin, win = pcall(surface.createWindow, bounds.x, bounds.y, bounds.w, bounds.h)
      if okWin and type(win) == "table" and type(win.getSize) == "function" then
        usedWindow = true
        term.redirect(win)
        okDraw, errDraw = pcall(drawFn, {
          x = 1,
          y = 1,
          w = bounds.w,
          h = bounds.h,
        }, true)
      else
        okDraw, errDraw = pcall(drawFn, bounds, false)
      end
    else
      okDraw, errDraw = pcall(drawFn, bounds, false)
    end

    term.redirect(prev)
    if not okDraw then
      logWarn("Tom window draw failed", { err = tostring(errDraw) })
    elseif usedWindow then
      logDebug("Tom window rendered", {
        x = tostring(bounds.x),
        y = tostring(bounds.y),
        w = tostring(bounds.w),
        h = tostring(bounds.h),
      })
    end
  end

  local function drawHeaderAndFooter(components, layout)
    local warn = (type(state.safetyWarnings) == "table" and state.safetyWarnings[1]) or "NONE"
    local rightTone = (warn ~= "NONE") and C.warn or C.info
    components.drawHeader(
      layout.header,
      "FUSION SUPERVISOR",
      phaseText(),
      "INFO " .. shortText(warn, 24),
      phaseTone(),
      rightTone
    )

    local gridPct = state.energyKnown and string.format("%3.0f%%", tonumber(state.energyPct) or 0) or "N/A"
    local laserText = shortText(tostring(state.laserStatusText or state.laserState or "ABS"), 14)
    components.drawFooter(layout.footer, {
      { text = "ACT " .. shortText(state.lastAction or "NONE", 18), tone = C.text },
      { text = "VIEW " .. shortText(string.upper(tostring(state.currentView or "supervision")), 8), tone = C.info },
      { text = "PHS " .. shortText(phaseText(), 12), tone = phaseTone() },
      { text = "LAS " .. laserText, tone = laserTone() },
      { text = "GRID " .. gridPct, tone = C.energy },
      { text = "OUT " .. shortText(hw.monitorName or "terminal", 16), tone = C.info },
    })
  end

  local function drawStatusColumn(components, panel, density)
    components.drawPanel(panel, "REACTOR STATUS", {
      bg = C.panelDark,
      border = C.border,
      headerBg = C.headerBg,
      headerFg = C.headerText,
    })

    local statusRows = {
      { "Phase", phaseText(), phaseTone() },
      { "Core", state.reactorPresent and (state.reactorFormed and "FORMED" or "UNFORMED") or "ABSENT", state.reactorPresent and C.info or C.bad },
      { "Ignition", state.ignition and "RUNNING" or "IDLE", state.ignition and C.ok or C.warn },
      { "Injection", tostring(math.floor(safeNumber(state.injectionRate, 0))) .. " mB/t", state.injectionWritable and C.info or C.dim },
      { "Plasma", formatTemp(state.plasmaTemp, density == "large" and 2 or 1), C.warn },
      { "Struct", formatTemp(state.caseTemp, density == "large" and 2 or 1), C.bad },
      { "Laser", shortText(tostring(state.laserStatusText or state.laserState or "ABS"), 16), laserTone() },
      { "Laser %", string.format("%3.0f%%", safeNumber(state.laserPct, 0)), C.info },
      { "L Energy", formatEnergy(state.laserEnergy), C.energy },
      { "L Max", formatEnergy(state.laserMax), C.energy },
      { "L Need", formatEnergy(state.laserThresholdRaw), C.warn },
      { "Prod", formatEnergyRate(state.passiveGeneration), C.info },
      { "Steam", tostring(math.floor(safeNumber(state.steamProduction, 0))) .. " mB/t", C.info },
      { "Hohlraum", state.hohlraumPresent and "PRESENT" or "MISSING", state.hohlraumPresent and C.ok or C.bad },
    }

    local maxRows = (density == "small") and 6 or ((density == "medium") and 10 or 14)
    for i = 1, math.min(maxRows, #statusRows) do
      local row = statusRows[i]
      components.drawLabelValue(panel, i - 1, row[1], row[2], row[3], C.dim)
    end

    local warnings = type(state.safetyWarnings) == "table" and state.safetyWarnings or {}
    local warningTop = maxRows + 1
    if #warnings > 0 and warningTop <= (panel.h - 4) then
      components.drawSectionTitle(panel, warningTop, "WARNINGS", C.warn)
      local warnLimit = (density == "small") and 1 or ((density == "medium") and 2 or 3)
      for i = 1, math.min(#warnings, warnLimit) do
        components.drawLabelValue(panel, warningTop + i, "-", warnings[i], C.warn, C.dim)
      end
    end

    local logs = type(state.eventLog) == "table" and state.eventLog or {}
    local logTop = panel.h - ((density == "small") and 2 or 4)
    if logTop >= 0 then
      components.drawSectionTitle(panel, logTop, "EVENT LOG", C.info)
      local logRows = (density == "small") and 1 or 2
      for i = 1, logRows do
        local entry = logs[i] or "N/A"
        components.drawLabelValue(panel, logTop + i, "#", entry, C.info, C.dim)
      end
    end
  end

  local function drawCenterSummary(components, bounds)
    components.drawPanel(bounds, "FUSION SUMMARY", {
      bg = C.panelDark,
      border = C.border,
      headerBg = C.headerBg,
      headerFg = C.headerText,
    })

    local formedText = state.reactorPresent and (state.reactorFormed and "CORE FORMED" or "CORE UNFORMED") or "CORE ABSENT"
    local formedTone = state.reactorPresent and (state.reactorFormed and C.ok or C.warn) or C.bad
    components.drawStatusBadge(bounds, 0, formedText, formedTone)

    local fuelMode = type(api.getRuntimeFuelMode) == "function"
      and tostring(api.getRuntimeFuelMode())
      or "N/A"
    local fuelTone = (type(api.isRuntimeFuelOk) == "function" and api.isRuntimeFuelOk()) and C.ok or C.warn
    components.drawLabelValue(bounds, 2, "Fuel", fuelMode, fuelTone, C.dim)
    components.drawLabelValue(bounds, 3, "Injection", tostring(math.floor(safeNumber(state.injectionRate, 0))) .. " mB/t", C.info, C.dim)
  end

  local function drawCenterTemps(components, bounds)
    components.drawPanel(bounds, "TEMPERATURES", {
      bg = C.panelDark,
      border = C.borderDim,
      headerBg = C.headerBg,
      headerFg = C.headerText,
    })
    components.drawLabelValue(bounds, 0, "Plasma", formatTemp(state.plasmaTemp, 2), C.warn, C.dim)
    components.drawLabelValue(bounds, 1, "Struct", formatTemp(state.caseTemp, 2), C.bad, C.dim)
  end

  local function drawCenterLaser(components, bounds, density)
    components.drawPanel(bounds, "LASER", {
      bg = C.panelDark,
      border = C.borderDim,
      headerBg = C.headerBg,
      headerFg = C.headerText,
    })

    local chargeRatio = clamp(safeNumber(state.laserPct, 0) / 100, 0, 1)
    local statusTxt = tostring(state.laserStatusText or state.laserState or "ABS")
    local statusTone = laserTone()
    components.drawHorizontalBar(bounds, 0, chargeRatio, C.ok, C.panelMid, string.format("%3.0f%%", safeNumber(state.laserPct, 0)))
    components.drawLabelValue(bounds, 2, "State", statusTxt, statusTone, C.dim)
    if density ~= "small" then
      components.drawLabelValue(bounds, 3, "Stored", formatEnergy(state.laserEnergy), C.energy, C.dim)
      components.drawLabelValue(bounds, 4, "Needed", formatEnergy(state.laserThresholdRaw), C.warn, C.dim)
    end
  end

  local function drawCenterStatus(components, bounds, density)
    components.drawPanel(bounds, "RUNTIME", {
      bg = C.panelDark,
      border = C.borderDim,
      headerBg = C.headerBg,
      headerFg = C.headerText,
    })

    local rows = {
      { "T Lock", state.tOpen and "OPEN" or "CLOSED", state.tOpen and C.tritium or C.dim },
      { "DT Lock", state.dtOpen and "OPEN" or "CLOSED", state.dtOpen and C.dtFuel or C.dim },
      { "D Lock", state.dOpen and "OPEN" or "CLOSED", state.dOpen and C.deuterium or C.dim },
      { "Alert", safeText(state.alert, "INFO"), (state.alert == "DANGER") and C.bad or ((state.alert == "WARN") and C.warn or C.info) },
      { "Power", state.energyKnown and string.format("%3.0f%%", safeNumber(state.energyPct, 0)) or "N/A", C.energy },
    }

    local maxRows = (density == "small") and 3 or #rows
    for i = 1, math.min(maxRows, #rows) do
      local row = rows[i]
      components.drawLabelValue(bounds, i - 1, row[1], row[2], row[3], C.dim)
    end
  end

  local function drawControlColumn(components, legacyLayout)
    local rightColumn = legacyLayout.right
    local controls = legacyLayout.tom.controls or {}
    local buttonBounds = controls.buttonBounds or {
      x = rightColumn.x + 2,
      y = rightColumn.y + 2,
      w = math.max(8, rightColumn.w - 4),
      h = math.max(3, rightColumn.h - 4),
    }
    local navBounds = controls.navBounds
    local ioBounds = controls.ioBounds

    components.drawPanel(rightColumn, "CONTROL COLUMN", {
      bg = C.panelDark,
      border = C.border,
      headerBg = C.headerBg,
      headerFg = C.headerText,
    })

    if navBounds then
      components.drawPanel(navBounds, "NAV", {
        bg = C.panelDark,
        border = C.borderDim,
        headerBg = C.headerBg,
        headerFg = C.headerText,
      })
    end

    components.drawPanel(buttonBounds, "ACTIONS", {
      bg = C.panelDark,
      border = C.borderDim,
      headerBg = C.headerBg,
      headerFg = C.headerText,
    })

    state.controlBounds = {
      x = buttonBounds.x + 1,
      y = buttonBounds.y + 1,
      w = math.max(6, buttonBounds.w - 2),
      h = math.max(3, buttonBounds.h - 2),
    }
    api.buildButtons(legacyLayout)
    api.drawButtons(api.getCurrentInputSource())

    if ioBounds and type(api.drawIoPanel) == "function" and state.currentView ~= "setup" then
      components.drawPanel(ioBounds, "REAL I/O", {
        bg = C.panelDark,
        border = C.borderDim,
        headerBg = C.headerBg,
        headerFg = C.headerText,
      })
      local ioInner = {
        x = ioBounds.x + 1,
        y = ioBounds.y + 1,
        w = math.max(1, ioBounds.w - 2),
        h = math.max(1, ioBounds.h - 2),
      }
      api.drawIoPanel(ioInner)
    end
  end

  local function drawReactorCenter(source, surface, components, legacyLayout, density)
    local center = legacyLayout.tom.center
    drawCenterSummary(components, center.summary)

    drawWindowed(source, surface, center.reactor, function(bounds)
      api.drawReactorDiagram(bounds.x, bounds.y, bounds.w, bounds.h)
    end)

    drawCenterTemps(components, center.temps)
    drawCenterLaser(components, center.laser, density)
    drawCenterStatus(components, center.status, density)
  end

  local function drawInductionCenter(source, surface, components, legacyLayout, density)
    local center = legacyLayout.tom.center
    drawCenterSummary(components, center.summary)
    drawWindowed(source, surface, center.reactor, function(bounds)
      api.drawInductionDiagram(bounds.x, bounds.y, bounds.w, bounds.h)
    end)
    drawCenterTemps(components, center.temps)
    drawCenterLaser(components, center.laser, density)
    drawCenterStatus(components, center.status, density)
  end

  local function renderLegacyView(view, legacyLayout)
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
    local design = TomDesign.build(width, height)
    local layout = TomLayout.compute(width, height, design, state.currentView)
    local components = TomComponents.build({
      writeAt = writeAt,
      fillArea = fillArea,
      shortText = shortText,
      design = design,
    })

    components.safeFill(1, 1, width, height, C.bg)

    if layout.tooSmall then
      local y = math.max(2, math.floor(height / 2))
      components.safeWrite(2, y - 1, "Display too small", C.bad, C.bg, math.max(4, width - 2), "center")
      components.safeWrite(2, y, "Need at least " .. tostring(layout.minW) .. "x" .. tostring(layout.minH), C.warn, C.bg, math.max(4, width - 2), "center")
      return layout
    end

    local legacyLayout = {
      mode = layout.legacy.mode,
      top = layout.legacy.top,
      bottom = layout.legacy.bottom,
      height = layout.legacy.height,
      width = layout.legacy.width,
      tooSmall = false,
      uiScale = design.scale,
      left = layout.legacy.left,
      center = layout.legacy.center,
      right = layout.legacy.right,
      stack = layout.stacked and true or nil,
      tom = {
        density = design.density,
        header = layout.header,
        footer = layout.footer,
        content = layout.content,
        left = layout.left,
        center = layout.center,
        right = layout.right,
        controls = layout.controls,
      },
    }

    drawHeaderAndFooter(components, layout)

    if state.choosingMonitor and type(api.drawMonitorSelection) == "function" then
      api.drawMonitorSelection(legacyLayout)
      drawHeaderAndFooter(components, layout)
      return layout
    end

    local view = tostring(state.currentView or "supervision")
    local renderedLegacy = false
    if view ~= "supervision" and view ~= "manual" and view ~= "induction" then
      renderedLegacy = renderLegacyView(view, legacyLayout)
    end

    if not renderedLegacy then
      local leftColumn = layout.legacy.left
      drawWindowed(source, surface, leftColumn, function(bounds)
        drawStatusColumn(components, bounds, design.density)
      end)

      if view == "induction" then
        drawInductionCenter(source, surface, components, legacyLayout, design.density)
      else
        drawReactorCenter(source, surface, components, legacyLayout, design.density)
      end

      drawControlColumn(components, legacyLayout)
    end

    drawHeaderAndFooter(components, layout)
    return layout
  end

  return {
    render = render,
  }
end

return M
