-- core/energy.lua
-- Utilitaires energie centralises (J <-> FE).

local M = {}

M.J_PER_FE = 2.5
M.FE_PER_J = 1 / M.J_PER_FE

local function toNumber(value, fallback)
  local n = tonumber(value)
  if n == nil then return fallback or 0 end
  return n
end

function M.sanitizeUnit(unit, fallback)
  local normalized = string.lower(tostring(unit or ""))
  if normalized == "fe" then return "fe" end
  if normalized == "j" then return "j" end
  return fallback or "j"
end

function M.sourceUnitFromString(value, fallback)
  local raw = string.lower(tostring(value or ""))
  if raw == "j" or raw == "joule" or raw == "joules" then return "j" end
  if raw == "fe" or raw == "rf" or raw == "forge_energy" then return "fe" end
  return M.sanitizeUnit(fallback, "j")
end

function M.fromJ(joules, targetUnit)
  local j = toNumber(joules, 0)
  local unit = M.sanitizeUnit(targetUnit, "j")
  if unit == "fe" then
    return j * M.FE_PER_J
  end
  return j
end

function M.toJ(value, sourceUnit)
  local energy = toNumber(value, 0)
  local unit = M.sanitizeUnit(sourceUnit, "j")
  if unit == "fe" then
    return energy * M.J_PER_FE
  end
  return energy
end

function M.scale(value)
  local n = toNumber(value, 0)
  local absn = math.abs(n)
  local units = {
    { 1e15, "P" },
    { 1e12, "T" },
    { 1e9, "G" },
    { 1e6, "M" },
    { 1e3, "k" },
  }

  for _, u in ipairs(units) do
    if absn >= u[1] then
      return n / u[1], u[2]
    end
  end

  return n, ""
end

function M.formatScaled(value, suffix, opts)
  opts = type(opts) == "table" and opts or {}
  local compact = opts.compact == true
  local decimals = tonumber(opts.decimals)
  if decimals == nil then decimals = 2 end

  local scaled, prefix = M.scale(value)
  if prefix == "" then
    if compact then
      return string.format("%." .. tostring(math.max(0, decimals)) .. "f%s", scaled, suffix)
    end
    return string.format("%." .. tostring(math.max(0, decimals)) .. "f %s", scaled, suffix)
  end

  if compact then
    return string.format("%." .. tostring(math.max(0, decimals)) .. "f%s%s", scaled, prefix, suffix)
  end
  return string.format("%." .. tostring(math.max(0, decimals)) .. "f %s%s", scaled, prefix, suffix)
end

function M.formatEnergyFromJ(joules, displayUnit, opts)
  local unit = M.sanitizeUnit(displayUnit, "j")
  local suffix = unit == "fe" and "FE" or "J"
  local displayValue = M.fromJ(joules, unit)
  return M.formatScaled(displayValue, suffix, opts)
end

function M.formatEnergyPerTickFromJ(joulesPerTick, displayUnit, opts)
  return M.formatEnergyFromJ(joulesPerTick, displayUnit, opts) .. "/t"
end

function M.thresholdFromJToSource(joulesThreshold, sourceUnit)
  return M.fromJ(joulesThreshold, sourceUnit)
end

return M
