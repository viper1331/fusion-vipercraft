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
    formatMJ = base.formatMJ,
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
  if currentView == "setup" then return "SETUP" end
  return "SUP"
end

function M.drawMonitorSelection(ctx, layout)
  local C = ctx.C
  local state = ctx.state

  term.setBackgroundColor(C.bg)
  term.setTextColor(C.text)
  term.clear()
  ctx.drawHeader("FUSION SUPERVISOR", "MONITOR LINK")

  local boxW = ctx.clamp(layout.width - 6, 26, 60)
  local boxH = ctx.clamp(layout.height - 3, 12, layout.height)
  local x = math.floor((layout.width - boxW) / 2) + 1
  local y = layout.top + 1

  ctx.drawBox(x, y, boxW, boxH, "MONITOR SELECTION", C.border)
  ctx.writeAt(x + 2, y + 1, "Choisissez une sortie d'affichage", C.dim, C.panelDark)
  ctx.writeAt(x + 2, y + 2, "IDX  NOM                      TAILLE", C.info, C.panelDark)

  for i = 1, 4 do
    local yy = y + 3 + (i - 1) * 3
    local m = state.monitorList[i]
    if m and yy + 1 < y + boxH - 2 then
      local row = string.format("[%d]  %-22s %3dx%-3d", i, ctx.shortText(m.name, 22), m.w or 0, m.h or 0)
      ctx.writeAt(x + 2, yy, ctx.shortText(row, boxW - 4), C.text, C.panelDark)
      ctx.writeAt(x + 2, yy + 1, "TAP / TOUCHE " .. i .. " pour selectionner", C.dim, C.panelDark)
    end
  end

  ctx.buildButtons(layout)
  ctx.drawButtons(ctx.getCurrentInputSource())
  ctx.drawFooter(layout)
end

