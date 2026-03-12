-- fusion.lua
-- Bootstrap/Orchestrateur minimal.
-- Règle d'architecture (obligatoire pour toutes les phases futures):
-- - logique métier lourde dans core/
-- - rendu/UI lourd dans ui/
-- - accès matériel dans io/
-- - ce fichier ne doit contenir que le bootstrap runtime

local CoreApp = require("core.app")

CoreApp.run()
