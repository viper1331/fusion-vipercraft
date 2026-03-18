-- core/app.lua
-- Runtime applicatif principal.
-- Architecture cible:
-- - fusion.lua: bootstrap/orchestrateur minimal.
-- - core/: logique métier et état runtime.
-- - ui/: rendu, vues, composants et hitboxes.
-- - io/: accès matériel et périphériques.
-- Toute nouvelle phase doit respecter cette séparation.

local M = {}

function M.run()
  local Theme = require("ui.theme")
  local UIComponents = require("ui.components")
  local UIViews = require("ui.views")
  local UIChrome = require("ui.chrome")
  local UIReactorDiagram = require("ui.reactor_diagram")
  local UIInductionDiagram = require("ui.induction_diagram")
  local CoreConfig = require("core.config")
  local CoreEnergy = require("core.energy")
  local CoreTemperature = require("core.temperature")
  local CoreUpdate = require("core.update")
  local CoreLogger = require("core.logger")
  local CoreState = require("core.state")
  local CoreReactor = require("core.reactor")
  local CoreInduction = require("core.induction")
  local CoreAlerts = require("core.alerts")
  local CoreActions = require("core.actions")
  local CoreStartup = require("core.startup")
  local CoreRuntimeLoop = require("core.runtime_loop")
  local CoreRuntimeRefresh = require("core.runtime_refresh")
  local RuntimeConfig = require("core.runtime_config")
  local IoDevices = require("io.devices")
  local IoReaders = require("io.readers")
  local IoRelays = require("io.relays")
  local IoMonitor = require("io.monitor")

  local runtime = RuntimeConfig.new()
  local CFG = runtime.cfg
  local LOCAL_VERSION = runtime.update.localVersion
  local UPDATE_ENABLED = runtime.update.enabled

  local nativeTerm = term.current()
  local buttons = {}
  local touchHitboxes = { terminal = {}, monitor = {} }
  local pressedButtons = {}
  local currentDrawSource = "terminal"
  local pressedEffectDuration = 0.18

  local HITBOX_DEFAULTS = runtime.hitboxDefaults

  local state = CoreState.new(CoreState.defaultRuntimeState(LOCAL_VERSION, UPDATE_ENABLED))
  local hw = CoreState.defaultHardwareState()
  local setupMonitor
  local logger = CoreLogger.new({
    fs = fs,
    term = nativeTerm,
    enabled = CFG.logEnabled,
    level = CFG.logLevel,
    toFile = CFG.logToFile,
    toTerminal = CFG.logToTerminal,
    file = CFG.logFile,
    maxFileBytes = CFG.logMaxFileBytes,
    prefix = "fusion",
  })

  logger.info("Fusion runtime boot", {
    version = tostring(LOCAL_VERSION),
    refreshDelay = tostring(CFG.refreshDelay),
  })

  local UI_PALETTE = {
    bgMain = colors.white,
    bgElevated = colors.lightGray,
    frameOuter = colors.lightBlue,
    frameInner = colors.cyan,
    frameDim = colors.gray,
    textMain = colors.black,
    textDim = colors.gray,
    accentOk = colors.green,
    accentWarn = colors.orange,
    accentBad = colors.red,
    accentInfo = colors.cyan,
    accentViolet = colors.purple,
    accentLaser = colors.yellow,
    headerBg = colors.lightGray,
    footerBg = colors.lightGray,
    buttonNeutral = colors.lightGray,
    buttonActive = colors.cyan,
    buttonPressed = colors.gray,
    buttonDanger = colors.red,
    buttonFuelT = colors.green,
    buttonFuelD = colors.orange,
    buttonFuelDT = colors.purple,
    buttonSuccess = colors.lime,
  }

  local styles = {
    panel = {
      default = { bg = UI_PALETTE.bgMain, header = UI_PALETTE.bgElevated, border = UI_PALETTE.frameInner, trim = UI_PALETTE.bgMain, accent = UI_PALETTE.frameInner, text = UI_PALETTE.textMain },
      accent = { bg = UI_PALETTE.bgMain, header = UI_PALETTE.bgElevated, border = UI_PALETTE.frameOuter, trim = UI_PALETTE.bgMain, accent = UI_PALETTE.frameInner, text = UI_PALETTE.textMain },
    },
    button = {
      primary = { face = UI_PALETTE.buttonActive, border = UI_PALETTE.frameOuter, text = UI_PALETTE.textMain },
      secondary = { face = UI_PALETTE.buttonNeutral, border = UI_PALETTE.frameOuter, text = UI_PALETTE.textMain },
      danger = { face = UI_PALETTE.buttonDanger, border = UI_PALETTE.frameOuter, text = UI_PALETTE.textMain },
      fuelT = { face = UI_PALETTE.buttonFuelT, border = UI_PALETTE.frameOuter, text = UI_PALETTE.textMain },
      fuelD = { face = UI_PALETTE.buttonFuelD, border = UI_PALETTE.frameOuter, text = UI_PALETTE.textMain },
      fuelDT = { face = UI_PALETTE.buttonFuelDT, border = UI_PALETTE.frameOuter, text = UI_PALETTE.textMain },
      success = { face = UI_PALETTE.buttonSuccess, border = UI_PALETTE.frameOuter, text = UI_PALETTE.textMain },
      disabled = { face = UI_PALETTE.bgElevated, border = UI_PALETTE.frameDim, text = UI_PALETTE.textDim },
    },
  }

  local C = {
    bg = UI_PALETTE.bgMain,
    panel = UI_PALETTE.bgElevated,
    panelDark = UI_PALETTE.bgMain,
    panelMid = UI_PALETTE.bgElevated,
    panelInner = UI_PALETTE.buttonNeutral,
    panelShadow = UI_PALETTE.bgMain,
    text = UI_PALETTE.textMain,
    dim = UI_PALETTE.textDim,
    ok = UI_PALETTE.accentOk,
    warn = UI_PALETTE.accentWarn,
    bad = UI_PALETTE.accentBad,
    info = UI_PALETTE.accentInfo,
    border = UI_PALETTE.frameInner,
    borderDim = UI_PALETTE.frameOuter,
    energy = UI_PALETTE.accentLaser,
    fuel = UI_PALETTE.accentWarn,
    headerBg = UI_PALETTE.headerBg,
    footerBg = UI_PALETTE.footerBg,
    headerText = UI_PALETTE.textMain,
    btnOn = UI_PALETTE.buttonFuelT,
    btnOff = UI_PALETTE.buttonDanger,
    btnAction = UI_PALETTE.buttonActive,
    btnWarn = UI_PALETTE.accentWarn,
    btnText = UI_PALETTE.textMain,
    tritium = UI_PALETTE.buttonFuelT,
    deuterium = UI_PALETTE.buttonFuelD,
    dtFuel = UI_PALETTE.buttonFuelDT,
    inactive = UI_PALETTE.frameDim,
  }

  local function colorHex(c)
    return colors.toBlit(c)
  end

  local function uiShortText(text, maxLen)
    text = tostring(text or "")
    if #text <= maxLen then return text end
    if maxLen <= 0 then return "" end
    return text:sub(1, maxLen)
  end

  local ui = {}

  function ui.write(x, y, txt, tc, bc)
    local tw, th = term.getSize()
    if y < 1 or y > th then return end
    txt = tostring(txt or "")
    if #txt == 0 then return end

    local sx = x
    local text = txt
    if sx < 1 then
      local cut = 1 - sx
      if cut >= #text then return end
      text = string.sub(text, cut + 1)
      sx = 1
    end
    if sx > tw then return end
    if sx + #text - 1 > tw then
      text = string.sub(text, 1, tw - sx + 1)
    end
    if #text == 0 then return end

    if bc then term.setBackgroundColor(bc) end
    if tc then term.setTextColor(tc) end
    term.setCursorPos(sx, y)
    term.write(text)
  end

  function ui.blit(x, y, text, fg, bg)
    local tw, th = term.getSize()
    if y < 1 or y > th then return end
    text = tostring(text or "")
    fg = tostring(fg or "")
    bg = tostring(bg or "")
    local n = math.min(#text, #fg, #bg)
    if n <= 0 then return end
    text = string.sub(text, 1, n)
    fg = string.sub(fg, 1, n)
    bg = string.sub(bg, 1, n)

    local sx = x
    if sx < 1 then
      local cut = 1 - sx
      if cut >= n then return end
      text = string.sub(text, cut + 1)
      fg = string.sub(fg, cut + 1)
      bg = string.sub(bg, cut + 1)
      sx = 1
    end
    if sx > tw then return end
    if sx + #text - 1 > tw then
      local keep = tw - sx + 1
      text = string.sub(text, 1, keep)
      fg = string.sub(fg, 1, keep)
      bg = string.sub(bg, 1, keep)
    end
    if #text == 0 then return end

    term.setCursorPos(sx, y)
    term.blit(text, fg, bg)
  end

  function ui.fill(x, y, w, h, bg)
    local bgHex = colorHex(bg or C.bg)
    local blanks = string.rep(" ", w)
    local fg = string.rep(colorHex(C.text), w)
    local bb = string.rep(bgHex, w)
    for yy = y, y + h - 1 do
      ui.blit(x, yy, blanks, fg, bb)
    end
  end

  function ui.hline(x, y, w, bg, tc, ch)
    ui.write(x, y, string.rep(ch or " ", w), tc or C.text, bg or C.bg)
  end

  function ui.vline(x, y, h, bg, tc, ch)
    for yy = y, y + h - 1 do
      ui.write(x, yy, ch or " ", tc or C.text, bg or C.bg)
    end
  end

  function ui.frame(x, y, w, h, border, inner)
    if w < 2 or h < 2 then return end
    local stroke = border or C.border
    ui.hline(x, y, w, stroke)
    ui.hline(x, y + h - 1, w, stroke)
    ui.vline(x, y + 1, h - 2, stroke)
    ui.vline(x + w - 1, y + 1, h - 2, stroke)
    if w > 2 and h > 2 then
      ui.fill(x + 1, y + 1, w - 2, h - 2, inner or C.panelDark)
    end
  end

  function ui.panel(x, y, w, h, title, style)
    local skin = style or styles.panel.default
    ui.frame(x, y, w, h, skin.border, skin.bg)
    if w > 2 and h > 2 then
      ui.fill(x + 1, y + 1, w - 2, h - 2, skin.bg)
    end
    if title and #title > 0 and w > 8 then
      local headerTitle = string.upper(title)
      ui.hline(x + 1, y, math.max(1, w - 2), skin.header)
      ui.write(x + 2, y, uiShortText("[ " .. headerTitle .. " ]", w - 3), skin.text, skin.header)
    end
  end

  function ui.centerText(y, text, tc, bc)
    local w = term.getSize()
    if bc then ui.hline(1, y, w, bc) end
    local x = math.floor((w - #text) / 2) + 1
    ui.write(x, y, text, tc or C.text, bc)
  end

  local function applyPremiumPalette()
    Theme.applyPremiumPalette(C)
    if not term.isColor or not term.isColor() then return end
    pcall(term.setPaletteColor, colors.black, 0.08, 0.08, 0.08)
    pcall(term.setPaletteColor, colors.gray, 0.53, 0.53, 0.53)
    pcall(term.setPaletteColor, colors.lightGray, 0.88, 0.86, 0.82)
    pcall(term.setPaletteColor, colors.white, 0.96, 0.95, 0.92)
    pcall(term.setPaletteColor, colors.blue, 0.14, 0.40, 0.55)
    pcall(term.setPaletteColor, colors.lightBlue, 0.39, 0.78, 0.90)
    pcall(term.setPaletteColor, colors.cyan, 0.33, 0.85, 0.85)
    pcall(term.setPaletteColor, colors.green, 0.33, 0.74, 0.28)
    pcall(term.setPaletteColor, colors.lime, 0.58, 0.86, 0.37)
    pcall(term.setPaletteColor, colors.red, 0.92, 0.33, 0.33)
    pcall(term.setPaletteColor, colors.orange, 0.94, 0.72, 0.34)
    pcall(term.setPaletteColor, colors.yellow, 0.95, 0.86, 0.43)
    pcall(term.setPaletteColor, colors.purple, 0.86, 0.50, 0.90)
  end

  local function centerText(y, text, tc, bc)
    ui.centerText(y, text, tc, bc)
  end

  local function clamp(v, a, b)
    if v < a then return a end
    if v > b then return b end
    return v
  end

  local function toNumber(v, default)
    local n = tonumber(v)
    if n == nil then return default or 0 end
    return n
  end

  local function yesno(v)
    return v and "ON" or "OFF"
  end

  local function contains(str, sub)
    return type(str) == "string" and type(sub) == "string"
      and string.find(string.lower(str), string.lower(sub), 1, true) ~= nil
  end

  local function fmt(n)
    if type(n) ~= "number" then return tostring(n) end
    local absn = math.abs(n)
    local units = {
      { 1e15, "P" },
      { 1e12, "T" },
      { 1e9, "G" },
      { 1e6, "M" },
      { 1e3, "k" },
    }
    for _, u in ipairs(units) do
      if absn >= u[1] then
        return string.format("%.2f%s", n / u[1], u[2])
      end
    end
    return tostring(math.floor(n))
  end

  local function formatEnergy(n)
    if type(n) ~= "number" then return tostring(n) end
    return CoreEnergy.formatEnergyFromJ(n, CFG.energyUnit, { compact = true, decimals = 2 })
  end

  local function formatEnergyPerTick(n)
    if type(n) ~= "number" then return tostring(n) end
    return CoreEnergy.formatEnergyPerTickFromJ(n, CFG.energyUnit, { compact = true, decimals = 2 })
  end

  local function formatTemperature(n, opts)
    if type(n) ~= "number" then return tostring(n) end
    local sourceUnit = CoreTemperature.sanitizeUnit(state.reactorTempSourceUnit, "k")
    return CoreTemperature.formatTemperature(n, sourceUnit, opts)
  end

  local function formatMJ(n)
    -- Alias historique garde pour compatibilite des appels existants.
    return formatEnergy(n)
  end

  local function normalizePortMode(mode)
    local raw = tostring(mode or "")
    local upper = string.upper(raw)

    if upper == "INPUT" or upper == "IN" then
      return "INPUT"
    end

    if upper == "OUTPUT" or upper == "OUT" then
      return "OUTPUT"
    end

    return "UNKNOWN"
  end

  local function formatFuelLevel(n)
    n = toNumber(n, 0)
    if n <= 0 then return "EMPTY" end
    if n < 2000000 then return "LOW" end
    if n < 10000000 then return "MED" end
    if n < 50000000 then return "HIGH" end
    if n < 250000000 then return "FULL" end
    if n < 1000000000 then return "SAT" end
    return "MAX"
  end

  local function safePeripheral(name)
    if name and peripheral.isPresent(name) then
      return peripheral.wrap(name)
    end
    return nil
  end

  local function safeCall(obj, method, ...)
    if not obj then
      logger.debug("safeCall skipped: no peripheral", { method = method })
      return false, nil
    end
    if type(obj[method]) ~= "function" then
      logger.debug("safeCall skipped: missing method", { method = method })
      return false, nil
    end
    local ok, result = pcall(obj[method], ...)
    if not ok then
      local key = tostring(method) .. "|" .. tostring(result)
      state.loggedMethodFailures = state.loggedMethodFailures or {}
      if not state.loggedMethodFailures[key] then
        state.loggedMethodFailures[key] = true
        logger.warn("safeCall failed", { method = method, err = tostring(result) })
      end
      return false, nil
    end
    return true, result
  end

  local function tryMethods(obj, methods)
    for _, m in ipairs(methods) do
      local ok, value = safeCall(obj, m)
      if ok then return true, value, m end
    end
    return false, nil, nil
  end

  local function getTypeOf(name)
    local ok, t = pcall(peripheral.getType, name)
    if ok then return t end
    return nil
  end

  local function writeAt(x, y, txt, tc, bc)
    ui.write(x, y, txt, tc, bc)
  end

  local function fillArea(x, y, w, h, bg)
    ui.fill(x, y, w, h, bg or C.bg)
  end

  local function shortText(txt, maxLen)
    txt = tostring(txt or "")
    if #txt <= maxLen then return txt end
    if maxLen <= 0 then return "" end
    return txt:sub(1, maxLen)
  end

  local function statusColor(status)
    if status == "ONLINE" or status == "AUTO" or status == "OK" then return C.ok end
    if status == "WARN" then return C.warn end
    if status == "OFFLINE" or status == "MANUAL" or status == "DANGER" then return C.bad end
    return C.info
  end

  local function drawBox(x, y, w, h, title, accent)
    if w < 4 or h < 3 then return end
    local skin = styles.panel.default
    local borderColor = accent or skin.border
    ui.frame(x, y, w, h, borderColor, skin.bg)
    if w > 2 and h > 2 then
      ui.fill(x + 1, y + 1, w - 2, h - 2, skin.bg)
    end
    if title and #title > 0 and w > 10 then
      local t = shortText(string.upper(title), w - 6)
      ui.hline(x + 1, y, w - 2, skin.header)
      ui.write(x + 2, y, " " .. t .. " ", skin.text, skin.header)
    end
  end

  local runtimeAlerts = CoreAlerts.build({
    state = state,
    hw = hw,
    CFG = CFG,
    C = C,
    contains = contains,
    toNumber = toNumber,
    CoreReactor = CoreReactor,
  })

  local reactorPhase = runtimeAlerts.reactorPhase
  local phaseColor = runtimeAlerts.phaseColor
  local getRuntimeFuelMode = runtimeAlerts.getRuntimeFuelMode
  local isRuntimeFuelOk = runtimeAlerts.isRuntimeFuelOk
  local computeSafetyWarnings = runtimeAlerts.computeSafetyWarnings
  local chromeRenderer = UIChrome.build({
    state = state,
    hw = hw,
    C = C,
    shortText = shortText,
    clamp = clamp,
    statusColor = statusColor,
    reactorPhase = reactorPhase,
    phaseColor = phaseColor,
    computeSafetyWarnings = computeSafetyWarnings,
    yesno = yesno,
    formatFuelLevel = formatFuelLevel,
    resolveViewName = UIViews.resolveViewName,
    hline = ui.hline,
    writeAt = writeAt,
    getSize = term.getSize,
  })

  local drawHeader = chromeRenderer.drawHeader
  local drawFooter = chromeRenderer.drawFooter

  local function pushEvent(message)
    if not message or #message == 0 then return end
    local stamp = string.format("%05.1f", os.clock() % 1000)
    table.insert(state.eventLog, 1, stamp .. " " .. message)
    while #state.eventLog > (state.maxEventLog or 8) do
      table.remove(state.eventLog)
    end
    logger.info(message, { source = "event" })
  end

  local function drawKeyValue(x, y, key, value, keyColor, valueColor, maxVal)
    local total = math.max(8, toNumber(maxVal, 20))
    local keyWidth = clamp(math.floor(total * 0.36), 4, 10)
    local valueWidth = math.max(1, total - keyWidth - 1)
    local k = shortText(tostring(key), keyWidth)
    local v = shortText(tostring(value), valueWidth)
    writeAt(x, y, k, keyColor or C.dim, C.panelDark)
    writeAt(x + keyWidth, y, " ", C.text, C.panelDark)
    writeAt(x + keyWidth + 1, y, v, valueColor or C.text, C.panelDark)
  end

  local function invokeSetupMonitor(context)
    if type(setupMonitor) ~= "function" then
      local msg = "Monitor setup unavailable"
      if context and context ~= "" then
        msg = msg .. " (" .. tostring(context) .. ")"
      end
      if type(state.setup) == "table" then
        state.setup.lastMessage = msg
      end
      state.lastAction = msg
      pushEvent(msg)
      logger.error("setupMonitor callback missing", { context = context or "runtime" })
      return false
    end

    local ok = setupMonitor()
    if ok == false then
      if type(state.setup) == "table" then
        state.setup.lastMessage = "Monitor reconfiguration failed"
      end
      state.lastAction = "Monitor reconfiguration failed"
      pushEvent("Monitor reconfiguration failed")
      logger.error("setupMonitor returned false", { context = context or "runtime" })
      return false
    end
    logger.info("Display surface configured", {
      context = context or "runtime",
      monitor = hw.monitorName or "none",
      backend = hw.monitorBackend or "terminal",
      output = CFG.displayOutput,
    })
    return true
  end

  local function computeLayout(tw, th)
    local uiScale = CoreConfig.sanitizeUiScale(CFG.uiScale, 1.0)
    local scaledTw = math.floor((tw / uiScale) + 0.5)
    local scaledTh = math.floor((th / uiScale) + 0.5)

    local minW, minH = 34, 14
    if scaledTw < minW or scaledTh < minH then
      return {
        tooSmall = true,
        minW = math.ceil(minW * uiScale),
        minH = math.ceil(minH * uiScale),
        mode = "tiny",
        uiScale = uiScale,
      }
    end

    local mode = "compact"
    if scaledTw >= 52 and scaledTh >= 18 then mode = "standard" end
    if scaledTw >= 68 and scaledTh >= 24 then mode = "large" end

    local top, bottom = 2, th - 1
    local gap = (mode == "compact") and 1 or 2
    local h = bottom - top + 1
    local layout = { mode = mode, top = top, bottom = bottom, height = h, width = tw, tooSmall = false, uiScale = uiScale }

    if mode == "compact" then
      -- Compact responsive:
      -- - Priorite a un layout empile (status / diagram / control) quand la hauteur le permet.
      -- - Fallback en 2 colonnes sur tres petites hauteurs.
      local canStack = (th >= 20 and tw >= 34)
      if canStack then
        local gapY = 1
        local statusH = clamp(math.floor(h * 0.34), 8, 12)
        local controlH = clamp(math.floor(h * 0.30), 7, 11)
        local centerH = h - statusH - controlH - (gapY * 2)

        if centerH < 7 then
          local deficit = 7 - centerH
          local cutStatus = math.min(deficit, math.max(0, statusH - 7))
          statusH = statusH - cutStatus
          deficit = deficit - cutStatus
          local cutControl = math.min(deficit, math.max(0, controlH - 6))
          controlH = controlH - cutControl
          centerH = h - statusH - controlH - (gapY * 2)
        end

        if centerH >= 7 then
          layout.stack = true
          layout.left = { x = 1, y = top, w = tw, h = statusH }
          layout.center = { x = 1, y = top + statusH + gapY, w = tw, h = centerH }
          layout.right = { x = 1, y = top + statusH + gapY + centerH + gapY, w = tw, h = controlH }
          return layout
        end
      end

      local lw = clamp(math.floor(tw * 0.56), 14, tw - 12)
      layout.left = { x = 1, y = top, w = lw, h = h }
      layout.right = { x = lw + 1 + gap, y = top, w = tw - lw - gap, h = h }
    elseif mode == "standard" then
      local lw = clamp(math.floor(tw * 0.30), 22, 34)
      local rw = clamp(math.floor(tw * 0.22), 18, 30)
      local cw = tw - lw - rw - (gap * 2)
      if cw < 34 then
        rw = math.max(16, rw - (34 - cw))
        cw = tw - lw - rw - (gap * 2)
      end
      layout.left = { x = 1, y = top, w = lw, h = h }
      layout.center = { x = lw + 1 + gap, y = top, w = cw, h = h }
      layout.right = { x = lw + cw + 1 + (gap * 2), y = top, w = rw, h = h }
    else
      local lw = clamp(math.floor(tw * 0.31), 24, 38)
      local rw = clamp(math.floor(tw * 0.21), 20, 32)
      local cw = tw - lw - rw - (gap * 2)
      if cw < 40 then
        local delta = 40 - cw
        rw = math.max(18, rw - delta)
        cw = tw - lw - rw - (gap * 2)
      end
      layout.left = { x = 1, y = top, w = lw, h = h }
      layout.center = { x = lw + 1 + gap, y = top, w = cw, h = h }
      layout.right = { x = lw + cw + 1 + (gap * 2), y = top, w = rw, h = h }
    end
    return layout
  end

  local inductionStatus
  local getInductionFillRatio

  -- Delegation explicite du rendu reacteur vers un module UI dedie.
  -- Cette extraction reduit la complexite de app.lua et facilite les evolutions visuelles.
  local drawReactorDiagram = UIReactorDiagram.build({
    state = state,
    CFG = CFG,
    C = C,
    drawBox = drawBox,
    writeAt = writeAt,
    shortText = shortText,
    clamp = clamp,
    formatTemperature = formatTemperature,
  })

  local drawInductionDiagram = UIInductionDiagram.build({
    state = state,
    C = C,
    drawBox = drawBox,
    writeAt = writeAt,
    fillArea = fillArea,
    shortText = shortText,
    clamp = clamp,
    inductionStatus = function() return inductionStatus() end,
    getInductionFillRatio = function() return getInductionFillRatio() end,
    formatEnergy = formatEnergy,
    formatEnergyPerTick = formatEnergyPerTick,
  })

  local function drawBadge(x, y, label, value, tone)
    local labelText = shortText(tostring(label), 9)
    local valueText = " " .. shortText(tostring(value), 10) .. " "
    local stateTone = tone or statusColor(value)
    writeAt(x, y, labelText, C.dim, C.panelDark)
    writeAt(x + 10, y, valueText, C.text, stateTone)
  end

  local function loadSavedMonitorName()
    if not fs.exists(runtime.files.monitorCacheFile) then return nil end
    local h = fs.open(runtime.files.monitorCacheFile, "r")
    if not h then return nil end
    local name = h.readLine()
    h.close()
    return name
  end

  local function saveSelectedMonitorName(name)
    local h = fs.open(runtime.files.monitorCacheFile, "w")
    if not h then return end
    h.writeLine(name or "")
    h.close()
  end

  local function trimText(txt)
    return CoreConfig.trimText(txt)
  end

  local function readLocalVersionFile()
    return CoreConfig.readLocalVersionFile(fs, runtime.files.versionFile, LOCAL_VERSION)
  end

  local function loadFusionConfig()
    return CoreConfig.loadFusionConfig(fs, runtime.files.configFile, CFG, UPDATE_ENABLED)
  end

  local function applyConfigToRuntime(config)
    if type(config) ~= "table" then return end
    CoreConfig.applyConfigToRuntime(config, CFG)
    logger.configure({
      enabled = CFG.logEnabled,
      level = CFG.logLevel,
      toFile = CFG.logToFile,
      toTerminal = CFG.logToTerminal,
      file = CFG.logFile,
      maxFileBytes = CFG.logMaxFileBytes,
      prefix = "fusion",
    })

    if type(config.ui) == "table" and type(config.ui.preferredView) == "string" then
      local view = string.upper(config.ui.preferredView)
      if view == "SUP" then state.currentView = "supervision"
      elseif view == "DIAG" then state.currentView = "diagnostic"
      elseif view == "MAN" then state.currentView = "manual"
      elseif view == "IND" then state.currentView = "induction"
      elseif view == "UPDATE" then state.currentView = "update"
      elseif view == "CFG" or view == "CONFIG" then state.currentView = "config"
      elseif view == "SETUP" then state.currentView = "setup"
      end
    end

    if type(config.update) == "table" and config.update.enabled ~= nil then
      UPDATE_ENABLED = config.update.enabled and true or false
    end
    logger.info("Runtime config applied", {
      output = CFG.displayOutput,
      displayBackend = CFG.displayBackend,
      preferredMonitor = CFG.preferredMonitor or "none",
      monitorScale = CFG.monitorScale,
      uiScale = CFG.uiScale,
      logLevel = CFG.logLevel,
    })
  end

  local function cloneTable(input)
    if type(input) ~= "table" then return input end
    local out = {}
    for k, v in pairs(input) do
      out[k] = cloneTable(v)
    end
    return out
  end

  local function normalizeSetupConfig(config)
    local base = CoreConfig.defaultFusionConfig(CFG, UPDATE_ENABLED)
    local merged = CoreConfig.mergeDefaults(cloneTable(config or {}), base)
    merged.ui.preferredView = string.upper(tostring(merged.ui.preferredView or "SUP"))
    if merged.ui.preferredView == "CONFIG" then merged.ui.preferredView = "CFG" end
    merged.ui.scale = CoreConfig.sanitizeUiScale(merged.ui.scale, base.ui.scale or 1.0)
    merged.ui.output = CoreConfig.sanitizeDisplayOutput(merged.ui.output, base.ui.output or "monitor")
    merged.ui.displayBackend = CoreConfig.sanitizeDisplayBackend(merged.ui.displayBackend, base.ui.displayBackend or "auto")
    merged.ui.energyUnit = CoreConfig.sanitizeEnergyUnit(merged.ui.energyUnit, base.ui.energyUnit or "j")
    merged.ui.laserCount = CoreConfig.sanitizeLaserCount(merged.ui.laserCount, base.ui.laserCount or 1)
    merged.monitor.scale = CoreConfig.sanitizeMonitorScale(merged.monitor.scale, base.monitor.scale or 0.5)
    merged.logs = type(merged.logs) == "table" and merged.logs or {}
    merged.logs.enabled = CoreConfig.sanitizeBoolean(merged.logs.enabled, base.logs.enabled ~= false)
    merged.logs.level = CoreConfig.sanitizeLogLevel(merged.logs.level, base.logs.level or "info")
    merged.logs.toFile = CoreConfig.sanitizeBoolean(merged.logs.toFile, base.logs.toFile ~= false)
    merged.logs.toTerminal = CoreConfig.sanitizeBoolean(merged.logs.toTerminal, base.logs.toTerminal == true)
    merged.logs.file = CoreConfig.sanitizeLogFile(merged.logs.file, base.logs.file or "fusion.log")
    merged.logs.maxFileBytes = CoreConfig.sanitizeLogMaxFileBytes(merged.logs.maxFileBytes, base.logs.maxFileBytes or 262144)
    return merged
  end

  local function refreshSetupWorkingConfig(config)
    local normalized = normalizeSetupConfig(config)
    state.setup.loaded = cloneTable(normalized)
    state.setup.working = cloneTable(normalized)
    state.setup.deviceStatus = {}
    state.setup.dirty = false
  end

  local function ensureConfigOrInstaller()
    local ok, config, err = loadFusionConfig()
    if not ok then
      logger.error("Config load failed", { err = tostring(err) })
      term.redirect(nativeTerm)
      term.setBackgroundColor(colors.black)
      term.setTextColor(colors.white)
      term.clear()
      term.setCursorPos(1, 1)
      print("[FUSION] Configuration absente ou invalide: " .. tostring(err))
      print("[FUSION] Lancez install.lua pour configurer ce setup.")
      print("[FUSION] Appuyez sur I pour lancer l'installateur, ou une autre touche pour quitter.")
      local _, key = os.pullEvent("key")
      if key == keys.i and fs.exists("install.lua") then
        logger.info("Launching installer from missing config prompt")
        shell.run("install.lua")
      end
      return false, nil
    end

    local configValid, configErrors = CoreConfig.validateConfig(config)
    if not configValid then
      logger.error("Config validation failed", { first = tostring(configErrors and configErrors[1]) })
      term.redirect(nativeTerm)
      term.setBackgroundColor(colors.black)
      term.setTextColor(colors.white)
      term.clear()
      term.setCursorPos(1, 1)
      print("[FUSION] Configuration invalide: champs obligatoires manquants.")
      for _, item in ipairs(configErrors) do
        print(" - " .. tostring(item))
      end
      print("[FUSION] Corrigez fusion_config.lua ou relancez install.lua.")
      print("[FUSION] Appuyez sur I pour lancer l'installateur, ou une autre touche pour quitter.")
      local _, key = os.pullEvent("key")
      if key == keys.i and fs.exists("install.lua") then
        logger.info("Launching installer from invalid config prompt")
        shell.run("install.lua")
      end
      return false, nil
    end

    applyConfigToRuntime(config)
    refreshSetupWorkingConfig(config)
    logger.info("Configuration loaded", { file = runtime.files.configFile })
    return true, config
  end

  local function loadRuntimeSetupConfig()
    local ok, config = loadFusionConfig()
    if ok and type(config) == "table" then
      refreshSetupWorkingConfig(config)
    end
  end

  local function setupDeviceExists(name, expectedType)
    if type(name) ~= "string" or trimText(name) == "" then return false, "UNBOUND" end
    if not peripheral.isPresent(name) then return false, "MISSING" end
    if not expectedType then return true, "OK" end
    local ptype = getTypeOf(name)
    if ptype == expectedType then return true, "OK" end
    if expectedType == "block_reader" and contains(name, "block_reader") then return true, "OK" end
    return false, "INVALID"
  end

  local function refreshSetupDeviceStatus()
    local w = state.setup.working
    if type(w) ~= "table" then return end
    local ds = {}

    local monitorOk, monitorStatus = setupDeviceExists(w.monitor.name, "monitor")
    w.monitor.ok = monitorOk
    ds.monitor = monitorStatus

    local deviceTypes = {
      reactorController = nil,
      logicAdapter = nil,
      laser = nil,
      induction = nil,
    }
    for role, expected in pairs(deviceTypes) do
      local _, status = setupDeviceExists(w.devices[role], expected)
      ds[role] = status
    end

    local _, relayLaser = setupDeviceExists(w.relays.laser.name, "redstone_relay")
    local _, relayTritium = setupDeviceExists(w.relays.tritium.name, "redstone_relay")
    local _, relayDeuterium = setupDeviceExists(w.relays.deuterium.name, "redstone_relay")
    ds.relayLaser = relayLaser
    ds.relayTritium = relayTritium
    ds.relayDeuterium = relayDeuterium

    local _, readerTritium = setupDeviceExists(w.readers.tritium, "block_reader")
    local _, readerDeuterium = setupDeviceExists(w.readers.deuterium, "block_reader")
    local _, readerAux = setupDeviceExists(w.readers.aux, "block_reader")
    ds.readerTritium = readerTritium
    ds.readerDeuterium = readerDeuterium
    ds.readerAux = readerAux

    state.setup.deviceStatus = ds
  end

  local function getSetupStatusRows()
    local w = state.setup.working or {}
    local ds = state.setup.deviceStatus or {}
    return {
      { role = "Monitor", name = (w.monitor and w.monitor.name) or "N/A", status = ds.monitor or "INVALID" },
      { role = "Reactor", name = (w.devices and w.devices.reactorController) or "N/A", status = ds.reactorController or "INVALID" },
      { role = "Logic", name = (w.devices and w.devices.logicAdapter) or "N/A", status = ds.logicAdapter or "INVALID" },
      { role = "Laser", name = (w.devices and w.devices.laser) or "N/A", status = ds.laser or "INVALID" },
      { role = "Induction", name = (w.devices and w.devices.induction) or "N/A", status = ds.induction or "INVALID" },
      { role = "Relay LAS", name = (w.relays and w.relays.laser and (w.relays.laser.name .. "." .. w.relays.laser.side)) or "N/A", status = ds.relayLaser or "INVALID" },
      { role = "Relay T", name = (w.relays and w.relays.tritium and (w.relays.tritium.name .. "." .. w.relays.tritium.side)) or "N/A", status = ds.relayTritium or "INVALID" },
      { role = "Relay D", name = (w.relays and w.relays.deuterium and (w.relays.deuterium.name .. "." .. w.relays.deuterium.side)) or "N/A", status = ds.relayDeuterium or "INVALID" },
      { role = "Reader T", name = (w.readers and w.readers.tritium) or "N/A", status = ds.readerTritium or "INVALID" },
      { role = "Reader D", name = (w.readers and w.readers.deuterium) or "N/A", status = ds.readerDeuterium or "INVALID" },
      { role = "Reader Aux", name = (w.readers and w.readers.aux) or "N/A", status = ds.readerAux or "INVALID" },
    }
  end

  local function listSetupCandidates(expectedType, validator)
    local candidates = {}
    for _, name in ipairs(peripheral.getNames()) do
      local include = false
      if type(validator) == "function" then
        local obj = safePeripheral(name)
        include = obj and validator(obj, name) or false
      elseif expectedType == nil then
        include = true
      else
        local ptype = getTypeOf(name)
        include = (ptype == expectedType) or (expectedType == "block_reader" and contains(name, "block_reader"))
      end
      if include then table.insert(candidates, name) end
    end
    table.sort(candidates)
    return candidates
  end

  local function getSetupRebindCandidates(role)
    if role == "monitor" then
      return listSetupCandidates("monitor")
    end

    if role == "reactorController" then
      return listSetupCandidates(nil, function(obj)
        return IoDevices.hasMethods(obj, { "isIgnited", "getPlasmaTemperature", "getPlasmaTemp", "getPlasmaHeat", "getCaseTemperature", "getCasingTemperature" }, 2)
      end)
    end

    if role == "logicAdapter" then
      return listSetupCandidates(nil, function(obj)
        return IoDevices.hasMethods(obj, { "isFormed", "isIgnited", "getPlasmaTemperature", "getPlasmaTemp", "getPlasmaHeat", "getIgnitionTemperature", "getIgnitionTemp" }, 3)
      end)
    end

    if role == "laser" then
      return listSetupCandidates(nil, function(obj)
        return IoDevices.hasMethods(obj, { "getEnergy", "getEnergyStored", "getStored", "getMaxEnergy", "getMaxEnergyStored", "getCapacity" }, 2)
      end)
    end

    if role == "induction" then
      return listSetupCandidates(nil, function(obj)
        return IoDevices.hasMethods(obj, { "isFormed", "getEnergy", "getMaxEnergy", "getEnergyFilledPercentage", "getTransferCap" }, 2)
      end)
    end

    if role == "relayLaser" or role == "relayTritium" or role == "relayDeuterium" then
      return listSetupCandidates("redstone_relay")
    end

    if role == "readerTritium" or role == "readerDeuterium" or role == "readerAux" then
      return listSetupCandidates("block_reader")
    end

    return {}
  end

  local function applySetupSelection(role, selectedName)
    local w = state.setup.working
    if type(w) ~= "table" then return false end
    if type(selectedName) ~= "string" or trimText(selectedName) == "" then return false end

    if role == "monitor" then
      w.monitor.name = selectedName
    elseif role == "reactorController" then
      w.devices.reactorController = selectedName
    elseif role == "logicAdapter" then
      w.devices.logicAdapter = selectedName
    elseif role == "laser" then
      w.devices.laser = selectedName
    elseif role == "induction" then
      w.devices.induction = selectedName
    elseif role == "relayLaser" then
      w.relays.laser.name = selectedName
    elseif role == "relayTritium" then
      w.relays.tritium.name = selectedName
    elseif role == "relayDeuterium" then
      w.relays.deuterium.name = selectedName
    elseif role == "readerTritium" then
      w.readers.tritium = selectedName
    elseif role == "readerDeuterium" then
      w.readers.deuterium = selectedName
    elseif role == "readerAux" then
      w.readers.aux = selectedName
    else
      return false
    end

    state.setup.dirty = true
    return true
  end

  local function runSetupTest(target)
    local setup = state.setup
    local w = setup.working
    if type(w) ~= "table" then
      setup.lastTestResult = "FAIL"
      setup.lastMessage = "Setup config not loaded"
      return false
    end

    local t = string.upper(tostring(target or ""))
    local ok, status = false, "INVALID"
    local label = t

    if t == "MONITOR" then
      ok, status = setupDeviceExists(w.monitor.name, "monitor")
      label = "monitor"
    elseif t == "LAS" then
      ok, status = setupDeviceExists(w.relays.laser.name, "redstone_relay")
      label = "relay laser"
    elseif t == "T" then
      ok, status = setupDeviceExists(w.relays.tritium.name, "redstone_relay")
      label = "relay tritium"
    elseif t == "D" then
      ok, status = setupDeviceExists(w.relays.deuterium.name, "redstone_relay")
      label = "relay deuterium"
    elseif t == "READER T" then
      ok, status = setupDeviceExists(w.readers.tritium, "block_reader")
      label = "reader tritium"
    elseif t == "READER D" then
      ok, status = setupDeviceExists(w.readers.deuterium, "block_reader")
      label = "reader deuterium"
    elseif t == "INDUCTION" then
      ok, status = setupDeviceExists(w.devices.induction, nil)
      label = "induction"
    elseif t == "LASER" then
      ok, status = setupDeviceExists(w.devices.laser, nil)
      label = "laser"
    else
      setup.lastTestResult = "FAIL " .. t
      setup.lastMessage = "Unknown setup test: " .. tostring(target)
      pushEvent("Setup test unknown")
      return false
    end

    setup.lastTestResult = (ok and "OK " or "FAIL ") .. t
    setup.lastMessage = string.format("%s: %s (%s)", label, ok and "OK" or "FAIL", tostring(status))
    refreshSetupDeviceStatus()
    pushEvent("Setup test " .. t .. (ok and " OK" or " FAIL"))
    return ok
  end

  local function setupStartRebind(role)
    local setup = state.setup
    local candidates = getSetupRebindCandidates(role)
    setup.rebindRole = role
    setup.rebindCandidates = candidates
    setup.rebindCursor = 1
    if #candidates == 0 then
      setup.lastMessage = "No candidate found for " .. tostring(role)
      setup.rebindRole = nil
      pushEvent("Setup rebind empty")
      return false
    end
    setup.lastMessage = string.format("Select %s (%d candidates)", tostring(role), #candidates)
    pushEvent("Setup rebind " .. tostring(role))
    return true
  end

  local function setupApplySelection(index)
    local setup = state.setup
    local role = setup.rebindRole
    local candidates = setup.rebindCandidates or {}
    local idx = tonumber(index) or setup.rebindCursor or 1
    idx = math.floor(idx)

    if type(role) ~= "string" or #candidates == 0 then
      setup.lastMessage = "No active rebind"
      return false
    end

    local selectedName = candidates[idx]
    if type(selectedName) ~= "string" then
      setup.lastMessage = "Invalid selection"
      return false
    end

    local applied = applySetupSelection(role, selectedName)
    if not applied then
      setup.lastMessage = "Unable to apply selection"
      return false
    end

    setup.rebindRole = nil
    setup.rebindCandidates = {}
    setup.rebindCursor = 1
    setup.lastMessage = string.format("%s -> %s", role, selectedName)
    refreshSetupDeviceStatus()
    pushEvent("Setup binding updated")
    return true
  end

  local function saveSetupConfig()
    local setup = state.setup
    if type(setup.working) ~= "table" then
      setup.saveStatus = "SAVE FAILED"
      setup.lastMessage = "Setup config not loaded"
      logger.error("Setup save failed: working config missing")
      return false
    end

    local normalized = normalizeSetupConfig(setup.working)
    local valid, errors = CoreConfig.validateConfig(normalized)
    if not valid then
      setup.saveStatus = "SAVE FAILED"
      setup.lastMessage = (errors and errors[1]) or "Configuration invalid"
      pushEvent("Config save failed")
      logger.error("Setup save failed: config validation", { err = tostring(setup.lastMessage) })
      return false
    end

    local okWrite, errWrite = CoreConfig.writeFusionConfig(fs, runtime.files.configFile, normalized)
    if not okWrite then
      setup.saveStatus = "SAVE FAILED"
      setup.lastMessage = tostring(errWrite or "Unable to write config")
      pushEvent("Config save failed")
      logger.error("Setup save failed: write error", { err = tostring(errWrite) })
      return false
    end

    applyConfigToRuntime(normalized)
    refreshSetupWorkingConfig(normalized)
    refreshSetupDeviceStatus()
    invokeSetupMonitor("save cfg")
    setup.saveStatus = "CONFIG SAVED"
    setup.lastMessage = "Configuration saved"
    state.lastAction = "Config saved"
    setup.dirty = false
    pushEvent("Config saved")
    logger.info("Setup config saved")
    return true
  end

  local function runInstallerFromSetup()
    local setup = state.setup
    if not fs.exists("install.lua") then
      setup.lastMessage = "install.lua missing"
      setup.saveStatus = "INSTALL FAILED"
      pushEvent("Installer missing")
      logger.error("Installer launch failed: install.lua missing")
      return false
    end

    local previousTerm = term.current()
    term.redirect(nativeTerm)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
    print("[FUSION] Running installer...")

    local okInstaller, installerErr = pcall(function()
      shell.run("install.lua")
    end)

    local redirected = pcall(term.redirect, previousTerm)
    if not redirected then
      term.redirect(nativeTerm)
    end
    applyPremiumPalette()

    if not okInstaller then
      setup.lastMessage = "Installer error: " .. tostring(installerErr)
      setup.saveStatus = "INSTALL FAILED"
      pushEvent("Installer failed")
      logger.error("Installer execution failed", { err = tostring(installerErr) })
      return false
    end

    local okConfig, config, configErr = loadFusionConfig()
    if okConfig and type(config) == "table" then
      applyConfigToRuntime(config)
      refreshSetupWorkingConfig(config)
      refreshSetupDeviceStatus()
      invokeSetupMonitor("installer return")
      setup.saveStatus = "CONFIG RELOADED"
      setup.lastMessage = "Installer complete"
      state.lastAction = "Installer complete"
      pushEvent("Installer complete")
      logger.info("Installer completed and config reloaded")
      return true
    end

    setup.saveStatus = "INSTALL DONE"
    setup.lastMessage = "Installer complete, reload failed: " .. tostring(configErr or "Unknown")
    state.lastAction = "Installer done"
    pushEvent("Installer complete")
    logger.warn("Installer completed but config reload failed", { err = tostring(configErr) })
    return false
  end

  local function setUpdateState(status, checkResult, applyResult)
    CoreUpdate.setUpdateState(state.update, status, checkResult, applyResult)
  end

  local function httpGetText(url)
    return CoreUpdate.httpGetText(http, trimText, state.update, url)
  end

  local function parseVersion(version)
    return CoreUpdate.parseVersion(version)
  end

  local function compareVersions(localV, remoteV)
    return CoreUpdate.compareVersions(localV, remoteV)
  end

  local function validateVersionString(version)
    return CoreUpdate.validateVersionString(version)
  end

  local function validateLuaScript(text)
    return CoreUpdate.validateLuaScript(text, trimText)
  end

  local function writeTextFile(path, content)
    return CoreUpdate.writeTextFile(fs, path, content)
  end

  local function readTextFile(path)
    return CoreUpdate.readTextFile(fs, path)
  end

  local function normalizePath(path)
    local normalized = trimText(tostring(path or ""))
    normalized = normalized:gsub("\\", "/")
    normalized = normalized:gsub("/+", "/")
    normalized = normalized:gsub("^%./+", "")
    return normalized
  end

  local function isSafeRelativePath(path)
    local normalized = normalizePath(path)
    if normalized == "" then return false end
    if normalized:sub(1, 1) == "/" then return false end
    if normalized:match("^[%a]:") then return false end
    for segment in normalized:gmatch("[^/]+") do
      if segment == "." or segment == ".." then
        return false
      end
    end
    return true
  end

  local function buildRawFileUrl(path)
    return runtime.update.repoRawBase .. "/" .. normalizePath(path)
  end

  local function getTempPathFor(filePath)
    return runtime.update.tempDir .. "/" .. normalizePath(filePath) .. ".new"
  end

  local function getBackupPathFor(filePath)
    return normalizePath(filePath) .. ".bak"
  end

  local function getMissingBackupMarker(filePath)
    return getBackupPathFor(filePath) .. runtime.update.missingBackupSuffix
  end

  local function ensureParentDir(path)
    local dir = fs.getDir(path)
    if dir and dir ~= "" and not fs.exists(dir) then
      fs.makeDir(dir)
    end
  end

  local function isPreservedFile(path, preserveSet)
    return preserveSet[normalizePath(path)] == true
  end

  local function buildPreserveSet(manifest)
    local preserveSet = {}
    for _, path in ipairs(manifest.preserve or {}) do
      preserveSet[normalizePath(path)] = true
    end
    preserveSet[normalizePath(runtime.files.configFile)] = true
    return preserveSet
  end

  local function parseManifest(body)
    if type(textutils) ~= "table" or type(textutils.unserializeJSON) ~= "function" then
      return false, nil, "JSON parser unavailable"
    end

    local ok, decoded = pcall(textutils.unserializeJSON, body)
    if not ok or type(decoded) ~= "table" then
      return false, nil, "Invalid manifest JSON"
    end
    if type(decoded.version) ~= "string" then
      return false, nil, "Manifest version missing"
    end
    if type(decoded.files) ~= "table" or #decoded.files == 0 then
      return false, nil, "Manifest files missing"
    end

    local validVersion, versionErr = validateVersionString(trimText(decoded.version))
    if not validVersion then
      return false, nil, versionErr or "Manifest version invalid"
    end

    local seen = {}
    local files = {}
    for _, item in ipairs(decoded.files) do
      local path = normalizePath(trimText(item))
      if path ~= "" then
        if not isSafeRelativePath(path) then
          return false, nil, "Manifest contains unsafe path: " .. tostring(path)
        end
        if not seen[path] then
          seen[path] = true
          table.insert(files, path)
        end
      end
    end
    if #files == 0 then
      return false, nil, "Manifest files list is empty"
    end

    -- Règle release: fusion.lua et fusion.version doivent toujours être publiés ensemble.
    -- Le manifeste porte la version publiée et doit inclure ces deux fichiers.
    if not seen["fusion.lua"] then
      return false, nil, "Manifest must include fusion.lua"
    end
    if not seen["fusion.version"] then
      return false, nil, "Manifest must include fusion.version"
    end

    local preserve = {}
    if type(decoded.preserve) == "table" then
      for _, item in ipairs(decoded.preserve) do
        local path = normalizePath(trimText(item))
        if path ~= "" then
          if not isSafeRelativePath(path) then
            return false, nil, "Manifest preserve path is unsafe: " .. tostring(path)
          end
          table.insert(preserve, path)
        end
      end
    end

    return true, {
      version = trimText(decoded.version),
      files = files,
      preserve = preserve,
    }, nil
  end

  local function validateDownloadedContent(path, content, expectedVersion)
    local normalized = normalizePath(path)
    if not isSafeRelativePath(normalized) then
      return false, "Unsafe target path: " .. tostring(normalized)
    end

    if type(content) ~= "string" or #trimText(content) == 0 then
      return false, "Downloaded file is empty: " .. normalized
    end

    if normalized == "fusion.version" then
      local normalizedVersion = trimText(content)
      local validVersion, versionErr = validateVersionString(normalizedVersion)
      if not validVersion then
        return false, versionErr or "fusion.version invalid"
      end
      if type(expectedVersion) == "string" and trimText(expectedVersion) ~= "" and normalizedVersion ~= trimText(expectedVersion) then
        return false, "Version mismatch: manifest " .. trimText(expectedVersion) .. " vs fusion.version " .. normalizedVersion
      end
      return true, nil
    end

    if normalized:match("%.lua$") then
      return validateLuaScript(content)
    end

    return true, nil
  end

  local function fetchRemoteManifest()
    local ok, body, err = httpGetText(runtime.update.manifestUrl)
    if not ok then
      return false, nil, err or "Manifest download failed"
    end

    local parsedOk, manifest, parseErr = parseManifest(body)
    if not parsedOk then
      return false, nil, parseErr
    end

    return true, manifest, nil
  end

  local function saveManifestCache(manifest)
    if type(textutils) ~= "table" or type(textutils.serializeJSON) ~= "function" then
      return false, "JSON serializer unavailable"
    end

    local ok, encoded = pcall(textutils.serializeJSON, manifest)
    if not ok or type(encoded) ~= "string" or #trimText(encoded) == 0 then
      return false, "Cannot encode manifest cache"
    end

    return writeTextFile(runtime.update.manifestCacheFile, encoded)
  end

  local function readManifestCache()
    if not fs.exists(runtime.update.manifestCacheFile) then
      return false, nil, "Manifest cache missing"
    end

    local ok, body, err = readTextFile(runtime.update.manifestCacheFile)
    if not ok then return false, nil, err end
    return parseManifest(body)
  end

  local function rollbackTargetList(noRemote)
    local okCache, manifest = readManifestCache()
    if okCache and type(manifest) == "table" and type(manifest.files) == "table" then
      return manifest.files
    end

    if not noRemote then
      local okManifest, remoteManifest = fetchRemoteManifest()
      if okManifest then return remoteManifest.files end
    end

    return { "fusion.lua", "fusion.version", "install.lua", "diagviewer.lua" }
  end

  local function hasAnyRollbackBackup(files)
    for _, filePath in ipairs(files or {}) do
      if fs.exists(getBackupPathFor(filePath)) or fs.exists(getMissingBackupMarker(filePath)) then
        return true
      end
    end
    return false
  end

  local function checkForUpdate()
    state.update.lastError = ""
    state.update.downloaded = false
    state.update.manifestLoaded = false
    state.update.filesToUpdate = 0
    state.update.lastManifestError = ""
    pushEvent("Update check started")
    logger.info("Update check started")

    if not UPDATE_ENABLED then
      state.update.httpStatus = "DISABLED"
      state.update.remoteVersion = "DISABLED"
      state.update.available = false
      setUpdateState("DISABLED", "Update disabled", nil)
      logger.warn("Update check skipped: update disabled")
      return false, "Update disabled"
    end

    local okManifest, manifest, errManifest = fetchRemoteManifest()
    if not okManifest then
      state.update.remoteVersion = "UNKNOWN"
      state.update.available = false
      state.update.lastError = errManifest or "Manifest download failed"
      state.update.lastManifestError = state.update.lastError
      setUpdateState("FAILED", "Check failed: " .. state.update.lastError, nil)
      pushEvent("Update failed")
      logger.error("Update check failed", { err = state.update.lastError })
      return false, state.update.lastError
    end

    state.update.manifestLoaded = true
    state.update.lastManifest = manifest
    state.update.remoteVersion = manifest.version
    state.update.filesToUpdate = #manifest.files
    state.update.lastCheckClock = os.clock()
    pushEvent("Manifest loaded " .. manifest.version)
    logger.info("Manifest loaded", { version = manifest.version, files = tostring(#manifest.files) })

    local localVersion = trimText(state.update.localVersion)
    local validLocalVersion, localVersionErr = validateVersionString(localVersion)
    if not validLocalVersion then
      state.update.available = false
      state.update.lastError = localVersionErr or "Local version invalid"
      setUpdateState("FAILED", "Check failed: " .. state.update.lastError, nil)
      pushEvent("Update failed")
      logger.error("Local version invalid", { err = state.update.lastError })
      return false, state.update.lastError
    end
    state.update.localVersion = localVersion

    local cmp = compareVersions(state.update.localVersion, manifest.version)
    if cmp == 1 then
      state.update.available = true
      setUpdateState("UPDATE AVAILABLE", "Remote " .. manifest.version .. " > local " .. state.update.localVersion, nil)
      pushEvent("Update available")
      logger.info("Update available", { localVersion = state.update.localVersion, remoteVersion = manifest.version })
      return true, "Update available"
    elseif cmp == 0 then
      state.update.available = false
      setUpdateState("UP TO DATE", "Local version is current", nil)
      return true, "Up to date"
    end

    state.update.available = false
    setUpdateState("AHEAD", "Local version is newer than remote", nil)
    return true, "Local ahead"
  end

  local function downloadUpdate()
    state.update.lastError = ""
    logger.info("Update download started")
    if not UPDATE_ENABLED then
      setUpdateState("DISABLED", nil, "Update disabled")
      return false, "Update disabled"
    end

    local manifest = state.update.lastManifest
    if type(manifest) ~= "table" then
      local okCheck, checkErr = checkForUpdate()
      if not okCheck then return false, checkErr end
      manifest = state.update.lastManifest
    end

    if type(manifest) ~= "table" then
      setUpdateState("FAILED", nil, "Manifest unavailable")
      return false, "Manifest unavailable"
    end

    setUpdateState("DOWNLOADING", nil, "Downloading files")
    pushEvent("Download started")

    local preserveSet = buildPreserveSet(manifest)
    local downloadedCount = 0
    for _, filePath in ipairs(manifest.files) do
      local normalized = normalizePath(filePath)
      if not isSafeRelativePath(normalized) then
        state.update.lastError = "Unsafe manifest path: " .. tostring(normalized)
        setUpdateState("FAILED", nil, "Manifest path rejected")
        logger.error("Update manifest path rejected", { path = normalized })
        return false, state.update.lastError
      end

      if not isPreservedFile(normalized, preserveSet) then
        local okBody, body, errBody = httpGetText(buildRawFileUrl(normalized))
        if not okBody then
          state.update.lastError = errBody or ("Download failed: " .. normalized)
          setUpdateState("FAILED", nil, "Download failed: " .. normalized)
          pushEvent("Update failed")
          logger.error("Update file download failed", { file = normalized, err = state.update.lastError })
          return false, state.update.lastError
        end

        local valid, reason = validateDownloadedContent(filePath, body, manifest.version)
        if not valid then
          state.update.lastError = reason or ("Validation failed: " .. normalized)
          setUpdateState("FAILED", nil, "Validation failed")
          pushEvent("Update failed")
          logger.error("Update file validation failed", { file = normalized, err = state.update.lastError })
          return false, state.update.lastError
        end

        local tempPath = getTempPathFor(normalized)
        ensureParentDir(tempPath)
        local okWrite, errWrite = writeTextFile(tempPath, body)
        if not okWrite then
          state.update.lastError = errWrite or ("Temp write failed: " .. normalized)
          setUpdateState("FAILED", nil, "Temp write failed")
          pushEvent("Update failed")
          logger.error("Update temp write failed", { file = normalized, err = state.update.lastError })
          return false, state.update.lastError
        end

        downloadedCount = downloadedCount + 1
      end
    end

    local cacheOk, cacheErr = saveManifestCache(manifest)
    if not cacheOk then
      state.update.lastError = cacheErr or "Cannot save manifest cache"
      setUpdateState("FAILED", nil, "Manifest cache failed")
      logger.error("Manifest cache save failed", { err = state.update.lastError })
      return false, state.update.lastError
    end

    state.update.downloaded = true
    state.update.remoteVersion = manifest.version
    state.update.filesToUpdate = #manifest.files
    setUpdateState("DOWNLOADED", nil, "Downloaded " .. tostring(downloadedCount) .. " files")
    pushEvent("Download complete")
    logger.info("Update files downloaded", { count = tostring(downloadedCount) })
    return true, nil
  end

  local function applyUpdate()
    state.update.lastError = ""
    logger.info("Apply update started")
    local manifest = state.update.lastManifest
    if type(manifest) ~= "table" then
      local okManifest, cachedManifest, cacheErr = readManifestCache()
      if not okManifest then
        setUpdateState("FAILED", nil, "Manifest cache missing")
        logger.error("Apply update failed: manifest cache missing", { err = tostring(cacheErr) })
        return false, cacheErr or "Manifest cache missing"
      end
      manifest = cachedManifest
      state.update.lastManifest = manifest
    end

    setUpdateState("APPLYING", nil, "Applying update")
    local preserveSet = buildPreserveSet(manifest)

    for _, filePath in ipairs(manifest.files) do
      local normalized = normalizePath(filePath)
      if not isSafeRelativePath(normalized) then
        state.update.lastError = "Unsafe manifest path: " .. tostring(normalized)
        setUpdateState("FAILED", nil, "Apply rejected")
        logger.error("Apply update rejected path", { path = normalized })
        return false, state.update.lastError
      end
      if not isPreservedFile(normalized, preserveSet) then
        local tempPath = getTempPathFor(normalized)
        if not fs.exists(tempPath) then
          state.update.lastError = "Missing temp file: " .. normalized
          setUpdateState("FAILED", nil, "Apply failed")
          logger.error("Apply update missing temp file", { file = normalized })
          return false, state.update.lastError
        end

        local okTemp, tempBody, tempErr = readTextFile(tempPath)
        if not okTemp then
          state.update.lastError = tempErr or ("Cannot read temp file: " .. normalized)
          setUpdateState("FAILED", nil, "Apply failed")
          logger.error("Apply update cannot read temp file", { file = normalized, err = state.update.lastError })
          return false, state.update.lastError
        end

        local valid, reason = validateDownloadedContent(normalized, tempBody, manifest.version)
        if not valid then
          state.update.lastError = reason or ("Invalid temp file: " .. normalized)
          setUpdateState("FAILED", nil, "Apply failed")
          logger.error("Apply update temp validation failed", { file = normalized, err = state.update.lastError })
          return false, state.update.lastError
        end

        local backupPath = getBackupPathFor(normalized)
        local missingMarker = getMissingBackupMarker(normalized)
        ensureParentDir(backupPath)

        if fs.exists(normalized) then
          local okCurrent, currentBody, currentErr = readTextFile(normalized)
          if not okCurrent then
            state.update.lastError = currentErr or ("Cannot backup file: " .. normalized)
            setUpdateState("FAILED", nil, "Backup failed")
            logger.error("Apply update backup read failed", { file = normalized, err = state.update.lastError })
            return false, state.update.lastError
          end
          local okBackup, backupErr = writeTextFile(backupPath, currentBody)
          if not okBackup then
            state.update.lastError = backupErr or ("Cannot write backup: " .. normalized)
            setUpdateState("FAILED", nil, "Backup failed")
            logger.error("Apply update backup write failed", { file = normalized, err = state.update.lastError })
            return false, state.update.lastError
          end
          if fs.exists(missingMarker) then pcall(fs.delete, missingMarker) end
        else
          local markerOk, markerErr = writeTextFile(missingMarker, "missing\n")
          if not markerOk then
            state.update.lastError = markerErr or ("Cannot mark missing backup: " .. normalized)
            setUpdateState("FAILED", nil, "Backup failed")
            logger.error("Apply update missing marker write failed", { file = normalized, err = state.update.lastError })
            return false, state.update.lastError
          end
        end

        ensureParentDir(normalized)
        local okWrite, writeErr = writeTextFile(normalized, tempBody)
        if not okWrite then
          state.update.lastError = writeErr or ("Cannot replace file: " .. normalized)
          setUpdateState("FAILED", nil, "Apply failed")
          logger.error("Apply update target write failed", { file = normalized, err = state.update.lastError })
          return false, state.update.lastError
        end
      end
    end

    if fs.exists(runtime.update.tempDir) then pcall(fs.delete, runtime.update.tempDir) end
    state.update.downloaded = false
    state.update.restartRequired = true
    state.update.localVersion = manifest.version
    state.update.remoteVersion = manifest.version
    setUpdateState("RESTART REQUIRED", nil, "Update applied. Restart required")
    pushEvent("Update applied")
    pushEvent("Restart required")
    logger.info("Update applied successfully", { version = manifest.version })
    return true, nil
  end

  local function performUpdate()
    local okCheck = checkForUpdate()
    if not okCheck then return false, "Check failed" end
    if not state.update.available then
      setUpdateState("UP TO DATE", state.update.lastCheckResult, "No update to apply")
      return false, "No update available"
    end

    local okDownload, downloadErr = downloadUpdate()
    if not okDownload then return false, downloadErr end

    local okApply, applyErr = applyUpdate()
    if not okApply then return false, applyErr end

    return true, nil
  end

  local function rollbackUpdate()
    logger.warn("Rollback requested")
    local files = rollbackTargetList()
    local restored = 0

    for _, filePath in ipairs(files) do
      local normalized = normalizePath(filePath)
      if not isSafeRelativePath(normalized) then
        setUpdateState("FAILED", nil, "Rollback rejected")
        logger.error("Rollback rejected path", { path = normalized })
        return false, "Unsafe rollback path: " .. tostring(normalized)
      end

      if normalized ~= normalizePath(runtime.files.configFile) then
        local backupPath = getBackupPathFor(normalized)
        local missingMarker = getMissingBackupMarker(normalized)

        if fs.exists(backupPath) then
          local okRead, backupBody, readErr = readTextFile(backupPath)
          if not okRead then
            setUpdateState("FAILED", nil, "Rollback failed")
            logger.error("Rollback read backup failed", { file = normalized, err = tostring(readErr) })
            return false, readErr
          end

          ensureParentDir(normalized)
          local okWrite, writeErr = writeTextFile(normalized, backupBody)
          if not okWrite then
            setUpdateState("FAILED", nil, "Rollback failed")
            logger.error("Rollback write failed", { file = normalized, err = tostring(writeErr) })
            return false, writeErr
          end
          restored = restored + 1
        elseif fs.exists(missingMarker) then
          if fs.exists(normalized) then pcall(fs.delete, normalized) end
          restored = restored + 1
        end
      end
    end

    if fs.exists(runtime.files.versionFile) then
      local okVersion, versionText = readTextFile(runtime.files.versionFile)
      if okVersion then state.update.localVersion = trimText(versionText) end
    end

    state.update.restartRequired = true
    state.update.downloaded = false
    if restored == 0 then
      setUpdateState("FAILED", nil, "No rollback backup available")
      logger.warn("Rollback aborted: no backup available")
      return false, "No rollback backup available"
    end

    setUpdateState("RESTART REQUIRED", nil, "Rollback applied. Restart required")
    pushEvent("Rollback applied")
    pushEvent("Restart required")
    logger.info("Rollback completed", { restored = tostring(restored) })
    return true, nil
  end

  local lastDisplayDiagnostics = nil

  local function getMonitorCandidates()
    local candidates, diagnostics = IoDevices.getMonitorCandidates(peripheral, getTypeOf, safePeripheral, logger)
    lastDisplayDiagnostics = diagnostics
    logger.debug("Display candidates scanned", {
      count = #candidates,
      tom = diagnostics and diagnostics.tomCandidates or 0,
      cc = diagnostics and diagnostics.ccCandidates or 0,
    })
    return candidates
  end

  local function findCandidateByName(candidates, name)
    if type(name) ~= "string" or name == "" then
      return nil
    end
    for _, candidate in ipairs(candidates) do
      if candidate.name == name then
        return candidate
      end
    end
    return nil
  end

  local function keepTopBackendCandidates(candidates)
    if #candidates == 0 then return {} end
    local backend = candidates[1].backend
    local filtered = {}
    for _, candidate in ipairs(candidates) do
      if candidate.backend == backend then
        filtered[#filtered + 1] = candidate
      end
    end
    return filtered
  end

  local function chooseMonitorAuto()
    local monitors = getMonitorCandidates()
    local preferredBackend = CoreConfig.sanitizeDisplayBackend(CFG.displayBackend, "auto")
    local saved = loadSavedMonitorName()
    logger.info("Display preference loaded", {
      backend = preferredBackend,
      preferredMonitor = CFG.preferredMonitor or "none",
      cachedMonitor = saved or "none",
      tomCandidates = tostring((lastDisplayDiagnostics and lastDisplayDiagnostics.tomCandidates) or 0),
      ccCandidates = tostring((lastDisplayDiagnostics and lastDisplayDiagnostics.ccCandidates) or 0),
    })

    if #monitors == 0 then
      return nil, { reason = "no_candidates", preferredBackend = preferredBackend }
    end

    local filtered = monitors
    local fallbackReason = nil
    if preferredBackend ~= "auto" then
      filtered = {}
      for _, candidate in ipairs(monitors) do
        if candidate.backend == preferredBackend then
          filtered[#filtered + 1] = candidate
        end
      end
      if #filtered == 0 then
        fallbackReason = "preferred_backend_unavailable"
        local rejectionLabel = preferredBackend == "toms_gpu"
          and "Tom backend rejected"
          or "Preferred backend rejected"
        logger.warn(rejectionLabel, {
          preferred = preferredBackend,
          reason = "no_matching_candidate",
          tomRejected = tostring((lastDisplayDiagnostics and lastDisplayDiagnostics.tomRejected) or 0),
        })
        filtered = monitors
      end
    end

    local candidatesForNamePreference = filtered
    if preferredBackend == "auto" then
      candidatesForNamePreference = keepTopBackendCandidates(filtered)
      local cachedOutsideTop = findCandidateByName(filtered, saved)
      if cachedOutsideTop and not findCandidateByName(candidatesForNamePreference, saved) then
        logger.info("Cached monitor ignored", {
          cachedMonitor = saved,
          cachedBackend = cachedOutsideTop.backend or "unknown",
          reason = "higher_priority_backend_available",
          selectedBackend = candidatesForNamePreference[1] and candidatesForNamePreference[1].backend or "unknown",
        })
      end
    end

    local selectionReason = "first_candidate"
    local chosen = findCandidateByName(candidatesForNamePreference, CFG.preferredMonitor)
    if chosen then
      selectionReason = "config_preferred_monitor"
    else
      chosen = findCandidateByName(candidatesForNamePreference, saved)
      if chosen then
        selectionReason = "cache_monitor"
      else
        chosen = candidatesForNamePreference[1]
        selectionReason = preferredBackend == "auto" and "auto_top_backend" or "backend_filtered_first"
      end
    end

    if not chosen then
      chosen = filtered[1]
      selectionReason = "filtered_first"
    end

    if preferredBackend ~= "auto" and chosen and chosen.backend ~= preferredBackend then
      logger.warn("Fallback to " .. tostring(chosen.backend or "unknown"), {
        preferred = preferredBackend,
        selected = chosen.backend or "unknown",
        reason = fallbackReason or "preferred_unusable",
      })
    end

    if chosen then
      saveSelectedMonitorName(chosen.name)
    end
    return chosen, {
      reason = selectionReason,
      preferredBackend = preferredBackend,
      fallbackReason = fallbackReason,
    }
  end

  setupMonitor = function()
    local chosen, selectionMeta = chooseMonitorAuto()
    hw.monitor = chosen and chosen.obj or nil
    hw.monitorName = chosen and chosen.name or nil
    if type(IoMonitor.setupMonitor) ~= "function" then
      logger.error("IoMonitor.setupMonitor unavailable")
      return false
    end
    IoMonitor.setupMonitor(nativeTerm, hw, CFG, C, chosen, getTypeOf, logger)
    if chosen then
      logger.info("Display backend selected", {
        name = chosen.name,
        backend = hw.monitorBackend or chosen.backend or "unknown",
        size = tostring(chosen.w or 0) .. "x" .. tostring(chosen.h or 0),
        reason = selectionMeta and selectionMeta.reason or "unknown",
      })
      if selectionMeta and selectionMeta.fallbackReason then
        logger.warn("Display fallback applied", {
          preferred = selectionMeta.preferredBackend or "auto",
          selected = hw.monitorBackend or chosen.backend or "unknown",
          reason = selectionMeta.fallbackReason,
        })
      end
    else
      logger.warn("No monitor selected; terminal fallback active")
    end
    return true
  end

  local function resolveDisplayOutputMode()
    local mode = CoreConfig.sanitizeDisplayOutput(CFG.displayOutput, "monitor")
    if mode ~= "terminal" and not hw.monitor then
      return "terminal"
    end
    return mode
  end

  local function isSourceEnabled(source)
    local mode = resolveDisplayOutputMode()
    if source == "terminal" then
      return mode == "terminal" or mode == "both"
    end
    if source == "monitor" then
      return mode == "monitor" or mode == "both"
    end
    return false
  end

  local function restoreTerm()
    term.redirect(nativeTerm)
    term.setCursorBlink(false)
  end

  local function scanPeripherals()
    IoDevices.scanPeripherals(peripheral, hw, CFG, safePeripheral, getTypeOf, contains, logger)
  end

  local function resolveKnownRelays()
    IoRelays.resolveKnownRelays(CFG, hw.relays)
  end

  local function scanBlockReaders()
    resolveKnownRelays()
    IoReaders.scanBlockReaders(hw, CFG.knownReaders, logger)
  end

  local function readChemicalFromReader(entry)
    return IoReaders.readChemicalFromReader(entry, toNumber)
  end

  local function readActiveFromReader(entry)
    return IoReaders.readActiveFromReader(entry, toNumber)
  end

  local function relayWrite(actionName, on)
    return IoRelays.relayWrite(CFG.actions, hw.relays, actionName, on, logger)
  end

  local function readRelayOutputState(actionName, fallback)
    return IoRelays.readRelayOutputState(CFG.actions, hw.relays, actionName, fallback, toNumber, logger)
  end

  local function ensureRelayLow(actionName)
    return IoRelays.ensureRelayLow(CFG.actions, hw.relays, actionName, logger)
  end

  local runtimeRefresh = CoreRuntimeRefresh.build({
    state = state,
    hw = hw,
    CFG = CFG,
    tryMethods = tryMethods,
    safeCall = safeCall,
    toNumber = toNumber,
    clamp = clamp,
    normalizePortMode = normalizePortMode,
    scanPeripherals = scanPeripherals,
    scanBlockReaders = scanBlockReaders,
    readChemicalFromReader = readChemicalFromReader,
    readActiveFromReader = readActiveFromReader,
    readRelayOutputState = readRelayOutputState,
    ensureRelayLow = ensureRelayLow,
    refreshSetupDeviceStatus = refreshSetupDeviceStatus,
    pushEvent = pushEvent,
    log = logger,
  })

  local refreshAll = runtimeRefresh.refreshAll

  local runtimeActions = CoreActions.build({
    state = state,
    CFG = CFG,
    relayWrite = relayWrite,
    pushEvent = pushEvent,
    runtimeAlerts = runtimeAlerts,
    log = logger,
  })

  function getHitboxBucket(source)
    return source == "monitor" and touchHitboxes.monitor or touchHitboxes.terminal
  end

  function clearHitboxes(source)
    if source then
      local bucket = getHitboxBucket(source)
      for i = #bucket, 1, -1 do bucket[i] = nil end
      return
    end
    clearHitboxes("terminal")
    clearHitboxes("monitor")
  end

  function addHitbox(source, id, x1, y1, x2, y2, action)
    if type(action) ~= "function" then return end
    local bx1 = math.floor(math.min(x1, x2))
    local by1 = math.floor(math.min(y1, y2))
    local bx2 = math.floor(math.max(x1, x2))
    local by2 = math.floor(math.max(y1, y2))
    local area = math.max(1, (bx2 - bx1 + 1) * (by2 - by1 + 1))
    local bucket = getHitboxBucket(source)
    bucket[#bucket + 1] = {
      id = id,
      x1 = bx1,
      y1 = by1,
      x2 = bx2,
      y2 = by2,
      area = area,
      action = action,
    }
  end

  function isInsideBox(x, y, box)
    return x >= box.x1 and x <= box.x2 and y >= box.y1 and y <= box.y2
  end

  function setButtonPressed(source, id)
    pressedButtons[source .. ":" .. id] = os.clock() + pressedEffectDuration
  end

  function isButtonPressed(source, id)
    local key = source .. ":" .. id
    local untilTs = pressedButtons[key]
    if not untilTs then return false end
    if os.clock() <= untilTs then return true end
    pressedButtons[key] = nil
    return false
  end

  function addButton(id, x, y, w, h, label, bg, fg, action, opts)
    opts = opts or {}
    local width = math.max(3, w)
    local height = math.max(2, h or (opts.big and 3 or 2))
    local maxW, maxH = term.getSize()
    if y > maxH or x > maxW then return end
    if (y + height - 1) < 1 or (x + width - 1) < 1 then return end
    x = clamp(x, 1, maxW)
    y = clamp(y, 1, maxH)
    width = clamp(width, 1, maxW - x + 1)
    height = clamp(height, 1, maxH - y + 1)

    local hitPadX = opts.hitPadX
    local hitPadY = opts.hitPadY

    if hitPadX == nil then
      hitPadX = HITBOX_DEFAULTS.basePadX
      if width <= HITBOX_DEFAULTS.minW then
        hitPadX = math.max(hitPadX, HITBOX_DEFAULTS.smallBoostPadX)
      end
      if opts.kind == "row" then
        hitPadX = math.max(hitPadX, HITBOX_DEFAULTS.rowPadX)
      end
    end

    if hitPadY == nil then
      hitPadY = HITBOX_DEFAULTS.basePadY
      if height <= HITBOX_DEFAULTS.minH then
        hitPadY = math.max(hitPadY, HITBOX_DEFAULTS.smallBoostPadY)
      end
      if opts.kind == "row" then
        hitPadY = math.max(hitPadY, HITBOX_DEFAULTS.rowPadY)
      end
    end

    buttons[#buttons + 1] = {
      id = id,
      x = x,
      y = y,
      w = width,
      h = height,
      label = shortText(tostring(label or ""), math.max(1, width)),
      bg = bg,
      fg = fg or C.btnText,
      action = action,
      hitPadX = hitPadX,
      hitPadY = hitPadY,
      hitbox = opts.hitbox,
      isBig = opts.big,
      style = opts.style,
      disabled = opts.disabled,
    }
  end

  function resolveButtonStyle(button)
    if button.style and styles.button[button.style] then
      return styles.button[button.style]
    end

    local id = tostring(button.id or "")
    if button.disabled then return styles.button.disabled end
    if id == "setupSave" or id == "cfgSave" or id == "updRestart" then return styles.button.success end
    if id == "setupInstaller" or id == "arret" or id == "manualStop" then return styles.button.danger end
    if button.bg == C.btnWarn then return styles.button.danger end
    if button.bg == C.tritium then return styles.button.fuelT end
    if button.bg == C.deuterium then return styles.button.fuelD end
    if button.bg == C.dtFuel then return styles.button.fuelDT end
    if button.bg == C.btnAction then return styles.button.primary end

    return styles.button.secondary
  end

  function isTabButton(button)
    return type(button.id) == "string" and string.sub(button.id, 1, 4) == "view"
  end

  function drawButtonLabel(button, textColor, faceColor, isPressed)
    local textOffset = 0
    local lx = button.x + math.max(1, math.floor((button.w - #button.label) / 2)) + textOffset
    local ly = button.y + math.floor((button.h - 1) / 2) + textOffset
    lx = clamp(lx, button.x, button.x + button.w - #button.label)
    ly = clamp(ly, button.y, button.y + button.h - 1)
    writeAt(lx, ly, button.label, textColor or button.fg, faceColor)
  end

  function drawButtonSprite(button, style)
    local skin = style or resolveButtonStyle(button)
    ui.fill(button.x, button.y, button.w, button.h, skin.face)
    return skin.face, skin.text
  end

  function drawButtonPressedSprite(button, style)
    local skin = style or resolveButtonStyle(button)
    local pressed = { face = UI_PALETTE.buttonPressed, border = skin.border or C.border, text = skin.text }
    return drawButtonSprite(button, pressed)
  end

  function drawButtonDisabledSprite(button)
    return drawButtonSprite(button, styles.button.disabled)
  end

  function drawButtonActiveSprite(button, style)
    return drawButtonSprite(button, style or resolveButtonStyle(button))
  end

  function drawTabSprite(x, y, w, h, label, isActive, isPressed)
    local face = isActive and C.info or C.panelMid
    if isPressed then
      face = C.panel
    end

    ui.fill(x, y, w, h, face)

    local txt = shortText(label, math.max(1, w))
    local tx = x + math.max(0, math.floor((w - #txt) / 2))
    local ty = y + math.floor((h - 1) / 2)
    ui.write(tx, ty, txt, isActive and C.text or C.dim, face)
  end

  function drawTabBar(button, isPressed)
    local isActive = button.bg == C.btnOn
    drawTabSprite(button.x, button.y, button.w, button.h, button.label, isActive, isPressed)
    return button.bg, C.text
  end

  function drawFuelButton(button, isPressed)
    local style = resolveButtonStyle(button)
    return isPressed and drawButtonPressedSprite(button, style) or drawButtonActiveSprite(button, style)
  end

  function drawPrimaryButton(button, isPressed)
    local style = resolveButtonStyle(button)
    return isPressed and drawButtonPressedSprite(button, style) or drawButtonActiveSprite(button, style)
  end

  function drawActionButton(button, isPressed)
    local style = resolveButtonStyle(button)
    return isPressed and drawButtonPressedSprite(button, style) or drawButtonActiveSprite(button, style)
  end

  function drawControlButton(button, isPressed)
    if button.disabled then return drawButtonDisabledSprite(button) end
    if isTabButton(button) then return drawTabBar(button, isPressed) end
    if button.bg == C.tritium or button.bg == C.deuterium or button.bg == C.dtFuel then
      return drawFuelButton(button, isPressed)
    end
    if button.bg == C.btnAction then
      return drawActionButton(button, isPressed)
    end
    return drawPrimaryButton(button, isPressed)
  end

  function drawButton(source, button)
    local isPressed = (not button.disabled) and isButtonPressed(source, button.id)
    local faceColor, textColor = drawControlButton(button, isPressed)
    if not isTabButton(button) then
      drawButtonLabel(button, textColor, faceColor, isPressed)
    end

    local maxW, maxH = term.getSize()
    local baseX1 = button.x
    local baseY1 = button.y
    local baseX2 = button.x + button.w - 1
    local baseY2 = button.y + button.h - 1
    if type(button.hitbox) == "table" then
      baseX1 = button.hitbox.x1 or baseX1
      baseY1 = button.hitbox.y1 or baseY1
      baseX2 = button.hitbox.x2 or baseX2
      baseY2 = button.hitbox.y2 or baseY2
    end
    local x1 = clamp(baseX1 - button.hitPadX, 1, maxW)
    local y1 = clamp(baseY1 - button.hitPadY, 1, maxH)
    local x2 = clamp(baseX2 + button.hitPadX, 1, maxW)
    local y2 = clamp(baseY2 + button.hitPadY, 1, maxH)
    if not button.disabled then
      addHitbox(source, button.id, x1, y1, x2, y2, button.action)
    end
  end

  function drawBigButton(id, x, y, w, label, bg, action)
    addButton(id, x, y, w, 2, label, bg, C.btnText, action, { big = true })
  end

  function addRowButton(id, x, y, w, h, label, bg, fg, action)
    addButton(id, x, y, w, h, label, bg, fg, action, {
      kind = "row",
      hitbox = { x1 = x, y1 = y, x2 = x + w - 1, y2 = y + h - 1 },
    })
  end

  function drawHitboxBox(hit)
    for xx = hit.x1, hit.x2 do
      writeAt(xx, hit.y1, " ", C.warn, colors.brown)
      writeAt(xx, hit.y2, " ", C.warn, colors.brown)
    end
    for yy = hit.y1, hit.y2 do
      writeAt(hit.x1, yy, " ", C.warn, colors.brown)
      writeAt(hit.x2, yy, " ", C.warn, colors.brown)
    end
  end

  function drawHitboxLabel(hit)
    local label = shortText(hit.id or "btn", math.max(3, hit.x2 - hit.x1 + 1))
    writeAt(hit.x1, hit.y1, label, C.text, colors.cyan)
  end

  function drawHitboxDebugOverlay(source)
    if not state.debugHitboxes then return end
    local bucket = getHitboxBucket(source)
    for _, hit in ipairs(bucket) do
      drawHitboxBox(hit)
      drawHitboxLabel(hit)
    end
  end

  function startMonitorSelection()
    state.choosingMonitor = true
    state.monitorList = getMonitorCandidates()
    state.monitorPage = 1
    state.uiDrawn = false
    state.lastAction = "Selection moniteur"
  end

  function stopMonitorSelection()
    state.choosingMonitor = false
    state.uiDrawn = false
  end

  function selectMonitorByIndex(index)
    local m = state.monitorList[index]
    if not m then return end
    saveSelectedMonitorName(m.name)
    invokeSetupMonitor("monitor select")
    stopMonitorSelection()
    state.lastAction = "Moniteur: " .. m.name
    pushEvent("Monitor changed")
  end

  local function ensureSetupWorking()
    if type(state.setup) ~= "table" then
      state.setup = {}
    end

    if type(state.setup.working) ~= "table" then
      loadRuntimeSetupConfig()
    end

    if type(state.setup.working) ~= "table" then
      refreshSetupWorkingConfig(CoreConfig.defaultFusionConfig(CFG, UPDATE_ENABLED))
    end

    return state.setup.working
  end

  local function applySetupScaleRuntime(working)
    if type(working) ~= "table" then return end
    if type(working.ui) ~= "table" then working.ui = {} end
    if type(working.monitor) ~= "table" then working.monitor = {} end

    CFG.uiScale = CoreConfig.sanitizeUiScale(working.ui.scale, CFG.uiScale or 1.0)
    CFG.displayOutput = CoreConfig.sanitizeDisplayOutput(working.ui.output, CFG.displayOutput or "monitor")
    CFG.displayBackend = CoreConfig.sanitizeDisplayBackend(working.ui.displayBackend, CFG.displayBackend or "auto")
    CFG.energyUnit = CoreConfig.sanitizeEnergyUnit(working.ui.energyUnit, CFG.energyUnit or "j")
    CFG.laserCount = CoreConfig.sanitizeLaserCount(working.ui.laserCount, CFG.laserCount or 1)
    CFG.monitorScale = CoreConfig.sanitizeMonitorScale(working.monitor.scale, CFG.monitorScale or 0.5)
    working.ui.scale = CFG.uiScale
    working.ui.output = CFG.displayOutput
    working.ui.displayBackend = CFG.displayBackend
    working.ui.energyUnit = CFG.energyUnit
    working.ui.laserCount = CFG.laserCount
    working.monitor.scale = CFG.monitorScale

    invokeSetupMonitor("setup scale")
    state.uiDrawn = false
  end

  local function reloadSetupConfig()
    local ok, config, err = loadFusionConfig()
    if not ok or type(config) ~= "table" then
      state.setup.saveStatus = "RELOAD FAILED"
      state.setup.lastMessage = tostring(err or "Config missing")
      state.lastAction = "Reload failed"
      pushEvent("Reload failed")
      return false
    end

    applyConfigToRuntime(config)
    refreshSetupWorkingConfig(config)
    refreshSetupDeviceStatus()
    invokeSetupMonitor("reload cfg")

    state.setup.saveStatus = "CONFIG RELOADED"
    state.setup.lastMessage = "Configuration reloaded"
    state.setup.dirty = false
    state.lastAction = "Config reloaded"
    pushEvent("Config reloaded")
    return true
  end

  local function adjustDisplayScale(delta)
    local working = ensureSetupWorking()
    local uiCfg = working.ui or {}
    working.ui = uiCfg

    local current = CoreConfig.sanitizeUiScale(uiCfg.scale, CFG.uiScale or 1.0)
    local tw, th = term.getSize()
    local maxBySurface = math.min(2.0, tw / 34, th / 14)
    if maxBySurface < 0.5 then maxBySurface = 0.5 end
    local desired = current + (delta or 0)
    if desired > maxBySurface then desired = maxBySurface end
    local nextScale = CoreConfig.sanitizeUiScale(desired, current)
    uiCfg.scale = nextScale
    state.setup.dirty = true
    state.setup.lastMessage = string.format("UI scale %.1fx", nextScale)
    state.lastAction = "UI scale " .. string.format("%.1fx", nextScale)
    applySetupScaleRuntime(working)
    pushEvent(state.lastAction)
  end

  local function adjustTextScale(delta)
    local working = ensureSetupWorking()
    local monitorCfg = working.monitor or {}
    working.monitor = monitorCfg

    local current = CoreConfig.sanitizeMonitorScale(monitorCfg.scale, CFG.monitorScale or 0.5)
    local nextScale = CoreConfig.sanitizeMonitorScale(current + (delta or 0), current)
    monitorCfg.scale = nextScale
    state.setup.dirty = true
    state.setup.lastMessage = string.format("Text scale %.1fx", nextScale)
    state.lastAction = "Text scale " .. string.format("%.1fx", nextScale)
    applySetupScaleRuntime(working)
    pushEvent(state.lastAction)
  end

  local function setDisplayOutput(mode)
    local working = ensureSetupWorking()
    local uiCfg = working.ui or {}
    working.ui = uiCfg

    local nextMode = CoreConfig.sanitizeDisplayOutput(mode, CFG.displayOutput or "monitor")
    uiCfg.output = nextMode
    state.setup.dirty = true
    state.setup.lastMessage = "Display output: " .. string.upper(nextMode)
    state.lastAction = "Output " .. string.upper(nextMode)
    applySetupScaleRuntime(working)
    pushEvent(state.lastAction)
  end

  local function setEnergyUnit(unit)
    local working = ensureSetupWorking()
    local uiCfg = working.ui or {}
    working.ui = uiCfg

    local nextUnit = CoreConfig.sanitizeEnergyUnit(unit, CFG.energyUnit or "j")
    uiCfg.energyUnit = nextUnit
    state.setup.dirty = true
    state.setup.lastMessage = "Energy unit: " .. string.upper(nextUnit)
    state.lastAction = "Unit " .. string.upper(nextUnit)
    applySetupScaleRuntime(working)
    pushEvent(state.lastAction)
  end

  local function adjustLaserCount(delta)
    local working = ensureSetupWorking()
    local uiCfg = working.ui or {}
    working.ui = uiCfg

    local current = CoreConfig.sanitizeLaserCount(uiCfg.laserCount, CFG.laserCount or 1)
    local nextCount = CoreConfig.sanitizeLaserCount(current + toNumber(delta, 0), current)
    uiCfg.laserCount = nextCount
    state.setup.dirty = true
    state.setup.lastMessage = "Lasers: " .. tostring(nextCount)
    state.lastAction = "Laser count " .. tostring(nextCount)
    applySetupScaleRuntime(working)
    pushEvent(state.lastAction)
  end

  local function setInjectionRate(targetRate)
    local target = hw.logic or hw.reactor
    if not target or type(target.setInjectionRate) ~= "function" then
      state.lastAction = "Injection indisponible"
      pushEvent("Injection unavailable")
      return false
    end

    local minRate = toNumber(state.injectionMin, 0)
    local maxRate = math.max(minRate, toNumber(state.injectionMax, 98))
    local desired = clamp(math.floor(toNumber(targetRate, state.injectionRate) + 0.5), minRate, maxRate)

    local okSet = safeCall(target, "setInjectionRate", desired)
    if not okSet then
      state.lastAction = "Set injection echec"
      pushEvent("Injection set failed")
      return false
    end

    local okRead, confirmed = safeCall(target, "getInjectionRate")
    if okRead then
      state.injectionRate = clamp(math.floor(toNumber(confirmed, desired) + 0.5), minRate, maxRate)
    else
      state.injectionRate = desired
    end

    state.lastAction = "Injection " .. tostring(state.injectionRate)
    pushEvent(state.lastAction)
    return true
  end

  local function adjustInjectionRate(delta)
    local current = toNumber(state.injectionRate, 0)
    return setInjectionRate(current + toNumber(delta, 0))
  end

  local function buildButtonActions()
    return {
      selectMonitorByIndex = selectMonitorByIndex,
      stopMonitorSelection = stopMonitorSelection,
      startMonitorSelection = startMonitorSelection,
      refreshNow = function()
        refreshAll()
        state.lastAction = "Refresh"
      end,
      setView = function(view)
        state.currentView = view
        pushEvent("View " .. view)
      end,
      canIgnite = runtimeAlerts.canIgnite,
      startReactorSequence = runtimeActions.startReactorSequence,
      stopManualReactor = function() runtimeActions.stopReactorSequence("ARRET DEMANDE") end,
      stopRequested = function() runtimeActions.stopReactorSequence("ARRET DEMANDE") end,
      toggleTritium = function() runtimeActions.openTritium(not state.tOpen) end,
      toggleDeuterium = function() runtimeActions.openDeuterium(not state.dOpen) end,
      toggleDTFuel = function()
        local nextState = not state.dtOpen
        runtimeActions.openDTFuel(nextState)
        if nextState then runtimeActions.openSeparatedGases(false) end
      end,
      fireLaser = runtimeActions.fireLaser,
      checkForUpdate = function()
        local ok, err = pcall(checkForUpdate)
        if not ok then
          state.update.lastError = tostring(err)
          setUpdateState("FAILED", "Check crashed", "No apply")
          pushEvent("Update failed")
        end
      end,
      performUpdate = function()
        local ok, result, err = pcall(performUpdate)
        if not ok then
          state.update.lastError = tostring(result)
          setUpdateState("FAILED", nil, "Update crashed")
          pushEvent("Update failed")
        elseif result == false then
          state.update.lastError = tostring(err or "No update available")
          state.lastAction = "No update"
        end
      end,
      restartProgram = function()
        state.pendingRestart = true
        state.running = false
        state.lastAction = "Restart requested"
        pushEvent("Restart requested")
      end,
      toggleDebugHitboxes = function()
        state.debugHitboxes = not state.debugHitboxes
        state.lastAction = state.debugHitboxes and "Hitbox debug ON" or "Hitbox debug OFF"
        pushEvent(state.lastAction)
      end,
      hasRollback = function()
        return hasAnyRollbackBackup(rollbackTargetList(true))
      end,
      rollbackUpdate = function()
        local ok, err = pcall(rollbackUpdate)
        if not ok then
          state.update.lastError = tostring(err)
          setUpdateState("FAILED", nil, "Rollback crashed")
          pushEvent("Update failed")
        end
      end,
      runSetupTest = runSetupTest,
      setupStartRebind = setupStartRebind,
      setupApplySelection = setupApplySelection,
      adjustDisplayScale = adjustDisplayScale,
      adjustTextScale = adjustTextScale,
      adjustInjectionRate = adjustInjectionRate,
      setDisplayOutput = setDisplayOutput,
      setEnergyUnit = setEnergyUnit,
      adjustLaserCount = adjustLaserCount,
      saveSetupConfig = saveSetupConfig,
      reloadSetupConfig = reloadSetupConfig,
      runInstallerFromSetup = runInstallerFromSetup,
      toggleMaster = function()
        state.autoMaster = not state.autoMaster
        if not state.autoMaster then
          runtimeActions.openDTFuel(false)
          runtimeActions.openSeparatedGases(false)
          runtimeActions.setLaserCharge(false)
          state.ignitionSequencePending = false
          state.status = "MASTER OFF"
        else
          state.status = "MASTER ON"
        end
        state.lastAction = "Toggle MASTER"
      end,
      toggleFusion = function()
        state.fusionAuto = not state.fusionAuto
        state.lastAction = "Toggle FUSION"
      end,
      toggleCharge = function()
        state.chargeAuto = not state.chargeAuto
        state.lastAction = "Toggle CHARGE"
      end,
    }
  end

  function buildButtons(layout)
    buttons = {}
    UIComponents.buildButtons({
      state = state,
      C = C,
      clamp = clamp,
      shortText = shortText,
      addButton = addButton,
      addRowButton = addRowButton,
      drawBigButton = drawBigButton,
      actions = buildButtonActions(),
    }, layout)
  end

  function getCurrentInputSource()
    return currentDrawSource
  end

  function drawButtons(source)
    clearHitboxes(source)
    for _, b in ipairs(buttons) do
      drawButton(source, b)
    end
    drawHitboxDebugOverlay(source)
  end

  function handleClick(x, y, source)
    if not isSourceEnabled(source) then
      return false
    end
    if type(x) ~= "number" or type(y) ~= "number" then
      return false
    end
    local bucket = getHitboxBucket(source)
    local chosen = nil
    for i = #bucket, 1, -1 do
      local hit = bucket[i]
      if isInsideBox(x, y, hit) then
        -- En cas de chevauchement, on retient la zone la plus petite
        -- pour privilegier le bouton le plus precis.
        if not chosen or hit.area < chosen.area then
          chosen = { hit = hit, area = hit.area }
        end
      end
    end
    if chosen then
      setButtonPressed(source, chosen.hit.id)
      chosen.hit.action()
      return true
    end
    return false
  end



  inductionStatus = function()
    if not state.inductionPresent then return "OFFLINE", C.bad end
    if not state.inductionFormed then return "UNFORMED", C.warn end

    local pct = toNumber(state.inductionPct, 0)
    local inp = toNumber(state.inductionInput, 0)
    local out = toNumber(state.inductionOutput, 0)

    if pct <= 0.2 then return "EMPTY", C.bad end
    if pct <= 10 then return "LOW", C.warn end
    if pct >= 99.9 then return "FULL", C.ok end
    if inp > 0 and out <= 0 then return "CHARGING", C.ok end
    if inp > out then return "CHARGING", C.ok end
    if out > inp then return "DISCHARGING", C.warn end
    return "ONLINE", C.info
  end

  getInductionFillRatio = function()
    return CoreInduction.getFillRatio(state)
  end

  local cachedUIViewContext = nil

  local function buildUIViewContext()
    -- Contexte UI memoise pour eviter de reconstruire la meme table
    -- a chaque sous-vue pendant un frame.
    if cachedUIViewContext then
      return cachedUIViewContext
    end

    cachedUIViewContext = UIViews.buildContext({
      C = C,
      state = state,
      hw = hw,
      CFG = CFG,
      fs = fs,
      UPDATE_ENABLED = UPDATE_ENABLED,
      UPDATE_TEMP_DIR = runtime.update.tempDir,
      UPDATE_MISSING_BACKUP_SUFFIX = runtime.update.missingBackupSuffix,
      drawBox = drawBox,
      writeAt = writeAt,
      drawKeyValue = drawKeyValue,
      drawBadge = drawBadge,
      shortText = shortText,
      clamp = clamp,
      fmt = fmt,
      formatTemperature = formatTemperature,
      formatEnergy = formatEnergy,
      formatEnergyPerTick = formatEnergyPerTick,
      formatMJ = formatMJ,
      yesno = yesno,
      reactorPhase = reactorPhase,
      phaseColor = phaseColor,
      getRuntimeFuelMode = getRuntimeFuelMode,
      isRuntimeFuelOk = isRuntimeFuelOk,
      statusColor = statusColor,
      drawHeader = drawHeader,
      drawFooter = drawFooter,
      buildButtons = buildButtons,
      drawButtons = drawButtons,
      getCurrentInputSource = getCurrentInputSource,
      drawControlPanel = drawControlPanel,
      drawReactorDiagram = drawReactorDiagram,
      drawInductionDiagram = drawInductionDiagram,
      inductionStatus = inductionStatus,
      hasAnyRollbackBackup = hasAnyRollbackBackup,
      rollbackTargetList = rollbackTargetList,
      getSetupStatusRows = getSetupStatusRows,
    })
    return cachedUIViewContext
  end

  function drawMonitorSelection(layout)
    UIViews.drawMonitorSelection(buildUIViewContext(), layout)
  end

  function drawControlPanel(panel, layout)
    drawBox(panel.x, panel.y, panel.w, panel.h, "CONTROL SYSTEM", C.border)

    local innerX = panel.x + 1
    local innerW = panel.w - 2
    local headerY = panel.y + 1
    local headerText = "CONTROL SYSTEM"
    local modeText = "MODE " .. string.upper(state.currentView or "supervision")
    ui.hline(innerX, headerY, innerW, C.headerBg)
    local titleX = panel.x + math.max(1, math.floor((panel.w - #headerText) / 2))
    writeAt(titleX, headerY, headerText, C.text, C.headerBg)
    local modeX = panel.x + panel.w - #modeText - 2
    if modeX > titleX + #headerText then
      writeAt(modeX, headerY, modeText, C.info, C.headerBg)
    end

    local showIo = state.currentView ~= "setup"
    local ioH = 0
    if showIo then
      ioH = clamp(math.floor(panel.h * 0.30), 6, 10)
    end

    local buttonsTop = panel.y + 2
    local buttonsBottom = panel.y + panel.h - 2 - ioH - (showIo and 1 or 0)
    if buttonsBottom < buttonsTop then buttonsBottom = buttonsTop end

    state.controlBounds = {
      x = panel.x + 2,
      y = buttonsTop,
      w = math.max(8, panel.w - 4),
      h = math.max(3, buttonsBottom - buttonsTop + 1),
    }

    buildButtons(layout)
    drawButtons(getCurrentInputSource())

    if showIo then
      local ioY = buttonsBottom + 1
      local ioRealH = (panel.y + panel.h - 1) - ioY
      if ioRealH >= 4 then
        UIComponents.drawIoPanel(buildUIViewContext(), panel.x + 1, ioY, panel.w - 2, ioRealH)
      end
    end
  end

  function drawDiagnosticView(layout)
    UIViews.drawDiagnosticView(buildUIViewContext(), layout)
  end

  function drawInductionView(layout)
    UIViews.drawInductionView(buildUIViewContext(), layout)
  end

  function drawManualView(layout)
    UIViews.drawManualView(buildUIViewContext(), layout)
  end

  function drawSupervisionView(layout)
    UIViews.drawSupervisionView(buildUIViewContext(), layout)
  end

  function drawUpdateView(layout)
    UIViews.drawUpdateView(buildUIViewContext(), layout)
  end

  function drawConfigView(layout)
    UIViews.drawConfigView(buildUIViewContext(), layout)
  end

  function drawSetupView(layout)
    UIViews.drawSetupView(buildUIViewContext(), layout)
  end

  local function drawUI()
    local function drawSurface(source, surface)
      term.redirect(surface)
      currentDrawSource = source
      clearHitboxes(source)
      state.controlBounds = nil

      local tw, th = term.getSize()
      local layout = computeLayout(tw, th)

      term.setBackgroundColor(C.bg)
      term.setTextColor(C.text)
      term.clear()

      if layout.tooSmall then
        centerText(math.max(2, math.floor(th / 2) - 1), "Ecran trop petit", C.bad, C.bg)
        centerText(math.max(3, math.floor(th / 2)), "Minimum recommande: " .. layout.minW .. "x" .. layout.minH, C.warn, C.bg)
        return
      end

      if state.choosingMonitor then
        drawMonitorSelection(layout)
        return
      end

      drawHeader("FUSION SUPERVISOR", state.status)

      if state.currentView == "diagnostic" then
        drawDiagnosticView(layout)
      elseif state.currentView == "manual" then
        drawManualView(layout)
      elseif state.currentView == "induction" then
        drawInductionView(layout)
      elseif state.currentView == "update" then
        drawUpdateView(layout)
      elseif state.currentView == "config" then
        drawConfigView(layout)
      elseif state.currentView == "setup" then
        drawSetupView(layout)
      else
        drawSupervisionView(layout)
      end

      drawFooter(layout)

      if type(surface.flush) == "function" then
        pcall(surface.flush)
      elseif type(surface.sync) == "function" then
        pcall(surface.sync)
      end
    end

    local mode = resolveDisplayOutputMode()
    local monitorSurface = hw.displaySurface or hw.monitor
    if mode == "monitor" and monitorSurface then
      drawSurface("monitor", monitorSurface)
      clearHitboxes("terminal")
    elseif mode == "both" and monitorSurface then
      drawSurface("terminal", nativeTerm)
      drawSurface("monitor", monitorSurface)
    else
      drawSurface("terminal", nativeTerm)
      clearHitboxes("monitor")
    end

    currentDrawSource = "terminal"
    term.redirect(nativeTerm)
    term.setCursorBlink(false)
    state.uiDrawn = true
  end

  local startupOk = CoreStartup.run({
    state = state,
    ensureConfigOrInstaller = ensureConfigOrInstaller,
    restoreTerm = restoreTerm,
    applyPremiumPalette = applyPremiumPalette,
    readLocalVersionFile = readLocalVersionFile,
    setupMonitor = setupMonitor,
    refreshAll = refreshAll,
    pushEvent = pushEvent,
    log = logger,
    UPDATE_ENABLED = UPDATE_ENABLED,
    checkForUpdate = checkForUpdate,
  })
  if not startupOk then
    return
  end

  CoreRuntimeLoop.run({
    state = state,
    hw = hw,
    CFG = CFG,
    refreshAll = refreshAll,
    fullAuto = runtimeActions.fullAuto,
    drawUI = drawUI,
    handleClick = handleClick,
    setupMonitor = setupMonitor,
    getMonitorCandidates = getMonitorCandidates,
    selectMonitorByIndex = selectMonitorByIndex,
    stopMonitorSelection = stopMonitorSelection,
    startMonitorSelection = startMonitorSelection,
    openDTFuel = runtimeActions.openDTFuel,
    openSeparatedGases = runtimeActions.openSeparatedGases,
    setLaserCharge = runtimeActions.setLaserCharge,
    triggerAutomaticIgnitionSequence = runtimeActions.triggerAutomaticIgnitionSequence,
    fireLaser = runtimeActions.fireLaser,
    pushEvent = pushEvent,
    log = logger,
  })

  if state.pendingRestart then
    restoreTerm()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
    print("Restarting Fusion...")

    local launched = false
    if shell and type(shell.run) == "function" then
      local okRun, runResult = pcall(shell.run, "fusion.lua")
      launched = okRun and runResult ~= false
      if not launched then
        local okRunShort, runResultShort = pcall(shell.run, "fusion")
        launched = okRunShort and runResultShort ~= false
      end
    end

    if not launched and os and type(os.reboot) == "function" then
      os.reboot()
    end
    return
  end

  restoreTerm()
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)

  print("Programme termine.")
end

return M

