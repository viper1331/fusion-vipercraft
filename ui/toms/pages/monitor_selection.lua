local M = {}

function M.render(ctx)
  local common = assert(ctx.common, "common helpers are required")
  local state = assert(ctx.state, "state is required")
  local hw = assert(ctx.hw, "hw is required")
  local asText = type(ctx.asText) == "function" and ctx.asText or tostring
  local panels = (ctx.layout and ctx.layout.panels) or {}
  local list = type(state.monitorList) == "table" and state.monitorList or {}

  ctx.ui.drawPanel(panels.reactor, "MONITOR SELECTION", {
    bg = ctx.theme.palette.panelBg,
    border = ctx.theme.palette.borderStrong,
    headerBg = ctx.theme.palette.panelHeader,
    headerText = ctx.theme.palette.textOnDark or ctx.theme.palette.textPrimary,
  })
  ctx.ui.drawLabelValue(panels.reactor, 0, "Detected", tostring(#list), ctx.theme.palette.info, ctx.theme.palette.textMuted)
  ctx.ui.drawLabelValue(panels.reactor, 1, "Input", "Touch / key 1..9", ctx.theme.palette.info, ctx.theme.palette.textMuted)
  ctx.ui.drawLabelValue(panels.reactor, 2, "Current", asText(hw.monitorName, "term"), ctx.theme.palette.ok, ctx.theme.palette.textMuted)

  ctx.ui.drawPanel(panels.temperatures, "CANDIDATES", {
    bg = ctx.theme.palette.panelBg,
    border = ctx.theme.palette.warning,
    headerBg = ctx.theme.palette.panelHeaderAlt,
    headerText = ctx.theme.palette.textOnDark or ctx.theme.palette.textPrimary,
  })
  local cap = math.max(1, panels.temperatures.h - 3)
  for i = 1, math.min(#list, cap) do
    local item = list[i]
    local label = string.format("[%d] %s %dx%d", i, asText(item.name, "?"), tonumber(item.w) or 0, tonumber(item.h) or 0)
    ctx.ui.drawLabelValue(panels.temperatures, i - 1, tostring(i), label, ctx.theme.palette.textPrimary, ctx.theme.palette.textMuted)
  end

  ctx.ui.drawPanel(panels.laser, "BACKEND", {
    bg = ctx.theme.palette.panelBg,
    border = ctx.theme.palette.ok,
    headerBg = ctx.theme.palette.panelHeaderAlt,
    headerText = ctx.theme.palette.textOnDark or ctx.theme.palette.textPrimary,
  })
  ctx.ui.drawLabelValue(panels.laser, 0, "Selected", asText(hw.monitorBackend, "terminal"), ctx.theme.palette.info, ctx.theme.palette.textMuted)
  ctx.ui.drawLabelValue(panels.laser, 1, "Family", asText(hw.monitorBackendFamily, "fallback"), ctx.theme.palette.info, ctx.theme.palette.textMuted)
  ctx.ui.drawLabelValue(panels.laser, 2, "Wrapper", asText(hw.monitorWrapperType, "terminal"), ctx.theme.palette.info, ctx.theme.palette.textMuted)

  common.drawCorePanel(ctx.ui, panels.core, ctx.theme, ctx.model, "DISPLAY PREVIEW")
  common.drawStatusPanel(ctx.ui, panels.status, ctx.theme, ctx.model)
  return true
end

return M

