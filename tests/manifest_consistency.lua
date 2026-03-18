-- tests/manifest_consistency.lua
-- Valide la coherence de fusion.manifest.json.

local M = {}

local function trim(text)
  text = tostring(text or "")
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function isLikelyRelativePath(path)
  if type(path) ~= "string" then return false end
  local clean = trim(path)
  if clean == "" then return false end
  if clean:sub(1, 1) == "/" then return false end
  if clean:find("^%a:[/\\]") then return false end
  if clean:find("%.%.") then return false end
  return true
end

function M.run(ctx)
  local fail = assert(ctx.fail, "ctx.fail requis")
  local ok = assert(ctx.ok, "ctx.ok requis")
  local manifest = ctx.manifest
  local version = tostring(ctx.version or "")
  local toPath = assert(ctx.toPath, "ctx.toPath requis")
  local exists = assert(ctx.exists, "ctx.exists requis")

  if type(manifest) ~= "table" then
    fail(40, "Manifest non charge (table attendue)")
    return
  end

  local manifestVersion = trim(manifest.version)
  if manifestVersion == "" then
    fail(41, "manifest.version absent ou vide")
  elseif version ~= "" and manifestVersion ~= version then
    fail(42, "Version mismatch: fusion.version=" .. version .. ", manifest.version=" .. manifestVersion)
  else
    ok("Version manifest coherente: " .. manifestVersion)
  end

  if type(manifest.files) ~= "table" then
    fail(43, "manifest.files absent ou invalide")
    return
  end

  if #manifest.files == 0 then
    fail(44, "manifest.files est vide")
    return
  end

  ok("manifest.files detecte: " .. tostring(#manifest.files) .. " fichiers")

  local seen = {}
  for i, relPath in ipairs(manifest.files) do
    local filePath = trim(relPath)
    if not isLikelyRelativePath(filePath) then
      fail(45, "manifest.files[" .. tostring(i) .. "] invalide: " .. tostring(relPath))
    elseif seen[filePath] then
      fail(46, "Doublon dans manifest.files: " .. filePath)
    else
      seen[filePath] = true
      local fullPath = toPath(filePath)
      if not exists(fullPath) or fs.isDir(fullPath) then
        fail(47, "Fichier manquant depuis manifest: " .. filePath)
      else
        ok("Present: " .. filePath)
      end
    end
  end
end

return M
