local M = {}

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
  CFG.monitorScale = tonumber(config.monitor and config.monitor.scale) or CFG.monitorScale
  CFG.refreshDelay = tonumber(config.ui and config.ui.refreshDelay) or CFG.refreshDelay

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
end

return M
