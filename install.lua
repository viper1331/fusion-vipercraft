-- install.lua
-- Assistant d'installation Fusion ViperCraft

local CONFIG_FILE = "fusion_config.lua"
local VERSION_FILE = "fusion.version"
local DEFAULT_VERSION = "1.1.0"

local function contains(str, sub)
  return type(str) == "string" and type(sub) == "string"
    and string.find(string.lower(str), string.lower(sub), 1, true) ~= nil
end

local function trim(text)
  text = tostring(text or "")
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function readLineDefault(prompt, defaultValue)
  write(prompt)
  if defaultValue ~= nil then
    write(" [" .. tostring(defaultValue) .. "]")
  end
  write(": ")
  local input = trim(read())
  if input == "" then
    return defaultValue
  end
  return input
end

local function askChoice(title, choices, suggested)
  print("")
  print(title)
  for i, item in ipairs(choices) do
    local tag = (suggested == item) and "*" or " "
    print(string.format("  %s %d) %s", tag, i, item))
  end
  print("    0) None")

  while true do
    local raw = readLineDefault("Sélection", suggested and tostring((function()
      for i, item in ipairs(choices) do
        if item == suggested then return i end
      end
      return 0
    end)()) or "0")

    local idx = tonumber(raw)
    if idx and idx >= 0 and idx <= #choices then
      if idx == 0 then return nil end
      return choices[idx]
    end
    print("Choix invalide.")
  end
end

local function askSide(title, defaultSide)
  local allowed = { top = true, bottom = true, left = true, right = true, front = true, back = true }
  while true do
    local side = string.lower(readLineDefault(title, defaultSide or "front") or "front")
    if allowed[side] then return side end
    print("Face invalide. Valeurs: top/bottom/left/right/front/back")
  end
end

local function gatherPeripherals()
  local names = peripheral.getNames()
  table.sort(names)

  local devices = {
    all = names,
    byType = {},
    monitors = {},
    readers = {},
    relays = {},
  }

  for _, name in ipairs(names) do
    local ptype = peripheral.getType(name) or "unknown"
    devices.byType[ptype] = devices.byType[ptype] or {}
    table.insert(devices.byType[ptype], name)

    if ptype == "monitor" then table.insert(devices.monitors, name) end
    if ptype == "block_reader" or contains(name, "block_reader") then table.insert(devices.readers, name) end
    if ptype == "redstone_relay" or contains(name, "relay") then table.insert(devices.relays, name) end
  end

  return devices
end

local function suggestByName(names, keywords)
  for _, name in ipairs(names) do
    for _, key in ipairs(keywords) do
      if contains(name, key) then
        return name
      end
    end
  end
  return nil
end

local function listCandidates(devices)
  local generic = devices.all
  local suggested = {
    monitor = suggestByName(devices.monitors, { "monitor" }),
    reactorController = suggestByName(generic, { "fusion_reactor_controller", "reactor_controller", "fusionreactor" }),
    logicAdapter = suggestByName(generic, { "logic_adapter", "fusionreactorlogicadapter", "logic" }),
    laser = suggestByName(generic, { "laser", "amplifier" }),
    induction = suggestByName(generic, { "induction", "matrix", "port" }),
    relayLaser = suggestByName(devices.relays, { "relay_0", "laser", "las" }),
    relayTritium = suggestByName(devices.relays, { "relay_2", "tritium", "tank_t" }),
    relayDeuterium = suggestByName(devices.relays, { "relay_1", "deuterium", "tank_d" }),
    readerTritium = suggestByName(devices.readers, { "reader_2", "tritium" }),
    readerDeuterium = suggestByName(devices.readers, { "reader_1", "deuterium" }),
    readerAux = suggestByName(devices.readers, { "reader_6", "aux", "inventory" }),
  }
  return suggested
end

local function runMonitorTest(name)
  if not name then return false, "Monitor non configuré" end
  local mon = peripheral.wrap(name)
  if not mon then return false, "Monitor introuvable" end

  local ok = pcall(function()
    mon.setBackgroundColor(colors.blue)
    mon.setTextColor(colors.white)
    mon.clear()
    mon.setCursorPos(1, 1)
    mon.write("Fusion installer: monitor test")
    mon.setCursorPos(1, 2)
    mon.write("Touch this monitor now")
  end)

  if not ok then return false, "Échec écriture monitor" end
  print("Touchez le monitor pour valider (5s)...")
  local timer = os.startTimer(5)
  while true do
    local ev, p1 = os.pullEvent()
    if ev == "monitor_touch" and p1 == name then
      return true, "Touch monitor détecté"
    end
    if ev == "timer" and p1 == timer then
      return true, "Monitor visible (pas de touch détecté)"
    end
  end
end

local function runRelayTest(relayName, side)
  if not relayName then return false, "Relay non configuré" end
  local relay = peripheral.wrap(relayName)
  if not relay or type(relay.setOutput) ~= "function" then
    return false, "Relay introuvable"
  end

  local ok, err = pcall(function()
    relay.setOutput(side, true)
    sleep(0.2)
    relay.setOutput(side, false)
  end)

  if not ok then
    return false, "Test relais échoué: " .. tostring(err)
  end
  return true, "Pulse envoyé sur " .. relayName .. "." .. side
end

