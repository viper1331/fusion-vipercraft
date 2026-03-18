-- tests/responsive_render.lua
-- Validation de robustesse responsive pour les couches UI.
-- Objectif: verifier que le rendu ne plante pas sur plusieurs tailles.

local M = {}

local function shortText(text, maxLen)
  text = tostring(text or "")
  if #text <= maxLen then return text end
  if maxLen <= 0 then return "" end
  return text:sub(1, maxLen)
end

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

function M.run(ctx)
  local fail = assert(ctx.fail, "ctx.fail requis")
  local ok = assert(ctx.ok, "ctx.ok requis")
  local toPath = assert(ctx.toPath, "ctx.toPath requis")

  local loadComponentsOk, UIComponents = pcall(dofile, toPath("ui/components.lua"))
  if not loadComponentsOk or type(UIComponents) ~= "table" then
    fail(109, "Chargement ui/components.lua impossible")
    return
  end

  local originalRequire = require
  _G.require = function(name)
    if name == "ui.components" then
      return UIComponents
    end
    return originalRequire(name)
  end

  local loadViewsOk, Views = pcall(dofile, toPath("ui/views.lua"))
  _G.require = originalRequire
  local loadChromeOk, Chrome = pcall(dofile, toPath("ui/chrome.lua"))
  local loadReactorOk, ReactorDiagram = pcall(dofile, toPath("ui/reactor_diagram.lua"))
  local loadInductionOk, InductionDiagram = pcall(dofile, toPath("ui/induction_diagram.lua"))

  if not loadViewsOk or type(Views) ~= "table" then
    fail(110, "Chargement ui/views.lua impossible")
    return
  end
  if not loadChromeOk or type(Chrome) ~= "table" then
    fail(111, "Chargement ui/chrome.lua impossible")
    return
  end
  if not loadReactorOk or type(ReactorDiagram) ~= "table" then
    fail(112, "Chargement ui/reactor_diagram.lua impossible")
    return
  end
  if not loadInductionOk or type(InductionDiagram) ~= "table" then
    fail(113, "Chargement ui/induction_diagram.lua impossible")
    return
  end

  local writes = 0
  local C = {
    bg = colors.white,
    panel = colors.lightGray,
    panelDark = colors.white,
    panelMid = colors.lightGray,
    text = colors.black,
    dim = colors.gray,
    ok = colors.green,
    warn = colors.orange,
    bad = colors.red,
    info = colors.cyan,
    border = colors.cyan,
    borderDim = colors.lightBlue,
    energy = colors.yellow,
    tritium = colors.green,
    deuterium = colors.orange,
    dtFuel = colors.purple,
    headerBg = colors.lightGray,
    footerBg = colors.lightGray,
    headerText = colors.black,
  }

  local state = {
    tick = 12,
    currentView = "supervision",
    lastAction = "Responsive test",
    alert = "NONE",
    eventLog = { "001 test", "000 boot" },
    safetyWarnings = {},
    ignitionChecklist = {
      { key = "LAS >= 800MFE", ok = true },
      { key = "T LOCK OPEN", ok = false },
    },

    reactorPresent = true,
    reactorFormed = true,
    ignition = false,
    ignitionSequencePending = false,
    plasmaTemp = 350,
    caseTemp = 305,
    tOpen = true,
    dOpen = false,
    dtOpen = false,
    hohlraumPresent = true,
    laserState = "READY",
    laserStatusText = "READY",
    laserPct = 100,
    laserDetectedCount = 3,
    laserLineOn = false,
    lastLaserPulseAt = -1,

    energyKnown = true,
    energyPct = 44,
    deuteriumAmount = 2000000,
    tritiumAmount = 3000000,

    update = {
      localVersion = "2.4.21",
      remoteVersion = "2.4.21",
      manifestLoaded = true,
      filesToUpdate = 0,
      status = "UP TO DATE",
      available = false,
      httpStatus = "OK",
      lastError = "",
      lastCheckResult = "OK",
      lastApplyResult = "N/A",
      lastManifestError = "",
      restartRequired = false,
    },

    setup = {
      dirty = false,
      saveStatus = "CONFIG SAVED",
      lastMessage = "Ready",
      working = {
        monitor = { name = "monitor_0", ok = true, scale = 0.5 },
        devices = {
          reactorController = "fusion_reactor_controller_0",
          logicAdapter = "fusion_reactor_logic_adapter_0",
          laser = "laser_amplifier_0",
          induction = "induction_port_0",
        },
        relays = {
          laser = { name = "redstone_relay_0", side = "top" },
          tritium = { name = "redstone_relay_1", side = "front" },
          deuterium = { name = "redstone_relay_2", side = "front" },
        },
        readers = {
          tritium = "block_reader_2",
          deuterium = "block_reader_1",
          aux = "block_reader_6",
        },
        ui = { preferredView = "SUP", output = "both", energyUnit = "j", laserCount = 3, scale = 1.0 },
      },
      deviceStatus = {
        reactorController = "OK",
        logicAdapter = "OK",
        laser = "OK",
        induction = "OK",
        relayLaser = "OK",
        relayTritium = "OK",
        relayDeuterium = "OK",
        readerTritium = "OK",
        readerDeuterium = "OK",
        readerAux = "OK",
      },
    },

    inductionPresent = true,
    inductionFormed = true,
    inductionPct = 55.1,
    inductionEnergy = 2.4e12,
    inductionMax = 4.8e12,
    inductionNeeded = 2.4e12,
    inductionInput = 1.2e9,
    inductionOutput = 8.0e8,
    inductionTransferCap = 2.0e9,
    inductionPortMode = "BIDIR",
    inductionCells = 64,
    inductionProviders = 8,
    inductionLength = 7,
    inductionWidth = 7,
    inductionHeight = 9,
  }

  local hw = {
    monitorName = "monitor_0",
    readerRoles = {
      tritium = { name = "block_reader_2" },
      deuterium = { name = "block_reader_1" },
      inventory = { name = "block_reader_6" },
    },
    relays = {
      redstone_relay_0 = true,
      redstone_relay_1 = true,
      redstone_relay_2 = true,
    },
    reactor = {},
    logic = {},
    laser = {},
    induction = {},
    reactorName = "fusion_reactor_controller_0",
    logicName = "fusion_reactor_logic_adapter_0",
    laserName = "laser_amplifier_0",
    inductionName = "induction_port_0",
  }

  local function drawBox(_, _, _, _, _, _)
    writes = writes + 1
  end

  local function writeAt(_, _, text)
    writes = writes + #(tostring(text or ""))
  end

  local function drawKeyValue(_, _, _, _, _, _, _)
    writes = writes + 1
  end

  local function drawBadge(_, _, _, _, _)
    writes = writes + 1
  end

  local baseCtx = {
    C = C,
    state = state,
    hw = hw,
    CFG = {
      uiScale = 1.0,
      monitorScale = 0.5,
      displayOutput = "both",
      energyUnit = "j",
      laserCount = 3,
      actions = {
        laser_charge = { relay = "redstone_relay_0", side = "top" },
        tritium = { relay = "redstone_relay_1", side = "front" },
        deuterium = { relay = "redstone_relay_2", side = "front" },
      },
    },
    fs = fs,
    UPDATE_ENABLED = true,
    UPDATE_TEMP_DIR = ".tmp_update",
    UPDATE_MISSING_BACKUP_SUFFIX = ".bak.missing",
    drawBox = drawBox,
    writeAt = writeAt,
    drawKeyValue = drawKeyValue,
    drawBadge = drawBadge,
    shortText = shortText,
    clamp = clamp,
    fmt = function(v) return tostring(v) end,
    formatTemperature = function(v) return string.format("%.1f C", tonumber(v) or 0) end,
    formatEnergy = function(v) return string.format("%.2f J", tonumber(v) or 0) end,
    formatEnergyPerTick = function(v) return string.format("%.2f J/t", tonumber(v) or 0) end,
    formatMJ = function(v) return string.format("%.2f J", tonumber(v) or 0) end,
    yesno = function(v) return v and "ON" or "OFF" end,
    reactorPhase = function() return "READY" end,
    phaseColor = function() return C.ok end,
    getRuntimeFuelMode = function() return "FLOW" end,
    isRuntimeFuelOk = function() return true end,
    statusColor = function() return C.info end,
    drawHeader = function() writes = writes + 1 end,
    drawFooter = function() writes = writes + 1 end,
    buildButtons = function() end,
    drawButtons = function() writes = writes + 1 end,
    getCurrentInputSource = function() return "terminal" end,
    drawControlPanel = function() writes = writes + 1 end,
    drawReactorDiagram = function() writes = writes + 1 end,
    drawInductionDiagram = function() writes = writes + 1 end,
    inductionStatus = function() return "ONLINE", C.ok end,
    hasAnyRollbackBackup = function() return false end,
    rollbackTargetList = function() return {} end,
    getSetupStatusRows = function()
      return {
        { role = "Laser", name = "laser_amplifier_0", status = "OK" },
        { role = "Relay T", name = "redstone_relay_1", status = "OK" },
        { role = "Reader D", name = "block_reader_1", status = "OK" },
      }
    end,
  }

  local viewCtx = Views.buildContext(baseCtx)
  local layouts = {
    compact = {
      mode = "compact",
      left = { x = 1, y = 2, w = 20, h = 14 },
      right = { x = 22, y = 2, w = 18, h = 14 },
      top = 2,
      bottom = 15,
      width = 40,
      height = 14,
    },
    compactStack = {
      mode = "compact",
      left = { x = 1, y = 2, w = 52, h = 8 },
      center = { x = 1, y = 11, w = 52, h = 9 },
      right = { x = 1, y = 21, w = 52, h = 8 },
      top = 2,
      bottom = 28,
      width = 52,
      height = 27,
      stack = true,
    },
    standard = {
      mode = "standard",
      left = { x = 1, y = 2, w = 24, h = 28 },
      center = { x = 27, y = 2, w = 48, h = 28 },
      right = { x = 77, y = 2, w = 22, h = 28 },
      top = 2,
      bottom = 29,
      width = 99,
      height = 28,
    },
  }

  local viewChecks = {
    { name = "SUP compact", fn = function() Views.drawSupervisionView(viewCtx, layouts.compact) end },
    { name = "SUP compact stack", fn = function() Views.drawSupervisionView(viewCtx, layouts.compactStack) end },
    { name = "SUP standard", fn = function() Views.drawSupervisionView(viewCtx, layouts.standard) end },
    { name = "IND compact", fn = function() Views.drawInductionView(viewCtx, layouts.compact) end },
    { name = "IND standard", fn = function() Views.drawInductionView(viewCtx, layouts.standard) end },
    { name = "DIAG standard", fn = function() Views.drawDiagnosticView(viewCtx, layouts.standard) end },
    { name = "CFG standard", fn = function() Views.drawConfigView(viewCtx, layouts.standard) end },
    { name = "SETUP standard", fn = function() Views.drawSetupView(viewCtx, layouts.standard) end },
    { name = "UPDATE standard", fn = function() Views.drawUpdateView(viewCtx, layouts.standard) end },
  }

  for _, check in ipairs(viewChecks) do
    local okDraw, errDraw = pcall(check.fn)
    if not okDraw then
      fail(114, "Vue responsive en erreur: " .. check.name .. " -> " .. tostring(errDraw))
      return
    end
  end

  local function runChromeForSize(width, height)
    local chrome = Chrome.build({
      state = state,
      hw = hw,
      C = C,
      shortText = shortText,
      clamp = clamp,
      statusColor = function() return C.info end,
      reactorPhase = function() return "READY" end,
      phaseColor = function() return C.ok end,
      computeSafetyWarnings = function() return {}, false end,
      yesno = function(v) return v and "ON" or "OFF" end,
      formatFuelLevel = function() return "MED" end,
      resolveViewName = function() return "SUP" end,
      hline = function(_, _, _, _) writes = writes + 1 end,
      writeAt = function(_, _, text) writes = writes + #(tostring(text or "")) end,
      getSize = function() return width, height end,
    })
    local okHeader, errHeader = pcall(chrome.drawHeader, "FUSION", "OK")
    if not okHeader then
      fail(115, "Header responsive en erreur (" .. width .. "x" .. height .. "): " .. tostring(errHeader))
      return false
    end
    local okFooter, errFooter = pcall(chrome.drawFooter)
    if not okFooter then
      fail(116, "Footer responsive en erreur (" .. width .. "x" .. height .. "): " .. tostring(errFooter))
      return false
    end
    return true
  end

  for _, size in ipairs({ { 32, 18 }, { 52, 24 }, { 96, 32 } }) do
    if not runChromeForSize(size[1], size[2]) then
      return
    end
  end

  local reactorRenderer = ReactorDiagram.build({
    state = state,
    CFG = { laserCount = 3 },
    C = C,
    drawBox = drawBox,
    writeAt = writeAt,
    shortText = shortText,
    clamp = clamp,
    formatTemperature = function(v)
      return string.format("%.1f C", tonumber(v) or 0)
    end,
  })

  local inductionRenderer = InductionDiagram.build({
    state = state,
    C = C,
    drawBox = drawBox,
    writeAt = writeAt,
    fillArea = function(_, _, _, _, _) writes = writes + 1 end,
    shortText = shortText,
    clamp = clamp,
    inductionStatus = function() return "ONLINE", C.ok end,
    getInductionFillRatio = function() return 0.55 end,
    formatEnergy = function(v) return string.format("%.2f J", tonumber(v) or 0) end,
    formatEnergyPerTick = function(v) return string.format("%.2f J/t", tonumber(v) or 0) end,
  })

  local diagramSizes = {
    { 24, 10 },
    { 36, 16 },
    { 86, 30 },
  }
  for _, size in ipairs(diagramSizes) do
    local okR, errR = pcall(reactorRenderer, 1, 1, size[1], size[2])
    if not okR then
      fail(117, "Reactor diagram responsive en erreur (" .. size[1] .. "x" .. size[2] .. "): " .. tostring(errR))
      return
    end
    local okI, errI = pcall(inductionRenderer, 1, 1, size[1], size[2])
    if not okI then
      fail(118, "Induction diagram responsive en erreur (" .. size[1] .. "x" .. size[2] .. "): " .. tostring(errI))
      return
    end
  end

  if writes <= 0 then
    fail(119, "Aucune sortie de rendu detectee en mode responsive")
    return
  end

  ok("Responsive UI render stable (views/chrome/diagrams)")
end

return M
