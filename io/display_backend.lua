local M = {}

local DEFAULT_PALETTE = {
  white = 0xFFF0F0F0,
  orange = 0xFFF2B233,
  magenta = 0xFFE57FD8,
  lightBlue = 0xFF99B2F2,
  yellow = 0xFFDEDE6C,
  lime = 0xFF7FCC19,
  pink = 0xFFF2B2CC,
  gray = 0xFF4C4C4C,
  lightGray = 0xFF999999,
  cyan = 0xFF4C99B2,
  purple = 0xFFB266E5,
  blue = 0xFF3366CC,
  brown = 0xFF7F664C,
  green = 0xFF57A64E,
  red = 0xFFCC4C4C,
  black = 0xFF111111,
}

local INVERTED_COLORS = {}
for k, v in pairs(colors) do
  if type(v) == "number" then
    INVERTED_COLORS[v] = k
  end
end

local DIRECTIONAL_ALIASES = {
  top = true,
  bottom = true,
  left = true,
  right = true,
  front = true,
  back = true,
}

local function methodCount(obj, methods)
  if not obj then return 0 end
  local count = 0
  for _, methodName in ipairs(methods) do
    if type(obj[methodName]) == "function" then
      count = count + 1
    end
  end
  return count
end

local function contains(haystack, needle)
  return tostring(haystack or ""):lower():find(tostring(needle or ""):lower(), 1, true) ~= nil
end

local function isDirectionalAlias(name)
  return DIRECTIONAL_ALIASES[string.lower(tostring(name or ""))] == true
end

local function looksLikeTomTypeHint(ptype, name)
  return contains(ptype, "tm_")
    or contains(name, "tm_")
    or contains(ptype, "tom")
    or contains(name, "tom")
    or contains(ptype, "gpu")
    or contains(name, "gpu")
end

local function colorFromBlit(hex)
  if type(hex) ~= "string" or #hex ~= 1 then return nil end
  local n = tonumber(hex, 16)
  if not n then return nil end
  return 2 ^ n
end

local function clamp(minValue, value, maxValue)
  if value < minValue then return minValue end
  if value > maxValue then return maxValue end
  return value
end

local function argbToRgb(packed)
  local n = tonumber(packed) or 0
  if n < 0 then
    n = 0x100000000 + n
  end
  return math.floor(n % 0x1000000)
end

local function readTermSize(obj)
  if not obj or type(obj.getSize) ~= "function" then
    return 0, 0
  end
  local ok, w, h = pcall(obj.getSize)
  if not ok then
    return 0, 0
  end
  w = tonumber(w) or 0
  h = tonumber(h) or 0
  return math.max(0, math.floor(w)), math.max(0, math.floor(h))
end

local function readTomResolution(obj)
  if not obj then return nil, nil end

  if type(obj.getResolution) == "function" then
    local ok, w, h = pcall(obj.getResolution)
    if ok then
      w = tonumber(w)
      h = tonumber(h)
      if w and h and w > 0 and h > 0 then
        return w, h
      end
    end
  end

  if type(obj.getWidth) == "function" and type(obj.getHeight) == "function" then
    local okW, w = pcall(obj.getWidth)
    local okH, h = pcall(obj.getHeight)
    if okW and okH then
      w = tonumber(w)
      h = tonumber(h)
      if w and h and w > 0 and h > 0 then
        return w, h
      end
    end
  end

  if type(obj.getSize) == "function" then
    local ok, w, h = pcall(obj.getSize)
    if ok then
      w = tonumber(w)
      h = tonumber(h)
      if w and h and w > 0 and h > 0 then
        return w, h
      end
    end
  end

  return nil, nil
end

local function refreshTomSize(obj)
  if not obj or type(obj.refreshSize) ~= "function" then
    return false
  end
  local ok = pcall(obj.refreshSize)
  return ok
end

local function trySetTomTargetSize(obj, target)
  if not obj or type(obj.setSize) ~= "function" then
    return false, "missing_method"
  end
  local n = tonumber(target)
  if not n then
    return false, "invalid_target"
  end
  n = math.max(1, math.floor(n + 0.5))

  if pcall(obj.setSize, n) then
    return true, "setSize(n)"
  end
  if pcall(obj.setSize, n, n) then
    return true, "setSize(n,n)"
  end
  return false, "setSize_failed"
end

local function probeTomRuntime(obj, opts)
  opts = type(opts) == "table" and opts or {}
  local runtime = {
    refreshBefore = false,
    refreshAfterSet = false,
    setSizeTried = false,
    setSizeApplied = false,
    setSizeMode = "none",
    targetSize = tonumber(opts.tomTargetSize or opts.targetSize or 64) or 64,
  }

  runtime.refreshBefore = refreshTomSize(obj)
  local preW, preH = readTomResolution(obj)
  runtime.prePxW, runtime.prePxH = preW, preH

  if opts.prepareRuntime and runtime.targetSize > 0 then
    runtime.setSizeTried = true
    local setOk, mode = trySetTomTargetSize(obj, runtime.targetSize)
    runtime.setSizeApplied = setOk
    runtime.setSizeMode = mode or "unknown"
  end

  runtime.refreshAfterSet = refreshTomSize(obj)
  local pxW, pxH = readTomResolution(obj)
  if not (pxW and pxH) then
    pxW, pxH = preW, preH
  end

  runtime.pxW = tonumber(pxW) or 0
  runtime.pxH = tonumber(pxH) or 0
  runtime.areaPx = math.max(0, math.floor(runtime.pxW * runtime.pxH))
  return runtime
end

local function sanitizeTomScale(scaleValue)
  local n = tonumber(scaleValue)
  if not n then return 1 end
  n = clamp(0.5, n, 3.0)
  return n
end

