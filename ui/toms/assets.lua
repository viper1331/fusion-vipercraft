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

function M.getSpriteAspect(key, fallback)
  local w, h = M.getSpriteSize(key)
  if w > 0 and h > 0 then
    return w / h
  end
  return tonumber(fallback) or 1
end

function M.resolveLaserModuleCount(cfg, state, fallback)
  local cfgValue = type(cfg) == "table" and cfg.laserCount or nil
  local stateValue = type(state) == "table" and state.laserCount or nil
  local value = tonumber(cfgValue or stateValue or fallback or 1) or 1
  value = math.floor(value + 0.00001)
  if value < 1 then
    value = 1
  end
  return value
end

function M.planVerticalStack(bounds, options)
  local b = type(bounds) == "table" and bounds or { x = 1, y = 1, w = 1, h = 1 }
  local opts = type(options) == "table" and options or {}
  local bx = asInt(b.x, 1)
  local by = asInt(b.y, 1)
  local bw = math.max(1, asInt(b.w, 1))
  local bh = math.max(1, asInt(b.h, 1))
  local count = math.max(1, asInt(opts.count, 1))
  local maxCount = math.max(1, asInt(opts.maxCount, 32))
  if count > maxCount then
    count = maxCount
  end

  local aspect = tonumber(opts.aspect) or M.getSpriteAspect("laser_module", 6.75)
  if aspect <= 0 then
    aspect = 6.75
  end

  local minWidth = math.max(1, asInt(opts.minWidth, 3))
  local maxWidth = math.max(minWidth, asInt(opts.maxWidth, bw))
  local widthRatio = tonumber(opts.widthRatio)
  local moduleW = asInt(opts.fixedWidth, 0)
  if moduleW <= 0 then
    moduleW = asInt(widthRatio and (bw * widthRatio) or bw, bw)
  end
  moduleW = clamp(moduleW, minWidth, maxWidth)

  local minHeight = math.max(1, asInt(opts.minHeight, 1))
  local maxHeight = math.max(minHeight, asInt(opts.maxHeight, bh))
  local moduleH = asInt(opts.fixedHeight, 0)
  if moduleH <= 0 then
    moduleH = asInt(moduleW / aspect, minHeight)
  end
  moduleH = clamp(moduleH, minHeight, maxHeight)

  local gapRatio = tonumber(opts.gapRatio) or 0.2
  local gap = math.max(0, asInt(opts.gap, moduleH * gapRatio))
  local minGap = math.max(0, asInt(opts.minGap, 0))
  local maxGap = math.max(minGap, asInt(opts.maxGap, bh))
  gap = clamp(gap, minGap, maxGap)

  local stackHeight = (count * moduleH) + ((count - 1) * gap)
  while stackHeight > bh and moduleH > minHeight do
    moduleH = moduleH - 1
    gap = clamp(math.max(minGap, asInt(moduleH * gapRatio, minGap)), minGap, maxGap)
    stackHeight = (count * moduleH) + ((count - 1) * gap)
  end
  while stackHeight > bh and gap > minGap do
    gap = gap - 1
    stackHeight = (count * moduleH) + ((count - 1) * gap)
  end

  local centerX = asInt(opts.centerX, bx + math.floor((bw - 1) / 2))
  centerX = clamp(centerX, bx, bx + bw - 1)
  local stackX = clamp(centerX - math.floor(moduleW / 2), bx, bx + bw - moduleW)
  local maxTop = by + bh - stackHeight
  if maxTop < by then
    maxTop = by
  end
  local stackTop = clamp(asInt(opts.top, by + math.floor((bh - stackHeight) / 2)), by, maxTop)

  local modules = {}
  for i = 1, count do
    local y = stackTop + ((i - 1) * (moduleH + gap))
    modules[#modules + 1] = {
      x = stackX,
      y = y,
      w = moduleW,
      h = moduleH,
    }
  end

  return {
    bounds = { x = bx, y = by, w = bw, h = bh, x2 = bx + bw - 1, y2 = by + bh - 1 },
    count = count,
    centerX = centerX,
    moduleW = moduleW,
    moduleH = moduleH,
    gap = gap,
    stackHeight = stackHeight,
    x = stackX,
    top = stackTop,
    modules = modules,
  }
