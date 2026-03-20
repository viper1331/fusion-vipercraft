local TomPageRegistry = require("ui.toms.pages.registry")

local M = {}

M.tabs = {
  { key = "supervision", label = "SUP" },
  { key = "diagnostic", label = "DIAG" },
  { key = "manual", label = "MAN" },
  { key = "induction", label = "IND" },
  { key = "update", label = "UPDATE" },
  { key = "config", label = "CFG" },
  { key = "setup", label = "SETUP" },
}

function M.resolveActiveView(state, fallbackView)
  local key = TomPageRegistry.resolve(fallbackView, state)
  return tostring(key or "supervision")
end

function M.drawBar(ui, bounds, titleBounds, theme, activeView)
  local nav = type(bounds) == "table" and bounds or nil
  if not nav then
    return
  end

  local bg = theme.palette.panelBgSoft or theme.palette.panelBg or colors.gray
  ui.safeFilledRect(nav.x, nav.y, nav.w, nav.h, bg)
  ui.safeFilledRect(nav.x, nav.y, nav.w, 1, theme.palette.borderStrong or colors.cyan)
  ui.safeFilledRect(nav.x, nav.y2, nav.w, 1, theme.palette.border or colors.lightBlue)

  local title = type(titleBounds) == "table" and titleBounds or nil
  if title and title.h >= 1 then
    local titleBg = theme.palette.panelHeader or colors.blue
    local textY = title.y + math.floor((title.h - 1) / 2)
    ui.safeFilledRect(title.x, title.y, title.w, title.h, titleBg)
    ui.safeText(
      title.x + 2,
      textY,
      "NAVIGATION",
      theme.palette.info,
      titleBg,
      math.max(1, math.floor(title.w * 0.38)),
      "left"
    )
    ui.safeText(
      title.x + 2,
      textY,
      "ACTIVE " .. string.upper(tostring(activeView or "supervision")),
      theme.palette.textOnDark or theme.palette.textPrimary,
      titleBg,
      math.max(1, title.w - 4),
      "right"
    )
  end
end

function M.resolveTouchBounds(layout, navBounds, insetFn)
  local controls = type(layout) == "table" and type(layout.controls) == "table" and layout.controls or nil
  local navInner = controls and type(controls.navBounds) == "table" and controls.navBounds or nil
  if navInner then
    return {
      x = navInner.x,
      y = navInner.y,
      w = navInner.w,
      h = navInner.h,
    }
  end
  if type(navBounds) == "table" and type(insetFn) == "function" then
    local fallback = insetFn(navBounds, 1, 1, 1, 1)
    return {
      x = fallback.x,
      y = fallback.y,
      w = fallback.w,
      h = fallback.h,
    }
  end
  return nil
end

return M
