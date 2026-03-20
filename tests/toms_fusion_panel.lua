-- tests/toms_fusion_panel.lua
-- Smoke test for the rebuilt Tom fusion panel renderer.

local M = {}

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
    fail(180, "Cannot load ui/toms/fusion_panel.lua")
    return
  end

  local counters = {
    buildButtons = 0,
    drawButtons = 0,
    legacy = 0,
    monitorSelection = 0,
  }

  local state = {
    tick = 12,
    currentView = "supervision",
    safetyWarnings = { "IGNITION BLOCKED" },
    status = "READY",
    lastAction = "none",
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
    laserThresholdRaw = 1.0e9,
    passiveGeneration = 1.2e7,
    steamProduction = 900,
    hohlraumPresent = true,
    fuelFlowMbT = 98,
    energyKnown = true,
    energyPct = 44,
    tOpen = true,
    dtOpen = false,
    dOpen = true,
    ignitionBlockers = {},
    choosingMonitor = false,
  }

  local function newMockTerm(w, h)
    local tw = math.max(1, math.floor(tonumber(w) or 1))
    local th = math.max(1, math.floor(tonumber(h) or 1))
    local cx, cy = 1, 1
    local tc, bc = colors.white, colors.black
    local blink = false
    return {
      getSize = function()
        return tw, th
      end,
      setCursorPos = function(x, y)
        cx = math.floor(tonumber(x) or cx)
        cy = math.floor(tonumber(y) or cy)
      end,
      getCursorPos = function()
        return cx, cy
      end,
      write = function(_) end,
      blit = function(_) end,
      clear = function() end,
      clearLine = function() end,
      setTextColor = function(color)
        tc = tonumber(color) or tc
      end,
      setTextColour = function(color)
        tc = tonumber(color) or tc
      end,
      setBackgroundColor = function(color)
        bc = tonumber(color) or bc
      end,
      setBackgroundColour = function(color)
        bc = tonumber(color) or bc
      end,
      getTextColor = function()
        return tc
      end,
      getBackgroundColor = function()
        return bc
      end,
      setCursorBlink = function(enabled)
        blink = not not enabled
      end,
      getCursorBlink = function()
        return blink
      end,
      isColor = function()
        return true
      end,
      isColour = function()
        return true
      end,
    }
  end

  local function fakeWindowSurface()
    return {
      createWindow = function(x, y, w, h)
        return newMockTerm(w, h)
      end,
    }
  end

  local renderer = Panel.build({
    state = state,
    hw = { monitorName = "tm_gpu_test" },
    C = {
      ok = colors.lime,
      warn = colors.orange,
      bad = colors.red,
      info = colors.cyan,
      dim = colors.lightGray,
    },
    reactorPhase = function()
      return "RUNNING / DT"
    end,
    phaseColor = function()
      return colors.lime
    end,
    formatTemperature = function(value)
      return string.format("%.1f C", tonumber(value) or 0)
    end,
    formatEnergy = function(value)
      return string.format("%.2f J", tonumber(value) or 0)
    end,
    formatEnergyPerTick = function(value)
      return string.format("%.2f J/t", tonumber(value) or 0)
    end,
    getRuntimeFuelMode = function()
      return "DT"
    end,
    buildButtons = function(layout)
      counters.buildButtons = counters.buildButtons + 1
      if type(layout) ~= "table" or type(layout.right) ~= "table" then
        error("Invalid legacy layout for buttons")
      end
    end,
    drawButtons = function()
      counters.drawButtons = counters.drawButtons + 1
    end,
    getCurrentInputSource = function()
      return "monitor"
    end,
    drawMonitorSelection = function()
      counters.monitorSelection = counters.monitorSelection + 1
    end,
    drawDiagnosticView = function() counters.legacy = counters.legacy + 1 end,
    drawUpdateView = function() counters.legacy = counters.legacy + 1 end,
    drawConfigView = function() counters.legacy = counters.legacy + 1 end,
    drawSetupView = function() counters.legacy = counters.legacy + 1 end,
  })

  local cases = {
    { source = "terminal", view = "supervision", w = 92, h = 30 },
    { source = "monitor", view = "manual", w = 128, h = 38 },
    { source = "monitor", view = "induction", w = 140, h = 42 },
    { source = "monitor", view = "diagnostic", w = 128, h = 38 },
    { source = "monitor", view = "update", w = 128, h = 38 },
    { source = "monitor", view = "setup", w = 128, h = 38 },
    { source = "monitor", view = "config", w = 120, h = 36 },
  }

  for _, item in ipairs(cases) do
    state.currentView = item.view
    state.choosingMonitor = false
    local prev = term.current()
    local rootMock = newMockTerm(item.w, item.h)
    term.redirect(rootMock)
    local okRender, err = pcall(renderer.render, item.source, fakeWindowSurface(), item.w, item.h)
    term.redirect(prev)
    if not okRender then
      fail(181, "Renderer crash on view " .. tostring(item.view) .. ": " .. tostring(err))
      return
    end
  end

  state.choosingMonitor = true
  local prev = term.current()
  term.redirect(newMockTerm(120, 36))
  local okSelection, errSelection = pcall(renderer.render, "monitor", fakeWindowSurface(), 120, 36)
  term.redirect(prev)
  if not okSelection then
    fail(182, "Renderer crash in monitor selection mode: " .. tostring(errSelection))
    return
  end

  if counters.buildButtons <= 0 or counters.drawButtons <= 0 then
    fail(183, "Renderer did not build/draw control buttons")
    return
  end
  if counters.legacy ~= 0 then
    fail(184, "Renderer should not route legacy views in Tom native mode")
    return
  end
  if counters.monitorSelection ~= 0 then
    fail(185, "Renderer should render monitor selection in Tom native mode without legacy callback")
    return
  end
  if type(state.controlBounds) ~= "table" then
    fail(186, "Renderer did not define control bounds")
    return
  end

  ok("Tom fusion panel v2 renderer pass OK")
end

return M
