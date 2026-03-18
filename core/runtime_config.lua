local M = {}

function M.new()
  local cfg = {
    -- Mode dynamique: aucune liaison n'est imposee par defaut.
    preferredMonitor = nil,
    preferredReactor = nil,
    preferredLogicAdapter = nil,
    preferredLaser = nil,
    preferredInduction = nil,

    uiScale = 1.0,
    displayOutput = "monitor",
    displayBackend = "auto",
    monitorScale = 0.5,
    energyUnit = "j",
    laserCount = 1,
    refreshDelay = 0.20,
    logEnabled = true,
    logLevel = "info",
    logToFile = true,
    logToTerminal = false,
    logFile = "fusion.log",
    logMaxFileBytes = 262144,

    ignitionLaserEnergyThreshold = 2000000000,

    laserChargeStartPct = 90,
    laserChargeStopPct = 100,

    energyLowPct = 20,
    energyHighPct = 99,

    emergencyStopIfReactorMissing = true,
    ignitionRetryDelay = 3.0,

    knownReaders = {
      deuterium = nil,
      tritium = nil,
      inventory = nil,
    },

    knownRelays = {
      laser_charge = { relay = nil, side = "top", label = "LAS" },
      deuterium = { relay = nil, side = "front", label = "Tank Deuterium" },
      tritium = { relay = nil, side = "front", label = "Tank Tritium" },
    },

    actions = {
      -- La ligne LAS doit rester a 0 hors pulse d'ignition.
      laser_charge = { relay = nil, side = "top", analog = 0, pulse = false, forceZero = true },
      deuterium = { relay = nil, side = "front", analog = 15, pulse = false },
      tritium = { relay = nil, side = "front", analog = 15, pulse = false },
      laser_fire = { relay = nil, side = "top", analog = 15, pulse = true, pulseTime = 0.15 },
      dt_fuel = nil,
    },
  }

  local files = {
    configFile = "fusion_config.lua",
    monitorCacheFile = "fusion_monitor.cfg",
    versionFile = "fusion.version",
  }

  local update = {
    localVersion = "0.0.0",
    enabled = true,
    repoRawBase = "https://raw.githubusercontent.com/viper1331/fusion-vipercraft/main",
    manifestFile = "fusion.manifest.json",
    tempDir = ".fusion_update_tmp",
    manifestCacheFile = "fusion.manifest.cache",
    missingBackupSuffix = ".bak.missing",
  }
  update.manifestUrl = update.repoRawBase .. "/" .. update.manifestFile

  local hitboxDefaults = {
    minW = 10,
    minH = 3,
    basePadX = 0,
    basePadY = 0,
    smallBoostPadX = 1,
    smallBoostPadY = 0,
    rowPadX = 0,
    rowPadY = 0,
  }

  return {
    cfg = cfg,
    files = files,
    update = update,
    hitboxDefaults = hitboxDefaults,
  }
end

return M