end

function M.planReactorScene(bounds, options)
  local b = type(bounds) == "table" and bounds or { x = 1, y = 1, w = 1, h = 1 }
  local opts = type(options) == "table" and options or {}
  local bx = asInt(b.x, 1)
  local by = asInt(b.y, 1)
  local bw = math.max(1, asInt(b.w, 1))
  local bh = math.max(1, asInt(b.h, 1))

  local centerX = bx + math.floor((bw - 1) / 2)
  local centerY = by + math.floor((bh - 1) / 2)
  local laserGap = math.max(1, asInt(opts.laserGap, 2))
  local count = M.resolveLaserModuleCount(opts.cfg, opts.state, opts.laserCount or 1)

  local reactorMinW = math.max(8, asInt(opts.reactorMinW, 20))
  local reactorMinH = math.max(6, asInt(opts.reactorMinH, 14))
  local reactorMaxW = math.max(reactorMinW, asInt(opts.reactorMaxW, bw - 2))
  local reactorMaxH = math.max(reactorMinH, asInt(opts.reactorMaxH, bh - 2))
  local reactorW = clamp(
    asInt(opts.reactorW, math.floor(bw * 0.72)),
    reactorMinW,
    reactorMaxW
  )
  local reactorH = clamp(
    asInt(opts.reactorH, math.floor(bh * 0.64)),
    reactorMinH,
    reactorMaxH
  )

  local topReserve = math.max(3, asInt(opts.topReserve, math.floor(bh * 0.35)))
  local reactorYMin = by + topReserve + laserGap
  local reactorYMax = by + bh - reactorH
  if reactorYMin > reactorYMax then
    reactorYMin = by
  end
  local reactorX = clamp(centerX - math.floor(reactorW / 2), bx, bx + bw - reactorW)
  local reactorY = clamp(centerY - math.floor(reactorH / 2), reactorYMin, reactorYMax)
  local reactor = {
    x = reactorX,
    y = reactorY,
    w = reactorW,
    h = reactorH,
    x2 = reactorX + reactorW - 1,
    y2 = reactorY + reactorH - 1,
  }

  local stackZoneTop = by
  local stackZoneHeight = math.max(1, reactor.y - stackZoneTop - laserGap)
  local stackBounds = { x = bx, y = stackZoneTop, w = bw, h = stackZoneHeight }
  local stack = M.planVerticalStack(stackBounds, {
    count = count,
    maxCount = asInt(opts.maxLaserCount, 32),
    centerX = centerX,
    aspect = tonumber(opts.moduleAspect) or M.getSpriteAspect("laser_module", 6.75),
    widthRatio = tonumber(opts.moduleWidthRatio) or 0.34,
    minWidth = asInt(opts.moduleMinWidth, 24),
    maxWidth = asInt(opts.moduleMaxWidth, math.floor(bw * 0.58)),
    minHeight = asInt(opts.moduleMinHeight, 3),
    maxHeight = asInt(opts.moduleMaxHeight, 14),
    gapRatio = tonumber(opts.moduleGapRatio) or 0.2,
    minGap = asInt(opts.moduleMinGap, 0),
    maxGap = asInt(opts.moduleMaxGap, 4),
  })

  local emitterY = stack.top + stack.stackHeight
  if emitterY > reactor.y then
    emitterY = reactor.y
  end

  return {
    bounds = { x = bx, y = by, w = bw, h = bh, x2 = bx + bw - 1, y2 = by + bh - 1 },
    centerX = centerX,
    centerY = centerY,
    reactor = reactor,
    stack = stack,
    laserGap = laserGap,
    emitterY = emitterY,
  }
end

return M
