-- core/temperature.lua
-- Utilitaires temperature centralises (K <-> C) pour l'UI.

local M = {}

local function toNumber(value, fallback)
  local n = tonumber(value)
  if n == nil then return fallback or 0 end
  return n
end

function M.sanitizeUnit(unit, fallback)
  local raw = string.lower(tostring(unit or ""))
  if raw == "k" or raw == "kelvin" then return "k" end
  if raw == "c" or raw == "celsius" or raw == "degc" or raw == "degree_celsius" then return "c" end
  return fallback or "k"
end

function M.sourceUnitFromString(value, fallback)
  local raw = string.lower(tostring(value or ""))
  if raw == "k" or raw == "kelvin" or raw == "degrees_k" then return "k" end
  if raw == "c" or raw == "celsius" or raw == "degc" or raw == "degrees_c" then return "c" end
  if raw:find("kelvin", 1, true) then return "k" end
  if raw:find("celsius", 1, true) then return "c" end
  return M.sanitizeUnit(fallback, "k")
end

function M.toCelsius(value, sourceUnit)
  local unit = M.sanitizeUnit(sourceUnit, "k")
  local n = toNumber(value, 0)
  if unit == "k" then
    return n - 273.15
  end
  return n
end

function M.scaleCelsius(value)
  local n = toNumber(value, 0)
  local absn = math.abs(n)

  if absn >= 1e9 then
    return n / 1e9, "GC"
  end
  if absn >= 1e6 then
    return n / 1e6, "MC"
  end
  if absn >= 1e3 then
    return n / 1e3, "kC"
  end
  return n, "C"
end

function M.formatTemperature(value, sourceUnit, opts)
  opts = type(opts) == "table" and opts or {}
  local compact = opts.compact == true
  local decimals = tonumber(opts.decimals)
  if decimals == nil then decimals = 2 end
  if decimals < 0 then decimals = 0 end

  local c = M.toCelsius(value, sourceUnit)
  local scaled, suffix = M.scaleCelsius(c)
  if compact then
    return string.format("%." .. tostring(decimals) .. "f%s", scaled, suffix)
  end
  return string.format("%." .. tostring(decimals) .. "f %s", scaled, suffix)
end

return M
