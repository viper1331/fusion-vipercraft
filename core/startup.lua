-- core/startup.lua
-- Sequence de demarrage runtime.

local M = {}

function M.run(api)
  local state = api.state

  local ensureConfigOrInstaller = api.ensureConfigOrInstaller
  local restoreTerm = api.restoreTerm
  local applyPremiumPalette = api.applyPremiumPalette
  local readLocalVersionFile = api.readLocalVersionFile
  local setupMonitor = api.setupMonitor
  local refreshAll = api.refreshAll
  local pushEvent = api.pushEvent

  local UPDATE_ENABLED = api.UPDATE_ENABLED
  local checkForUpdate = api.checkForUpdate

  local configOk = ensureConfigOrInstaller()
  if not configOk then
    restoreTerm()
    return false
  end

  applyPremiumPalette()
  state.update.localVersion = readLocalVersionFile()
  setupMonitor()
  refreshAll()
  state.status = "READY"
  pushEvent("System ready")

  if UPDATE_ENABLED then
    local ok, err = pcall(checkForUpdate)
    if not ok then
      state.update.status = "FAILED"
      state.update.lastCheckResult = "Startup check failed"
      state.update.lastError = tostring(err)
      state.update.httpStatus = "FAIL"
      pushEvent("Update failed")
    end
  end

  return true
end

return M
