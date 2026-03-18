-- tests/temperature_units.lua
-- Verifie les conversions temperature K <-> C centralisees.

local M = {}

function M.run(ctx)
  local fail = assert(ctx.fail, "ctx.fail requis")
  local ok = assert(ctx.ok, "ctx.ok requis")
  local toPath = assert(ctx.toPath, "ctx.toPath requis")

  local tempPath = toPath("core/temperature.lua")
  local loadOk, Temp = pcall(dofile, tempPath)
  if not loadOk or type(Temp) ~= "table" then
    fail(90, "Impossible de charger core/temperature.lua")
    return
  end

  local function approxEqual(a, b, eps)
    return math.abs((tonumber(a) or 0) - (tonumber(b) or 0)) <= (eps or 1e-9)
  end

  local celsius = Temp.toCelsius(295, "k")
  if not approxEqual(celsius, 21.85, 1e-2) then
    fail(91, "Conversion Kelvin->Celsius invalide (295K)")
  else
    ok("Conversion Kelvin->Celsius valide (295K)")
  end

  local passthrough = Temp.toCelsius(42.5, "c")
  if not approxEqual(passthrough, 42.5, 1e-9) then
    fail(92, "Conversion Celsius passthrough invalide")
  else
    ok("Conversion Celsius passthrough valide")
  end

  local parsedUnit = Temp.sourceUnitFromString("kelvin", "c")
  if parsedUnit ~= "k" then
    fail(93, "Detection unite temperature invalide")
  else
    ok("Detection unite temperature valide")
  end

  local label = Temp.formatTemperature(295, "k", { compact = true, decimals = 2 })
  if label ~= "21.85C" then
    fail(94, "Format temperature invalide")
  else
    ok("Format temperature valide")
  end
end

return M
