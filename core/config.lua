local M = {}

local VALID_VIEWS = {
  SUP = true,
  DIAG = true,
  MAN = true,
  IND = true,
  UPDATE = true,
}

local VALID_SIDES = {
  top = true,
  bottom = true,
  left = true,
  right = true,
  front = true,
  back = true,
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
      touchEnabled = true,
      refreshDelay = CFG.refreshDelay,
    },
    update = {
      enabled = updateEnabled,
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

  CFG.preferredMonitor = config.monitor and config.monitor.name or CFG.preferredMonitor
  CFG.monitorScale = M.sanitizeMonitorScale(config.monitor and config.monitor.scale, CFG.monitorScale)
  CFG.refreshDelay = M.sanitizeRefreshDelay(config.ui and config.ui.refreshDelay, CFG.refreshDelay)

  CFG.preferredReactor = config.devices and config.devices.reactorController or CFG.preferredReactor
  CFG.preferredLogicAdapter = config.devices and config.devices.logicAdapter or CFG.preferredLogicAdapter
  CFG.preferredLaser = config.devices and config.devices.laser or CFG.preferredLaser
  CFG.preferredInduction = config.devices and config.devices.induction or CFG.preferredInduction

  CFG.knownReaders.deuterium = config.readers and config.readers.deuterium or CFG.knownReaders.deuterium
  CFG.knownReaders.tritium = config.readers and config.readers.tritium or CFG.knownReaders.tritium
  CFG.knownReaders.inventory = config.readers and config.readers.aux or CFG.knownReaders.inventory

  CFG.knownRelays.laser_charge.relay = config.relays and config.relays.laser and config.relays.laser.name or CFG.knownRelays.laser_charge.relay
  CFG.knownRelays.laser_charge.side = M.sanitizeRelaySide(config.relays and config.relays.laser and config.relays.laser.side, CFG.knownRelays.laser_charge.side)
  CFG.knownRelays.tritium.relay = config.relays and config.relays.tritium and config.relays.tritium.name or CFG.knownRelays.tritium.relay
  CFG.knownRelays.tritium.side = M.sanitizeRelaySide(config.relays and config.relays.tritium and config.relays.tritium.side, CFG.knownRelays.tritium.side)
  CFG.knownRelays.deuterium.relay = config.relays and config.relays.deuterium and config.relays.deuterium.name or CFG.knownRelays.deuterium.relay
  CFG.knownRelays.deuterium.side = M.sanitizeRelaySide(config.relays and config.relays.deuterium and config.relays.deuterium.side, CFG.knownRelays.deuterium.side)
end

function M.sanitizeMonitorScale(value, fallback)
  local numeric = tonumber(value)
  if numeric == nil then return fallback end
  if numeric < 0.5 then return 0.5 end
  if numeric > 5 then return 5 end
  return math.floor(numeric * 2 + 0.5) / 2
end

function M.sanitizeRefreshDelay(value, fallback)
  local numeric = tonumber(value)
  if numeric == nil then return fallback end
  if numeric < 0.05 then return 0.05 end
  if numeric > 5 then return 5 end
  return numeric
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

  local monitorName = config.monitor and config.monitor.name
  if type(monitorName) ~= "string" or M.trimText(monitorName) == "" then
    table.insert(errors, "monitor.name is missing")
  end

  local deviceKeys = { "reactorController", "logicAdapter", "laser", "induction" }
  for _, key in ipairs(deviceKeys) do
    local value = config.devices and config.devices[key]
    if type(value) ~= "string" or M.trimText(value) == "" then
      table.insert(errors, "devices." .. key .. " is missing")
    end
  end

  local preferredView = config.ui and config.ui.preferredView
  if preferredView ~= nil and not VALID_VIEWS[tostring(preferredView)] then
    table.insert(errors, "ui.preferredView is invalid")
  end

  local relayEntries = {
    { path = "relays.laser.side", value = config.relays and config.relays.laser and config.relays.laser.side },
    { path = "relays.tritium.side", value = config.relays and config.relays.tritium and config.relays.tritium.side },
    { path = "relays.deuterium.side", value = config.relays and config.relays.deuterium and config.relays.deuterium.side },
  }

  for _, relay in ipairs(relayEntries) do
    if relay.value ~= nil and not VALID_SIDES[tostring(relay.value)] then
      table.insert(errors, relay.path .. " is invalid")
    end
  end

  return #errors == 0, errors
end

return M