local function looksLikeTomGpu(ptype, name, obj)
  local gpuMethods = {
    "fill",
    "filledRectangle",
    "fillRect",
    "drawText",
    "drawString",
    "drawChar",
    "drawPixel",
    "setPixel",
    "getResolution",
    "getSize",
    "getWidth",
    "getHeight",
    "getTextLength",
    "sync",
    "flush",
    "update",
  }

  local pxW, pxH = readTomResolution(obj)
  local hasResolution = (pxW ~= nil and pxH ~= nil)
  local hasDrawCall = type(obj and obj.drawText) == "function"
    or type(obj and obj.drawString) == "function"
    or type(obj and obj.drawChar) == "function"
  local hasFillCall = type(obj and obj.filledRectangle) == "function"
    or type(obj and obj.fillRect) == "function"
    or type(obj and obj.fill) == "function"

  local score = methodCount(obj, gpuMethods)
  local hasSync = type(obj and obj.sync) == "function"
    or type(obj and obj.flush) == "function"
    or type(obj and obj.update) == "function"
  local typeHint = looksLikeTomTypeHint(ptype, name)

  local strongCaps = hasResolution and hasDrawCall and hasFillCall and score >= 4
  local veryStrongCaps = hasResolution and hasDrawCall and hasFillCall and score >= 6
  local permissiveTomCaps = typeHint and hasDrawCall and hasFillCall and (score >= 4 or hasSync)
  return (strongCaps and (typeHint or veryStrongCaps)) or permissiveTomCaps
end

local function looksLikeTermDisplay(ptype, obj)
  local termMethods = {
    "getSize",
    "setCursorPos",
    "write",
    "clear",
    "setTextColor",
    "setBackgroundColor",
  }
  local score = methodCount(obj, termMethods)
  if score < 5 then
    return false
  end
  return ptype == "monitor"
    or contains(ptype, "monitor")
    or contains(ptype, "display")
    or contains(ptype, "screen")
    or score >= 7
end

function M.detectCandidate(name, obj, getTypeOf, opts)
  if not obj then return nil end
  opts = type(opts) == "table" and opts or {}
  local ptype = ""
  if type(getTypeOf) == "function" then
    ptype = tostring(getTypeOf(name) or "")
  elseif peripheral and type(peripheral.getType) == "function" and name then
    local ok, t = pcall(peripheral.getType, name)
    if ok then ptype = tostring(t or "") end
  end

  if looksLikeTomGpu(ptype, name, obj) then
    local runtime = probeTomRuntime(obj, {
      prepareRuntime = not not opts.prepareRuntime,
      targetSize = opts.tomTargetSize or opts.targetSize or 64,
    })
    local scale = sanitizeTomScale(opts.monitorScale or 1)
    local pxW = runtime.pxW > 0 and runtime.pxW or nil
    local pxH = runtime.pxH > 0 and runtime.pxH or nil
    local charW = math.max(2, math.floor((6 * scale) + 0.5))
    local charH = math.max(3, math.floor((9 * scale) + 0.5))
    local w = pxW and math.max(1, math.floor(pxW / charW)) or 0
    local h = pxH and math.max(1, math.floor(pxH / charH)) or 0
    return {
      name = name,
      obj = obj,
      kind = "toms_gpu",
      touchEvent = "tm_monitor_touch",
      w = w,
      h = h,
      pxW = pxW or 0,
      pxH = pxH or 0,
      runtimeArea = runtime.areaPx or (w * h),
      runtime = runtime,
    }, nil
  end

  if looksLikeTermDisplay(ptype, obj) then
    local w, h = readTermSize(obj)
    local touchEvent = (contains(ptype, "tm_") or contains(ptype, "tom")) and "tm_monitor_touch" or "monitor_touch"
    return {
      name = name,
      obj = obj,
      kind = "cc_monitor",
      touchEvent = touchEvent,
      w = w,
      h = h,
      runtimeArea = math.max(0, math.floor(w * h)),
    }, nil
  end

  if looksLikeTomTypeHint(ptype, name) then
    return nil, "tom_caps_missing"
  end
  if contains(ptype, "monitor") or contains(ptype, "display") then
    return nil, "display_caps_missing"
  end
  return nil, "not_display"
end

