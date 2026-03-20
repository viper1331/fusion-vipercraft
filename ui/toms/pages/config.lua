local M = {}

function M.render(ctx)
  local common = assert(ctx.common, "common helpers are required")
  local state = assert(ctx.state, "state is required")
  local cfg = type(ctx.CFG) == "table" and ctx.CFG or {}
  local asText = type(ctx.asText) == "function" and ctx.asText or tostring
  local setup = type(state.setup) == "table" and state.setup or {}
  local working = type(setup.working) == "table" and setup.working or {}
  local uiCfg = type(working.ui) == "table" and working.ui or {}
  local monCfg = type(working.monitor) == "table" and working.monitor or {}
  local panels = (ctx.layout and ctx.layout.panels) or {}

  common.drawReactorPanel(ctx.ui, panels.reactor, ctx.theme, ctx.model)

  ctx.ui.drawPanel(panels.temperatures, "DISPLAY CONFIG", {
    bg = ctx.theme.palette.panelBg,
    border = ctx.theme.palette.warning,
    headerBg = ctx.theme.palette.panelHeaderAlt,
    headerText = ctx.theme.palette.textOnDark or ctx.theme.palette.textPrimary,
  })
  ctx.ui.drawLabelValue(panels.temperatures, 0, "UI Scale", tostring(uiCfg.scale or cfg.uiScale or "1.0"), ctx.theme.palette.info, ctx.theme.palette.textMuted)
  ctx.ui.drawLabelValue(panels.temperatures, 1, "Text Scale", tostring(monCfg.scale or cfg.monitorScale or "0.5"), ctx.theme.palette.info, ctx.theme.palette.textMuted)
  ctx.ui.drawLabelValue(panels.temperatures, 2, "Output", asText(uiCfg.output or cfg.displayOutput, "monitor"), ctx.theme.palette.info, ctx.theme.palette.textMuted)
  ctx.ui.drawLabelValue(panels.temperatures, 3, "Energy", asText(uiCfg.energyUnit or cfg.energyUnit, "j"), ctx.theme.palette.info, ctx.theme.palette.textMuted)
  ctx.ui.drawLabelValue(panels.temperatures, 4, "Laser Count", tostring(cfg.laserCount or uiCfg.laserCount or 1), ctx.theme.palette.ok, ctx.theme.palette.textMuted)
  ctx.ui.drawLabelValue(panels.temperatures, 5, "Dirty", setup.dirty and "YES" or "NO", setup.dirty and ctx.theme.palette.warning or ctx.theme.palette.ok, ctx.theme.palette.textMuted)

  ctx.ui.drawPanel(panels.laser, "CONFIG MESSAGE", {
    bg = ctx.theme.palette.panelBg,
    border = ctx.theme.palette.ok,
    headerBg = ctx.theme.palette.panelHeaderAlt,
    headerText = ctx.theme.palette.textOnDark or ctx.theme.palette.textPrimary,
  })
  ctx.ui.drawLabelValue(panels.laser, 0, "Status", asText(setup.saveStatus, "N/A"), ctx.theme.palette.info, ctx.theme.palette.textMuted)
  ctx.ui.drawLabelValue(panels.laser, 1, "Message", asText(setup.lastMessage, "Ready"), ctx.theme.palette.textPrimary, ctx.theme.palette.textMuted)
  ctx.ui.drawLabelValue(panels.laser, 2, "View", asText(uiCfg.preferredView or state.currentView, "supervision"), ctx.theme.palette.info, ctx.theme.palette.textMuted)

  common.drawInfoPanel(ctx.ui, panels.core, ctx.theme, "CONFIG OVERVIEW", {
    { kind = "section", text = "UI settings" },
    { label = "Output", value = asText(uiCfg.output or cfg.displayOutput, "monitor"), valueTone = ctx.theme.palette.info },
    { label = "View", value = asText(uiCfg.preferredView or state.currentView, "supervision"), valueTone = ctx.theme.palette.info },
    { label = "Energy", value = asText(uiCfg.energyUnit or cfg.energyUnit, "j"), valueTone = ctx.theme.palette.info },
    { label = "Laser count", value = tostring(cfg.laserCount or uiCfg.laserCount or 1), valueTone = ctx.theme.palette.ok },
    { kind = "section", text = "Config state" },
    { label = "Dirty", value = setup.dirty and "YES" or "NO", valueTone = setup.dirty and ctx.theme.palette.warning or ctx.theme.palette.ok },
    { label = "Save status", value = asText(setup.saveStatus, "N/A"), valueTone = ctx.theme.palette.info },
    { label = "Message", value = asText(setup.lastMessage, "Ready"), valueTone = ctx.theme.palette.textPrimary },
  })
  common.drawStatusPanel(ctx.ui, panels.status, ctx.theme, ctx.model)
  return true
end

return M

