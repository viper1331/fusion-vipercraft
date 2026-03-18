-- tests/laser_device_selection.lua
-- Verifie la selection du bon peripherique laser (amplifier prioritaire).

local M = {}

function M.run(ctx)
  local fail = assert(ctx.fail, "ctx.fail requis")
  local ok = assert(ctx.ok, "ctx.ok requis")
  local toPath = assert(ctx.toPath, "ctx.toPath requis")

  local devicesPath = toPath("io/devices.lua")
  local loadOk, Devices = pcall(dofile, devicesPath)
  if not loadOk or type(Devices) ~= "table" then
    fail(80, "Impossible de charger io/devices.lua")
    return
  end

  local fakePeripherals = {
    laser_0 = {
      getEnergy = function() return 1990000 end,
      getEnergyFilledPercentage = function() return 0.995 end,
      getMaxEnergy = function() return 2000000 end,
    },
    laserAmplifier_1 = {
      getEnergy = function() return 5000000000 end,
      getEnergyFilledPercentage = function() return 1 end,
      getMaxEnergy = function() return 5000000000 end,
      getMinThreshold = function() return 0 end,
      getMaxThreshold = function() return 5000000000 end,
    },
  }

  local peripheralApi = {
    getNames = function()
      return { "laser_0", "laserAmplifier_1" }
    end,
  }

  local function safePeripheral(name)
    return fakePeripherals[name]
  end

  local function getTypeOf(name)
    if name == "laserAmplifier_1" then return "laserAmplifier" end
    if name == "laser_0" then return "laser" end
    return nil
  end

  local function contains(str, sub)
    return tostring(str or ""):lower():find(tostring(sub or ""):lower(), 1, true) ~= nil
  end

  if type(Devices.detectBestLaserPeripheral) ~= "function" then
    fail(81, "detectBestLaserPeripheral manquant")
    return
  end

  local obj, name = Devices.detectBestLaserPeripheral(peripheralApi, nil, safePeripheral, getTypeOf, contains)
  if name ~= "laserAmplifier_1" or obj ~= fakePeripherals.laserAmplifier_1 then
    fail(82, "Selection laser incorrecte (amplifier attendu)")
  else
    ok("Selection laser amplifier prioritaire: OK")
  end

  -- Scenario 2:
  -- Le type peut etre remonte en camelCase ("laserAmplifier").
  -- On verifie que ce cas reste prioritaire face a un laser classique.
  local fakePeripherals2 = {
    laser_0 = {
      getEnergy = function() return 2000000 end,
      getMaxEnergy = function() return 2000000 end,
    },
    laserAmplifier_1 = {
      getEnergy = function() return 2000000 end,
      getMaxEnergy = function() return 2000000 end,
      getEnergyFilledPercentage = function() return 1 end,
    },
  }

  local function safePeripheral2(name)
    return fakePeripherals2[name]
  end

  local function getTypeOf2(name)
    if name == "laserAmplifier_1" then return "laserAmplifier" end
    if name == "laser_0" then return "laser" end
    return nil
  end

  local obj2, name2 = Devices.detectBestLaserPeripheral(peripheralApi, nil, safePeripheral2, getTypeOf2, contains)
  if name2 ~= "laserAmplifier_1" or obj2 ~= fakePeripherals2.laserAmplifier_1 then
    fail(83, "Selection laser incorrecte en type camelCase")
  else
    ok("Selection laser (camelCase) prioritaire: OK")
  end
end

return M