local function buildTomTermSurface(gpu, cfg, runtimeInfo)
  local scale = sanitizeTomScale(cfg and cfg.monitorScale)
  runtimeInfo = type(runtimeInfo) == "table" and runtimeInfo or nil
  local pxW = runtimeInfo and tonumber(runtimeInfo.pxW) or nil
  local pxH = runtimeInfo and tonumber(runtimeInfo.pxH) or nil
  if not (pxW and pxH and pxW > 0 and pxH > 0) then
    pxW, pxH = readTomResolution(gpu)
  end
  pxW = tonumber(pxW) or 0
  pxH = tonumber(pxH) or 0

  local function detectTextMetrics()
    local defaultCharW = math.max(2, math.floor((6 * scale) + 0.5))
    local defaultCharH = math.max(3, math.floor((9 * scale) + 0.5))

    local measuredW = nil
    if type(gpu and gpu.getTextLength) == "function" then
      local okW, rawW = pcall(gpu.getTextLength, "W")
      if okW and tonumber(rawW) then
        measuredW = math.max(1, math.floor((tonumber(rawW) or 1) + 0.5))
      end
    end

    local measuredH = nil
    local hAccessors = {
      "getFontHeight",
      "getTextHeight",
      "getCharHeight",
    }
    for _, methodName in ipairs(hAccessors) do
      local fn = gpu and gpu[methodName]
      if type(fn) == "function" then
        local okH, rawH = pcall(fn)
        if okH and tonumber(rawH) then
          measuredH = math.max(1, math.floor((tonumber(rawH) or 1) + 0.5))
          break
        end
      end
    end

    local charW = measuredW or defaultCharW
    local charH = measuredH or defaultCharH

    local effectivePxW = pxW or 192
    local effectivePxH = pxH or 108
    local width = math.max(1, math.floor(effectivePxW / math.max(1, charW)))
    local height = math.max(1, math.floor(effectivePxH / math.max(1, charH)))

    -- Tom GPU expose des APIs differentes selon versions/modpacks.
    -- Si la grille resulte en UI inutilisable, on compacte moins les cellules.
    if width < 60 or height < 24 then
      local tunedCharW = math.max(1, math.floor(effectivePxW / 90))
      local tunedCharH = math.max(1, math.floor(effectivePxH / 40))
      charW = math.max(1, math.min(charW, tunedCharW))
      charH = math.max(1, math.min(charH, tunedCharH))
      width = math.max(1, math.floor(effectivePxW / charW))
      height = math.max(1, math.floor(effectivePxH / charH))
    end

    return charW, charH, width, height
  end

  local charW, charH, width, height = detectTextMetrics()

  local palette = {}
  for k, v in pairs(DEFAULT_PALETTE) do
    palette[k] = v
  end

  local function rgbToArgb(r, g, b)
    local function norm(v)
      v = tonumber(v) or 0
      if v <= 1 then
        v = math.floor((v * 255) + 0.5)
      end
      return clamp(0, math.floor(v), 255)
    end
    local rn, gn, bn = norm(r), norm(g), norm(b)
    return 0xFF000000 + (rn * 0x10000) + (gn * 0x100) + bn
  end

  local function callGpu(methodName, ...)
    local fn = gpu and gpu[methodName]
    if type(fn) ~= "function" then
      return false
    end
    local ok = pcall(fn, ...)
    return ok
  end

  local function callGpuVariants(methodName, variants)
    for _, args in ipairs(variants or {}) do
      if callGpu(methodName, table.unpack(args)) then
        return true
      end
    end
    return false
  end

  local function syncGpu()
    if callGpu("sync") then return end
    if callGpu("flush") then return end
    callGpu("update")
  end

  local function bgArgb(bgColor)
    local key = INVERTED_COLORS[bgColor] or "black"
    return palette[key] or DEFAULT_PALETTE.black
  end

  local function fgArgb(fgColor)
    local key = INVERTED_COLORS[fgColor] or "white"
    return palette[key] or DEFAULT_PALETTE.white
  end

  local function textPixelWidth(text)
    if type(gpu and gpu.getTextLength) == "function" then
      local ok, pixelW = pcall(gpu.getTextLength, text)
      if ok and tonumber(pixelW) then
        return math.max(1, math.floor(tonumber(pixelW)))
      end
    end
    return math.max(1, #tostring(text or ""))
  end

  local cursorX, cursorY = 1, 1
  local textColor, bgColor = colors.white, colors.black
  local cursorBlink = false

  local function drawFill(x, y, w, h, color)
    local x1 = math.floor(tonumber(x) or 1)
    local y1 = math.floor(tonumber(y) or 1)
    local ww = math.max(0, math.floor(tonumber(w) or 0))
    local hh = math.max(0, math.floor(tonumber(h) or 0))
    if ww <= 0 or hh <= 0 then
      return
    end
    local x2 = x1 + ww - 1
    local y2 = y1 + hh - 1
    if pxW > 0 and pxH > 0 then
      if x1 > pxW or y1 > pxH or x2 < 1 or y2 < 1 then
        return
      end
      x1 = clamp(1, x1, pxW)
      y1 = clamp(1, y1, pxH)
      x2 = clamp(1, x2, pxW)
      y2 = clamp(1, y2, pxH)
      ww = math.max(0, (x2 - x1) + 1)
      hh = math.max(0, (y2 - y1) + 1)
      if ww <= 0 or hh <= 0 then
        return
      end
    end
    if callGpuVariants("filledRectangle", {
      { x1, y1, ww, hh, color },
      { x1, y1, x2, y2, color },
    }) then return end
    if callGpuVariants("fillRect", {
      { x1, y1, ww, hh, color },
      { x1, y1, x2, y2, color },
    }) then return end
    if x1 == 1 and y1 == 1 and pxW > 0 and pxH > 0 and ww >= pxW and hh >= pxH then
      if callGpu("fill", color) then return end
    end
  end

  local function drawGlyph(x, y, char, color)
    if char == " " then return end
    local gx = math.floor(tonumber(x) or 1)
    local gy = math.floor(tonumber(y) or 1)
    if pxW > 0 and pxH > 0 then
      if gx < 1 or gx > pxW or gy < 1 or gy > pxH then
        return
      end
    end
    local rgbColor = argbToRgb(color)
    local fgIndex = textColor

    -- Certaines implementations Tom exigent d'abord une couleur globale.
    callGpuVariants("setForeground", {
      { color },
      { rgbColor },
      { fgIndex },
    })
    callGpuVariants("setTextColor", {
      { color },
      { rgbColor },
      { fgIndex },
    })

    if callGpuVariants("drawText", {
      { gx, gy, char, color, -1, scale },
      { gx, gy, char, rgbColor, -1, scale },
      { char, gx, gy, color, -1, scale },
      { char, gx, gy, rgbColor, -1, scale },
      { gx, gy, color, char, -1, scale },
      { gx, gy, rgbColor, char, -1, scale },
      { char, gx, gy, color },
      { char, gx, gy, rgbColor },
      { gx, gy, char, color },
      { gx, gy, char, rgbColor },
      { gx, gy, color, char },
      { gx, gy, rgbColor, char },
      { gx, gy, char },
      { char, gx, gy },
    }) then return end
    if callGpuVariants("drawString", {
      { gx, gy, char, color },
      { gx, gy, char, rgbColor },
      { char, gx, gy, color },
      { char, gx, gy, rgbColor },
      { gx, gy, color, char },
      { gx, gy, rgbColor, char },
      { gx, gy, char },
      { char, gx, gy },
    }) then return end
    callGpuVariants("drawChar", {
      { gx, gy, string.byte(char), color, -1, scale },
      { gx, gy, char, color, -1, scale },
      { gx, gy, char, rgbColor, -1, scale },
      { string.byte(char), gx, gy, color },
      { char, gx, gy, color },
      { char, gx, gy, rgbColor },
      { gx, gy, string.byte(char), color },
      { gx, gy, char, color },
      { gx, gy, char, rgbColor },
      { gx, gy, char },
      { char, gx, gy },
    })
  end

  local bufferA = {}
  local bufferB = {}
  for y = 1, height do
    bufferA[y] = {}
    bufferB[y] = {}
    for x = 1, width do
      bufferA[y][x] = { ch = " ", fg = colors.white, bg = colors.black }
      bufferB[y][x] = { ch = " ", fg = colors.white, bg = colors.black }
    end
  end

  local function drawCell(tx, ty, ch, fg, bg)
    local px = ((tx - 1) * charW) + 1
    local py = ((ty - 1) * charH) + 1
    drawFill(px, py, charW, charH, bgArgb(bg))
    if ch ~= " " then
      local glyphW = textPixelWidth(ch)
      local glyphX = px + math.max(0, math.floor((charW - glyphW) / 2))
      drawGlyph(glyphX, py, ch, fgArgb(fg))
    end
  end

  local function writeCell(x, y, ch, fg, bg)
    if x < 1 or x > width or y < 1 or y > height then return end
    bufferA[y][x].ch = ch
    bufferA[y][x].fg = fg
    bufferA[y][x].bg = bg
  end

  local function writeRun(text, fgColor, bgColorValue)
    text = tostring(text or "")
    for i = 1, #text do
      local xPos = cursorX + i - 1
      if xPos >= 1 and xPos <= width and cursorY >= 1 and cursorY <= height then
        writeCell(xPos, cursorY, text:sub(i, i), fgColor, bgColorValue)
      end
    end
    cursorX = cursorX + #text
  end

  local surface = {}

  function surface.getSize()
    return width, height
  end

  function surface.setCursorPos(x, y)
    cursorX = math.floor(tonumber(x) or cursorX)
    cursorY = math.floor(tonumber(y) or cursorY)
  end

  function surface.getCursorPos()
    return cursorX, cursorY
  end

  function surface.setCursorBlink(enabled)
    cursorBlink = not not enabled
  end

  function surface.getCursorBlink()
    return cursorBlink
  end

  function surface.setTextColor(color)
    textColor = tonumber(color) or textColor
  end
  surface.setTextColour = surface.setTextColor

  function surface.getTextColor()
    return textColor
  end
  surface.getTextColour = surface.getTextColor

  function surface.setBackgroundColor(color)
    bgColor = tonumber(color) or bgColor
  end
  surface.setBackgroundColour = surface.setBackgroundColor

  function surface.getBackgroundColor()
    return bgColor
  end
  surface.getBackgroundColour = surface.getBackgroundColor

  function surface.clear()
    for y = 1, height do
      for x = 1, width do
        writeCell(x, y, " ", textColor, bgColor)
      end
    end
  end

  function surface.clearLine()
    if cursorY < 1 or cursorY > height then return end
    for x = 1, width do
      writeCell(x, cursorY, " ", textColor, bgColor)
    end
  end

  function surface.write(value)
    writeRun(value, textColor, bgColor)
  end

  function surface.blit(text, fg, bg)
    text = tostring(text or "")
    fg = tostring(fg or "")
    bg = tostring(bg or "")
    local n = math.min(#text, #fg, #bg)
    if n <= 0 then
      return
    end

    for i = 1, n do
      local xPos = cursorX + i - 1
      if xPos >= 1 and xPos <= width and cursorY >= 1 and cursorY <= height then
        local fgc = colorFromBlit(fg:sub(i, i)) or colors.white
        local bgc = colorFromBlit(bg:sub(i, i)) or colors.black
        writeCell(xPos, cursorY, text:sub(i, i), fgc, bgc)
      end
    end
    cursorX = cursorX + n
  end

  function surface.scroll(lines)
    lines = math.floor(tonumber(lines) or 0)
    if lines == 0 then return end
    if math.abs(lines) >= height then
      surface.clear()
      return
    end

    local newBuffer = {}
    for y = 1, height do
      newBuffer[y] = {}
      for x = 1, width do
        newBuffer[y][x] = { ch = " ", fg = textColor, bg = bgColor }
      end
    end

    for y = 1, height do
      local newY = y - lines
      if newY >= 1 and newY <= height then
        for x = 1, width do
          newBuffer[newY][x].ch = bufferA[y][x].ch
          newBuffer[newY][x].fg = bufferA[y][x].fg
          newBuffer[newY][x].bg = bufferA[y][x].bg
        end
      end
    end
    bufferA = newBuffer
  end

  function surface.isColor()
    return true
  end
  surface.isColour = surface.isColor

  function surface.getPaletteColor(color)
    local key = INVERTED_COLORS[tonumber(color) or 0] or "white"
    local packed = palette[key] or DEFAULT_PALETTE.white
    local r = math.floor((packed % 0x1000000) / 0x10000)
    local g = math.floor((packed % 0x10000) / 0x100)
    local b = math.floor(packed % 0x100)
    return r / 255, g / 255, b / 255
  end
  surface.getPaletteColour = surface.getPaletteColor

  function surface.setPaletteColor(color, r, g, b)
    local key = INVERTED_COLORS[tonumber(color) or 0]
    if not key then
      return
    end
    if g ~= nil and b ~= nil then
      palette[key] = rgbToArgb(r, g, b)
      return
    end
    local packed = tonumber(r)
    if packed then
      if packed < 0x1000000 then
        packed = 0xFF000000 + packed
      end
      palette[key] = packed
    end
  end
  surface.setPaletteColour = surface.setPaletteColor

  function surface.setTextScale()
    -- No-op for GPU backend: char metrics are driven by resolution and font scale.
  end

  function surface.mapPixel(x, y)
    local tx = math.floor(((tonumber(x) or 1) - 1) / charW) + 1
    local ty = math.floor(((tonumber(y) or 1) - 1) / charH) + 1
    return tx, ty
  end

  local function makeWindow(parent, ox, oy, ww, hh)
    local win = {}
    local winW = math.max(1, math.floor(tonumber(ww) or 1))
    local winH = math.max(1, math.floor(tonumber(hh) or 1))
    local baseX = math.floor(tonumber(ox) or 1)
    local baseY = math.floor(tonumber(oy) or 1)
    local winCursorX, winCursorY = 1, 1
    local winTextColor = colors.white
    local winBgColor = colors.black
    local winBlink = false

    local function mapToParent(x, y)
      local px = baseX + x - 1
      local py = baseY + y - 1
      return px, py
    end

    function win.getSize()
      return winW, winH
    end

    function win.setCursorPos(x, y)
      winCursorX = math.floor(tonumber(x) or winCursorX)
      winCursorY = math.floor(tonumber(y) or winCursorY)
    end

    function win.getCursorPos()
      return winCursorX, winCursorY
    end

    function win.setCursorBlink(enabled)
      winBlink = not not enabled
    end

    function win.getCursorBlink()
      return winBlink
    end

    function win.setTextColor(color)
      winTextColor = tonumber(color) or winTextColor
    end
    win.setTextColour = win.setTextColor

    function win.getTextColor()
      return winTextColor
    end
    win.getTextColour = win.getTextColor

    function win.setBackgroundColor(color)
      winBgColor = tonumber(color) or winBgColor
    end
    win.setBackgroundColour = win.setBackgroundColor

    function win.getBackgroundColor()
      return winBgColor
    end
    win.getBackgroundColour = win.getBackgroundColor

    function win.write(value)
      local text = tostring(value or "")
      local x = winCursorX
      local y = winCursorY
      if y < 1 or y > winH then return end
      if x < 1 then
        local cut = 1 - x
        if cut >= #text then return end
        text = text:sub(cut + 1)
        x = 1
      end
      if x > winW then return end
      if (x + #text - 1) > winW then
        text = text:sub(1, (winW - x) + 1)
      end
      local px, py = mapToParent(x, y)
      parent.setCursorPos(px, py)
      parent.setTextColor(winTextColor)
      parent.setBackgroundColor(winBgColor)
      parent.write(text)
      winCursorX = winCursorX + #text
    end

    function win.blit(text, fg, bg)
      text = tostring(text or "")
      fg = tostring(fg or "")
      bg = tostring(bg or "")
      local n = math.min(#text, #fg, #bg)
      if n <= 0 then return end
      local x = winCursorX
      local y = winCursorY
      if y < 1 or y > winH then return end
      if x < 1 then
        local cut = 1 - x
        if cut >= n then return end
        text = text:sub(cut + 1, n)
        fg = fg:sub(cut + 1, n)
        bg = bg:sub(cut + 1, n)
        n = #text
        x = 1
      else
        text = text:sub(1, n)
        fg = fg:sub(1, n)
        bg = bg:sub(1, n)
      end
      if x > winW then return end
      if (x + #text - 1) > winW then
        local keep = (winW - x) + 1
        text = text:sub(1, keep)
        fg = fg:sub(1, keep)
        bg = bg:sub(1, keep)
      end
      local px, py = mapToParent(x, y)
      parent.setCursorPos(px, py)
      parent.blit(text, fg, bg)
      winCursorX = winCursorX + #text
    end

    function win.clear()
      local blank = string.rep(" ", winW)
      local fg = string.rep(colors.toBlit(winTextColor), winW)
      local bb = string.rep(colors.toBlit(winBgColor), winW)
      for row = 1, winH do
        local px, py = mapToParent(1, row)
        parent.setCursorPos(px, py)
        parent.blit(blank, fg, bb)
      end
    end

    function win.clearLine()
      if winCursorY < 1 or winCursorY > winH then return end
      local px, py = mapToParent(1, winCursorY)
      parent.setCursorPos(px, py)
      parent.setTextColor(winTextColor)
      parent.setBackgroundColor(winBgColor)
      parent.write(string.rep(" ", winW))
    end

    function win.scroll(lines)
      lines = math.floor(tonumber(lines) or 0)
      if lines == 0 then return end
      if math.abs(lines) >= winH then
        win.clear()
        return
      end
      local emptyLine = string.rep(" ", winW)
      local fillBg = string.rep(colors.toBlit(winBgColor), winW)
      local fillFg = string.rep(colors.toBlit(winTextColor), winW)
      if lines > 0 then
        for row = 1, winH do
          local src = row + lines
          local dstPx, dstPy = mapToParent(1, row)
          parent.setCursorPos(dstPx, dstPy)
          if src <= winH then
            local srcPx, srcPy = mapToParent(1, src)
            parent.setCursorPos(srcPx, srcPy)
            -- Best effort: redraw blank then rely on next frame full redraw.
            parent.setCursorPos(dstPx, dstPy)
            parent.blit(emptyLine, fillFg, fillBg)
          else
            parent.blit(emptyLine, fillFg, fillBg)
          end
        end
      else
        win.clear()
      end
    end

    function win.isColor()
      return true
    end
    win.isColour = win.isColor

    win.getPaletteColor = parent.getPaletteColor
    win.getPaletteColour = parent.getPaletteColour
    win.setPaletteColor = parent.setPaletteColor
    win.setPaletteColour = parent.setPaletteColour

    function win.setTextScale()
      -- No-op for sub windows.
    end

    function win.mapPixel(x, y)
      local px = baseX + (math.floor(tonumber(x) or 1) - 1)
      local py = baseY + (math.floor(tonumber(y) or 1) - 1)
      local tx, ty = parent.mapPixel(px, py)
      return tx - baseX + 1, ty - baseY + 1
    end

    function win.flush()
      if type(parent.flush) == "function" then
        parent.flush()
      end
    end
    win.sync = win.flush

    function win.createWindow(x, y, w, h)
      local subX = baseX + math.max(0, math.floor(tonumber(x) or 1) - 1)
      local subY = baseY + math.max(0, math.floor(tonumber(y) or 1) - 1)
      return makeWindow(parent, subX, subY, w, h)
    end

    return win
  end

  function surface.createWindow(x, y, w, h)
    local ox = clamp(1, math.floor(tonumber(x) or 1), width)
    local oy = clamp(1, math.floor(tonumber(y) or 1), height)
    local maxW = (width - ox) + 1
    local maxH = (height - oy) + 1
    local ww = clamp(1, math.floor(tonumber(w) or maxW), maxW)
    local hh = clamp(1, math.floor(tonumber(h) or maxH), maxH)
    return makeWindow(surface, ox, oy, ww, hh)
  end

  function surface.flush()
    local changed = false
    for y = 1, height do
      for x = 1, width do
        local a = bufferA[y][x]
        local b = bufferB[y][x]
        if a.ch ~= b.ch or a.fg ~= b.fg or a.bg ~= b.bg then
          drawCell(x, y, a.ch, a.fg, a.bg)
          b.ch = a.ch
          b.fg = a.fg
          b.bg = a.bg
          changed = true
        end
      end
    end
    if changed then
      syncGpu()
    end
  end
  surface.sync = surface.flush

  return surface, {
    kind = "toms_gpu",
    touchEvent = "tm_monitor_touch",
    mapPixel = surface.mapPixel,
    createWindow = surface.createWindow,
    width = width,
    height = height,
    pixelWidth = pxW,
    pixelHeight = pxH,
    area = math.max(0, math.floor(width * height)),
    runtimeArea = runtimeInfo and runtimeInfo.areaPx or math.max(0, math.floor(pxW * pxH)),
    setSizeTried = runtimeInfo and runtimeInfo.setSizeTried or false,
    setSizeApplied = runtimeInfo and runtimeInfo.setSizeApplied or false,
    setSizeMode = runtimeInfo and runtimeInfo.setSizeMode or "none",
    targetSize = runtimeInfo and runtimeInfo.targetSize or nil,
    charW = charW,
    charH = charH,
  }
end

local function buildTomNativeSurface(gpu, cfg, runtimeInfo, opts)
  opts = type(opts) == "table" and opts or {}
  runtimeInfo = type(runtimeInfo) == "table" and runtimeInfo or {}
  local pxW = tonumber(runtimeInfo.pxW) or 0
  local pxH = tonumber(runtimeInfo.pxH) or 0
  if pxW <= 0 or pxH <= 0 then
    local rw, rh = readTomResolution(gpu)
    pxW = tonumber(rw) or pxW
    pxH = tonumber(rh) or pxH
  end
  pxW = math.max(1, math.floor(pxW))
  pxH = math.max(1, math.floor(pxH))

  local lineHeight = 1
  for _, methodName in ipairs({ "getFontHeight", "getTextHeight", "getCharHeight" }) do
    local fn = type(gpu) == "table" and gpu[methodName] or nil
    if type(fn) == "function" then
      local okH, h = pcall(fn)
      if okH and tonumber(h) then
        lineHeight = math.max(1, math.floor(tonumber(h) + 0.5))
        break
      end
    end
  end

  local charWidthEstimate = math.max(4, math.floor((lineHeight * 0.62) + 0.5))
  if type(gpu) == "table" and type(gpu.getTextLength) == "function" then
    local okW, wText = pcall(gpu.getTextLength, "W")
    if okW and tonumber(wText) then
      charWidthEstimate = math.max(1, math.floor((tonumber(wText) or 1) + 0.5))
    end
  end

  local scale = sanitizeTomScale(cfg and cfg.monitorScale)
  local palette = {}
  for k, v in pairs(DEFAULT_PALETTE) do
    palette[k] = v
  end

  local function colorArgb(colorValue, fallbackKey)
    local key = INVERTED_COLORS[tonumber(colorValue) or 0] or fallbackKey
    return palette[key] or DEFAULT_PALETTE[fallbackKey]
  end

  local function normalizeArgb(colorValue, fallbackKey)
    local n = tonumber(colorValue)
    if n and n > 0xFFFF then
      if n < 0 then
        n = 0x100000000 + n
      end
      return math.floor(n)
    end
    return colorArgb(n or colors[fallbackKey] or colors.white, fallbackKey)
  end

  local function callGpu(methodName, ...)
    local fn = type(gpu) == "table" and gpu[methodName] or nil
    if type(fn) ~= "function" then
      return false
    end
    local ok = pcall(fn, ...)
    return ok
  end

  local function callGpuVariants(methodName, variants)
    for _, args in ipairs(variants or {}) do
      if callGpu(methodName, table.unpack(args)) then
        return true
      end
    end
    return false
  end

  local function clampRect(x, y, w, h)
    local x1 = math.floor(tonumber(x) or 1)
    local y1 = math.floor(tonumber(y) or 1)
    local ww = math.max(0, math.floor(tonumber(w) or 0))
    local hh = math.max(0, math.floor(tonumber(h) or 0))
    if ww <= 0 or hh <= 0 then
      return nil
    end
    local x2 = x1 + ww - 1
    local y2 = y1 + hh - 1
    if x2 < 1 or y2 < 1 or x1 > pxW or y1 > pxH then
      return nil
    end
    if x1 < 1 then x1 = 1 end
    if y1 < 1 then y1 = 1 end
    if x2 > pxW then x2 = pxW end
    if y2 > pxH then y2 = pxH end
    local cw = (x2 - x1) + 1
    local ch = (y2 - y1) + 1
    if cw <= 0 or ch <= 0 then
      return nil
    end
    return x1, y1, cw, ch, x2, y2
  end

  local function fillRect(x, y, w, h, color)
    local x1, y1, cw, ch, x2, y2 = clampRect(x, y, w, h)
    if not x1 then return end
    if callGpuVariants("filledRectangle", {
      { x1, y1, cw, ch, color },
      { x1, y1, x2, y2, color },
    }) then return end
    if callGpuVariants("fillRect", {
      { x1, y1, cw, ch, color },
      { x1, y1, x2, y2, color },
    }) then return end
    if x1 == 1 and y1 == 1 and cw >= pxW and ch >= pxH then
      if callGpu("fill", color) then return end
    end
  end

  local function textPixelWidth(text)
    local raw = tostring(text or "")
    if type(gpu) == "table" and type(gpu.getTextLength) == "function" then
      local ok, pixelW = pcall(gpu.getTextLength, raw)
      if ok and tonumber(pixelW) then
        return math.max(1, math.floor(tonumber(pixelW) + 0.5))
      end
    end
    return math.max(1, #raw)
  end

  local function drawText(x, y, text, argbColor)
    local xx = math.floor(tonumber(x) or 1)
    local yy = math.floor(tonumber(y) or 1)
    local raw = tostring(text or "")
    if raw == "" then return end
    if yy < 1 or yy > pxH then return end
    local color = tonumber(argbColor) or DEFAULT_PALETTE.white
    local rgb = argbToRgb(color)
    if callGpuVariants("drawText", {
      { xx, yy, raw, color, -1, scale },
      { xx, yy, raw, rgb, -1, scale },
      { raw, xx, yy, color, -1, scale },
      { raw, xx, yy, rgb, -1, scale },
      { xx, yy, color, raw },
      { xx, yy, rgb, raw },
      { xx, yy, raw, color },
      { xx, yy, raw, rgb },
      { raw, xx, yy, color },
      { raw, xx, yy, rgb },
      { xx, yy, raw },
      { raw, xx, yy },
    }) then return end
    if callGpuVariants("drawString", {
      { xx, yy, raw, color },
      { xx, yy, raw, rgb },
      { raw, xx, yy, color },
      { raw, xx, yy, rgb },
      { xx, yy, color, raw },
      { xx, yy, rgb, raw },
      { xx, yy, raw },
      { raw, xx, yy },
    }) then return end
    for i = 1, #raw do
      local ch = raw:sub(i, i)
      callGpuVariants("drawChar", {
        { xx + i - 1, yy, string.byte(ch), color, -1, scale },
        { xx + i - 1, yy, ch, color, -1, scale },
        { xx + i - 1, yy, ch, rgb, -1, scale },
      })
    end
  end

  local function syncGpu()
    if callGpu("sync") then return end
    if callGpu("flush") then return end
    callGpu("update")
  end

  local cursorX, cursorY = 1, 1
  local textColor, bgColor = colors.white, colors.black
  local cursorBlink = false

  local surface = {}

  function surface.getSize()
    return pxW, pxH
  end

  function surface.setCursorPos(x, y)
    cursorX = math.floor(tonumber(x) or cursorX)
    cursorY = math.floor(tonumber(y) or cursorY)
  end

  function surface.getCursorPos()
    return cursorX, cursorY
  end

  function surface.setCursorBlink(enabled)
    cursorBlink = not not enabled
  end

  function surface.getCursorBlink()
    return cursorBlink
  end

  function surface.setTextColor(color)
    textColor = tonumber(color) or textColor
  end
  surface.setTextColour = surface.setTextColor

  function surface.getTextColor()
    return textColor
  end
  surface.getTextColour = surface.getTextColor

  function surface.setBackgroundColor(color)
    bgColor = tonumber(color) or bgColor
  end
  surface.setBackgroundColour = surface.setBackgroundColor

  function surface.getBackgroundColor()
    return bgColor
  end
  surface.getBackgroundColour = surface.getBackgroundColor

  function surface.clear()
    fillRect(1, 1, pxW, pxH, colorArgb(bgColor, "black"))
  end

  function surface.clearLine()
    fillRect(1, cursorY, pxW, lineHeight, colorArgb(bgColor, "black"))
  end

  function surface.write(value)
    local raw = tostring(value or "")
    if raw == "" then return end
    if cursorY < 1 or cursorY > pxH then return end
    local argbBg = colorArgb(bgColor, "black")
    local argbFg = colorArgb(textColor, "white")
    local width = textPixelWidth(raw)
    fillRect(cursorX, cursorY, width, lineHeight, argbBg)
    drawText(cursorX, cursorY, raw, argbFg)
    cursorX = cursorX + #raw
  end

  function surface.getTextLength(text)
    return textPixelWidth(text)
  end

  function surface.filledRectangle(x, y, w, h, color)
    fillRect(x, y, w, h, normalizeArgb(color, "black"))
  end

  function surface.fillRect(x, y, w, h, color)
    fillRect(x, y, w, h, normalizeArgb(color, "black"))
  end

  function surface.fill(color)
    fillRect(1, 1, pxW, pxH, normalizeArgb(color, "black"))
  end

  function surface.drawText(a, b, c, d)
    local x, y, text, color = nil, nil, nil, nil
    if type(a) == "number" and type(b) == "number" and type(c) == "string" then
      x, y, text, color = a, b, c, d
    elseif type(a) == "string" and type(b) == "number" and type(c) == "number" then
      x, y, text, color = b, c, a, d
    elseif type(a) == "number" and type(b) == "number" and type(c) == "number" and type(d) == "string" then
      x, y, text, color = a, b, d, c
    else
      return false
    end
    drawText(x, y, text, normalizeArgb(color, "white"))
    return true
  end
  surface.drawString = surface.drawText

  function surface.blit(text, fg, bg)
    text = tostring(text or "")
    fg = tostring(fg or "")
    bg = tostring(bg or "")
    local n = math.min(#text, #fg, #bg)
    if n <= 0 then return end
    for i = 1, n do
      local ch = text:sub(i, i)
      local fgIdx = colorFromBlit(fg:sub(i, i)) or colors.white
      local bgIdx = colorFromBlit(bg:sub(i, i)) or colors.black
      local x = cursorX + i - 1
      fillRect(x, cursorY, 1, lineHeight, colorArgb(bgIdx, "black"))
      if ch ~= " " then
        drawText(x, cursorY, ch, colorArgb(fgIdx, "white"))
      end
    end
    cursorX = cursorX + n
  end

  function surface.scroll(_)
    -- No buffered text grid in native mode; full redraw is done every frame.
  end

  function surface.isColor()
    return true
  end
  surface.isColour = surface.isColor

  function surface.getPaletteColor(color)
    local packed = colorArgb(color, "white")
    local r = math.floor((packed % 0x1000000) / 0x10000)
    local g = math.floor((packed % 0x10000) / 0x100)
    local b = math.floor(packed % 0x100)
    return r / 255, g / 255, b / 255
  end
  surface.getPaletteColour = surface.getPaletteColor

  function surface.setPaletteColor(color, r, g, b)
    local key = INVERTED_COLORS[tonumber(color) or 0]
    if not key then return end
    if g ~= nil and b ~= nil then
      local rr = clamp(0, math.floor((tonumber(r) or 0) * 255 + 0.5), 255)
      local gg = clamp(0, math.floor((tonumber(g) or 0) * 255 + 0.5), 255)
      local bb = clamp(0, math.floor((tonumber(b) or 0) * 255 + 0.5), 255)
      palette[key] = 0xFF000000 + (rr * 0x10000) + (gg * 0x100) + bb
      return
    end
    local packed = tonumber(r)
    if packed then
      if packed < 0x1000000 then
        packed = 0xFF000000 + packed
      end
      palette[key] = packed
    end
  end
  surface.setPaletteColour = surface.setPaletteColor

  function surface.setTextScale()
    -- No-op for native Tom GPU surface.
  end

  function surface.mapPixel(x, y)
    return math.floor(tonumber(x) or 1), math.floor(tonumber(y) or 1)
  end

  local function makeWindow(parent, ox, oy, ww, hh)
    local win = {}
    local baseX = math.floor(tonumber(ox) or 1)
    local baseY = math.floor(tonumber(oy) or 1)
    local winW = math.max(1, math.floor(tonumber(ww) or 1))
    local winH = math.max(1, math.floor(tonumber(hh) or 1))
    local wx, wy = 1, 1
    local wfg, wbg = colors.white, colors.black
    local wblink = false

    local function mapPos(x, y)
      return baseX + x - 1, baseY + y - 1
    end

    function win.getSize() return winW, winH end
    function win.setCursorPos(x, y)
      wx = math.floor(tonumber(x) or wx)
      wy = math.floor(tonumber(y) or wy)
    end
    function win.getCursorPos() return wx, wy end
    function win.setCursorBlink(v) wblink = not not v end
    function win.getCursorBlink() return wblink end
    function win.setTextColor(v) wfg = tonumber(v) or wfg end
    win.setTextColour = win.setTextColor
    function win.getTextColor() return wfg end
    win.getTextColour = win.getTextColor
    function win.setBackgroundColor(v) wbg = tonumber(v) or wbg end
    win.setBackgroundColour = win.setBackgroundColor
    function win.getBackgroundColor() return wbg end
    win.getBackgroundColour = win.getBackgroundColor

    function win.write(value)
      local gx, gy = mapPos(wx, wy)
      parent.setCursorPos(gx, gy)
      parent.setTextColor(wfg)
      parent.setBackgroundColor(wbg)
      parent.write(value)
      wx = wx + #tostring(value or "")
    end

    function win.blit(text, fg, bg)
      local gx, gy = mapPos(wx, wy)
      parent.setCursorPos(gx, gy)
      parent.blit(text, fg, bg)
      wx = wx + math.min(#tostring(text or ""), #tostring(fg or ""), #tostring(bg or ""))
    end

    function win.clear()
      local gx, gy = mapPos(1, 1)
      parent.setBackgroundColor(wbg)
      local argb = colorArgb(wbg, "black")
      fillRect(gx, gy, winW, winH, argb)
    end

    function win.clearLine()
      local gx, gy = mapPos(1, wy)
      parent.setBackgroundColor(wbg)
      fillRect(gx, gy, winW, lineHeight, colorArgb(wbg, "black"))
    end

    function win.scroll(_)
      -- No buffered text grid in native mode.
    end

    function win.isColor() return true end
    win.isColour = win.isColor
    win.getPaletteColor = parent.getPaletteColor
    win.getPaletteColour = parent.getPaletteColour
    win.setPaletteColor = parent.setPaletteColor
    win.setPaletteColour = parent.setPaletteColour
    function win.setTextScale() end
    function win.mapPixel(x, y)
      local gx, gy = mapPos(math.floor(tonumber(x) or 1), math.floor(tonumber(y) or 1))
      return gx - baseX + 1, gy - baseY + 1
    end
    function win.flush() if type(parent.flush) == "function" then parent.flush() end end
    win.sync = win.flush
    function win.createWindow(x, y, w, h)
      local nx = baseX + math.max(0, math.floor(tonumber(x) or 1) - 1)
      local ny = baseY + math.max(0, math.floor(tonumber(y) or 1) - 1)
      return makeWindow(parent, nx, ny, w, h)
    end

    return win
  end

  function surface.createWindow(x, y, w, h)
    local ox = clamp(1, math.floor(tonumber(x) or 1), pxW)
    local oy = clamp(1, math.floor(tonumber(y) or 1), pxH)
    local maxW = (pxW - ox) + 1
    local maxH = (pxH - oy) + 1
    local ww = clamp(1, math.floor(tonumber(w) or maxW), maxW)
    local hh = clamp(1, math.floor(tonumber(h) or maxH), maxH)
    return makeWindow(surface, ox, oy, ww, hh)
  end

  function surface.flush()
    syncGpu()
  end
  surface.sync = surface.flush

  local wrapperType = opts.debug and "toms_native_debug" or "toms_native"
  return surface, {
    kind = "toms_gpu",
    backendFamily = "toms_native",
    wrapperType = wrapperType,
    touchEvent = "tm_monitor_touch",
    mapPixel = surface.mapPixel,
    createWindow = surface.createWindow,
    width = pxW,
    height = pxH,
    wrappedWidth = pxW,
    wrappedHeight = pxH,
    pixelWidth = pxW,
    pixelHeight = pxH,
    area = math.max(0, math.floor(pxW * pxH)),
    runtimeArea = runtimeInfo and runtimeInfo.areaPx or math.max(0, math.floor(pxW * pxH)),
    setSizeTried = runtimeInfo and runtimeInfo.setSizeTried or false,
    setSizeApplied = runtimeInfo and runtimeInfo.setSizeApplied or false,
    setSizeMode = runtimeInfo and runtimeInfo.setSizeMode or "none",
    targetSize = runtimeInfo and runtimeInfo.targetSize or nil,
    monitorConversion = false,
    charW = charWidthEstimate,
    charH = lineHeight,
    textGridWidth = math.max(1, math.floor(pxW / math.max(1, charWidthEstimate))),
    textGridHeight = math.max(1, math.floor(pxH / math.max(1, lineHeight))),
    textGridInformational = true,
  }
end

local function sanitizeTomWrapperMode(value)
  local mode = string.lower(tostring(value or "native"))
  if mode == "compat" or mode == "compat_term" or mode == "text_grid" then
    return "compat_term"
  end
  return "native"
end

function M.createSurface(candidate, cfg, opts)
  opts = type(opts) == "table" and opts or {}
  if type(candidate) ~= "table" or not candidate.obj then
    return nil, { kind = "none", touchEvent = "monitor_touch" }
  end

  if candidate.kind == "toms_gpu" then
    local runtimeInfo = candidate.runtime
    local finalProbe = probeTomRuntime(candidate.obj, {
      prepareRuntime = true,
      targetSize = (cfg and cfg.tomTargetSize) or 64,
    })
    if type(finalProbe) == "table" then
      runtimeInfo = finalProbe
    end
    local wrapperMode = sanitizeTomWrapperMode((cfg and cfg.tomWrapperMode) or opts.tomWrapperMode)
    if wrapperMode == "compat_term" then
      local surface, meta = buildTomTermSurface(candidate.obj, cfg, runtimeInfo)
      if type(meta) == "table" then
        meta.backendFamily = "toms_native"
        meta.wrapperType = opts.debug and "toms_native_debug_compat" or "toms_native_compat"
        meta.monitorConversion = true
        meta.wrappedWidth = tonumber(meta.width) or 0
        meta.wrappedHeight = tonumber(meta.height) or 0
      end
      return surface, meta
    end
    return buildTomNativeSurface(candidate.obj, cfg, runtimeInfo, { debug = opts.debug == true })
  end

  return candidate.obj, {
    kind = candidate.kind or "cc_monitor",
    backendFamily = "classic_monitor",
    wrapperType = "classic_monitor",
    touchEvent = candidate.touchEvent or "monitor_touch",
    mapPixel = nil,
    createWindow = nil,
    width = candidate.w,
    height = candidate.h,
    wrappedWidth = candidate.w,
    wrappedHeight = candidate.h,
    pixelWidth = candidate.w,
    pixelHeight = candidate.h,
    area = math.max(0, math.floor((tonumber(candidate.w) or 0) * (tonumber(candidate.h) or 0))),
    runtimeArea = tonumber(candidate.runtimeArea) or 0,
    monitorConversion = false,
  }
end

function M.isDirectionalAlias(name)
  return isDirectionalAlias(name)
end

return M
