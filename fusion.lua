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

local function fmtFuelAmount(n)
  n = toNumber(n, 0)
  if n >= 1000000000000 then return "SAT" end
  if n >= 1000000000 then return "FULL" end
  if n >= 100000000 then return "MAX" end
  if n >= 10000000 then return "HIGH" end
  return fmt(n)
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

local function drawHeader(title, status)
  local tw = term.getSize()
  local heartbeat = (state.tick % 8 < 4) and "●" or "○"
  local phase = state.status or "N/A"
  fillLine(1, colors.gray)
  writeAt(2, 1, shortText(title, math.max(10, tw - 34)), C.headerText, colors.gray)
  local centerTxt = "PHASE " .. shortText(phase, 18)
  local cx = math.max(2, math.floor((tw - #centerTxt) / 2))
  writeAt(cx, 1, centerTxt, C.info, colors.gray)
  local statusTxt = shortText(status or "N/A", 16)
  local rightTxt = heartbeat .. " ALERT " .. statusTxt
  local sx = math.max(2, tw - #rightTxt - 2)
  writeAt(sx, 1, rightTxt, statusColor(state.alert), colors.gray)
end

local function drawFooter(layout)
  local tw, th = term.getSize()
  fillLine(th, colors.gray)
  local seg = math.max(12, math.floor(tw / 6))
  local s1 = shortText("ACT " .. state.lastAction, seg - 1)
  local s2 = shortText("MON " .. tostring(hw.monitorName or "term"), seg - 1)
  local s3 = shortText("PHASE " .. reactorPhase() .. " / IGN " .. (state.ignition and "ON" or "OFF"), seg - 1)
  local s4 = shortText("LASER " .. string.format("%3.0f%%", state.laserPct), seg - 1)
  local s5 = shortText("FUEL D " .. fmtFuelAmount(state.deuteriumAmount) .. " T " .. fmtFuelAmount(state.tritiumAmount), seg - 1)
  local s6 = shortText("GRID " .. (state.energyKnown and string.format("%3.0f%%", state.energyPct) or "N/A"), tw - (seg * 5) - 2)

  writeAt(2, th, s1, C.text, colors.gray)
  writeAt(seg + 1, th, "|", C.panelMid, colors.gray)
  writeAt(seg + 2, th, s2, C.info, colors.gray)
  writeAt(seg * 2 + 1, th, "|", C.panelMid, colors.gray)
  writeAt(seg * 2 + 2, th, s3, state.ignition and C.ok or C.warn, colors.gray)
  writeAt(seg * 3 + 1, th, "|", C.panelMid, colors.gray)
  writeAt(seg * 3 + 2, th, s4, C.energy, colors.gray)
  writeAt(seg * 4 + 1, th, "|", C.panelMid, colors.gray)
  writeAt(seg * 4 + 2, th, s5, C.fuel, colors.gray)
  writeAt(seg * 5 + 1, th, "|", C.panelMid, colors.gray)
  writeAt(seg * 5 + 2, th, s6, C.energy, colors.gray)
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

local function reactorPhase()
  if not state.reactorPresent then return "OFFLINE" end
  if not state.reactorFormed then return "FORMED" end
  if state.ignitionSequencePending then return "IGNITING" end
  if state.ignition and state.dtOpen then return "FUEL FLOW" end
  if state.ignition then return "IGNITED" end
  if state.laserChargeOn then return "CHARGING" end
  return "SAFE STOP"
end

local function drawReactorDiagram(x, y, w, h)
  drawBox(x, y, w, h, "FUSION CHAMBER", C.border)
  if w < 28 or h < 14 then
    writeAt(x + 2, y + 2, "Schema indisponible", C.dim, C.panelDark)
    return
  end

  local innerW = w - 2
  local innerH = h - 2
  local cx = x + math.floor(innerW / 2)
  local cy = y + math.floor(innerH / 2)
  local pulse = (state.tick % 6 < 3) and "●" or "○"
  local phase = reactorPhase()
  local laserChar = state.laserLineOn and ((state.tick % 4 < 2) and "=" or "~") or "."
  local fuelChar = ((state.tick % 4 < 2) and "=" or "-")

  local coreW = clamp(math.floor(innerW * 0.52), 16, math.max(16, innerW - 18))
  local coreH = clamp(math.floor(innerH * 0.60), 10, math.max(10, innerH - 4))
  local coreX = cx - math.floor(coreW / 2)
  local coreY = cy - math.floor(coreH / 2)
  local coreRight = coreX + coreW - 1
  local coreBottom = coreY + coreH - 1

  local laserY = coreY + 2
  writeAt(x + 2, laserY, "Charge Laser", C.info, C.panelDark)
  local beamStart = x + 8
  local beamLen = math.max(6, coreX - beamStart - 1)
  writeAt(beamStart, laserY, string.rep(laserChar, beamLen) .. ">", state.laserLineOn and C.ok or C.dim, C.panelDark)

  local dY = cy + 1
  local tY = cy + 3
  local leftPipe = x + 2
  local leftLen = math.max(3, coreX - leftPipe - 8)
  writeAt(leftPipe, dY, "D Tank", C.info, C.panelDark)
  writeAt(leftPipe + 7, dY, string.rep(fuelChar, leftLen) .. ">", state.dOpen and C.ok or C.dim, C.panelDark)
  writeAt(leftPipe, tY, "T Tank", C.info, C.panelDark)
  writeAt(leftPipe + 7, tY, string.rep(fuelChar, leftLen) .. ">", state.tOpen and C.ok or C.dim, C.panelDark)

  writeAt(coreX, coreY, "+" .. string.rep("-", coreW - 2) .. "+", C.border, C.panelDark)
  for yy = coreY + 1, coreBottom - 1 do
    writeAt(coreX, yy, "|", C.border, C.panelDark)
    writeAt(coreRight, yy, "|", C.border, C.panelDark)
    if yy > coreY + 1 and yy < coreBottom - 1 then
      writeAt(coreX + 1, yy, string.rep(" ", coreW - 2), C.text, (yy % 2 == 0) and colors.black or colors.gray)
    end
  end
  writeAt(coreX, coreBottom, "+" .. string.rep("-", coreW - 2) .. "+", C.border, C.panelDark)

  local plasmaW = clamp(math.floor(coreW * 0.46), 8, coreW - 6)
  local plasmaX = cx - math.floor(plasmaW / 2)
  local plasmaY = cy
  writeAt(plasmaX, plasmaY, "[" .. string.rep(pulse, plasmaW - 2) .. "]", state.ignition and C.ok or C.warn, C.panelDark)
  writeAt(coreX + 2, coreY + 1, shortText("IGNITION  " .. (state.ignition and "ONLINE" or (state.ignitionSequencePending and "PENDING" or "IDLE")), coreW - 4), state.ignition and C.ok or C.warn, C.panelDark)
  writeAt(coreX + 2, coreY + 3, shortText("PLASMA    " .. (state.ignition and "CONFINED" or "COLD"), coreW - 4), state.ignition and C.ok or C.dim, C.panelDark)
  writeAt(coreX + 2, coreY + 5, shortText("FUEL FLOW " .. ((state.dtOpen or state.dOpen or state.tOpen) and "ACTIVE" or "STOP"), coreW - 4), (state.dtOpen or state.dOpen or state.tOpen) and C.fuel or C.warn, C.panelDark)
  writeAt(coreX + 2, coreY + 7, shortText("STABILITY " .. (state.alert == "DANGER" and "CRITICAL" or "NOMINAL"), coreW - 4), state.alert == "DANGER" and C.bad or C.ok, C.panelDark)

  local outX = coreRight + 1
  if outX < x + w - 7 then
    local outLen = math.max(3, x + w - outX - 3)
    writeAt(outX, cy, string.rep("-", outLen) .. ">", C.energy, C.panelDark)
    writeAt(outX, cy - 2, shortText("OUTPUT GRID", outLen), C.energy, C.panelDark)
    local stTxt = state.energyKnown and string.format("CHARGE %3.0f%%", state.energyPct) or "CHARGE N/A"
    writeAt(outX, cy + 1, shortText(stTxt, outLen), C.energy, C.panelDark)
  end

  local eTxt = state.energyKnown and ("GRID " .. string.format("%3.0f%%", state.energyPct)) or "GRID N/A"
  local lTxt = "LAS " .. string.format("%3.0f%%", state.laserPct)
  writeAt(x + 2, y + h - 2, shortText("PHASE " .. phase, math.floor(w * 0.50)), statusColor(state.alert), C.panelDark)
  writeAt(x + math.floor(w * 0.50), y + h - 2, shortText(lTxt .. "  " .. eTxt, w - math.floor(w * 0.50) - 2), C.info, C.panelDark)
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
  if not state.reactorPresent then
    state.alert = "WARN"
  elseif not state.reactorFormed then
    state.alert = "WARN"
  elseif state.energyKnown and state.energyPct <= CFG.energyLowPct then
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
  local by = ctrl.y + 5
  local bh = (layout.mode == "compact") and 1 or 2

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

local function drawStatusPanel(panel)
  drawBox(panel.x, panel.y, panel.w, panel.h, "STATUS COLUMN", C.border)
  local x = panel.x + 1
  local y = panel.y + 1
  local w = panel.w - 2

  local blockH = clamp(math.floor((panel.h - 3) / 4), 4, 7)
  local b1 = { x = x, y = y, w = w, h = blockH }
  local b2 = { x = x, y = b1.y + b1.h, w = w, h = blockH }
  local b3 = { x = x, y = b2.y + b2.h, w = w, h = blockH }
  local b4 = { x = x, y = b3.y + b3.h, w = w, h = panel.y + panel.h - (b3.y + b3.h) }

  drawBox(b1.x, b1.y, b1.w, b1.h, "REACTOR", C.borderDim)
  drawBadge(b1.x + 2, b1.y + 1, "CORE", state.reactorPresent and "ONLINE" or "OFFLINE")
  drawBadge(b1.x + 2, b1.y + 2, "MODE", state.autoMaster and "AUTO" or "MANUAL")
  if b1.h > 4 then
    drawKeyValue(b1.x + 2, b1.y + 3, "STATE", reactorPhase(), C.dim, statusColor(state.alert), b1.w - 14)
  end

  drawBox(b2.x, b2.y, b2.w, b2.h, "LASER", C.borderDim)
  drawKeyValue(b2.x + 2, b2.y + 1, "STATUS", state.laserLineOn and "CHARGE" or "IDLE", C.dim, state.laserLineOn and C.ok or C.warn, b2.w - 14)
  drawKeyValue(b2.x + 2, b2.y + 2, "ENERGY", fmt(state.laserEnergy), C.dim, C.info, b2.w - 14)
  if b2.h > 4 then
    drawBar(b2.x + 2, b2.y + 3, math.max(8, b2.w - 4), state.laserPct, C.warn, string.format("LAS %3.0f%%", state.laserPct))
  end

  drawBox(b3.x, b3.y, b3.w, b3.h, "ENERGY", C.borderDim)
  drawKeyValue(b3.x + 2, b3.y + 1, "GRID", state.energyKnown and fmt(state.energyStored) or "UNKNOWN", C.dim, C.energy, b3.w - 14)
  drawKeyValue(b3.x + 2, b3.y + 2, "CASE T", fmt(state.caseTemp), C.dim, C.info, b3.w - 14)
  if b3.h > 4 then
    drawBar(b3.x + 2, b3.y + 3, math.max(8, b3.w - 4), state.energyKnown and state.energyPct or 0, C.energy, state.energyKnown and string.format("GRID %3.0f%%", state.energyPct) or "GRID N/A")
  end

  if b4.h >= 4 then
    drawBox(b4.x, b4.y, b4.w, b4.h, "FUEL", C.borderDim)
    drawKeyValue(b4.x + 2, b4.y + 1, "D", fmtFuelAmount(state.deuteriumAmount), C.dim, C.fuel, b4.w - 14)
    drawKeyValue(b4.x + 2, b4.y + 2, "T", fmtFuelAmount(state.tritiumAmount), C.dim, C.fuel, b4.w - 14)
    if b4.h > 4 then
      drawKeyValue(b4.x + 2, b4.y + 3, "D RELAY", state.dOpen and "OPEN" or "STOP", C.dim, state.dOpen and C.ok or C.warn, b4.w - 14)
    end
    if b4.h > 5 then
      drawKeyValue(b4.x + 2, b4.y + 4, "T RELAY", state.tOpen and "OPEN" or "STOP", C.dim, state.tOpen and C.ok or C.warn, b4.w - 14)
    end
    if b4.h > 6 then
      drawKeyValue(b4.x + 2, b4.y + 5, "Reader D", hw.readerRoles.deuterium and "OK" or "MISS", C.dim, hw.readerRoles.deuterium and C.ok or C.warn, b4.w - 14)
    end
    if b4.h > 7 then
      drawKeyValue(b4.x + 2, b4.y + 6, "Reader T", hw.readerRoles.tritium and "OK" or "MISS", C.dim, hw.readerRoles.tritium and C.ok or C.warn, b4.w - 14)
    end
    if b4.h > 8 then
      drawKeyValue(b4.x + 2, b4.y + 7, "Reader Aux", hw.readerRoles.inventory and "OK" or "MISS", C.dim, hw.readerRoles.inventory and C.ok or C.warn, b4.w - 14)
    end
  end
end

local function drawControlPanel(panel, layout)
  drawBox(panel.x, panel.y, panel.w, panel.h, "CONTROL COLUMN", C.border)
  local x = panel.x + 1
  local w = panel.w - 2

  local summaryH = clamp(math.floor(panel.h * 0.28), 6, 8)
  drawBox(x, panel.y + 1, w, summaryH, "MODE SUMMARY", C.borderDim)
  local sx = x + 2
  drawBadge(sx, panel.y + 2, "MASTER", state.autoMaster and "AUTO" or "MANUAL")
  drawBadge(sx, panel.y + 3, "FUSION", state.fusionAuto and "AUTO" or "MANUAL")
  drawBadge(sx, panel.y + 4, "CHARGE", state.chargeAuto and "AUTO" or "MANUAL")
  drawBadge(sx, panel.y + 5, "GAS", state.gasAuto and "AUTO" or "MANUAL")
  if summaryH >= 7 then
    drawKeyValue(sx, panel.y + 6, "Charge L", state.laserLineOn and "ON" or "OFF", C.dim, state.laserLineOn and C.ok or C.warn, w - 6)
  end

  local controlsY = panel.y + 1 + summaryH
  local controlsH = panel.h - summaryH - 1
  if controlsH >= 6 then
    drawBox(x, controlsY, w, controlsH, "COMMANDS", C.borderDim)
  end

  buildButtons(layout)
  drawButtons()

  local fy = panel.y + panel.h - 3
  if fy > panel.y + 9 then
    drawKeyValue(panel.x + 3, fy, "Tank D", state.dOpen and "OPEN" or "STOP", C.dim, state.dOpen and C.ok or C.warn, panel.w - 16)
    drawKeyValue(panel.x + 3, fy + 1, "Tank T", state.tOpen and "OPEN" or "STOP", C.dim, state.tOpen and C.ok or C.warn, panel.w - 16)
  end
end

local function drawCompactLayout(layout)
  drawStatusPanel(layout.left)
  drawControlPanel(layout.right, layout)
end

local function drawStandardLayout(layout)
  drawStatusPanel(layout.left)
  drawReactorDiagram(layout.center.x, layout.center.y, layout.center.w, layout.center.h)
  drawControlPanel(layout.right, layout)
end

local function drawLargeLayout(layout)
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

  if layout.mode == "compact" then
    drawCompactLayout(layout)
  elseif layout.mode == "standard" then
    drawStandardLayout(layout)
  else
    drawLargeLayout(layout)
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
