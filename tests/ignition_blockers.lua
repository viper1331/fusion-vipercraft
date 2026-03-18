-- tests/ignition_blockers.lua
-- Verifie qu'une charge laser suffisante autorise l'ignition
-- meme si la ligne de charge est OFF.

local M = {}

function M.run(ctx)
  local fail = assert(ctx.fail, "ctx.fail requis")
  local ok = assert(ctx.ok, "ctx.ok requis")
  local toPath = assert(ctx.toPath, "ctx.toPath requis")

  local alertsPath = toPath("core/alerts.lua")
  local previousRequire = _G.require
  _G.require = function(name)
    local relPath = tostring(name or ""):gsub("%.", "/") .. ".lua"
    return dofile(toPath(relPath))
  end
  local loadOk, Alerts = pcall(dofile, alertsPath)
  _G.require = previousRequire
  if not loadOk or type(Alerts) ~= "table" or type(Alerts.build) ~= "function" then
    fail(90, "Impossible de charger core/alerts.lua")
    return
  end

  local function contains(str, sub)
    return tostring(str or ""):lower():find(tostring(sub or ""):lower(), 1, true) ~= nil
  end

  local function toNumber(value, default)
    local n = tonumber(value)
    if n == nil then return default or 0 end
    return n
  end

  local function buildRuntime(stateOverrides)
    local state = {
      alert = "INFO",
      reactorPresent = true,
      reactorFormed = true,
      ignition = false,
      ignitionSequencePending = false,
      ignitionBlockers = {},
      ignitionChecklist = {},
      safetyWarnings = { "IGNITION BLOCKED" },
      laserPresent = true,
      laserEnergy = 2500000000,
      laserEnergySourceUnit = "j",
      laserPct = 100,
      laserChargeOn = false,
      laserLineOn = false,
      dtOpen = false,
      dOpen = true,
      tOpen = true,
      hohlraumPresent = true,
      energyKnown = false,
      energyPct = 0,
    }

    for k, v in pairs(stateOverrides or {}) do
      state[k] = v
    end

    local runtime = Alerts.build({
      state = state,
      hw = {
        relays = {
          relay_las = {},
          relay_d = {},
          relay_t = {},
        },
        readerRoles = { deuterium = {}, tritium = {}, inventory = {}, active = {}, unknown = {} },
      },
      CFG = {
        energyUnit = "j",
        ignitionLaserEnergyThreshold = 2500000000,
        actions = {
          laser_charge = { relay = "relay_las", side = "top" },
          deuterium = { relay = "relay_d", side = "front" },
          tritium = { relay = "relay_t", side = "front" },
        },
      },
      C = { ok = 1, warn = 2, bad = 4, dim = 8 },
      contains = contains,
      toNumber = toNumber,
      CoreReactor = { canIgnite = function() return true end },
    })

    return runtime, state
  end

  local runtimeReady, stateReady = buildRuntime({
    laserEnergy = 2500000000,
    laserChargeOn = false,
    laserLineOn = false,
  })
  runtimeReady.updateAlerts()
  if stateReady.laserState ~= "READY" then
    fail(91, "Etat laser devrait etre READY au-dessus du seuil")
  else
    ok("Etat laser READY coherent avec energie reelle")
  end
  if #stateReady.ignitionBlockers ~= 0 then
    fail(92, "Aucun blocker attendu quand LAS est charge et prerequis OK")
  else
    ok("Aucun faux blocker LAS OFF quand charge suffisante")
  end
  if not runtimeReady.canIgnite() then
    fail(93, "canIgnite doit etre true si energie laser suffisante")
  else
    ok("canIgnite true avec LAS charge")
  end

  local runtimeLow, stateLow = buildRuntime({
    laserEnergy = 2499999999,
    laserChargeOn = false,
    laserLineOn = false,
  })
  runtimeLow.updateAlerts()
  if stateLow.laserState ~= "INSUFFICIENT" then
    fail(94, "Etat laser insuffisant attendu sous le seuil")
  else
    ok("Etat laser insuffisant detecte sous seuil")
  end
  if #stateLow.ignitionBlockers == 0 then
    fail(95, "Blocker attendu quand energie laser est sous le seuil")
  else
    ok("Blocker LAS sous seuil detecte")
  end

  local runtimeCharging, stateCharging = buildRuntime({
    laserEnergy = 2000000000,
    laserChargeOn = true,
    laserLineOn = false,
  })
  runtimeCharging.updateAlerts()
  if stateCharging.laserState ~= "CHARGING" then
    fail(96, "Etat CHARGING attendu quand la charge est active")
  else
    ok("Etat CHARGING coherent")
  end
end

return M
