local M = {}

function M.render(ctx)
  local common = assert(ctx.common, "common helpers are required")
  local panels = (ctx.layout and ctx.layout.panels) or {}

  common.drawReactorPanel(ctx.ui, panels.reactor, ctx.theme, ctx.model)
  common.drawTemperaturePanel(ctx.ui, panels.temperatures, ctx.theme, ctx.model)
  common.drawLaserPanel(ctx.ui, panels.laser, ctx.theme, ctx.model)
  common.drawInfoPanel(ctx.ui, panels.core, ctx.theme, "MANUAL CONTROL", {
    { kind = "section", text = "Runtime actions" },
    { label = "Refresh", value = "Available", valueTone = ctx.theme.palette.ok },
    { label = "Laser Pulse", value = ctx.model.allowControl and "Enabled" or "Locked", valueTone = ctx.model.allowControl and ctx.theme.palette.warning or ctx.theme.palette.ok },
    { label = "Injection -", value = ctx.model.allowControl and "Enabled" or "Locked", valueTone = ctx.model.allowControl and ctx.theme.palette.warning or ctx.theme.palette.ok },
    { label = "Injection +", value = ctx.model.allowControl and "Enabled" or "Locked", valueTone = ctx.model.allowControl and ctx.theme.palette.warning or ctx.theme.palette.ok },
    { kind = "section", text = "Current state" },
    { label = "Global", value = ctx.model.statusText, valueTone = ctx.model.statusTone },
    { label = "Phase", value = ctx.model.phase, valueTone = ctx.model.phaseTone },
    { label = "Last action", value = ctx.model.lastAction, valueTone = ctx.theme.palette.info },
    { label = "Control mode", value = ctx.model.allowControl and "UNLOCKED" or "LOCKED", valueTone = ctx.model.allowControl and ctx.theme.palette.warning or ctx.theme.palette.ok },
  })
  common.drawStatusPanel(ctx.ui, panels.status, ctx.theme, ctx.model)
  ctx.ui.drawLabelValue(panels.status, 10, "Manual mode", "Operator view", ctx.theme.palette.warning, ctx.theme.palette.textMuted)
  return true
end

return M

