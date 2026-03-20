local M = {}

function M.render(ctx)
  local common = assert(ctx.common, "common helpers are required")
  local state = assert(ctx.state, "state is required")
  local asText = type(ctx.asText) == "function" and ctx.asText or tostring
  local updateState = type(state.update) == "table" and state.update or {}
  local panels = (ctx.layout and ctx.layout.panels) or {}

  common.drawReactorPanel(ctx.ui, panels.reactor, ctx.theme, ctx.model)

  ctx.ui.drawPanel(panels.temperatures, "UPDATE CHANNEL", {
    bg = ctx.theme.palette.panelBg,
    border = ctx.theme.palette.warning,
    headerBg = ctx.theme.palette.panelHeaderAlt,
    headerText = ctx.theme.palette.textOnDark or ctx.theme.palette.textPrimary,
  })
  ctx.ui.drawLabelValue(panels.temperatures, 0, "Local", asText(updateState.localVersion, "N/A"), ctx.theme.palette.info, ctx.theme.palette.textMuted)
  ctx.ui.drawLabelValue(panels.temperatures, 1, "Remote", asText(updateState.remoteVersion, "N/A"), ctx.theme.palette.info, ctx.theme.palette.textMuted)
  ctx.ui.drawLabelValue(panels.temperatures, 2, "Status", asText(updateState.checkStatus, "N/A"), ctx.theme.palette.warning, ctx.theme.palette.textMuted)
  ctx.ui.drawLabelValue(panels.temperatures, 3, "Busy", updateState.inProgress and "YES" or "NO", updateState.inProgress and ctx.theme.palette.warning or ctx.theme.palette.ok, ctx.theme.palette.textMuted)
  ctx.ui.drawLabelValue(panels.temperatures, 4, "Rollback", asText(updateState.lastRollback, "N/A"), ctx.theme.palette.info, ctx.theme.palette.textMuted)

  ctx.ui.drawPanel(panels.laser, "UPDATE RESULT", {
    bg = ctx.theme.palette.panelBg,
    border = ctx.theme.palette.ok,
    headerBg = ctx.theme.palette.panelHeaderAlt,
    headerText = ctx.theme.palette.textOnDark or ctx.theme.palette.textPrimary,
  })
  ctx.ui.drawLabelValue(panels.laser, 0, "Message", asText(updateState.lastMessage, "Ready"), ctx.theme.palette.textPrimary, ctx.theme.palette.textMuted)
  ctx.ui.drawLabelValue(panels.laser, 1, "Last Action", asText(ctx.model.lastAction, "NONE"), ctx.theme.palette.textPrimary, ctx.theme.palette.textMuted)
  ctx.ui.drawLabelValue(panels.laser, 2, "Auto Check", asText(updateState.autoCheck, "N/A"), ctx.theme.palette.info, ctx.theme.palette.textMuted)
  ctx.ui.drawLabelValue(panels.laser, 3, "Manifest", asText(updateState.manifestVersion, "N/A"), ctx.theme.palette.info, ctx.theme.palette.textMuted)

  common.drawInfoPanel(ctx.ui, panels.core, ctx.theme, "UPDATE OVERVIEW", {
    { kind = "section", text = "Channel status" },
    { label = "Local version", value = asText(updateState.localVersion, "N/A"), valueTone = ctx.theme.palette.info },
    { label = "Remote version", value = asText(updateState.remoteVersion, "N/A"), valueTone = ctx.theme.palette.info },
    { label = "Manifest", value = asText(updateState.manifestVersion, "N/A"), valueTone = ctx.theme.palette.info },
    { label = "Auto check", value = asText(updateState.autoCheck, "N/A"), valueTone = ctx.theme.palette.info },
    { kind = "section", text = "Execution" },
    { label = "Busy", value = updateState.inProgress and "YES" or "NO", valueTone = updateState.inProgress and ctx.theme.palette.warning or ctx.theme.palette.ok },
    { label = "Check status", value = asText(updateState.checkStatus, "N/A"), valueTone = ctx.theme.palette.warning },
    { label = "Last action", value = asText(ctx.model.lastAction, "NONE"), valueTone = ctx.theme.palette.textPrimary },
    { label = "Message", value = asText(updateState.lastMessage, "Ready"), valueTone = ctx.theme.palette.textPrimary },
  })
  common.drawStatusPanel(ctx.ui, panels.status, ctx.theme, ctx.model)
  return true
end

return M

