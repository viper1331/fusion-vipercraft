-- tests/tom_renderer_engine.lua
-- Ensures the Tom renderer runs on multiple views and sizes without crashing.

local M = {}

function M.run(ctx)
  local fail = assert(ctx.fail, "ctx.fail required")
  local ok = assert(ctx.ok, "ctx.ok required")
  local toPath = assert(ctx.toPath, "ctx.toPath required")

  local originalRequire = _G.require
  _G.require = function(name)
    if name == "ui.tom_design" then
      return assert(dofile(toPath("ui/tom_design.lua")))
    end
    if name == "ui.tom_layout" then
      return assert(dofile(toPath("ui/tom_layout.lua")))
    end
    if name == "ui.tom_components" then
      return assert(dofile(toPath("ui/tom_components.lua")))
    end
    if type(originalRequire) == "function" then
      return originalRequire(name)
    end
    error("module not found: " .. tostring(name))
  end

  local loadOk, TomRenderer = pcall(dofile, toPath("ui/tom_renderer.lua"))
  _G.require = originalRequire
  if not loadOk or type(TomRenderer) ~= "table" or type(TomRenderer.build) ~= "function" then
    fail(182, "Cannot load ui/tom_renderer.lua")
    return
  end

  local writes = 0
  local buttonsBuilt = 0
  local buttonsDrawn = 0
  local ioDrawn = 0
  local legacyDraws = 0

  local state = {
    tick = 10,
    currentView = "supervision",
    safetyWarnings = { "IGNITION BLOCKED" },
    status = "READY",
    lastAction = "Renderer test",
    reactorPresent = true,
    reactorFormed = true,
    ignition = false,
    injectionRate = 98,
    injectionWritable = true,
    plasmaTemp = 295,
    caseTemp = 293,
    laserState = "READY",
    laserStatusText = "READY",
    laserPct = 73,
    laserEnergy = 2.5e9,
    laserMax = 5.0e9,
    laserThresholdRaw = 1.0e9,
    passiveGeneration = 1.2e7,
    steamProduction = 2400,
    hohlraumPresent = true,
    eventLog = { "001 ready", "000 boot" },
    alert = "INFO",
    tOpen = true,
    dtOpen = false,
    dOpen = true,
    energyKnown = true,
    energyPct = 44,
  }

  local renderer = TomRenderer.build({
    state = state,
    hw = { monitorName = "tm_gpu_test" },
    CFG = {},
    C = {
      bg = colors.black,
      panelDark = colors.black,
      panelMid = colors.gray,
      border = colors.lightBlue,
      borderDim = colors.blue,
      headerBg = colors.blue,
      headerText = colors.white,
      text = colors.white,
      dim = colors.lightGray,
      ok = colors.lime,
      warn = colors.orange,
      bad = colors.red,
      info = colors.cyan,
      energy = colors.yellow,
      tritium = colors.green,
      deuterium = colors.orange,
      dtFuel = colors.purple,
    },
    writeAt = function(_, _, text)
      writes = writes + #(tostring(text or ""))
    end,
    fillArea = function(_, _, w, h)
      writes = writes + math.max(0, (tonumber(w) or 0) * (tonumber(h) or 0))
    end,
    shortText = function(text, maxLen)
      text = tostring(text or "")
      maxLen = math.max(0, math.floor(tonumber(maxLen) or 0))
      if #text <= maxLen then return text end
      return text:sub(1, maxLen)
    end,
    formatTemperature = function(v)
      return string.format("%.1f C", tonumber(v) or 0)
    end,
    formatEnergy = function(v)
      return string.format("%.2f J", tonumber(v) or 0)
    end,
    formatEnergyPerTick = function(v)
      return string.format("%.2f J/t", tonumber(v) or 0)
    end,
    reactorPhase = function()
      return "READY"
    end,
    phaseColor = function()
      return colors.lime
    end,
    getRuntimeFuelMode = function()
      return "DT"
    end,
    isRuntimeFuelOk = function()
      return true
    end,
    buildButtons = function(layout)
      buttonsBuilt = buttonsBuilt + 1
      if type(layout) ~= "table" or type(layout.tom) ~= "table" then
        error("legacy layout missing tom payload")
      end
    end,
    drawButtons = function()
      buttonsDrawn = buttonsDrawn + 1
    end,
    getCurrentInputSource = function()
      return "terminal"
    end,
    drawReactorDiagram = function(_, _, w, h)
      writes = writes + math.max(1, (tonumber(w) or 1) * (tonumber(h) or 1))
    end,
    drawInductionDiagram = function(_, _, w, h)
      writes = writes + math.max(1, (tonumber(w) or 1) * (tonumber(h) or 1))
    end,
    drawMonitorSelection = function()
      legacyDraws = legacyDraws + 1
    end,
    drawDiagnosticView = function()
      legacyDraws = legacyDraws + 1
    end,
    drawUpdateView = function()
      legacyDraws = legacyDraws + 1
    end,
    drawConfigView = function()
      legacyDraws = legacyDraws + 1
    end,
    drawSetupView = function()
      legacyDraws = legacyDraws + 1
    end,
    drawIoPanel = function(bounds)
      ioDrawn = ioDrawn + 1
      if type(bounds) ~= "table" or (bounds.w or 0) < 1 then
        error("invalid io bounds")
      end
    end,
  })

  local cases = {
    { view = "supervision", w = 92, h = 30 },
    { view = "manual", w = 108, h = 34 },
    { view = "induction", w = 124, h = 38 },
    { view = "diagnostic", w = 124, h = 38 },
    { view = "update", w = 124, h = 38 },
    { view = "config", w = 124, h = 38 },
    { view = "setup", w = 124, h = 38 },
  }

  for _, item in ipairs(cases) do
    state.currentView = item.view
    local okRender, errRender = pcall(renderer.render, "terminal", term.current(), item.w, item.h)
    if not okRender then
      fail(183, "Tom renderer crashed on " .. item.view .. ": " .. tostring(errRender))
      return
    end
  end

  if writes <= 0 then
    fail(184, "Tom renderer produced no drawing output")
    return
  end
  if buttonsBuilt <= 0 or buttonsDrawn <= 0 then
    fail(185, "Tom renderer did not build/draw buttons")
    return
  end
  if ioDrawn <= 0 then
    fail(186, "Tom renderer did not draw IO panel")
    return
  end
  if legacyDraws <= 0 then
    fail(187, "Tom renderer did not use legacy fallback views")
    return
  end
  if type(state.controlBounds) ~= "table" then
    fail(188, "Tom renderer did not set control bounds")
    return
  end

  ok("Tom renderer adaptive pass OK")
end

return M
