local function resolveCurrentDir()
  if type(debug) == "table" and type(debug.getinfo) == "function" then
    local info = debug.getinfo(1, "S")
    local source = info and info.source or ""
    if type(source) == "string" and source:sub(1, 1) == "@" then
      local filePath = source:sub(2):gsub("\\", "/")
      if type(fs) == "table" and type(fs.getDir) == "function" then
        return fs.getDir(filePath)
      end
    end
  end
  return ""
end

local function loadAssetData()
  local okRequire, modRequire = pcall(require, "ui.toms.assets_data")
  if okRequire and type(modRequire) == "table" then
    return modRequire
  end

  local candidates = {
    "ui/toms/assets_data.lua",
    "/ui/toms/assets_data.lua",
  }

  local thisDir = resolveCurrentDir()
  if thisDir ~= "" and type(fs) == "table" and type(fs.combine) == "function" then
    candidates[#candidates + 1] = fs.combine(thisDir, "assets_data.lua")
  end

  for i = 1, #candidates do
    local okFile, modFile = pcall(dofile, candidates[i])
    if okFile and type(modFile) == "table" then
      return modFile
    end
  end

  return { paletteMap = {}, sprites = {} }
end

local AssetData = loadAssetData()

local M = {}

local HEX_TO_COLOR = AssetData.paletteMap or {}
local SCALED_RUN_CACHE = {}

local function clamp(value, lo, hi)
  if value < lo then return lo end
  if value > hi then return hi end
  return value
end

local function asInt(value, fallback)
  local n = tonumber(value)
  if n == nil then
    n = fallback or 0
  end
  return math.floor(n + 0.5)
end

local function getSprite(key)
  local sprites = AssetData.sprites or {}
  return sprites[tostring(key or "")]
end

local function callFill(surface, x, y, w, h, color)
  if w <= 0 or h <= 0 then
    return true
  end

  if type(surface) == "table" then
    if type(surface.filledRectangle) == "function" then
      local ok, res = pcall(surface.filledRectangle, x, y, w, h, color)
      if ok and res ~= false then return true end
    end
    if type(surface.fillRect) == "function" then
      local ok, res = pcall(surface.fillRect, x, y, w, h, color)
      if ok and res ~= false then return true end
    end
    if type(surface.fill) == "function" and x == 1 and y == 1 then
      local ok, res = pcall(surface.fill, color)
      if ok and res ~= false then return true end
    end
    if type(surface.setBackgroundColor) == "function"
      and type(surface.setCursorPos) == "function"
      and type(surface.write) == "function" then
      local okBg = pcall(surface.setBackgroundColor, color)
      if okBg then
        local blanks = string.rep(" ", math.max(1, w))
        for row = 0, h - 1 do
          pcall(surface.setCursorPos, x, y + row)
          pcall(surface.write, blanks)
        end
        return true
      end
    end
  end

  return false
end

local function compileScaledRuns(sprite, width, height)
  local key = table.concat({ tostring(sprite.width), tostring(sprite.height), tostring(width), tostring(height) }, ":")
  local cached = SCALED_RUN_CACHE[key]
  if cached then
    return cached
  end

  local rows = {}
  local sourceRows = sprite.rows or {}
  local sourceW = math.max(1, asInt(sprite.width, 1))
  local sourceH = math.max(1, asInt(sprite.height, 1))

  for ty = 0, height - 1 do
    local sy = clamp(math.floor((ty * sourceH) / math.max(1, height)) + 1, 1, sourceH)
    local sourceRow = tostring(sourceRows[sy] or "")
    if #sourceRow < sourceW then
      sourceRow = sourceRow .. string.rep(".", sourceW - #sourceRow)
    end

    local lineRuns = {}
    local runStart = nil
    local runColor = nil

    local function flushRun(tx)
      if runStart and runColor then
        lineRuns[#lineRuns + 1] = {
          x = runStart,
          w = tx - runStart,
          color = runColor,
        }
      end
      runStart = nil
      runColor = nil
    end

    for tx = 0, width - 1 do
      local sx = clamp(math.floor((tx * sourceW) / math.max(1, width)) + 1, 1, sourceW)
      local hex = sourceRow:sub(sx, sx)
      local color = HEX_TO_COLOR[hex]

      if color == nil then
        flushRun(tx)
      elseif runColor == color then
        -- continue current run
      else
        flushRun(tx)
        runStart = tx
        runColor = color
      end
    end
    flushRun(width)
    rows[ty + 1] = lineRuns
  end

  SCALED_RUN_CACHE[key] = rows
  return rows
end

function M.draw(surface, key, x, y, w, h)
  local sprite = getSprite(key)
  if not sprite or type(surface) ~= "table" then
    return false
  end

  local rx = asInt(x, 1)
  local ry = asInt(y, 1)
  local rw = math.max(1, asInt(w, sprite.width))
  local rh = math.max(1, asInt(h, sprite.height))

  local scaledRuns = compileScaledRuns(sprite, rw, rh)
  for ty = 0, rh - 1 do
    local runs = scaledRuns[ty + 1]
    for i = 1, #runs do
      local run = runs[i]
      callFill(surface, rx + run.x, ry + ty, run.w, 1, run.color)
    end
  end
  return true
end

function M.getAnchors(key, x, y, w, h)
  local sprite = getSprite(key)
  if not sprite or type(sprite.anchors) ~= "table" then
    return nil
  end

  local rx = asInt(x, 1)
  local ry = asInt(y, 1)
  local rw = math.max(1, asInt(w, sprite.width))
  local rh = math.max(1, asInt(h, sprite.height))
  local anchors = {}

  for anchorName, anchor in pairs(sprite.anchors) do
    local ax = clamp(tonumber(anchor.x) or 0.5, 0, 1)
    local ay = clamp(tonumber(anchor.y) or 0.5, 0, 1)
    anchors[anchorName] = {
      x = rx + math.floor((rw - 1) * ax + 0.5),
      y = ry + math.floor((rh - 1) * ay + 0.5),
    }
  end

  return anchors
end

function M.getSpriteSize(key)
  local sprite = getSprite(key)
  if not sprite then
    return 0, 0
  end
  return math.max(1, asInt(sprite.width, 1)), math.max(1, asInt(sprite.height, 1))
end

return M
