-- tests/smoke.lua
-- Orchestrateur de validation locale (CraftOS-PC headless compatible).
-- Objectif: verifier rapidement l'integrite du projet avant modification/push.

local EXIT = {
  OK = 0,
  VERSION_MISSING = 10,
  VERSION_EMPTY = 11,
  VERSION_INVALID = 12,
  MANIFEST_MISSING = 20,
  MANIFEST_EMPTY = 21,
  MANIFEST_INVALID = 22,
  MODULE_LOAD_ERROR = 23,
}

local failures = {}
local exitCode = EXIT.OK

local function trim(text)
  text = tostring(text or "")
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local basePath = trim(({ ... })[1] or "")

local function toPath(relPath)
  if basePath == "" then
    return relPath
  end
  return fs.combine(basePath, relPath)
end

local function setExit(code)
  if exitCode == EXIT.OK then
    exitCode = code
  end
end

local function fail(code, msg)
  failures[#failures + 1] = msg
  setExit(code)
  print("[FAIL] " .. msg)
end

local function ok(msg)
  print("[OK] " .. msg)
end

local function readAll(path)
  local handle = fs.open(path, "r")
  if not handle then
    return nil
  end
  local data = handle.readAll()
  handle.close()
  return data
end

local function expectFile(path, label, codeIfMissing)
  if not fs.exists(path) or fs.isDir(path) then
    fail(codeIfMissing, label .. " manquant: " .. path)
    return false
  end
  ok(label .. " present: " .. path)
  return true
end

local function loadModule(moduleName)
  local scriptPath = (shell and shell.getRunningProgram and shell.getRunningProgram()) or "tests/smoke.lua"
  local scriptDir = fs.getDir(scriptPath)
  local modulePath = fs.combine(scriptDir, moduleName)
  local loadOk, moduleOrErr = pcall(dofile, modulePath)
  if not loadOk then
    fail(EXIT.MODULE_LOAD_ERROR, "Echec chargement module " .. moduleName .. ": " .. tostring(moduleOrErr))
    return nil
  end
  if type(moduleOrErr) ~= "table" or type(moduleOrErr.run) ~= "function" then
    fail(EXIT.MODULE_LOAD_ERROR, "Module invalide: " .. moduleName)
    return nil
  end
  ok("Module test charge: " .. moduleName)
  return moduleOrErr
end

if basePath ~= "" then
  print("[INFO] Base path: " .. basePath)
end

local versionPath = toPath("fusion.version")
local manifestPath = toPath("fusion.manifest.json")

local versionValue = ""
if expectFile(versionPath, "Version", EXIT.VERSION_MISSING) then
  versionValue = trim(readAll(versionPath))
  if versionValue == "" then
    fail(EXIT.VERSION_EMPTY, "fusion.version est vide")
  elseif not string.match(versionValue, "^%d+%.%d+%.%d+$") then
    fail(EXIT.VERSION_INVALID, "fusion.version format invalide (attendu: X.Y.Z): " .. versionValue)
  else
    ok("fusion.version valide: " .. versionValue)
  end
end

local manifest = nil
if expectFile(manifestPath, "Manifest", EXIT.MANIFEST_MISSING) then
  local rawManifest = readAll(manifestPath)
  if not rawManifest or trim(rawManifest) == "" then
    fail(EXIT.MANIFEST_EMPTY, "fusion.manifest.json est vide ou illisible")
  elseif not textutils or type(textutils.unserializeJSON) ~= "function" then
    fail(EXIT.MANIFEST_INVALID, "Parser JSON indisponible (textutils.unserializeJSON)")
  else
    local parseOk, parsed = pcall(textutils.unserializeJSON, rawManifest)
    if not parseOk or type(parsed) ~= "table" then
      fail(EXIT.MANIFEST_INVALID, "fusion.manifest.json invalide")
    else
      manifest = parsed
      ok("fusion.manifest.json parse correctement")
    end
  end
end

local modules = {
  "project_structure.lua",
  "manifest_consistency.lua",
  "energy_units.lua",
  "temperature_units.lua",
  "laser_device_selection.lua",
  "laser_threshold.lua",
  "ignition_blockers.lua",
  "config_laser_count.lua",
  "logger.lua",
  "display_backend.lua",
  "display_selection_preference.lua",
  "monitor_backend_bridge.lua",
  "install_display_dtfuel_config.lua",
  "reactor_diagram_render.lua",
  "responsive_render.lua",
}

local baseCtx = {
  fail = fail,
  ok = ok,
  toPath = toPath,
  exists = fs.exists,
  manifest = manifest,
  version = versionValue,
}

for _, moduleName in ipairs(modules) do
  local mod = loadModule(moduleName)
  if mod then
    local runOk, runErr = pcall(mod.run, baseCtx)
    if not runOk then
      fail(EXIT.MODULE_LOAD_ERROR, "Execution module " .. moduleName .. " echouee: " .. tostring(runErr))
    end
  end
end

if #failures > 0 then
  print("SMOKE RESULT: FAIL (" .. tostring(#failures) .. " erreurs)")
  print("SMOKE_EXIT_CODE=" .. tostring(exitCode))
  -- Retour non nul pour shell.run: false.
  error("SMOKE_FAILED_CODE_" .. tostring(exitCode), 0)
end

print("SMOKE RESULT: OK")
print("SMOKE_EXIT_CODE=0")
