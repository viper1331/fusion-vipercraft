-- tests/toms_native_surface_pipeline.lua
-- Verifies Tom debug pipeline keeps native GPU dimensions/source metadata.

local M = {}

local function makeNativeTomSurface(width, height)
  local syncCount = 0
  local drawOps = 0
  local w = math.max(1, math.floor(tonumber(width) or 1))
  local h = math.max(1, math.floor(tonumber(height) or 1))

  local surface = {}

  function surface.getResolution()
    return w, h
  end

  function surface.getSize()
    return w, h
  end

  function surface.filledRectangle()
    drawOps = drawOps + 1
    return true
  end

  function surface.fillRect()
    drawOps = drawOps + 1
    return true
  end

  function surface.drawText()
    drawOps = drawOps + 1
    return true
  end

  function surface.drawString()
    drawOps = drawOps + 1
    return true
  end

  function surface.sync()
    syncCount = syncCount + 1
    return true
  end

  function surface.getStats()
    return {
      syncCount = syncCount,
      drawOps = drawOps,
    }
  end

  return surface
end

function M.run(ctx)
  local fail = assert(ctx.fail, "ctx.fail required")
  local ok = assert(ctx.ok, "ctx.ok required")
  local toPath = assert(ctx.toPath, "ctx.toPath required")

  local originalRequire = _G.require
  _G.require = function(name)
    if name == "ui.toms.theme" then
      return assert(dofile(toPath("ui/toms/theme.lua")))
    end
    if name == "ui.toms.layout" then
      return assert(dofile(toPath("ui/toms/layout.lua")))
    end
    if name == "ui.toms.components" then
      return assert(dofile(toPath("ui/toms/components.lua")))
    end
    if type(originalRequire) == "function" then
      return originalRequire(name)
    end
    error("module not found: " .. tostring(name))
  end

  local loadOk, Panel = pcall(dofile, toPath("ui/toms/fusion_panel.lua"))
  _G.require = originalRequire
  if not loadOk or type(Panel) ~= "table" or type(Panel.build) ~= "function" then
    fail(204, "Cannot load ui/toms/fusion_panel.lua for native surface pipeline test")
    return
  end

  local debugFilePath = toPath("logs/toms_debug.txt")
  if fs.exists(debugFilePath) and not fs.isDir(debugFilePath) then
    pcall(fs.delete, debugFilePath)
  end

  local state = {
    tick = 1,
    currentView = "supervision",
    tomUiDiagnosticMode = true,
    safetyWarnings = {},
    eventLog = {},
    ignitionBlockers = {},
    status = "READY",
    lastAction = "none",
    reactorPresent = true,
    reactorFormed = true,
    ignition = false,
    injectionRate = 50,
    injectionWritable = true,
    plasmaTemp = 295,
    caseTemp = 293,
    laserState = "READY",
    laserStatusText = "READY",
    laserPct = 73,
    laserEnergy = 2.0e9,
    laserMax = 2.5e9,
    laserThresholdRaw = 1.0e9,
    passiveGeneration = 3.2e6,
    steamProduction = 128,
    hohlraumPresent = true,
    fuelFlowMbT = 50,
    energyKnown = true,
    energyPct = 44,
    tOpen = true,
    dtOpen = false,
    dOpen = true,
    choosingMonitor = false,
  }

  local renderer = Panel.build({
    state = state,
    hw = { monitorName = "tm_gpu_1", monitorBackend = "toms_gpu" },
    CFG = { allowControl = false },
    C = { ok = colors.lime, warn = colors.orange, bad = colors.red, info = colors.cyan, dim = colors.lightGray },
    reactorPhase = function() return "RUNNING / DT" end,
    phaseColor = function() return colors.lime end,
    formatTemperature = function(value) return string.format("%.1f C", tonumber(value) or 0) end,
    formatEnergy = function(value) return string.format("%.2f FE", tonumber(value) or 0) end,
    formatEnergyPerTick = function(value) return string.format("%.2f FE/t", tonumber(value) or 0) end,
    getRuntimeFuelMode = function() return "DT" end,
    buildButtons = function() end,
    drawButtons = function() end,
    getCurrentInputSource = function() return "monitor" end,
    drawIoPanel = function() end,
    log = {},
  })

  local nativeSurface = makeNativeTomSurface(448, 384)
  local renderCtx = {
    backend = "toms_gpu",
    inputSource = "monitor",
    renderSource = "toms_gpu",
    displaySurface = {},
    nativeSurface = nativeSurface,
    displayWidth = 74,
    displayHeight = 76,
    nativeWidth = 448,
    nativeHeight = 384,
    useNativeDebug = true,
    sourcePath = "test.native.pipeline",
    wrappedPath = "test.surface.wrapper",
    termRedirectTarget = "monitor",
  }

  local okRender, errRender = pcall(renderer.render, "monitor", nativeSurface, 448, 384, renderCtx)
  if not okRender then
    fail(205, "Native diagnostic render crashed: " .. tostring(errRender))
    return
  end

  local stats = nativeSurface.getStats()
  if (tonumber(stats.drawOps) or 0) <= 0 then
    fail(206, "Native diagnostic render did not draw on native Tom surface")
    return
  end
  if (tonumber(stats.syncCount) or 0) <= 0 then
    fail(207, "Native diagnostic render did not sync native Tom surface")
    return
  end

  if not fs.exists(debugFilePath) or fs.isDir(debugFilePath) then
    fail(208, "Native diagnostic render did not create logs/toms_debug.txt")
    return
  end
  local handle = fs.open(debugFilePath, "r")
  if not handle then
    fail(209, "Cannot read logs/toms_debug.txt after native diagnostic render")
    return
  end
  local body = handle.readAll() or ""
  handle.close()

  if not string.find(body, "Runtime source%s+toms_gpu") then
    fail(210, "Debug report runtime source is not toms_gpu")
    return
  end
  if not string.find(body, "Runtime dimensions%s+448x384") then
    fail(211, "Debug report runtime dimensions are not 448x384")
    return
  end
  if not string.find(body, "Display dimensions%s+74x76") then
    fail(212, "Debug report missing wrapped display dimensions 74x76")
    return
  end
  if not string.find(body, "Native dimensions%s+448x384") then
    fail(213, "Debug report missing native dimensions 448x384")
    return
  end
  if not string.find(body, "Render type%s+TOM_DIRECT_NO_WINDOWS") then
    fail(214, "Debug report render type mismatch for native debug mode")
    return
  end

  ok("Tom native diagnostic pipeline keeps native source/dimensions")
end

return M
