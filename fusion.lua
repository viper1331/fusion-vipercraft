-- fusion_cc.lua
-- Version renforcée 39x19
-- CC:Tweaked + Mekanism + Advanced Peripherals + Redstone Relays

local CFG = {
  preferredMonitor = "monitor_2",
  preferredReactor = "mekanismgenerators:fusion_reactor_controller_3",
  preferredLogicAdapter = "fusionReactorLogicAdapter_0",
  preferredLaser = "laserAmplifier_1",
  preferredInduction = "inductionPort_1",

  monitorScale = 0.5,
  refreshDelay = 0.20,

  ignitionLaserEnergyThreshold = 2000000000, -- 2.0G

  laserChargeStartPct = 90,
  laserChargeStopPct  = 100,

  energyLowPct  = 20,
  energyHighPct = 99,

  emergencyStopIfReactorMissing = true,

  ignitionRetryDelay = 3.0,

  -- Topologie connue issue de diagviewer (prioritaire, avec fallback)
  knownReaders = {
    deuterium = "block_reader_1",
    tritium = "block_reader_2",
    inventory = "block_reader_6",
  },

  knownRelays = {
    laser_charge = { relay = "redstone_relay_0", side = "top",   label = "LAS" },
    deuterium    = { relay = "redstone_relay_1", side = "front", label = "Tank Deuterium" },
    tritium      = { relay = "redstone_relay_2", side = "front", label = "Tank Tritium" },
  },

  -- Mapping des actions redstone
  actions = {
    laser_charge = { relay = "redstone_relay_0", side = "top",   analog = 15, pulse = false },
    deuterium    = { relay = "redstone_relay_1", side = "front", analog = 15, pulse = false },
    tritium      = { relay = "redstone_relay_2", side = "front", analog = 15, pulse = false },

    laser_fire   = { relay = "redstone_relay_0", side = "top",   analog = 15, pulse = true, pulseTime = 0.15 },
    dt_fuel      = nil,
  },
}

local CONFIG_FILE = "fusion_config.lua"
local MONITOR_CACHE_FILE = "fusion_monitor.cfg"
local VERSION_FILE = "fusion.version"

-- Configuration update GitHub
local LOCAL_VERSION = "0.0.0"
local UPDATE_ENABLED = true
local UPDATE_REPO_RAW_BASE = "https://raw.githubusercontent.com/viper1331/fusion-vipercraft/main"
local UPDATE_VERSION_URL = UPDATE_REPO_RAW_BASE .. "/fusion.version"
local UPDATE_SCRIPT_URL = UPDATE_REPO_RAW_BASE .. "/fusion.lua"
local UPDATE_SCRIPT_FILE = "fusion.lua"
local UPDATE_VERSION_FILE = "fusion.version"
local UPDATE_BACKUP_FILE = "fusion.bak"
local UPDATE_VERSION_BACKUP_FILE = "fusion.version.bak"
local UPDATE_TEMP_FILE = "fusion.new"
local UPDATE_TEMP_VERSION_FILE = "fusion.version.new"

local nativeTerm = term.current()
local buttons = {}
local touchHitboxes = { terminal = {}, monitor = {} }
local pressedButtons = {}
local pressedEffectDuration = 0.18

local HITBOX_DEFAULTS = {
  minW = 10,
  minH = 3,
  basePadX = 1,
  basePadY = 1,
  smallBoostPadX = 2,
  smallBoostPadY = 1,
  rowPadX = 1,
  rowPadY = 0,
}

local state = {
  running = true,
  uiDrawn = false,
  choosingMonitor = false,
  monitorList = {},
  monitorPage = 1,

  autoMaster = true,
  chargeAuto = true,
  fusionAuto = true,
  gasAuto = true,

  reactorPresent = false,
  reactorFormed = false,
  ignition = false,
  plasmaTemp = 0,
  ignitionTemp = 0,
  caseTemp = 0,

  laserPresent = false,
  laserEnergy = 0,
  laserMax = 1,
  laserPct = 0,
  laserChargeOn = false,

  energyPresent = false,
  energyKnown = false,
  energyStored = 0,
  energyMax = 1,
  energyPct = 0,

  inductionPresent = false,
  inductionFormed = false,
  inductionEnergy = 0,
  inductionMax = 1,
  inductionPct = 0,
  inductionNeeded = 0,
  inductionInput = 0,
  inductionOutput = 0,
  inductionTransferCap = 0,
  inductionCells = 0,
  inductionProviders = 0,
  inductionLength = 0,
  inductionHeight = 0,
  inductionWidth = 0,
  inductionPortMode = "UNKNOWN",

  deuteriumName = "N/A",
  deuteriumAmount = 0,
  tritiumName = "N/A",
  tritiumAmount = 0,

  auxPresent = false,
  auxActive = false,
  auxRedstone = 0,

  dtOpen = false,
  dOpen = false,
  tOpen = false,

  laserLineOn = false,
  knownLabels = {
    laser = "Charge Laser",
    deuterium = "Tank Deuterium",
    tritium = "Tank Tritium",
    readerD = "Reader Deuterium",
    readerT = "Reader Tritium",
    readerAux = "Reader Aux",
  },

  ignitionSequencePending = false,
  lastIgnitionAttempt = 0,

  status = "Init",
  lastAction = "Aucune",
  alert = "INFO",

  currentView = "supervision",
  safetyWarnings = {},
  ignitionChecklist = {},
  ignitionBlockers = {},
  eventLog = {},
  maxEventLog = 8,

  update = {
    localVersion = LOCAL_VERSION,
    remoteVersion = "UNKNOWN",
    status = UPDATE_ENABLED and "IDLE" or "DISABLED",
    httpStatus = "UNKNOWN",
    lastCheckResult = "Never",
    lastApplyResult = "Never",
    lastError = "",
    available = false,
    restartRequired = false,
    downloaded = false,
    lastCheckClock = 0,
  },

  tick = 0,
  debugHitboxes = false,
}

local hw = {
  monitor = nil,
  monitorName = nil,

  reactor = nil,
  reactorName = nil,

  logic = nil,
  logicName = nil,

  laser = nil,
  laserName = nil,

  induction = nil,
  inductionName = nil,

  relays = {},

  blockReaders = {},
  readerRoles = {
    deuterium = nil,
    tritium = nil,
    inventory = nil,
    energy = nil,
    active = {},
    unknown = {},
  }
}

local UI_PALETTE = {
  bgMain = colors.black,
  bgElevated = colors.gray,
  frameOuter = colors.lightBlue,
  frameInner = colors.cyan,
  frameDim = colors.gray,
  textMain = colors.white,
  textDim = colors.lightGray,
  accentOk = colors.lime,
  accentWarn = colors.orange,
  accentBad = colors.red,
  accentInfo = colors.cyan,
  accentViolet = colors.purple,
  accentLaser = colors.yellow,
  headerBg = colors.gray,
  footerBg = colors.gray,
  buttonNeutral = colors.gray,
  buttonActive = colors.blue,
  buttonPressed = colors.lightGray,
  buttonDanger = colors.red,
  buttonFuelT = colors.green,
  buttonFuelD = colors.red,
  buttonFuelDT = colors.purple,
}

local styles = {
  panel = {
    default = { bg = UI_PALETTE.bgMain, header = UI_PALETTE.bgElevated, border = UI_PALETTE.frameInner, trim = UI_PALETTE.frameDim, text = UI_PALETTE.textMain },
    accent = { bg = UI_PALETTE.bgMain, header = UI_PALETTE.buttonActive, border = UI_PALETTE.frameOuter, trim = UI_PALETTE.frameInner, text = UI_PALETTE.textMain },
  },
  button = {
    primary = { face = UI_PALETTE.buttonActive, rimLight = UI_PALETTE.frameOuter, rimDark = UI_PALETTE.bgMain, text = UI_PALETTE.textMain },
    secondary = { face = UI_PALETTE.buttonNeutral, rimLight = UI_PALETTE.frameInner, rimDark = UI_PALETTE.bgMain, text = UI_PALETTE.textMain },
    danger = { face = UI_PALETTE.buttonDanger, rimLight = UI_PALETTE.accentWarn, rimDark = UI_PALETTE.bgMain, text = UI_PALETTE.textMain },
    fuelT = { face = UI_PALETTE.buttonFuelT, rimLight = UI_PALETTE.accentOk, rimDark = UI_PALETTE.bgMain, text = UI_PALETTE.textMain },
    fuelD = { face = UI_PALETTE.buttonFuelD, rimLight = UI_PALETTE.accentWarn, rimDark = UI_PALETTE.bgMain, text = UI_PALETTE.textMain },
    fuelDT = { face = UI_PALETTE.buttonFuelDT, rimLight = UI_PALETTE.frameOuter, rimDark = UI_PALETTE.bgMain, text = UI_PALETTE.textMain },
    disabled = { face = UI_PALETTE.frameDim, rimLight = UI_PALETTE.textDim, rimDark = UI_PALETTE.bgMain, text = UI_PALETTE.textDim },
  },
}

