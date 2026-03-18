local M = {}

local VALID_VIEWS = {
  SUP = true,
  DIAG = true,
  MAN = true,
  IND = true,
  UPDATE = true,
  CFG = true,
  CONFIG = true,
  SETUP = true,
}

local VALID_SIDES = {
  top = true,
  bottom = true,
  left = true,
  right = true,
  front = true,
  back = true,
}

local VALID_OUTPUTS = {
  terminal = true,
  monitor = true,
  both = true,
}

local VALID_DISPLAY_BACKENDS = {
  auto = true,
  cc_monitor = true,
  toms_gpu = true,
}

local VALID_ENERGY_UNITS = {
  j = true,
  fe = true,
}

local VALID_LOG_LEVELS = {
  debug = true,
  info = true,
  warn = true,
  error = true,
  off = true,
}

function M.trimText(txt)
  txt = tostring(txt or "")
  return (txt:gsub("^%s+", ""):gsub("%s+$", ""))
end

function M.readLocalVersionFile(fsApi, versionFile, fallback)
  local ok, content = pcall(function()
    if not fsApi.exists(versionFile) then return nil end
    local h = fsApi.open(versionFile, "r")
    if not h then return nil end
    local v = h.readAll()
    h.close()
    return M.trimText(v)
  end)
  if ok and content and #content > 0 then
    return content
  end
  return fallback
end

function M.defaultFusionConfig(CFG, updateEnabled)
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
      scale = CFG.uiScale or 1.0,
      output = CFG.displayOutput or "monitor",
      displayBackend = CFG.displayBackend or "auto",
      energyUnit = CFG.energyUnit or "j",
      laserCount = CFG.laserCount or 1,
      touchEnabled = true,
      refreshDelay = CFG.refreshDelay,
    },
    actions = {
      dt_fuel = {
        relay = CFG.actions and CFG.actions.dt_fuel and CFG.actions.dt_fuel.relay or nil,
        side = CFG.actions and CFG.actions.dt_fuel and CFG.actions.dt_fuel.side or "front",
      },
    },
    update = {
      enabled = updateEnabled,
    },
    logs = {
      enabled = CFG.logEnabled,
      level = CFG.logLevel,
      toFile = CFG.logToFile,
      toTerminal = CFG.logToTerminal,
      file = CFG.logFile,
      maxFileBytes = CFG.logMaxFileBytes,
    },
  }
end

function M.mergeDefaults(target, defaults)
  if type(target) ~= "table" then target = {} end
  for k, v in pairs(defaults) do
    if type(v) == "table" then
      target[k] = M.mergeDefaults(type(target[k]) == "table" and target[k] or {}, v)
    elseif target[k] == nil then
      target[k] = v
    end
  end
  return target
end

function M.migrateConfig(config, CFG, updateEnabled)
  local cfg = type(config) == "table" and config or {}
  local version = tonumber(cfg.configVersion) or 0
  local defaults = M.defaultFusionConfig(CFG, updateEnabled)

  if version < 1 then
    cfg = M.mergeDefaults(cfg, defaults)
    cfg.configVersion = 1
  end

  cfg = M.mergeDefaults(cfg, defaults)
  return cfg
end

function M.loadFusionConfig(fsApi, configFile, CFG, updateEnabled)
  if not fsApi.exists(configFile) then
    return false, nil, "CONFIG_MISSING"
  end

  local ok, configOrErr = pcall(dofile, configFile)
  if not ok then
    return false, nil, "CONFIG_INVALID: " .. tostring(configOrErr)
  end

  if type(configOrErr) ~= "table" then
    return false, nil, "CONFIG_INVALID: Not a table"
  end

  local migrated = M.migrateConfig(configOrErr, CFG, updateEnabled)
  return true, migrated, nil
end

