local M = {}

local LEVELS = {
  debug = 10,
  info = 20,
  warn = 30,
  error = 40,
  off = 100,
}

local function trimText(txt)
  txt = tostring(txt or "")
  return (txt:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function normalizeLevel(level, fallback)
  local normalized = string.lower(trimText(level))
  if LEVELS[normalized] then
    return normalized
  end
  return fallback or "info"
end

local function sanitizePath(path, fallback)
  local p = trimText(path)
  if p == "" then
    return fallback or "fusion.log"
  end
  p = p:gsub("\\", "/")
  p = p:gsub("/+", "/")
  p = p:gsub("^%./+", "")
  if p:sub(1, 1) == "/" then
    return fallback or "fusion.log"
  end
  if p:match("^[%a]:") then
    return fallback or "fusion.log"
  end
  if p:find("%.%.", 1, true) then
    return fallback or "fusion.log"
  end
  return p
end

local function sanitizeBool(value, fallback)
  if type(value) == "boolean" then
    return value
  end
  if value == nil then
    return fallback == true
  end
  if type(value) == "number" then
    return value ~= 0
  end
  local raw = string.lower(trimText(value))
  if raw == "true" or raw == "1" or raw == "yes" or raw == "on" then
    return true
  end
  if raw == "false" or raw == "0" or raw == "no" or raw == "off" then
    return false
  end
  return fallback == true
end

local function sanitizeMaxBytes(value, fallback)
  local n = tonumber(value)
  if not n then
    return fallback or 262144
  end
  n = math.floor(n + 0.5)
  if n < 8192 then n = 8192 end
  if n > 8388608 then n = 8388608 end
  return n
end

local function stringifyMeta(meta)
  if meta == nil then
    return ""
  end
  if type(meta) ~= "table" then
    return tostring(meta)
  end

  local keys = {}
  for key in pairs(meta) do
    keys[#keys + 1] = tostring(key)
  end
  table.sort(keys)

  local parts = {}
  for _, key in ipairs(keys) do
    local raw = meta[key]
    local val = tostring(raw)
    if #val > 64 then
      val = val:sub(1, 61) .. "..."
    end
    parts[#parts + 1] = key .. "=" .. val
  end
  return table.concat(parts, " ")
end

function M.levelValue(level)
  return LEVELS[normalizeLevel(level, "info")] or LEVELS.info
end

function M.new(options)
  options = type(options) == "table" and options or {}

  local fsApi = options.fs
  local nativeTerm = options.term
  local sink = nil

  local cfg = {
    enabled = sanitizeBool(options.enabled, true),
    level = normalizeLevel(options.level, "info"),
    toFile = sanitizeBool(options.toFile, true),
    toTerminal = sanitizeBool(options.toTerminal, false),
    file = sanitizePath(options.file, "fusion.log"),
    maxFileBytes = sanitizeMaxBytes(options.maxFileBytes, 262144),
    prefix = trimText(options.prefix) ~= "" and trimText(options.prefix) or "fusion",
  }

  local logger = {}

  local function shouldLog(level)
    if not cfg.enabled then
      return false
    end
    return M.levelValue(level) >= M.levelValue(cfg.level)
  end

  local function nowStamp()
    local clock = 0
    local okClock, rawClock = pcall(os.clock)
    if okClock and tonumber(rawClock) then
      clock = tonumber(rawClock)
    end

    local datePart = ""
    if type(os.date) == "function" then
      local okDate, rawDate = pcall(os.date, "%Y-%m-%d %H:%M:%S")
      if okDate and type(rawDate) == "string" then
        datePart = rawDate
      end
    end

    local tickPart = string.format("%08.3f", clock)
    if datePart ~= "" then
      return datePart .. " @" .. tickPart
    end
    return "@" .. tickPart
  end

  local function ensureLogDir(path)
    if type(fsApi) ~= "table" or type(fsApi.getDir) ~= "function" then
      return
    end
    local dir = fsApi.getDir(path)
    if type(dir) ~= "string" or dir == "" then
      return
    end
    if type(fsApi.exists) == "function" and fsApi.exists(dir) then
      return
    end
    if type(fsApi.makeDir) == "function" then
      pcall(fsApi.makeDir, dir)
    end
  end

  local function rotateLogIfNeeded()
    if not cfg.toFile then return end
    if type(fsApi) ~= "table" then return end
    if type(fsApi.exists) ~= "function" or type(fsApi.getSize) ~= "function" then
      return
    end
    if not fsApi.exists(cfg.file) then return end
    local okSize, size = pcall(fsApi.getSize, cfg.file)
    if not okSize or tonumber(size) == nil then return end
    if tonumber(size) < cfg.maxFileBytes then return end

    local rotated = cfg.file .. ".1"
    if type(fsApi.delete) == "function" and fsApi.exists(rotated) then
      pcall(fsApi.delete, rotated)
    end
    if type(fsApi.move) == "function" then
      pcall(fsApi.move, cfg.file, rotated)
    else
      if type(fsApi.copy) == "function" then
        pcall(fsApi.copy, cfg.file, rotated)
      end
      if type(fsApi.delete) == "function" then
        pcall(fsApi.delete, cfg.file)
      end
    end
  end

  local function appendFile(line)
    if not cfg.toFile then return true end
    if type(fsApi) ~= "table" or type(fsApi.open) ~= "function" then
      return false
    end

    ensureLogDir(cfg.file)
    rotateLogIfNeeded()

    local handle = fsApi.open(cfg.file, "a")
    if not handle then
      return false
    end
    handle.writeLine(line)
    handle.close()
    return true
  end

  local function appendTerminal(line)
    if not cfg.toTerminal then return true end

    if not nativeTerm then
      print(line)
      return true
    end

    local prev = term.current()
    local okRedirect = pcall(term.redirect, nativeTerm)
    if not okRedirect then
      print(line)
      return false
    end

    local okWrite = pcall(function()
      term.setBackgroundColor(colors.black)
      term.setTextColor(colors.white)
      term.setCursorPos(1, 1)
      print(line)
    end)

    pcall(term.redirect, prev)
    return okWrite
  end

  local function emit(level, message, meta)
    local lvl = normalizeLevel(level, "info")
    if not shouldLog(lvl) then
      return false
    end

    local body = trimText(message)
    if body == "" then
      body = "(empty message)"
    end

    local metaText = stringifyMeta(meta)
    local line = string.format(
      "%s [%s] [%s] %s%s",
      nowStamp(),
      string.upper(lvl),
      cfg.prefix,
      body,
      metaText ~= "" and (" | " .. metaText) or ""
    )

    local fileOk = appendFile(line)
    local termOk = appendTerminal(line)

    if type(sink) == "function" then
      pcall(sink, lvl, body, meta, line)
    end

    return fileOk and termOk
  end

  function logger.configure(nextCfg)
    nextCfg = type(nextCfg) == "table" and nextCfg or {}
    cfg.enabled = sanitizeBool(nextCfg.enabled, cfg.enabled)
    cfg.level = normalizeLevel(nextCfg.level, cfg.level)
    cfg.toFile = sanitizeBool(nextCfg.toFile, cfg.toFile)
    cfg.toTerminal = sanitizeBool(nextCfg.toTerminal, cfg.toTerminal)
    cfg.file = sanitizePath(nextCfg.file, cfg.file)
    cfg.maxFileBytes = sanitizeMaxBytes(nextCfg.maxFileBytes, cfg.maxFileBytes)
    if trimText(nextCfg.prefix) ~= "" then
      cfg.prefix = trimText(nextCfg.prefix)
    end
    return logger.getConfig()
  end

  function logger.getConfig()
    return {
      enabled = cfg.enabled,
      level = cfg.level,
      toFile = cfg.toFile,
      toTerminal = cfg.toTerminal,
      file = cfg.file,
      maxFileBytes = cfg.maxFileBytes,
      prefix = cfg.prefix,
    }
  end

  function logger.setSink(callback)
    if type(callback) == "function" then
      sink = callback
    else
      sink = nil
    end
  end

  function logger.log(level, message, meta)
    return emit(level, message, meta)
  end

  function logger.debug(message, meta)
    return emit("debug", message, meta)
  end

  function logger.info(message, meta)
    return emit("info", message, meta)
  end

  function logger.warn(message, meta)
    return emit("warn", message, meta)
  end

  function logger.error(message, meta)
    return emit("error", message, meta)
  end

  function logger.captureError(context, err, meta)
    local payload = type(meta) == "table" and meta or {}
    payload.error = tostring(err)
    return emit("error", tostring(context or "runtime error"), payload)
  end

  logger.levelValue = M.levelValue
  logger.normalizeLevel = normalizeLevel
  logger.configure(options)
  return logger
end

return M