local C = {
  bg = UI_PALETTE.bgMain,
  panel = UI_PALETTE.bgElevated,
  panelDark = UI_PALETTE.bgMain,
  panelMid = UI_PALETTE.buttonPressed,
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
  return string.format("%x", colors.toBlit(c))
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
  ui.frame(x, y, w, h, skin.border, skin.trim)
  if w > 2 and h > 2 then
    ui.fill(x + 1, y + 1, w - 2, h - 2, skin.bg)
  end
  if title and #title > 0 and w > 8 then
    ui.hline(x + 1, y, w - 2, skin.header)
    ui.write(x + 2, y, uiShortText(" " .. title .. " ", w - 4), skin.text, skin.header)
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
  if not term.isColor or not term.isColor() then return end
  pcall(term.setPaletteColor, colors.black, 0.03, 0.05, 0.09)
  pcall(term.setPaletteColor, colors.gray, 0.14, 0.19, 0.24)
  pcall(term.setPaletteColor, colors.lightGray, 0.28, 0.35, 0.41)
  pcall(term.setPaletteColor, colors.white, 0.84, 0.91, 0.98)
  pcall(term.setPaletteColor, colors.blue, 0.08, 0.24, 0.42)
  pcall(term.setPaletteColor, colors.lightBlue, 0.22, 0.68, 0.92)
  pcall(term.setPaletteColor, colors.cyan, 0.19, 0.83, 0.86)
  pcall(term.setPaletteColor, colors.green, 0.15, 0.55, 0.24)
  pcall(term.setPaletteColor, colors.lime, 0.30, 0.95, 0.50)
  pcall(term.setPaletteColor, colors.red, 0.93, 0.20, 0.23)
  pcall(term.setPaletteColor, colors.orange, 0.94, 0.56, 0.15)
  pcall(term.setPaletteColor, colors.yellow, 0.96, 0.78, 0.16)
  pcall(term.setPaletteColor, colors.purple, 0.67, 0.34, 0.89)
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
  local style = styles.panel.default
  if accent and accent ~= C.border then
    style = {
      bg = styles.panel.default.bg,
      header = accent,
      border = accent,
      trim = styles.panel.default.trim,
      text = styles.panel.default.text,
    }
  end
  ui.panel(x, y, w, h, title, style)
end

local function drawPanelSprite(x, y, w, h, title, style)
  ui.panel(x, y, w, h, title, style or styles.panel.default)
end

local function drawHeaderBarSprite(title, status)
  local tw = term.getSize()
  local heartbeat = (state.tick % 8 < 4) and "•" or " "
  local phase = reactorPhase()
  ui.hline(1, 1, tw, C.headerBg)
  ui.write(2, 1, shortText(title .. " | " .. string.upper(state.currentView), math.max(10, tw - 42)), C.headerText, C.headerBg)
  local centerTxt = "PHASE " .. shortText(phase, 18)
  local cx = math.max(2, math.floor((tw - #centerTxt) / 2))
  ui.write(cx, 1, centerTxt, phaseColor(phase), C.headerBg)
  local statusTxt = shortText(status or "N/A", 16)
  local rightTxt = heartbeat .. " ALERT " .. statusTxt
  local sx = math.max(2, tw - #rightTxt - 1)
  ui.write(sx, 1, rightTxt, statusColor(state.alert), C.headerBg)
end

local function drawFooterBarSprite()
  local tw, th = term.getSize()
  ui.hline(1, th, tw, C.footerBg)
  local labels = {
    { "ACT", shortText(state.lastAction, 18), C.text },
    { "MON", tostring(hw.monitorName or "term"), C.info },
    { "PHASE", reactorPhase(), phaseColor(reactorPhase()) },
    { "LAS", yesno(state.laserLineOn), state.laserLineOn and C.warn or C.dim },
    { "GRID", state.energyKnown and string.format("%3.0f%%", state.energyPct) or "N/A", C.energy },
    { "FUEL", "D " .. formatFuelLevel(state.deuteriumAmount) .. " T " .. formatFuelLevel(state.tritiumAmount), C.fuel },
  }
  local segW = math.max(9, math.floor(tw / #labels))
  for i, item in ipairs(labels) do
    local sx = ((i - 1) * segW) + 1
    local content = shortText(item[1] .. " " .. item[2], segW - 1)
    ui.write(sx, th, content, item[3], C.footerBg)
    if i < #labels and sx + segW - 1 <= tw then ui.write(sx + segW - 1, th, " ", C.borderDim, C.borderDim) end
  end
end

local function getRuntimeFuelMode()
  local dt = state.dtOpen == true
  local d = state.dOpen == true
  local t = state.tOpen == true

  if dt and not d and not t then return "DT" end
  if (not dt) and d and t then return "D+T" end
  if dt and (d or t) then return "HYBRID" end
  return "STARVED"
end

local function isRuntimeFuelOk()
  return (state.dOpen and state.tOpen) or state.dtOpen
end

local function reactorPhase()
  if state.alert == "DANGER" then return "SAFE STOP" end
  if not state.reactorPresent then return "OFFLINE" end
  if not state.reactorFormed then return "UNFORMED" end
  if state.ignition then
    if isRuntimeFuelOk() then
      local mode = getRuntimeFuelMode()
      return mode == "HYBRID" and "RUNNING / HYBRID" or ("RUNNING / " .. mode)
    end
    return "RUNNING / STARVED"
  end
  if #state.ignitionBlockers > 0 then return "BLOCKED" end
  if state.ignitionSequencePending then return "FIRING" end
  if state.laserChargeOn or state.laserLineOn then return "CHARGING" end

  local threshold = toNumber(CFG and CFG.ignitionLaserEnergyThreshold, 0)
  local laserEnergy = toNumber(state.laserEnergy, 0)
  if laserEnergy >= threshold and threshold > 0 then return "READY" end

  return "READY"
end

local function phaseColor(phase)
  if contains(phase, "RUNNING") and not contains(phase, "STARVED") then return C.ok end
  if phase == "RUNNING" or phase == "IGNITED" then return C.ok end
  if phase == "READY" then return C.warn end
  if phase == "CHARGING" or phase == "FIRING" then return C.warn end
  if phase == "SAFE STOP" or phase == "OFFLINE" or phase == "UNFORMED" or phase == "BLOCKED" or contains(phase, "STARVED") then return C.bad end
  return C.dim
end

local function pushEvent(message)
  if not message or #message == 0 then return end
  local stamp = string.format("%05.1f", os.clock() % 1000)
  table.insert(state.eventLog, 1, stamp .. " " .. message)
  while #state.eventLog > (state.maxEventLog or 8) do
    table.remove(state.eventLog)
  end
end

local function getIgnitionChecklist()
  local list = {
    { key = "LAS >= 2 GFE", ok = state.laserEnergy >= CFG.ignitionLaserEnergyThreshold, wait = state.laserPresent },
    { key = "T OPEN", ok = state.tOpen },
    { key = "D OPEN", ok = state.dOpen },
    { key = "REACTOR FORMED", ok = state.reactorPresent and state.reactorFormed },
    { key = "SAFETY OK", ok = #state.safetyWarnings == 0 and state.alert ~= "DANGER" },
  }
  return list
end

local function getIgnitionBlockers()
  local blockers = {}
  for _, item in ipairs(getIgnitionChecklist()) do
    if not item.ok then
      table.insert(blockers, item.key)
    end
  end
  return blockers
end

local function canIgnite()
  return #getIgnitionBlockers() == 0
end

local function computeSafetyWarnings()
  local warnings = {}
  local critical = false

  if not state.reactorPresent then
    table.insert(warnings, "REACTOR ABSENT")
    critical = true
  elseif not state.reactorFormed then
    table.insert(warnings, "REACTOR UNFORMED")
  end

  if (not state.ignition) and state.laserEnergy < CFG.ignitionLaserEnergyThreshold then
    table.insert(warnings, "LAS BELOW 2 GFE")
  end
  if state.ignition then
    if not isRuntimeFuelOk() then
      table.insert(warnings, "RUNTIME FUEL FAIL")
      table.insert(warnings, "NO FUEL FLOW")
      table.insert(warnings, "STARVED")
    end
  else
    if not state.tOpen then table.insert(warnings, "TANK T CLOSED") end
    if not state.dOpen then table.insert(warnings, "TANK D CLOSED") end
  end

  if not hw.readerRoles.deuterium or not hw.readerRoles.tritium then
    table.insert(warnings, "FUEL SENSOR FAIL")
  end
  if not hw.readerRoles.inventory then
    table.insert(warnings, "READER AUX FAIL")
  end

  if not hw.relays[CFG.actions.laser_charge.relay]
    or not hw.relays[CFG.actions.deuterium.relay]
    or not hw.relays[CFG.actions.tritium.relay] then
    table.insert(warnings, "CONTROL LINE FAIL")
    critical = true
  end

  if (not state.ignition) and #state.ignitionBlockers > 0 then
    table.insert(warnings, "IGNITION BLOCKED")
  end

  if #hw.readerRoles.unknown > 0 then table.insert(warnings, "FALLBACK DETECTION") end
  return warnings, critical
end

local function drawHeader(title, status)
  drawHeaderBarSprite(title, status)
end

local function drawFooter(layout)
  drawFooterBarSprite()
end

local function drawKeyValue(x, y, key, value, keyColor, valueColor, maxVal)
  writeAt(x, y, shortText(key, 12), keyColor or C.dim, C.panelDark)
  writeAt(x + 12, y, shortText(value, maxVal or 20), valueColor or C.text, C.panelDark)
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
  drawBox(x, y, w, h, "FUSION CHAMBER", C.border)
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


  writeAt(x + 2, y + 2, shortText("CORE " .. (state.reactorPresent and (state.reactorFormed and "FORMED" or "UNFORMED") or "ABSENT"), math.max(8, math.floor(w * 0.33))), state.reactorPresent and C.info or C.bad, C.panelDark)
end

local function drawBadge(x, y, label, value, tone)
  local badgeTxt = " " .. tostring(value) .. " "
  writeAt(x, y, shortText(label, 9), C.dim, C.panelDark)
  local bx = x + 10
  writeAt(bx, y, badgeTxt, C.text, tone or statusColor(value))
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
  txt = tostring(txt or "")
  return (txt:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function readLocalVersionFile()
  local ok, content = pcall(function()
    if not fs.exists(VERSION_FILE) then return nil end
    local h = fs.open(VERSION_FILE, "r")
    if not h then return nil end
    local v = h.readAll()
    h.close()
    return trimText(v)
  end)
  if ok and content and #content > 0 then
    return content
  end
  return LOCAL_VERSION
end

local function defaultFusionConfig()
  return {
    configVersion = 1,
    setupName = "Fusion ViperCraft",
    monitor = { name = CFG.preferredMonitor, scale = CFG.monitorScale },
    devices = {
      reactorController = CFG.preferredReactor,
      logicAdapter = CFG.preferredLogicAdapter,
      laser = CFG.preferredLaser,
      induction = CFG.preferredInduction,
    },
    relays = {
      laser = { name = CFG.knownRelays.laser_charge.relay, side = CFG.knownRelays.laser_charge.side },
      tritium = { name = CFG.knownRelays.tritium.relay, side = CFG.knownRelays.tritium.side },
      deuterium = { name = CFG.knownRelays.deuterium.relay, side = CFG.knownRelays.deuterium.side },
    },
    readers = {
      tritium = CFG.knownReaders.tritium,
      deuterium = CFG.knownReaders.deuterium,
      aux = CFG.knownReaders.inventory,
    },
    ui = {
      preferredView = "SUP",
      touchEnabled = true,
      refreshDelay = CFG.refreshDelay,
    },
    update = {
      enabled = UPDATE_ENABLED,
    },
  }
end

local function mergeDefaults(target, defaults)
  if type(target) ~= "table" then target = {} end
  for k, v in pairs(defaults) do
    if type(v) == "table" then
      target[k] = mergeDefaults(type(target[k]) == "table" and target[k] or {}, v)
    elseif target[k] == nil then
      target[k] = v
    end
  end
  return target
end

local function migrateConfig(config)
  local cfg = type(config) == "table" and config or {}
  local version = tonumber(cfg.configVersion) or 0

  if version < 1 then
    cfg = mergeDefaults(cfg, defaultFusionConfig())
    cfg.configVersion = 1
  end

  cfg = mergeDefaults(cfg, defaultFusionConfig())
  return cfg
end

local function loadFusionConfig()
  if not fs.exists(CONFIG_FILE) then
    return false, nil, "CONFIG_MISSING"
  end

  local ok, configOrErr = pcall(dofile, CONFIG_FILE)
  if not ok then
    return false, nil, "CONFIG_INVALID: " .. tostring(configOrErr)
  end

  if type(configOrErr) ~= "table" then
    return false, nil, "CONFIG_INVALID: Not a table"
  end

  local migrated = migrateConfig(configOrErr)
  return true, migrated, nil
end

local function applyConfigToRuntime(config)
  if type(config) ~= "table" then return end

  CFG.preferredMonitor = config.monitor and config.monitor.name or CFG.preferredMonitor
  CFG.monitorScale = toNumber(config.monitor and config.monitor.scale, CFG.monitorScale)
  CFG.refreshDelay = toNumber(config.ui and config.ui.refreshDelay, CFG.refreshDelay)

  CFG.preferredReactor = config.devices and config.devices.reactorController or CFG.preferredReactor
  CFG.preferredLogicAdapter = config.devices and config.devices.logicAdapter or CFG.preferredLogicAdapter
  CFG.preferredLaser = config.devices and config.devices.laser or CFG.preferredLaser
  CFG.preferredInduction = config.devices and config.devices.induction or CFG.preferredInduction

  CFG.knownReaders.deuterium = config.readers and config.readers.deuterium or CFG.knownReaders.deuterium
  CFG.knownReaders.tritium = config.readers and config.readers.tritium or CFG.knownReaders.tritium
  CFG.knownReaders.inventory = config.readers and config.readers.aux or CFG.knownReaders.inventory

  CFG.knownRelays.laser_charge.relay = config.relays and config.relays.laser and config.relays.laser.name or CFG.knownRelays.laser_charge.relay
  CFG.knownRelays.laser_charge.side = config.relays and config.relays.laser and config.relays.laser.side or CFG.knownRelays.laser_charge.side
  CFG.knownRelays.tritium.relay = config.relays and config.relays.tritium and config.relays.tritium.name or CFG.knownRelays.tritium.relay
  CFG.knownRelays.tritium.side = config.relays and config.relays.tritium and config.relays.tritium.side or CFG.knownRelays.tritium.side
  CFG.knownRelays.deuterium.relay = config.relays and config.relays.deuterium and config.relays.deuterium.name or CFG.knownRelays.deuterium.relay
  CFG.knownRelays.deuterium.side = config.relays and config.relays.deuterium and config.relays.deuterium.side or CFG.knownRelays.deuterium.side

  if type(config.update) == "table" and config.update.enabled ~= nil then
    UPDATE_ENABLED = config.update.enabled and true or false
  end
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

  applyConfigToRuntime(config)
  return true, config
end

local function isHttpReady()
  return type(http) == "table" and type(http.get) == "function"
end

local function setUpdateState(status, checkResult, applyResult)
  state.update.status = status or state.update.status
  if checkResult then state.update.lastCheckResult = checkResult end
  if applyResult then state.update.lastApplyResult = applyResult end
end

local function httpGetText(url)
  if not isHttpReady() then
    state.update.httpStatus = "DISABLED"
    return false, nil, "HTTP API disabled"
  end

  local ok, response = pcall(http.get, url)
  if not ok or not response then
    state.update.httpStatus = "FAIL"
    return false, nil, "HTTP request failed"
  end

  local readOk, body = pcall(response.readAll)
  pcall(response.close)

  if not readOk then
    state.update.httpStatus = "FAIL"
    return false, nil, "Unable to read response"
  end

  if type(body) ~= "string" or #trimText(body) == 0 then
    state.update.httpStatus = "FAIL"
    return false, nil, "Empty response"
  end

  state.update.httpStatus = "OK"
  return true, body, nil
end

local function parseVersion(version)
  local parts = {}
  for n in tostring(version or "0"):gmatch("%d+") do
    parts[#parts + 1] = tonumber(n) or 0
  end
  if #parts == 0 then parts[1] = 0 end
  return parts
end

local function compareVersions(localV, remoteV)
  local a = parseVersion(localV)
  local b = parseVersion(remoteV)
  local count = math.max(#a, #b)

  for i = 1, count do
    local av = a[i] or 0
    local bv = b[i] or 0
    if bv > av then return 1 end
    if bv < av then return -1 end
  end
  return 0
end

local function validateLuaScript(text)
  if type(text) ~= "string" then return false, "Not a string" end
  if #trimText(text) < 32 then return false, "Downloaded script is too short" end
  if not contains(text, "local CFG") and not contains(text, "state") then
    return false, "Invalid Lua signature"
  end
  return true, nil
end

local function writeTextFile(path, content)
  local h = fs.open(path, "w")
  if not h then return false, "Cannot open file for writing: " .. tostring(path) end
  h.write(content)
  h.close()
  return true, nil
end

local function readTextFile(path)
  if not fs.exists(path) then return false, nil, "File not found: " .. tostring(path) end
  local h = fs.open(path, "r")
  if not h then return false, nil, "Cannot open file: " .. tostring(path) end
  local text = h.readAll()
  h.close()
  return true, text, nil
end

local function checkForUpdate()
  state.update.lastError = ""
  state.update.downloaded = false
  pushEvent("Update check started")

  if not UPDATE_ENABLED then
    state.update.httpStatus = "DISABLED"
    state.update.remoteVersion = "DISABLED"
    state.update.available = false
    setUpdateState("DISABLED", "Update disabled", nil)
    return false, "Update disabled"
  end

  local ok, body, err = httpGetText(UPDATE_VERSION_URL)
  if not ok then
    state.update.remoteVersion = "UNKNOWN"
    state.update.available = false
    state.update.lastError = err or "Unknown network error"
    setUpdateState("FAILED", "Check failed: " .. state.update.lastError, nil)
    pushEvent("Update failed")
    return false, state.update.lastError
  end

  local remoteVersion = trimText(body)
  state.update.remoteVersion = remoteVersion
  state.update.lastCheckClock = os.clock()
  pushEvent("Remote version found " .. remoteVersion)

  local cmp = compareVersions(state.update.localVersion, remoteVersion)
  if cmp == 1 then
    state.update.available = true
    setUpdateState("UPDATE AVAILABLE", "Remote " .. remoteVersion .. " > local " .. state.update.localVersion, nil)
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

  setUpdateState("DOWNLOADING", nil, "Download started")
  pushEvent("Download started")

  local okVersion, versionBody, versionErr = httpGetText(UPDATE_VERSION_URL)
  if not okVersion then
    state.update.lastError = versionErr or "Version download failed"
    setUpdateState("FAILED", nil, "Version download failed: " .. state.update.lastError)
    pushEvent("Update failed")
    return false, state.update.lastError
  end

  local remoteVersion = trimText(versionBody)
  if #remoteVersion == 0 then
    state.update.lastError = "Remote version is empty"
    setUpdateState("FAILED", nil, "Invalid remote version")
    pushEvent("Update failed")
    return false, state.update.lastError
  end

  local okScript, scriptBody, scriptErr = httpGetText(UPDATE_SCRIPT_URL)
  if not okScript then
    state.update.lastError = scriptErr or "Script download failed"
    setUpdateState("FAILED", nil, "Script download failed: " .. state.update.lastError)
    pushEvent("Update failed")
    return false, state.update.lastError
  end

  local valid, reason = validateLuaScript(scriptBody)
  if not valid then
    state.update.lastError = reason or "Invalid update script"
    setUpdateState("FAILED", nil, "Validation failed: " .. state.update.lastError)
    pushEvent("Update failed")
    return false, state.update.lastError
  end

  local writeVersionOk, writeVersionErr = writeTextFile(UPDATE_TEMP_VERSION_FILE, remoteVersion .. "\n")
  if not writeVersionOk then
    state.update.lastError = writeVersionErr or "Cannot write temp version"
    setUpdateState("FAILED", nil, "Temp version write failed")
    pushEvent("Update failed")
    return false, state.update.lastError
  end

  local writeScriptOk, writeScriptErr = writeTextFile(UPDATE_TEMP_FILE, scriptBody)
  if not writeScriptOk then
    state.update.lastError = writeScriptErr or "Cannot write temp script"
    setUpdateState("FAILED", nil, "Temp script write failed")
    pushEvent("Update failed")
    return false, state.update.lastError
  end

  state.update.remoteVersion = remoteVersion
  state.update.downloaded = true
  setUpdateState("DOWNLOADED", nil, "Version and script downloaded")
  pushEvent("Download complete")
  return true, nil
end

local function applyUpdate()
  state.update.lastError = ""
  if not fs.exists(UPDATE_TEMP_FILE) or not fs.exists(UPDATE_TEMP_VERSION_FILE) then
    setUpdateState("FAILED", nil, "Missing downloaded files")
    return false, "Missing downloaded files"
  end

  setUpdateState("APPLYING", nil, "Applying update")

  local okNewScript, newScript, errNewScript = readTextFile(UPDATE_TEMP_FILE)
  if not okNewScript then
    state.update.lastError = errNewScript or "Cannot read temp script"
    setUpdateState("FAILED", nil, "Apply failed: " .. state.update.lastError)
    pushEvent("Update failed")
    return false, state.update.lastError
  end

  local scriptValid, scriptReason = validateLuaScript(newScript)
  if not scriptValid then
    state.update.lastError = scriptReason or "Invalid temp script"
    setUpdateState("FAILED", nil, "Apply failed: invalid script")
    pushEvent("Update failed")
    return false, state.update.lastError
  end

  local okNewVersion, newVersionText, errNewVersion = readTextFile(UPDATE_TEMP_VERSION_FILE)
  if not okNewVersion then
    state.update.lastError = errNewVersion or "Cannot read temp version"
    setUpdateState("FAILED", nil, "Apply failed: invalid version")
    pushEvent("Update failed")
    return false, state.update.lastError
  end

  local newVersion = trimText(newVersionText)
  if #newVersion == 0 then
    state.update.lastError = "Temp version is empty"
    setUpdateState("FAILED", nil, "Apply failed: invalid version")
    pushEvent("Update failed")
    return false, state.update.lastError
  end

  local okCurrentScript, currentScript, errCurrentScript = readTextFile(UPDATE_SCRIPT_FILE)
  if not okCurrentScript then
    state.update.lastError = errCurrentScript or "Cannot read current script"
    setUpdateState("FAILED", nil, "Apply failed: cannot backup script")
    pushEvent("Update failed")
    return false, state.update.lastError
  end

  local currentVersion = ""
  if fs.exists(UPDATE_VERSION_FILE) then
    local okCurrentVersion, currentVersionText = readTextFile(UPDATE_VERSION_FILE)
    if okCurrentVersion then currentVersion = currentVersionText end
  end

  local okBackupScript, errBackupScript = writeTextFile(UPDATE_BACKUP_FILE, currentScript)
  if not okBackupScript then
    state.update.lastError = errBackupScript or "Script backup failed"
    setUpdateState("FAILED", nil, "Backup failed")
    pushEvent("Update failed")
    return false, state.update.lastError
  end

  local okBackupVersion, errBackupVersion = writeTextFile(UPDATE_VERSION_BACKUP_FILE, currentVersion)
  if not okBackupVersion then
    state.update.lastError = errBackupVersion or "Version backup failed"
    setUpdateState("FAILED", nil, "Backup failed")
    pushEvent("Update failed")
    return false, state.update.lastError
  end

  local okWriteScript, errWriteScript = writeTextFile(UPDATE_SCRIPT_FILE, newScript)
  if not okWriteScript then
    pcall(writeTextFile, UPDATE_SCRIPT_FILE, currentScript)
    state.update.lastError = errWriteScript or "Cannot replace script"
    setUpdateState("FAILED", nil, "Apply failed: script write")
    pushEvent("Update failed")
    return false, state.update.lastError
  end

  local okWriteVersion, errWriteVersion = writeTextFile(UPDATE_VERSION_FILE, newVersion .. "\n")
  if not okWriteVersion then
    pcall(writeTextFile, UPDATE_SCRIPT_FILE, currentScript)
    pcall(writeTextFile, UPDATE_VERSION_FILE, currentVersion)
    state.update.lastError = errWriteVersion or "Cannot replace version"
    setUpdateState("FAILED", nil, "Apply failed: version write")
    pushEvent("Update failed")
    return false, state.update.lastError
  end

  pcall(fs.delete, UPDATE_TEMP_FILE)
  pcall(fs.delete, UPDATE_TEMP_VERSION_FILE)
  state.update.downloaded = false
  state.update.restartRequired = true
  state.update.localVersion = newVersion
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
  if not fs.exists(UPDATE_BACKUP_FILE) then
    setUpdateState("FAILED", nil, "No backup file")
    return false, "No backup file"
  end

  local okBackup, backupText, errBackup = readTextFile(UPDATE_BACKUP_FILE)
  if not okBackup then
    setUpdateState("FAILED", nil, "Rollback failed")
    return false, errBackup
  end

  local versionBackupText = nil
  if fs.exists(UPDATE_VERSION_BACKUP_FILE) then
    local okVersionBackup, versionText = readTextFile(UPDATE_VERSION_BACKUP_FILE)
    if okVersionBackup then versionBackupText = versionText end
  end

  local okWrite, errWrite = writeTextFile(UPDATE_SCRIPT_FILE, backupText)
  if not okWrite then
    setUpdateState("FAILED", nil, "Rollback failed")
    return false, errWrite
  end

  if versionBackupText ~= nil then
    pcall(writeTextFile, UPDATE_VERSION_FILE, versionBackupText)
    state.update.localVersion = trimText(versionBackupText)
  end

  state.update.restartRequired = true
  state.update.downloaded = false
  setUpdateState("RESTART REQUIRED", nil, "Rollback applied. Restart required")
  pushEvent("Rollback applied")
  pushEvent("Restart required")
  return true, nil
end

local function getMonitorCandidates()
  local monitors = {}
  for _, name in ipairs(peripheral.getNames()) do
    if getTypeOf(name) == "monitor" then
      local obj = safePeripheral(name)
      local w, h = 0, 0
      if obj and type(obj.getSize) == "function" then
        local ok, mw, mh = pcall(obj.getSize)
        if ok then
          w, h = mw, mh
        end
      end
      table.insert(monitors, { name = name, obj = obj, w = w, h = h })
    end
  end
  table.sort(monitors, function(a, b) return a.name < b.name end)
  return monitors
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

  if hw.monitor then
    term.redirect(nativeTerm)
    hw.monitor.setTextScale(CFG.monitorScale)
    hw.monitor.setBackgroundColor(C.bg)
    hw.monitor.setTextColor(C.text)
    term.redirect(hw.monitor)
  else
    term.redirect(nativeTerm)
  end

  term.setCursorBlink(false)
end

local function restoreTerm()
  term.redirect(nativeTerm)
  term.setCursorBlink(false)
end

local function hasMethods(obj, methods, minCount)
  if not obj then return false end
  local count = 0
  for _, m in ipairs(methods) do
    if type(obj[m]) == "function" then
      count = count + 1
    end
  end
  return count >= (minCount or 1)
end

local function detectBestPeripheral(preferredName, validator)
  local p = safePeripheral(preferredName)
  if p and validator(p, preferredName) then
    return p, preferredName
  end

  for _, name in ipairs(peripheral.getNames()) do
    local obj = safePeripheral(name)
    if obj and validator(obj, name) then
      return obj, name
    end
  end

  return nil, nil
end

local function scanPeripherals()
  hw.relays = {}
  hw.blockReaders = {}

  hw.logic, hw.logicName = detectBestPeripheral(CFG.preferredLogicAdapter, function(obj, name)
    return contains(name, "fusion") or hasMethods(obj, { "isFormed", "isIgnited", "getPlasmaTemperature", "getCaseTemperature" }, 2)
  end)

  hw.reactor, hw.reactorName = detectBestPeripheral(CFG.preferredReactor, function(obj, name)
    return contains(name, "fusion_reactor") or contains(name, "reactor_controller")
        or hasMethods(obj, { "isIgnited", "getPlasmaTemperature", "getIgnitionTemperature" }, 2)
  end)

  hw.laser, hw.laserName = detectBestPeripheral(CFG.preferredLaser, function(obj, name)
    return contains(name, "laser") or hasMethods(obj, { "getEnergy", "getEnergyStored", "getMaxEnergyStored" }, 2)
  end)

  hw.induction, hw.inductionName = detectBestPeripheral(CFG.preferredInduction, function(obj, name)
    return contains(name, "induction") or hasMethods(obj, { "getEnergy", "getEnergyStored", "getMaxEnergyStored", "getEnergyCapacity" }, 2)
  end)

  for _, name in ipairs(peripheral.getNames()) do
    local ptype = getTypeOf(name)

    if ptype == "redstone_relay" then
      hw.relays[name] = safePeripheral(name)
    elseif ptype == "block_reader" or contains(name, "block_reader") then
      table.insert(hw.blockReaders, {
        name = name,
        obj = safePeripheral(name),
        role = "unknown",
        data = nil,
      })
    end
  end
end

local function resolveKnownRelays()
  for action, cfg in pairs(CFG.knownRelays) do
    if CFG.actions[action] == nil then
      CFG.actions[action] = { relay = cfg.relay, side = cfg.side, analog = 15, pulse = false }
    else
      CFG.actions[action].relay = cfg.relay
      CFG.actions[action].side = cfg.side
      CFG.actions[action].analog = CFG.actions[action].analog or 15
      CFG.actions[action].pulse = false
    end
  end
end

local function resolveKnownReaders()
  local byName = {}

  for _, entry in ipairs(hw.blockReaders) do
    byName[entry.name] = entry
  end

  if byName[CFG.knownReaders.deuterium] then
    hw.readerRoles.deuterium = byName[CFG.knownReaders.deuterium]
    hw.readerRoles.deuterium.role = "deuterium"
  end

  if byName[CFG.knownReaders.tritium] then
    hw.readerRoles.tritium = byName[CFG.knownReaders.tritium]
    hw.readerRoles.tritium.role = "tritium"
  end

  if byName[CFG.knownReaders.inventory] then
    hw.readerRoles.inventory = byName[CFG.knownReaders.inventory]
    hw.readerRoles.inventory.role = "inventory"
  end
end

local function resolveKnownTopology()
  resolveKnownRelays()
  resolveKnownReaders()
end

local function classifyBlockReaderData(data)
  if type(data) ~= "table" then return "unknown" end

  if type(data.chemical_tanks) == "table" and type(data.chemical_tanks[1]) == "table" then
    local stored = data.chemical_tanks[1].stored
    if type(stored) == "table" then
      local chemId = tostring(stored.id or "")
      if contains(chemId, "deuterium") then
        return "deuterium"
      elseif contains(chemId, "tritium") then
        return "tritium"
      end
    end
    return "chemical"
  end

  if type(data.energy_containers) == "table" then
    return "energy"
  end

  if data.inventory ~= nil or data.items ~= nil or data.slots ~= nil then
    return "inventory"
  end

  if data.active_state ~= nil or data.redstone ~= nil or data.current_redstone ~= nil then
    return "active"
  end

  return "unknown"
end

local function scanBlockReaders()
  hw.readerRoles = {
    deuterium = nil,
    tritium = nil,
    inventory = nil,
    energy = nil,
    active = {},
    unknown = {},
  }

  resolveKnownTopology()

  for _, entry in ipairs(hw.blockReaders) do
    entry.role = "unknown"
    entry.data = nil

    if entry.obj and type(entry.obj.getBlockData) == "function" then
      local ok, data = pcall(entry.obj.getBlockData)
      if ok then
        entry.data = data
        entry.role = classifyBlockReaderData(data)
      end
    end

    if entry == hw.readerRoles.deuterium or entry == hw.readerRoles.tritium or entry == hw.readerRoles.inventory then
      -- deja force par topologie connue
    elseif entry.role == "deuterium" and not hw.readerRoles.deuterium then
      hw.readerRoles.deuterium = entry
    elseif entry.role == "tritium" and not hw.readerRoles.tritium then
      hw.readerRoles.tritium = entry
    elseif entry.role == "inventory" and not hw.readerRoles.inventory then
      hw.readerRoles.inventory = entry
    elseif entry.role == "energy" and not hw.readerRoles.energy then
      hw.readerRoles.energy = entry
    elseif entry.role == "active" then
      table.insert(hw.readerRoles.active, entry)
    else
      table.insert(hw.readerRoles.unknown, entry)
    end
  end
end

local function extractChemicalData(raw)
  if type(raw) ~= "table" then return "N/A", 0 end
  local tanks = raw.chemical_tanks
  if type(tanks) ~= "table" or type(tanks[1]) ~= "table" then return "N/A", 0 end
  local stored = tanks[1].stored
  if type(stored) ~= "table" then return "VIDE", 0 end
  return tostring(stored.id or "UNKNOWN"), toNumber(stored.amount, 0)
end

local function readChemicalFromReader(entry)
  if not entry or not entry.data then return "N/A", 0 end
  return extractChemicalData(entry.data)
end

local function readActiveFromReader(entry)
  if not entry or not entry.data then return false, 0 end
  local a = entry.data.active_state
  local active = (a == true) or (tonumber(a) == 1)
  return active, toNumber(entry.data.current_redstone or entry.data.redstone, 0)
end

local function relayWrite(actionName, on)
  local cfg = CFG.actions[actionName]
  if not cfg then return false end

  local relay = hw.relays[cfg.relay]
  if not relay then return false end

  if cfg.pulse then
    if on then
      if type(relay.setAnalogOutput) == "function" then
        relay.setAnalogOutput(cfg.side, cfg.analog or 15)
        sleep(cfg.pulseTime or 0.2)
        relay.setAnalogOutput(cfg.side, 0)
        return true
      elseif type(relay.setOutput) == "function" then
        relay.setOutput(cfg.side, true)
        sleep(cfg.pulseTime or 0.2)
        relay.setOutput(cfg.side, false)
        return true
      end
    end
  else
    if type(relay.setAnalogOutput) == "function" then
      relay.setAnalogOutput(cfg.side, on and (cfg.analog or 15) or 0)
      return true
    elseif type(relay.setOutput) == "function" then
      relay.setOutput(cfg.side, on and true or false)
      return true
    end
  end

  return false
end

local function readRelayOutputState(actionName, fallback)
  local cfg = CFG.actions[actionName]
  if not cfg then return fallback end
  local relay = hw.relays[cfg.relay]
  if not relay then return fallback end

  if type(relay.getAnalogOutput) == "function" then
    local ok, v = pcall(relay.getAnalogOutput, cfg.side)
    if ok then return toNumber(v, 0) > 0 end
  end

  if type(relay.getOutput) == "function" then
    local ok, v = pcall(relay.getOutput, cfg.side)
    if ok then return v == true end
  end

  return fallback
end

local function setLaserCharge(on)
  if state.laserChargeOn == on then return end
  relayWrite("laser_charge", on)
  state.laserChargeOn = on
  state.lastAction = on and "Charge laser ON" or "Charge laser OFF"
  pushEvent(state.lastAction)
end

local function fireLaser()
  if CFG.actions.laser_fire and relayWrite("laser_fire", true) then
    state.lastAction = "Pulse LAS"
    pushEvent("Pulse LAS")
  else
    state.lastAction = "Laser pulse non cable"
    pushEvent("Pulse LAS FAIL")
  end
end

local function openDTFuel(on)
  if state.dtOpen == on then return end
  if CFG.actions.dt_fuel then
    relayWrite("dt_fuel", on)
  end
  state.dtOpen = on
  state.lastAction = on and "DT OPEN" or "DT CLOSED"
  pushEvent(state.lastAction)
end

local function openDeuterium(on)
  if state.dOpen == on then return end
  if CFG.actions.deuterium then
    relayWrite("deuterium", on)
  end
  state.dOpen = on
  pushEvent(on and "D line OPEN" or "D line CLOSED")
end

local function openTritium(on)
  if state.tOpen == on then return end
  if CFG.actions.tritium then
    relayWrite("tritium", on)
  end
  state.tOpen = on
  pushEvent(on and "T line OPEN" or "T line CLOSED")
end

local function openSeparatedGases(on)
  openDeuterium(on)
  openTritium(on)
  state.lastAction = on and "Ouverture tanks separes" or "Fermeture tanks separes"
end

local function hardStop(reason)
  openDTFuel(false)
  openSeparatedGases(false)
  setLaserCharge(false)
  state.ignitionSequencePending = false
  state.status = reason or "EMERGENCY STOP"
  state.alert = "DANGER"
  state.lastAction = "Arret securite"
  pushEvent("Emergency stop")
end

local function detectReactorFormed()
  if hw.logic then
    local ok, formed = tryMethods(hw.logic, { "isFormed", "getFormed" })
    if ok then return formed == true end
  end

  if hw.reactor then
    local okPlasma, plasma = tryMethods(hw.reactor, { "getPlasmaTemperature", "getPlasmaTemp", "getPlasmaHeat" })
    local okIgn, ign = tryMethods(hw.reactor, { "isIgnited", "getIgnitionStatus" })
    if okPlasma and plasma ~= nil then return true end
    if okIgn and ign ~= nil then return true end
  end

  return false
end

local function readLaser()
  state.laserPresent = hw.laser ~= nil
  if not hw.laser then
    state.laserEnergy = 0
    state.laserMax = 1
    state.laserPct = 0
    return
  end

  local okE, e = tryMethods(hw.laser, { "getEnergy", "getEnergyStored", "getStored" })
  local okM, m = tryMethods(hw.laser, { "getMaxEnergy", "getMaxEnergyStored", "getCapacity" })

  state.laserEnergy = toNumber(e, 0)
  state.laserMax = math.max(1, toNumber(m, 1))
  state.laserPct = clamp((state.laserEnergy * 100) / state.laserMax, 0, 100)
end

local function readReactor()
  state.reactorPresent = hw.reactor ~= nil or hw.logic ~= nil
  state.reactorFormed = detectReactorFormed()

  if hw.logic then
    local okIgn, ign = tryMethods(hw.logic, { "isIgnited" })
    if okIgn then state.ignition = (ign == true) end

    local okPlasma, plasma = tryMethods(hw.logic, { "getPlasmaTemperature", "getPlasmaTemp", "getPlasmaHeat" })
    if okPlasma then state.plasmaTemp = toNumber(plasma, 0) end

    local okIgnTemp, ignTemp = tryMethods(hw.logic, { "getIgnitionTemperature", "getIgnitionTemp" })
    if okIgnTemp then
      state.ignitionTemp = toNumber(ignTemp, 0)
      state.minTemp = state.ignitionTemp + 10000
    end

    local okCase, caseTemp = tryMethods(hw.logic, { "getCaseTemperature", "getCasingTemperature" })
    if okCase then state.caseTemp = toNumber(caseTemp, 0) end
  elseif hw.reactor then
    local okIgn, ign = tryMethods(hw.reactor, { "isIgnited", "getIgnitionStatus" })
    state.ignition = okIgn and (ign == true or ign == "true") or false

    local okPlasma, plasma = tryMethods(hw.reactor, { "getPlasmaTemperature", "getPlasmaTemp", "getPlasmaHeat" })
    state.plasmaTemp = toNumber(plasma, 0)

    local okIgnTemp, ignTemp = tryMethods(hw.reactor, { "getIgnitionTemperature", "getIgnitionTemp" })
    state.ignitionTemp = toNumber(ignTemp, 0)
    state.minTemp = state.ignitionTemp + 10000

    local okCase, caseTemp = tryMethods(hw.reactor, { "getCaseTemperature", "getCasingTemperature" })
    state.caseTemp = toNumber(caseTemp, 0)
  else
    state.ignition = false
    state.plasmaTemp = 0
    state.ignitionTemp = 0
    state.caseTemp = 0
  end

  if state.ignition then
    state.ignitionSequencePending = false
  elseif state.ignitionSequencePending and ((os.clock() - state.lastIgnitionAttempt) > CFG.ignitionRetryDelay) then
    state.ignitionSequencePending = false
  end
end

local function readInductionStatus()
  state.inductionPresent = hw.induction ~= nil
  state.inductionFormed = false
  state.inductionEnergy = 0
  state.inductionMax = 1
  state.inductionPct = 0
  state.inductionNeeded = 0
  state.inductionInput = 0
  state.inductionOutput = 0
  state.inductionTransferCap = 0
  state.inductionCells = 0
  state.inductionProviders = 0
  state.inductionLength = 0
  state.inductionHeight = 0
  state.inductionWidth = 0
  state.inductionPortMode = "UNKNOWN"

  state.energyPresent = state.inductionPresent
  state.energyKnown = false
  state.energyStored = 0
  state.energyMax = 1
  state.energyPct = 0

  if not hw.induction then return end

  local okFormed, formed = safeCall(hw.induction, "isFormed")
  local okEnergy, energy = safeCall(hw.induction, "getEnergy")
  local okMax, maxEnergy = safeCall(hw.induction, "getMaxEnergy")
  local okPct, pct = safeCall(hw.induction, "getEnergyFilledPercentage")
  local okNeed, needed = safeCall(hw.induction, "getEnergyNeeded")
  local okIn, lastInput = safeCall(hw.induction, "getLastInput")
  local okOut, lastOutput = safeCall(hw.induction, "getLastOutput")
  local okCap, transferCap = safeCall(hw.induction, "getTransferCap")
  local okCells, cells = safeCall(hw.induction, "getInstalledCells")
  local okProv, providers = safeCall(hw.induction, "getInstalledProviders")
  local okLen, length = safeCall(hw.induction, "getLength")
  local okHeight, height = safeCall(hw.induction, "getHeight")
  local okWidth, width = safeCall(hw.induction, "getWidth")
  local okPortMode, portMode = safeCall(hw.induction, "getMode")

  state.inductionFormed = okFormed and formed == true or false
  state.inductionEnergy = toNumber(energy, 0)
  state.inductionMax = math.max(1, toNumber(maxEnergy, 1))
  state.inductionNeeded = toNumber(needed, math.max(0, state.inductionMax - state.inductionEnergy))
  state.inductionInput = toNumber(lastInput, 0)
  state.inductionOutput = toNumber(lastOutput, 0)
  state.inductionTransferCap = toNumber(transferCap, 0)
  state.inductionCells = toNumber(cells, 0)
  state.inductionProviders = toNumber(providers, 0)
  state.inductionLength = toNumber(length, 0)
  state.inductionHeight = toNumber(height, 0)
  state.inductionWidth = toNumber(width, 0)
  state.inductionPortMode = okPortMode and normalizePortMode(portMode) or "UNKNOWN"

  if okPct then
    local rawPct = toNumber(pct, 0)
    if rawPct <= 1.0 then
      rawPct = rawPct * 100
    end
    state.inductionPct = clamp(rawPct, 0, 100)
  else
    state.inductionPct = clamp((state.inductionEnergy * 100) / state.inductionMax, 0, 100)
  end

  state.energyKnown = okEnergy or okMax or okPct
  state.energyStored = state.inductionEnergy
  state.energyMax = state.inductionMax
  state.energyPct = state.inductionPct
end

local function readReaders()
  state.deuteriumName, state.deuteriumAmount = readChemicalFromReader(hw.readerRoles.deuterium)
  state.tritiumName, state.tritiumAmount = readChemicalFromReader(hw.readerRoles.tritium)

  local auxReader = hw.readerRoles.inventory or hw.readerRoles.active[1]
  if auxReader then
    state.auxPresent = true
    local active, rs = readActiveFromReader(auxReader)
    state.auxActive = active
    state.auxRedstone = rs
  else
    state.auxPresent = false
    state.auxActive = false
    state.auxRedstone = 0
  end

  state.laserLineOn = readRelayOutputState("laser_charge", state.laserChargeOn)
  state.dOpen = readRelayOutputState("deuterium", state.dOpen)
  state.tOpen = readRelayOutputState("tritium", state.tOpen)
end

local function refreshAll()
  local wasIgnited = state.ignition
  scanPeripherals()
  scanBlockReaders()
  readLaser()
  readReactor()
  readInductionStatus()
  readReaders()
  if (not wasIgnited) and state.ignition then
    pushEvent("Reactor running")
  end
  state.tick = (state.tick or 0) + 1
end

local function updateAlerts()
  state.ignitionChecklist = getIgnitionChecklist()
  state.ignitionBlockers = getIgnitionBlockers()
  local warnings, critical = computeSafetyWarnings()
  state.safetyWarnings = warnings
  local preStartBlocked = (not state.ignition) and (#state.ignitionBlockers > 0)
  if critical then
    state.alert = "DANGER"
  elseif #warnings > 0 or preStartBlocked or (state.energyKnown and state.energyPct <= CFG.energyLowPct) then
    state.alert = "WARN"
  elseif state.ignition then
    state.alert = "OK"
  else
    state.alert = "INFO"
  end
end

local function startReactorSequence()
  state.ignitionChecklist = getIgnitionChecklist()
  state.ignitionBlockers = getIgnitionBlockers()

  if state.ignitionSequencePending then
    state.status = "FIRING"
    return false
  end

  if not canIgnite() then
    state.status = "BLOCKED"
    state.lastAction = "Ignition refused"
    pushEvent("Ignition refused")
    return false
  end

  state.ignitionSequencePending = true
  state.lastIgnitionAttempt = os.clock()
  openDTFuel(false)
  sleep(0.15)
  fireLaser()
  state.status = "FIRING"
  state.lastAction = "Start sequence"
  pushEvent("Ignition start sequence")
  return true
end

local function stopReactorSequence(reason)
  openDTFuel(false)
  openSeparatedGases(false)
  setLaserCharge(false)
  state.ignitionSequencePending = false
  state.status = reason or "ARRET"
  state.lastAction = "Arret commande"
  pushEvent("Reactor stop sequence")
end

local function triggerAutomaticIgnitionSequence()
  return startReactorSequence()
end

local function autoChargeLaser()
  if not state.chargeAuto then return end

  if state.laserPct >= CFG.laserChargeStopPct then
    if state.laserChargeOn then setLaserCharge(false) end
  elseif state.laserPct <= CFG.laserChargeStartPct then
    if not state.laserChargeOn then setLaserCharge(true) end
  end
end

local function autoFusionControl()
  if not state.fusionAuto then return end

  if not state.reactorFormed then
    state.status = "BLOCKED"
    openDTFuel(false)
    openSeparatedGases(false)
    return
  end

  if (not state.ignition) and (not state.ignitionSequencePending) and state.laserEnergy >= CFG.ignitionLaserEnergyThreshold then
    triggerAutomaticIgnitionSequence()
    return
  end

  if state.energyKnown then
    if state.energyPct <= CFG.energyLowPct then
      if state.ignition and not state.dtOpen then
        openDTFuel(true)
        openSeparatedGases(false)
        state.status = "Energie basse : D-T actif"
      elseif not state.ignition then
        state.status = state.ignitionSequencePending and "Ignition en attente" or "Attente seuil 2.0G"
      end
    elseif state.energyPct >= CFG.energyHighPct and state.ignition then
      openDTFuel(false)
      openSeparatedGases(false)
      state.status = "Energie pleine : stop injection"
    else
      if state.ignition and not isRuntimeFuelOk() then
        state.status = "RUNNING / STARVED"
      else
        state.status = state.ignition and ("RUNNING / " .. getRuntimeFuelMode()) or "READY"
      end
    end
  else
    if not state.ignition and not state.ignitionSequencePending and state.laserEnergy >= CFG.ignitionLaserEnergyThreshold then
      triggerAutomaticIgnitionSequence()
    else
      if state.ignition and not isRuntimeFuelOk() then
        state.status = "RUNNING / STARVED"
      else
        state.status = state.ignition and ("RUNNING / " .. getRuntimeFuelMode()) or (state.ignitionSequencePending and "FIRING" or "READY")
      end
    end
  end
end

local function autoGasSanity()
  if not state.gasAuto then return end
  if (not state.ignition) and state.dtOpen and (state.dOpen or state.tOpen) then
    openSeparatedGases(false)
  end
end

local function autoSafety()
  if not state.autoMaster then return end
  if CFG.emergencyStopIfReactorMissing and not state.reactorPresent then
    hardStop("Reactor absent")
  end
end

local function fullAuto()
  if not state.autoMaster then
    updateAlerts()
    return
  end
  autoSafety()
  autoChargeLaser()
  autoFusionControl()
  autoGasSanity()
  updateAlerts()
end

local function getHitboxBucket(source)
  return source == "monitor" and touchHitboxes.monitor or touchHitboxes.terminal
end

local function clearHitboxes(source)
  if source then
    local bucket = getHitboxBucket(source)
    for i = #bucket, 1, -1 do bucket[i] = nil end
    return
  end
  clearHitboxes("terminal")
  clearHitboxes("monitor")
end

local function addHitbox(source, id, x1, y1, x2, y2, action)
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

local function isInsideBox(x, y, box)
  return x >= box.x1 and x <= box.x2 and y >= box.y1 and y <= box.y2
end

local function setButtonPressed(source, id)
  pressedButtons[source .. ":" .. id] = os.clock() + pressedEffectDuration
end

local function isButtonPressed(source, id)
  local key = source .. ":" .. id
  local untilTs = pressedButtons[key]
  if not untilTs then return false end
  if os.clock() <= untilTs then return true end
  pressedButtons[key] = nil
  return false
end

local function addButton(id, x, y, w, h, label, bg, fg, action, opts)
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

local function resolveButtonStyle(button)
  if button.style and styles.button[button.style] then
    return styles.button[button.style]
  end

  if button.bg == C.btnWarn then return styles.button.danger end
  if button.bg == C.tritium then return styles.button.fuelT end
  if button.bg == C.deuterium then return styles.button.fuelD end
  if button.bg == C.dtFuel then return styles.button.fuelDT end
  if button.bg == C.btnAction then return styles.button.primary end

  return styles.button.secondary
end

local function drawButtonSprite(button, style)
  local skin = style or resolveButtonStyle(button)
  ui.fill(button.x, button.y, button.w, button.h, skin.face)
  if button.w >= 2 and button.h >= 2 then
    ui.hline(button.x, button.y, button.w, skin.rimLight)
    ui.vline(button.x, button.y + 1, button.h - 2, skin.rimLight)
    ui.hline(button.x, button.y + button.h - 1, button.w, skin.rimDark)
    ui.vline(button.x + button.w - 1, button.y + 1, button.h - 2, skin.rimDark)
  end
  return skin.face, skin.text
end

local function drawButtonPressedSprite(button, style)
  local skin = style or resolveButtonStyle(button)
  local pressed = { face = UI_PALETTE.buttonPressed, rimLight = skin.face, rimDark = skin.rimDark, text = skin.text }
  return drawButtonSprite(button, pressed)
end

local function drawButtonDisabledSprite(button)
  return drawButtonSprite(button, styles.button.disabled)
end

local function drawButtonActiveSprite(button, style)
  return drawButtonSprite(button, style or resolveButtonStyle(button))
end

local function drawTabSprite(x, y, w, label, isActive)
  local bg = isActive and UI_PALETTE.buttonActive or UI_PALETTE.bgElevated
  local edge = isActive and UI_PALETTE.frameOuter or UI_PALETTE.frameDim
  ui.hline(x, y, w, bg)
  ui.hline(x, y + 1, w, edge)
  ui.write(x + 1, y, shortText(label, math.max(1, w - 2)), C.text, bg)
end

local function drawStatusBarSprite(x, y, w, title, value, tone)
  ui.hline(x, y, w, UI_PALETTE.bgElevated)
  ui.write(x + 1, y, shortText(title .. ":", math.max(1, w - 2)), C.dim, UI_PALETTE.bgElevated)
  local txt = shortText(value, math.max(1, w - #title - 4))
  ui.write(x + math.max(2, w - #txt - 1), y, txt, tone or C.info, UI_PALETTE.bgElevated)
end

local function drawRaisedButton(button)
  return drawButtonActiveSprite(button)
end

local function drawPressedButton(button)
  return drawButtonPressedSprite(button)
end

local function drawButton(source, button)
  local isPressed = (not button.disabled) and isButtonPressed(source, button.id)
  local faceColor, textColor
  if button.disabled then
    faceColor, textColor = drawButtonDisabledSprite(button)
  else
    faceColor, textColor = isPressed and drawPressedButton(button) or drawRaisedButton(button)
  end

  local textOffset = isPressed and 1 or 0
  local lx = button.x + math.max(1, math.floor((button.w - #button.label) / 2)) + textOffset
  local ly = button.y + math.floor((button.h - 1) / 2) + textOffset
  lx = clamp(lx, button.x + 1, button.x + button.w - #button.label)
  ly = clamp(ly, button.y + 1, button.y + button.h - 1)
  writeAt(lx, ly, button.label, textColor or button.fg, faceColor)

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

local function drawBigButton(id, x, y, w, label, bg, action)
  addButton(id, x, y, w, 5, label, bg, C.btnText, action, { big = true })
end

local function addRowButton(id, x, y, w, h, label, bg, fg, action)
  addButton(id, x, y, w, h, label, bg, fg, action, {
    kind = "row",
    hitbox = { x1 = x, y1 = y, x2 = x + w - 1, y2 = y + h - 1 },
  })
end

local function drawHitboxBox(hit)
  for xx = hit.x1, hit.x2 do
    writeAt(xx, hit.y1, " ", C.warn, colors.brown)
    writeAt(xx, hit.y2, " ", C.warn, colors.brown)
  end
  for yy = hit.y1, hit.y2 do
    writeAt(hit.x1, yy, " ", C.warn, colors.brown)
    writeAt(hit.x2, yy, " ", C.warn, colors.brown)
  end
end

local function drawHitboxLabel(hit)
  local label = shortText(hit.id or "btn", math.max(3, hit.x2 - hit.x1 + 1))
  writeAt(hit.x1, hit.y1, label, C.text, colors.cyan)
end

local function drawHitboxDebugOverlay(source)
  if not state.debugHitboxes then return end
  local bucket = getHitboxBucket(source)
  for _, hit in ipairs(bucket) do
    drawHitboxBox(hit)
    drawHitboxLabel(hit)
  end
end

local function startMonitorSelection()
  state.choosingMonitor = true
  state.monitorList = getMonitorCandidates()
  state.monitorPage = 1
  state.uiDrawn = false
  state.lastAction = "Selection moniteur"
end

local function stopMonitorSelection()
  state.choosingMonitor = false
  state.uiDrawn = false
end

local function selectMonitorByIndex(index)
  local m = state.monitorList[index]
  if not m then return end
  saveSelectedMonitorName(m.name)
  setupMonitor()
  stopMonitorSelection()
  state.lastAction = "Moniteur: " .. m.name
  pushEvent("Monitor changed")
end

local function buildButtons(layout)
  buttons = {}

  if state.choosingMonitor then
    local boxW = clamp(layout.width - 6, 24, 60)
    local x = math.floor((layout.width - boxW) / 2) + 1
    local y0 = layout.top + 4
    for i = 1, 4 do
      local rowY = y0 + (i - 1) * 3
      local rowAction = function() selectMonitorByIndex(i) end
      addRowButton("mrow" .. i, x + 1, rowY, boxW - 2, 2, "", C.panelDark, C.text, rowAction)
      addButton("m" .. i, x + boxW - 8, rowY, 6, 2, tostring(i), C.btnAction, nil, rowAction, { kind = "small" })
    end
    addButton("cancelMon", x + 1, layout.bottom - 4, boxW - 2, 4, "ANNULER", C.bad, nil, function() stopMonitorSelection() end)
    return
  end

  local ctrl = layout.right or layout.left
  local bx = ctrl.x + 2
  local bw = math.max(12, ctrl.w - 4)
  local by = ctrl.y + 10
  local bh = (layout.mode == "compact") and 4 or 5
  local bGap = 2

  local navW = math.max(6, math.floor(bw / 5))
  addButton("viewSup", bx, ctrl.y + 1, navW, 4, "SUP", state.currentView == "supervision" and C.btnOn or C.panelMid, nil, function() state.currentView = "supervision"; pushEvent("View supervision") end)
  addButton("viewDiag", bx + navW, ctrl.y + 1, navW, 4, "DIAG", state.currentView == "diagnostic" and C.btnOn or C.panelMid, nil, function() state.currentView = "diagnostic"; pushEvent("View diagnostic") end)
  addButton("viewMan", bx + (navW * 2), ctrl.y + 1, navW, 4, "MAN", state.currentView == "manual" and C.btnOn or C.panelMid, nil, function() state.currentView = "manual"; pushEvent("View manual") end)
  addButton("viewInd", bx + (navW * 3), ctrl.y + 1, navW, 4, "IND", state.currentView == "induction" and C.btnOn or C.panelMid, nil, function() state.currentView = "induction"; pushEvent("View induction") end)
  addButton("viewUpd", bx + (navW * 4), ctrl.y + 1, bw - (navW * 4), 4, "UPD", state.currentView == "update" and C.btnOn or C.panelMid, nil, function() state.currentView = "update"; pushEvent("View update") end)

  addButton("refreshNow", bx, ctrl.y + 6, bw, 4, "REFRESH", C.btnAction, nil, function()
    refreshAll()
    state.lastAction = "Refresh"
  end)

  if state.currentView == "update" then
    local uY = by
    addButton("updCheck", bx, uY, bw, 4, "CHECK", C.btnAction, nil, function()
      local ok, err = pcall(checkForUpdate)
      if not ok then
        state.update.lastError = tostring(err)
        setUpdateState("FAILED", "Check crashed", "No apply")
        pushEvent("Update failed")
      end
    end)
    addButton("updApply", bx, uY + 5, bw, 4, "UPDATE", state.update.available and C.warn or C.inactive, nil, function()
      local ok, result, err = pcall(performUpdate)
      if not ok then
        state.update.lastError = tostring(result)
        setUpdateState("FAILED", nil, "Update crashed")
        pushEvent("Update failed")
      elseif result == false then
        state.update.lastError = tostring(err or "No update available")
        state.lastAction = "No update"
      end
    end)
    addButton("updDebug", bx, uY + 10, bw, 4, state.debugHitboxes and "DEBUG ON" or "DEBUG OFF", state.debugHitboxes and C.info or C.panelMid, nil, function()
      state.debugHitboxes = not state.debugHitboxes
      state.lastAction = state.debugHitboxes and "Hitbox debug ON" or "Hitbox debug OFF"
      pushEvent(state.lastAction)
    end)
    local splitGap = 1
    local splitW = math.max(8, math.floor((bw - splitGap) / 2))
    addButton("updRollback", bx, uY + 15, splitW, 4, "ROLLBACK", fs.exists(UPDATE_BACKUP_FILE) and C.bad or C.inactive, nil, function()
      local ok, err = pcall(rollbackUpdate)
      if not ok then
        state.update.lastError = tostring(err)
        setUpdateState("FAILED", nil, "Rollback crashed")
        pushEvent("Update failed")
      end
    end)
    addButton("monitor", bx + splitW + splitGap, uY + 15, bw - splitW - splitGap, 4, "MONITOR", C.btnWarn, nil, function() startMonitorSelection() end)
    return
  end

  if state.currentView == "diagnostic" or state.currentView == "induction" then
    drawBigButton("monitor", bx, ctrl.y + 12, bw, "MONITOR", C.btnWarn, function() startMonitorSelection() end)
    return
  end

  if state.currentView == "manual" then
    local mY = by
    drawBigButton("manualStart", bx, mY, bw, "DEMARRAGE", canIgnite() and C.warn or C.inactive, function() startReactorSequence() end)
    drawBigButton("manualStop", bx, mY + 7, bw, "ARRET", C.bad, function() stopReactorSequence("ARRET DEMANDE") end)
    addButton("manualT", bx, mY + 14, bw, 5, "T LOCK", state.tOpen and C.tritium or C.inactive, nil, function() openTritium(not state.tOpen) end)
    addButton("manualDT", bx, mY + 20, bw, 5, "DT LOCK", state.dtOpen and C.dtFuel or C.inactive, nil, function()
      local nextState = not state.dtOpen
      openDTFuel(nextState)
      if nextState then openSeparatedGases(false) end
    end)
    addButton("manualD", bx, mY + 26, bw, 5, "D LOCK", state.dOpen and C.deuterium or C.inactive, nil, function() openDeuterium(not state.dOpen) end)
    addButton("manualPulse", bx, mY + 32, bw, 5, "PULSE LAS", C.warn, nil, function() fireLaser() end)
    addButton("monitor", bx, mY + 38, bw, 4, "MONITOR", C.btnWarn, nil, function() startMonitorSelection() end)
    addButton("manualBack", bx, mY + 43, bw, 4, "RETOUR SUP", C.btnAction, nil, function() state.currentView = "supervision"; pushEvent("View supervision") end)
    return
  end

  addButton("master", bx, by, bw, bh, "MASTER", state.autoMaster and C.btnOn or C.btnOff, nil, function()
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
  end)

  addButton("fusion", bx, by + (bh + bGap), bw, bh, "FUSION", state.fusionAuto and C.btnOn or C.btnOff, nil, function()
    state.fusionAuto = not state.fusionAuto
    state.lastAction = "Toggle FUSION"
  end)

  addButton("charge", bx, by + (bh + bGap) * 2, bw, bh, "CHARGE", state.chargeAuto and C.btnOn or C.btnOff, nil, function()
    state.chargeAuto = not state.chargeAuto
    state.lastAction = "Toggle CHARGE"
  end)

  drawBigButton("demarrage", bx, by + (bh + bGap) * 3, bw, "DEMARRAGE", canIgnite() and C.warn or C.inactive, function() startReactorSequence() end)
  addButton("monitor", bx, by + (bh + bGap) * 3 + 7, bw, 4, "MONITOR", C.btnWarn, nil, function() startMonitorSelection() end)
  addButton("arret", bx, by + (bh + bGap) * 3 + 12, bw, 4, "ARRET", C.bad, nil, function() stopReactorSequence("ARRET DEMANDE") end)

  local center = layout.center
  if center and layout.mode ~= "compact" and state.currentView == "supervision" then
    local innerX = center.x + 2
    local innerW = center.w - 4
    local barY = center.y + center.h - 5
    local btnH = 5
    local gap = 3
    local btnW = math.max(10, math.floor((innerW - (gap * 2)) / 3))
    local totalW = (btnW * 3) + (gap * 2)
    local startX = innerX + math.max(0, math.floor((innerW - totalW) / 2))

    addButton("lock_t", startX, barY, btnW, btnH, "T LOCK", state.tOpen and C.tritium or C.inactive, C.btnText, function()
      openTritium(not state.tOpen)
    end)

    addButton("lock_dt", startX + btnW + gap, barY, btnW, btnH, "DT LOCK", state.dtOpen and C.dtFuel or C.inactive, C.btnText, function()
      local nextState = not state.dtOpen
      openDTFuel(nextState)
      if nextState then openSeparatedGases(false) end
    end)

    addButton("lock_d", startX + (btnW + gap) * 2, barY, btnW, btnH, "D LOCK", state.dOpen and C.deuterium or C.inactive, C.btnText, function()
      openDeuterium(not state.dOpen)
    end)
  end
end

local function getCurrentInputSource()
  return term.current() == nativeTerm and "terminal" or "monitor"
end

local function drawButtons(source)
  clearHitboxes(source)
  for _, b in ipairs(buttons) do
    drawButton(source, b)
  end
  drawHitboxDebugOverlay(source)
end

local function handleClick(x, y, source)
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



local function inductionStatus()
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

local function getInductionFillRatio()
  local pct = clamp(toNumber(state.inductionPct, 0), 0, 100)
  return clamp(pct / 100, 0, 1)
end

local function drawMonitorSelection(layout)
  term.setBackgroundColor(C.bg)
  term.setTextColor(C.text)
  term.clear()
  drawHeader("FUSION SUPERVISOR", "MONITOR LINK")

  local boxW = clamp(layout.width - 6, 26, 60)
  local boxH = clamp(layout.height - 3, 12, layout.height)
  local x = math.floor((layout.width - boxW) / 2) + 1
  local y = layout.top + 1

  drawBox(x, y, boxW, boxH, "SELECTION MONITEUR", C.border)
  writeAt(x + 2, y + 1, "Choisissez une sortie d'affichage", C.dim, C.panelDark)
  writeAt(x + 2, y + 2, "IDX  NOM                      TAILLE", C.info, C.panelDark)

  for i = 1, 4 do
    local yy = y + 3 + (i - 1) * 3
    local m = state.monitorList[i]
    if m and yy + 1 < y + boxH - 2 then
      local row = string.format("[%d]  %-22s %3dx%-3d", i, shortText(m.name, 22), m.w or 0, m.h or 0)
      writeAt(x + 2, yy, shortText(row, boxW - 4), C.text, C.panelDark)
      writeAt(x + 2, yy + 1, "TAP / TOUCHE " .. i .. " pour selectionner", C.dim, C.panelDark)
    end
  end

  buildButtons(layout)
  drawButtons(getCurrentInputSource())
  drawFooter(layout)
end

local function drawIoPanel(x, y, w, h)
  if h < 4 then return end
  drawBox(x, y, w, h, "REAL I/O BUS", C.border)
  local rx = x + 2
  local ry = y + 1
  local maxY = y + h - 2
  writeAt(rx, ry, "OUT", C.info, C.panelDark)
  if ry + 1 <= maxY then drawKeyValue(rx, ry + 1, "LAS", yesno(state.laserLineOn), C.dim, state.laserLineOn and C.ok or C.warn, w - 6) end
  if ry + 2 <= maxY then drawKeyValue(rx, ry + 2, "T", yesno(state.tOpen), C.dim, state.tOpen and C.tritium or C.warn, w - 6) end
  if ry + 3 <= maxY then drawKeyValue(rx, ry + 3, "D", yesno(state.dOpen), C.dim, state.dOpen and C.deuterium or C.warn, w - 6) end
  if ry + 4 <= maxY then drawKeyValue(rx, ry + 4, "DT", yesno(state.dtOpen), C.dim, state.dtOpen and C.dtFuel or C.warn, w - 6) end

  if ry + 5 <= maxY then writeAt(rx, ry + 5, "SENSE", C.info, C.panelDark) end
  if ry + 6 <= maxY then drawKeyValue(rx, ry + 6, "R-T", hw.readerRoles.tritium and "OK" or "FAIL", C.dim, hw.readerRoles.tritium and C.ok or C.bad, w - 6) end
  if ry + 7 <= maxY then drawKeyValue(rx, ry + 7, "R-D", hw.readerRoles.deuterium and "OK" or "FAIL", C.dim, hw.readerRoles.deuterium and C.ok or C.bad, w - 6) end
  if ry + 8 <= maxY then drawKeyValue(rx, ry + 8, "R-AUX", hw.readerRoles.inventory and "OK" or "FAIL", C.dim, hw.readerRoles.inventory and C.ok or C.bad, w - 6) end

end

local function drawStatusPanel(panel)
  drawBox(panel.x, panel.y, panel.w, panel.h, "SUPERVISION CORE", C.border)
  local x = panel.x + 1
  local y = panel.y + 1
  local w = panel.w - 2

  local b1h = clamp(math.floor(panel.h * 0.23), 5, 7)
  local b2h = clamp(math.floor(panel.h * 0.22), 5, 7)
  local b3h = clamp(math.floor(panel.h * 0.26), 6, 8)
  local b4h = panel.h - b1h - b2h - b3h - 3

  drawBox(x, y, w, b1h, "PHASE", C.borderDim)
  local phase = reactorPhase()
  drawBadge(x + 2, y + 1, "STATE", phase, phaseColor(phase))
  drawBadge(x + 2, y + 2, "CORE", state.reactorPresent and (state.reactorFormed and "FORMED" or "UNFORMED") or "OFFLINE")
  if b1h > 5 then drawKeyValue(x + 2, y + 3, "Temp P", fmt(state.plasmaTemp), C.dim, C.info, w - 6) end

  local y2 = y + b1h
  if state.ignition then
    drawBox(x, y2, w, b2h, "RUNTIME FUEL", C.borderDim)
    local mode = getRuntimeFuelMode()
    local flowOk = isRuntimeFuelOk()
    local rows = {
      { "Fuel Mode", mode, mode == "STARVED" and C.bad or C.ok },
      { "Fuel Flow", flowOk and "OK" or "NO FLOW", flowOk and C.ok or C.bad },
      { "D Line", state.dOpen and "OPEN" or "CLOSED", state.dOpen and C.deuterium or C.warn },
      { "T Line", state.tOpen and "OPEN" or "CLOSED", state.tOpen and C.tritium or C.warn },
      { "DT Line", state.dtOpen and "OPEN" or "CLOSED", state.dtOpen and C.dtFuel or C.warn },
    }
    for i = 1, math.min(#rows, b2h - 2) do
      local r = rows[i]
      drawKeyValue(x + 2, y2 + i, r[1], r[2], C.dim, r[3], w - 6)
    end
  else
    drawBox(x, y2, w, b2h, "IGNITION CHECK", C.borderDim)
    local checklist = state.ignitionChecklist or {}
    for i = 1, math.min(#checklist, b2h - 2) do
      local item = checklist[i]
      local tone = item.ok and C.ok or (item.wait and C.warn or C.bad)
      local mark = item.ok and "[OK]" or (item.wait and "[...]" or "[NO]")
      writeAt(x + 2, y2 + i, shortText(mark .. " " .. item.key, w - 4), tone, C.panelDark)
    end
  end

  local y3 = y2 + b2h
  drawBox(x, y3, w, b3h, "SAFETY", C.borderDim)
  local warnings = state.safetyWarnings or {}
  if #warnings == 0 then
    writeAt(x + 2, y3 + 1, "NO CRITICAL WARNING", C.ok, C.panelDark)
  else
    for i = 1, math.min(#warnings, b3h - 2) do
      local blink = (state.tick % 6 < 3)
      local tone = (i == 1 and blink) and C.bad or C.warn
      writeAt(x + 2, y3 + i, shortText("- " .. warnings[i], w - 4), tone, C.panelDark)
    end
  end

  local y4 = y3 + b3h
  drawBox(x, y4, w, b4h, "EVENT LOG", C.borderDim)
  local logs = state.eventLog or {}
  for i = 1, math.min(#logs, b4h - 2) do
    writeAt(x + 2, y4 + i, shortText(logs[i], w - 4), C.info, C.panelDark)
  end
end
local function drawControlPanel(panel, layout)
  drawBox(panel.x, panel.y, panel.w, panel.h, state.currentView == "manual" and "MANUAL COMMAND" or (state.currentView == "update" and "UPDATE COMMAND" or "CONTROL COLUMN"), C.border)
  local x = panel.x + 1
  local w = panel.w - 2

  local autoH = clamp(math.floor(panel.h * 0.24), 6, 8)
  local actionH = clamp(math.floor(panel.h * 0.34), 8, 12)
  local ioH = panel.h - autoH - actionH - 2

  drawBox(x, panel.y + 1, w, autoH, "AUTO", C.borderDim)
  local sx = x + 2
  drawBadge(sx, panel.y + 2, "MASTER", state.autoMaster and "AUTO" or "MANUAL")
  drawBadge(sx, panel.y + 3, "FUSION", state.fusionAuto and "AUTO" or "MANUAL")
  drawBadge(sx, panel.y + 4, "CHARGE", state.chargeAuto and "AUTO" or "MANUAL")
  drawBadge(sx, panel.y + 5, "GAS", state.gasAuto and "AUTO" or "MANUAL")

  local yAction = panel.y + 1 + autoH
  drawBox(x, yAction, w, actionH, "ACTIONS", C.borderDim)

  buildButtons(layout)
  drawButtons(getCurrentInputSource())

  local yIo = yAction + actionH
  drawIoPanel(x, yIo, w, ioH)
end

local function drawDiagnosticView(layout)
  local left = layout.left
  local center = layout.center
  drawStatusPanel(left)
  if not center then
    drawControlPanel(layout.right, layout)
    return
  end

  drawBox(center.x, center.y, center.w, center.h, "DIAGNOSTIC GRID", C.border)
  local x = center.x + 2
  local y = center.y + 1
  local maxY = center.y + center.h - 2
  writeAt(x, y, "RESOLVED DEVICES", C.info, C.panelDark)

  local rows = {
    {"Reactor", hw.reactorName or "FAIL", hw.reactor ~= nil, "Fusion core control"},
    {"Logic Adapter", hw.logicName or "FAIL", hw.logic ~= nil, "Ignition and injection status"},
    {"Laser", hw.laserName or "FAIL", hw.laser ~= nil, "Ignition beam source"},
    {"Induction Matrix", hw.inductionName or "FAIL", hw.induction ~= nil, "Battery / power buffer"},
    {"Relay LAS", CFG.actions.laser_charge.relay .. "." .. CFG.actions.laser_charge.side, hw.relays[CFG.actions.laser_charge.relay] ~= nil, "Laser charge and fire line"},
    {"Relay T", CFG.actions.tritium.relay .. "." .. CFG.actions.tritium.side, hw.relays[CFG.actions.tritium.relay] ~= nil, "Tritium valve line"},
    {"Relay D", CFG.actions.deuterium.relay .. "." .. CFG.actions.deuterium.side, hw.relays[CFG.actions.deuterium.relay] ~= nil, "Deuterium valve line"},
    {"Reader T", hw.readerRoles.tritium and hw.readerRoles.tritium.name or "FAIL", hw.readerRoles.tritium ~= nil, "Tritium tank read"},
    {"Reader D", hw.readerRoles.deuterium and hw.readerRoles.deuterium.name or "FAIL", hw.readerRoles.deuterium ~= nil, "Deuterium tank read"},
    {"Reader Aux", hw.readerRoles.inventory and hw.readerRoles.inventory.name or "FAIL", hw.readerRoles.inventory ~= nil, "Auxiliary inventory / feed"},
    {"Monitor", hw.monitorName or "term", hw.monitorName ~= nil, "Touch interface"},
  }

  local rowStep = 2
  for i, row in ipairs(rows) do
    local yy = y + ((i - 1) * rowStep) + 1
    if yy + 1 <= maxY then
      local tone = row[3] and C.ok or C.bad
      local head = string.format("%s | %s", row[2], row[3] and "OK" or "FAIL")
      drawKeyValue(x, yy, row[1], shortText(head, 16), C.dim, tone, center.w - 6)
      writeAt(x + 1, yy + 1, shortText("role: " .. row[4], center.w - 8), C.info, C.panelDark)
    end
  end

  drawControlPanel(layout.right or layout.left, layout)
end

local function inductionFillTone(status, pulse)
  if status == "CHARGING" then return pulse and C.info or C.energy end
  if status == "DISCHARGING" then return pulse and C.warn or C.energy end
  if status == "LOW" or status == "EMPTY" then return pulse and C.bad or C.warn end
  if status == "FULL" then return pulse and C.ok or C.info end
  return C.energy
end

local function inductionDiagramGeometry(x, y, w, h)
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

local function drawInductionProfileBase(geo)
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

local function drawInductionProfileFill(geo, status, pulse, fillTone)
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

local function drawInductionProfileDecor(geo, status)
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

local function drawInductionDiagramInfo(x, y, w, h, geo, status, tone)
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

local function drawInductionDiagram(x, y, w, h)
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

local function drawInductionView(layout)
  local istat, statusTone = inductionStatus()
  local left = layout.left
  drawBox(left.x, left.y, left.w, left.h, "INDUCTION MATRIX", C.border)
  local x = left.x + 2
  local y = left.y + 2

  drawKeyValue(x, y, "Online", state.inductionPresent and "ONLINE" or "OFFLINE", C.dim, state.inductionPresent and C.ok or C.bad, left.w - 6)
  drawKeyValue(x, y + 1, "Formed", state.inductionFormed and "FORMED" or "UNFORMED", C.dim, state.inductionFormed and C.ok or C.warn, left.w - 6)
  drawKeyValue(x, y + 2, "Global", istat, C.dim, statusTone, left.w - 6)

  drawBox(x - 1, y + 4, left.w - 4, 9, "TECHNICAL", C.borderDim)
  drawKeyValue(x, y + 5, "Stored", formatMJ(state.inductionEnergy), C.dim, C.energy, left.w - 6)
  drawKeyValue(x, y + 6, "Max", formatMJ(state.inductionMax), C.dim, C.energy, left.w - 6)
  drawKeyValue(x, y + 7, "Fill %", string.format("%.1f%%", state.inductionPct), C.dim, C.energy, left.w - 6)
  drawKeyValue(x, y + 8, "Needed", formatMJ(state.inductionNeeded), C.dim, C.dim, left.w - 6)
  drawKeyValue(x, y + 9, "Transfer Cap", formatMJ(state.inductionTransferCap), C.dim, C.info, left.w - 6)
  drawKeyValue(x, y + 10, "Last In", formatMJ(state.inductionInput), C.dim, C.ok, left.w - 6)
  drawKeyValue(x, y + 11, "Last Out", formatMJ(state.inductionOutput), C.dim, C.warn, left.w - 6)

  drawBox(x - 1, y + 13, left.w - 4, 6, "STRUCTURE", C.borderDim)
  drawKeyValue(x, y + 14, "Cells", tostring(state.inductionCells), C.dim, C.info, left.w - 6)
  drawKeyValue(x, y + 15, "Providers", tostring(state.inductionProviders), C.dim, C.info, left.w - 6)
  drawKeyValue(x, y + 16, "Dimensions", string.format("%dx%dx%d", state.inductionLength, state.inductionWidth, state.inductionHeight), C.dim, C.text, left.w - 6)
  drawKeyValue(x, y + 17, "Port Mode", state.inductionPortMode, C.dim, C.info, left.w - 6)

  if layout.center then
    drawInductionDiagram(layout.center.x, layout.center.y, layout.center.w, layout.center.h)
    drawControlPanel(layout.right or layout.left, layout)
  else
    local right = layout.right
    drawInductionDiagram(right.x, right.y, right.w, right.h)
  end
end

local function drawManualView(layout)
  if layout.center then
    drawReactorDiagram(layout.center.x, layout.center.y, layout.center.w, layout.center.h)
  end
  drawStatusPanel(layout.left)
  drawControlPanel(layout.right or layout.left, layout)
end

local function drawSupervisionView(layout)
  if layout.mode == "compact" then
    drawStatusPanel(layout.left)
    drawControlPanel(layout.right, layout)
    return
  end
  drawStatusPanel(layout.left)
  drawReactorDiagram(layout.center.x, layout.center.y, layout.center.w, layout.center.h)
  drawControlPanel(layout.right, layout)
end

local function drawUpdateView(layout)
  local infoPanel
  local controlPanel

  if layout.center then
    drawStatusPanel(layout.left)
    infoPanel = layout.center
    controlPanel = layout.right or layout.left
  else
    infoPanel = layout.left
    controlPanel = layout.right or layout.left
  end

  drawBox(infoPanel.x, infoPanel.y, infoPanel.w, infoPanel.h, "UPDATE CENTER", C.info)
  local x = infoPanel.x + 2
  local w = infoPanel.w - 4

  drawBox(x - 1, infoPanel.y + 1, w, 6, "VERSIONS", C.borderDim)
  drawKeyValue(x, infoPanel.y + 2, "Local", state.update.localVersion, C.dim, C.ok, w - 4)
  drawKeyValue(x, infoPanel.y + 3, "Remote", state.update.remoteVersion, C.dim, C.info, w - 4)
  drawKeyValue(x, infoPanel.y + 4, "Status", state.update.status, C.dim, statusColor(state.update.available and "WARN" or "OK"), w - 4)

  drawBox(x - 1, infoPanel.y + 7, w, 6, "NETWORK", C.borderDim)
  drawKeyValue(x, infoPanel.y + 8, "HTTP", state.update.httpStatus, C.dim, state.update.httpStatus == "OK" and C.ok or C.warn, w - 4)
  drawKeyValue(x, infoPanel.y + 9, "Enabled", UPDATE_ENABLED and "YES" or "NO", C.dim, UPDATE_ENABLED and C.ok or C.bad, w - 4)
  drawKeyValue(x, infoPanel.y + 10, "Error", state.update.lastError ~= "" and state.update.lastError or "None", C.dim, state.update.lastError ~= "" and C.bad or C.info, w - 4)

  local resultY = infoPanel.y + 13
  local resultH = math.max(9, infoPanel.h - 14)
  drawBox(x - 1, resultY, w, resultH, "RESULT", C.borderDim)
  writeAt(x, resultY + 1, shortText("Check: " .. tostring(state.update.lastCheckResult or "Never"), w - 3), C.info, C.panelDark)
  writeAt(x, resultY + 2, shortText("Apply: " .. tostring(state.update.lastApplyResult or "Never"), w - 3), C.info, C.panelDark)
  writeAt(x, resultY + 3, shortText("Backup LUA: " .. (fs.exists(UPDATE_BACKUP_FILE) and "AVAILABLE" or "MISSING"), w - 3), C.dim, C.panelDark)
  writeAt(x, resultY + 4, shortText("Backup VER: " .. (fs.exists(UPDATE_VERSION_BACKUP_FILE) and "AVAILABLE" or "MISSING"), w - 3), C.dim, C.panelDark)
  writeAt(x, resultY + 5, shortText("Temp LUA: " .. (fs.exists(UPDATE_TEMP_FILE) and "READY" or "EMPTY"), w - 3), C.dim, C.panelDark)
  writeAt(x, resultY + 6, shortText("Temp VER: " .. (fs.exists(UPDATE_TEMP_VERSION_FILE) and "READY" or "EMPTY"), w - 3), C.dim, C.panelDark)
  writeAt(x, resultY + 7, shortText("Restart: " .. (state.update.restartRequired and "REQUIRED" or "NOT REQUIRED"), w - 3), state.update.restartRequired and C.warn or C.ok, C.panelDark)

  drawControlPanel(controlPanel, layout)
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
  else
    drawSupervisionView(layout)
  end

  drawFooter(layout)
  state.uiDrawn = true
end

local configOk = ensureConfigOrInstaller()
if not configOk then
  restoreTerm()
  return
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

while state.running do
  refreshAll()
  fullAuto()
  drawUI()

  local timer = os.startTimer(CFG.refreshDelay)
  local ev, p1, p2, p3 = os.pullEvent()

  if ev == "char" then
    local ch = string.lower(p1)

    if state.choosingMonitor then
      if ch == "1" then selectMonitorByIndex(1)
      elseif ch == "2" then selectMonitorByIndex(2)
      elseif ch == "3" then selectMonitorByIndex(3)
      elseif ch == "4" then selectMonitorByIndex(4)
      elseif ch == "q" or ch == "x" then stopMonitorSelection()
      end
    else
      if ch == "q" then
        state.running = false
      elseif ch == "a" then
        state.autoMaster = not state.autoMaster
        if not state.autoMaster then
          openDTFuel(false)
          openSeparatedGases(false)
          setLaserCharge(false)
          state.ignitionSequencePending = false
        end
      elseif ch == "z" then
        state.chargeAuto = not state.chargeAuto
      elseif ch == "f" then
        state.fusionAuto = not state.fusionAuto
      elseif ch == "g" then
        state.gasAuto = not state.gasAuto
      elseif ch == "m" then
        startMonitorSelection()
      elseif ch == "1" then
        state.currentView = "supervision"
        pushEvent("View supervision")
      elseif ch == "2" then
        state.currentView = "diagnostic"
        pushEvent("View diagnostic")
      elseif ch == "3" then
        state.currentView = "manual"
        pushEvent("View manual")
      elseif ch == "4" then
        state.currentView = "induction"
        pushEvent("View induction")
      elseif ch == "5" then
        state.currentView = "update"
        pushEvent("View update")
      elseif ch == "i" then
        triggerAutomaticIgnitionSequence()
      elseif ch == "l" then
        fireLaser()
      elseif ch == "o" then
        openDTFuel(true)
      elseif ch == "p" then
        openDTFuel(false)
      end
    end

  elseif ev == "mouse_click" then
    local _, x, y = p1, p2, p3
    handleClick(x, y, "terminal")

  elseif ev == "monitor_touch" then
    local mon, x, y = p1, p2, p3
    if mon == hw.monitorName then
      handleClick(x, y, "monitor")
    end

  elseif ev == "monitor_resize" or ev == "term_resize" then
    setupMonitor()
    state.uiDrawn = false

  elseif ev == "peripheral" or ev == "peripheral_detach" then
    setupMonitor()
    state.uiDrawn = false
    if state.choosingMonitor then
      state.monitorList = getMonitorCandidates()
    end

  elseif ev == "timer" and p1 == timer then
  end
end

restoreTerm()
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)

print("Programme termine.")