function M.applyConfigToRuntime(config, CFG)
  if type(config) ~= "table" then return end

  CFG.preferredMonitor = M.sanitizeDeviceName(config.monitor and config.monitor.name, CFG.preferredMonitor)
  CFG.monitorScale = M.sanitizeMonitorScale(config.monitor and config.monitor.scale, CFG.monitorScale)
  CFG.uiScale = M.sanitizeUiScale(config.ui and config.ui.scale, CFG.uiScale or 1.0)
  CFG.displayOutput = M.sanitizeDisplayOutput(config.ui and config.ui.output, CFG.displayOutput or "monitor")
  CFG.displayBackend = M.sanitizeDisplayBackend(config.ui and config.ui.displayBackend, CFG.displayBackend or "auto")
  CFG.energyUnit = M.sanitizeEnergyUnit(config.ui and config.ui.energyUnit, CFG.energyUnit or "j")
  CFG.laserCount = M.sanitizeLaserCount(config.ui and config.ui.laserCount, CFG.laserCount or 1)
  CFG.refreshDelay = M.sanitizeRefreshDelay(config.ui and config.ui.refreshDelay, CFG.refreshDelay)
  CFG.logEnabled = M.sanitizeBoolean(config.logs and config.logs.enabled, CFG.logEnabled ~= false)
  CFG.logLevel = M.sanitizeLogLevel(config.logs and config.logs.level, CFG.logLevel or "info")
  CFG.logToFile = M.sanitizeBoolean(config.logs and config.logs.toFile, CFG.logToFile ~= false)
  CFG.logToTerminal = M.sanitizeBoolean(config.logs and config.logs.toTerminal, CFG.logToTerminal == true)
  CFG.logFile = M.sanitizeLogFile(config.logs and config.logs.file, CFG.logFile or "fusion.log")
  CFG.logMaxFileBytes = M.sanitizeLogMaxFileBytes(config.logs and config.logs.maxFileBytes, CFG.logMaxFileBytes or 262144)

  CFG.preferredReactor = M.sanitizeDeviceName(config.devices and config.devices.reactorController, CFG.preferredReactor)
  CFG.preferredLogicAdapter = M.sanitizeDeviceName(config.devices and config.devices.logicAdapter, CFG.preferredLogicAdapter)
  CFG.preferredLaser = M.sanitizeDeviceName(config.devices and config.devices.laser, CFG.preferredLaser)
  CFG.preferredInduction = M.sanitizeDeviceName(config.devices and config.devices.induction, CFG.preferredInduction)

  CFG.knownReaders.deuterium = M.sanitizeDeviceName(config.readers and config.readers.deuterium, CFG.knownReaders.deuterium)
  CFG.knownReaders.tritium = M.sanitizeDeviceName(config.readers and config.readers.tritium, CFG.knownReaders.tritium)
  CFG.knownReaders.inventory = M.sanitizeDeviceName(config.readers and config.readers.aux, CFG.knownReaders.inventory)

  CFG.knownRelays.laser_charge.relay = M.sanitizeDeviceName(config.relays and config.relays.laser and config.relays.laser.name, CFG.knownRelays.laser_charge.relay)
  CFG.knownRelays.laser_charge.side = M.sanitizeRelaySide(config.relays and config.relays.laser and config.relays.laser.side, CFG.knownRelays.laser_charge.side)
  CFG.knownRelays.tritium.relay = M.sanitizeDeviceName(config.relays and config.relays.tritium and config.relays.tritium.name, CFG.knownRelays.tritium.relay)
  CFG.knownRelays.tritium.side = M.sanitizeRelaySide(config.relays and config.relays.tritium and config.relays.tritium.side, CFG.knownRelays.tritium.side)
  CFG.knownRelays.deuterium.relay = M.sanitizeDeviceName(config.relays and config.relays.deuterium and config.relays.deuterium.name, CFG.knownRelays.deuterium.relay)
  CFG.knownRelays.deuterium.side = M.sanitizeRelaySide(config.relays and config.relays.deuterium and config.relays.deuterium.side, CFG.knownRelays.deuterium.side)

  local dtFuelRelay = M.sanitizeDeviceName(
    (config.actions and config.actions.dt_fuel and config.actions.dt_fuel.relay)
      or (config.relays and config.relays.dtFuel and config.relays.dtFuel.name),
    CFG.actions and CFG.actions.dt_fuel and CFG.actions.dt_fuel.relay
  )
  local dtFuelSide = M.sanitizeRelaySide(
    (config.actions and config.actions.dt_fuel and config.actions.dt_fuel.side)
      or (config.relays and config.relays.dtFuel and config.relays.dtFuel.side),
    (CFG.actions and CFG.actions.dt_fuel and CFG.actions.dt_fuel.side) or "front"
  )
  CFG.actions = type(CFG.actions) == "table" and CFG.actions or {}
  if dtFuelRelay then
    CFG.actions.dt_fuel = type(CFG.actions.dt_fuel) == "table" and CFG.actions.dt_fuel or {}
    CFG.actions.dt_fuel.relay = dtFuelRelay
    CFG.actions.dt_fuel.side = dtFuelSide
    CFG.actions.dt_fuel.analog = tonumber(CFG.actions.dt_fuel.analog) or 15
    CFG.actions.dt_fuel.pulse = false
  else
    CFG.actions.dt_fuel = nil
  end
end

function M.sanitizeMonitorScale(value, fallback)
  local numeric = tonumber(value)
  if numeric == nil then return fallback end
  if numeric < 0.5 then return 0.5 end
  if numeric > 5 then return 5 end
  return math.floor(numeric * 2 + 0.5) / 2
