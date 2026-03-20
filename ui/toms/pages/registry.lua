local TomPageSupervision = require("ui.toms.pages.supervision")
local TomPageDiagnostic = require("ui.toms.pages.diagnostic")
local TomPageManual = require("ui.toms.pages.manual")
local TomPageInduction = require("ui.toms.pages.induction")
local TomPageUpdate = require("ui.toms.pages.update")
local TomPageConfig = require("ui.toms.pages.config")
local TomPageSetup = require("ui.toms.pages.setup")
local TomPageMonitorSelection = require("ui.toms.pages.monitor_selection")

local M = {}

local PAGE_RENDERERS = {
  supervision = TomPageSupervision.render,
  diagnostic = TomPageDiagnostic.render,
  manual = TomPageManual.render,
  induction = TomPageInduction.render,
  update = TomPageUpdate.render,
  config = TomPageConfig.render,
  setup = TomPageSetup.render,
  monitor_selection = TomPageMonitorSelection.render,
}

local ALIASES = {
  sup = "supervision",
  supervision = "supervision",
  diag = "diagnostic",
  diagnostics = "diagnostic",
  diagnostic = "diagnostic",
  man = "manual",
  manual = "manual",
  ind = "induction",
  induction = "induction",
  update = "update",
  cfg = "config",
  config = "config",
  setup = "setup",
}

M.order = {
  "supervision",
  "diagnostic",
  "manual",
  "induction",
  "update",
  "config",
  "setup",
}

local function normalizeViewKey(view)
  local raw = string.lower(tostring(view or "supervision"))
  return ALIASES[raw] or "supervision"
end

function M.resolve(view, state)
  if type(state) == "table" and state.choosingMonitor == true then
    return "monitor_selection", PAGE_RENDERERS.monitor_selection
  end
  local key = normalizeViewKey(view or (type(state) == "table" and state.currentView or nil))
  local renderer = PAGE_RENDERERS[key] or PAGE_RENDERERS.supervision
  return key, renderer
end

function M.render(view, state, pageContext)
  local key, renderer = M.resolve(view, state)
  if type(renderer) ~= "function" then
    return false, key
  end
  local ok = renderer(pageContext)
  if ok == false and key ~= "supervision" and type(PAGE_RENDERERS.supervision) == "function" then
    PAGE_RENDERERS.supervision(pageContext)
    return true, "supervision"
  end
  return ok ~= false, key
end

return M
