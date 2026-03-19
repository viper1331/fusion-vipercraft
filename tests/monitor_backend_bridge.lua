-- tests/monitor_backend_bridge.lua
-- Verifie le pont backend->kind dans io/monitor.lua.

local M = {}

function M.run(ctx)
  local fail = assert(ctx.fail, "ctx.fail requis")
  local ok = assert(ctx.ok, "ctx.ok requis")
  local toPath = assert(ctx.toPath, "ctx.toPath requis")

  local loadOk, IoMonitor = pcall(dofile, toPath("io/monitor.lua"))
  if not loadOk or type(IoMonitor) ~= "table" then
    fail(96, "Chargement io/monitor.lua impossible")
    return
  end

  local gpu = {
    getResolution = function() return 192, 108 end,
    fillRect = function() end,
    drawText = function() end,
    sync = function() end,
  }

  local hw = {
    monitor = gpu,
    monitorName = "tm_gpu_any",
  }
  local cfg = {
    displayOutput = "both",
    monitorScale = 1.0,
  }
  local palette = {
    bg = colors.black,
    text = colors.white,
  }

  local chosen = {
    name = "tm_gpu_any",
    obj = gpu,
    backend = "toms_gpu", -- simulant le format produit par io/devices.lua
    touchEvent = "tm_monitor_touch",
    w = 16,
    h = 8,
  }

  local originalRedirect = term.redirect
  local originalSetCursorBlink = term.setCursorBlink
  term.redirect = function(target)
    return target
  end
  term.setCursorBlink = function() end

  local okSetup, err = pcall(IoMonitor.setupMonitor, term.current(), hw, cfg, palette, chosen, function()
    return "tm_gpu"
  end, nil)

  term.redirect = originalRedirect
  term.setCursorBlink = originalSetCursorBlink
  if not okSetup then
    fail(97, "setupMonitor a plante: " .. tostring(err))
    return
  end

  if hw.monitorBackend ~= "toms_gpu" then
    fail(98, "backend attendu toms_gpu, obtenu: " .. tostring(hw.monitorBackend))
  else
    ok("Pont backend->kind monitor valide")
  end

  if type(hw.displaySurface) ~= "table"
    or type(hw.displaySurface.setBackgroundColor) ~= "function"
    or type(hw.displaySurface.setTextColor) ~= "function"
    or type(hw.displaySurface.clear) ~= "function" then
    fail(99, "Surface Tom term-compat non initialisee")
  else
    ok("Surface Tom active et compatible")
  end
end

return M
