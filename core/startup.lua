-- core/startup.lua
-- Sequence de demarrage runtime.

local M = {}

function M.run(api)
  local state = api.state
  local log = api.log or {}
  local logInfo = type(log.info) == "function" and log.info or function() end
  local logWarn = type(log.warn) == "function" and log.warn or function() end
  local logError = type(log.error) == "function" and log.error or function() end

  local ensureConfigOrInstaller = api.ensureConfigOrInstaller
  local restoreTerm = api.restoreTerm
  local applyPremiumPalette = api.applyPremiumPalette
  local readLocalVersionFile = api.readLocalVersionFile
  local setupMonitor = api.setupMonitor
  local refreshAll = api.refreshAll
  local pushEvent = api.pushEvent

  local UPDATE_ENABLED = api.UPDATE_ENABLED
  local checkForUpdate = api.checkForUpdate

  logInfo("Startup sequence begin")

  local configOk = ensureConfigOrInstaller()
  if not configOk then
    logWarn("Startup stopped: configuration missing or invalid")
    restoreTerm()
    return false
  end

  applyPremiumPalette()
  state.update.localVersion = readLocalVersionFile()
  setupMonitor()
  refreshAll()
  state.status = "READY"
  pushEvent("System ready")
  logInfo("Startup completed", { status = state.status })

  if UPDATE_ENABLED then
    local ok, err = pcall(checkForUpdate)
    if not ok then
      state.update.status = "FAILED"
      state.update.lastCheckResult = "Startup check failed"
      state.update.lastError = tostring(err)
      state.update.httpStatus = "FAIL"
      pushEvent("Update failed")
      logError("Startup update check failed", { err = tostring(err) })
    end
  end

  return true
end

return M
