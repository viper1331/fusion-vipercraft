local UIComponents = require("ui.components")

local M = {}

function M.resolveViewName(currentView)
  if currentView == "diagnostic" then return "DIAG" end
  if currentView == "manual" then return "MAN" end
  if currentView == "induction" then return "IND" end
  if currentView == "update" then return "UPDATE" end
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

  ctx.drawBox(x - 1, y + 4, left.w - 4, 9, "TECHNICAL", C.borderDim)
  ctx.drawKeyValue(x, y + 5, "Stored", ctx.formatMJ(state.inductionEnergy), C.dim, C.energy, left.w - 6)
  ctx.drawKeyValue(x, y + 6, "Max", ctx.formatMJ(state.inductionMax), C.dim, C.energy, left.w - 6)
  ctx.drawKeyValue(x, y + 7, "Fill %", string.format("%.1f%%", state.inductionPct), C.dim, C.energy, left.w - 6)
  ctx.drawKeyValue(x, y + 8, "Needed", ctx.formatMJ(state.inductionNeeded), C.dim, C.dim, left.w - 6)
  ctx.drawKeyValue(x, y + 9, "Transfer Cap", ctx.formatMJ(state.inductionTransferCap), C.dim, C.info, left.w - 6)
  ctx.drawKeyValue(x, y + 10, "Last In", ctx.formatMJ(state.inductionInput), C.dim, C.ok, left.w - 6)
  ctx.drawKeyValue(x, y + 11, "Last Out", ctx.formatMJ(state.inductionOutput), C.dim, C.warn, left.w - 6)

  ctx.drawBox(x - 1, y + 13, left.w - 4, 6, "STRUCTURE", C.borderDim)
  ctx.drawKeyValue(x, y + 14, "Cells", tostring(state.inductionCells), C.dim, C.info, left.w - 6)
  ctx.drawKeyValue(x, y + 15, "Providers", tostring(state.inductionProviders), C.dim, C.info, left.w - 6)
  ctx.drawKeyValue(x, y + 16, "Dimensions", string.format("%dx%dx%d", state.inductionLength, state.inductionWidth, state.inductionHeight), C.dim, C.text, left.w - 6)
  ctx.drawKeyValue(x, y + 17, "Port Mode", state.inductionPortMode, C.dim, C.info, left.w - 6)

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

return M
