-- install.lua
-- Assistant d'installation Fusion ViperCraft

local CONFIG_FILE = "fusion_config.lua"
local VERSION_FILE = "fusion.version"
local DEFAULT_VERSION = "1.1.0"

local CoreConfig = require("core.config")
local function loadDisplayBackend()
  if type(require) == "function" then
    local ok, mod = pcall(require, "io.display_backend")
    if ok and type(mod) == "table" then
      return mod
    end
  end
  return {
    detectCandidate = function(name, obj)
      if not obj then return nil end
      if type(obj.getSize) == "function" then
        local ok, w, h = pcall(obj.getSize)
        if ok then
          return {
            name = name,
            obj = obj,
            kind = "cc_monitor",
            touchEvent = "monitor_touch",
            w = tonumber(w) or 0,
            h = tonumber(h) or 0,
          }
        end
      end
      return nil
    end,
    createSurface = function(candidate)
      return candidate and candidate.obj or nil, {
        kind = (candidate and candidate.kind) or "cc_monitor",
        touchEvent = (candidate and candidate.touchEvent) or "monitor_touch",
        mapPixel = nil,
      }
    end,
  }
end

local DisplayBackend = loadDisplayBackend()
local state

local SIDES = { "top", "bottom", "left", "right", "front", "back" }

local function contains(str, sub)
  return type(str) == "string" and type(sub) == "string"
    and string.find(string.lower(str), string.lower(sub), 1, true) ~= nil
end

local function getTypeOf(name)
  local ok, ptype = pcall(peripheral.getType, name)
  if ok then return ptype end
  return nil
end

local function safePeripheral(name)
  if type(name) ~= "string" or name == "" then return nil end
  if not peripheral.isPresent(name) then return nil end
  local ok, obj = pcall(peripheral.wrap, name)
  if ok then return obj end
  return nil
end

local function hasMethods(obj, methods, minCount)
  if not obj then return false end
  local count = 0
  for _, methodName in ipairs(methods) do
    if type(obj[methodName]) == "function" then
      count = count + 1
    end
  end
  return count >= (minCount or 1), count
end

local function normalizeDisplayCandidate(name, obj)
  if not obj then return nil end
  local candidate = DisplayBackend.detectCandidate(name, obj, getTypeOf)
  if not candidate then return nil end

  local width = tonumber(candidate.w) or 0
  local height = tonumber(candidate.h) or 0
  if (width <= 0 or height <= 0) and type(obj.getSize) == "function" then
    local ok, w, h = pcall(obj.getSize)
    if ok then
      width = tonumber(w) or width
      height = tonumber(h) or height
    end
  end

  local backend = tostring(candidate.kind or "cc_monitor")
  local touchEvent = tostring(candidate.touchEvent or "monitor_touch")
  return {
    name = name,
    obj = obj,
    backend = backend,
    touchEvent = touchEvent,
    w = math.max(0, math.floor(width)),
    h = math.max(0, math.floor(height)),
  }
end

