local M = {}

function M.render(ctx)
  local common = assert(ctx.common, "common helpers are required")
  local panels = (ctx.layout and ctx.layout.panels) or {}

  common.drawReactorPanel(ctx.ui, panels.reactor, ctx.theme, ctx.model)
  common.drawTemperaturePanel(ctx.ui, panels.temperatures, ctx.theme, ctx.model)
  common.drawLaserPanel(ctx.ui, panels.laser, ctx.theme, ctx.model)
  common.drawCorePanel(ctx.ui, panels.core, ctx.theme, ctx.model, "FUSION CHAMBER")
  common.drawStatusPanel(ctx.ui, panels.status, ctx.theme, ctx.model)
  return true
end

return M

