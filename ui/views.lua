local UIComponents = require("ui.components")

local M = {}


function M.buildContext(base)
  return {
    C = base.C,
    state = base.state,
    hw = base.hw,
    CFG = base.CFG,
    fs = base.fs,
    UPDATE_ENABLED = base.UPDATE_ENABLED,
    UPDATE_TEMP_DIR = base.UPDATE_TEMP_DIR,
    UPDATE_MISSING_BACKUP_SUFFIX = base.UPDATE_MISSING_BACKUP_SUFFIX,
    drawBox = base.drawBox,
    writeAt = base.writeAt,
    drawKeyValue = base.drawKeyValue,
    drawBadge = base.drawBadge,
    shortText = base.shortText,
    clamp = base.clamp,
    fmt = base.fmt,
    formatTemperature = base.formatTemperature,
    formatEnergy = base.formatEnergy or base.formatMJ,
    formatEnergyPerTick = base.formatEnergyPerTick or base.formatMJ,
    formatMJ = base.formatMJ or base.formatEnergy,
    yesno = base.yesno,
    reactorPhase = base.reactorPhase,
    phaseColor = base.phaseColor,
    getRuntimeFuelMode = base.getRuntimeFuelMode,
    isRuntimeFuelOk = base.isRuntimeFuelOk,
    statusColor = base.statusColor,
    drawHeader = base.drawHeader,
    drawFooter = base.drawFooter,
    buildButtons = base.buildButtons,
    drawButtons = base.drawButtons,
    getCurrentInputSource = base.getCurrentInputSource,
    drawControlPanel = base.drawControlPanel,
    drawReactorDiagram = base.drawReactorDiagram,
    drawInductionDiagram = base.drawInductionDiagram,
    inductionStatus = base.inductionStatus,
    hasAnyRollbackBackup = base.hasAnyRollbackBackup,
    rollbackTargetList = base.rollbackTargetList,
    getSetupStatusRows = base.getSetupStatusRows,
  }
end

function M.resolveViewName(currentView)
  if currentView == "diagnostic" then return "DIAG" end
  if currentView == "manual" then return "MAN" end
  if currentView == "induction" then return "IND" end
  if currentView == "update" then return "UPDATE" end
  if currentView == "config" then return "CFG" end
  if currentView == "setup" then return "SETUP" end
  return "SUP"
end

local function panelInner(panel, padX, padY)
  padX = padX or 2
  padY = padY or 1
  return {
    x = panel.x + padX,
    y = panel.y + padY,
    w = math.max(1, panel.w - (padX * 2)),
    h = math.max(1, panel.h - (padY * 2)),
  }
end

local function splitVertical(top, bottom, specs, gap)
  gap = gap or 1
  local count = #specs
  if count == 0 then return {} end
  local total = bottom - top + 1
  if total <= 0 then return {} end

  local gapTotal = gap * math.max(0, count - 1)
  local usable = math.max(count, total - gapTotal)
  local mins = {}
  local heights = {}
  local minSum = 0
  local weightSum = 0
  for i, spec in ipairs(specs) do
    local m = math.max(1, math.floor(tonumber(spec.min) or 1))
    mins[i] = m
    heights[i] = m
    minSum = minSum + m
    weightSum = weightSum + math.max(0, tonumber(spec.weight) or 0)
  end

  if minSum > usable then
    local overflow = minSum - usable
    for i = count, 1, -1 do
      if overflow <= 0 then break end
      local cut = math.min(overflow, math.max(0, heights[i] - 1))
      heights[i] = heights[i] - cut
      overflow = overflow - cut
    end
  else
    local extra = usable - minSum
    if extra > 0 then
      if weightSum <= 0 then weightSum = count end
      for i = 1, count do
        local weight = math.max(0, tonumber(specs[i].weight) or 0)
        if weightSum == count and weight == 0 then weight = 1 end
        if weight > 0 then
          local add = math.floor((extra * weight) / weightSum)
          heights[i] = heights[i] + add
        end
      end
      local used = 0
      for i = 1, count do used = used + heights[i] end
      local rem = usable - used
      local idx = 1
      while rem > 0 do
        heights[idx] = heights[idx] + 1
        rem = rem - 1
        idx = (idx % count) + 1
      end
    end
  end

  local out = {}
  local y = top
  for i = 1, count do
    out[i] = { y = y, h = heights[i] }
    y = y + heights[i] + gap
  end
  return out
end

