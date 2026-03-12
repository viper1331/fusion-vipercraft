local M = {}

function M.new()
  local cfg = {
    preferredMonitor = "monitor_2",
    preferredReactor = "mekanismgenerators:fusion_reactor_controller_3",
    preferredLogicAdapter = "fusionReactorLogicAdapter_0",
    preferredLaser = "laserAmplifier_1",
    preferredInduction = "inductionPort_1",

    monitorScale = 0.5,
    refreshDelay = 0.20,

    ignitionLaserEnergyThreshold = 2000000000,

    laserChargeStartPct = 90,
    laserChargeStopPct = 100,

    energyLowPct = 20,
    energyHighPct = 99,

    emergencyStopIfReactorMissing = true,
    ignitionRetryDelay = 3.0,

    knownReaders = {
      deuterium = "block_reader_1",
      tritium = "block_reader_2",
      inventory = "block_reader_6",
    },

    knownRelays = {
      laser_charge = { relay = "redstone_relay_0", side = "top", label = "LAS" },
      deuterium = { relay = "redstone_relay_1", side = "front", label = "Tank Deuterium" },
      tritium = { relay = "redstone_relay_2", side = "front", label = "Tank Tritium" },
    },

    actions = {
      laser_charge = { relay = "redstone_relay_0", side = "top", analog = 15, pulse = false },
      deuterium = { relay = "redstone_relay_1", side = "front", analog = 15, pulse = false },
      tritium = { relay = "redstone_relay_2", side = "front", analog = 15, pulse = false },
      laser_fire = { relay = "redstone_relay_0", side = "top", analog = 15, pulse = true, pulseTime = 0.15 },
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
    basePadX = 1,
    basePadY = 1,
    smallBoostPadX = 2,
    smallBoostPadY = 1,
    rowPadX = 1,
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
