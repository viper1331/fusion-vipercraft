local M = {}

function M.render(ctx)
  local common = assert(ctx.common, "common helpers are required")
  local state = assert(ctx.state, "state is required")
  local asText = type(ctx.asText) == "function" and ctx.asText or tostring
  local panels = (ctx.layout and ctx.layout.panels) or {}

  ctx.ui.drawPanel(panels.reactor, "INDUCTION MATRIX", {
    bg = ctx.theme.palette.panelBg,
    border = ctx.theme.palette.borderStrong,
    headerBg = ctx.theme.palette.panelHeader,
    headerText = ctx.theme.palette.textOnDark or ctx.theme.palette.textPrimary,
  })
  ctx.ui.drawLabelValue(panels.reactor, 0, "Present", state.inductionPresent and "YES" or "NO", state.inductionPresent and ctx.theme.palette.ok or ctx.theme.palette.critical, ctx.theme.palette.textMuted)
  ctx.ui.drawLabelValue(panels.reactor, 1, "Formed", state.inductionFormed and "FORMED" or "UNFORMED", state.inductionFormed and ctx.theme.palette.ok or ctx.theme.palette.warning, ctx.theme.palette.textMuted)
  ctx.ui.drawLabelValue(panels.reactor, 2, "Stored", asText(type(ctx.api.formatEnergy) == "function" and ctx.api.formatEnergy(state.inductionEnergy) or state.inductionEnergy, "N/A"), ctx.theme.palette.energy, ctx.theme.palette.textMuted)
  ctx.ui.drawLabelValue(panels.reactor, 3, "Max", asText(type(ctx.api.formatEnergy) == "function" and ctx.api.formatEnergy(state.inductionMax) or state.inductionMax, "N/A"), ctx.theme.palette.energy, ctx.theme.palette.textMuted)
  ctx.ui.drawLabelValue(panels.reactor, 4, "Needed", asText(type(ctx.api.formatEnergy) == "function" and ctx.api.formatEnergy(state.inductionNeeded) or state.inductionNeeded, "N/A"), ctx.theme.palette.warning, ctx.theme.palette.textMuted)

  common.drawTemperaturePanel(ctx.ui, panels.temperatures, ctx.theme, ctx.model)
  common.drawLaserPanel(ctx.ui, panels.laser, ctx.theme, ctx.model)
  common.drawCorePanel(ctx.ui, panels.core, ctx.theme, ctx.model, "INDUCTION / FUSION LINK")
  common.drawStatusPanel(ctx.ui, panels.status, ctx.theme, ctx.model)
  return true
end

return M