function M.drawMonitorSelection(ctx, layout)
  local C = ctx.C
  local state = ctx.state

  term.setBackgroundColor(C.bg)
  term.setTextColor(C.text)
  term.clear()
  ctx.drawHeader("FUSION SUPERVISOR", "MONITOR LINK")

  local boxW = ctx.clamp(layout.width - 6, 26, 60)
  local boxH = ctx.clamp(layout.height - 3, 10, layout.height)
  local x = math.floor((layout.width - boxW) / 2) + 1
  local y = layout.top + 1

  ctx.drawBox(x, y, boxW, boxH, "MONITOR SELECTION", C.border)
  local innerW = boxW - 4
  ctx.writeAt(x + 2, y + 1, ctx.shortText("Choisissez une sortie d affichage", innerW), C.dim, C.panelDark)
  ctx.writeAt(x + 2, y + 2, ctx.shortText("IDX  NOM                      TAILLE", innerW), C.info, C.panelDark)

  local monitors = type(state.monitorList) == "table" and state.monitorList or {}
  local maxRows = math.max(1, math.floor((boxH - 6) / 3))
  local visible = math.min(#monitors, maxRows, 9)
  for i = 1, visible do
    local yy = y + 3 + (i - 1) * 3
    local m = monitors[i]
    if m and yy + 1 <= y + boxH - 2 then
      local row = string.format("[%d]  %-22s %3dx%-3d", i, ctx.shortText(m.name, 22), m.w or 0, m.h or 0)
      ctx.writeAt(x + 2, yy, ctx.shortText(row, innerW), C.text, C.panelDark)
      ctx.writeAt(x + 2, yy + 1, ctx.shortText("TAP / TOUCHE " .. i .. " pour selectionner", innerW), C.dim, C.panelDark)
    end
  end
  if visible == 0 and y + 4 <= y + boxH - 2 then
    ctx.writeAt(x + 2, y + 4, ctx.shortText("Aucun monitor detecte", innerW), C.warn, C.panelDark)
  end

  ctx.buildButtons(layout)
  ctx.drawButtons(ctx.getCurrentInputSource())
  ctx.drawFooter(layout)
end

function M.drawSupervisionView(ctx, layout)
  UIComponents.drawStatusPanel(ctx, layout.left)
  if layout.mode == "compact" and not layout.center then
    ctx.drawControlPanel(layout.right, layout)
    return
  end

  if layout.center then
    ctx.drawReactorDiagram(layout.center.x, layout.center.y, layout.center.w, layout.center.h)
  end
  ctx.drawControlPanel(layout.right, layout)
end

function M.drawManualView(ctx, layout)
  if layout.center then
    ctx.drawReactorDiagram(layout.center.x, layout.center.y, layout.center.w, layout.center.h)
  end
  UIComponents.drawStatusPanel(ctx, layout.left)
  ctx.drawControlPanel(layout.right or layout.left, layout)
end

function M.drawDiagnosticView(ctx, layout)
  local C = ctx.C
  local hw = ctx.hw
  local CFG = ctx.CFG

  local left = layout.left
  local center = layout.center
  UIComponents.drawStatusPanel(ctx, left)
  if not center then
    ctx.drawControlPanel(layout.right, layout)
    return
  end

  ctx.drawBox(center.x, center.y, center.w, center.h, "SYSTEM DIAGNOSTICS", C.border)
  local x = center.x + 2
  local y = center.y + 1
  local maxY = center.y + center.h - 2
  ctx.writeAt(x, y, "RESOLVED DEVICES", C.info, C.panelDark)

  local function relayRef(actionName)
    local action = CFG.actions and CFG.actions[actionName] or nil
    local relayName = type(action) == "table" and action.relay or nil
    local relaySide = type(action) == "table" and action.side or nil
    if type(relayName) ~= "string" or relayName == "" then
      return "UNBOUND", false
    end
    local side = (type(relaySide) == "string" and relaySide ~= "") and relaySide or "top"
    return relayName .. "." .. side, hw.relays[relayName] ~= nil
  end

  local lasRef, lasOk = relayRef("laser_charge")
  local tRef, tOk = relayRef("tritium")
  local dRef, dOk = relayRef("deuterium")

  local rows = {
    {"Reactor", hw.reactorName or "FAIL", hw.reactor ~= nil, "Fusion core control"},
    {"Logic Adapter", hw.logicName or "FAIL", hw.logic ~= nil, "Ignition and injection status"},
    {"Laser", hw.laserName or "FAIL", hw.laser ~= nil, "Ignition beam source"},
    {"Induction Matrix", hw.inductionName or "FAIL", hw.induction ~= nil, "Battery / power buffer"},
    {"Relay LAS", lasRef, lasOk, "Laser charge and fire line"},
    {"Relay T", tRef, tOk, "Tritium valve line"},
    {"Relay D", dRef, dOk, "Deuterium valve line"},
    {"Reader T", hw.readerRoles.tritium and hw.readerRoles.tritium.name or "FAIL", hw.readerRoles.tritium ~= nil, "Tritium tank read"},
    {"Reader D", hw.readerRoles.deuterium and hw.readerRoles.deuterium.name or "FAIL", hw.readerRoles.deuterium ~= nil, "Deuterium tank read"},
    {"Reader Aux", hw.readerRoles.inventory and hw.readerRoles.inventory.name or "FAIL", hw.readerRoles.inventory ~= nil, "Auxiliary inventory / feed"},
    {"Monitor", hw.monitorName or "term", hw.monitorName ~= nil, "Touch interface"},
  }

  local rowStep = 2
  for i, row in ipairs(rows) do
    local yy = y + ((i - 1) * rowStep) + 1
    if yy + 1 <= maxY then
      local tone = row[3] and C.ok or C.bad
      local head = string.format("%s | %s", row[2], row[3] and "OK" or "FAIL")
      ctx.drawKeyValue(x, yy, row[1], ctx.shortText(head, 16), C.dim, tone, center.w - 6)
      ctx.writeAt(x + 1, yy + 1, ctx.shortText("role: " .. row[4], center.w - 8), C.info, C.panelDark)
    end
  end

  ctx.drawControlPanel(layout.right or layout.left, layout)
end

function M.drawInductionView(ctx, layout)
  local C = ctx.C
  local state = ctx.state

  local istat, statusTone = ctx.inductionStatus()
  local left = layout.left
  ctx.drawBox(left.x, left.y, left.w, left.h, "INDUCTION MATRIX", C.border)
  local x = left.x + 2
  local y = left.y + 1
  local maxY = left.y + left.h - 2
  local contentW = math.max(8, left.w - 6)

  ctx.drawKeyValue(x, y + 1, "Online", state.inductionPresent and "ONLINE" or "OFFLINE", C.dim, state.inductionPresent and C.ok or C.bad, contentW)
  if y + 2 <= maxY then
    ctx.drawKeyValue(x, y + 2, "Formed", state.inductionFormed and "FORMED" or "UNFORMED", C.dim, state.inductionFormed and C.ok or C.warn, contentW)
  end
  if y + 3 <= maxY then
    ctx.drawKeyValue(x, y + 3, "Global", istat, C.dim, statusTone, contentW)
  end

  local phaseY = y + 5
  if phaseY + 1 <= maxY and contentW >= 16 then
    local leftW = math.max(8, math.floor(contentW * 0.50))
    local rightW = math.max(8, contentW - leftW)
    UIComponents.drawStateBlock(ctx, x, phaseY, leftW, "Phase", istat)
    UIComponents.drawStateBlock(ctx, x + leftW, phaseY, rightW, "Alert", state.alert)
  end

  local detailsTop = phaseY + 3
  if detailsTop <= maxY then
    if left.h < 24 then
      local compactRows = {
        { "Stored", ctx.formatEnergy(state.inductionEnergy), C.energy },
        { "Max", ctx.formatEnergy(state.inductionMax), C.energy },
        { "Need", ctx.formatEnergy(state.inductionNeeded), C.warn },
        { "Fill", string.format("%.1f%%", state.inductionPct), C.energy },
        { "Cells", tostring(state.inductionCells), C.info },
        { "Prov", tostring(state.inductionProviders), C.info },
      }
      local ry = detailsTop
      for i = 1, #compactRows do
        if ry > maxY then break end
        local row = compactRows[i]
        ctx.drawKeyValue(x, ry, row[1], row[2], C.dim, row[3], contentW)
        ry = ry + 1
      end
    else
      local sections = splitVertical(detailsTop, maxY, {
        { min = 8, weight = 3 },
        { min = 6, weight = 2 },
      }, 1)
      local technical = sections[1]
      local structure = sections[2]

      if technical then
        ctx.drawBox(x - 1, technical.y, left.w - 4, technical.h, "TECHNICAL", C.borderDim)
        local techRows = {
          { "Stored", ctx.formatEnergy(state.inductionEnergy), C.energy },
          { "Max", ctx.formatEnergy(state.inductionMax), C.energy },
          { "Needed", ctx.formatEnergy(state.inductionNeeded), C.warn },
          { "In / Out", ctx.formatEnergyPerTick(state.inductionInput) .. " / " .. ctx.formatEnergyPerTick(state.inductionOutput), C.info },
          { "Fill", string.format("%.1f %%", state.inductionPct), C.energy },
        }
        local rowCap = math.max(0, technical.h - 2)
        for i = 1, math.min(#techRows, rowCap) do
          local row = techRows[i]
          ctx.drawKeyValue(x, technical.y + i, row[1], row[2], C.dim, row[3], contentW)
        end
      end

      if structure then
        ctx.drawBox(x - 1, structure.y, left.w - 4, structure.h, "STRUCTURE", C.borderDim)
        local structRows = {
          { "Cells", tostring(state.inductionCells), C.info },
          { "Providers", tostring(state.inductionProviders), C.info },
          { "Dim", string.format("%dx%dx%d", state.inductionLength, state.inductionWidth, state.inductionHeight), C.text },
          { "Port", state.inductionPortMode, C.info },
        }
        local rowCap = math.max(0, structure.h - 2)
        for i = 1, math.min(#structRows, rowCap) do
          local row = structRows[i]
          ctx.drawKeyValue(x, structure.y + i, row[1], row[2], C.dim, row[3], contentW)
        end
      end
    end
  end

  if layout.center then
    ctx.drawInductionDiagram(layout.center.x, layout.center.y, layout.center.w, layout.center.h)
    ctx.drawControlPanel(layout.right or layout.left, layout)
  else
    -- Petit ecran: on privilegie l'accessibilite des controles.
    ctx.drawControlPanel(layout.right or layout.left, layout)
  end
end

function M.drawUpdateView(ctx, layout)
  local infoPanel
  local controlPanel

  if layout.center then
    UIComponents.drawStatusPanel(ctx, layout.left)
    infoPanel = layout.center
    controlPanel = layout.right or layout.left
  else
    infoPanel = layout.left
    controlPanel = layout.right or layout.left
  end

  UIComponents.drawUpdateInfoPanel(ctx, infoPanel)
  ctx.drawControlPanel(controlPanel, layout)
end

function M.drawConfigView(ctx, layout)
  local C = ctx.C
  local setup = ctx.state.setup

  local infoPanel
  local controlPanel
  if layout.center then
    UIComponents.drawStatusPanel(ctx, layout.left)
    infoPanel = layout.center
    controlPanel = layout.right or layout.left
  else
    infoPanel = layout.left
    controlPanel = layout.right or layout.left
  end

  ctx.drawBox(infoPanel.x, infoPanel.y, infoPanel.w, infoPanel.h, "DISPLAY CONFIG", C.border)
  local inner = panelInner(infoPanel, 2, 2)
  local x = inner.x
  local y = inner.y
  local w = math.max(8, infoPanel.w - 6)
  local maxY = infoPanel.y + infoPanel.h - 2

  if type(setup) ~= "table" or type(setup.working) ~= "table" then
    ctx.writeAt(x, y, "Config setup indisponible", C.warn, C.panelDark)
    ctx.drawControlPanel(controlPanel, layout)
    return
  end

  local working = setup.working
  local uiScale = tonumber(working.ui and working.ui.scale) or 1.0
  local textScale = tonumber(working.monitor and working.monitor.scale) or 0.5
  local outputMode = string.lower(tostring(working.ui and working.ui.output or "monitor"))
  local energyUnit = string.lower(tostring(working.ui and working.ui.energyUnit or "j"))
  local laserCount = tonumber(working.ui and working.ui.laserCount) or 1
  local appliedUiScale = tonumber(ctx.CFG.uiScale) or uiScale
  local appliedTextScale = tonumber(ctx.CFG.monitorScale) or textScale
  local appliedOutputMode = string.lower(tostring(ctx.CFG.displayOutput or outputMode))
  local appliedEnergyUnit = string.lower(tostring(ctx.CFG.energyUnit or energyUnit))
  local appliedLaserCount = tonumber(ctx.CFG.laserCount) or laserCount

  local function outputLabel(mode)
    if mode == "terminal" then return "TERMINAL" end
    if mode == "both" then return "TERMINAL + MON" end
    return "MONITOR"
  end

  local function energyLabel(unit)
    if unit == "fe" then return "FE" end
    return "J"
  end

  local sections = splitVertical(y, maxY, {
    { min = 8, weight = 4 },
    { min = 5, weight = 2 },
    { min = 4, weight = 1 },
  }, 1)

  local values = sections[1]
  local tips = sections[2]
  local message = sections[3]

  if values then
    ctx.drawBox(x - 1, values.y, w + 2, values.h, "CURRENT VALUES", C.borderDim)
    local rows = {
      { "UI Scale", string.format("%.1fx", uiScale), C.info },
      { "Text Scale", string.format("%.1fx", textScale), C.info },
      { "Output", outputLabel(outputMode), C.info },
      { "Energy Unit", energyLabel(energyUnit), C.info },
      { "Laser Count", tostring(laserCount), C.info },
      { "Applied UI", string.format("%.1fx", appliedUiScale), C.ok },
      { "Applied TXT", string.format("%.1fx", appliedTextScale), C.ok },
      { "Applied OUT", outputLabel(appliedOutputMode), C.ok },
      { "Applied UNIT", energyLabel(appliedEnergyUnit), C.ok },
      { "Applied LAS", tostring(appliedLaserCount), C.ok },
      { "State", setup.dirty and "MODIFIED" or "SAVED", setup.dirty and C.warn or C.ok },
    }
    local rowCap = math.max(0, values.h - 2)
    for i = 1, math.min(#rows, rowCap) do
      local row = rows[i]
      ctx.drawKeyValue(x, values.y + i, row[1], row[2], C.dim, row[3], w)
    end
  end

  if tips then
    ctx.drawBox(x - 1, tips.y, w + 2, tips.h, "TIPS", C.borderDim)
    local tipRows = {
      "- UI +/- : scale layout",
      "- TXT +/- : monitor text",
      "- TERM/MON/BOTH : output mode",
      "- UNIT J/FE : energy",
      "- LAS +/- : laser count",
    }
    local rowCap = math.max(0, tips.h - 2)
    for i = 1, math.min(#tipRows, rowCap) do
      ctx.writeAt(x, tips.y + i, ctx.shortText(tipRows[i], w), C.dim, C.panelDark)
    end
  end

  if message then
    local msg = tostring(setup.lastMessage or "Ready")
    ctx.drawBox(x - 1, message.y, w + 2, message.h, "MESSAGE", C.borderDim)
    if message.h >= 3 then
      ctx.writeAt(x, message.y + 1, ctx.shortText(msg, w), C.info, C.panelDark)
    end
    if message.h >= 4 then
      ctx.writeAt(x, message.y + 2, ctx.shortText("Save: " .. tostring(setup.saveStatus or "N/A"), w), C.dim, C.panelDark)
    end
  end

  ctx.drawControlPanel(controlPanel, layout)
end

function M.drawSetupView(ctx, layout)
  local C = ctx.C
  local state = ctx.state
  local setup = state.setup
  if type(setup) ~= "table" or type(setup.working) ~= "table" then
    ctx.drawBox(layout.left.x, layout.left.y, layout.left.w, layout.left.h, "SETUP / MAINTENANCE", C.border)
    ctx.writeAt(layout.left.x + 2, layout.left.y + 2, "Setup config not loaded", C.warn, C.panelDark)
    ctx.drawControlPanel(layout.right or layout.left, layout)
    return
  end

  local left = layout.left
  local center = layout.center
  ctx.drawBox(left.x, left.y, left.w, left.h, "SETUP / MAINTENANCE", C.border)
  local lx = left.x + 2
  local maxLeftY = left.y + left.h - 2
  local leftW = math.max(8, left.w - 6)

  local baseRows = {
    { "Monitor", setup.working.monitor.name, setup.working.monitor.ok and C.ok or C.bad },
    { "Reactor", setup.working.devices.reactorController, setup.deviceStatus.reactorController == "OK" and C.ok or C.bad },
    { "Logic", setup.working.devices.logicAdapter, setup.deviceStatus.logicAdapter == "OK" and C.ok or C.bad },
    { "Laser", setup.working.devices.laser, setup.deviceStatus.laser == "OK" and C.ok or C.bad },
    { "Induction", setup.working.devices.induction, setup.deviceStatus.induction == "OK" and C.ok or C.bad },
  }
  local ly = left.y + 2
  for i = 1, #baseRows do
    if ly > maxLeftY then break end
    local row = baseRows[i]
    ctx.drawKeyValue(lx, ly, row[1], row[2], C.dim, row[3], leftW)
    ly = ly + 1
  end

  local detailTop = ly + 1
  if detailTop <= maxLeftY then
    local sections = splitVertical(detailTop, maxLeftY, {
      { min = 6, weight = 3 },
      { min = 4, weight = 2 },
    }, 1)
    local active = sections[1]
    local uiState = sections[2]

    if active then
      ctx.drawBox(lx - 1, active.y, left.w - 4, active.h, "ACTIVE CONFIG", C.borderDim)
      local rows = {
        { "Relay LAS", setup.working.relays.laser.name .. "." .. setup.working.relays.laser.side, setup.deviceStatus.relayLaser == "OK" and C.ok or C.warn },
        { "Relay T", setup.working.relays.tritium.name .. "." .. setup.working.relays.tritium.side, setup.deviceStatus.relayTritium == "OK" and C.ok or C.warn },
        { "Relay D", setup.working.relays.deuterium.name .. "." .. setup.working.relays.deuterium.side, setup.deviceStatus.relayDeuterium == "OK" and C.ok or C.warn },
        { "Reader T", setup.working.readers.tritium, setup.deviceStatus.readerTritium == "OK" and C.ok or C.warn },
        { "Reader D", setup.working.readers.deuterium, setup.deviceStatus.readerDeuterium == "OK" and C.ok or C.warn },
        { "Reader Aux", setup.working.readers.aux, setup.deviceStatus.readerAux == "OK" and C.ok or C.warn },
      }
      local cap = math.max(0, active.h - 2)
      for i = 1, math.min(#rows, cap) do
        local row = rows[i]
        ctx.drawKeyValue(lx, active.y + i, row[1], row[2], C.dim, row[3], leftW)
      end
    end

    if uiState then
      ctx.drawBox(lx - 1, uiState.y, left.w - 4, uiState.h, "UI STATE", C.borderDim)
      local rows = {
        { "View/Out", setup.working.ui.preferredView .. "/" .. tostring(setup.working.ui.output or "monitor"), C.info },
        { "Energy", string.upper(tostring(setup.working.ui.energyUnit or "j")), C.info },
        { "Laser Cnt", tostring(setup.working.ui.laserCount or 1), C.info },
        { "Text", tostring(setup.working.monitor.scale), C.info },
        { "UI", tostring(setup.working.ui.scale), C.info },
      }
      local cap = math.max(0, uiState.h - 2)
      for i = 1, math.min(#rows, cap) do
        local row = rows[i]
        ctx.drawKeyValue(lx, uiState.y + i, row[1], row[2], C.dim, row[3], leftW)
      end
    end
  end

  if center then
    ctx.drawBox(center.x, center.y, center.w, center.h, "DEVICE STATUS / TESTS", C.border)
    local x = center.x + 2
    local y = center.y + 1
    local maxY = center.y + center.h - 2
    local rows = ctx.getSetupStatusRows()
    ctx.writeAt(x, y, "CONFIGURED ELEMENTS", C.info, C.panelDark)

    local resultH = math.min(6, math.max(4, math.floor(center.h * 0.28)))
    local rowsBottom = maxY - resultH - 1
    local rowCap = math.max(0, rowsBottom - (y + 1) + 1)
    for i = 1, math.min(#rows, rowCap) do
      local row = rows[i]
      local yy = y + i
      local tone = row.status == "OK" and C.ok or (row.status == "MISSING" and C.bad or C.warn)
      ctx.writeAt(x, yy, ctx.shortText(string.format("%-10s %-16s %-8s", row.role, row.name, row.status), center.w - 6), tone, C.panelDark)
    end

    local msgY = maxY - resultH + 1
    if msgY > y then
      ctx.drawBox(x - 1, msgY, center.w - 4, resultH, "RESULT", C.borderDim)
      if msgY + 1 <= maxY then
        ctx.writeAt(x, msgY + 1, ctx.shortText("TEST: " .. tostring(setup.lastTestResult or "N/A"), center.w - 6), C.info, C.panelDark)
      end
      if msgY + 2 <= maxY then
        ctx.writeAt(x, msgY + 2, ctx.shortText("SAVE: " .. tostring(setup.saveStatus or "N/A"), center.w - 6), setup.saveStatus == "CONFIG SAVED" and C.ok or C.warn, C.panelDark)
      end
      if msgY + 3 <= maxY then
        ctx.writeAt(x, msgY + 3, ctx.shortText("INFO: " .. tostring(setup.lastMessage or "Ready"), center.w - 6), C.dim, C.panelDark)
      end
    end
  end

  ctx.drawControlPanel(layout.right or layout.left, layout)
end

return M
