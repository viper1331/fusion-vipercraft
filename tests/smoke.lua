-- tests/smoke.lua
-- Smoke test CraftOS-PC pour valider l'integrite minimale du package.

local failures = {}

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

local function fail(msg)
  failures[#failures + 1] = msg
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

local function expectFile(path, label)
  if not fs.exists(path) then
    fail(label .. " manquant: " .. path)
    return false
  end
  ok(label .. " present: " .. path)
  return true
end

if basePath ~= "" then
  print("[INFO] Base path: " .. basePath)
end

local versionPath = toPath("fusion.version")
local manifestPath = toPath("fusion.manifest.json")

local hasVersion = expectFile(versionPath, "Version")
local hasManifest = expectFile(manifestPath, "Manifest")

if hasVersion then
  local rawVersion = readAll(versionPath)
  local version = trim(rawVersion)
  if version == "" then
    fail("fusion.version est vide")
  else
    ok("fusion.version non vide: " .. version)
  end
end

if hasManifest then
  local rawManifest = readAll(manifestPath)
  if not rawManifest or trim(rawManifest) == "" then
    fail("fusion.manifest.json est vide ou illisible")
  else
    local parsed = nil
    if textutils and type(textutils.unserializeJSON) == "function" then
      local parseOk, manifestOrErr = pcall(textutils.unserializeJSON, rawManifest)
      if parseOk and type(manifestOrErr) == "table" then
        parsed = manifestOrErr
      else
        fail("fusion.manifest.json invalide")
      end
    else
      fail("Parser JSON indisponible (textutils.unserializeJSON)")
    end

    if parsed then
      if type(parsed.files) ~= "table" then
        fail("manifest.files absent ou invalide")
      elseif #parsed.files == 0 then
        fail("manifest.files est vide")
      else
        ok("manifest.files detecte: " .. tostring(#parsed.files) .. " fichiers")
        for i, path in ipairs(parsed.files) do
          if type(path) ~= "string" or trim(path) == "" then
            fail("manifest.files[" .. tostring(i) .. "] invalide")
          else
            local fullPath = toPath(path)
            if not fs.exists(fullPath) then
              fail("Fichier manquant depuis manifest: " .. path)
            else
              ok("Present: " .. path)
            end
          end
        end
      end
    end
  end
end

if #failures > 0 then
  print("SMOKE RESULT: FAIL (" .. tostring(#failures) .. " erreurs)")
  -- Permet une sortie non nulle via shell.run (retour false).
  error("SMOKE_FAILED", 0)
end

print("SMOKE RESULT: OK")
