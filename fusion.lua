-- fusion.lua
-- Bootstrap/Orchestrateur minimal.
-- Règle d'architecture (obligatoire pour toutes les phases futures):
-- - logique métier lourde dans core/
-- - rendu/UI lourd dans ui/
-- - accès matériel dans io/
-- - ce fichier ne doit contenir que le bootstrap runtime

local CoreApp = require("core.app")

local args = { ... }
local options = {
  tomsDebug = false,
}

for _, raw in ipairs(args) do
  local arg = string.lower(tostring(raw or ""))
  if arg == "--toms-debug" or arg == "--tom-debug" then
    options.tomsDebug = true
  end
end

CoreApp.run(options)
