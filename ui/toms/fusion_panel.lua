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
  local log = type(api.log) == "table" and api.log or {}

  local function logWarn(message, meta)
    if type(log.warn) == "function" then
      log.warn(message, meta)
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

    return {
      phase = phaseText(),
      phaseTone = phaseTone(),
      laserTone = laserTone(theme),
      warnings = warnings,
      events = events,
      blockers = blockers,
      reactorState = reactorVisualState(),
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
      tOpen = state.tOpen == true,
      dtOpen = state.dtOpen == true,
      dOpen = state.dOpen == true,
      hohlraum = state.hohlraumPresent and "PRESENT" or "MISSING",
    }
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

  local function drawStatusColumn(ui, layout, theme, model)
    local statusPanel = layout.left.status
    local safetyPanel = layout.left.safety
    local eventsPanel = layout.left.events

    ui.drawPanel(statusPanel, "FUSION SUPERVISOR", {
      bg = theme.palette.panelBg,
      border = theme.palette.border,
      headerBg = theme.palette.panelHeader,
      headerText = theme.palette.textPrimary,
    })

    local statusRows = {
      { "Phase", model.phase, model.phaseTone },
      { "State", state.ignition and "RUNNING" or "BLOCKED", state.ignition and theme.palette.ok or theme.palette.warning },
      { "Core", state.reactorFormed and "FORMED" or "UNFORMED", state.reactorFormed and theme.palette.ok or theme.palette.warning },
      { "Inject", tostring(model.injectionRate) .. " mB/t", state.injectionWritable and theme.palette.info or theme.palette.textMuted },
      { "Fuel", model.fuelMode, theme.palette.info },
      { "Flow", model.fuelFlow, theme.palette.info },
      { "Hohlraum", model.hohlraum, state.hohlraumPresent and theme.palette.ok or theme.palette.warning },
    }
    local cap = math.max(2, statusPanel.h - 4)
    for i = 1, math.min(cap, #statusRows) do
      local row = statusRows[i]
      ui.drawLabelValue(statusPanel, i - 1, row[1], row[2], row[3], theme.palette.textMuted)
    end

    ui.drawPanel(safetyPanel, "IGNITION CHECK", {
      bg = theme.palette.panelBg,
      border = theme.palette.warning,
      headerBg = theme.palette.panelHeaderAlt,
      headerText = theme.palette.textPrimary,
    })
    local safetyRows = {}
    if #model.blockers == 0 then
      safetyRows[1] = { "[OK]", "No blocker", theme.palette.ok }
    else
      for i = 1, #model.blockers do
        safetyRows[#safetyRows + 1] = { "[NO]", model.blockers[i], theme.palette.critical }
      end
    end
    if #model.warnings > 0 then
      for i = 1, #model.warnings do
        safetyRows[#safetyRows + 1] = { "-", model.warnings[i], theme.palette.warning }
      end
    end
    local safetyCap = math.max(1, safetyPanel.h - 4)
    for i = 1, math.min(safetyCap, #safetyRows) do
      local row = safetyRows[i]
      ui.drawLabelValue(safetyPanel, i - 1, row[1], row[2], row[3], theme.palette.textMuted)
    end

    ui.drawPanel(eventsPanel, "EVENT LOG", {
      bg = theme.palette.panelBg,
      border = theme.palette.border,
      headerBg = theme.palette.panelHeaderAlt,
      headerText = theme.palette.textPrimary,
    })
    local slots = math.max(1, eventsPanel.h - 4)
    for i = 1, math.min(slots, #model.events) do
      ui.drawLabelValue(eventsPanel, i - 1, tostring(i), asText(model.events[i], "..."), theme.palette.info, theme.palette.textMuted)
    end
    if #model.events == 0 then
      ui.drawLabelValue(eventsPanel, 0, "-", "No runtime event", theme.palette.textMuted, theme.palette.textMuted)
    end
  end

  local function drawCenterColumn(ui, layout, theme, model)
    local headlinePanel = layout.center.headline
    local laserPanel = layout.center.laser
    local corePanel = layout.center.core
    local runtimePanel = layout.center.runtime

    ui.drawPanel(headlinePanel, "FUSION CHAMBER", {
      bg = theme.palette.panelBg,
      border = theme.palette.borderStrong,
      headerBg = theme.palette.panelHeader,
      headerText = theme.palette.textPrimary,
    })
    ui.drawStatusBadge(headlinePanel, 0, state.reactorFormed and "CORE FORMED" or "CORE UNFORMED", state.reactorFormed and theme.palette.ok or theme.palette.warning)
    ui.drawLabelValue(headlinePanel, 2, "Plasma", model.plasmaTemp, theme.palette.warning, theme.palette.textMuted)
    ui.drawLabelValue(headlinePanel, 3, "Struct", model.caseTemp, theme.palette.critical, theme.palette.textMuted)

    ui.drawPanel(laserPanel, "LASER ARRAY", {
      bg = theme.palette.panelBg,
      border = theme.palette.ok,
      headerBg = theme.palette.panelHeaderAlt,
      headerText = theme.palette.textPrimary,
    })
    local laserInner = inset(laserPanel, 1, 1, 1, 1)
    ui.drawLaserStack(laserInner, {
      count = model.laserCount,
      activeCount = model.laserActiveCount,
      pct = model.laserPct,
      state = model.laserState,
      tone = model.laserTone,
    })

    ui.drawPanel(corePanel, "REACTOR CORE", {
      bg = theme.palette.panelBg,
      border = theme.palette.borderStrong,
      headerBg = theme.palette.panelHeaderAlt,
      headerText = theme.palette.textPrimary,
    })
    local coreInner = inset(corePanel, 1, 1, 1, 1)
    ui.drawReactorCore(coreInner, {
      tick = state.tick or 0,
      reactorState = model.reactorState,
      laserActive = model.laserActive,
      laserCharging = model.laserCharging,
      laserLabel = "LAS " .. tostring(model.laserPct) .. "%",
      tOpen = model.tOpen,
      dtOpen = model.dtOpen,
      dOpen = model.dOpen,
    })

    ui.drawPanel(runtimePanel, "RUNTIME METRICS", {
      bg = theme.palette.panelBg,
      border = theme.palette.border,
      headerBg = theme.palette.panelHeaderAlt,
      headerText = theme.palette.textPrimary,
    })
    local laserRatio = clamp(asNumber(state.laserPct, 0) / 100, 0, 1)
    local gridRatio = clamp(asNumber(state.energyPct, 0) / 100, 0, 1)
    ui.drawHorizontalBar(runtimePanel, 0, laserRatio, theme.palette.ok, theme.palette.panelBgRaised, "LAS " .. tostring(model.laserPct) .. "%")
    ui.drawHorizontalBar(runtimePanel, 1, gridRatio, theme.palette.energy, theme.palette.panelBgRaised, "GRID " .. (model.energyKnown and string.format("%3.0f%%", model.energyPct) or "N/A"))
    ui.drawLabelValue(runtimePanel, 3, "Laser E", model.laserEnergy, theme.palette.info, theme.palette.textMuted)
    ui.drawLabelValue(runtimePanel, 4, "Laser Max", model.laserMax, theme.palette.info, theme.palette.textMuted)
    ui.drawLabelValue(runtimePanel, 5, "Laser Need", model.laserNeed, theme.palette.warning, theme.palette.textMuted)
    if theme.density ~= "small" then
      ui.drawLabelValue(runtimePanel, 6, "Production", model.passiveGeneration, theme.palette.info, theme.palette.textMuted)
      ui.drawLabelValue(runtimePanel, 7, "Steam", model.steamProduction, theme.palette.info, theme.palette.textMuted)
    end
  end

  local function drawRightColumn(ui, layout, theme, legacyLayout, model)
    local navPanel = layout.right.nav
    local actionPanel = layout.right.actions
    local ioPanel = layout.right.io

    ui.drawPanel(navPanel, "CONTROL", {
      bg = theme.palette.panelBg,
      border = theme.palette.border,
      headerBg = theme.palette.panelHeader,
      headerText = theme.palette.textPrimary,
    })
    ui.drawStatusBadge(navPanel, 0, "SUP", theme.palette.info)
    ui.drawLabelValue(navPanel, 2, "Master", state.autoMaster and "AUTO" or "MANUAL", state.autoMaster and theme.palette.ok or theme.palette.warning, theme.palette.textMuted)
    ui.drawLabelValue(navPanel, 3, "Fuel", state.fusionAuto and "AUTO" or "MANUAL", state.fusionAuto and theme.palette.ok or theme.palette.warning, theme.palette.textMuted)
    ui.drawLabelValue(navPanel, 4, "Charge", state.chargeAuto and "AUTO" or "MANUAL", state.chargeAuto and theme.palette.ok or theme.palette.warning, theme.palette.textMuted)

    ui.drawPanel(actionPanel, "ACTIONS", {
      bg = theme.palette.panelBg,
      border = theme.palette.border,
      headerBg = theme.palette.panelHeaderAlt,
      headerText = theme.palette.textPrimary,
    })
    ui.drawLabelValue(actionPanel, 0, "Control", (api.CFG and api.CFG.allowControl) and "ENABLED" or "LOCKED", (api.CFG and api.CFG.allowControl) and theme.palette.warning or theme.palette.ok, theme.palette.textMuted)
    ui.drawLabelValue(actionPanel, 1, "Injection", tostring(model.injectionRate) .. " mB/t", theme.palette.info, theme.palette.textMuted)
    ui.drawLabelValue(actionPanel, 2, "Laser", model.laserState, model.laserTone, theme.palette.textMuted)

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

    ui.drawPanel(ioPanel, "REAL I/O", {
      bg = theme.palette.panelBg,
      border = theme.palette.border,
      headerBg = theme.palette.panelHeaderAlt,
      headerText = theme.palette.textPrimary,
    })
    if type(api.drawIoPanel) == "function" and state.currentView ~= "setup" then
      local ioInner = inset(ioPanel, 1, 1, 1, 1)
      api.drawIoPanel(ioInner)
    else
      ui.drawLabelValue(ioPanel, 0, "Monitor", model.monitorName, theme.palette.info, theme.palette.textMuted)
      ui.drawLabelValue(ioPanel, 1, "Output", asText(api.getCurrentInputSource and api.getCurrentInputSource() or "monitor", "monitor"), theme.palette.info, theme.palette.textMuted)
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
    rootUi.drawBackdrop(layout.root or rect(1, 1, width, height))

    if layout.tooSmall then
      local y = math.max(2, math.floor(height / 2))
      rootUi.safeText(2, y - 1, "Display too small", theme.palette.critical, theme.palette.bgRoot, math.max(4, width - 2), "center")
      rootUi.safeText(2, y, "Need at least " .. tostring(layout.minW) .. "x" .. tostring(layout.minH), theme.palette.warning, theme.palette.bgRoot, math.max(4, width - 2), "center")
      return layout
    end

    local model = runtimeModel(theme)
    local warning = model.warnings[1] or "NONE"
    local warningTone = warning == "NONE" and theme.palette.info or theme.palette.warning
    local headerLeft = "FUSION SUPERVISOR"
    local headerCenter = model.phase
    local headerRight = "INFO " .. asText(warning, "NONE")
    local footerSegments = {
      { text = "ACT " .. model.lastAction, tone = theme.palette.textMuted },
      { text = "VIEW " .. string.upper(asText(state.currentView, "SUP")), tone = theme.palette.info },
      { text = "PHASE " .. model.phase, tone = model.phaseTone },
      { text = "LAS " .. model.laserState, tone = model.laserTone },
      { text = "GRID " .. (model.energyKnown and string.format("%3.0f%%", model.energyPct) or "N/A"), tone = theme.palette.energy },
      { text = "OUT " .. model.monitorName, tone = theme.palette.info },
    }
    local legacyLayout = buildLegacyLayout(layout, theme)

    rootUi.drawHeader(layout.header, headerLeft, headerCenter, headerRight, model.phaseTone, warningTone)
    rootUi.drawFooter(layout.footer, footerSegments)

    if state.choosingMonitor and type(api.drawMonitorSelection) == "function" then
      api.drawMonitorSelection(legacyLayout)
      rootUi.drawHeader(layout.header, headerLeft, headerCenter, headerRight, model.phaseTone, warningTone)
      rootUi.drawFooter(layout.footer, footerSegments)
      return layout
    end

    local view = tostring(state.currentView or "supervision")
    if view ~= "supervision" and view ~= "manual" and view ~= "induction" then
      if drawLegacyView(view, legacyLayout) then
        rootUi.drawHeader(layout.header, headerLeft, headerCenter, headerRight, model.phaseTone, warningTone)
        rootUi.drawFooter(layout.footer, footerSegments)
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
          { key = "status", weight = 4 },
          { key = "safety", weight = 3 },
          { key = "events", weight = 4 },
        }, theme.spacing.sectionGap),
      }
      drawStatusColumn(ui, localLayout, theme, model)
    end)

    drawArea(layout.columns.center, function(ui, localBounds)
      local localLayout = {
        center = splitVertical(inset(localBounds, 1, 1, 1, 1), {
          { key = "headline", weight = 2 },
          { key = "laser", weight = 3 },
          { key = "core", weight = 8 },
          { key = "runtime", weight = 4 },
        }, theme.spacing.sectionGap),
      }
      drawCenterColumn(ui, localLayout, theme, model)
    end)

    drawRightColumn(rootUi, layout, theme, legacyLayout, model)
    rootUi.drawHeader(layout.header, headerLeft, headerCenter, headerRight, model.phaseTone, warningTone)
    rootUi.drawFooter(layout.footer, footerSegments)
    return layout
  end

  return {
    render = render,
  }
end

return M
