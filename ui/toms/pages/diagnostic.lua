local M = {}

function M.render(ctx)
  local common = assert(ctx.common, "common helpers are required")
  local state = assert(ctx.state, "state is required")
  local hw = assert(ctx.hw, "hw is required")
  local cfg = type(ctx.CFG) == "table" and ctx.CFG or {}
  local asText = type(ctx.asText) == "function" and ctx.asText or tostring
  local panels = (ctx.layout and ctx.layout.panels) or {}

  ctx.ui.drawPanel(panels.reactor, "DEVICE STATUS", {
    bg = ctx.theme.palette.panelBg,
    border = ctx.theme.palette.border,
    headerBg = ctx.theme.palette.panelHeader,
    headerText = ctx.theme.palette.textOnDark or ctx.theme.palette.textPrimary,
  })
  ctx.ui.drawLabelValue(panels.reactor, 0, "Reactor", hw.reactor and "OK" or "MISSING", hw.reactor and ctx.theme.palette.ok or ctx.theme.palette.critical, ctx.theme.palette.textMuted)
  ctx.ui.drawLabelValue(panels.reactor, 1, "Logic", hw.logic and "OK" or "MISSING", hw.logic and ctx.theme.palette.ok or ctx.theme.palette.critical, ctx.theme.palette.textMuted)
  ctx.ui.drawLabelValue(panels.reactor, 2, "Laser", hw.laser and "OK" or "MISSING", hw.laser and ctx.theme.palette.ok or ctx.theme.palette.critical, ctx.theme.palette.textMuted)
  ctx.ui.drawLabelValue(panels.reactor, 3, "Induction", hw.induction and "OK" or "MISSING", hw.induction and ctx.theme.palette.ok or ctx.theme.palette.warning, ctx.theme.palette.textMuted)
  ctx.ui.drawLabelValue(panels.reactor, 4, "Display", ctx.model.monitorName, ctx.theme.palette.info, ctx.theme.palette.textMuted)
  ctx.ui.drawLabelValue(panels.reactor, 5, "Backend", ctx.model.backendName, ctx.theme.palette.info, ctx.theme.palette.textMuted)

  ctx.ui.drawPanel(panels.temperatures, "RELAYS / READERS", {
    bg = ctx.theme.palette.panelBg,
    border = ctx.theme.palette.warning,
    headerBg = ctx.theme.palette.panelHeaderAlt,
    headerText = ctx.theme.palette.textOnDark or ctx.theme.palette.textPrimary,
  })
  local relayLaser = type(cfg.actions) == "table" and type(cfg.actions.laser_charge) == "table" and cfg.actions.laser_charge.relay or "N/A"
  local relayT = type(cfg.actions) == "table" and type(cfg.actions.tritium) == "table" and cfg.actions.tritium.relay or "N/A"
  local relayD = type(cfg.actions) == "table" and type(cfg.actions.deuterium) == "table" and cfg.actions.deuterium.relay or "N/A"
  ctx.ui.drawLabelValue(panels.temperatures, 0, "Relay LAS", asText(relayLaser, "N/A"), ctx.theme.palette.info, ctx.theme.palette.textMuted)
  ctx.ui.drawLabelValue(panels.temperatures, 1, "Relay T", asText(relayT, "N/A"), ctx.theme.palette.info, ctx.theme.palette.textMuted)
  ctx.ui.drawLabelValue(panels.temperatures, 2, "Relay D", asText(relayD, "N/A"), ctx.theme.palette.info, ctx.theme.palette.textMuted)
  ctx.ui.drawLabelValue(panels.temperatures, 3, "Reader T", asText(hw.readerRoles and hw.readerRoles.tritium and hw.readerRoles.tritium.name, "N/A"), ctx.theme.palette.info, ctx.theme.palette.textMuted)
  ctx.ui.drawLabelValue(panels.temperatures, 4, "Reader D", asText(hw.readerRoles and hw.readerRoles.deuterium and hw.readerRoles.deuterium.name, "N/A"), ctx.theme.palette.info, ctx.theme.palette.textMuted)
  ctx.ui.drawLabelValue(panels.temperatures, 5, "Reader AUX", asText(hw.readerRoles and hw.readerRoles.inventory and hw.readerRoles.inventory.name, "N/A"), ctx.theme.palette.info, ctx.theme.palette.textMuted)

  ctx.ui.drawPanel(panels.laser, "MATCHED METHODS", {
    bg = ctx.theme.palette.panelBg,
    border = ctx.theme.palette.ok,
    headerBg = ctx.theme.palette.panelHeaderAlt,
    headerText = ctx.theme.palette.textOnDark or ctx.theme.palette.textPrimary,
  })
  local methods = type(state.runtimeMethodMatches) == "table" and state.runtimeMethodMatches or {}
  ctx.ui.drawLabelValue(panels.laser, 0, "plasma", asText(methods.plasma, "N/A"), ctx.theme.palette.textPrimary, ctx.theme.palette.textMuted)
  ctx.ui.drawLabelValue(panels.laser, 1, "case", asText(methods.case, "N/A"), ctx.theme.palette.textPrimary, ctx.theme.palette.textMuted)
  ctx.ui.drawLabelValue(panels.laser, 2, "injection", asText(methods.injection, "N/A"), ctx.theme.palette.textPrimary, ctx.theme.palette.textMuted)
  ctx.ui.drawLabelValue(panels.laser, 3, "active", asText(methods.active, "N/A"), ctx.theme.palette.textPrimary, ctx.theme.palette.textMuted)
  ctx.ui.drawLabelValue(panels.laser, 4, "passive", asText(methods.passive, "N/A"), ctx.theme.palette.textPrimary, ctx.theme.palette.textMuted)
  ctx.ui.drawLabelValue(panels.laser, 5, "steam", asText(methods.steam, "N/A"), ctx.theme.palette.textPrimary, ctx.theme.palette.textMuted)
  ctx.ui.drawLabelValue(panels.laser, 6, "fuel", asText(methods.fuel, "N/A"), ctx.theme.palette.textPrimary, ctx.theme.palette.textMuted)
  ctx.ui.drawLabelValue(panels.laser, 7, "laserE", asText(methods.laserEnergy, "N/A"), ctx.theme.palette.textPrimary, ctx.theme.palette.textMuted)

  common.drawInfoPanel(ctx.ui, panels.core, ctx.theme, "RUNTIME DIAGNOSTICS", {
    { kind = "section", text = "System overview" },
    { label = "Global", value = ctx.model.statusText, valueTone = ctx.model.statusTone },
    { label = "Phase", value = ctx.model.phase, valueTone = ctx.model.phaseTone },
    { label = "Backend", value = ctx.model.backendName, valueTone = ctx.theme.palette.info },
    { label = "Display", value = ctx.model.monitorName, valueTone = ctx.theme.palette.info },
    { kind = "section", text = "Ignition safety" },
    { label = "Blockers", value = tostring(#(ctx.model.blockers or {})), valueTone = (#(ctx.model.blockers or {}) > 0) and ctx.theme.palette.critical or ctx.theme.palette.ok },
    { label = "Warnings", value = tostring(#(ctx.model.warnings or {})), valueTone = (#(ctx.model.warnings or {}) > 0) and ctx.theme.palette.warning or ctx.theme.palette.ok },
    { label = "Control", value = ctx.model.allowControl and "UNLOCKED" or "LOCKED", valueTone = ctx.model.allowControl and ctx.theme.palette.warning or ctx.theme.palette.ok },
  })
  common.drawStatusPanel(ctx.ui, panels.status, ctx.theme, ctx.model)
  return true
end

return M