end

function M.sanitizeUiScale(value, fallback)
  local numeric = tonumber(value)
  if numeric == nil then return fallback end
  if numeric < 0.5 then return 0.5 end
  if numeric > 2 then return 2 end
  return math.floor(numeric * 10 + 0.5) / 10
end

function M.sanitizeDisplayOutput(value, fallback)
  local mode = string.lower(tostring(value or ""))
  if VALID_OUTPUTS[mode] then return mode end
  return fallback
end

function M.sanitizeDisplayBackend(value, fallback)
  local mode = string.lower(tostring(value or ""))
  if VALID_DISPLAY_BACKENDS[mode] then return mode end
  return fallback
end

function M.sanitizeEnergyUnit(value, fallback)
  local unit = string.lower(tostring(value or ""))
  if VALID_ENERGY_UNITS[unit] then return unit end
  return fallback
end

function M.sanitizeLaserCount(value, fallback)
  local numeric = tonumber(value)
  if numeric == nil then return fallback end
  numeric = math.floor(numeric + 0.5)
  if numeric < 1 then return 1 end
  if numeric > 16 then return 16 end
  return numeric
end

function M.sanitizeRefreshDelay(value, fallback)
  local numeric = tonumber(value)
  if numeric == nil then return fallback end
  if numeric < 0.05 then return 0.05 end
  if numeric > 5 then return 5 end
  return numeric
end

function M.sanitizeBoolean(value, fallback)
  if type(value) == "boolean" then return value end
  if value == nil then return fallback and true or false end
  if type(value) == "number" then return value ~= 0 end
  local raw = string.lower(tostring(value or ""))
  if raw == "true" or raw == "1" or raw == "yes" or raw == "on" then return true end
  if raw == "false" or raw == "0" or raw == "no" or raw == "off" then return false end
  return fallback and true or false
end

function M.sanitizeLogLevel(value, fallback)
  local level = string.lower(tostring(value or ""))
  if VALID_LOG_LEVELS[level] then return level end
  return string.lower(tostring(fallback or "info"))
end

function M.sanitizeLogFile(value, fallback)
  local file = M.trimText(tostring(value or ""))
  if file == "" then return fallback end
  file = file:gsub("\\", "/")
  file = file:gsub("/+", "/")
  file = file:gsub("^%./+", "")
  if file:sub(1, 1) == "/" then return fallback end
  if file:match("^[%a]:") then return fallback end
  if file:find("%.%.", 1, true) then return fallback end
  return file
end

function M.sanitizeLogMaxFileBytes(value, fallback)
  local numeric = tonumber(value)
  if numeric == nil then return fallback end
  numeric = math.floor(numeric + 0.5)
  if numeric < 8192 then return 8192 end
  if numeric > 8388608 then return 8388608 end
  return numeric
end

function M.sanitizeDeviceName(value, fallback)
  if value == nil then return fallback end
  if type(value) ~= "string" then return fallback end
  local trimmed = M.trimText(value)
  if trimmed == "" then return nil end
  return trimmed
end

function M.sanitizeRelaySide(value, fallback)
  local side = tostring(value or "")
  if VALID_SIDES[side] then return side end
  return fallback
end

