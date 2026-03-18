-- tests/logger.lua
-- Verifie le module de logging central.

local M = {}

local function trim(text)
  text = tostring(text or "")
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

function M.run(ctx)
  local fail = assert(ctx.fail, "ctx.fail requis")
  local ok = assert(ctx.ok, "ctx.ok requis")
  local toPath = assert(ctx.toPath, "ctx.toPath requis")

  local loadOk, Logger = pcall(dofile, toPath("core/logger.lua"))
  if not loadOk or type(Logger) ~= "table" or type(Logger.new) ~= "function" then
    fail(110, "Impossible de charger core/logger.lua")
    return
  end
  ok("Module logger charge")

  local tmpLog = toPath("tests/.tmp_fusion_logger.log")
  local rotated = tmpLog .. ".1"
  if fs.exists(tmpLog) then pcall(fs.delete, tmpLog) end
  if fs.exists(rotated) then pcall(fs.delete, rotated) end

  local logger = Logger.new({
    fs = fs,
    enabled = true,
    level = "warn",
    toFile = true,
    toTerminal = false,
    file = tmpLog,
    maxFileBytes = 8192,
    prefix = "test",
  })

  logger.info("info message ignored")
  logger.warn("warn message kept")
  logger.error("error message kept")

  if not fs.exists(tmpLog) then
    fail(111, "Le fichier de log n'a pas ete cree")
    return
  end

  local h = fs.open(tmpLog, "r")
  if not h then
    fail(112, "Impossible de lire le fichier de log temporaire")
    return
  end
  local body = tostring(h.readAll() or "")
  h.close()

  if body:find("INFO", 1, true) then
    fail(113, "Le niveau INFO ne doit pas passer quand level=warn")
  else
    ok("Filtrage de niveau INFO OK")
  end

  if not body:find("WARN", 1, true) then
    fail(114, "Message WARN attendu dans le log")
  else
    ok("Message WARN ecrit")
  end

  if not body:find("ERROR", 1, true) then
    fail(115, "Message ERROR attendu dans le log")
  else
    ok("Message ERROR ecrit")
  end

  logger.configure({ level = "debug" })
  logger.debug("debug message kept", { phase = "test" })

  local h2 = fs.open(tmpLog, "r")
  local body2 = ""
  if h2 then
    body2 = tostring(h2.readAll() or "")
    h2.close()
  end
  if not body2:find("debug message kept", 1, true) then
    fail(116, "Reconfiguration niveau debug non prise en compte")
  else
    ok("Reconfiguration niveau debug OK")
  end

  logger.configure({ maxFileBytes = 8192 })
  for i = 1, 200 do
    logger.error("line " .. tostring(i) .. " " .. string.rep("#", 80))
  end

  if not fs.exists(tmpLog) then
    fail(117, "Le fichier de log principal est manquant apres ecritures")
  else
    ok("Ecriture soutenue logger OK")
  end

  -- Nettoyage test.
  if fs.exists(tmpLog) then pcall(fs.delete, tmpLog) end
  if fs.exists(rotated) then pcall(fs.delete, rotated) end
  ok("Nettoyage logger test OK")
end

return M
