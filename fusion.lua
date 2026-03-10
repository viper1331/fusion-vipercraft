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
    laser_charge = { relay = "redstone_relay_0", side = "top",   label = "Charge Laser" },
    deuterium    = { relay = "redstone_relay_1", side = "front", label = "Tank Deuterium" },
    tritium      = { relay = "redstone_relay_2", side = "front", label = "Tank Tritium" },
  },

  -- Mapping des actions redstone
  actions = {
    laser_charge = { relay = "redstone_relay_0", side = "top",   analog = 15, pulse = false },
    deuterium    = { relay = "redstone_relay_1", side = "front", analog = 15, pulse = false },
    tritium      = { relay = "redstone_relay_2", side = "front", analog = 15, pulse = false },

    laser_fire   = nil,
    hohlraum     = nil,
    dt_fuel      = nil,
  },
}

local CONFIG_FILE = "fusion_monitor.cfg"

local nativeTerm = term.current()
local buttons = {}

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

  tick = 0,
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

local C = {
  bg = colors.black,
  panel = colors.gray,
  panelDark = colors.black,
  panelMid = colors.lightGray,
  text = colors.white,
  dim = colors.lightGray,
  ok = colors.lime,
  warn = colors.orange,
  bad = colors.red,
  info = colors.cyan,
  border = colors.lightBlue,
  borderDim = colors.gray,
  energy = colors.yellow,
  fuel = colors.orange,
  headerBg = colors.blue,
  footerBg = colors.gray,
  headerText = colors.white,
  btnOn = colors.green,
  btnOff = colors.red,
  btnAction = colors.blue,
  btnWarn = colors.orange,
  btnText = colors.white,
}