local function gatherPeripherals()
  local names = peripheral.getNames()
  table.sort(names)

  local devices = {
    all = names,
    byType = {},
    byName = {},
    monitors = {},
    displays = {},
    displayCandidates = {},
    displayByName = {},
    displayBackends = { cc_monitor = 0, toms_gpu = 0, other = 0 },
    readers = {},
    relays = {},
  }

  for _, name in ipairs(names) do
    local ptype = getTypeOf(name) or "unknown"
    local obj = safePeripheral(name)

    devices.byName[name] = { type = ptype, obj = obj }
    devices.byType[ptype] = devices.byType[ptype] or {}
    table.insert(devices.byType[ptype], name)

    local displayCandidate = normalizeDisplayCandidate(name, obj)
    if displayCandidate then
      devices.displayCandidates[#devices.displayCandidates + 1] = displayCandidate
      devices.displayByName[name] = displayCandidate
      devices.displays[#devices.displays + 1] = name
      devices.monitors[#devices.monitors + 1] = name
      if displayCandidate.backend == "toms_gpu" then
        devices.displayBackends.toms_gpu = devices.displayBackends.toms_gpu + 1
      elseif displayCandidate.backend == "cc_monitor" then
        devices.displayBackends.cc_monitor = devices.displayBackends.cc_monitor + 1
      else
        devices.displayBackends.other = devices.displayBackends.other + 1
      end
    end

    local isReader = hasMethods(obj, {
      "getBlockData",
      "getBlockName",
      "listMethods",
    }, 1)
    if ptype == "block_reader" or isReader or contains(ptype, "reader") then
      devices.readers[#devices.readers + 1] = name
    end

    local isRelay = hasMethods(obj, {
      "setOutput",
      "setAnalogOutput",
      "setAnalogueOutput",
      "getOutput",
    }, 1)
    if ptype == "redstone_relay" or isRelay or contains(ptype, "relay") or contains(name, "relay") then
      devices.relays[#devices.relays + 1] = name
    end
  end

  local backendPriority = {
    toms_gpu = 1,
    cc_monitor = 2,
  }
  table.sort(devices.displayCandidates, function(a, b)
    local pa = backendPriority[a.backend] or 99
    local pb = backendPriority[b.backend] or 99
    if pa ~= pb then return pa < pb end
    return a.name < b.name
  end)
  table.sort(devices.readers)
  table.sort(devices.relays)

  return devices
end

local function pickUnused(list, used)
  for _, name in ipairs(list) do
    if not used[name] then
      used[name] = true
      return name
    end
  end
  return nil
end

local function pickByKeywords(list, keywords, used)
  for _, name in ipairs(list) do
    if not used[name] then
      for _, key in ipairs(keywords) do
        if contains(name, key) then
          used[name] = true
          return name
        end
      end
    end
  end
  return nil
end

local function countMethods(obj, methods)
  local _, count = hasMethods(obj, methods, 1)
  return count or 0
end

local function pickBestByRule(devices, scorer)
  local bestName = nil
  local bestScore = nil
  for _, name in ipairs(devices.all) do
    local info = devices.byName[name]
    if info and info.obj then
      local score = scorer(name, info.obj, tostring(info.type or ""))
      if score ~= nil and (bestScore == nil or score > bestScore or (score == bestScore and name < bestName)) then
        bestScore = score
        bestName = name
      end
    end
  end
  return bestName
end

local function listCandidates(devices)
  local usedRelay = {}
  local usedReader = {}

  local displayCandidate = devices.displayCandidates[1]
  local monitorName = displayCandidate and displayCandidate.name or nil

  local reactorController = pickBestByRule(devices, function(name, obj, ptype)
    local valid = hasMethods(obj, {
      "isIgnited",
      "getPlasmaTemperature",
      "getPlasmaTemp",
      "getPlasmaHeat",
      "getCaseTemperature",
      "getCasingTemperature",
    }, 2)
    if not valid then return nil end
    local score = countMethods(obj, {
      "isIgnited",
      "getPlasmaTemperature",
      "getPlasmaTemp",
      "getPlasmaHeat",
      "getCaseTemperature",
      "getCasingTemperature",
    })
    if contains(ptype, "fusion_reactor_controller") then score = score + 20 end
    if contains(name, "reactor") then score = score + 2 end
    return score
  end)

  local logicAdapter = pickBestByRule(devices, function(name, obj, ptype)
    local valid = hasMethods(obj, {
      "isFormed",
      "isIgnited",
      "setInjectionRate",
      "getInjectionRate",
      "getPlasmaTemperature",
      "getCaseTemperature",
    }, 3)
    if not valid then return nil end
    local score = countMethods(obj, {
      "isFormed",
      "isIgnited",
      "setInjectionRate",
      "getInjectionRate",
      "getPlasmaTemperature",
      "getCaseTemperature",
    })
    if contains(ptype, "logic") then score = score + 8 end
    if contains(name, "logic") then score = score + 2 end
    return score
  end)

  local laser = pickBestByRule(devices, function(name, obj, ptype)
    local valid = hasMethods(obj, {
      "getEnergy",
      "getEnergyStored",
      "getMaxEnergy",
      "getMaxEnergyStored",
      "getEnergyFilledPercentage",
    }, 2)
    if not valid then return nil end
    local score = countMethods(obj, {
      "getEnergy",
      "getEnergyStored",
      "getMaxEnergy",
      "getMaxEnergyStored",
      "getEnergyFilledPercentage",
    })
    if contains(ptype, "laser") or contains(name, "laser") then score = score + 10 end
    return score
  end)

  local induction = pickBestByRule(devices, function(name, obj, ptype)
    local valid = hasMethods(obj, {
      "isFormed",
      "getEnergy",
      "getMaxEnergy",
      "getLastInput",
      "getLastOutput",
      "getTransferCap",
    }, 3)
    if not valid then return nil end
    local score = countMethods(obj, {
      "isFormed",
      "getEnergy",
      "getMaxEnergy",
      "getLastInput",
      "getLastOutput",
      "getTransferCap",
    })
    if contains(ptype, "induction") or contains(name, "induction") then score = score + 10 end
    if contains(ptype, "matrix") or contains(name, "matrix") then score = score + 2 end
    return score
  end)

  local relayLaser = pickByKeywords(devices.relays, { "laser", "las" }, usedRelay) or pickUnused(devices.relays, usedRelay)
  local relayTritium = pickByKeywords(devices.relays, { "tritium", "tank_t", "tankt" }, usedRelay) or pickUnused(devices.relays, usedRelay)
  local relayDeuterium = pickByKeywords(devices.relays, { "deuterium", "tank_d", "tankd" }, usedRelay) or pickUnused(devices.relays, usedRelay)
  local relayDTFuel = pickByKeywords(devices.relays, { "dt", "fuel", "mix" }, usedRelay) or pickUnused(devices.relays, usedRelay)

  local readerTritium = pickByKeywords(devices.readers, { "tritium", "tank_t", "tankt" }, usedReader) or pickUnused(devices.readers, usedReader)
  local readerDeuterium = pickByKeywords(devices.readers, { "deuterium", "tank_d", "tankd" }, usedReader) or pickUnused(devices.readers, usedReader)
  local readerAux = pickByKeywords(devices.readers, { "aux", "inventory", "inv" }, usedReader) or pickUnused(devices.readers, usedReader)

  return {
    monitor = monitorName,
    -- La preference backend reste sur "auto" tant que l'utilisateur n'a pas choisi.
    displayBackend = nil,
    reactorController = reactorController,
    logicAdapter = logicAdapter,
    laser = laser,
    induction = induction,
    relayLaser = relayLaser,
    relayTritium = relayTritium,
    relayDeuterium = relayDeuterium,
    relayDTFuel = relayDTFuel,
    readerTritium = readerTritium,
    readerDeuterium = readerDeuterium,
    readerAux = readerAux,
  }
end

local function runMonitorTest(name)
  if not name then return false, "Display non configure" end
  local obj = safePeripheral(name)
  if not obj then return false, "Display introuvable" end
  local scale = tonumber(state.monitorScale) or 0.5
  if scale < 0.5 then scale = 0.5 end
  if scale > 5 then scale = 5 end

  local candidate = normalizeDisplayCandidate(name, obj)
  if not candidate then return false, "Display non compatible" end

  local surface, meta = DisplayBackend.createSurface(candidate, { monitorScale = scale })
  surface = surface or obj
  if candidate.backend == "cc_monitor" and type(obj.setTextScale) == "function" then
    pcall(obj.setTextScale, scale)
  end

  local ok = pcall(function()
    surface.setBackgroundColor(colors.blue)
    surface.setTextColor(colors.white)
    surface.clear()
    surface.setCursorPos(2, 2)
    surface.write("Fusion installer: display test")
    surface.setCursorPos(2, 4)
    surface.write("Touch this display now")
    if type(surface.flush) == "function" then
      surface.flush()
    elseif type(surface.sync) == "function" then
      surface.sync()
    end
  end)

  if not ok then return false, "Echec ecriture display" end
  local expectedTouch = (meta and meta.touchEvent) or candidate.touchEvent or "monitor_touch"
  local timer = os.startTimer(5)
  while true do
    local ev, p1 = os.pullEvent()
    if (ev == expectedTouch or ev == "monitor_touch" or ev == "tm_monitor_touch") and p1 == name then
      return true, "Touch display detecte"
    end
    if ev == "timer" and p1 == timer then
      return true, "Display visible (pas de touch detecte)"
    end
  end
end

local function runRelayTest(relayName, side)
  if not relayName then return false, "Relay non configure" end
  local relay = peripheral.wrap(relayName)
  if not relay or type(relay.setOutput) ~= "function" then
    return false, "Relay introuvable"
  end

  local ok, err = pcall(function()
    relay.setOutput(side, true)
    sleep(0.2)
    relay.setOutput(side, false)
  end)

  if not ok then return false, "Test relais echoue: " .. tostring(err) end
  return true, "Pulse envoye sur " .. relayName .. "." .. side
end

local function runReaderTest(readerName)
  if not readerName then return false, "Reader non configure" end
  local reader = peripheral.wrap(readerName)
  if not reader then return false, "Reader introuvable" end

  local methods = peripheral.getMethods(readerName) or {}
  if #methods == 0 then return false, "Aucune methode reader" end
  return true, "Reader disponible (" .. tostring(#methods) .. " methodes)"
end

local function runDevicePresenceTest(name)
  if not name then return false, "Non configure" end
  if peripheral.isPresent(name) then return true, "Present" end
  return false, "Manquant"
end

local function serializeValue(value, indent)
  indent = indent or 0
  local sp = string.rep("  ", indent)
  local sp2 = string.rep("  ", indent + 1)

  if type(value) == "table" then
    local keys = {}
    for k in pairs(value) do table.insert(keys, k) end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)

    local parts = { "{" }
    for _, key in ipairs(keys) do
      local encodedKey
      if type(key) == "string" and key:match("^[%a_][%w_]*$") then
        encodedKey = key
      else
        encodedKey = "[" .. string.format("%q", tostring(key)) .. "]"
      end
      local encodedValue = serializeValue(value[key], indent + 1)
      table.insert(parts, string.format("\n%s%s = %s,", sp2, encodedKey, encodedValue))
    end
    if #keys > 0 then table.insert(parts, "\n" .. sp) end
    table.insert(parts, "}")
    return table.concat(parts)
  end

  if type(value) == "string" then return string.format("%q", value) end
  return tostring(value)
end

local function writeConfig(config)
  local h = fs.open(CONFIG_FILE, "w")
  if not h then return false, "Impossible d ecrire " .. CONFIG_FILE end
  h.write("return ")
  h.write(serializeValue(config, 0))
  h.write("\n")
  h.close()
  return true
end

local function ensureVersionFile()
  if fs.exists(VERSION_FILE) then return end
  local h = fs.open(VERSION_FILE, "w")
  if h then
    h.write(DEFAULT_VERSION .. "\n")
    h.close()
  end
end

local function sanitizeConfigString(value, fallback)
  if CoreConfig and type(CoreConfig.sanitizeDeviceName) == "function" then
    return CoreConfig.sanitizeDeviceName(value, fallback)
  end
  if value == nil then return fallback end
  if type(value) ~= "string" then return fallback end
  local trimmed = value:gsub("^%s+", ""):gsub("%s+$", "")
  if trimmed == "" then return nil end
  return trimmed
end

local function sanitizeConfigSide(value, fallback)
  if CoreConfig and type(CoreConfig.sanitizeRelaySide) == "function" then
    return CoreConfig.sanitizeRelaySide(value, fallback)
  end
  local side = tostring(value or "")
  for _, known in ipairs(SIDES) do
    if side == known then return side end
  end
  return fallback
end

local function sanitizeConfigOutput(value, fallback)
  if CoreConfig and type(CoreConfig.sanitizeDisplayOutput) == "function" then
    return CoreConfig.sanitizeDisplayOutput(value, fallback)
  end
  local raw = string.lower(tostring(value or ""))
  if raw == "terminal" or raw == "monitor" or raw == "both" then
    return raw
  end
  return fallback
end

local function sanitizeConfigBackend(value, fallback)
  if CoreConfig and type(CoreConfig.sanitizeDisplayBackend) == "function" then
    return CoreConfig.sanitizeDisplayBackend(value, fallback)
  end
  local raw = string.lower(tostring(value or ""))
  if raw == "auto" or raw == "cc_monitor" or raw == "toms_gpu" then
    return raw
  end
  return fallback
end

local function sanitizeMonitorScaleLocal(value, fallback)
  local numeric = tonumber(value)
  if numeric == nil then
    numeric = tonumber(fallback) or 0.5
  end
  if numeric < 0.5 then return 0.5 end
  if numeric > 5 then return 5 end
  return numeric
end

local function loadExistingConfig()
  if not fs.exists(CONFIG_FILE) or fs.isDir(CONFIG_FILE) then
    return nil, "missing"
  end
  local ok, cfg = pcall(dofile, CONFIG_FILE)
  if not ok or type(cfg) ~= "table" then
    return nil, "invalid"
  end
  return cfg, nil
end

local function applyExistingConfig(cfg)
  if type(cfg) ~= "table" then return false end

  state.setupName = tostring(cfg.setupName or state.setupName)
  state.monitorScale = sanitizeMonitorScaleLocal((cfg.monitor and cfg.monitor.scale), state.monitorScale)
  state.outputMode = sanitizeConfigOutput(cfg.ui and cfg.ui.output, state.outputMode)
  state.selected.displayBackend = sanitizeConfigBackend(cfg.ui and cfg.ui.displayBackend, state.selected.displayBackend)
  if CoreConfig and type(CoreConfig.sanitizeLaserCount) == "function" then
    state.laserCount = CoreConfig.sanitizeLaserCount(cfg.ui and cfg.ui.laserCount, state.laserCount)
  end
  state.preferredView = tostring((cfg.ui and cfg.ui.preferredView) or state.preferredView)

  state.selected.monitor = sanitizeConfigString(cfg.monitor and cfg.monitor.name, state.selected.monitor)
  state.selected.reactorController = sanitizeConfigString(cfg.devices and cfg.devices.reactorController, state.selected.reactorController)
  state.selected.logicAdapter = sanitizeConfigString(cfg.devices and cfg.devices.logicAdapter, state.selected.logicAdapter)
  state.selected.laser = sanitizeConfigString(cfg.devices and cfg.devices.laser, state.selected.laser)
  state.selected.induction = sanitizeConfigString(cfg.devices and cfg.devices.induction, state.selected.induction)

  state.selected.relayLaser = sanitizeConfigString(cfg.relays and cfg.relays.laser and cfg.relays.laser.name, state.selected.relayLaser)
  state.selected.relayLaserSide = sanitizeConfigSide(cfg.relays and cfg.relays.laser and cfg.relays.laser.side, state.selected.relayLaserSide)
  state.selected.relayTritium = sanitizeConfigString(cfg.relays and cfg.relays.tritium and cfg.relays.tritium.name, state.selected.relayTritium)
  state.selected.relayTritiumSide = sanitizeConfigSide(cfg.relays and cfg.relays.tritium and cfg.relays.tritium.side, state.selected.relayTritiumSide)
  state.selected.relayDeuterium = sanitizeConfigString(cfg.relays and cfg.relays.deuterium and cfg.relays.deuterium.name, state.selected.relayDeuterium)
  state.selected.relayDeuteriumSide = sanitizeConfigSide(cfg.relays and cfg.relays.deuterium and cfg.relays.deuterium.side, state.selected.relayDeuteriumSide)

  local dtRelayName = sanitizeConfigString(
    (cfg.actions and cfg.actions.dt_fuel and cfg.actions.dt_fuel.relay)
      or (cfg.relays and cfg.relays.dtFuel and cfg.relays.dtFuel.name),
    state.selected.relayDTFuel
  )
  local dtRelaySide = sanitizeConfigSide(
    (cfg.actions and cfg.actions.dt_fuel and cfg.actions.dt_fuel.side)
      or (cfg.relays and cfg.relays.dtFuel and cfg.relays.dtFuel.side),
    state.selected.relayDTFuelSide
  )
  state.selected.relayDTFuel = dtRelayName
  state.selected.relayDTFuelSide = dtRelaySide

  state.selected.readerTritium = sanitizeConfigString(cfg.readers and cfg.readers.tritium, state.selected.readerTritium)
  state.selected.readerDeuterium = sanitizeConfigString(cfg.readers and cfg.readers.deuterium, state.selected.readerDeuterium)
  state.selected.readerAux = sanitizeConfigString(cfg.readers and cfg.readers.aux, state.selected.readerAux)

  return true
end

state = {
  step = 1,
  running = true,
  devices = gatherPeripherals(),
  suggested = nil,
  status = "Bienvenue dans l assistant d installation Fusion.",
  setupName = "Fusion ViperCraft",
  uiScale = 1.0,
  outputMode = "monitor",
  energyUnit = "j",
  laserCount = 1,
  monitorScale = 0.5,
  monitorTouchEvent = "monitor_touch",
  monitorTouchMapper = nil,
  preferredView = "SUP",
  touchEnabled = true,
  uiOnMonitor = false,
  monitorScroll = 0,
  roleScroll = 0,
  relayScroll = { laser = 0, tritium = 0, deuterium = 0, dtFuel = 0 },
  readerScroll = 0,
  activeRole = "reactorController",
  activeRelay = "laser",
  activeReaderRole = "tritium",
  tests = {},
  selected = {
    monitor = nil,
    reactorController = nil,
    logicAdapter = nil,
    laser = nil,
    induction = nil,
    displayBackend = "auto",
    relayLaser = nil,
    relayLaserSide = "top",
    relayTritium = nil,
    relayTritiumSide = "front",
    relayDeuterium = nil,
    relayDeuteriumSide = "front",
    relayDTFuel = nil,
    relayDTFuelSide = "front",
    readerTritium = nil,
    readerDeuterium = nil,
    readerAux = nil,
  },
}
local existingConfig = loadExistingConfig()
if existingConfig then
  applyExistingConfig(existingConfig)
end
state.suggested = listCandidates(state.devices)
for k, v in pairs(state.suggested) do
  if state.selected[k] == nil and v ~= nil then
    state.selected[k] = v
  end
end

local hitboxes = { term = {}, monitor = {} }
local nativeTerm = term.current()
local currentSource = "term"
local currentSurface = nativeTerm


local function sanitizeUiText(text)
  local value = tostring(text or "")
  value = value:gsub("[^\r\n\t\032-\126]", "")
  return value
end

local function clearHitboxes(source)
  hitboxes[source] = {}
end

local function addHitbox(source, id, x1, y1, x2, y2, action)
  table.insert(hitboxes[source], {
    id = id,
    x1 = math.min(x1, x2),
    y1 = math.min(y1, y2),
    x2 = math.max(x1, x2),
    y2 = math.max(y1, y2),
    action = action,
  })
end

local function handleClick(x, y, source)
  local list = hitboxes[source] or {}
  for i = #list, 1, -1 do
    local hb = list[i]
    if x >= hb.x1 and x <= hb.x2 and y >= hb.y1 and y <= hb.y2 then
      if hb.action then hb.action(hb.id) end
      return true
    end
  end
  return false
end

local function withSurface(fn)
  local previous = term.current()
  term.redirect(currentSurface)
  fn()
  term.redirect(previous)
end

local function drawText(x, y, text, fg, bg)
  local w, h = currentSurface.getSize()
  if y < 1 or y > h then return end
  local safeText = sanitizeUiText(text)
  if #safeText == 0 then return end

  local sx = x
  local visible = safeText
  if sx < 1 then
    local cut = 1 - sx
    if cut >= #visible then return end
    visible = visible:sub(cut + 1)
    sx = 1
  end
  if sx > w then return end
  if sx + #visible - 1 > w then
    visible = visible:sub(1, w - sx + 1)
  end
  if #visible == 0 then return end

  currentSurface.setCursorPos(sx, y)
  if bg then currentSurface.setBackgroundColor(bg) end
  if fg then currentSurface.setTextColor(fg) end
  currentSurface.write(visible)
end

local function fitText(text, maxWidth)
  local value = sanitizeUiText(text)
  if maxWidth <= 0 then return "" end
  if #value <= maxWidth then return value end
  if maxWidth <= 3 then return value:sub(1, maxWidth) end
  return value:sub(1, maxWidth - 3) .. "..."
end

local function fillRect(x1, y1, x2, y2, bg)
  local w, h = currentSurface.getSize()
  local xa = math.max(1, math.min(x1, x2))
  local xb = math.min(w, math.max(x1, x2))
  local ya = math.max(1, math.min(y1, y2))
  local yb = math.min(h, math.max(y1, y2))
  if xa > xb or ya > yb then return end
  currentSurface.setBackgroundColor(bg)
  for y = ya, yb do
    currentSurface.setCursorPos(xa, y)
    currentSurface.write(string.rep(" ", math.max(0, xb - xa + 1)))
  end
end

local function buttonColors(kind, pressed)
  if kind == "primary" then
    return pressed and colors.blue or colors.cyan, colors.white, colors.lightBlue
  elseif kind == "danger" then
    return pressed and colors.red or colors.orange, colors.white, colors.red
  end
  return pressed and colors.gray or colors.lightGray, colors.black, colors.gray
end

local function computeLayout(w, h)
  local compact = w < 56 or h < 22
  local large = w >= 90 and h >= 30
  local marginX = compact and 2 or 3
  local contentTop = 5
  local footerHeight = compact and 4 or 3
  local navY = math.max(contentTop + 4, h - footerHeight - 3)

  return {
    compact = compact,
    large = large,
    marginX = marginX,
    contentTop = contentTop,
    contentBottom = navY - 1,
    navY = navY,
    footerHeight = footerHeight,
    listTop = contentTop + 2,
  }
end

local function isCompactLayout(layout)
  return layout.compact
end

local function isLargeLayout(layout)
  return layout.large
end

local drawButton

local function drawButtonRow(source, y, defs, left, right, gap)
  local count = #defs
  if count == 0 then return 0 end
  local space = right - left + 1
  if space < 6 then return 0 end

  local rows = {}
  local idx = 1
  while idx <= count do
    local row = {}
    local used = 0
    while idx <= count do
      local def = defs[idx]
      local minW = math.max(6, #(sanitizeUiText(def.label or "")) + 2)
      local nextUsed = used + ((#row > 0) and gap or 0) + minW
      if #row > 0 and nextUsed > space then break end
      row[#row + 1] = { def = def, minW = minW }
      used = nextUsed
      idx = idx + 1
    end
    if #row == 0 then
      local def = defs[idx]
      row[1] = { def = def, minW = math.max(6, space) }
      idx = idx + 1
    end
    rows[#rows + 1] = row
  end

  for rowIndex, row in ipairs(rows) do
    local rowY = y + ((rowIndex - 1) * 3)
    local minTotal = 0
    for _, entry in ipairs(row) do
      minTotal = minTotal + entry.minW
    end
    local totalGap = gap * math.max(0, #row - 1)
    local extra = math.max(0, space - minTotal - totalGap)
    local x = left
    for i, entry in ipairs(row) do
      local stretch = 0
      if extra > 0 then
        local slots = #row - i + 1
        stretch = math.floor(extra / slots)
        extra = extra - stretch
      end
      local width = entry.minW + stretch
      if i == #row then
        width = math.max(6, (right - x + 1))
      end
      local label = fitText(entry.def.label, math.max(1, width - 2))
      drawButton(source, entry.def.id, x, rowY, width, label, entry.def.kind, entry.def.action)
      x = x + width + gap
    end
  end
  return #rows
end

drawButton = function(source, id, x, y, w, label, kind, action)
  local sw, sh = currentSurface.getSize()
  if y > sh or x > sw or (x + w - 1) < 1 or y < 1 then return end
  x = math.max(1, x)
  y = math.max(1, y)
  w = math.min(w, sw - x + 1)
  if w < 4 then return end
  local clipped = fitText(label, w - 2)
  local bg, fg, shade = buttonColors(kind, false)
  fillRect(x, y, x + w - 1, y + 2, shade)
  fillRect(x, y, x + w - 1, y + 1, bg)
  local tx = x + math.floor((w - #clipped) / 2)
  drawText(tx, y + 1, clipped, fg, bg)
  addHitbox(source, id, x, y, x + w - 1, y + 2, function()
    local pbg, pfg = buttonColors(kind, true)
    fillRect(x, y, x + w - 1, y + 2, pbg)
    drawText(tx, y + 1, clipped, pfg, pbg)
    sleep(0.05)
    action()
  end)
end

local function sanitizeScale(v)
  local n = tonumber(v) or 0.5
  if n < 0.5 then n = 0.5 end
  if n > 5 then n = 5 end
  return n
end

local stepTitles = {
  "Accueil",
  "Scan devices",
  "Display backend",
  "Devices principaux",
  "Relays & faces",
  "Readers",
  "Laser count",
  "Tests materiels",
  "Recapitulatif",
}

local function drawSteps(w, layout)
  local txt = string.format("STEP %d/%d - %s", state.step, #stepTitles, stepTitles[state.step])
  fillRect(1, 1, w, 3, colors.gray)
  local title = isLargeLayout(layout) and "Fusion ViperCraft Installer" or "Fusion Installer"
  drawText(2, 1, fitText(title, w - 2), colors.white, colors.gray)
  drawText(2, 2, fitText(txt, w - 2), colors.yellow, colors.gray)
  local hint = isCompactLayout(layout)
    and "Touch: souris/monitor/tm"
    or "Navigation tactile: souris + monitor_touch + tm_monitor_touch"
  drawText(2, 3, fitText(hint, w - 2), colors.white, colors.gray)
end

local function drawFooter(w, h, layout)
  local top = h - layout.footerHeight + 1
  fillRect(1, top, w, h, colors.black)

  local status = fitText(state.status or "", w - 2)
  drawText(2, top + 1, status, colors.lightGray, colors.black)

  if layout.compact then
    drawText(2, top + 2, fitText("Back/Next: naviguer", w - 2), colors.gray, colors.black)
    drawText(2, top + 3, fitText("Click ligne: selectionner", w - 2), colors.gray, colors.black)
  else
    local help = "Back/Next pour naviguer - Cliquer une ligne pour selectionner"
    drawText(2, top + 2, fitText(help, w - 2), colors.gray, colors.black)
  end
end

local function scanNow()
  state.devices = gatherPeripherals()
  state.suggested = listCandidates(state.devices)
  for k, v in pairs(state.suggested) do
    if state.selected[k] == nil and v ~= nil then
      state.selected[k] = v
    end
  end
  if type(state.selected.displayBackend) ~= "string" or state.selected.displayBackend == "" then
    state.selected.displayBackend = "auto"
  end
  if state.selected.displayBackend ~= "auto" then
    local foundBackend = false
    for _, candidate in ipairs(state.devices.displayCandidates) do
      if candidate.backend == state.selected.displayBackend then
        foundBackend = true
        break
      end
    end
    if not foundBackend then
      state.selected.displayBackend = "auto"
    end
  end

  if state.selected.monitor and not state.devices.displayByName[state.selected.monitor] then
    state.selected.monitor = nil
  end
  if not state.selected.monitor and state.suggested.monitor then
    state.selected.monitor = state.suggested.monitor
  end
  state.status = string.format("SCAN COMPLETE - %d DEVICES FOUND", #state.devices.all)
end

local function backendLabel(backend)
  if backend == "toms_gpu" then return "Tom GPU" end
  if backend == "cc_monitor" then return "CC Monitor" end
  return tostring(backend or "auto")
end

local function displayBackendMatches(candidate, preferredBackend)
  if type(candidate) ~= "table" then return false end
  local pref = tostring(preferredBackend or "auto")
  if pref == "auto" then return true end
  return tostring(candidate.backend or "") == pref
end

local function getDisplayCandidatesByPreference()
  local pref = state.selected.displayBackend or "auto"
  local filtered = {}
  for _, candidate in ipairs(state.devices.displayCandidates) do
    if displayBackendMatches(candidate, pref) then
      filtered[#filtered + 1] = candidate
    end
  end
  if #filtered == 0 then
    for _, candidate in ipairs(state.devices.displayCandidates) do
      filtered[#filtered + 1] = candidate
    end
  end
  return filtered
end

local function resolveSelectedDisplayCandidate()
  local preferred = getDisplayCandidatesByPreference()
  if #preferred == 0 then
    return nil
  end

  local selectedName = state.selected.monitor
  if selectedName then
    for _, candidate in ipairs(preferred) do
      if candidate.name == selectedName then
        return candidate
      end
    end
  end

  local fallback = preferred[1]
  state.selected.monitor = fallback.name
  return fallback
end

local function hasDisplayCandidateForBackend(backend)
  local pref = tostring(backend or "auto")
  if pref == "auto" then return true end
  for _, candidate in ipairs(state.devices.displayCandidates) do
    if tostring(candidate.backend or "") == pref then
      return true
    end
  end
  return false
end

local function previewDisplayCandidate()
  local preferred = getDisplayCandidatesByPreference()
  if #preferred == 0 then
    return nil
  end

  local selectedName = state.selected.monitor
  if selectedName then
    for _, candidate in ipairs(preferred) do
      if candidate.name == selectedName then
        return candidate
      end
    end
  end

  return preferred[1]
end

local function createListRows(items, selected, startY, rows, scroll, source, onSelect, x1, x2)
  local w, _ = currentSurface.getSize()
  x1 = x1 or 3
  x2 = x2 or (w - 3)
  fillRect(x1, startY, x2, startY + rows - 1, colors.black)
  for i = 1, rows do
    local idx = scroll + i
    local y = startY + i - 1
    local name = items[idx]
    if name then
      local isSel = selected == name
      local bg = isSel and colors.blue or colors.black
      local fg = isSel and colors.white or colors.lightGray
      fillRect(x1, y, x2, y, bg)
      local ptype = peripheral.getType(name) or "unknown"
      local text = string.format("[%02d] %s (%s)", idx, name, ptype)
      drawText(x1 + 1, y, fitText(text, x2 - x1 - 1), fg, bg)
      addHitbox(source, "row_" .. tostring(idx), x1, y, x2, y, function() onSelect(name) end)
    end
  end
end

local function drawNavigation(source, w, _, layout)
  local y = layout.navY
  local left = layout.marginX
  local right = w - layout.marginX
  local available = right - left + 1
  local dual = state.step > 1 and state.step < #stepTitles
  local gap = dual and 1 or 0
  local btnW = dual and math.max(8, math.floor((available - gap) / 2)) or math.max(8, math.min(14, available))

  if state.step > 1 then
    drawButton(source, "back", left, y, btnW, "BACK", "secondary", function()
      state.step = math.max(1, state.step - 1)
    end)
  end
  if state.step < #stepTitles then
    local nextX = dual and (right - btnW + 1) or left
    drawButton(source, "next", nextX, y, btnW, "NEXT", "primary", function()
      state.step = math.min(#stepTitles, state.step + 1)
    end)
  end
end

local function drawWelcome(source, w, h, layout)
  local left = layout.marginX
  local right = w - layout.marginX
  local panelTop = layout.contentTop
  local panelBottom = layout.contentBottom

  fillRect(left, panelTop, right, panelBottom, colors.black)
  fillRect(left, panelTop, right, panelTop, colors.gray)
  fillRect(left, panelTop + 2, right, panelTop + 2, colors.gray)

  local y = panelTop + 1
  drawText(left + 1, y, fitText("FUSION VIPERCRAFT INSTALLER", right - left - 1), colors.white, colors.gray)
  y = y + 2
  drawText(left + 1, y, fitText("Version " .. DEFAULT_VERSION, right - left - 1), colors.lightGray, colors.black)
  y = y + 2
  drawText(left + 1, y, fitText("Objectif", right - left - 1), colors.white, colors.black)
  y = y + 1
  drawText(left + 2, y, fitText("Configurer rapidement le setup Fusion + peripheriques.", right - left - 3), colors.lightGray, colors.black)
  y = y + 2

  local monitorInfo = state.selected.monitor and ("Monitor: " .. state.selected.monitor) or "Monitor: non selectionne"
  drawText(left + 1, y, fitText("Etat scan", right - left - 1), colors.white, colors.black)
  y = y + 1
  drawText(left + 2, y, fitText("Devices detectes: " .. tostring(#state.devices.all), right - left - 3), colors.lightGray, colors.black)
  y = y + 1
  drawText(left + 2, y, fitText(monitorInfo, right - left - 3), colors.lightGray, colors.black)

  local actionsY = math.max(y + 2, panelBottom - 3)
  drawButtonRow(source, actionsY, {
    { id = "start", label = "START INSTALL", kind = "primary", action = function() state.step = 2 end },
    { id = "rescan", label = "RESCAN", kind = "secondary", action = function() scanNow() end },
    { id = "exit", label = "EXIT", kind = "danger", action = function() state.running = false end },
  }, left + 1, right - 1, layout.compact and 1 or 2)
end

local function drawScan(source, w, h, layout)
  local left = layout.marginX
  local right = w - layout.marginX
  local y = layout.contentTop
  drawText(left, y, fitText(string.format("Total devices: %d", #state.devices.all), w - left * 2), colors.white, colors.black)
  y = y + 2

  local entries = {
    { "Displays", #state.devices.displayCandidates },
    { "CC monitors", state.devices.displayBackends.cc_monitor or 0 },
    { "Tom GPU", state.devices.displayBackends.toms_gpu or 0 },
    { "Relays", #state.devices.relays },
    { "Readers", #state.devices.readers },
    { "Reactor devices", #(state.devices.byType["fusion_reactor_controller"] or {}) + #(state.devices.byType["fusionReactorLogicAdapter"] or {}) },
    { "Induction/Laser", #(state.devices.byType["laser_amplifier"] or {}) + #(state.devices.byType["induction_port"] or {}) },
    { "Modems", #(state.devices.byType["modem"] or {}) },
  }

  for _, e in ipairs(entries) do
    local line = string.format("- %-16s : %d", e[1], e[2])
    drawText(left + 1, y, fitText(line, right - left - 1), colors.lightGray, colors.black)
    y = y + 1
    if y >= layout.navY - 4 then break end
  end

  drawButton(source, "scan", left, layout.navY - 4, math.min(16, right - left + 1), "SCAN", "primary", function() scanNow() end)
end

local function drawMonitorStep(source, w, h, layout)
  local left = layout.marginX
  local right = w - layout.marginX
  local listTop = layout.contentTop + 4
  local canSideScroll = (right - left + 1) >= 30
  local scrollX = right - 8
  local listRight = canSideScroll and (scrollX - 1) or right
  local displayCandidates = getDisplayCandidatesByPreference()

  drawText(left, layout.contentTop, fitText("Choisissez la surface display principale:", right - left + 1), colors.white, colors.black)
  drawText(left, layout.contentTop + 1, fitText("Terminal + monitor/tm touch restent actifs en parallele.", right - left + 1), colors.lightGray, colors.black)
  local selectedBackend = tostring(state.selected.displayBackend or "auto")
  drawText(left, layout.contentTop + 2, fitText("Backend prefere: " .. string.upper(selectedBackend), right - left + 1), colors.yellow, colors.black)

  local rows = math.max(3, layout.navY - listTop - 10)
  local maxScroll = math.max(0, #displayCandidates - rows)
  if state.monitorScroll > maxScroll then state.monitorScroll = maxScroll end

  fillRect(left, listTop, listRight, listTop + rows - 1, colors.black)
  if #displayCandidates == 0 then
    drawText(left + 1, listTop, fitText("Aucun display compatible detecte (fallback terminal).", listRight - left - 1), colors.orange, colors.black)
  end
  for i = 1, rows do
    local idx = state.monitorScroll + i
    local y = listTop + i - 1
    local candidate = displayCandidates[idx]
    if candidate then
      local isSel = state.selected.monitor == candidate.name
      local bg = isSel and colors.blue or colors.black
      local fg = isSel and colors.white or colors.lightGray
      fillRect(left, y, listRight, y, bg)
      local itemText = string.format("[%02d] %s (%s %dx%d)", idx, candidate.name, backendLabel(candidate.backend), candidate.w or 0, candidate.h or 0)
      drawText(left + 1, y, fitText(itemText, listRight - left - 1), fg, bg)
      addHitbox(source, "display_" .. tostring(idx), left, y, listRight, y, function()
        state.selected.monitor = candidate.name
        state.status = "Display selectionne: " .. candidate.name .. " (" .. backendLabel(candidate.backend) .. ")"
      end)
    end
  end

  if canSideScroll then
    drawButton(source, "mup", scrollX, listTop, 8, "UP", "secondary", function()
      state.monitorScroll = math.max(0, state.monitorScroll - 1)
    end)
    drawButton(source, "mdown", scrollX, listTop + 4, 8, "DOWN", "secondary", function()
      state.monitorScroll = math.min(maxScroll, state.monitorScroll + 1)
    end)
  end

  local settingsY = math.min(layout.navY - 8, listTop + rows + 1)
  local backendDefs = {
    {
      id = "backend_auto",
      label = "B: AUTO",
      kind = selectedBackend == "auto" and "primary" or "secondary",
      action = function()
        state.selected.displayBackend = "auto"
        state.monitorScroll = 0
        local chosen = resolveSelectedDisplayCandidate()
        if chosen then state.selected.monitor = chosen.name end
        state.status = "Backend prefere: AUTO"
      end,
    },
    {
      id = "backend_tom",
      label = "B: TOM GPU",
      kind = selectedBackend == "toms_gpu" and "primary" or "secondary",
      action = function()
        state.selected.displayBackend = "toms_gpu"
        state.monitorScroll = 0
        local chosen = resolveSelectedDisplayCandidate()
        if chosen then state.selected.monitor = chosen.name end
        state.status = "Backend prefere: TOM GPU"
      end,
    },
    {
      id = "backend_cc",
      label = "B: CC MON",
      kind = selectedBackend == "cc_monitor" and "primary" or "secondary",
      action = function()
        state.selected.displayBackend = "cc_monitor"
        state.monitorScroll = 0
        local chosen = resolveSelectedDisplayCandidate()
        if chosen then state.selected.monitor = chosen.name end
        state.status = "Backend prefere: CC MONITOR"
      end,
    },
  }
  drawButtonRow(source, settingsY, backendDefs, left, right, 1)

  local outputDefs = {
    {
      id = "output_terminal",
      label = "OUT TERM",
      kind = state.outputMode == "terminal" and "primary" or "secondary",
      action = function()
        state.outputMode = "terminal"
        state.status = "Sortie UI: TERMINAL"
      end,
    },
    {
      id = "output_monitor",
      label = "OUT MON",
      kind = state.outputMode == "monitor" and "primary" or "secondary",
      action = function()
        state.outputMode = "monitor"
        state.status = "Sortie UI: MONITOR"
      end,
    },
    {
      id = "output_both",
      label = "OUT BOTH",
      kind = state.outputMode == "both" and "primary" or "secondary",
      action = function()
        state.outputMode = "both"
        state.status = "Sortie UI: BOTH"
      end,
    },
  }
  drawButtonRow(source, settingsY + 3, outputDefs, left, right, 1)

  drawButtonRow(source, layout.navY - 4, {
    { id = "test_monitor", label = "TEST MONITOR", kind = "primary", action = function()
      local ok, msg = runMonitorTest(state.selected.monitor)
      state.tests.monitor = { ok = ok, msg = msg }
      state.status = (ok and "OK: " or "FAIL: ") .. msg
    end },
    { id = "toggle_surface", label = state.uiOnMonitor and "MONITOR UI OFF" or "MONITOR UI ON", kind = "secondary", action = function()
      if state.uiOnMonitor then
        state.uiOnMonitor = false
        state.monitorTouchEvent = "monitor_touch"
        state.monitorTouchMapper = nil
        state.status = "Affichage revenu sur terminal."
        return
      end
      local candidate = resolveSelectedDisplayCandidate()
      if not candidate then
        state.status = "Aucune surface display compatible detectee."
        return
      end
      state.selected.monitor = candidate.name
      state.uiOnMonitor = true
      state.status = "UI active sur display + terminal (" .. backendLabel(candidate.backend) .. ")."
    end },
  }, left, right, layout.compact and 1 or 2)
end

local function currentRoleValue()
  if state.activeRole == "reactorController" then return state.selected.reactorController end
  if state.activeRole == "logicAdapter" then return state.selected.logicAdapter end
  if state.activeRole == "laser" then return state.selected.laser end
  return state.selected.induction
end

local function setCurrentRole(name)
  if state.activeRole == "reactorController" then state.selected.reactorController = name
  elseif state.activeRole == "logicAdapter" then state.selected.logicAdapter = name
  elseif state.activeRole == "laser" then state.selected.laser = name
  else state.selected.induction = name end
end

local function drawCoreDevices(source, w, h, layout)
  local left = layout.marginX
  local right = w - layout.marginX
  local canSideScroll = (right - left + 1) >= 30
  local scrollX = right - 8
  local listRight = canSideScroll and (scrollX - 1) or right
  drawText(left, layout.contentTop, fitText("Choisissez un role puis cliquez un device.", right - left + 1), colors.white, colors.black)

  local roles = {
    { "reactorController", "Reactor Ctrl" },
    { "logicAdapter", "Logic Adapter" },
    { "laser", "Laser" },
    { "induction", "Induction" },
  }

  local defs = {}
  for _, r in ipairs(roles) do
    local active = state.activeRole == r[1]
    table.insert(defs, {
      id = "role_" .. r[1],
      label = active and ("> " .. r[2]) or r[2],
      kind = active and "primary" or "secondary",
      action = function() state.activeRole = r[1] end,
    })
  end
  drawButtonRow(source, layout.contentTop + 2, defs, left, right, 1)

  local listTop = layout.contentTop + 6
  local rows = math.max(3, layout.navY - listTop - 1)
  local maxScroll = math.max(0, #state.devices.all - rows)
  if state.roleScroll > maxScroll then state.roleScroll = maxScroll end

  createListRows(state.devices.all, currentRoleValue(), listTop, rows, state.roleScroll, source, function(name)
    setCurrentRole(name)
    state.status = "Assignation " .. state.activeRole .. " -> " .. name
  end, left, listRight)

  if canSideScroll then
    drawButton(source, "rup", scrollX, listTop, 8, "UP", "secondary", function() state.roleScroll = math.max(0, state.roleScroll - 1) end)
    drawButton(source, "rdown", scrollX, listTop + 4, 8, "DOWN", "secondary", function() state.roleScroll = math.min(maxScroll, state.roleScroll + 1) end)
  end
end

local relayRoleMap = {
  laser = { key = "relayLaser", side = "relayLaserSide", label = "Relay LAS" },
  tritium = { key = "relayTritium", side = "relayTritiumSide", label = "Relay T" },
  deuterium = { key = "relayDeuterium", side = "relayDeuteriumSide", label = "Relay D" },
  dtFuel = { key = "relayDTFuel", side = "relayDTFuelSide", label = "Relay DT-FUEL" },
}

local function drawRelays(source, w, h, layout)
  local left = layout.marginX
  local right = w - layout.marginX
  local canSideScroll = (right - left + 1) >= 30
  local scrollX = right - 8
  local listRight = canSideScroll and (scrollX - 1) or right

  local roleDefs = {}
  for _, role in ipairs({ "laser", "tritium", "deuterium", "dtFuel" }) do
    local active = state.activeRelay == role
    table.insert(roleDefs, {
      id = "relay_role_" .. role,
      label = active and ("> " .. relayRoleMap[role].label) or relayRoleMap[role].label,
      kind = active and "primary" or "secondary",
      action = function() state.activeRelay = role end,
    })
  end
  drawButtonRow(source, layout.contentTop, roleDefs, left, right, 1)

  local meta = relayRoleMap[state.activeRelay]
  local selectedRelay = state.selected[meta.key]
  local listTop = layout.contentTop + 4
  local rows = math.max(3, layout.navY - listTop - 6)
  local maxScroll = math.max(0, #state.devices.relays - rows)
  local scroll = state.relayScroll[state.activeRelay]
  if scroll > maxScroll then scroll = maxScroll end
  state.relayScroll[state.activeRelay] = scroll

  drawText(left, listTop - 1, fitText("Selection relay:", right - left + 1), colors.white, colors.black)
  createListRows(state.devices.relays, selectedRelay, listTop, rows, scroll, source, function(name)
    state.selected[meta.key] = name
    state.status = meta.label .. " -> " .. name
  end, left, listRight)

  if canSideScroll then
    drawButton(source, "lup", scrollX, listTop, 8, "UP", "secondary", function()
      state.relayScroll[state.activeRelay] = math.max(0, state.relayScroll[state.activeRelay] - 1)
    end)
    drawButton(source, "ldown", scrollX, listTop + 4, 8, "DOWN", "secondary", function()
      state.relayScroll[state.activeRelay] = math.min(maxScroll, state.relayScroll[state.activeRelay] + 1)
    end)
  end

  local sideY = math.max(listTop + rows + 1, layout.navY - 8)
  local latestSideY = layout.navY - 7
  if sideY > latestSideY then
    sideY = latestSideY
  end
  if sideY >= listTop then
    drawText(left, sideY - 1, fitText("Selection face:", right - left + 1), colors.white, colors.black)
    local sideDefs = {}
    for _, side in ipairs(SIDES) do
      local selectedSide = state.selected[meta.side] == side
      table.insert(sideDefs, {
        id = "side_" .. side,
        label = side:upper(),
        kind = selectedSide and "primary" or "secondary",
        action = function() state.selected[meta.side] = side end,
      })
    end
    drawButtonRow(source, sideY, sideDefs, left, right, 1)
  end

  drawButton(source, "test_relay", left, layout.navY - 4, math.min(18, right - left + 1), "TEST RELAY", "primary", function()
    local ok, msg = runRelayTest(state.selected[meta.key], state.selected[meta.side])
    state.tests[meta.key] = { ok = ok, msg = msg }
    state.status = (ok and "OK: " or "FAIL: ") .. msg
  end)
end

local readerRoleMap = {
  tritium = { key = "readerTritium", label = "Reader T" },
  deuterium = { key = "readerDeuterium", label = "Reader D" },
  aux = { key = "readerAux", label = "Reader Aux" },
}

local function drawReaders(source, w, h, layout)
  local left = layout.marginX
  local right = w - layout.marginX
  local canSideScroll = (right - left + 1) >= 30
  local scrollX = right - 8
  local listRight = canSideScroll and (scrollX - 1) or right

  local roleDefs = {}
  for _, role in ipairs({ "tritium", "deuterium", "aux" }) do
    local active = state.activeReaderRole == role
    table.insert(roleDefs, {
      id = "reader_role_" .. role,
      label = active and ("> " .. readerRoleMap[role].label) or readerRoleMap[role].label,
      kind = active and "primary" or "secondary",
      action = function() state.activeReaderRole = role end,
    })
  end
  drawButtonRow(source, layout.contentTop, roleDefs, left, right, 1)

  local meta = readerRoleMap[state.activeReaderRole]
  local listTop = layout.contentTop + 4
  local rows = math.max(3, layout.navY - listTop - 1)
  local maxScroll = math.max(0, #state.devices.readers - rows)
  if state.readerScroll > maxScroll then state.readerScroll = maxScroll end

  createListRows(state.devices.readers, state.selected[meta.key], listTop, rows, state.readerScroll, source, function(name)
    state.selected[meta.key] = name
    state.status = meta.label .. " -> " .. name
  end, left, listRight)

  if canSideScroll then
    drawButton(source, "reader_up", scrollX, listTop, 8, "UP", "secondary", function() state.readerScroll = math.max(0, state.readerScroll - 1) end)
    drawButton(source, "reader_down", scrollX, listTop + 4, 8, "DOWN", "secondary", function() state.readerScroll = math.min(maxScroll, state.readerScroll + 1) end)
  end
end

local LASER_COUNT_MIN = 1
local LASER_COUNT_MAX = 8
local LASER_COUNT_OPTIONS = { 1, 2, 3, 4, 6, 8 }

local function setLaserCount(value, sourceLabel)
  local numeric = tonumber(value)
  if numeric == nil then
    state.status = "Laser count invalide: nombre requis."
    return false
  end

  numeric = math.floor(numeric + 0.5)
  if numeric < LASER_COUNT_MIN or numeric > LASER_COUNT_MAX then
    state.status = string.format(
      "Laser count invalide: plage %d-%d.",
      LASER_COUNT_MIN,
      LASER_COUNT_MAX
    )
    return false
  end

  state.laserCount = CoreConfig.sanitizeLaserCount(numeric, state.laserCount or LASER_COUNT_MIN)
  state.status = "Laser count " .. tostring(sourceLabel or "set") .. ": " .. tostring(state.laserCount)
  return true
end

local function promptLaserCountInput()
  local previous = term.current()
  term.redirect(nativeTerm)
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)
  print("LASER COUNT INPUT")
  print(string.format("Enter a value between %d and %d.", LASER_COUNT_MIN, LASER_COUNT_MAX))
  print("Current value: " .. tostring(state.laserCount))
  write("> ")
  local raw = read()
  term.redirect(previous)

  local entry = sanitizeUiText(raw or "")
  if entry == "" then
    state.status = "Laser count invalide: entree vide."
    return
  end
  setLaserCount(entry, "manuel")
end

local function drawLaserCountStep(source, w, h, layout)
  local left = layout.marginX
  local right = w - layout.marginX
  local panelTop = layout.contentTop
  local panelBottom = layout.contentBottom
  local titleW = right - left + 1

  fillRect(left, panelTop, right, panelBottom, colors.black)
  drawText(left, panelTop, fitText("Choisissez le nombre de lasers:", titleW), colors.white, colors.black)
  drawText(left + 1, panelTop + 2, fitText("Valeur active: " .. tostring(state.laserCount), titleW - 1), colors.yellow, colors.black)
  drawText(left + 1, panelTop + 3, fitText("Selection rapide + saisie manuelle.", titleW - 1), colors.lightGray, colors.black)

  local defs = {}
  for _, value in ipairs(LASER_COUNT_OPTIONS) do
    local active = tonumber(state.laserCount) == value
      table.insert(defs, {
        id = "laser_count_" .. tostring(value),
        label = tostring(value),
        kind = active and "primary" or "secondary",
        action = function()
          setLaserCount(value, "choisi")
        end,
      })
  end

  local rowY = panelTop + 6
  local rowsUsed = 0
  if rowY <= panelBottom - 1 then
    rowsUsed = drawButtonRow(source, rowY, defs, left + 1, right - 1, layout.compact and 1 or 2)
  end

  local inputY = rowY + (rowsUsed * 3) + 1
  if inputY > panelBottom - 1 then
    inputY = math.max(panelTop + 4, panelBottom - 2)
  end
  if inputY <= panelBottom - 1 then
    drawButtonRow(source, inputY, {
      {
        id = "laser_count_input",
        label = "INPUT VALUE",
        kind = "primary",
        action = function()
          promptLaserCountInput()
        end,
      },
    }, left + 1, right - 1, 1)
  end

  local hintY = math.min(panelBottom - 1, inputY + 3)
  if hintY > panelTop then
    drawText(
      left + 1,
      hintY,
      fitText(
        string.format("Range: %d-%d | Quick: 1,2,3,4,6,8", LASER_COUNT_MIN, LASER_COUNT_MAX),
        titleW - 1
      ),
      colors.gray,
      colors.black
    )
  end
end

local function runNamedTest(id)
  local ok, msg = false, ""
  if id == "monitor" then
    ok, msg = runMonitorTest(state.selected.monitor)
  elseif id == "display" then
    local preferredBackend = tostring(state.selected.displayBackend or "auto")
    local preferredAvailable = hasDisplayCandidateForBackend(preferredBackend)
    local candidate = resolveSelectedDisplayCandidate()
    if not candidate then
      ok, msg = false, "Aucun display compatible"
    elseif preferredBackend ~= "auto" and not preferredAvailable then
      ok, msg = true, "Backend " .. backendLabel(preferredBackend) .. " indisponible, fallback " .. candidate.name
    else
      ok, msg = true, "Display valide: " .. candidate.name .. " (" .. backendLabel(candidate.backend) .. ")"
    end
  elseif id == "relayLaser" then
    ok, msg = runRelayTest(state.selected.relayLaser, state.selected.relayLaserSide)
  elseif id == "relayTritium" then
    ok, msg = runRelayTest(state.selected.relayTritium, state.selected.relayTritiumSide)
  elseif id == "relayDeuterium" then
    ok, msg = runRelayTest(state.selected.relayDeuterium, state.selected.relayDeuteriumSide)
  elseif id == "relayDTFuel" then
    ok, msg = runRelayTest(state.selected.relayDTFuel, state.selected.relayDTFuelSide)
  elseif id == "readerTritium" then
    ok, msg = runReaderTest(state.selected.readerTritium)
  elseif id == "readerDeuterium" then
    ok, msg = runReaderTest(state.selected.readerDeuterium)
  elseif id == "laser" then
    ok, msg = runDevicePresenceTest(state.selected.laser)
  elseif id == "induction" then
    ok, msg = runDevicePresenceTest(state.selected.induction)
  end
  state.tests[id] = { ok = ok, msg = msg }
  state.status = (ok and "OK: " or "FAIL: ") .. msg
end

local function drawTests(source, w, h, layout)
  local tests = {
    { "display", "TEST DISPLAY CFG" },
    { "monitor", "TEST MONITOR" },
    { "relayLaser", "TEST RELAY LAS" },
    { "relayTritium", "TEST RELAY T" },
    { "relayDeuterium", "TEST RELAY D" },
    { "relayDTFuel", "TEST RELAY DT" },
    { "readerTritium", "TEST READER T" },
    { "readerDeuterium", "TEST READER D" },
    { "laser", "TEST LASER" },
    { "induction", "TEST INDUCTION" },
  }

  local left = layout.marginX
  local right = w - layout.marginX
  local statusX = math.min(right, left + (layout.compact and 16 or 22))
  local buttonW = math.max(14, statusX - left - 1)
  local y = layout.contentTop

  for _, t in ipairs(tests) do
    if y + 2 > layout.navY - 1 then break end
    drawButton(source, "test_" .. t[1], left, y, buttonW, t[2], "primary", function() runNamedTest(t[1]) end)
    local status = state.tests[t[1]] and (state.tests[t[1]].ok and "OK" or "FAIL") or "PENDING"
    local color = status == "OK" and colors.lime or (status == "FAIL" and colors.red or colors.gray)
    drawText(statusX + 1, y + 1, fitText(status, right - statusX), color, colors.black)
    y = y + 4
  end
end
local function buildConfig()
  local displayBackend = sanitizeConfigBackend(state.selected.displayBackend, "auto")
  local dtFuelAction = nil
  if sanitizeConfigString(state.selected.relayDTFuel, nil) then
    dtFuelAction = {
      relay = state.selected.relayDTFuel,
      side = sanitizeConfigSide(state.selected.relayDTFuelSide, "front"),
    }
  end

  return {
    configVersion = 1,
    setupName = state.setupName,
    monitor = {
      name = state.selected.monitor,
      scale = sanitizeScale(state.monitorScale),
    },
    devices = {
      reactorController = state.selected.reactorController,
      logicAdapter = state.selected.logicAdapter,
      laser = state.selected.laser,
      induction = state.selected.induction,
    },
    relays = {
      laser = { name = state.selected.relayLaser, side = state.selected.relayLaserSide },
      tritium = { name = state.selected.relayTritium, side = state.selected.relayTritiumSide },
      deuterium = { name = state.selected.relayDeuterium, side = state.selected.relayDeuteriumSide },
      dtFuel = { name = state.selected.relayDTFuel, side = state.selected.relayDTFuelSide },
    },
    actions = {
      dt_fuel = dtFuelAction,
    },
    readers = {
      tritium = state.selected.readerTritium,
      deuterium = state.selected.readerDeuterium,
      aux = state.selected.readerAux,
    },
    ui = {
      preferredView = state.preferredView,
      scale = state.uiScale,
      output = state.outputMode,
      displayBackend = displayBackend,
      energyUnit = state.energyUnit,
      laserCount = state.laserCount,
      touchEnabled = state.touchEnabled,
      refreshDelay = 0.20,
    },
    update = {
      enabled = true,
    },
  }
end

local function validateBuiltConfig(config)
  local ok, errors = CoreConfig.validateConfig(config)
  if ok then return true, nil end
  return false, table.concat(errors, "; ")
end

local function drawSummary(source, w, h, layout)
  local left = layout.marginX
  local right = w - layout.marginX
  local previewDisplay = previewDisplayCandidate()
  local displayTarget = previewDisplay
    and (previewDisplay.name .. " (" .. backendLabel(previewDisplay.backend) .. ")")
    or "terminal fallback"
  local lines = {
    "Monitor: " .. tostring(state.selected.monitor),
    "Display backend: " .. tostring(state.selected.displayBackend or "auto"),
    "Display target: " .. tostring(displayTarget),
    "Display output: " .. tostring(state.outputMode),
    "Laser count: " .. tostring(state.laserCount),
    "Reactor controller: " .. tostring(state.selected.reactorController),
    "Logic adapter: " .. tostring(state.selected.logicAdapter),
    "Laser: " .. tostring(state.selected.laser),
    "Induction: " .. tostring(state.selected.induction),
    "Relay LAS: " .. tostring(state.selected.relayLaser) .. " / " .. tostring(state.selected.relayLaserSide),
    "Relay T: " .. tostring(state.selected.relayTritium) .. " / " .. tostring(state.selected.relayTritiumSide),
    "Relay D: " .. tostring(state.selected.relayDeuterium) .. " / " .. tostring(state.selected.relayDeuteriumSide),
    "Relay DT-FUEL: " .. tostring(state.selected.relayDTFuel) .. " / " .. tostring(state.selected.relayDTFuelSide),
    "Action DT-FUEL: " .. tostring(state.selected.relayDTFuel) .. " / " .. tostring(state.selected.relayDTFuelSide),
    "Reader T: " .. tostring(state.selected.readerTritium),
    "Reader D: " .. tostring(state.selected.readerDeuterium),
    "Reader Aux: " .. tostring(state.selected.readerAux),
  }

  local y = layout.contentTop
  for _, line in ipairs(lines) do
    drawText(left, y, fitText(line, right - left + 1), colors.lightGray, colors.black)
    y = y + 1
    if y > layout.navY - 5 then break end
  end

  drawButtonRow(source, layout.navY - 4, {
    { id = "save", label = "SAVE CONFIG", kind = "primary", action = function()
      local config = buildConfig()
      local valid, validationErr = validateBuiltConfig(config)
      if not valid then
        state.status = "Config incomplete: " .. tostring(validationErr)
        return
      end

      local ok, err = writeConfig(config)
      if not ok then
        state.status = "Erreur sauvegarde: " .. tostring(err)
        return
      end
      ensureVersionFile()
      state.status = "CONFIG SAVED - INSTALLATION COMPLETE - READY TO LAUNCH"
    end },
    { id = "launch", label = "LAUNCH FUSION", kind = "primary", action = function()
      local config = buildConfig()
      local valid, validationErr = validateBuiltConfig(config)
      if not valid then
        state.status = "Config incomplete: " .. tostring(validationErr)
        return
      end

      local ok, err = writeConfig(config)
      if not ok then
        state.status = "Erreur sauvegarde: " .. tostring(err)
        return
      end

      ensureVersionFile()
      state.running = false
      state.launch = true
    end },
  }, left, right, 2)
end

local function renderOnSurface(source, surface)
  currentSource = source
  currentSurface = surface

  withSurface(function()
    local w, h = currentSurface.getSize()
    clearHitboxes(source)
    currentSurface.setBackgroundColor(colors.black)
    currentSurface.setTextColor(colors.white)
    currentSurface.clear()

    local layout = computeLayout(w, h)

    drawSteps(w, layout)
    if state.step == 1 then drawWelcome(source, w, h, layout)
    elseif state.step == 2 then drawScan(source, w, h, layout)
    elseif state.step == 3 then drawMonitorStep(source, w, h, layout)
    elseif state.step == 4 then drawCoreDevices(source, w, h, layout)
    elseif state.step == 5 then drawRelays(source, w, h, layout)
    elseif state.step == 6 then drawReaders(source, w, h, layout)
    elseif state.step == 7 then drawLaserCountStep(source, w, h, layout)
    elseif state.step == 8 then drawTests(source, w, h, layout)
    elseif state.step == 9 then drawSummary(source, w, h, layout)
    end

    drawNavigation(source, w, h, layout)
    drawFooter(w, h, layout)

    if type(currentSurface.flush) == "function" then
      pcall(currentSurface.flush)
    elseif type(currentSurface.sync) == "function" then
      pcall(currentSurface.sync)
    end
  end)
end

local function render()
  local monitorSurface = nil
  state.monitorTouchEvent = "monitor_touch"
  state.monitorTouchMapper = nil
  if state.uiOnMonitor and state.selected.monitor then
    local selected = resolveSelectedDisplayCandidate()
    if selected then
      local obj = safePeripheral(selected.name)
      local candidate = normalizeDisplayCandidate(selected.name, obj)
      if candidate and candidate.obj then
        state.selected.monitor = candidate.name
        if candidate.backend == "cc_monitor" and type(candidate.obj.setTextScale) == "function" then
          pcall(candidate.obj.setTextScale, sanitizeScale(state.monitorScale))
        end
        local surface, meta = DisplayBackend.createSurface(candidate, { monitorScale = sanitizeScale(state.monitorScale) })
        monitorSurface = surface or candidate.obj
        state.monitorTouchEvent = (meta and meta.touchEvent) or candidate.touchEvent or "monitor_touch"
        state.monitorTouchMapper = meta and meta.mapPixel or nil
      else
        state.uiOnMonitor = false
        state.status = "Monitor UI desactivee: display indisponible."
        clearHitboxes("monitor")
      end
    else
      state.uiOnMonitor = false
      state.status = "Monitor UI desactivee: aucune surface compatible."
      clearHitboxes("monitor")
    end
  else
    clearHitboxes("monitor")
  end

  renderOnSurface("term", nativeTerm)
  if monitorSurface then
    renderOnSurface("monitor", monitorSurface)
  end
end

scanNow()
render()

while state.running do
  local ev, p1, p2, p3 = os.pullEvent()
  if ev == "mouse_click" then
    handleClick(p2, p3, "term")
    render()
  elseif (ev == "monitor_touch" or ev == "tm_monitor_touch") and p1 == state.selected.monitor then
    local mx, my = p2, p3
    if type(state.monitorTouchMapper) == "function" and ev == state.monitorTouchEvent then
      local mappedX, mappedY = state.monitorTouchMapper(mx, my)
      mx = tonumber(mappedX) or mx
      my = tonumber(mappedY) or my
    end
    handleClick(mx, my, "monitor")
    render()
  elseif ev == "key" and p1 == keys.q then
    state.running = false
  elseif ev == "peripheral" or ev == "peripheral_detach" then
    scanNow()
    render()
  end
end

if state.launch then
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)
  shell.run("fusion.lua")
else
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)
  print("Installateur ferme.")
end
