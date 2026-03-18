-- tests/laser_threshold.lua
-- Verifie la coherence de seuil laser selon l'unite source.

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
    fail(70, "Impossible de charger core/alerts.lua")
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

  local function makeRuntime(stateOverrides)
    local state = {
      alert = "INFO",
      reactorPresent = true,
      reactorFormed = true,
      ignition = false,
      ignitionSequencePending = false,
      ignitionBlockers = {},
      safetyWarnings = {},
      laserChargeOn = false,
      laserLineOn = false,
      laserPresent = true,
      laserEnergy = 0,
      laserEnergySourceUnit = "j",
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

    return Alerts.build({
      state = state,
      hw = {
        relays = {},
        readerRoles = { deuterium = {}, tritium = {}, inventory = {}, active = {}, unknown = {} },
      },
      CFG = {
        energyUnit = "fe",
        ignitionLaserEnergyThreshold = 2500000000,
        actions = {},
      },
      C = { ok = 1, warn = 2, bad = 4, dim = 8 },
      contains = contains,
      toNumber = toNumber,
      CoreReactor = { canIgnite = function() return true end },
    }), state
  end

  local runtimeJ = makeRuntime({
    laserEnergySourceUnit = "j",
    laserEnergy = 2500000000,
  })
  local thresholdJ = runtimeJ.getLaserThresholdRaw()
  if math.abs(thresholdJ - 2500000000) > 1e-3 then
    fail(71, "Seuil laser brut J invalide")
  else
    ok("Seuil laser brut J valide")
  end
  if not runtimeJ.isLaserReady() then
    fail(72, "Etat LAS READY invalide en unite J")
  else
    ok("Etat LAS READY valide en unite J")
  end

  local runtimeFe = makeRuntime({
    laserEnergySourceUnit = "fe",
    laserEnergy = 1000000000,
  })
  local thresholdFe = runtimeFe.getLaserThresholdRaw()
  if math.abs(thresholdFe - 1000000000) > 1e-3 then
    fail(73, "Seuil laser brut FE invalide")
  else
    ok("Seuil laser brut FE valide")
  end
  if not runtimeFe.isLaserReady() then
    fail(74, "Etat LAS READY invalide en unite FE")
  else
    ok("Etat LAS READY valide en unite FE")
  end

  local runtimeNotReady = makeRuntime({
    laserEnergySourceUnit = "fe",
    laserEnergy = 999999999,
  })
  if runtimeNotReady.isLaserReady() then
    fail(75, "Etat LAS READY devrait etre false sous le seuil")
  else
    ok("Etat LAS READY false valide sous le seuil")
  end
end

return M
