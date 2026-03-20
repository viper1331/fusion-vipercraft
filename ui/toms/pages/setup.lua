local M = {}

function M.render(ctx)
  local common = assert(ctx.common, "common helpers are required")
  local state = assert(ctx.state, "state is required")
  local cfg = type(ctx.CFG) == "table" and ctx.CFG or {}
  local asText = type(ctx.asText) == "function" and ctx.asText or tostring
  local setup = type(state.setup) == "table" and state.setup or {}
  local working = type(setup.working) == "table" and setup.working or {}
  local devices = type(working.devices) == "table" and working.devices or {}
  local panels = (ctx.layout and ctx.layout.panels) or {}

  ctx.ui.drawPanel(panels.reactor, "SETUP DEVICES", {
    bg = ctx.theme.palette.panelBg,
    border = ctx.theme.palette.borderStrong,
    headerBg = ctx.theme.palette.panelHeader,
    headerText = ctx.theme.palette.textOnDark or ctx.theme.palette.textPrimary,
  })
  ctx.ui.drawLabelValue(panels.reactor, 0, "Monitor", asText(working.monitor and working.monitor.name, ctx.model.monitorName), ctx.theme.palette.info, ctx.theme.palette.textMuted)
  ctx.ui.drawLabelValue(panels.reactor, 1, "Reactor", asText(devices.reactorController, "N/A"), ctx.theme.palette.info, ctx.theme.palette.textMuted)
  ctx.ui.drawLabelValue(panels.reactor, 2, "Logic", asText(devices.logicAdapter, "N/A"), ctx.theme.palette.info, ctx.theme.palette.textMuted)
  ctx.ui.drawLabelValue(panels.reactor, 3, "Laser", asText(devices.laser, "N/A"), ctx.theme.palette.info, ctx.theme.palette.textMuted)
  ctx.ui.drawLabelValue(panels.reactor, 4, "Induction", asText(devices.induction, "N/A"), ctx.theme.palette.info, ctx.theme.palette.textMuted)

  ctx.ui.drawPanel(panels.temperatures, "SETUP STATE", {
    bg = ctx.theme.palette.panelBg,
    border = ctx.theme.palette.warning,
    headerBg = ctx.theme.palette.panelHeaderAlt,
    headerText = ctx.theme.palette.textOnDark or ctx.theme.palette.textPrimary,
  })
  ctx.ui.drawLabelValue(panels.temperatures, 0, "Save", asText(setup.saveStatus, "N/A"), ctx.theme.palette.info, ctx.theme.palette.textMuted)
  ctx.ui.drawLabelValue(panels.temperatures, 1, "Test", asText(setup.lastTestResult, "N/A"), ctx.theme.palette.info, ctx.theme.palette.textMuted)
  ctx.ui.drawLabelValue(panels.temperatures, 2, "Message", asText(setup.lastMessage, "Ready"), ctx.theme.palette.textPrimary, ctx.theme.palette.textMuted)
  ctx.ui.drawLabelValue(panels.temperatures, 3, "View", asText(working.ui and working.ui.preferredView, state.currentView), ctx.theme.palette.info, ctx.theme.palette.textMuted)
  ctx.ui.drawLabelValue(panels.temperatures, 4, "Output", asText(working.ui and working.ui.output, cfg.displayOutput), ctx.theme.palette.info, ctx.theme.palette.textMuted)

  ctx.ui.drawPanel(panels.laser, "CONFIGURED ELEMENTS", {
    bg = ctx.theme.palette.panelBg,
    border = ctx.theme.palette.ok,
    headerBg = ctx.theme.palette.panelHeaderAlt,
    headerText = ctx.theme.palette.textOnDark or ctx.theme.palette.textPrimary,
  })
  local rows = type(ctx.api.getSetupStatusRows) == "function" and ctx.api.getSetupStatusRows() or {}
  local cap = math.max(0, panels.laser.h - 4)
  for i = 1, math.min(#rows, cap) do
    local row = rows[i]
    local tone = row.status == "OK" and ctx.theme.palette.ok or (row.status == "MISSING" and ctx.theme.palette.critical or ctx.theme.palette.warning)
    ctx.ui.drawLabelValue(panels.laser, i - 1, tostring(row.role or "?"), tostring(row.name or "?") .. " " .. tostring(row.status or "?"), tone, ctx.theme.palette.textMuted)
  end

  common.drawCorePanel(ctx.ui, panels.core, ctx.theme, ctx.model, "SETUP REACTOR PREVIEW")
  common.drawStatusPanel(ctx.ui, panels.status, ctx.theme, ctx.model)
  return true
end

return M

