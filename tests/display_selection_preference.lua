-- tests/display_selection_preference.lua
-- Verifie la priorite de selection display et le diagnostic Tom.

local M = {}

function M.run(ctx)
  local fail = assert(ctx.fail, "ctx.fail requis")
  local ok = assert(ctx.ok, "ctx.ok requis")
  local toPath = assert(ctx.toPath, "ctx.toPath requis")

  local loadOk, IoDevices = pcall(dofile, toPath("io/devices.lua"))
  if not loadOk or type(IoDevices) ~= "table" then
    fail(90, "Chargement io/devices.lua impossible")
    return
  end

  local periphMap = {
    monitor_0 = {
      getSize = function() return 80, 40 end,
      setCursorPos = function() end,
      write = function() end,
      clear = function() end,
      setTextColor = function() end,
      setBackgroundColor = function() end,
    },
    tm_display_0 = {
      getSize = function() return 192, 108 end,
      fillRect = function() end,
      drawText = function() end,
      sync = function() end,
    },
  }

  local fakePeripheral = {
    getNames = function()
      return { "monitor_0", "tm_display_0" }
    end,
  }

  local function getTypeOf(name)
    if name == "monitor_0" then return "monitor" end
    if name == "tm_display_0" then return "tm_display" end
    return "unknown"
  end

  local function safePeripheral(name)
    return periphMap[name]
  end

  local candidates, diag = IoDevices.getMonitorCandidates(fakePeripheral, getTypeOf, safePeripheral, nil)
  if type(candidates) ~= "table" or #candidates < 2 then
    fail(91, "Liste de candidats display insuffisante")
    return
  end

  if candidates[1].backend ~= "toms_gpu" or candidates[1].name ~= "tm_display_0" then
    fail(92, "Le candidat Tom doit etre prioritaire")
  else
    ok("Priorite Tom backend valide")
  end

  if type(diag) ~= "table" or tonumber(diag.tomCandidates or 0) < 1 then
    fail(93, "Diagnostic Tom candidates invalide")
  else
    ok("Diagnostic Tom candidates valide")
  end

  local weakMap = {
    monitor_0 = periphMap.monitor_0,
    tm_display_weak = {
      getSize = function() return 120, 60 end,
      write = function() end,
    },
  }

  local fakePeripheralWeak = {
    getNames = function()
      return { "monitor_0", "tm_display_weak" }
    end,
  }

  local function getTypeWeak(name)
    if name == "monitor_0" then return "monitor" end
    if name == "tm_display_weak" then return "tm_display" end
    return "unknown"
  end

  local function safeWeak(name)
    return weakMap[name]
  end

  local weakCandidates, weakDiag = IoDevices.getMonitorCandidates(fakePeripheralWeak, getTypeWeak, safeWeak, nil)
  local hasTom = false
  for _, item in ipairs(weakCandidates or {}) do
    if item.backend == "toms_gpu" then
      hasTom = true
      break
    end
  end

  if hasTom then
    fail(94, "Un device Tom incomplet ne doit pas etre selectionne en toms_gpu")
  else
    ok("Rejet Tom incomplet valide")
  end

  if type(weakDiag) ~= "table" or tonumber(weakDiag.tomRejected or 0) < 1 then
    fail(95, "Le rejet Tom doit etre diagnostique")
  else
    ok("Diagnostic rejet Tom valide")
  end
end

return M
