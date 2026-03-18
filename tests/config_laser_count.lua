-- tests/config_laser_count.lua
-- Verifie la configuration persistante du nombre de lasers.

local M = {}

function M.run(ctx)
  local fail = assert(ctx.fail, "ctx.fail requis")
  local ok = assert(ctx.ok, "ctx.ok requis")
  local toPath = assert(ctx.toPath, "ctx.toPath requis")

  local configPath = toPath("core/config.lua")
  local loadOk, CoreConfig = pcall(dofile, configPath)
  if not loadOk or type(CoreConfig) ~= "table" then
    fail(100, "Impossible de charger core/config.lua")
    return
  end

  if type(CoreConfig.sanitizeLaserCount) ~= "function" then
    fail(101, "sanitizeLaserCount manquante")
    return
  end

  if CoreConfig.sanitizeLaserCount(nil, 3) ~= 3 then
    fail(102, "sanitizeLaserCount fallback invalide")
  else
    ok("sanitizeLaserCount fallback valide")
  end

  if CoreConfig.sanitizeLaserCount(0, 1) ~= 1 then
    fail(103, "sanitizeLaserCount doit borner min a 1")
  else
    ok("sanitizeLaserCount borne min valide")
  end

  if CoreConfig.sanitizeLaserCount(99, 1) ~= 16 then
    fail(104, "sanitizeLaserCount doit borner max a 16")
  else
    ok("sanitizeLaserCount borne max valide")
  end

  local runtimeCfg = {
    preferredMonitor = nil,
    monitorScale = 0.5,
    uiScale = 1.0,
    displayOutput = "monitor",
    energyUnit = "j",
    laserCount = 1,
    refreshDelay = 0.2,
    preferredReactor = nil,
    preferredLogicAdapter = nil,
    preferredLaser = nil,
    preferredInduction = nil,
    knownReaders = { deuterium = nil, tritium = nil, inventory = nil },
    knownRelays = {
      laser_charge = { relay = nil, side = "top" },
      tritium = { relay = nil, side = "front" },
      deuterium = { relay = nil, side = "front" },
    },
  }

  local defaultCfg = CoreConfig.defaultFusionConfig(runtimeCfg, true)
  local laserCountValue = defaultCfg
    and defaultCfg.ui
    and defaultCfg.ui.laserCount
    or nil
  if laserCountValue ~= 1 then
    fail(105, "defaultFusionConfig doit initialiser ui.laserCount a 1")
  else
    ok("defaultFusionConfig ui.laserCount valide")
  end

  CoreConfig.applyConfigToRuntime({
    monitor = { name = nil, scale = 0.5 },
    devices = {},
    relays = {},
    readers = {},
    ui = {
      scale = 1.0,
      output = "monitor",
      energyUnit = "j",
      laserCount = 4,
      refreshDelay = 0.2,
    },
  }, runtimeCfg)

  if runtimeCfg.laserCount ~= 4 then
    fail(106, "applyConfigToRuntime doit appliquer ui.laserCount")
  else
    ok("applyConfigToRuntime ui.laserCount applique")
  end
end

return M
