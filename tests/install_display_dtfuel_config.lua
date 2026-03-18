-- tests/install_display_dtfuel_config.lua
-- Verifie les champs de config ajoutes pour backend display et DT fuel.

local M = {}

function M.run(ctx)
  local fail = assert(ctx.fail, "ctx.fail requis")
  local ok = assert(ctx.ok, "ctx.ok requis")
  local toPath = assert(ctx.toPath, "ctx.toPath requis")

  local loadOk, CoreConfig = pcall(dofile, toPath("core/config.lua"))
  if not loadOk or type(CoreConfig) ~= "table" then
    fail(120, "Impossible de charger core/config.lua")
    return
  end

  local runtimeCfg = {
    preferredMonitor = nil,
    monitorScale = 0.5,
    uiScale = 1.0,
    displayOutput = "monitor",
    displayBackend = "auto",
    energyUnit = "j",
    laserCount = 1,
    refreshDelay = 0.2,
    logEnabled = true,
    logLevel = "info",
    logToFile = true,
    logToTerminal = false,
    logFile = "fusion.log",
    logMaxFileBytes = 262144,
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
    actions = {
      dt_fuel = nil,
    },
  }

  local defaultCfg = CoreConfig.defaultFusionConfig(runtimeCfg, true)
  if not (defaultCfg and defaultCfg.ui and defaultCfg.ui.displayBackend == "auto") then
    fail(121, "defaultFusionConfig doit inclure ui.displayBackend=auto")
  else
    ok("defaultFusionConfig ui.displayBackend valide")
  end

  if not (defaultCfg and defaultCfg.actions and type(defaultCfg.actions.dt_fuel) == "table") then
    fail(122, "defaultFusionConfig doit inclure actions.dt_fuel")
  else
    ok("defaultFusionConfig actions.dt_fuel present")
  end

  local validCfg = {
    monitor = { name = nil, scale = 0.5 },
    devices = {},
    relays = {
      laser = { name = nil, side = "top" },
      tritium = { name = nil, side = "front" },
      deuterium = { name = nil, side = "front" },
      dtFuel = { name = "relay_dt_a", side = "back" },
    },
    readers = {},
    ui = {
      preferredView = "SUP",
      scale = 1.0,
      output = "monitor",
      displayBackend = "toms_gpu",
      energyUnit = "j",
      laserCount = 2,
      refreshDelay = 0.2,
    },
    actions = {
      dt_fuel = {
        relay = "relay_dt_a",
        side = "back",
      },
    },
  }

  local cfgOk, cfgErrors = CoreConfig.validateConfig(validCfg)
  if not cfgOk then
    fail(123, "validateConfig doit accepter ui.displayBackend/actions.dt_fuel: " .. tostring(cfgErrors and cfgErrors[1]))
  else
    ok("validateConfig accepte ui.displayBackend/actions.dt_fuel")
  end

  CoreConfig.applyConfigToRuntime(validCfg, runtimeCfg)
  if runtimeCfg.displayBackend ~= "toms_gpu" then
    fail(124, "applyConfigToRuntime doit appliquer ui.displayBackend")
  else
    ok("applyConfigToRuntime ui.displayBackend applique")
  end

  if type(runtimeCfg.actions.dt_fuel) ~= "table" then
    fail(125, "applyConfigToRuntime doit initialiser actions.dt_fuel")
  elseif runtimeCfg.actions.dt_fuel.relay ~= "relay_dt_a" or runtimeCfg.actions.dt_fuel.side ~= "back" then
    fail(126, "applyConfigToRuntime doit appliquer relay/side DT fuel")
  else
    ok("applyConfigToRuntime actions.dt_fuel applique")
  end

  local fallbackCfg = {
    monitor = { name = nil, scale = 0.5 },
    devices = {},
    relays = {
      laser = { name = nil, side = "top" },
      tritium = { name = nil, side = "front" },
      deuterium = { name = nil, side = "front" },
      dtFuel = { name = "relay_dt_b", side = "left" },
    },
    readers = {},
    ui = {
      preferredView = "SUP",
      scale = 1.0,
      output = "monitor",
      displayBackend = "cc_monitor",
      energyUnit = "j",
      laserCount = 1,
      refreshDelay = 0.2,
    },
    actions = {},
  }

  CoreConfig.applyConfigToRuntime(fallbackCfg, runtimeCfg)
  if type(runtimeCfg.actions.dt_fuel) ~= "table"
    or runtimeCfg.actions.dt_fuel.relay ~= "relay_dt_b"
    or runtimeCfg.actions.dt_fuel.side ~= "left" then
    fail(127, "Fallback relays.dtFuel -> actions.dt_fuel invalide")
  else
    ok("Fallback relays.dtFuel -> actions.dt_fuel valide")
  end

  local invalidCfg = {
    monitor = { name = nil, scale = 0.5 },
    devices = {},
    relays = {
      laser = { name = nil, side = "top" },
      tritium = { name = nil, side = "front" },
      deuterium = { name = nil, side = "front" },
    },
    readers = {},
    ui = {
      preferredView = "SUP",
      scale = 1.0,
      output = "monitor",
      displayBackend = "invalid_backend",
      energyUnit = "j",
      laserCount = 1,
      refreshDelay = 0.2,
    },
  }
  local invalidOk = CoreConfig.validateConfig(invalidCfg)
  if invalidOk then
    fail(128, "validateConfig doit refuser ui.displayBackend invalide")
  else
    ok("validateConfig refuse ui.displayBackend invalide")
  end
end

return M
