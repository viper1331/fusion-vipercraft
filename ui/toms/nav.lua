local function loadPageRegistry()
  if type(require) == "function" then
    local ok, mod = pcall(require, "ui.toms.pages.registry")
    if ok and type(mod) == "table" then
      return mod
    end
  end
  local okFile, modFile = pcall(dofile, "ui/toms/pages/registry.lua")
  if okFile and type(modFile) == "table" then
    return modFile
  end
  return {
    order = {
      "supervision",
      "diagnostic",
      "manual",
      "induction",
      "update",
      "config",
      "setup",
    },
    resolve = function(view)
      return tostring(view or "supervision")
    end,
  }
end

local TomPageRegistry = loadPageRegistry()

local M = {}

local TAB_DEFINITIONS = {
  supervision = { key = "supervision", label = "SUP", compactLabel = "SUP", buttonId = "viewSup", hotkeys = { "1" } },
  diagnostic = { key = "diagnostic", label = "DIAG", compactLabel = "DIAG", buttonId = "viewDiag", hotkeys = { "2" } },
  manual = { key = "manual", label = "MAN", compactLabel = "MAN", buttonId = "viewMan", hotkeys = { "3" } },
  induction = { key = "induction", label = "IND", compactLabel = "IND", buttonId = "viewInd", hotkeys = { "4" } },
  update = { key = "update", label = "UPDATE", compactLabel = "UPD", buttonId = "viewUpd", hotkeys = { "5" } },
  config = { key = "config", label = "CFG", compactLabel = "CFG", buttonId = "viewCfg", hotkeys = { "6" } },
  setup = { key = "setup", label = "SETUP", compactLabel = "SET", buttonId = "viewSetup", hotkeys = { "7" } },
}

local DEFAULT_ORDER = {
  "supervision",
  "diagnostic",
  "manual",
  "induction",
  "update",
  "config",
  "setup",
}

local HOTKEY_TO_VIEW = {}
for _, key in ipairs(DEFAULT_ORDER) do
  local definition = TAB_DEFINITIONS[key]
  if definition and type(definition.hotkeys) == "table" then
    for _, hotkey in ipairs(definition.hotkeys) do
      HOTKEY_TO_VIEW[string.lower(tostring(hotkey))] = key
    end
  end
end

local function cloneDefinition(key)
  local definition = TAB_DEFINITIONS[key]
  if not definition then
    return nil
  end
  return {
    key = definition.key,
    label = definition.label,
    compactLabel = definition.compactLabel,
    buttonId = definition.buttonId,
    hotkeys = definition.hotkeys,
  }
end

local function resolveOrder()
  local order = type(TomPageRegistry.order) == "table" and TomPageRegistry.order or DEFAULT_ORDER
  local keys = {}
  for _, key in ipairs(order) do
    if TAB_DEFINITIONS[key] then
      keys[#keys + 1] = key
    end
  end
  if #keys == 0 then
    keys = DEFAULT_ORDER
  end
  return keys
end

local function normalizeView(view)
  local stateProbe = { choosingMonitor = false, currentView = view }
  local key = select(1, TomPageRegistry.resolve(view, stateProbe))
  key = tostring(key or "supervision")
  if key == "monitor_selection" then
    return "supervision"
  end
  if TAB_DEFINITIONS[key] then
    return key
  end
  return "supervision"
end

function M.resolveActiveView(state, fallbackView)
  local candidate = fallbackView
  if candidate == nil and type(state) == "table" then
    candidate = state.currentView
  end
  return normalizeView(candidate)
end

function M.getTabs(state)
  local active = M.resolveActiveView(state)
  local tabs = {}
  local order = resolveOrder()
  for _, key in ipairs(order) do
    local definition = cloneDefinition(key)
    if definition then
      definition.active = key == active
      tabs[#tabs + 1] = definition
    end
  end
  return tabs
end

function M.setActiveView(state, view, onNavigate)
  if type(state) ~= "table" then
    return false, "supervision"
  end
  local target = normalizeView(view)
  local previous = normalizeView(state.currentView)
  if previous == target then
    return false, target
  end
  state.currentView = target
  if type(onNavigate) == "function" then
    onNavigate(target, previous)
  end
  return true, target
end

function M.handleHotkey(state, key, onNavigate)
  local hotkey = string.lower(tostring(key or ""))
  local target = HOTKEY_TO_VIEW[hotkey]
  if not target then
    return false, nil
  end
  local changed, resolved = M.setActiveView(state, target, onNavigate)
  return changed, resolved
end

function M.buildButtonItems(state, palette, actions, opts)
  local options = type(opts) == "table" and opts or {}
  local useCompact = options.compact == true
  local tabs = M.getTabs(state)
  local items = {}
  for _, tab in ipairs(tabs) do
    local label = useCompact and (tab.compactLabel or tab.label) or tab.label
    local isActive = tab.active == true
    local setView = type(actions) == "table" and type(actions.setView) == "function" and actions.setView or nil
    items[#items + 1] = {
      id = tostring(tab.buttonId or ("view_" .. tab.key)),
      label = tostring(label or tab.key),
      bg = isActive and (palette.btnOn or colors.lime) or (palette.panelMid or colors.gray),
      action = function()
        if setView then
          setView(tab.key)
        else
          M.setActiveView(state, tab.key, options.onNavigate)
        end
      end,
      view = tab.key,
      compact = useCompact,
    }
  end
  return items
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

M.tabs = M.getTabs()

return M
