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
  local UIRender = require("ui.render")
  local UIViews = require("ui.views")
  local CoreConfig = require("core.config")
  local CoreUpdate = require("core.update")
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
  local CONFIG_FILE = runtime.files.configFile
  local MONITOR_CACHE_FILE = runtime.files.monitorCacheFile
  local VERSION_FILE = runtime.files.versionFile

  local LOCAL_VERSION = runtime.update.localVersion
  local UPDATE_ENABLED = runtime.update.enabled
  local UPDATE_REPO_RAW_BASE = runtime.update.repoRawBase
  local UPDATE_MANIFEST_FILE = runtime.update.manifestFile
  local UPDATE_MANIFEST_URL = runtime.update.manifestUrl
  local UPDATE_TEMP_DIR = runtime.update.tempDir
  local UPDATE_MANIFEST_CACHE_FILE = runtime.update.manifestCacheFile
  local UPDATE_MISSING_BACKUP_SUFFIX = runtime.update.missingBackupSuffix

  local nativeTerm = term.current()
  local buttons = {}
  local touchHitboxes = { terminal = {}, monitor = {} }
  local pressedButtons = {}
  local pressedEffectDuration = 0.18

  local HITBOX_DEFAULTS = runtime.hitboxDefaults

  local state = CoreState.new(CoreState.defaultRuntimeState(LOCAL_VERSION, UPDATE_ENABLED))
  local hw = CoreState.defaultHardwareState()

  local UI_PALETTE = {
    bgMain = colors.black,
    bgElevated = colors.gray,
    frameOuter = colors.lightGray,
    frameInner = colors.lightBlue,
    frameDim = colors.gray,
    textMain = colors.white,
    textDim = colors.lightGray,
    accentOk = colors.green,
    accentWarn = colors.orange,
    accentBad = colors.red,
    accentInfo = colors.cyan,
    accentViolet = colors.purple,
    accentLaser = colors.yellow,
    headerBg = colors.gray,
    footerBg = colors.gray,
    buttonNeutral = colors.gray,
    buttonActive = colors.lightBlue,
    buttonPressed = colors.black,
    buttonDanger = colors.red,
    buttonFuelT = colors.green,
    buttonFuelD = colors.red,
    buttonFuelDT = colors.purple,
    buttonSuccess = colors.lime,
  }

  local styles = {
    panel = {
      default = { bg = UI_PALETTE.bgMain, header = UI_PALETTE.bgElevated, border = UI_PALETTE.frameDim, trim = UI_PALETTE.bgElevated, accent = UI_PALETTE.frameInner, text = UI_PALETTE.textMain },
      accent = { bg = UI_PALETTE.bgMain, header = UI_PALETTE.bgElevated, border = UI_PALETTE.frameDim, trim = UI_PALETTE.bgElevated, accent = UI_PALETTE.frameInner, text = UI_PALETTE.textMain },
    },
    button = {
      primary = { face = UI_PALETTE.buttonActive, rimLight = UI_PALETTE.textMain, rimDark = UI_PALETTE.bgMain, trim = UI_PALETTE.frameInner, text = UI_PALETTE.bgMain },
      secondary = { face = UI_PALETTE.buttonNeutral, rimLight = UI_PALETTE.frameOuter, rimDark = UI_PALETTE.bgMain, trim = UI_PALETTE.frameDim, text = UI_PALETTE.textMain },
      danger = { face = UI_PALETTE.buttonDanger, rimLight = UI_PALETTE.accentWarn, rimDark = UI_PALETTE.bgMain, trim = UI_PALETTE.frameOuter, text = UI_PALETTE.textMain },
      fuelT = { face = UI_PALETTE.buttonFuelT, rimLight = UI_PALETTE.accentOk, rimDark = UI_PALETTE.bgMain, trim = UI_PALETTE.frameOuter, text = UI_PALETTE.textMain },
      fuelD = { face = UI_PALETTE.buttonFuelD, rimLight = UI_PALETTE.accentWarn, rimDark = UI_PALETTE.bgMain, trim = UI_PALETTE.frameOuter, text = UI_PALETTE.textMain },
      fuelDT = { face = UI_PALETTE.buttonFuelDT, rimLight = UI_PALETTE.frameInner, rimDark = UI_PALETTE.bgMain, trim = UI_PALETTE.frameOuter, text = UI_PALETTE.textMain },
      success = { face = UI_PALETTE.buttonSuccess, rimLight = UI_PALETTE.textMain, rimDark = UI_PALETTE.bgMain, trim = UI_PALETTE.accentOk, text = UI_PALETTE.bgMain },
      disabled = { face = UI_PALETTE.frameDim, rimLight = UI_PALETTE.bgElevated, rimDark = UI_PALETTE.bgMain, trim = UI_PALETTE.bgMain, text = UI_PALETTE.textDim },
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
    borderDim = UI_PALETTE.frameDim,
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
    if maxLen <= 3 then return text:sub(1, maxLen) end
    return text:sub(1, maxLen - 3) .. "..."
  end

  local ui = {}

  function ui.write(x, y, txt, tc, bc)
    if bc then term.setBackgroundColor(bc) end
    if tc then term.setTextColor(tc) end
    term.setCursorPos(x, y)
    term.write(txt)
  end

  function ui.blit(x, y, text, fg, bg)
    term.setCursorPos(x, y)
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

  function ui.box(x, y, w, h, bg)
    ui.fill(x, y, w, h, bg or C.panelDark)
  end

  function ui.frame(x, y, w, h, border, inner)
    if w < 2 or h < 2 then return end
    ui.hline(x, y, w, border or C.border)
    ui.hline(x, y + h - 1, w, border or C.borderDim)
    ui.vline(x, y + 1, h - 2, border or C.border)
    ui.vline(x + w - 1, y + 1, h - 2, border or C.borderDim)
    if w > 2 and h > 2 then
      ui.fill(x + 1, y + 1, w - 2, h - 2, inner or C.panelDark)
    end
  end

  function ui.panel(x, y, w, h, title, style)
    local skin = style or styles.panel.default
    local accent = skin.accent or skin.border
    ui.frame(x, y, w, h, skin.border, skin.trim)
    if w > 2 and h > 2 then
      ui.fill(x + 1, y + 1, w - 2, h - 2, skin.bg)
    end
    if h >= 4 and w >= 8 then
      ui.vline(x + 1, y + 1, h - 2, accent)
      ui.vline(x + w - 2, y + 1, h - 2, skin.trim)
    end
    if title and #title > 0 and w > 8 then
      local headerTitle = string.upper(title)
      ui.hline(x + 1, y, math.max(1, w - 2), skin.header)
      ui.write(x + 2, y, uiShortText("[ " .. headerTitle .. " ]", w - 3), skin.text, skin.header)
    end
  end

  function ui.label(x, y, text, tc, bc)
    ui.write(x, y, text, tc or C.text, bc)
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
    pcall(term.setPaletteColor, colors.black, 0.03, 0.04, 0.05)
    pcall(term.setPaletteColor, colors.gray, 0.15, 0.18, 0.20)
    pcall(term.setPaletteColor, colors.lightGray, 0.36, 0.40, 0.42)
    pcall(term.setPaletteColor, colors.white, 0.90, 0.92, 0.92)
    pcall(term.setPaletteColor, colors.blue, 0.10, 0.23, 0.33)
    pcall(term.setPaletteColor, colors.lightBlue, 0.18, 0.56, 0.72)
    pcall(term.setPaletteColor, colors.cyan, 0.26, 0.69, 0.74)
    pcall(term.setPaletteColor, colors.green, 0.19, 0.62, 0.31)
    pcall(term.setPaletteColor, colors.lime, 0.44, 0.78, 0.42)
    pcall(term.setPaletteColor, colors.red, 0.78, 0.20, 0.18)
    pcall(term.setPaletteColor, colors.orange, 0.88, 0.56, 0.18)
    pcall(term.setPaletteColor, colors.yellow, 0.90, 0.74, 0.23)
    pcall(term.setPaletteColor, colors.purple, 0.52, 0.34, 0.68)
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

  local function formatMJ(n)
    if type(n) ~= "number" then return tostring(n) end
    local absn = math.abs(n)
    local units = {
      { 1e12, "TMJ" },
      { 1e9, "GMJ" },
      { 1e6, "MMJ" },
      { 1e3, "kMJ" },
    }

    for _, u in ipairs(units) do
      if absn >= u[1] then
        return string.format("%.2f%s", n / u[1], u[2])
      end
    end

    return string.format("%.0fMJ", n)
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

  local function fmtFuelAmount(n)
    return formatFuelLevel(n)
  end

  local function safePeripheral(name)
    if name and peripheral.isPresent(name) then
      return peripheral.wrap(name)
    end
    return nil
  end

  local function safeCall(obj, method, ...)
    if not obj then return false, nil end
    if type(obj[method]) ~= "function" then return false, nil end
    local ok, result = pcall(obj[method], ...)
    if not ok then return false, nil end
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

  local function fillLine(y, bg)
    local w = term.getSize()
    ui.hline(1, y, w, bg)
  end

  local function shortText(txt, maxLen)
    txt = tostring(txt or "")
    if #txt <= maxLen then return txt end
    if maxLen <= 3 then return txt:sub(1, maxLen) end
    return txt:sub(1, maxLen - 3) .. "..."
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
    if accent and accent ~= C.border then
      skin = {
        bg = styles.panel.default.bg,
        header = styles.panel.default.header,
        border = styles.panel.default.border,
        trim = styles.panel.default.trim,
        accent = accent,
        text = styles.panel.default.text,
      }
    end

    ui.frame(x, y, w, h, skin.border, skin.bg)
    if w > 2 and h > 2 then
      ui.fill(x + 1, y + 1, w - 2, h - 2, skin.bg)
    end
    if h >= 4 then
      ui.hline(x + 1, y + 1, w - 2, skin.trim)
      ui.vline(x + 1, y + 1, h - 2, skin.accent or skin.border)
    end
    if title and #title > 0 and w > 10 then
      local t = shortText(string.upper(title), w - 6)
      ui.write(x + 2, y, " " .. t .. " ", skin.text, skin.header)
    end
  end

  local function drawPanelSprite(x, y, w, h, title, style)
    ui.panel(x, y, w, h, title, style or styles.panel.default)
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
  local collectSafetyWarnings = runtimeAlerts.computeSafetyWarnings

  local function drawHeaderBarSprite(title, status)
    local function drawHeaderSegment(x, y, w, label, value, tone)
      if w < 6 then return end
      ui.hline(x, y, w, C.bg)
      ui.hline(x + 1, y, w - 2, C.headerBg)
      local txt = shortText(string.format("%s:%s", label, tostring(value or "N/A")), math.max(1, w - 4))
      ui.write(x + 2, y, txt, tone or C.text, C.headerBg)
    end

    local function drawMainHeader(headerTitle, headerStatus)
      local tw = term.getSize()
      local phase = reactorPhase()
      local warnings, critical = computeSafetyWarnings()
      local pulse = (state.tick % 8 < 4)
      local mainAlert = headerStatus or state.alert or "INFO"
      local firstWarn = warnings[1] or "NONE"

      ui.hline(1, 1, tw, C.bg)
      if tw < 44 then
        ui.write(2, 1, shortText("SYS " .. headerTitle .. " " .. string.upper(state.currentView), tw - 2), C.headerText, C.bg)
        return
      end

      local w1 = clamp(math.floor(tw * 0.34), 14, tw - 28)
      local w2 = clamp(math.floor(tw * 0.20), 10, tw - w1 - 16)
      local w3 = clamp(math.floor(tw * 0.21), 10, tw - w1 - w2 - 8)
      local w4 = tw - w1 - w2 - w3

      local x1 = 1
      local x2 = x1 + w1
      local x3 = x2 + w2
      local x4 = x3 + w3

      drawHeaderSegment(x1, 1, w1, "SYS", shortText(headerTitle, 14) .. " " .. string.upper(state.currentView), C.headerText)
      drawHeaderSegment(x2, 1, w2, "PHS", shortText(phase, 14), phaseColor(phase))
      drawHeaderSegment(x3, 1, w3, "ALR", shortText(mainAlert, 14), statusColor(mainAlert))

      local critTone = critical and (pulse and C.bad or C.warn) or C.info
      drawHeaderSegment(x4, 1, w4, critical and "CRIT" or "INFO", shortText(firstWarn, 18), critTone)
    end

    drawMainHeader(title, status)
  end

  local function drawFooterBarSprite()
    local function drawFooterSegment(x, y, w, key, value, tone, bg)
      if w < 6 then return end
      local txt = shortText(key .. " " .. tostring(value), math.max(1, w - 3))
      ui.hline(x, y, w, C.bg)
      ui.hline(x + 1, y, w - 2, bg)
      ui.write(x + 2, y, txt, tone or C.text, bg)
    end

    local function drawMainFooter()
      local tw, th = term.getSize()
      local bg = C.footerBg
      ui.hline(1, th, tw, C.bg)
      local phase = reactorPhase()
      local labels = {
        { key = "ACT", value = shortText(state.lastAction, 14), tone = C.text },
        { key = "MON", value = shortText(tostring(hw.monitorName or "term"), 10), tone = C.info },
        { key = "PHS", value = shortText(phase, 12), tone = phaseColor(phase) },
        { key = "LAS", value = yesno(state.laserLineOn), tone = state.laserLineOn and C.warn or C.dim },
        { key = "GRID", value = state.energyKnown and string.format("%3.0f%%", state.energyPct) or "N/A", tone = C.energy },
        { key = "FUEL", value = "D " .. formatFuelLevel(state.deuteriumAmount) .. " T " .. formatFuelLevel(state.tritiumAmount), tone = C.fuel },
      }

      local gap = 1
      local segW = math.max(10, math.floor((tw - ((#labels - 1) * gap)) / #labels))
      local x = 1
      for i, seg in ipairs(labels) do
        local width = (i == #labels) and (tw - x + 1) or segW
        drawFooterSegment(x, th, width, seg.key, seg.value, seg.tone, bg)
        x = x + width + gap
      end
    end

    drawMainFooter()
  end

  local function drawHeader(title, status)
    drawHeaderBarSprite(title, status)
  end

  local function drawFooter(layout)
    local currentViewName = UIViews.resolveViewName(state.currentView)
    drawFooterBarSprite()
  end

  local function pushEvent(message)
    if not message or #message == 0 then return end
    local stamp = string.format("%05.1f", os.clock() % 1000)
    table.insert(state.eventLog, 1, stamp .. " " .. message)
    while #state.eventLog > (state.maxEventLog or 8) do
      table.remove(state.eventLog)
    end
  end

  local function drawKeyValue(x, y, key, value, keyColor, valueColor, maxVal)
    local k = shortText(tostring(key), 12)
    local v = shortText(tostring(value), maxVal or 20)
    writeAt(x, y, k, keyColor or C.dim, C.panelDark)
    writeAt(x + 12, y, " ", C.text, C.panelDark)
    writeAt(x + 13, y, v, valueColor or C.text, C.panelDark)
  end

  local function computeLayout(tw, th)
    local minW, minH = 34, 14
    if tw < minW or th < minH then
      return { tooSmall = true, minW = minW, minH = minH, mode = "tiny" }
    end

    local mode = "compact"
    if tw >= 58 and th >= 19 then mode = "standard" end
    if tw >= 74 and th >= 26 then mode = "large" end

    local top, bottom = 2, th - 1
    local h = bottom - top + 1
    local layout = { mode = mode, top = top, bottom = bottom, height = h, width = tw, tooSmall = false }

    if mode == "compact" then
      local lw = clamp(math.floor(tw * 0.54), 18, tw - 14)
      layout.left = { x = 1, y = top, w = lw, h = h }
      layout.right = { x = lw + 1, y = top, w = tw - lw, h = h }
    elseif mode == "standard" then
      local lw = clamp(math.floor(tw * 0.30), 20, 26)
      local rw = clamp(math.floor(tw * 0.28), 18, 24)
      local cw = tw - lw - rw
      if cw < 24 then
        rw = math.max(17, rw - (24 - cw))
        cw = tw - lw - rw
      end
      layout.left = { x = 1, y = top, w = lw, h = h }
      layout.center = { x = lw + 1, y = top, w = cw, h = h }
      layout.right = { x = lw + cw + 1, y = top, w = rw, h = h }
    else
      local lw = clamp(math.floor(tw * 0.29), 22, 30)
      local rw = clamp(math.floor(tw * 0.27), 21, 28)
      local cw = tw - lw - rw
      if cw < 34 then
        local delta = 34 - cw
        rw = math.max(18, rw - delta)
        cw = tw - lw - rw
      end
      layout.left = { x = 1, y = top, w = lw, h = h }
      layout.center = { x = lw + 1, y = top, w = cw, h = h }
      layout.right = { x = lw + cw + 1, y = top, w = rw, h = h }
    end
    return layout
  end

  local function drawReactorDiagram(x, y, w, h)
    drawBox(x, y, w, h, "FUSION CHAMBER", C.borderDim)
    if w < 30 or h < 16 then
      writeAt(x + 2, y + 2, "Schema top-down indisponible", C.dim, C.panelDark)
      return
    end

    local innerX, innerY = x + 1, y + 1
    local innerW, innerH = w - 2, h - 2
    local phase = reactorPhase()
    local pulse = (state.tick % 6 < 3)
    local blink = (state.tick % 4 < 2)

    local function cellColor(base)
      if state.alert == "DANGER" then return C.bad end
      return base
    end

    local structureColor = C.borderDim
    if state.reactorPresent and state.reactorFormed then
      structureColor = cellColor(C.info)
    elseif state.reactorPresent then
      structureColor = C.dim
    end

    local ringColor = state.reactorPresent and cellColor(C.border) or C.borderDim
    local spineColor = state.reactorPresent and C.info or C.borderDim
    if state.alert == "WARN" then spineColor = C.warn end

    local coreColor
    if not state.reactorPresent then
      coreColor = C.panel
    elseif state.ignition then
      coreColor = pulse and C.ok or colors.green
    elseif state.ignitionSequencePending then
      coreColor = blink and C.warn or colors.yellow
    elseif state.reactorFormed then
      coreColor = blink and colors.cyan or C.info
    else
      coreColor = C.panel
    end
    if state.alert == "DANGER" then coreColor = pulse and C.bad or C.warn end

    local cellW = 2
    local maxGw = math.floor((innerW - 4) / cellW)
    local gw = clamp(maxGw, 17, 23)
    if gw % 2 == 0 then gw = gw - 1 end
    local gh = clamp(innerH - 4, 15, 19)
    if gh % 2 == 0 then gh = gh - 1 end

    local rx = innerX + math.floor((innerW - (gw * cellW)) / 2)
    local ryBase = innerY + math.floor((innerH - gh) / 2)
    local ry = math.min(innerY + innerH - gh, ryBase + 1)

    local gcx = math.floor((gw + 1) / 2)
    local gcy = math.floor((gh + 1) / 2)

    local function drawCell(gx, gy, bg, ch, tc)
      if gx < 1 or gx > gw or gy < 1 or gy > gh then return end
      local sx = rx + (gx - 1) * cellW
      local sy = ry + gy - 1
      local text = ch or "  "
      if #text == 1 then text = text .. " " end
      writeAt(sx, sy, text, tc or C.text, bg)
    end

    for gy = 1, gh do
      for gx = 1, gw do
        local dx = math.abs(gx - gcx)
        local dy = math.abs(gy - gcy)
        local layer = 0

        if math.max(dx, dy) <= 5 then layer = 1 end
        if math.max(dx, dy) <= 4 then layer = 2 end
        if dx <= 1 and dy <= 7 then layer = math.max(layer, 1) end
        if dy <= 1 and dx <= 7 then layer = math.max(layer, 1) end
        if dx <= 0 and dy <= 6 then layer = math.max(layer, 2) end
        if dy <= 0 and dx <= 6 then layer = math.max(layer, 2) end
        if dx == 5 and dy == 5 then layer = 0 end
        if dx <= 1 and dy <= 1 then layer = 3 end

        if layer == 1 then
          drawCell(gx, gy, structureColor)
        elseif layer == 2 then
          drawCell(gx, gy, ringColor)
        elseif layer == 3 then
          local coreGlyph = state.ignition and (pulse and "<>" or "##") or (state.ignitionSequencePending and (blink and "::" or "..") or "[]")
          drawCell(gx, gy, coreColor, coreGlyph, C.text)
        end
      end
    end

    for i = -5, 5 do
      drawCell(gcx + i, gcy, spineColor)
      drawCell(gcx, gcy + i, spineColor)
    end

    drawCell(gcx, gcy, coreColor, state.ignition and (pulse and "**" or "##") or (state.ignitionSequencePending and (blink and "!!" or "::") or "[]"), C.text)
    drawCell(gcx - 1, gcy, ringColor, "[]", C.text)
    drawCell(gcx + 1, gcy, ringColor, "[]", C.text)
    drawCell(gcx, gcy - 1, ringColor, "[]", C.text)
    drawCell(gcx, gcy + 1, ringColor, "[]", C.text)

    local laserOn = state.laserChargeOn or state.laserLineOn or state.ignitionSequencePending
    local laserTone = laserOn and C.warn or C.dim
    local dTone = state.dOpen and C.deuterium or C.dim
    local tTone = state.tOpen and C.tritium or C.dim
    local dtTone = state.dtOpen and C.dtFuel or C.dim

    local conduitTone = C.borderDim
    if state.alert == "WARN" then conduitTone = C.warn end
    if state.alert == "DANGER" then conduitTone = C.bad end

    local laserPathTone = laserOn and C.warn or conduitTone
    local tPathTone = state.tOpen and C.tritium or conduitTone
    local dPathTone = state.dOpen and C.deuterium or conduitTone

    local moduleW = clamp(math.min(gw * cellW - 2, 12), 8, 12)
    if moduleW % 2 ~= 0 then moduleW = moduleW - 1 end
    local moduleX = rx + math.floor((gw * cellW - moduleW) / 2)
    local moduleY = math.max(y + 1, ry - 3)
    local gapTop = moduleY + 1
    local gapBottom = ry - 1

    for gxCol = moduleX, moduleX + moduleW - 1 do
      writeAt(gxCol, moduleY, " ", C.text, laserOn and C.warn or C.panelMid)
    end
    local moduleLabel = laserOn and "LAS ON" or "LAS"
    writeAt(moduleX + math.floor((moduleW - #moduleLabel) / 2), moduleY, moduleLabel, laserOn and C.text or C.dim, laserOn and C.warn or C.panelMid)

    for yLine = gapTop, gapBottom do
      writeAt(rx + (gcx - 1) * cellW, yLine, laserOn and (pulse and "||" or "::") or "..", laserOn and C.text or C.dim, C.panelDark)
    end

    for gyLine = 2, gcy - 2 do
      drawCell(gcx, gyLine, laserPathTone, laserOn and (pulse and "||" or "::") or "  ", C.text)
    end

    local legY = math.min(gh - 1, gcy + 6)
    for gyLine = gcy + 2, legY do
      drawCell(gcx - 4, gyLine, tPathTone)
      drawCell(gcx + 4, gyLine, dPathTone)
    end
    for gxLine = gcx - 3, gcx - 1 do
      drawCell(gxLine, gcy + 2, tPathTone)
    end
    for gxLine = gcx + 1, gcx + 3 do
      drawCell(gxLine, gcy + 2, dPathTone)
    end

    drawCell(gcx - 4, legY, tPathTone, state.tOpen and (blink and "<<" or "TT") or "T ", C.text)
    drawCell(gcx + 4, legY, dPathTone, state.dOpen and (blink and ">>" or "DD") or "D ", C.text)

    local topY = moduleY - 1
    if topY >= y + 1 then
      local laserTxt = string.format("LAS %3.0f%%", state.laserPct)
      writeAt(rx + math.floor((gw * cellW - #laserTxt) / 2), topY, laserTxt, laserTone, C.panelDark)
    elseif moduleX + moduleW + 1 <= x + w - 2 then
      local laserTxt = string.format("%3.0f%%", state.laserPct)
      writeAt(moduleX + moduleW + 1, moduleY, laserTxt, laserTone, C.panelDark)
    end

    local bottomY = ry + gh
    if bottomY <= y + h - 2 then
      local tTxt = "T " .. (state.tOpen and (blink and "FLOW" or "OPEN") or "LOCK")
      local dTxt = "D " .. (state.dOpen and (blink and "FLOW" or "OPEN") or "LOCK")
      local tX = rx + 1
      local dX = rx + gw * cellW - #dTxt - 1
      if tX >= x + 2 then
        writeAt(tX, bottomY, tTxt, tTone, C.panelDark)
      end
      if dX + #dTxt <= x + w - 2 then
        writeAt(dX, bottomY, dTxt, dTone, C.panelDark)
      end

      local fuelTxt = "DT " .. (state.dtOpen and (blink and "MIX" or "OPEN") or "LOCK")
      writeAt(rx + math.floor((gw * cellW - #fuelTxt) / 2), bottomY - 1, fuelTxt, dtTone, C.panelDark)

      local labelY = bottomY + 1
      if labelY <= y + h - 3 then
        local leftBranchX = rx + (gcx - 4 - 1) * cellW
        local rightBranchX = rx + (gcx + 4 - 1) * cellW
        local centerBranchX = rx + (gcx - 1) * cellW
        writeAt(leftBranchX, labelY, "||", tPathTone, C.panelDark)
        writeAt(centerBranchX, labelY, "||", dtTone, C.panelDark)
        writeAt(rightBranchX, labelY, "||", dPathTone, C.panelDark)

        local lockY = labelY + 1
        if lockY <= y + h - 2 then
          local tLock = " T LOCK "
          local dtLock = " DT LOCK "
          local dLock = " D LOCK "
          local tLockX = leftBranchX - math.floor((#tLock - 2) / 2)
          local dtLockX = centerBranchX - math.floor((#dtLock - 2) / 2)
          local dLockX = rightBranchX - math.floor((#dLock - 2) / 2)
          writeAt(tLockX, lockY, tLock, C.text, state.tOpen and C.tritium or C.panelMid)
          writeAt(dtLockX, lockY, dtLock, C.text, state.dtOpen and C.dtFuel or C.panelMid)
          writeAt(dLockX, lockY, dLock, C.text, state.dOpen and C.deuterium or C.panelMid)
        end
      end
    end

    local tdModuleY = math.min(y + h - 3, ry + gh + 1)
    if tdModuleY <= y + h - 2 then
      local tMx = rx
      local dMx = rx + gw * cellW - 6
      writeAt(tMx, tdModuleY, " TANK T", state.tOpen and C.text or C.dim, state.tOpen and C.tritium or C.panelMid)
      writeAt(dMx, tdModuleY, " TANK D", state.dOpen and C.text or C.dim, state.dOpen and C.deuterium or C.panelMid)
    end


    writeAt(x + 3, y + 2, shortText("CORE " .. (state.reactorPresent and (state.reactorFormed and "FORMED" or "UNFORMED") or "ABSENT"), math.max(8, math.floor(w * 0.31))), state.reactorPresent and C.info or C.bad, C.panelDark)
  end

  local function drawBadge(x, y, label, value, tone)
    local labelText = shortText(tostring(label), 9)
    local valueText = " " .. shortText(tostring(value), 10) .. " "
    local stateTone = tone or statusColor(value)
    writeAt(x, y, labelText, C.dim, C.panelDark)
    writeAt(x + 10, y, valueText, C.text, stateTone)
  end

  local function drawBar(x, y, w, pct, color, label)
    pct = clamp(toNumber(pct, 0), 0, 100)
    if w < 4 then return end
    local fill = math.floor((w * pct) / 100)
    writeAt(x, y, string.rep(" ", w), C.text, C.panel)
    if fill > 0 then
      writeAt(x, y, string.rep(" ", fill), C.text, color or C.ok)
    end
    if label and #label > 0 and w > 6 then
      local txt = shortText(label, w - 2)
      local lx = x + math.floor((w - #txt) / 2)
      writeAt(lx, y, txt, C.text, C.panelDark)
    end
  end

  local function drawBars(panel, x, y)
    local bw = math.max(10, panel.w - 6)
    drawBar(x, y, bw, state.laserPct, C.warn, string.format("LASER %3.0f%%", state.laserPct))
    drawBar(x, y + 2, bw, state.energyKnown and state.energyPct or 0, C.energy, state.energyKnown and string.format("GRID %3.0f%%", state.energyPct) or "GRID N/A")
  end

  local function drawKV(x, y, key, value, keyColor, valueColor)
    writeAt(x, y, shortText(key, 11), keyColor or C.dim, C.panelDark)
    writeAt(x + 11, y, shortText(value, 10), valueColor or C.text, C.panelDark)
  end

  local function loadSavedMonitorName()
    if not fs.exists(MONITOR_CACHE_FILE) then return nil end
    local h = fs.open(MONITOR_CACHE_FILE, "r")
    if not h then return nil end
    local name = h.readLine()
    h.close()
    return name
  end

  local function saveSelectedMonitorName(name)
    local h = fs.open(MONITOR_CACHE_FILE, "w")
    if not h then return end
    h.writeLine(name or "")
    h.close()
  end

  local function trimText(txt)
    return CoreConfig.trimText(txt)
  end

  local function readLocalVersionFile()
    return CoreConfig.readLocalVersionFile(fs, VERSION_FILE, LOCAL_VERSION)
  end

  local function loadFusionConfig()
    return CoreConfig.loadFusionConfig(fs, CONFIG_FILE, CFG, UPDATE_ENABLED)
  end

  local function applyConfigToRuntime(config)
    if type(config) ~= "table" then return end
    CoreConfig.applyConfigToRuntime(config, CFG)

    if type(config.ui) == "table" and type(config.ui.preferredView) == "string" then
      local view = string.upper(config.ui.preferredView)
      if view == "SUP" then state.currentView = "supervision"
      elseif view == "DIAG" then state.currentView = "diagnostic"
      elseif view == "MAN" then state.currentView = "manual"
      elseif view == "IND" then state.currentView = "induction"
      elseif view == "UPDATE" then state.currentView = "update"
      elseif view == "SETUP" then state.currentView = "setup"
      end
    end

    if type(config.update) == "table" and config.update.enabled ~= nil then
      UPDATE_ENABLED = config.update.enabled and true or false
    end
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
    if merged.ui.preferredView == "CFG" then merged.ui.preferredView = "SETUP" end
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
        shell.run("install.lua")
      end
      return false, nil
    end

    local configValid, configErrors = CoreConfig.validateConfig(config)
    if not configValid then
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
        shell.run("install.lua")
      end
      return false, nil
    end

    applyConfigToRuntime(config)
    refreshSetupWorkingConfig(config)
    return true, config
  end

  local function loadRuntimeSetupConfig()
    local ok, config = loadFusionConfig()
    if ok and type(config) == "table" then
      refreshSetupWorkingConfig(config)
    end
  end

  local function setupDeviceExists(name, expectedType)
    if type(name) ~= "string" or trimText(name) == "" then return false, "INVALID" end
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
    return CoreUpdate.validateLuaScript(text, trimText, contains)
  end

  local function writeTextFile(path, content)
    return CoreUpdate.writeTextFile(fs, path, content)
  end

  local function readTextFile(path)
    return CoreUpdate.readTextFile(fs, path)
  end

  local function normalizePath(path)
    return tostring(path or ""):gsub("\\", "/")
  end

  local function buildRawFileUrl(path)
    return UPDATE_REPO_RAW_BASE .. "/" .. normalizePath(path)
  end

  local function getTempPathFor(filePath)
    return UPDATE_TEMP_DIR .. "/" .. normalizePath(filePath) .. ".new"
  end

  local function getBackupPathFor(filePath)
    return normalizePath(filePath) .. ".bak"
  end

  local function getMissingBackupMarker(filePath)
    return getBackupPathFor(filePath) .. UPDATE_MISSING_BACKUP_SUFFIX
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
    preserveSet[CONFIG_FILE] = true
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
      if path ~= "" and not seen[path] then
        seen[path] = true
        table.insert(files, path)
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
        if path ~= "" then table.insert(preserve, path) end
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
      if #trimText(content) < 8 then
        return false, "Lua file too short: " .. normalized
      end
    end

    return true, nil
  end

  local function fetchRemoteManifest()
    local ok, body, err = httpGetText(UPDATE_MANIFEST_URL)
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

    return writeTextFile(UPDATE_MANIFEST_CACHE_FILE, encoded)
  end

  local function readManifestCache()
    if not fs.exists(UPDATE_MANIFEST_CACHE_FILE) then
      return false, nil, "Manifest cache missing"
    end

    local ok, body, err = readTextFile(UPDATE_MANIFEST_CACHE_FILE)
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

    if not UPDATE_ENABLED then
      state.update.httpStatus = "DISABLED"
      state.update.remoteVersion = "DISABLED"
      state.update.available = false
      setUpdateState("DISABLED", "Update disabled", nil)
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
      return false, state.update.lastError
    end

    state.update.manifestLoaded = true
    state.update.lastManifest = manifest
    state.update.remoteVersion = manifest.version
    state.update.filesToUpdate = #manifest.files
    state.update.lastCheckClock = os.clock()
    pushEvent("Manifest loaded " .. manifest.version)

    local localVersion = trimText(state.update.localVersion)
    local validLocalVersion, localVersionErr = validateVersionString(localVersion)
    if not validLocalVersion then
      state.update.available = false
      state.update.lastError = localVersionErr or "Local version invalid"
      setUpdateState("FAILED", "Check failed: " .. state.update.lastError, nil)
      pushEvent("Update failed")
      return false, state.update.lastError
    end
    state.update.localVersion = localVersion

    local cmp = compareVersions(state.update.localVersion, manifest.version)
    if cmp == 1 then
      state.update.available = true
      setUpdateState("UPDATE AVAILABLE", "Remote " .. manifest.version .. " > local " .. state.update.localVersion, nil)
      pushEvent("Update available")
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
      if not isPreservedFile(filePath, preserveSet) then
        local okBody, body, errBody = httpGetText(buildRawFileUrl(filePath))
        if not okBody then
          state.update.lastError = errBody or ("Download failed: " .. filePath)
          setUpdateState("FAILED", nil, "Download failed: " .. filePath)
          pushEvent("Update failed")
          return false, state.update.lastError
        end

        local valid, reason = validateDownloadedContent(filePath, body, manifest.version)
        if not valid then
          state.update.lastError = reason or ("Validation failed: " .. filePath)
          setUpdateState("FAILED", nil, "Validation failed")
          pushEvent("Update failed")
          return false, state.update.lastError
        end

        local tempPath = getTempPathFor(filePath)
        ensureParentDir(tempPath)
        local okWrite, errWrite = writeTextFile(tempPath, body)
        if not okWrite then
          state.update.lastError = errWrite or ("Temp write failed: " .. filePath)
          setUpdateState("FAILED", nil, "Temp write failed")
          pushEvent("Update failed")
          return false, state.update.lastError
        end

        downloadedCount = downloadedCount + 1
      end
    end

    local cacheOk, cacheErr = saveManifestCache(manifest)
    if not cacheOk then
      state.update.lastError = cacheErr or "Cannot save manifest cache"
      setUpdateState("FAILED", nil, "Manifest cache failed")
      return false, state.update.lastError
    end

    state.update.downloaded = true
    state.update.remoteVersion = manifest.version
    state.update.filesToUpdate = #manifest.files
    setUpdateState("DOWNLOADED", nil, "Downloaded " .. tostring(downloadedCount) .. " files")
    pushEvent("Download complete")
    return true, nil
  end

  local function applyUpdate()
    state.update.lastError = ""
    local manifest = state.update.lastManifest
    if type(manifest) ~= "table" then
      local okManifest, cachedManifest, cacheErr = readManifestCache()
      if not okManifest then
        setUpdateState("FAILED", nil, "Manifest cache missing")
        return false, cacheErr or "Manifest cache missing"
      end
      manifest = cachedManifest
      state.update.lastManifest = manifest
    end

    setUpdateState("APPLYING", nil, "Applying update")
    local preserveSet = buildPreserveSet(manifest)

    for _, filePath in ipairs(manifest.files) do
      local normalized = normalizePath(filePath)
      if not isPreservedFile(normalized, preserveSet) then
        local tempPath = getTempPathFor(normalized)
        if not fs.exists(tempPath) then
          state.update.lastError = "Missing temp file: " .. normalized
          setUpdateState("FAILED", nil, "Apply failed")
          return false, state.update.lastError
        end

        local okTemp, tempBody, tempErr = readTextFile(tempPath)
        if not okTemp then
          state.update.lastError = tempErr or ("Cannot read temp file: " .. normalized)
          setUpdateState("FAILED", nil, "Apply failed")
          return false, state.update.lastError
        end

        local valid, reason = validateDownloadedContent(normalized, tempBody, manifest.version)
        if not valid then
          state.update.lastError = reason or ("Invalid temp file: " .. normalized)
          setUpdateState("FAILED", nil, "Apply failed")
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
            return false, state.update.lastError
          end
          local okBackup, backupErr = writeTextFile(backupPath, currentBody)
          if not okBackup then
            state.update.lastError = backupErr or ("Cannot write backup: " .. normalized)
            setUpdateState("FAILED", nil, "Backup failed")
            return false, state.update.lastError
          end
          if fs.exists(missingMarker) then pcall(fs.delete, missingMarker) end
        else
          local markerOk, markerErr = writeTextFile(missingMarker, "missing\n")
          if not markerOk then
            state.update.lastError = markerErr or ("Cannot mark missing backup: " .. normalized)
            setUpdateState("FAILED", nil, "Backup failed")
            return false, state.update.lastError
          end
        end

        ensureParentDir(normalized)
        local okWrite, writeErr = writeTextFile(normalized, tempBody)
        if not okWrite then
          state.update.lastError = writeErr or ("Cannot replace file: " .. normalized)
          setUpdateState("FAILED", nil, "Apply failed")
          return false, state.update.lastError
        end
      end
    end

    if fs.exists(UPDATE_TEMP_DIR) then pcall(fs.delete, UPDATE_TEMP_DIR) end
    state.update.downloaded = false
    state.update.restartRequired = true
    state.update.localVersion = manifest.version
    state.update.remoteVersion = manifest.version
    setUpdateState("RESTART REQUIRED", nil, "Update applied. Restart required")
    pushEvent("Update applied")
    pushEvent("Restart required")
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
    local files = rollbackTargetList()
    local restored = 0

    for _, filePath in ipairs(files) do
      local normalized = normalizePath(filePath)
      if normalized ~= CONFIG_FILE then
        local backupPath = getBackupPathFor(normalized)
        local missingMarker = getMissingBackupMarker(normalized)

        if fs.exists(backupPath) then
          local okRead, backupBody, readErr = readTextFile(backupPath)
          if not okRead then
            setUpdateState("FAILED", nil, "Rollback failed")
            return false, readErr
          end

          ensureParentDir(normalized)
          local okWrite, writeErr = writeTextFile(normalized, backupBody)
          if not okWrite then
            setUpdateState("FAILED", nil, "Rollback failed")
            return false, writeErr
          end
          restored = restored + 1
        elseif fs.exists(missingMarker) then
          if fs.exists(normalized) then pcall(fs.delete, normalized) end
          restored = restored + 1
        end
      end
    end

    if fs.exists(VERSION_FILE) then
      local okVersion, versionText = readTextFile(VERSION_FILE)
      if okVersion then state.update.localVersion = trimText(versionText) end
    end

    state.update.restartRequired = true
    state.update.downloaded = false
    if restored == 0 then
      setUpdateState("FAILED", nil, "No rollback backup available")
      return false, "No rollback backup available"
    end

    setUpdateState("RESTART REQUIRED", nil, "Rollback applied. Restart required")
    pushEvent("Rollback applied")
    pushEvent("Restart required")
    return true, nil
  end

  local function getMonitorCandidates()

    return IoDevices.getMonitorCandidates(peripheral, getTypeOf, safePeripheral)
  end

  local function chooseMonitorAuto()
    local monitors = getMonitorCandidates()
    if #monitors == 0 then return nil end

    local saved = loadSavedMonitorName()
    if saved then
      for _, m in ipairs(monitors) do
        if m.name == saved then return m end
      end
    end

    for _, m in ipairs(monitors) do
      if m.name == CFG.preferredMonitor then
        saveSelectedMonitorName(m.name)
        return m
      end
    end

    saveSelectedMonitorName(monitors[1].name)
    return monitors[1]
  end

  local function setupMonitor()
    local chosen = chooseMonitorAuto()
    hw.monitor = chosen and chosen.obj or nil
    hw.monitorName = chosen and chosen.name or nil
    IoMonitor.setupMonitor(nativeTerm, hw, CFG, C)
  end

  local function restoreTerm()
    term.redirect(nativeTerm)
    term.setCursorBlink(false)
  end

  local function scanPeripherals()
    IoDevices.scanPeripherals(peripheral, hw, CFG, safePeripheral, getTypeOf, contains)
  end

  local function resolveKnownRelays()
    IoRelays.resolveKnownRelays(CFG)
  end

  local function resolveKnownReaders()
    IoReaders.resolveKnownReaders(hw, CFG.knownReaders)
  end

  local function resolveKnownTopology()
    resolveKnownRelays()
    resolveKnownReaders()
  end

  local function classifyBlockReaderData(data)
    return IoReaders.classifyBlockReaderData(data)
  end

  local function scanBlockReaders()
    resolveKnownRelays()
    IoReaders.scanBlockReaders(hw, CFG.knownReaders)
  end

  local function extractChemicalData(raw)
    return IoReaders.extractChemicalData(raw, toNumber)
  end

  local function readChemicalFromReader(entry)
    return IoReaders.readChemicalFromReader(entry, toNumber)
  end

  local function readActiveFromReader(entry)
    return IoReaders.readActiveFromReader(entry, toNumber)
  end

  local function relayWrite(actionName, on)
    return IoRelays.relayWrite(CFG.actions, hw.relays, actionName, on)
  end

  local function readRelayOutputState(actionName, fallback)
    return IoRelays.readRelayOutputState(CFG.actions, hw.relays, actionName, fallback, toNumber)
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
    refreshSetupDeviceStatus = refreshSetupDeviceStatus,
    pushEvent = pushEvent,
  })

  local refreshAll = runtimeRefresh.refreshAll

  local runtimeActions = CoreActions.build({
    state = state,
    CFG = CFG,
    relayWrite = relayWrite,
    pushEvent = pushEvent,
    runtimeAlerts = runtimeAlerts,
  })

  local setLaserCharge = runtimeActions.setLaserCharge
  local fireLaser = runtimeActions.fireLaser
  local openDTFuel = runtimeActions.openDTFuel
  local openDeuterium = runtimeActions.openDeuterium
  local openTritium = runtimeActions.openTritium
  local openSeparatedGases = runtimeActions.openSeparatedGases
  local hardStop = runtimeActions.hardStop
  local canIgnite = runtimeAlerts.canIgnite
  local startReactorSequence = runtimeActions.startReactorSequence
  local stopReactorSequence = runtimeActions.stopReactorSequence
  local triggerAutomaticIgnitionSequence = runtimeActions.triggerAutomaticIgnitionSequence
  local fullAuto = runtimeActions.fullAuto

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
    local bucket = getHitboxBucket(source)
    bucket[#bucket + 1] = {
      id = id,
      x1 = bx1,
      y1 = by1,
      x2 = bx2,
      y2 = by2,
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
    local width = math.max(6, w)
    local height = math.max(3, h or (opts.big and 5 or 4))

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
      label = label,
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
    if id == "setupSave" then return styles.button.success end
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
    local textOffset = isPressed and 1 or 0
    local lx = button.x + math.max(1, math.floor((button.w - #button.label) / 2)) + textOffset
    local ly = button.y + math.floor((button.h - 1) / 2) + textOffset
    lx = clamp(lx, button.x + 1, button.x + button.w - #button.label)
    ly = clamp(ly, button.y + 1, button.y + button.h - 1)
    writeAt(lx, ly, button.label, textColor or button.fg, faceColor)
  end

  function drawButtonSprite(button, style)
    local skin = style or resolveButtonStyle(button)
    ui.fill(button.x, button.y, button.w, button.h, skin.face)
    if button.w >= 3 and button.h >= 3 then
      ui.hline(button.x, button.y, button.w, skin.rimLight)
      ui.hline(button.x, button.y + button.h - 1, button.w, skin.rimDark)
      ui.vline(button.x, button.y + 1, button.h - 2, skin.rimLight)
      ui.vline(button.x + button.w - 1, button.y + 1, button.h - 2, skin.rimDark)
      if button.h >= 4 then
        ui.hline(button.x + 1, button.y + 1, math.max(1, button.w - 2), skin.trim)
      end
    end
    return skin.face, skin.text
  end

  function drawButtonPressedSprite(button, style)
    local skin = style or resolveButtonStyle(button)
    local pressed = { face = UI_PALETTE.buttonPressed, rimLight = skin.rimLight, rimDark = skin.rimDark, trim = skin.face, text = skin.text }
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
    local top = isActive and C.text or C.borderDim
    local bottom = isActive and C.border or C.bg
    if isPressed then
      face = C.panel
      top = C.borderDim
      bottom = C.bg
    end

    ui.fill(x, y, w, h, face)
    ui.hline(x, y, w, top)
    ui.hline(x, y + h - 1, w, bottom)
    if w >= 3 then
      ui.vline(x, y, h, top)
      ui.vline(x + w - 1, y, h, bottom)
    end

    local txt = shortText(label, math.max(1, w - 2))
    local tx = x + math.max(1, math.floor((w - #txt) / 2))
    local ty = y + math.floor((h - 1) / 2) + (isPressed and 1 or 0)
    ui.write(tx, ty, txt, isActive and C.bg or C.text, face)
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

  function drawStatusBarSprite(x, y, w, title, value, tone)
    ui.hline(x, y, w, UI_PALETTE.bgElevated)
    ui.write(x + 1, y, shortText(title .. ":", math.max(1, w - 2)), C.dim, UI_PALETTE.bgElevated)
    local txt = shortText(value, math.max(1, w - #title - 4))
    ui.write(x + math.max(2, w - #txt - 1), y, txt, tone or C.info, UI_PALETTE.bgElevated)
  end

  function drawRaisedButton(button)
    return drawButtonActiveSprite(button)
  end

  function drawPressedButton(button)
    return drawButtonPressedSprite(button)
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
    addButton(id, x, y, w, 5, label, bg, C.btnText, action, { big = true })
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
    setupMonitor()
    stopMonitorSelection()
    state.lastAction = "Moniteur: " .. m.name
    pushEvent("Monitor changed")
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
      canIgnite = canIgnite,
      startReactorSequence = startReactorSequence,
      stopManualReactor = function() stopReactorSequence("ARRET DEMANDE") end,
      stopRequested = function() stopReactorSequence("ARRET DEMANDE") end,
      toggleTritium = function() openTritium(not state.tOpen) end,
      toggleDeuterium = function() openDeuterium(not state.dOpen) end,
      toggleDTFuel = function()
        local nextState = not state.dtOpen
        openDTFuel(nextState)
        if nextState then openSeparatedGases(false) end
      end,
      fireLaser = fireLaser,
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
      saveSetupConfig = saveSetupConfig,
      runInstallerFromSetup = runInstallerFromSetup,
      toggleMaster = function()
        state.autoMaster = not state.autoMaster
        if not state.autoMaster then
          openDTFuel(false)
          openSeparatedGases(false)
          setLaserCharge(false)
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
    return term.current() == nativeTerm and "terminal" or "monitor"
  end

  function drawButtons(source)
    clearHitboxes(source)
    for _, b in ipairs(buttons) do
      drawButton(source, b)
    end
    drawHitboxDebugOverlay(source)
  end

  function handleClick(x, y, source)
    local bucket = getHitboxBucket(source)
    for i = #bucket, 1, -1 do
      local hit = bucket[i]
      if isInsideBox(x, y, hit) then
        setButtonPressed(source, hit.id)
        hit.action()
        return true
      end
    end
    return false
  end



  function inductionStatus()
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

  function getInductionFillRatio()
    return CoreInduction.getFillRatio(state)
  end

  local function buildUIViewContext()
    return UIViews.buildContext({
      C = C,
      state = state,
      hw = hw,
      CFG = CFG,
      fs = fs,
      UPDATE_ENABLED = UPDATE_ENABLED,
      UPDATE_TEMP_DIR = UPDATE_TEMP_DIR,
      UPDATE_MISSING_BACKUP_SUFFIX = UPDATE_MISSING_BACKUP_SUFFIX,
      drawBox = drawBox,
      writeAt = writeAt,
      drawKeyValue = drawKeyValue,
      drawBadge = drawBadge,
      shortText = shortText,
      clamp = clamp,
      fmt = fmt,
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
  end

  function drawMonitorSelection(layout)
    UIViews.drawMonitorSelection(buildUIViewContext(), layout)
  end

  function drawControlPanel(panel, layout)
    drawBox(panel.x, panel.y, panel.w, panel.h,
      state.currentView == "manual" and "MANUAL CONTROL"
        or (state.currentView == "update" and "UPDATE COMMAND"
        or (state.currentView == "setup" and "SETUP COMMAND" or "CONTROL SYSTEM")), C.border)
    local x = panel.x + 2
    local w = panel.w - 3

    local autoH = clamp(math.floor(panel.h * 0.24), 6, 8)
    local actionH = clamp(math.floor(panel.h * 0.34), 8, 12)
    local ioH = panel.h - autoH - actionH - 2

    drawBox(x, panel.y + 1, w, autoH, "CONTROL SYSTEM", C.borderDim)
    local sx = x + 2
    drawBadge(sx, panel.y + 2, "MASTER", state.autoMaster and "AUTO" or "MANUAL")
    drawBadge(sx, panel.y + 3, "FUSION", state.fusionAuto and "AUTO" or "MANUAL")
    drawBadge(sx, panel.y + 4, "CHARGE", state.chargeAuto and "AUTO" or "MANUAL")
    drawBadge(sx, panel.y + 5, "GAS", state.gasAuto and "AUTO" or "MANUAL")

    local yAction = panel.y + 1 + autoH
    drawBox(x, yAction, w, actionH, "COMMAND ACTIONS", C.borderDim)

    buildButtons(layout)
    drawButtons(getCurrentInputSource())

    local yIo = yAction + actionH
    UIComponents.drawIoPanel(buildUIViewContext(), x, yIo, w, ioH)
  end



  function inductionFillTone(status, pulse)
    if status == "CHARGING" then return pulse and C.info or C.energy end
    if status == "DISCHARGING" then return pulse and C.warn or C.energy end
    if status == "LOW" or status == "EMPTY" then return pulse and C.bad or C.warn end
    if status == "FULL" then return pulse and C.ok or C.info end
    return C.energy
  end

  function inductionDiagramGeometry(x, y, w, h)
    local geo = {
      ix = x + 2,
      iy = y + 2,
      iw = w - 4,
      ih = h - 4,
      gapRight = 4,
    }

    local infoMinW = 22
    local profileMaxW = math.max(12, geo.iw - infoMinW - geo.gapRight - 2)
    geo.profileW = clamp(math.floor(geo.iw * 0.52), 12, profileMaxW)
    geo.profileH = clamp(math.floor(geo.ih * 0.78), 8, geo.ih - 3)

    local dimsKnown = state.inductionLength > 0 and state.inductionWidth > 0 and state.inductionHeight > 0
    if dimsKnown then
      local footprint = clamp((state.inductionLength + state.inductionWidth) / 2, 3, 18)
      local maxFootprint = math.max(footprint, state.inductionHeight, 3)
      local footprintRatio = clamp(footprint / maxFootprint, 0.35, 1.0)
      local verticalRatio = clamp(state.inductionHeight / maxFootprint, 0.35, 1.0)
      geo.profileW = clamp(math.floor(profileMaxW * (0.30 + footprintRatio * 0.55)), 12, profileMaxW)
      geo.profileH = clamp(math.floor((geo.ih - 3) * (0.40 + verticalRatio * 0.46)), 8, geo.ih - 3)
    end

    geo.sx = geo.ix + 2
    geo.sy = geo.iy + math.floor((geo.ih - geo.profileH) / 2)
    geo.ex = geo.sx + geo.profileW - 1
    geo.ey = geo.sy + geo.profileH - 1
    geo.capDepth = clamp(math.floor(geo.profileW * 0.20), 2, 6)
    geo.fillRows = clamp(math.floor(getInductionFillRatio() * (geo.profileH - 2) + 0.5), 0, geo.profileH - 2)
    geo.infoX = geo.ix + geo.profileW + geo.capDepth + geo.gapRight
    return geo
  end

  function drawInductionProfileBase(geo)
    fillArea(geo.ix, geo.iy, geo.iw, geo.ih, C.panelDark)
    drawBox(geo.sx - 1, geo.sy - 1, geo.profileW + geo.capDepth + 2, geo.profileH + 2, "SIDE PROFILE", C.borderDim)

    for yy = geo.sy, geo.ey do
      local depthDiv = math.max(1, geo.profileH / math.max(1, geo.capDepth))
      local rowDepth = clamp(geo.capDepth - math.floor((yy - geo.sy) / depthDiv), 0, geo.capDepth)
      writeAt(geo.sx, yy, string.rep(" ", geo.profileW), C.text, C.panel)
      if rowDepth > 0 then
        writeAt(geo.ex + 1, yy, string.rep(" ", rowDepth), C.text, C.panelMid)
      end
    end
  end

  function drawInductionProfileFill(geo, status, pulse, fillTone)
    local waveOffset = (status == "CHARGING" and pulse) and 1 or 0
    for i = 0, geo.fillRows - 1 do
      local yy = geo.ey - 1 - i
      local waveCut = ((state.tick + yy) % 5 == 0) and waveOffset or 0
      local fillWidth = clamp(geo.profileW - 2 - waveCut, 1, geo.profileW - 2)
      writeAt(geo.sx + 1, yy, string.rep(" ", fillWidth), C.text, fillTone)
      if fillWidth < (geo.profileW - 2) then
        writeAt(geo.sx + 1 + fillWidth, yy, string.rep(" ", (geo.profileW - 2) - fillWidth), C.text, C.panel)
      end
    end

    local levelY = geo.ey - geo.fillRows
    if geo.fillRows > 0 and levelY >= geo.sy + 1 and levelY <= geo.ey - 1 then
      writeAt(geo.sx + 1, levelY, string.rep(" ", geo.profileW - 2), C.text, pulse and C.info or fillTone)
    end
  end

  function drawInductionProfileDecor(geo, status)
    local cellDensity = clamp(math.floor((math.max(1, state.inductionCells) + 3) / 4), 1, 8)
    for i = 0, cellDensity - 1 do
      local yy = geo.sy + math.floor((i + 1) * geo.profileH / (cellDensity + 1))
      writeAt(geo.sx + 1, yy, string.rep(" ", math.max(1, geo.profileW - 2)), C.text, C.borderDim)
    end

    local providerColor = status == "DISCHARGING" and C.warn or C.info
    local providerDensity = clamp(math.max(1, state.inductionProviders), 1, 6)
    for i = 0, providerDensity - 1 do
      local py = geo.sy + math.floor((i + 1) * geo.profileH / (providerDensity + 1))
      writeAt(geo.sx - 3, py, "  ", C.text, providerColor)
      writeAt(geo.ex + geo.capDepth + 2, py, "  ", C.text, providerColor)
    end
  end

  function drawInductionDiagramInfo(x, y, w, h, geo, status, tone)
    writeAt(x + 2, y + 1, string.format("STATE %s", status), tone, C.panelDark)
    writeAt(geo.infoX, geo.sy + 1, string.format("FILL  %5.1f%%", state.inductionPct), C.energy, C.panelDark)
    writeAt(geo.infoX, geo.sy + 2, string.format("STORED %s", formatMJ(state.inductionEnergy)), C.text, C.panelDark)
    writeAt(geo.infoX, geo.sy + 3, string.format("MAX    %s", formatMJ(state.inductionMax)), C.dim, C.panelDark)
    writeAt(geo.infoX, geo.sy + 4, string.format("NEEDED %s", formatMJ(state.inductionNeeded)), C.dim, C.panelDark)
    writeAt(geo.infoX, geo.sy + 6, string.format("IN   %s", formatMJ(state.inductionInput)), C.ok, C.panelDark)
    writeAt(geo.infoX, geo.sy + 7, string.format("OUT  %s", formatMJ(state.inductionOutput)), C.warn, C.panelDark)
    writeAt(geo.infoX, geo.sy + 8, string.format("CAP  %s", formatMJ(state.inductionTransferCap)), C.info, C.panelDark)
    writeAt(geo.infoX, geo.sy + 9, string.format("PORT  %s", state.inductionPortMode), C.info, C.panelDark)
    writeAt(geo.infoX, geo.sy + 10, string.format("CELLS %d", state.inductionCells), C.info, C.panelDark)
    writeAt(geo.infoX, geo.sy + 11, string.format("PROV  %d", state.inductionProviders), C.info, C.panelDark)
    writeAt(geo.infoX, geo.sy + 12, string.format("DIM   %dx%dx%d", state.inductionLength, state.inductionWidth, state.inductionHeight), C.text, C.panelDark)
    writeAt(x + 2, y + h - 2, shortText(string.format("CELLS %d | PROVIDERS %d | %dx%dx%d", state.inductionCells, state.inductionProviders, state.inductionLength, state.inductionWidth, state.inductionHeight), w - 4), C.dim, C.panelDark)
  end

  function drawInductionDiagram(x, y, w, h)
    drawBox(x, y, w, h, "INDUCTION MATRIX", C.border)
    if w < 34 or h < 16 then
      writeAt(x + 2, y + 2, "Schema matrix indisponible", C.dim, C.panelDark)
      return
    end

    local status, tone = inductionStatus()
    local geo = inductionDiagramGeometry(x, y, w, h)
    local pulse = (state.tick % 6 < 3)
    local fillTone = inductionFillTone(status, pulse)

    drawInductionProfileBase(geo)
    drawInductionProfileFill(geo, status, pulse, fillTone)
    drawInductionProfileDecor(geo, status)
    drawInductionDiagramInfo(x, y, w, h, geo, status, tone)
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

  function drawSetupView(layout)
    UIViews.drawSetupView(buildUIViewContext(), layout)
  end

  local function drawUI()
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
    elseif state.currentView == "setup" then
      drawSetupView(layout)
    else
      drawSupervisionView(layout)
    end

    drawFooter(layout)
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
    fullAuto = fullAuto,
    drawUI = drawUI,
    handleClick = handleClick,
    setupMonitor = setupMonitor,
    getMonitorCandidates = getMonitorCandidates,
    selectMonitorByIndex = selectMonitorByIndex,
    stopMonitorSelection = stopMonitorSelection,
    startMonitorSelection = startMonitorSelection,
    openDTFuel = openDTFuel,
    openSeparatedGases = openSeparatedGases,
    setLaserCharge = setLaserCharge,
    triggerAutomaticIgnitionSequence = triggerAutomaticIgnitionSequence,
    fireLaser = fireLaser,
    pushEvent = pushEvent,
  })

  restoreTerm()
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)

  print("Programme termine.")
end

return M