local function centerText(y, text, tc, bc)
  local w, _ = term.getSize()

  if bc then
    term.setBackgroundColor(bc)
    term.setCursorPos(1, y)
    term.write(string.rep(" ", w))
  end

  local x = math.floor((w - #text) / 2) + 1
  if tc then term.setTextColor(tc) end
  if bc then term.setBackgroundColor(bc) end
  term.setCursorPos(x, y)
  term.write(text)
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
  if n >= 1000000000 then
    return string.format("%.2fG", n / 1000000000)
  elseif n >= 1000000 then
    return string.format("%.2fM", n / 1000000)
  elseif n >= 1000 then
    return string.format("%.2fk", n / 1000)
  else
    return tostring(math.floor(n))
  end
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
  if bc then term.setBackgroundColor(bc) end
  if tc then term.setTextColor(tc) end
  term.setCursorPos(x, y)
  term.write(txt)
end

local function fillArea(x, y, w, h, bg)
  term.setBackgroundColor(bg or C.bg)
  for yy = y, y + h - 1 do
    term.setCursorPos(x, yy)
    term.write(string.rep(" ", w))
  end
end

local function fillLine(y, bg)
  local w = term.getSize()
  term.setBackgroundColor(bg)
  term.setCursorPos(1, y)
  term.write(string.rep(" ", w))
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
  accent = accent or C.border
  fillArea(x, y, w, h, C.panelDark)
  if w < 2 or h < 2 then return end
  writeAt(x, y, string.rep(" ", w), C.text, accent)
  writeAt(x, y + h - 1, string.rep("-", w), accent, C.panelDark)
  for yy = y + 1, y + h - 2 do
    writeAt(x, yy, " ", C.text, accent)
    writeAt(x + w - 1, yy, " ", C.text, accent)
  end

  if title and #title > 0 and w > 6 then
    writeAt(x + 2, y, shortText(title, w - 4), C.text, accent)
  end
end

local function reactorPhase()
  if state.alert == "DANGER" then return "SAFE STOP" end
  if not state.reactorPresent then return "OFFLINE" end
  if not state.reactorFormed then return "UNFORMED" end
  if state.ignition and state.dtOpen then return "RUNNING" end
  if state.ignition then return "IGNITED" end
  if state.ignitionSequencePending then return "IGNITING" end
  if state.laserChargeOn or state.laserLineOn then return "CHARGING" end

  local threshold = toNumber(CFG and CFG.ignitionLaserEnergyThreshold, 0)
  local laserEnergy = toNumber(state.laserEnergy, 0)
  if laserEnergy >= threshold and threshold > 0 then return "READY" end

  return "READY"
end

local function phaseColor(phase)
  if phase == "RUNNING" or phase == "IGNITED" then return C.ok end
  if phase == "READY" then return C.info end
  if phase == "CHARGING" or phase == "IGNITING" then return C.warn end
  if phase == "SAFE STOP" or phase == "OFFLINE" or phase == "UNFORMED" then return C.bad end
  return C.dim
end

local function computeSafetyWarnings()
  local warnings = {}
  local critical = false
  if not state.reactorPresent then table.insert(warnings, "REACTOR ABSENT") critical = true end
  if state.reactorPresent and not state.reactorFormed then table.insert(warnings, "UNFORMED") end
  if not hw.readerRoles.deuterium or not hw.readerRoles.tritium then table.insert(warnings, "FUEL SENSOR FAIL") end
  if not hw.relays[CFG.actions.laser_charge.relay] or not hw.relays[CFG.actions.deuterium.relay] or not hw.relays[CFG.actions.tritium.relay] then
    table.insert(warnings, "CONTROL LINE FAIL")
    critical = true
  end
  if (state.laserChargeOn or state.laserLineOn) and (not state.reactorFormed or state.ignition) then table.insert(warnings, "SAFETY HOLD") end
  if state.dOpen and state.tOpen and state.dtOpen then table.insert(warnings, "UNSAFE STATE") end
  if #hw.readerRoles.unknown > 0 then table.insert(warnings, "FALLBACK DETECTION") end
  return warnings, critical
end

local function drawHeader(title, status)
  local tw = term.getSize()
  local heartbeat = (state.tick % 8 < 4) and "●" or "○"
  local phase = reactorPhase()
  fillLine(1, colors.gray)
  writeAt(2, 1, shortText(title .. " [" .. string.upper(state.currentView:sub(1, 1)) .. "]", math.max(10, tw - 40)), C.headerText, colors.gray)
  local centerTxt = "PHASE " .. shortText(phase, 16)
  local cx = math.max(2, math.floor((tw - #centerTxt) / 2))
  writeAt(cx, 1, centerTxt, phaseColor(phase), colors.gray)
  local statusTxt = shortText(status or "N/A", 16)
  local rightTxt = heartbeat .. " ALERT " .. statusTxt
  local sx = math.max(2, tw - #rightTxt - 2)
  writeAt(sx, 1, rightTxt, statusColor(state.alert), colors.gray)
end

local function drawFooter(layout)
  local tw, th = term.getSize()
  fillLine(th, colors.gray)
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
    writeAt(sx, th, content, item[3], colors.gray)
    if i < #labels and sx + segW - 1 <= tw then writeAt(sx + segW - 1, th, "|", C.panelMid, colors.gray) end
  end
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
  local gw = clamp(maxGw, 15, 21)
  if gw % 2 == 0 then gw = gw - 1 end
  local gh = clamp(innerH - 4, 13, 17)
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

      if math.max(dx, dy) <= 4 then layer = 1 end
      if math.max(dx, dy) <= 3 then layer = 2 end
      if dx <= 1 and dy <= 6 then layer = math.max(layer, 1) end
      if dy <= 1 and dx <= 6 then layer = math.max(layer, 1) end
      if dx <= 0 and dy <= 5 then layer = math.max(layer, 2) end
      if dy <= 0 and dx <= 5 then layer = math.max(layer, 2) end
      if dx == 4 and dy == 4 then layer = 0 end
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

  for i = -4, 4 do
    drawCell(gcx + i, gcy, spineColor)
    drawCell(gcx, gcy + i, spineColor)
  end

  drawCell(gcx, gcy, coreColor, state.ignition and (pulse and "**" or "##") or (state.ignitionSequencePending and (blink and "!!" or "::") or "[]"), C.text)

  local laserOn = state.laserChargeOn or state.laserLineOn or state.ignitionSequencePending
  local laserTone = laserOn and C.warn or C.dim
  local dTone = state.dOpen and C.ok or C.dim
  local tTone = state.tOpen and C.ok or C.dim
  local dtTone = state.dtOpen and C.fuel or C.dim

  local conduitTone = C.borderDim
  if state.alert == "WARN" then conduitTone = C.warn end
  if state.alert == "DANGER" then conduitTone = C.bad end

  local laserPathTone = laserOn and C.warn or conduitTone
  local tPathTone = state.tOpen and C.ok or conduitTone
  local dPathTone = state.dOpen and C.ok or conduitTone

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

  for gyLine = gcy + 2, gcy + 5 do
    drawCell(gcx - 4, gyLine, tPathTone)
    drawCell(gcx + 4, gyLine, dPathTone)
  end
  for gxLine = gcx - 3, gcx - 1 do
    drawCell(gxLine, gcy + 2, tPathTone)
  end
  for gxLine = gcx + 1, gcx + 3 do
    drawCell(gxLine, gcy + 2, dPathTone)
  end

  drawCell(gcx - 4, gcy + 5, tPathTone, state.tOpen and (blink and "<<" or "TT") or "T ", C.text)
  drawCell(gcx + 4, gcy + 5, dPathTone, state.dOpen and (blink and ">>" or "DD") or "D ", C.text)

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
  end

  local tdModuleY = math.min(y + h - 3, ry + gh + 1)
  if tdModuleY <= y + h - 2 then
    local tMx = rx
    local dMx = rx + gw * cellW - 6
    writeAt(tMx, tdModuleY, " TANK T", state.tOpen and C.text or C.dim, state.tOpen and C.ok or C.panelMid)
    writeAt(dMx, tdModuleY, " TANK D", state.dOpen and C.text or C.dim, state.dOpen and C.ok or C.panelMid)
  end

  local statusTxt = state.reactorPresent and (state.reactorFormed and "FORMED" or "UNFORMED") or "ABSENT"
  local ignTxt = state.ignition and "IGNITED" or (state.ignitionSequencePending and "IGN PEND" or "IDLE")
  local gridTxt = state.energyKnown and string.format("GRID %3.0f%%", state.energyPct) or "GRID N/A"

  writeAt(x + 2, y + 2, shortText("CORE " .. statusTxt, math.max(8, math.floor(w * 0.33))), state.reactorPresent and C.info or C.bad, C.panelDark)
  writeAt(x + 2, y + h - 2, shortText("PHASE " .. phase .. " | " .. ignTxt, math.max(10, math.floor(w * 0.58))), statusColor(state.alert), C.panelDark)
  writeAt(x + math.floor(w * 0.62), y + h - 2, shortText(gridTxt, math.max(8, w - math.floor(w * 0.62) - 2)), C.energy, C.panelDark)
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
  if not fs.exists(CONFIG_FILE) then return nil end
  local h = fs.open(CONFIG_FILE, "r")
  if not h then return nil end
  local name = h.readLine()
  h.close()
  return name
end

local function saveSelectedMonitorName(name)
  local h = fs.open(CONFIG_FILE, "w")
  if not h then return end
  h.writeLine(name or "")
  h.close()
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
  if relayWrite("laser_charge", on) then
    state.laserChargeOn = on
    state.lastAction = on and "Charge laser ON" or "Charge laser OFF"
  else
    state.laserChargeOn = false
  end
end

local function fireLaser()
  if CFG.actions.laser_fire and relayWrite("laser_fire", true) then
    state.lastAction = "Pulse laser"
  else
    state.lastAction = "Laser pulse non cable"
  end
end

local function injectHohlraum()
  if CFG.actions.hohlraum and relayWrite("hohlraum", true) then
    state.lastAction = "Injection hohlraum"
  else
    state.lastAction = "Ligne hohlraum non cablee"
  end
end

local function openDTFuel(on)
  if CFG.actions.dt_fuel then
    relayWrite("dt_fuel", on)
  end
  state.dtOpen = on
  state.lastAction = on and "D-T Fuel ouvert" or "D-T Fuel ferme"
end

local function openDeuterium(on)
  if CFG.actions.deuterium then
    relayWrite("deuterium", on)
  end
  state.dOpen = on
end

local function openTritium(on)
  if CFG.actions.tritium then
    relayWrite("tritium", on)
  end
  state.tOpen = on
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

local function readEnergy()
  state.energyPresent = hw.induction ~= nil
  state.energyKnown = false
  state.energyStored = 0
  state.energyMax = 1
  state.energyPct = 0

  if hw.induction then
    local okS, s = tryMethods(hw.induction, { "getEnergy", "getEnergyStored", "getStoredEnergy" })
    local okM, m = tryMethods(hw.induction, { "getMaxEnergy", "getMaxEnergyStored", "getEnergyCapacity" })

    if okS or okM then
      state.energyKnown = true
      state.energyStored = toNumber(s, 0)
      state.energyMax = math.max(1, toNumber(m, 1))
      state.energyPct = clamp((state.energyStored * 100) / state.energyMax, 0, 100)
    end
  end
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
  scanPeripherals()
  scanBlockReaders()
  readLaser()
  readReactor()
  readEnergy()
  readReaders()
  state.tick = (state.tick or 0) + 1
end

local function updateAlerts()
  local warnings, critical = computeSafetyWarnings()
  state.safetyWarnings = warnings
  if critical then
    state.alert = "DANGER"
  elseif #warnings > 0 or (state.energyKnown and state.energyPct <= CFG.energyLowPct) then
    state.alert = "WARN"
  elseif state.ignition then
    state.alert = "OK"
  else
    state.alert = "INFO"
  end
end

local function triggerAutomaticIgnitionSequence()
  if state.ignitionSequencePending then
    state.status = "Ignition en attente"
    return
  end

  if not state.reactorFormed then
    state.status = "Reacteur non forme"
    return
  end

  if state.laserEnergy < CFG.ignitionLaserEnergyThreshold then
    state.status = "Laser insuffisant"
    state.lastAction = "Ignition refusee"
    return
  end

  state.ignitionSequencePending = true
  state.lastIgnitionAttempt = os.clock()

  openDTFuel(false)
  openSeparatedGases(true)
  injectHohlraum()
  sleep(0.15)
  fireLaser()

  state.status = "Ignition auto"
  state.lastAction = "Laser > 2.0G -> tanks + hohlraum + pulse"
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
    state.status = "Reacteur non forme"
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
      state.status = "Regime nominal"
    end
  else
    if not state.ignition and not state.ignitionSequencePending and state.laserEnergy >= CFG.ignitionLaserEnergyThreshold then
      triggerAutomaticIgnitionSequence()
    else
      state.status = state.ignitionSequencePending and "Ignition en attente" or "Mode auto"
    end
  end
end

local function autoGasSanity()
  if not state.gasAuto then return end
  if state.dtOpen and (state.dOpen or state.tOpen) then
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

local function addButton(id, x, y, w, h, label, bg, fg, action)
  buttons[id] = { x = x, y = y, w = w, h = h or 1, label = label, bg = bg, fg = fg or C.btnText, action = action }
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
end

local function buildButtons(layout)
  buttons = {}

  if state.choosingMonitor then
    local boxW = clamp(layout.width - 6, 24, 60)
    local x = math.floor((layout.width - boxW) / 2) + 1
    local y0 = layout.top + 3
    for i = 1, 4 do
      addButton("m" .. i, x + 1, y0 + (i - 1) * 3, boxW - 2, 2, tostring(i), C.btnAction, nil, function() selectMonitorByIndex(i) end)
    end
    addButton("cancelMon", x + 1, layout.bottom - 2, boxW - 2, 2, "ANNULER", C.bad, nil, function() stopMonitorSelection() end)
    return
  end

  local ctrl = layout.right or layout.left
  local bx = ctrl.x + 2
  local bw = math.max(10, ctrl.w - 4)
  local by = ctrl.y + 8
  local bh = (layout.mode == "compact") and 1 or 2

  addButton("viewSup", bx, ctrl.y + 1, math.max(8, math.floor(bw / 3)), 1, "SUP", state.currentView == "supervision" and C.btnOn or C.panelMid, nil, function() state.currentView = "supervision" end)
  addButton("viewDiag", bx + math.max(8, math.floor(bw / 3)), ctrl.y + 1, math.max(8, math.floor(bw / 3)), 1, "DIAG", state.currentView == "diagnostic" and C.btnOn or C.panelMid, nil, function() state.currentView = "diagnostic" end)
  addButton("viewMan", bx + (math.max(8, math.floor(bw / 3)) * 2), ctrl.y + 1, bw - (math.max(8, math.floor(bw / 3)) * 2), 1, "MAN", state.currentView == "manual" and C.btnOn or C.panelMid, nil, function() state.currentView = "manual" end)

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

  addButton("fusion", bx, by + bh, bw, bh, "FUSION", state.fusionAuto and C.btnOn or C.btnOff, nil, function()
    state.fusionAuto = not state.fusionAuto
    state.lastAction = "Toggle FUSION"
  end)

  addButton("charge", bx, by + bh * 2, bw, bh, "CHARGE", state.chargeAuto and C.btnOn or C.btnOff, nil, function()
    state.chargeAuto = not state.chargeAuto
    state.lastAction = "Toggle CHARGE"
  end)

  addButton("ignite", bx, by + bh * 3, bw, bh, "IGNITE", C.btnAction, nil, function() triggerAutomaticIgnitionSequence() end)
  addButton("monitor", bx, by + bh * 4, bw, 1, "MONITOR", C.btnWarn, nil, function() startMonitorSelection() end)
  addButton("stop", bx, by + bh * 4 + 1, bw, 1, "E-STOP", C.bad, nil, function() hardStop("EMERGENCY STOP") end)

  if state.currentView == "manual" then
    addButton("manualLaser", bx, by + bh * 5 + 1, bw, 1, "LAS OUT " .. yesno(state.laserChargeOn), state.laserChargeOn and C.btnOn or C.btnOff, nil, function() setLaserCharge(not state.laserChargeOn) end)
    addButton("manualT", bx, by + bh * 5 + 2, bw, 1, "T OUT " .. yesno(state.tOpen), state.tOpen and C.btnOn or C.btnOff, nil, function() openTritium(not state.tOpen) end)
    addButton("manualD", bx, by + bh * 5 + 3, bw, 1, "D OUT " .. yesno(state.dOpen), state.dOpen and C.btnOn or C.btnOff, nil, function() openDeuterium(not state.dOpen) end)
  end
end

local function drawButtons()
  for _, b in pairs(buttons) do
    for yy = b.y, b.y + b.h - 1 do
      writeAt(b.x, yy, string.rep(" ", b.w), b.fg, b.bg)
    end
    local lx = b.x + math.max(0, math.floor((b.w - #b.label) / 2))
    local ly = b.y + math.floor((b.h - 1) / 2)
    writeAt(lx, ly, b.label, b.fg, b.bg)
  end
end

local function handleTouch(x, y)
  for _, b in pairs(buttons) do
    if y >= b.y and y < b.y + b.h and x >= b.x and x < b.x + b.w then
      b.action()
      return true
    end
  end
  return false
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
  drawButtons()
  drawFooter(layout)
end

local function drawIoPanel(x, y, w, h)
  if h < 4 then return end
  drawBox(x, y, w, h, "REAL I/O", C.borderDim)
  local rx = x + 2
  local ry = y + 1
  drawKeyValue(rx, ry, "LAS OUT", yesno(state.laserLineOn), C.dim, state.laserLineOn and C.ok or C.warn, w - 6)
  drawKeyValue(rx, ry + 1, "T OUT", yesno(state.tOpen), C.dim, state.tOpen and C.ok or C.warn, w - 6)
  drawKeyValue(rx, ry + 2, "D OUT", yesno(state.dOpen), C.dim, state.dOpen and C.ok or C.warn, w - 6)
  drawKeyValue(rx, ry + 3, "Reader T", hw.readerRoles.tritium and "OK" or "FAIL", C.dim, hw.readerRoles.tritium and C.ok or C.bad, w - 6)
  if ry + 4 <= y + h - 2 then drawKeyValue(rx, ry + 4, "Reader D", hw.readerRoles.deuterium and "OK" or "FAIL", C.dim, hw.readerRoles.deuterium and C.ok or C.bad, w - 6) end
  if ry + 5 <= y + h - 2 then drawKeyValue(rx, ry + 5, "Reader Aux", hw.readerRoles.inventory and "OK" or "FAIL", C.dim, hw.readerRoles.inventory and C.ok or C.bad, w - 6) end
end

local function drawStatusPanel(panel)
  drawBox(panel.x, panel.y, panel.w, panel.h, "SUPERVISION", C.border)
  local x = panel.x + 1
  local y = panel.y + 1
  local w = panel.w - 2

  local b1h = clamp(math.floor(panel.h * 0.28), 5, 8)
  local b2h = clamp(math.floor(panel.h * 0.26), 5, 8)
  local b3h = panel.h - b1h - b2h - 2

  drawBox(x, y, w, b1h, "PHASE", C.borderDim)
  local phase = reactorPhase()
  drawBadge(x + 2, y + 1, "STATE", phase, phaseColor(phase))
  drawBadge(x + 2, y + 2, "CORE", state.reactorPresent and (state.reactorFormed and "FORMED" or "UNFORMED") or "OFFLINE")
  if b1h > 5 then drawKeyValue(x + 2, y + 3, "Temp P", fmt(state.plasmaTemp), C.dim, C.info, w - 6) end
  if b1h > 6 then drawKeyValue(x + 2, y + 4, "Temp C", fmt(state.caseTemp), C.dim, C.info, w - 6) end

  local y2 = y + b1h
  drawBox(x, y2, w, b2h, "ENERGY/FUEL", C.borderDim)
  drawBar(x + 2, y2 + 1, math.max(8, w - 4), state.laserPct, C.warn, string.format("LAS %3.0f%%", state.laserPct))
  drawBar(x + 2, y2 + 2, math.max(8, w - 4), state.energyKnown and state.energyPct or 0, C.energy, state.energyKnown and string.format("GRID %3.0f%%", state.energyPct) or "GRID N/A")
  if b2h > 5 then
    drawKeyValue(x + 2, y2 + 3, "D Tank", formatFuelLevel(state.deuteriumAmount), C.dim, C.fuel, w - 6)
    drawKeyValue(x + 2, y2 + 4, "T Tank", formatFuelLevel(state.tritiumAmount), C.dim, C.fuel, w - 6)
  end

  local y3 = y2 + b2h
  drawBox(x, y3, w, b3h, "SAFETY", C.borderDim)
  local warnings = state.safetyWarnings or {}
  if #warnings == 0 then
    writeAt(x + 2, y3 + 1, "NO CRITICAL WARNING", C.ok, C.panelDark)
  else
    for i = 1, math.min(#warnings, b3h - 2) do
      writeAt(x + 2, y3 + i, shortText("- " .. warnings[i], w - 4), C.warn, C.panelDark)
    end
  end
end

local function drawControlPanel(panel, layout)
  drawBox(panel.x, panel.y, panel.w, panel.h, "CONTROL COLUMN", C.border)
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
  drawButtons()

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
  if center then
    drawBox(center.x, center.y, center.w, center.h, "DIAGNOSTIC", C.border)
    local x = center.x + 2
    local y = center.y + 1
    drawKeyValue(x, y, "Reactor", hw.reactorName or "MISSING", C.dim, hw.reactor and C.ok or C.bad, center.w - 6)
    drawKeyValue(x, y + 1, "Logic", hw.logicName or "MISSING", C.dim, hw.logic and C.ok or C.bad, center.w - 6)
    drawKeyValue(x, y + 2, "Laser", hw.laserName or "MISSING", C.dim, hw.laser and C.ok or C.bad, center.w - 6)
    drawKeyValue(x, y + 3, "Induction", hw.inductionName or "MISSING", C.dim, hw.induction and C.ok or C.warn, center.w - 6)
    drawKeyValue(x, y + 5, "Relay LAS", CFG.actions.laser_charge.relay .. "." .. CFG.actions.laser_charge.side, C.dim, hw.relays[CFG.actions.laser_charge.relay] and C.ok or C.bad, center.w - 6)
    drawKeyValue(x, y + 6, "Relay D", CFG.actions.deuterium.relay .. "." .. CFG.actions.deuterium.side, C.dim, hw.relays[CFG.actions.deuterium.relay] and C.ok or C.bad, center.w - 6)
    drawKeyValue(x, y + 7, "Relay T", CFG.actions.tritium.relay .. "." .. CFG.actions.tritium.side, C.dim, hw.relays[CFG.actions.tritium.relay] and C.ok or C.bad, center.w - 6)
    drawKeyValue(x, y + 9, "Reader D", hw.readerRoles.deuterium and hw.readerRoles.deuterium.name or "MISSING", C.dim, hw.readerRoles.deuterium and C.ok or C.bad, center.w - 6)
    drawKeyValue(x, y + 10, "Reader T", hw.readerRoles.tritium and hw.readerRoles.tritium.name or "MISSING", C.dim, hw.readerRoles.tritium and C.ok or C.bad, center.w - 6)
    drawKeyValue(x, y + 11, "Reader Aux", hw.readerRoles.inventory and hw.readerRoles.inventory.name or "MISSING", C.dim, hw.readerRoles.inventory and C.ok or C.warn, center.w - 6)
    if y + 13 <= center.y + center.h - 2 then
      drawKeyValue(x, y + 13, "Fuel D raw", tostring(state.deuteriumAmount), C.dim, C.text, center.w - 6)
      drawKeyValue(x, y + 14, "Fuel T raw", tostring(state.tritiumAmount), C.dim, C.text, center.w - 6)
    end
  end
  drawControlPanel(layout.right or layout.left, layout)
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
  else
    drawSupervisionView(layout)
  end

  drawFooter(layout)
  state.uiDrawn = true
end

setupMonitor()
refreshAll()
state.status = "Systeme pret"

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
      elseif ch == "2" then
        state.currentView = "diagnostic"
      elseif ch == "3" then
        state.currentView = "manual"
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

  elseif ev == "monitor_touch" then
    local mon, x, y = p1, p2, p3
    if mon == hw.monitorName then
      handleTouch(x, y)
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
