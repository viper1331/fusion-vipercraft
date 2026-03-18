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

function M.detectCandidate(name, obj, getTypeOf)
  if not obj then return nil end
  local ptype = ""
  if type(getTypeOf) == "function" then
    ptype = tostring(getTypeOf(name) or "")
  elseif peripheral and type(peripheral.getType) == "function" and name then
    local ok, t = pcall(peripheral.getType, name)
    if ok then ptype = tostring(t or "") end
  end

  if looksLikeTomGpu(ptype, name, obj) then
    local scale = 1
    local pxW, pxH = readTomResolution(obj)
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

local function buildTomTermSurface(gpu, cfg)
  local scale = sanitizeTomScale(cfg and cfg.monitorScale)
  local charW = math.max(2, math.floor((6 * scale) + 0.5))
  local charH = math.max(3, math.floor((9 * scale) + 0.5))
  local pxW, pxH = readTomResolution(gpu)
  local width = math.max(1, math.floor((pxW or 192) / charW))
  local height = math.max(1, math.floor((pxH or 108) / charH))

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

  local function drawFill(x, y, w, h, color)
    if callGpu("filledRectangle", x, y, w, h, color) then return end
    if callGpu("fillRect", x, y, w, h, color) then return end
    if x == 1 and y == 1 and pxW and pxH and w >= pxW and h >= pxH then
      if callGpu("fill", color) then return end
    end
  end

  local function drawGlyph(x, y, char, color)
    if char == " " then return end
    if callGpu("drawText", x, y, char, color, -1, scale) then return end
    if callGpu("drawString", x, y, char, color) then return end
    callGpu("drawChar", x, y, string.byte(char), color, -1, scale)
  end

  local cursorX, cursorY = 1, 1
  local textColor, bgColor = colors.white, colors.black
  local cursorBlink = false

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
    width = width,
    height = height,
    charW = charW,
    charH = charH,
  }
end

function M.createSurface(candidate, cfg)
  if type(candidate) ~= "table" or not candidate.obj then
    return nil, { kind = "none", touchEvent = "monitor_touch" }
  end

  if candidate.kind == "toms_gpu" then
    return buildTomTermSurface(candidate.obj, cfg)
  end

  return candidate.obj, {
    kind = candidate.kind or "cc_monitor",
    touchEvent = candidate.touchEvent or "monitor_touch",
    mapPixel = nil,
    width = candidate.w,
    height = candidate.h,
  }
end

return M
