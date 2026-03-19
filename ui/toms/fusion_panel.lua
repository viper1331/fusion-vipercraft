local TomTheme = require("ui.toms.theme")
local TomLayout = require("ui.toms.layout")
local TomComponents = require("ui.toms.components")

local M = {}

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

local function splitVertical(bounds, weights, gap)
  local count = #weights
  local out = {}
  if count <= 0 then return out end

  gap = math.max(0, math.floor(tonumber(gap) or 0))
  local available = math.max(1, bounds.h - (gap * (count - 1)))
  local weightSum = 0
  for i = 1, count do
    weightSum = weightSum + math.max(0, tonumber(weights[i].weight) or 0)
  end
  if weightSum <= 0 then weightSum = count end

  local y = bounds.y
  local used = 0
  for i = 1, count do
    local h = math.floor((available * math.max(0, tonumber(weights[i].weight) or 1)) / weightSum)
    if h < 1 then h = 1 end
    if i == count then
      h = math.max(1, (bounds.y + bounds.h) - y)
    end
    out[weights[i].key] = rect(bounds.x, y, bounds.w, h)
    y = y + h + gap
    used = used + h
  end
  if used < available then
    local last = out[weights[count].key]
    out[weights[count].key] = rect(last.x, last.y, last.w, last.h + (available - used))
  end
  return out
end

