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
  text = colors.white,
  dim = colors.lightGray,
  ok = colors.lime,
  warn = colors.orange,
  bad = colors.red,
  info = colors.cyan,
  energy = colors.yellow,
  fuel = colors.orange,
  headerBg = colors.blue,
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

local function progressBar(x, y, w, pct, color)
  pct = clamp(toNumber(pct, 0), 0, 100)
  local fill = math.floor((w * pct) / 100)
  writeAt(x, y, string.rep("-", w), colors.gray, C.bg)
  if fill > 0 then
    writeAt(x, y, string.rep(" ", fill), colors.white, color or C.ok)
  end
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

local function addButton(id, x, y, w, label, bg, fg, action)
  buttons[id] = { x = x, y = y, w = w, label = label, bg = bg, fg = fg or C.btnText, action = action }
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

local function buildButtons()
  buttons = {}

  if state.choosingMonitor then
    addButton("m1", 1, 5, 39, "1", C.btnAction, nil, function() selectMonitorByIndex(1) end)
    addButton("m2", 1, 7, 39, "2", C.btnAction, nil, function() selectMonitorByIndex(2) end)
    addButton("m3", 1, 9, 39, "3", C.btnAction, nil, function() selectMonitorByIndex(3) end)
    addButton("m4", 1, 11, 39, "4", C.btnAction, nil, function() selectMonitorByIndex(4) end)
    addButton("cancelMon", 1, 17, 39, "ANNULER", C.bad, nil, function() stopMonitorSelection() end)
    return
  end

  addButton("master", 26, 4, 12, "MASTER", state.autoMaster and C.btnOn or C.btnOff, nil, function()
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

  addButton("fusion", 26, 6, 12, "FUSION", state.fusionAuto and C.btnOn or C.btnOff, nil, function()
    state.fusionAuto = not state.fusionAuto
    state.lastAction = "Toggle FUSION"
  end)

  addButton("charge", 26, 8, 12, "CHARGE", state.chargeAuto and C.btnOn or C.btnOff, nil, function()
    state.chargeAuto = not state.chargeAuto
    state.lastAction = "Toggle CHARGE"
  end)

  addButton("ignite", 26, 10, 12, "IGNITE", C.btnAction, nil, function()
    triggerAutomaticIgnitionSequence()
  end)

  addButton("monitor", 26, 12, 12, "MONITOR", C.btnWarn, nil, function()
    startMonitorSelection()
  end)

  addButton("stop", 26, 14, 12, "E-STOP", C.bad, nil, function()
    hardStop("EMERGENCY STOP")
  end)
end

local function drawButtons()
  buildButtons()
  for _, b in pairs(buttons) do
    writeAt(b.x, b.y, string.rep(" ", b.w), b.fg, b.bg)
    local lx = b.x + math.max(0, math.floor((b.w - #b.label) / 2))
    writeAt(lx, b.y, b.label, b.fg, b.bg)
  end
end

local function handleTouch(x, y)
  for _, b in pairs(buttons) do
    if y == b.y and x >= b.x and x < b.x + b.w then
      b.action()
      return true
    end
  end
  return false
end

local function drawMonitorSelection()
  term.setBackgroundColor(C.bg)
  term.setTextColor(C.text)
  term.clear()

  fillLine(1, C.headerBg)
  centerText(1, " Selection Moniteur ", C.headerText, C.headerBg)

  writeAt(1, 2, "Choisissez un moniteur :", C.text)
  writeAt(1, 3, "Index - Nom - Taille", C.dim)

  for i = 1, 4 do
    local y = 4 + (i * 2 - 1)
    local m = state.monitorList[i]
    if m then
      local label = string.format("[%d] %s (%dx%d)", i, m.name, m.w or 0, m.h or 0)
      writeAt(1, y, string.rep(" ", 39), C.text, C.bg)
      writeAt(2, y, label:sub(1, 37), C.text, C.bg)
    else
      writeAt(1, y, string.rep(" ", 39), C.text, C.bg)
      writeAt(2, y, string.format("[%d] --", i), C.dim, C.bg)
    end
  end

  drawButtons()
end

local function drawUI()
  local tw, th = term.getSize()

  if tw < 39 or th < 19 then
    term.setBackgroundColor(C.bg)
    term.setTextColor(C.bad)
    term.clear()
    centerText(2, "Moniteur trop petit", C.bad, C.bg)
    centerText(4, "Taille mini 39x19", C.warn, C.bg)
    return
  end

  if state.choosingMonitor then
    drawMonitorSelection()
    return
  end

  term.setBackgroundColor(C.bg)
  term.setTextColor(C.text)

  if not state.uiDrawn then
    term.clear()
    fillLine(1, C.headerBg)
    centerText(1, " Fusion Control 39x19 ", C.headerText, C.headerBg)
    state.uiDrawn = true
  end

  fillArea(1, 2, 39, 18, C.bg)

  writeAt(1, 2, "STAT: " .. state.status, C.warn)
  writeAt(1, 3, "ALRT: " .. state.alert, state.alert == "DANGER" and C.bad or (state.alert == "WARN" and C.warn or C.ok))

  writeAt(1, 5, "Reactor: " .. yesno(state.reactorPresent), state.reactorPresent and C.ok or C.bad)
  writeAt(1, 6, "Formed : " .. yesno(state.reactorFormed), state.reactorFormed and C.ok or C.bad)
  writeAt(1, 7, "Ignite : " .. yesno(state.ignition), state.ignition and C.ok or C.bad)

  writeAt(1, 9,  "LaserE : " .. fmt(state.laserEnergy), C.text)
  progressBar(1, 10, 18, state.laserPct, C.ok)
  writeAt(1, 11, "L%     : " .. string.format("%5.1f", state.laserPct), C.dim)

  writeAt(1, 13, "Energy : " .. (state.energyKnown and fmt(state.energyStored) or "N/A"), C.text)
  writeAt(1, 14, "E%     : " .. (state.energyKnown and string.format("%5.1f", state.energyPct) or "N/A"), C.energy)

  writeAt(1, 16, "D: " .. fmt(state.deuteriumAmount), C.fuel)
  writeAt(1, 17, "T: " .. fmt(state.tritiumAmount), C.fuel)

  local monText = tostring(hw.monitorName or "none")
  writeAt(1, 18, "Mon: " .. monText:sub(1, 34), C.dim)

  drawButtons()
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