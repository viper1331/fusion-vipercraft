local M = {}

local function defaultAsText(value, fallback)
  local out = tostring(value or "")
  if out == "" then
    return tostring(fallback or "N/A")
  end
  return out
end

function M.build(deps)
  deps = type(deps) == "table" and deps or {}
  local state = assert(deps.state, "state is required")
  local hw = assert(deps.hw, "hw is required")
  local CFG = type(deps.CFG) == "table" and deps.CFG or {}
  local api = type(deps.api) == "table" and deps.api or {}
  local inset = assert(deps.inset, "inset is required")
  local asText = type(deps.asText) == "function" and deps.asText or defaultAsText
  local assets = type(deps.assets) == "table" and deps.assets or {}

  local function drawReactorPanel(ui, bounds, theme, model)
    ui.drawPanel(bounds, "REACTOR", {
      bg = theme.palette.panelBg,
      border = theme.palette.borderStrong,
      headerBg = theme.palette.panelHeader,
      headerText = theme.palette.textOnDark or theme.palette.textPrimary,
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
      headerText = theme.palette.textOnDark or theme.palette.textPrimary,
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
      headerText = theme.palette.textOnDark or theme.palette.textPrimary,
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
      headerText = theme.palette.textOnDark or theme.palette.textPrimary,
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

  local function drawIoSummaryPanel(ui, bounds, theme, model)
    ui.drawPanel(bounds, "REAL I/O", {
      bg = theme.palette.panelBg,
      border = theme.palette.border,
      headerBg = theme.palette.panelHeaderAlt,
      headerText = theme.palette.textOnDark or theme.palette.textPrimary,
    })
    ui.drawLabelValue(bounds, 0, "LAS CHG", model.laserCharging and "ON" or "OFF", model.laserCharging and theme.palette.ok or theme.palette.textMuted, theme.palette.textMuted)
    ui.drawLabelValue(bounds, 1, "LAS PULSE", model.laserActive and "ON" or "OFF", model.laserActive and theme.palette.warning or theme.palette.textMuted, theme.palette.textMuted)
    ui.drawLabelValue(bounds, 2, "T LOCK", model.tOpen and "OPEN" or "CLOSED", model.tOpen and theme.palette.ok or theme.palette.warning, theme.palette.textMuted)
    ui.drawLabelValue(bounds, 3, "DT LOCK", model.dtOpen and "OPEN" or "CLOSED", model.dtOpen and theme.palette.ok or theme.palette.warning, theme.palette.textMuted)
    ui.drawLabelValue(bounds, 4, "D LOCK", model.dOpen and "OPEN" or "CLOSED", model.dOpen and theme.palette.ok or theme.palette.warning, theme.palette.textMuted)
    ui.drawLabelValue(bounds, 5, "Backend", model.backendName, theme.palette.info, theme.palette.textMuted)
  end

  local function drawCorePanel(ui, bounds, theme, model, title)
    ui.drawPanel(bounds, title or "FUSION CHAMBER", {
      bg = theme.palette.panelBg,
      border = theme.palette.borderStrong,
      headerBg = theme.palette.panelHeaderAlt,
      headerText = theme.palette.textOnDark or theme.palette.textPrimary,
    })
    local coreInner = inset(bounds, 1, 1, 1, 1)
    local anchors = type(assets.getAnchors) == "function" and assets.getAnchors("reactor", coreInner.x, coreInner.y, coreInner.w, coreInner.h) or nil
    local moduleAspect = 6.75
    if type(assets.getSpriteAspect) == "function" then
      moduleAspect = tonumber(assets.getSpriteAspect("laser_module", 6.75)) or 6.75
    elseif type(assets.getSpriteSize) == "function" then
      local laserSpriteW, laserSpriteH = assets.getSpriteSize("laser_module")
      if tonumber(laserSpriteW) and tonumber(laserSpriteH) and tonumber(laserSpriteH) > 0 then
        moduleAspect = tonumber(laserSpriteW) / tonumber(laserSpriteH)
      end
    end
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
      laserCount = model.laserCount,
      laserModuleAspect = moduleAspect,
      reactorAnchors = anchors,
    })
  end

  local function drawInfoPanel(ui, bounds, theme, title, rows, panelOpts)
    local opts = type(panelOpts) == "table" and panelOpts or {}
    ui.drawPanel(bounds, title or "PAGE OVERVIEW", {
      bg = opts.bg or theme.palette.panelBg,
      border = opts.border or theme.palette.borderStrong,
      headerBg = opts.headerBg or theme.palette.panelHeaderAlt,
      headerText = opts.headerText or theme.palette.textOnDark or theme.palette.textPrimary,
      shadow = opts.shadow,
    })

    local maxRows = math.max(0, (tonumber(bounds.h) or 0) - 4)
    local rowIndex = 0
    local entries = type(rows) == "table" and rows or {}
    for i = 1, #entries do
      if rowIndex >= maxRows then
        break
      end
      local entry = entries[i]
      if type(entry) == "table" and entry.kind == "section" then
        ui.drawSectionTitle(bounds, rowIndex, tostring(entry.text or ""), entry.tone or theme.palette.info)
      else
        local label = type(entry) == "table" and entry.label or ""
        local value = type(entry) == "table" and entry.value or ""
        local valueTone = type(entry) == "table" and entry.valueTone or theme.palette.textPrimary
        local labelTone = type(entry) == "table" and entry.labelTone or theme.palette.textMuted
        ui.drawLabelValue(bounds, rowIndex, tostring(label), tostring(value), valueTone, labelTone)
      end
      rowIndex = rowIndex + 1
    end
  end

  return {
    asText = asText,
    drawReactorPanel = drawReactorPanel,
    drawTemperaturePanel = drawTemperaturePanel,
    drawLaserPanel = drawLaserPanel,
    drawStatusPanel = drawStatusPanel,
    drawIoSummaryPanel = drawIoSummaryPanel,
    drawCorePanel = drawCorePanel,
    drawInfoPanel = drawInfoPanel,
    state = state,
    hw = hw,
    CFG = CFG,
    api = api,
  }
end

return M

