-- tests/toms_diagnostic_mode.lua
-- Verifies internal Tom diagnostic mode uses direct draw without createWindow.

local M = {}

local function newBufferTerm(w, h)
  local tw = math.max(1, math.floor(tonumber(w) or 1))
  local th = math.max(1, math.floor(tonumber(h) or 1))
  local cx, cy = 1, 1
  local rows = {}
  for y = 1, th do
    rows[y] = string.rep(" ", tw)
  end

  local function writeAt(x, y, text)
    if y < 1 or y > th then return end
    local line = rows[y]
    if x < 1 then
      local cut = 1 - x
      if cut >= #text then return end
      text = text:sub(cut + 1)
      x = 1
    end
    if x > tw then return end
    if x + #text - 1 > tw then
      text = text:sub(1, tw - x + 1)
    end
    if #text == 0 then return end
    rows[y] = line:sub(1, x - 1) .. text .. line:sub(x + #text)
  end

  return {
    getSize = function() return tw, th end,
    setCursorPos = function(x, y)
      cx = math.floor(tonumber(x) or cx)
      cy = math.floor(tonumber(y) or cy)
    end,
    getCursorPos = function() return cx, cy end,
    write = function(text) writeAt(cx, cy, tostring(text or "")) end,
    blit = function(text) writeAt(cx, cy, tostring(text or "")) end,
    clear = function()
      for y = 1, th do rows[y] = string.rep(" ", tw) end
    end,
    clearLine = function() rows[cy] = string.rep(" ", tw) end,
    setTextColor = function() end,
    setTextColour = function() end,
    setBackgroundColor = function() end,
    setBackgroundColour = function() end,
    isColor = function() return true end,
    isColour = function() return true end,
    setCursorBlink = function() end,
    dump = function()
      return table.concat(rows, "\n")
    end,
  }
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
    if name == "ui.toms.pages.common" then
      return assert(dofile(toPath("ui/toms/pages/common.lua")))
    end
    if name == "ui.toms.pages.supervision" then
      return assert(dofile(toPath("ui/toms/pages/supervision.lua")))
    end
    if name == "ui.toms.pages.diagnostic" then
      return assert(dofile(toPath("ui/toms/pages/diagnostic.lua")))
    end
    if name == "ui.toms.pages.manual" then
      return assert(dofile(toPath("ui/toms/pages/manual.lua")))
    end
    if name == "ui.toms.pages.induction" then
      return assert(dofile(toPath("ui/toms/pages/induction.lua")))
    end
    if name == "ui.toms.pages.update" then
      return assert(dofile(toPath("ui/toms/pages/update.lua")))
    end
    if name == "ui.toms.pages.config" then
      return assert(dofile(toPath("ui/toms/pages/config.lua")))
    end
    if name == "ui.toms.pages.setup" then
      return assert(dofile(toPath("ui/toms/pages/setup.lua")))
    end
    if name == "ui.toms.pages.monitor_selection" then
      return assert(dofile(toPath("ui/toms/pages/monitor_selection.lua")))
    end
    if type(originalRequire) == "function" then
      return originalRequire(name)
    end
    error("module not found: " .. tostring(name))
  end

  local loadOk, Panel = pcall(dofile, toPath("ui/toms/fusion_panel.lua"))
  _G.require = originalRequire
  if not loadOk or type(Panel) ~= "table" or type(Panel.build) ~= "function" then
    fail(191, "Cannot load ui/toms/fusion_panel.lua for diagnostic mode test")
    return
  end

  local createWindowCalls = 0
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
    laserPct = 77,
    laserEnergy = 2.0e9,
    laserMax = 2.5e9,
    laserThresholdRaw = 1.0e9,
    passiveGeneration = 3.2e6,
    steamProduction = 128,
    hohlraumPresent = true,
    fuelFlowMbT = 50,
    energyKnown = true,
    energyPct = 41,
    tOpen = true,
    dtOpen = false,
    dOpen = true,
    choosingMonitor = false,
  }

  local surface = {
    createWindow = function()
      createWindowCalls = createWindowCalls + 1
      return newBufferTerm(20, 10)
    end,
  }

  local root = newBufferTerm(120, 36)
  local renderer = Panel.build({
    state = state,
    hw = { monitorName = "tm_gpu_diag", monitorBackend = "toms_gpu" },
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

  local prev = term.current()
  term.redirect(root)
  local okRender, errRender = pcall(renderer.render, "monitor", surface, 120, 36)
  term.redirect(prev)
  if not okRender then
    fail(192, "Diagnostic render crashed: " .. tostring(errRender))
    return
  end
  if createWindowCalls ~= 0 then
    fail(193, "Diagnostic mode must not use createWindow")
    return
  end
  if type(state.controlBounds) ~= "table" then
    fail(194, "Diagnostic mode did not expose control bounds")
    return
  end

  local dump = root.dump()
  if not string.find(dump, "TOMS DEBUG MODE", 1, true) then
    fail(195, "Diagnostic title not rendered")
    return
  end
  if not string.find(dump, "RENDER TOM_DIRECT_NO_WINDOWS", 1, true) then
    fail(196, "Diagnostic render type line missing")
    return
  end
  if not string.find(dump, "GPU 120x36", 1, true) then
    fail(197, "Diagnostic GPU size line missing")
    return
  end
  if not string.find(dump, "DEBUG FILE: logs/toms_debug.txt", 1, true) then
    fail(198, "Diagnostic debug file path line missing")
    return
  end
  if not fs.exists(debugFilePath) or fs.isDir(debugFilePath) then
    fail(199, "Diagnostic mode did not create logs/toms_debug.txt")
    return
  end
  local handle = fs.open(debugFilePath, "r")
  if not handle then
    fail(200, "Cannot read logs/toms_debug.txt")
    return
  end
  local debugBody = handle.readAll() or ""
  handle.close()
  if not string.find(debugBody, "TOMS DEBUG RUNTIME REPORT", 1, true) then
    fail(201, "Debug report header missing in logs/toms_debug.txt")
    return
  end
  if not string.find(debugBody, "Selected GPU", 1, true) then
    fail(202, "Debug report missing selected GPU section")
    return
  end
  if not string.find(debugBody, "BYPASS CONFIRMATION", 1, true) then
    fail(203, "Debug report missing bypass section")
    return
  end

  ok("Tom diagnostic mode uses direct internal pipeline")
end

return M
