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

  -- Mapping des redstone relays
  actions = {
    laser_charge = { relay = "redstone_relay_0", side = "top",   analog = 15, pulse = false },
    laser_fire   = { relay = "redstone_relay_1", side = "front", analog = 15, pulse = true, pulseTime = 0.4 },
    hohlraum     = { relay = "redstone_relay_2", side = "front", analog = 15, pulse = true, pulseTime = 0.2 },

    dt_fuel      = nil,
    deuterium    = nil,
    tritium      = nil,
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
  writeAt(x, y, "+" .. string.rep("-", w - 2) .. "+", accent, C.panelDark)
  for yy = y + 1, y + h - 2 do
    writeAt(x, yy, "|", accent, C.panelDark)
    writeAt(x + w - 1, yy, "|", accent, C.panelDark)
  end
  writeAt(x, y + h - 1, "+" .. string.rep("-", w - 2) .. "+", accent, C.panelDark)

  if title and #title > 0 and w > 6 then
    writeAt(x + 2, y, " " .. shortText(title, w - 6) .. " ", C.text, accent)
  end
end

local function drawHeader(title, status)
  local tw = term.getSize()
  local heartbeat = (state.tick % 8 < 4) and "◆" or "◇"
  fillLine(1, C.headerBg)
  writeAt(2, 1, shortText(title, math.max(8, tw - 28)), C.headerText, C.headerBg)
  local statusTxt = "[" .. shortText(status or "N/A", 16) .. "]"
  local sx = math.max(2, tw - #statusTxt - 3)
  writeAt(sx - 2, 1, heartbeat, state.ignition and C.ok or C.warn, C.headerBg)
  writeAt(sx, 1, statusTxt, C.text, C.headerBg)
end

local function drawFooter(layout)
  local tw, th = term.getSize()
  fillLine(th, C.footerBg)
  local left = "ACT " .. shortText(state.lastAction, math.max(10, math.floor(tw * 0.45) - 5))
  local right = "MON " .. shortText(tostring(hw.monitorName or "term"), math.max(8, math.floor(tw * 0.28)))
  writeAt(2, th, left, C.text, C.footerBg)
  writeAt(math.max(2, tw - #right - 1), th, right, C.text, C.footerBg)
  if layout.mode == "large" then
    local center = "L:" .. string.format("%3.0f%%", state.laserPct) .. " E:" .. (state.energyKnown and string.format("%3.0f%%", state.energyPct) or "N/A")
    writeAt(math.max(2, math.floor((tw - #center) / 2)), th, center, C.info, C.footerBg)
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
  if tw >= 66 and th >= 20 then mode = "standard" end
  if tw >= 92 and th >= 23 then mode = "large" end

  local top, bottom = 2, th - 1
  local h = bottom - top + 1
  local layout = { mode = mode, top = top, bottom = bottom, height = h, width = tw, tooSmall = false }

  if mode == "compact" then
    local lw = clamp(math.floor(tw * 0.56), 18, tw - 14)
    layout.left = { x = 1, y = top, w = lw, h = h }
    layout.right = { x = lw + 1, y = top, w = tw - lw, h = h }
  elseif mode == "standard" then
    local lw = clamp(math.floor(tw * 0.44), 26, tw - 32)
    layout.left = { x = 1, y = top, w = lw, h = h }
    layout.right = { x = lw + 1, y = top, w = tw - lw, h = h }
  else
    local lw = clamp(math.floor(tw * 0.26), 22, 30)
    local rw = clamp(math.floor(tw * 0.28), 24, 34)
    local cw = tw - lw - rw
    if cw < 24 then rw = rw - (24 - cw) cw = 24 end
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
  drawBox(x, y, w, h, "REACTOR SCHEMA", C.border)
  if w < 18 or h < 9 then
    writeAt(x + 2, y + 2, "Schema indisponible", C.dim, C.panelDark)
    return
  end

  local cx = x + math.floor(w / 2)
  local cy = y + math.floor(h / 2)
  local pulse = (state.tick % 6 < 3) and "*" or "+"
  local phase = reactorPhase()

  writeAt(x + 2, y + 2, "LASER", C.info, C.panelDark)
  writeAt(x + 8, y + 2, string.rep("-", math.max(2, cx - x - 9)) .. ">", state.laserChargeOn and C.ok or C.dim, C.panelDark)
  writeAt(cx - 3, cy - 1, "+-----+", C.borderDim, C.panelDark)
  writeAt(cx - 3, cy, "| " .. pulse .. " |", state.ignition and C.ok or C.warn, C.panelDark)
  writeAt(cx - 3, cy + 1, "+-----+", C.borderDim, C.panelDark)
  writeAt(cx - 1, cy + 2, "CORE", C.text, C.panelDark)

  local py = math.min(y + h - 4, cy + 4)
  writeAt(x + 2, py - 1, "D2", C.info, C.panelDark)
  writeAt(x + 5, py - 1, string.rep("=", math.max(2, cx - x - 10)) .. ">", state.dOpen and C.ok or C.dim, C.panelDark)
  writeAt(cx + 5, py - 1, state.dOpen and "OPEN" or "STOP", state.dOpen and C.ok or C.warn, C.panelDark)
  writeAt(x + 2, py, "T2", C.info, C.panelDark)
  writeAt(x + 5, py, string.rep("=", math.max(2, cx - x - 10)) .. ">", state.tOpen and C.ok or C.dim, C.panelDark)
  writeAt(cx + 5, py, state.tOpen and "OPEN" or "STOP", state.tOpen and C.ok or C.warn, C.panelDark)

  local eTxt = state.energyKnown and ("GRID " .. string.format("%3.0f%%", state.energyPct)) or "GRID N/A"
  writeAt(x + 2, y + h - 2, shortText("PHASE " .. phase, w - 4), statusColor(state.alert), C.panelDark)
  writeAt(math.max(x + 2, x + w - #eTxt - 2), y + h - 2, eTxt, C.energy, C.panelDark)
end

local function drawBadge(x, y, label, value, tone)
  local badgeTxt = " " .. tostring(value) .. " "
  writeAt(x, y, shortText(label, 9), C.dim, C.panelDark)
  local bx = x + 10
  writeAt(bx, y, badgeTxt, C.text, tone or statusColor(value))
end

local function drawBar(x, y, w, pct, color, label)
  pct = clamp(toNumber(pct, 0), 0, 100)
  local fill = math.floor((w * pct) / 100)
  writeAt(x, y, string.rep(" ", w), C.text, C.panel)
  if fill > 0 then
    writeAt(x, y, string.rep(" ", fill), C.text, color or C.ok)
  end
  if label and #label > 0 and w > 6 then
    local txt = shortText(label, w - 1)
    local lx = x + math.floor((w - #txt) / 2)
    writeAt(lx, y, txt, C.text, C.panelDark)
  end
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

  if data.active_state ~= nil or data.redstone ~= nil or data.current_redstone ~= nil then
    return "active"
  end

  return "unknown"
end

local function scanBlockReaders()
  hw.readerRoles = {
    deuterium = nil,
    tritium = nil,
    energy = nil,
    active = {},
    unknown = {},
  }

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

    if entry.role == "deuterium" and not hw.readerRoles.deuterium then
      hw.readerRoles.deuterium = entry
    elseif entry.role == "tritium" and not hw.readerRoles.tritium then
      hw.readerRoles.tritium = entry
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

local function setLaserCharge(on)
  if relayWrite("laser_charge", on) then
    state.laserChargeOn = on
    state.lastAction = on and "Charge laser ON" or "Charge laser OFF"
  else
    state.laserChargeOn = false
  end
end

local function fireLaser()
  if relayWrite("laser_fire", true) then
    state.lastAction = "Pulse laser"
  end
end

local function injectHohlraum()
  if relayWrite("hohlraum", true) then
    state.lastAction = "Injection hohlraum"
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

  if #hw.readerRoles.active > 0 then
    state.auxPresent = true
    local active, rs = readActiveFromReader(hw.readerRoles.active[1])
    state.auxActive = active
    state.auxRedstone = rs
  else
    state.auxPresent = false
    state.auxActive = false
    state.auxRedstone = 0
  end
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

local function drawLeftStats(panel)
  drawBox(panel.x, panel.y, panel.w, panel.h, "SYSTEM STATUS", C.border)
  local x, y = panel.x + 1, panel.y + 1
  drawBadge(x, y, "CORE", state.reactorPresent and "ONLINE" or "OFFLINE")
  drawBadge(x, y + 1, "MODE", state.autoMaster and "AUTO" or "MANUAL")
  drawBadge(x, y + 2, "ALERT", state.alert, statusColor(state.alert))
  drawKeyValue(x, y + 3, "IGNITION", state.ignition and "ACTIVE" or "IDLE", C.dim, state.ignition and C.ok or C.warn, 12)

  drawKeyValue(x, y + 5, "LASER", fmt(state.laserEnergy), C.dim, C.text, panel.w - 14)
  drawBar(x, y + 6, panel.w - 3, state.laserPct, C.ok, string.format("LASER %3.0f%%", state.laserPct))
  drawKeyValue(x, y + 7, "CHARGE", state.laserChargeOn and "ON" or "OFF", C.dim, state.laserChargeOn and C.ok or C.bad, 8)

  if y + 11 < panel.y + panel.h - 1 then
    drawKeyValue(x, y + 9, "ENERGY", state.energyKnown and fmt(state.energyStored) or "UNKNOWN", C.dim, C.energy, panel.w - 14)
    drawBar(x, y + 10, panel.w - 3, state.energyKnown and state.energyPct or 0, C.energy, state.energyKnown and string.format("GRID %3.0f%%", state.energyPct) or "GRID N/A")
    drawKeyValue(x, y + 11, "CASE T", fmt(state.caseTemp), C.dim, C.info, 10)
  end
end

local function drawControlPanel(panel, layout)
  drawBox(panel.x, panel.y, panel.w, panel.h, "CONTROL", C.border)
  local x = panel.x + 1
  drawBadge(x, panel.y + 1, "FUSION", state.fusionAuto and "AUTO" or "MANUAL")
  drawBadge(x, panel.y + 2, "CHARGE", state.chargeAuto and "AUTO" or "MANUAL")
  drawBadge(x, panel.y + 3, "GAS", state.gasAuto and "AUTO" or "MANUAL")
  buildButtons(layout)
  drawButtons()
  local fy = panel.y + panel.h - 3
  if fy > panel.y + 8 then
    drawKeyValue(x, fy, "DEUT", fmt(state.deuteriumAmount), C.dim, C.fuel, panel.w - 14)
    drawKeyValue(x, fy + 1, "TRIT", fmt(state.tritiumAmount), C.dim, C.fuel, panel.w - 14)
  end
end

local function drawCompactLayout(layout)
  drawLeftStats(layout.left)
  drawControlPanel(layout.right, layout)
end

local function drawStandardLayout(layout)
  local diagramH = clamp(math.floor(layout.right.h * 0.60), 9, layout.right.h - 8)
  drawLeftStats(layout.left)
  drawReactorDiagram(layout.right.x, layout.right.y, layout.right.w, diagramH)
  drawControlPanel({ x = layout.right.x, y = layout.right.y + diagramH, w = layout.right.w, h = layout.right.h - diagramH }, layout)
end

local function drawLargeLayout(layout)
  drawLeftStats(layout.left)
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