function M.drawSupervisionView(ctx, layout)
  UIComponents.drawStatusPanel(ctx, layout.left)
  if layout.mode == "compact" then
    ctx.drawControlPanel(layout.right, layout)
    return
  end

  ctx.drawReactorDiagram(layout.center.x, layout.center.y, layout.center.w, layout.center.h)
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

  local rows = {
    {"Reactor", hw.reactorName or "FAIL", hw.reactor ~= nil, "Fusion core control"},
    {"Logic Adapter", hw.logicName or "FAIL", hw.logic ~= nil, "Ignition and injection status"},
    {"Laser", hw.laserName or "FAIL", hw.laser ~= nil, "Ignition beam source"},
    {"Induction Matrix", hw.inductionName or "FAIL", hw.induction ~= nil, "Battery / power buffer"},
    {"Relay LAS", CFG.actions.laser_charge.relay .. "." .. CFG.actions.laser_charge.side, hw.relays[CFG.actions.laser_charge.relay] ~= nil, "Laser charge and fire line"},
    {"Relay T", CFG.actions.tritium.relay .. "." .. CFG.actions.tritium.side, hw.relays[CFG.actions.tritium.relay] ~= nil, "Tritium valve line"},
    {"Relay D", CFG.actions.deuterium.relay .. "." .. CFG.actions.deuterium.side, hw.relays[CFG.actions.deuterium.relay] ~= nil, "Deuterium valve line"},
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
  local y = left.y + 2

  ctx.drawKeyValue(x, y, "Online", state.inductionPresent and "ONLINE" or "OFFLINE", C.dim, state.inductionPresent and C.ok or C.bad, left.w - 6)
  ctx.drawKeyValue(x, y + 1, "Formed", state.inductionFormed and "FORMED" or "UNFORMED", C.dim, state.inductionFormed and C.ok or C.warn, left.w - 6)
  ctx.drawKeyValue(x, y + 2, "Global", istat, C.dim, statusTone, left.w - 6)

  UIComponents.drawStateBlock(ctx, x, y + 4, left.w - 6, "Phase", istat)
  UIComponents.drawStateBlock(ctx, x + math.floor((left.w - 6) / 2), y + 4, left.w - 6 - math.floor((left.w - 6) / 2), "Alert", state.alert)

  ctx.drawBox(x - 1, y + 7, left.w - 4, 11, "TECHNICAL", C.borderDim)
  UIComponents.drawValueBlock(ctx, x, y + 8, left.w - 6, "Stored", ctx.formatMJ(state.inductionEnergy), "", C.energy)
  UIComponents.drawValueBlock(ctx, x, y + 10, left.w - 6, "Max", ctx.formatMJ(state.inductionMax), "", C.energy)
  UIComponents.drawValueBlock(ctx, x, y + 12, left.w - 6, "Needed", ctx.formatMJ(state.inductionNeeded), "", C.warn)
  UIComponents.drawValueBlock(ctx, x, y + 14, left.w - 6, "In / Out", ctx.formatMJ(state.inductionInput) .. " / " .. ctx.formatMJ(state.inductionOutput), "", C.info)
  UIComponents.drawValueBlock(ctx, x, y + 16, left.w - 6, "Fill", string.format("%.1f", state.inductionPct), "%", C.energy)

  ctx.drawBox(x - 1, y + 19, left.w - 4, 6, "STRUCTURE", C.borderDim)
  ctx.drawKeyValue(x, y + 20, "Cells", tostring(state.inductionCells), C.dim, C.info, left.w - 6)
  ctx.drawKeyValue(x, y + 21, "Providers", tostring(state.inductionProviders), C.dim, C.info, left.w - 6)
  ctx.drawKeyValue(x, y + 22, "Dimensions", string.format("%dx%dx%d", state.inductionLength, state.inductionWidth, state.inductionHeight), C.dim, C.text, left.w - 6)
  ctx.drawKeyValue(x, y + 23, "Port Mode", state.inductionPortMode, C.dim, C.info, left.w - 6)

  if layout.center then
    ctx.drawInductionDiagram(layout.center.x, layout.center.y, layout.center.w, layout.center.h)
    ctx.drawControlPanel(layout.right or layout.left, layout)
  else
    local right = layout.right
    ctx.drawInductionDiagram(right.x, right.y, right.w, right.h)
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
  local ly = left.y + 2

  ctx.drawKeyValue(lx, ly, "Monitor", setup.working.monitor.name, C.dim, setup.working.monitor.ok and C.ok or C.bad, left.w - 6)
  ctx.drawKeyValue(lx, ly + 1, "Reactor", setup.working.devices.reactorController, C.dim, setup.deviceStatus.reactorController == "OK" and C.ok or C.bad, left.w - 6)
  ctx.drawKeyValue(lx, ly + 2, "Logic", setup.working.devices.logicAdapter, C.dim, setup.deviceStatus.logicAdapter == "OK" and C.ok or C.bad, left.w - 6)
  ctx.drawKeyValue(lx, ly + 3, "Laser", setup.working.devices.laser, C.dim, setup.deviceStatus.laser == "OK" and C.ok or C.bad, left.w - 6)
  ctx.drawKeyValue(lx, ly + 4, "Induction", setup.working.devices.induction, C.dim, setup.deviceStatus.induction == "OK" and C.ok or C.bad, left.w - 6)

  ctx.drawBox(lx - 1, ly + 6, left.w - 4, 10, "ACTIVE CONFIG", C.borderDim)
  ctx.drawKeyValue(lx, ly + 7, "Relay LAS", setup.working.relays.laser.name .. "." .. setup.working.relays.laser.side, C.dim, setup.deviceStatus.relayLaser == "OK" and C.ok or C.warn, left.w - 6)
  ctx.drawKeyValue(lx, ly + 8, "Relay T", setup.working.relays.tritium.name .. "." .. setup.working.relays.tritium.side, C.dim, setup.deviceStatus.relayTritium == "OK" and C.ok or C.warn, left.w - 6)
  ctx.drawKeyValue(lx, ly + 9, "Relay D", setup.working.relays.deuterium.name .. "." .. setup.working.relays.deuterium.side, C.dim, setup.deviceStatus.relayDeuterium == "OK" and C.ok or C.warn, left.w - 6)
  ctx.drawKeyValue(lx, ly + 10, "Reader T", setup.working.readers.tritium, C.dim, setup.deviceStatus.readerTritium == "OK" and C.ok or C.warn, left.w - 6)
  ctx.drawKeyValue(lx, ly + 11, "Reader D", setup.working.readers.deuterium, C.dim, setup.deviceStatus.readerDeuterium == "OK" and C.ok or C.warn, left.w - 6)
  ctx.drawKeyValue(lx, ly + 12, "Reader Aux", setup.working.readers.aux, C.dim, setup.deviceStatus.readerAux == "OK" and C.ok or C.warn, left.w - 6)
  ctx.drawKeyValue(lx, ly + 13, "View", setup.working.ui.preferredView, C.dim, C.info, left.w - 6)
  ctx.drawKeyValue(lx, ly + 14, "Scale", tostring(setup.working.monitor.scale), C.dim, C.info, left.w - 6)

  if center then
    ctx.drawBox(center.x, center.y, center.w, center.h, "DEVICE STATUS / TESTS", C.border)
    local x = center.x + 2
    local y = center.y + 1
    local rows = ctx.getSetupStatusRows()
    ctx.writeAt(x, y, "CONFIGURED ELEMENTS", C.info, C.panelDark)
    for i = 1, math.min(#rows, 11) do
      local row = rows[i]
      local yy = y + i
      local tone = row.status == "OK" and C.ok or (row.status == "MISSING" and C.bad or C.warn)
      ctx.writeAt(x, yy, ctx.shortText(string.format("%-10s %-16s %-8s", row.role, row.name, row.status), center.w - 6), tone, C.panelDark)
    end

    local msgY = center.y + center.h - 6
    ctx.drawBox(x - 1, msgY, center.w - 4, 5, "RESULT", C.borderDim)
    ctx.writeAt(x, msgY + 1, ctx.shortText("TEST: " .. tostring(setup.lastTestResult or "N/A"), center.w - 6), C.info, C.panelDark)
    ctx.writeAt(x, msgY + 2, ctx.shortText("SAVE: " .. tostring(setup.saveStatus or "N/A"), center.w - 6), setup.saveStatus == "CONFIG SAVED" and C.ok or C.warn, C.panelDark)
    ctx.writeAt(x, msgY + 3, ctx.shortText("INFO: " .. tostring(setup.lastMessage or "Ready"), center.w - 6), C.dim, C.panelDark)
  end

  ctx.drawControlPanel(layout.right or layout.left, layout)
end

return M
