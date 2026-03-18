-- tests/energy_units.lua
-- Verifie les conversions FE <-> J centralisees.

local M = {}

function M.run(ctx)
  local fail = assert(ctx.fail, "ctx.fail requis")
  local ok = assert(ctx.ok, "ctx.ok requis")
  local toPath = assert(ctx.toPath, "ctx.toPath requis")

  local energyPath = toPath("core/energy.lua")
  local loadOk, Energy = pcall(dofile, energyPath)
  if not loadOk or type(Energy) ~= "table" then
    fail(60, "Impossible de charger core/energy.lua")
    return
  end

  local function approxEqual(a, b, eps)
    return math.abs((tonumber(a) or 0) - (tonumber(b) or 0)) <= (eps or 1e-9)
  end

  if not approxEqual(Energy.J_PER_FE, 2.5, 1e-12) then
    fail(61, "Constante J_PER_FE invalide")
  else
    ok("Constante J_PER_FE valide")
  end

  if not approxEqual(Energy.FE_PER_J, 0.4, 1e-12) then
    fail(62, "Constante FE_PER_J invalide")
  else
    ok("Constante FE_PER_J valide")
  end

  local sampleFe = 1000
  local inJ = Energy.toJ(sampleFe, "fe")
  if not approxEqual(inJ, 2500, 1e-6) then
    fail(63, "Conversion FE->J invalide")
  else
    ok("Conversion FE->J valide")
  end

  local backToFe = Energy.fromJ(inJ, "fe")
  if not approxEqual(backToFe, sampleFe, 1e-6) then
    fail(64, "Conversion J->FE invalide")
  else
    ok("Conversion J->FE valide")
  end

  local thresholdFe = Energy.thresholdFromJToSource(2000000000, "fe")
  if not approxEqual(thresholdFe, 800000000, 1e-3) then
    fail(65, "Conversion seuil laser J->FE invalide")
  else
    ok("Conversion seuil laser J->FE valide")
  end
end

return M