function M.validateConfig(config)
  local errors = {}
  if type(config) ~= "table" then
    table.insert(errors, "Configuration root must be a table")
    return false, errors
  end
  local relays = type(config.relays) == "table" and config.relays or {}
  local actions = type(config.actions) == "table" and config.actions or nil

  local function optionalBindingName(value, path)
    if value == nil then return end
    if type(value) ~= "string" then
      table.insert(errors, path .. " is invalid")
      return
    end
    if M.trimText(value) == "" then return end
  end

  optionalBindingName(config.monitor and config.monitor.name, "monitor.name")
  optionalBindingName(config.devices and config.devices.reactorController, "devices.reactorController")
  optionalBindingName(config.devices and config.devices.logicAdapter, "devices.logicAdapter")
  optionalBindingName(config.devices and config.devices.laser, "devices.laser")
  optionalBindingName(config.devices and config.devices.induction, "devices.induction")
  optionalBindingName(config.readers and config.readers.tritium, "readers.tritium")
  optionalBindingName(config.readers and config.readers.deuterium, "readers.deuterium")
  optionalBindingName(config.readers and config.readers.aux, "readers.aux")
  optionalBindingName(relays.laser and relays.laser.name, "relays.laser.name")
  optionalBindingName(relays.tritium and relays.tritium.name, "relays.tritium.name")
  optionalBindingName(relays.deuterium and relays.deuterium.name, "relays.deuterium.name")
  optionalBindingName(relays.dtFuel and relays.dtFuel.name, "relays.dtFuel.name")
  optionalBindingName(actions and actions.dt_fuel and actions.dt_fuel.relay, "actions.dt_fuel.relay")

  local preferredView = config.ui and config.ui.preferredView
  if type(preferredView) ~= "string" or not VALID_VIEWS[preferredView] then
    table.insert(errors, "ui.preferredView is invalid")
  end

  if tonumber(config.ui and config.ui.scale) == nil then
    table.insert(errors, "ui.scale is invalid")
  end

  local outputMode = config.ui and config.ui.output
  if type(outputMode) ~= "string" or not VALID_OUTPUTS[string.lower(outputMode)] then
    table.insert(errors, "ui.output is invalid")
  end

  local displayBackend = config.ui and config.ui.displayBackend
  if displayBackend ~= nil and (type(displayBackend) ~= "string" or not VALID_DISPLAY_BACKENDS[string.lower(displayBackend)]) then
    table.insert(errors, "ui.displayBackend is invalid")
  end

  local energyUnit = config.ui and config.ui.energyUnit
  if type(energyUnit) ~= "string" or not VALID_ENERGY_UNITS[string.lower(energyUnit)] then
    table.insert(errors, "ui.energyUnit is invalid")
  end

  if tonumber(config.ui and config.ui.laserCount) == nil then
    table.insert(errors, "ui.laserCount is invalid")
  end

  local logs = config.logs
  if logs ~= nil and type(logs) ~= "table" then
    table.insert(errors, "logs must be a table")
  elseif type(logs) == "table" then
    if logs.enabled ~= nil and type(logs.enabled) ~= "boolean" then
      table.insert(errors, "logs.enabled is invalid")
    end
    if logs.toFile ~= nil and type(logs.toFile) ~= "boolean" then
      table.insert(errors, "logs.toFile is invalid")
    end
    if logs.toTerminal ~= nil and type(logs.toTerminal) ~= "boolean" then
      table.insert(errors, "logs.toTerminal is invalid")
    end
    if logs.level ~= nil then
      local level = string.lower(tostring(logs.level))
      if not VALID_LOG_LEVELS[level] then
        table.insert(errors, "logs.level is invalid")
      end
    end
    if logs.file ~= nil then
      if type(logs.file) ~= "string" or M.trimText(logs.file) == "" then
        table.insert(errors, "logs.file is invalid")
      end
    end
    if logs.maxFileBytes ~= nil and tonumber(logs.maxFileBytes) == nil then
      table.insert(errors, "logs.maxFileBytes is invalid")
    end
  end

  local relaySides = {
    { path = "relays.laser.side", value = relays.laser and relays.laser.side },
    { path = "relays.tritium.side", value = relays.tritium and relays.tritium.side },
    { path = "relays.deuterium.side", value = relays.deuterium and relays.deuterium.side },
  }

  for _, relay in ipairs(relaySides) do
    if type(relay.value) ~= "string" or not VALID_SIDES[relay.value] then
      table.insert(errors, relay.path .. " is invalid")
    end
  end

  if relays.dtFuel and relays.dtFuel.side ~= nil then
    local side = relays.dtFuel.side
    if type(side) ~= "string" or not VALID_SIDES[side] then
      table.insert(errors, "relays.dtFuel.side is invalid")
    end
  end

  if config.actions ~= nil and type(config.actions) ~= "table" then
    table.insert(errors, "actions must be a table")
  elseif actions and actions.dt_fuel ~= nil then
    if type(actions.dt_fuel) ~= "table" then
      table.insert(errors, "actions.dt_fuel must be a table")
    elseif actions.dt_fuel.side ~= nil then
      local side = actions.dt_fuel.side
      if type(side) ~= "string" or not VALID_SIDES[side] then
        table.insert(errors, "actions.dt_fuel.side is invalid")
      end
    end
  end

  return #errors == 0, errors
end

function M.serializeValue(value, indent)
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
      local encodedValue = M.serializeValue(value[key], indent + 1)
      table.insert(parts, string.format("\n%s%s = %s,", sp2, encodedKey, encodedValue))
    end
    if #keys > 0 then table.insert(parts, "\n" .. sp) end
    table.insert(parts, "}")
    return table.concat(parts)
  end

  if type(value) == "string" then return string.format("%q", value) end
  return tostring(value)
end

function M.writeFusionConfig(fsApi, configFile, config)
  local h = fsApi.open(configFile, "w")
  if not h then return false, "Unable to open " .. tostring(configFile) end
  h.write("return ")
  h.write(M.serializeValue(config, 0))
  h.write("\n")
  h.close()
  return true
end

return M