function M.build(api)
  local state = assert(api.state, "state is required")
  local hw = assert(api.hw, "hw is required")
  local C = assert(api.C, "C is required")
  local log = type(api.log) == "table" and api.log or {}

  local function logWarn(message, meta)
    if type(log.warn) == "function" then
      log.warn(message, meta)
    end
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
    return tostring(value or "N/A")
  end

  local function formatEnergyTick(value)
    if type(api.formatEnergyPerTick) == "function" then
      return tostring(api.formatEnergyPerTick(value))
    end
    return tostring(value or "N/A")
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

  local function laserTone()
    local st = tostring(state.laserState or "ABSENT")
    if st == "READY" then return C.ok end
    if st == "CHARGING" then return C.warn end
    if st == "INSUFFICIENT" then return C.warn end
    if st == "ABSENT" then return C.bad end
    return C.dim
  end

  local function reactorVisualState()
    if not state.reactorPresent then
      return "warning"
    end
    if not state.reactorFormed then
      return "warning"
    end
    if state.ignition then
      return "active"
    end
    if state.laserReady and (#(state.ignitionBlockers or {}) == 0) then
      return "ready"
    end
    return "idle"
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
    }
  end

  local function buildHeaderInfo(theme)
    local warning = (type(state.safetyWarnings) == "table" and state.safetyWarnings[1]) or "NONE"
    local warningTone = warning == "NONE" and theme.palette.info or theme.palette.warning
    return {
      left = "FUSION SUPERVISOR",
      center = phaseText(),
      centerTone = phaseTone(),
      right = "INFO " .. asText(warning, "NONE"),
      rightTone = warningTone,
    }
  end

  local function buildFooterSegments(theme)
    local gridPct = state.energyKnown and string.format("%3.0f%%", asNumber(state.energyPct, 0)) or "N/A"
    local laserStatus = asText(state.laserStatusText or state.laserState, "ABS")
    return {
      { text = "ACT " .. asText(state.lastAction, "NONE"), tone = theme.palette.textMuted },
      { text = "VIEW " .. string.upper(asText(state.currentView, "SUP")), tone = theme.palette.info },
      { text = "PHASE " .. phaseText(), tone = phaseTone() },
      { text = "LAS " .. laserStatus, tone = laserTone() },
      { text = "GRID " .. gridPct, tone = theme.palette.energy },
      { text = "OUT " .. asText(hw.monitorName, "terminal"), tone = theme.palette.info },
    }
  end

  local function drawLeftColumn(ui, bounds, theme)
    ui.drawPanel(bounds, "REACTOR STATUS", {
      bg = theme.palette.panelBg,
      border = theme.palette.border,
      headerBg = theme.palette.panelBgSoft,
      headerText = theme.palette.textPrimary,
    })

    local rows = {
      { "State", phaseText(), phaseTone() },
      { "Core", state.reactorFormed and "FORMED" or "UNFORMED", state.reactorFormed and theme.palette.ok or theme.palette.warning },
      { "Injection", tostring(math.floor(asNumber(state.injectionRate, 0))) .. " mB/t", state.injectionWritable and theme.palette.info or theme.palette.textMuted },
      { "Plasma", formatTemperature(state.plasmaTemp, 1), theme.palette.warning },
      { "Struct", formatTemperature(state.caseTemp, 1), theme.palette.critical },
      { "Laser", asText(state.laserStatusText or state.laserState, "ABS"), laserTone() },
      { "L. Energy", formatEnergy(state.laserEnergy), theme.palette.energy },
      { "L. Need", formatEnergy(state.laserThresholdRaw), theme.palette.warning },
      { "Fuel", asText(type(api.getRuntimeFuelMode) == "function" and api.getRuntimeFuelMode() or "N/A", "N/A"), theme.palette.info },
      { "Flow", string.format("%.1f mB/t", asNumber(state.fuelFlowMbT, 0)), theme.palette.info },
      { "Steam", string.format("%.1f mB/t", asNumber(state.steamProduction, 0)), theme.palette.info },
      { "Hohlraum", state.hohlraumPresent and "PRESENT" or "MISSING", state.hohlraumPresent and theme.palette.ok or theme.palette.warning },
    }

    local capacity = math.max(4, bounds.h - 5)
    local rowsToShow = rows
    if theme.density == "small" then
      rowsToShow = { rows[1], rows[2], rows[3], rows[4], rows[5], rows[6], rows[12] }
    elseif theme.density == "medium" then
      rowsToShow = { rows[1], rows[2], rows[3], rows[4], rows[5], rows[6], rows[7], rows[9], rows[12] }
    end

    for i = 1, math.min(#rowsToShow, capacity) do
      local entry = rowsToShow[i]
      ui.drawLabelValue(bounds, i - 1, entry[1], entry[2], entry[3], theme.palette.textMuted)
    end

    local warningTop = math.min(capacity - 1, #rowsToShow + 1)
    if warningTop >= 1 then
      ui.drawSectionTitle(bounds, warningTop, "WARNINGS", theme.palette.warning)
      local warnings = type(state.safetyWarnings) == "table" and state.safetyWarnings or {}
      local warnSlots = math.max(1, capacity - warningTop - 1)
      for i = 1, math.min(#warnings, warnSlots) do
        ui.drawLabelValue(bounds, warningTop + i, "-", warnings[i], theme.palette.warning, theme.palette.textMuted)
      end
    end
  end

  local function drawCenterColumn(ui, bounds, theme)
    ui.drawPanel(bounds, "FUSION CHAMBER", {
      bg = theme.palette.panelBg,
      border = theme.palette.borderStrong,
      headerBg = theme.palette.panelBgSoft,
      headerText = theme.palette.textPrimary,
    })

    local content = inset(bounds, 1, 1, 1, 1)
    local sections = splitVertical(content, {
      { key = "headline", weight = 2 },
      { key = "core", weight = 7 },
      { key = "metrics", weight = 3 },
    }, theme.spacing.sectionGap)

    ui.drawStatusBadge(sections.headline, 0, state.reactorFormed and "CORE FORMED" or "CORE UNFORMED", state.reactorFormed and theme.palette.ok or theme.palette.warning)
    ui.drawLabelValue(sections.headline, 1, "Injection", tostring(math.floor(asNumber(state.injectionRate, 0))) .. " mB/t", theme.palette.info, theme.palette.textMuted)

    ui.drawReactorCore(sections.core, {
      tick = state.tick or 0,
      reactorState = reactorVisualState(),
      laserActive = state.laserLineOn == true,
      laserCharging = state.laserChargeOn == true,
      tOpen = state.tOpen == true,
      dtOpen = state.dtOpen == true,
      dOpen = state.dOpen == true,
    })

    ui.drawPanel(sections.metrics, "RUNTIME METRICS", {
      bg = theme.palette.panelBg,
      border = theme.palette.border,
      headerBg = theme.palette.panelBgSoft,
      headerText = theme.palette.textPrimary,
    })

    local laserRatio = clamp(asNumber(state.laserPct, 0) / 100, 0, 1)
    ui.drawHorizontalBar(
      sections.metrics,
      0,
      laserRatio,
      theme.palette.ok,
      theme.palette.panelBgRaised,
      "LAS " .. string.format("%3.0f%%", asNumber(state.laserPct, 0))
    )

    local energyRatio = clamp(asNumber(state.energyPct, 0) / 100, 0, 1)
    ui.drawHorizontalBar(
      sections.metrics,
      1,
      energyRatio,
      theme.palette.energy,
      theme.palette.panelBgRaised,
      "GRID " .. (state.energyKnown and string.format("%3.0f%%", asNumber(state.energyPct, 0)) or "N/A")
    )

    if theme.density ~= "small" then
      ui.drawLabelValue(sections.metrics, 3, "Plasma", formatTemperature(state.plasmaTemp, 2), theme.palette.warning, theme.palette.textMuted)
      ui.drawLabelValue(sections.metrics, 4, "Struct", formatTemperature(state.caseTemp, 2), theme.palette.critical, theme.palette.textMuted)
      ui.drawLabelValue(sections.metrics, 5, "Production", formatEnergyTick(state.passiveGeneration), theme.palette.info, theme.palette.textMuted)
    else
      ui.drawLabelValue(sections.metrics, 3, "Plasma", formatTemperature(state.plasmaTemp, 1), theme.palette.warning, theme.palette.textMuted)
    end
  end

  local function drawRightColumn(ui, layout, legacyLayout, theme)
    local col = layout.columns.right
    ui.drawPanel(col, "CONTROL COLUMN", {
      bg = theme.palette.panelBg,
      border = theme.palette.border,
      headerBg = theme.palette.panelBgSoft,
      headerText = theme.palette.textPrimary,
    })

    local navBounds = layout.controls.navBounds
    local actionBounds = layout.controls.actionBounds
    local ioBounds = layout.controls.ioBounds

    ui.drawPanel(navBounds, "NAV", {
      bg = theme.palette.panelBg,
      border = theme.palette.border,
      headerBg = theme.palette.panelBgSoft,
      headerText = theme.palette.textPrimary,
    })
    ui.drawPanel(actionBounds, "ACTIONS", {
      bg = theme.palette.panelBg,
      border = theme.palette.border,
      headerBg = theme.palette.panelBgSoft,
      headerText = theme.palette.textPrimary,
    })
    ui.drawPanel(ioBounds, "REAL I/O", {
      bg = theme.palette.panelBg,
      border = theme.palette.border,
      headerBg = theme.palette.panelBgSoft,
      headerText = theme.palette.textPrimary,
    })

    local buttonBounds = inset(layout.controls.buttonBounds, 0, 0, 0, 0)
    state.controlBounds = {
      x = buttonBounds.x,
      y = buttonBounds.y,
      w = buttonBounds.w,
      h = buttonBounds.h,
    }

    if type(api.buildButtons) == "function" and type(api.drawButtons) == "function" then
      api.buildButtons(legacyLayout)
      api.drawButtons(api.getCurrentInputSource and api.getCurrentInputSource() or "monitor")
    end

    if type(api.drawIoPanel) == "function" and state.currentView ~= "setup" then
      local ioInner = inset(ioBounds, 1, 1, 1, 1)
      api.drawIoPanel(ioInner)
    end
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
    local layout = TomLayout.compute(width, height, theme, state.currentView)

    local rootUi = TomComponents.new({
      target = term.current(),
      width = width,
      height = height,
      theme = theme,
    })
    rootUi.safeFill(1, 1, width, height, theme.palette.bgRoot)

    if layout.tooSmall then
      local y = math.max(2, math.floor(height / 2))
      rootUi.safeWrite(2, y - 1, "Display too small", theme.palette.critical, theme.palette.bgRoot, math.max(4, width - 2), "center")
      rootUi.safeWrite(
        2,
        y,
        "Need at least " .. tostring(layout.minW) .. "x" .. tostring(layout.minH),
        theme.palette.warning,
        theme.palette.bgRoot,
        math.max(4, width - 2),
        "center"
      )
      return layout
    end

    local legacyLayout = buildLegacyLayout(layout, theme)
    local headerInfo = buildHeaderInfo(theme)
    rootUi.drawHeader(layout.header, headerInfo.left, headerInfo.center, headerInfo.right, headerInfo.centerTone, headerInfo.rightTone)
    rootUi.drawFooter(layout.footer, buildFooterSegments(theme))

    if state.choosingMonitor and type(api.drawMonitorSelection) == "function" then
      api.drawMonitorSelection(legacyLayout)
      rootUi.drawHeader(layout.header, headerInfo.left, headerInfo.center, headerInfo.right, headerInfo.centerTone, headerInfo.rightTone)
      rootUi.drawFooter(layout.footer, buildFooterSegments(theme))
      return layout
    end

    local view = tostring(state.currentView or "supervision")
    if view ~= "supervision" and view ~= "manual" and view ~= "induction" then
      if drawLegacyView(view, legacyLayout) then
        rootUi.drawHeader(layout.header, headerInfo.left, headerInfo.center, headerInfo.right, headerInfo.centerTone, headerInfo.rightTone)
        rootUi.drawFooter(layout.footer, buildFooterSegments(theme))
        return layout
      end
    end

    local useWindows = source == "monitor"
      and type(surface) == "table"
      and type(surface.createWindow) == "function"
      and theme.density ~= "small"

    local function drawArea(bounds, drawFn)
      if useWindows and bounds.w >= 12 and bounds.h >= 6 then
        local okWin, win = pcall(surface.createWindow, bounds.x, bounds.y, bounds.w, bounds.h)
        if okWin and type(win) == "table" then
          local prev = term.current()
          term.redirect(win)
          local localUi = TomComponents.new({
            target = win,
            width = bounds.w,
            height = bounds.h,
            theme = theme,
          })
          local okDraw, errDraw = pcall(drawFn, localUi, rect(1, 1, bounds.w, bounds.h), true)
          term.redirect(prev)
          if not okDraw then
            logWarn("Tom area draw failed", { err = tostring(errDraw) })
          end
          return
        end
      end
      drawFn(rootUi, bounds, false)
    end

    drawArea(layout.columns.left, function(ui, area)
      drawLeftColumn(ui, area, theme)
    end)

    drawArea(layout.columns.center, function(ui, area)
      drawCenterColumn(ui, area, theme)
    end)

    drawRightColumn(rootUi, layout, legacyLayout, theme)

    rootUi.drawHeader(layout.header, headerInfo.left, headerInfo.center, headerInfo.right, headerInfo.centerTone, headerInfo.rightTone)
    rootUi.drawFooter(layout.footer, buildFooterSegments(theme))
    return layout
  end

  return {
    render = render,
  }
end

return M