local function runReaderTest(readerName)
  if not readerName then return false, "Reader non configuré" end
  local reader = peripheral.wrap(readerName)
  if not reader then return false, "Reader introuvable" end

  local methods = peripheral.getMethods(readerName) or {}
  if #methods == 0 then return false, "Aucune méthode reader" end
  return true, "Reader disponible (" .. tostring(#methods) .. " méthodes)"
end

local function runDevicePresenceTest(name)
  if not name then return false, "Non configuré" end
  if peripheral.isPresent(name) then
    return true, "Présent"
  end
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
    if #keys > 0 then
      table.insert(parts, "\n" .. sp)
    end
    table.insert(parts, "}")
    return table.concat(parts)
  end

  if type(value) == "string" then
    return string.format("%q", value)
  end

  return tostring(value)
end

local function writeConfig(config)
  local h = fs.open(CONFIG_FILE, "w")
  if not h then return false, "Impossible d'écrire " .. CONFIG_FILE end
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

term.clear()
term.setCursorPos(1, 1)
print("=== Fusion ViperCraft - Install Wizard ===")
print("Scan des périphériques locaux/distants en cours...")

local devices = gatherPeripherals()
local suggested = listCandidates(devices)

print(string.format("%d périphériques détectés.", #devices.all))
print(string.format("Monitors: %d | Relays: %d | Readers: %d", #devices.monitors, #devices.relays, #devices.readers))

local monitorName = askChoice("Monitor principal", devices.monitors, suggested.monitor)
local monitorScale = tonumber(readLineDefault("Scale monitor (0.5 recommandé)", "0.5")) or 0.5
local setupName = readLineDefault("Nom du setup", "Fusion ViperCraft")

local reactorController = askChoice("Reactor controller", devices.all, suggested.reactorController)
local logicAdapter = askChoice("Logic adapter", devices.all, suggested.logicAdapter)
local laser = askChoice("Laser", devices.all, suggested.laser)
local induction = askChoice("Induction matrix/port", devices.all, suggested.induction)

local relayLaser = askChoice("Relay LAS", devices.relays, suggested.relayLaser)
local relayLaserSide = askSide("Face Relay LAS", "top")
local relayTritium = askChoice("Relay Tritium", devices.relays, suggested.relayTritium)
local relayTritiumSide = askSide("Face Relay Tritium", "front")
local relayDeuterium = askChoice("Relay Deuterium", devices.relays, suggested.relayDeuterium)
local relayDeuteriumSide = askSide("Face Relay Deuterium", "front")

local readerTritium = askChoice("Reader Tritium", devices.readers, suggested.readerTritium)
local readerDeuterium = askChoice("Reader Deuterium", devices.readers, suggested.readerDeuterium)
local readerAux = askChoice("Reader Aux", devices.readers, suggested.readerAux)

local preferredView = readLineDefault("Vue UI préférée (SUP/DIAG/MAN/IND/UPD)", "SUP")
local touchEnabled = string.lower(readLineDefault("Touch monitor activé ? (y/n)", "y")) ~= "n"

print("")
print("=== Tests matériels ===")
local tests = {
  { "Monitor", runMonitorTest(monitorName) },
  { "Relay LAS", runRelayTest(relayLaser, relayLaserSide) },
  { "Relay Tritium", runRelayTest(relayTritium, relayTritiumSide) },
  { "Relay Deuterium", runRelayTest(relayDeuterium, relayDeuteriumSide) },
  { "Reader Tritium", runReaderTest(readerTritium) },
  { "Reader Deuterium", runReaderTest(readerDeuterium) },
  { "Reader Aux", runReaderTest(readerAux) },
  { "Laser", runDevicePresenceTest(laser) },
  { "Induction", runDevicePresenceTest(induction) },
}

for _, item in ipairs(tests) do
  local name = item[1]
  local ok, msg = item[2], item[3]
  print(string.format("- %s: %s (%s)", name, ok and "OK" or "WARN", msg or ""))
end

local config = {
  configVersion = 1,
  setupName = setupName,
  monitor = {
    name = monitorName,
    scale = monitorScale,
  },
  devices = {
    reactorController = reactorController,
    logicAdapter = logicAdapter,
    laser = laser,
    induction = induction,
  },
  relays = {
    laser = { name = relayLaser, side = relayLaserSide },
    tritium = { name = relayTritium, side = relayTritiumSide },
    deuterium = { name = relayDeuterium, side = relayDeuteriumSide },
  },
  readers = {
    tritium = readerTritium,
    deuterium = readerDeuterium,
    aux = readerAux,
  },
  ui = {
    preferredView = preferredView,
    touchEnabled = touchEnabled,
    refreshDelay = 0.20,
  },
  update = {
    enabled = true,
  },
}

local okWrite, errWrite = writeConfig(config)
if not okWrite then
  print("Erreur écriture config: " .. tostring(errWrite))
  return
end

ensureVersionFile()

print("")
print("Configuration sauvegardée dans " .. CONFIG_FILE)
print("Résumé:")
print("- Setup: " .. tostring(config.setupName))
print("- Monitor: " .. tostring(config.monitor.name))
print("- Reactor: " .. tostring(config.devices.reactorController))
print("- Logic: " .. tostring(config.devices.logicAdapter))
print("- Laser: " .. tostring(config.devices.laser))
print("- Induction: " .. tostring(config.devices.induction))

local launchNow = string.lower(readLineDefault("Lancer fusion.lua maintenant ? (y/n)", "y")) ~= "n"
if launchNow then
  shell.run("fusion.lua")
end
