local M = {}

local function asInt(value, fallback)
  local n = tonumber(value)
  if n == nil then
    n = fallback or 0
  end
  return math.floor(n + 0.5)
end

local function clamp(value, lo, hi)
  if value < lo then return lo end
  if value > hi then return hi end
  return value
end

local function copyRect(bounds)
  local b = type(bounds) == "table" and bounds or {}
  local x = asInt(b.x, 1)
  local y = asInt(b.y, 1)
  local w = math.max(1, asInt(b.w, 1))
  local h = math.max(1, asInt(b.h, 1))
  return {
    x = x,
    y = y,
    w = w,
    h = h,
    x2 = x + w - 1,
    y2 = y + h - 1,
  }
end

local function rect(x, y, w, h)
  return copyRect({ x = x, y = y, w = w, h = h })
end

local function fitRect(bounds, maxW, maxH)
  local b = copyRect(bounds)
  local x1 = clamp(b.x, 1, maxW)
  local y1 = clamp(b.y, 1, maxH)
  local x2 = clamp(b.x2, 1, maxW)
  local y2 = clamp(b.y2, 1, maxH)
  if x2 < x1 or y2 < y1 then
    return nil
  end
  return rect(x1, y1, (x2 - x1) + 1, (y2 - y1) + 1)
end

local function inset(bounds, left, top, right, bottom)
  local b = copyRect(bounds)
  local l = math.max(0, asInt(left, 0))
  local t = math.max(0, asInt(top, 0))
  local r = math.max(0, asInt(right, l))
  local bt = math.max(0, asInt(bottom, t))
  local w = b.w - l - r
  local h = b.h - t - bt
  if w < 1 then w = 1 end
  if h < 1 then h = 1 end
  local x = clamp(b.x + l, b.x, b.x2 - w + 1)
  local y = clamp(b.y + t, b.y, b.y2 - h + 1)
  return rect(x, y, w, h)
end

local function makeSpaces(count)
  if count <= 0 then return "" end
  return string.rep(" ", count)
end

local COLOR_ARGB = {
  [colors.white] = 0xFFF0F0F0,
  [colors.orange] = 0xFFF2B233,
  [colors.magenta] = 0xFFE57FD8,
  [colors.lightBlue] = 0xFF99B2F2,
  [colors.yellow] = 0xFFDEDE6C,
  [colors.lime] = 0xFF7FCC19,
  [colors.pink] = 0xFFF2B2CC,
  [colors.gray] = 0xFF4C4C4C,
  [colors.lightGray] = 0xFF999999,
  [colors.cyan] = 0xFF4C99B2,
  [colors.purple] = 0xFFB266E5,
  [colors.blue] = 0xFF3366CC,
  [colors.brown] = 0xFF7F664C,
  [colors.green] = 0xFF57A64E,
  [colors.red] = 0xFFCC4C4C,
  [colors.black] = 0xFF111111,
}

function M.new(options)
  options = type(options) == "table" and options or {}
  local target = options.target or term.current()
  local assetDrawer = type(options.assetDrawer) == "function" and options.assetDrawer or nil
  local width = asInt(options.width, 0)
  local height = asInt(options.height, 0)
  if (width <= 0 or height <= 0) and target and type(target.getSize) == "function" then
    local ok, w, h = pcall(target.getSize)
    if ok then
      width = asInt(w, 0)
      height = asInt(h, 0)
    end
  end
  width = math.max(1, width)
  height = math.max(1, height)

  local theme = type(options.theme) == "table" and options.theme or {}
  local palette = type(theme.palette) == "table" and theme.palette or {}
  local spacing = type(theme.spacing) == "table" and theme.spacing or {}
  local sizes = type(theme.sizes) == "table" and theme.sizes or {}
  local metrics = type(theme.metrics) == "table" and theme.metrics or {}
  local nativePixels = metrics.nativePixels == true
  local lineHeight = math.max(1, asInt(sizes.lineHeight, 1))
  local rowStep = math.max(1, asInt(sizes.dataRowHeight or lineHeight, lineHeight))
  local panelHeaderH = math.max(1, asInt(sizes.panelHeaderHeight, 1))
  local rowPadding = math.max(0, asInt(spacing.rowPadding, 0))
  local fontCharWidth = math.max(1, asInt(metrics.fontCharWidthPx or 1, 1))
  local fontCharHeight = math.max(1, asInt(metrics.fontCharHeightPx or lineHeight, lineHeight))
  local textRules = type(theme.text) == "table" and theme.text or {}
  local truncate = type(textRules.truncate) == "function"
    and textRules.truncate
    or function(value, maxLen)
      local raw = tostring(value or "")
      maxLen = math.max(0, asInt(maxLen, 0))
      if #raw <= maxLen then return raw end
      if maxLen <= 3 then return raw:sub(1, maxLen) end
      return raw:sub(1, maxLen - 3) .. "..."
    end

  local function clipText(text, maxLen)
    return truncate(tostring(text or ""), math.max(0, asInt(maxLen, 0)))
  end

  local function colorToArgb(colorValue, fallback)
    local n = tonumber(colorValue)
    if n and n > 0xFFFF then
      return math.floor(n)
    end
    if n and COLOR_ARGB[n] then
      return COLOR_ARGB[n]
    end
    local fb = tonumber(fallback)
    if fb and fb > 0xFFFF then
      return math.floor(fb)
    end
    if fb and COLOR_ARGB[fb] then
      return COLOR_ARGB[fb]
    end
    return COLOR_ARGB[colors.white]
  end

  local function callDrawVariants(methodName, variants)
    local fn = type(target) == "table" and target[methodName] or nil
    if type(fn) ~= "function" then
      return false
    end
    for _, args in ipairs(variants or {}) do
      local ok, result = pcall(fn, table.unpack(args))
      if ok and result ~= false then
        return true
      end
    end
    return false
  end

  local function measureTextPixels(textValue)
    local textRaw = tostring(textValue or "")
    if textRaw == "" then
      return 0
    end
    if type(target) == "table" and type(target.getTextLength) == "function" then
      local okLen, len = pcall(target.getTextLength, textRaw)
      if okLen and tonumber(len) then
        return math.max(1, math.floor((tonumber(len) or 0) + 0.5))
      end
    end
    return math.max(1, #textRaw * fontCharWidth)
  end

  -- Safe drawing helpers inherited from fusion_panel_v2 philosophy:
  -- clip before drawing, never assume coordinates are valid, never crash on boundaries.
  local function safeFilledRect(x, y, w, h, bg)
    local clipped = fitRect(rect(x, y, w, h), width, height)
    if not clipped then return end
    if nativePixels then
      local fillColor = colorToArgb(bg or palette.panelBg or colors.black, palette.panelBg or colors.black)
      if callDrawVariants("filledRectangle", {
        { clipped.x, clipped.y, clipped.w, clipped.h, fillColor },
        { clipped.x, clipped.y, clipped.x2, clipped.y2, fillColor },
      }) then
        return
      end
      if callDrawVariants("fillRect", {
        { clipped.x, clipped.y, clipped.w, clipped.h, fillColor },
        { clipped.x, clipped.y, clipped.x2, clipped.y2, fillColor },
      }) then
        return
      end
      if clipped.x == 1 and clipped.y == 1 and clipped.w >= width and clipped.h >= height then
        if callDrawVariants("fill", {
          { fillColor },
        }) then
          return
        end
      end
    end
    local fillLine = makeSpaces(clipped.w)
    if fillLine == "" then return end
    if type(target.setBackgroundColor) == "function" and bg ~= nil then
      pcall(target.setBackgroundColor, bg)
    end
    if type(target.setCursorPos) ~= "function" or type(target.write) ~= "function" then
      return
    end
    for yy = clipped.y, clipped.y2 do
      pcall(target.setCursorPos, clipped.x, yy)
      pcall(target.write, fillLine)
    end
  end

  local function safeRect(x, y, w, h, stroke)
    local clipped = fitRect(rect(x, y, w, h), width, height)
    if not clipped then return end
    if clipped.w <= 1 or clipped.h <= 1 then return end
    local color = stroke or palette.border or colors.lightBlue
    safeFilledRect(clipped.x, clipped.y, clipped.w, 1, color)
    safeFilledRect(clipped.x, clipped.y2, clipped.w, 1, color)
    if clipped.h > 2 then
      safeFilledRect(clipped.x, clipped.y + 1, 1, clipped.h - 2, color)
      safeFilledRect(clipped.x2, clipped.y + 1, 1, clipped.h - 2, color)
    end
  end

  local function safeText(x, y, textValue, fg, bg, maxWidth, align)
    local yy = asInt(y, 1)
    if yy < 1 or yy > height then return end
    local xx = asInt(x, 1)
    local textRaw = tostring(textValue or "")
    local widthLimitRaw = asInt(maxWidth, nativePixels and measureTextPixels(textRaw) or #textRaw)
    local widthLimit = widthLimitRaw
    if nativePixels then
      widthLimit = math.max(1, math.floor(widthLimitRaw / math.max(1, fontCharWidth)))
    end
    if widthLimit <= 0 then return end

    local out = clipText(textRaw, widthLimit)
    local outLen = #out
    if outLen <= 0 then return end
    local textSpan = nativePixels and measureTextPixels(out) or outLen
    local limitSpan = nativePixels and widthLimitRaw or widthLimit

    if align == "center" then
      xx = xx + math.floor((limitSpan - textSpan) / 2)
    elseif align == "right" then
      xx = xx + (limitSpan - textSpan)
    end

    if xx > width or (xx + textSpan - 1) < 1 then return end
    if xx < 1 then
      local cut = 1 - xx
      local cutChars = nativePixels and math.floor(cut / math.max(1, fontCharWidth)) or cut
      if cutChars >= outLen then return end
      out = out:sub(cutChars + 1)
      outLen = #out
      textSpan = nativePixels and measureTextPixels(out) or outLen
      xx = 1
    end
    if xx + textSpan - 1 > width then
      local remain = width - xx + 1
      local maxChars = nativePixels and math.max(1, math.floor(remain / math.max(1, fontCharWidth))) or remain
      out = out:sub(1, maxChars)
      outLen = #out
      if outLen <= 0 then return end
      textSpan = nativePixels and measureTextPixels(out) or outLen
    end

    if bg ~= nil then
      safeFilledRect(xx, yy, math.max(1, textSpan), math.max(1, nativePixels and fontCharHeight or 1), bg)
    end

    if nativePixels then
      local textColor = colorToArgb(fg or palette.textPrimary or colors.white, palette.textPrimary or colors.white)
      if callDrawVariants("drawText", {
        { xx, yy, out, textColor },
        { out, xx, yy, textColor },
        { xx, yy, out },
        { out, xx, yy },
      }) then
        return
      end
      if callDrawVariants("drawString", {
        { xx, yy, out, textColor },
        { out, xx, yy, textColor },
        { xx, yy, out },
        { out, xx, yy },
      }) then
        return
      end
    end

    if type(target.setBackgroundColor) == "function" and bg ~= nil then
      pcall(target.setBackgroundColor, bg)
    end
    if type(target.setTextColor) == "function" and fg ~= nil then
      pcall(target.setTextColor, fg)
    end
    if type(target.setCursorPos) == "function" and type(target.write) == "function" then
      pcall(target.setCursorPos, xx, yy)
      pcall(target.write, out)
    end
  end

  local function safeFrame(bounds, stroke, fill)
    local b = fitRect(bounds, width, height)
    if not b then return end
    local borderColor = stroke or palette.border or colors.lightBlue
    local fillColor = fill or palette.panelBg or colors.black
    safeRect(b.x, b.y, b.w, b.h, borderColor)
    if b.w > 2 and b.h > 2 then
      safeFilledRect(b.x + 1, b.y + 1, b.w - 2, b.h - 2, fillColor)
    end
  end

  local function drawAsset(key, x, y, w, h)
    if type(assetDrawer) ~= "function" then
      return false
    end
    local ok, drawn = pcall(
      assetDrawer,
      tostring(key or ""),
      asInt(x, 1),
      asInt(y, 1),
      math.max(1, asInt(w, 1)),
      math.max(1, asInt(h, 1))
    )
    if not ok then
      return false
    end
    return drawn == true
  end

  local function drawBackdrop(bounds)
    local b = copyRect(bounds)
    local bg = palette.bgRoot or colors.black
    local grid = palette.bgBackdrop or colors.gray
    safeFilledRect(b.x, b.y, b.w, b.h, bg)

    local hStride = math.max(4, math.floor(rowStep * 1.5))
    local vStride = math.max(10, math.floor(rowStep * 3.4))
    for y = b.y + hStride, b.y2, hStride do
      safeFilledRect(b.x, y, b.w, 1, grid)
    end
    for x = b.x + vStride, b.x2, vStride do
      safeFilledRect(x, b.y, 1, b.h, grid)
    end
  end

  local function drawPanel(bounds, title, opts)
    local b = copyRect(bounds)
    local cfg = type(opts) == "table" and opts or {}
    local border = cfg.border or palette.border or colors.lightBlue
    local innerBg = cfg.bg or palette.panelBg or colors.black
    local headerBg = cfg.headerBg or palette.panelHeader or colors.blue
    local headerText = cfg.headerText or palette.textPrimary or colors.white
    local shadow = cfg.shadow or palette.borderSoft or colors.gray

    if b.w < 4 or b.h < (panelHeaderH + 2) then
      safeFilledRect(b.x, b.y, b.w, b.h, innerBg)
      return
    end

    if b.w >= 6 and b.h >= 4 then
      safeFilledRect(b.x + 1, b.y + 1, b.w - 1, b.h - 1, shadow)
    end
    safeFrame(b, border, innerBg)

    if title and b.w >= 8 then
      local hh = math.min(panelHeaderH, math.max(1, b.h - 2))
      safeFilledRect(b.x + 1, b.y + 1, math.max(1, b.w - 2), hh, headerBg)
      safeText(
        b.x + 2,
        b.y + 1 + math.floor((hh - 1) / 2),
        string.upper(tostring(title)),
        headerText,
        headerBg,
        math.max(1, b.w - 4),
        "left"
      )
      if b.w > 10 then
        safeFilledRect(b.x + b.w - 4, b.y + 1, 2, 1, border)
      end
    end
  end

  local function drawPanelHeader(bounds, title, tone)
    local b = copyRect(bounds)
    if b.w < 6 then return end
    local bg = palette.panelHeaderAlt or palette.panelBgSoft or colors.gray
    local hh = math.min(panelHeaderH, math.max(1, b.h - 2))
    safeFilledRect(b.x + 1, b.y + 1, math.max(1, b.w - 2), hh, bg)
    safeText(
      b.x + 2,
      b.y + 1 + math.floor((hh - 1) / 2),
      tostring(title or ""),
      tone or palette.textPrimary or colors.white,
      bg,
      math.max(1, b.w - 4),
      "left"
    )
  end

  local function rowY(bounds, rowIndex)
    local b = copyRect(bounds)
    local top = b.y + panelHeaderH + 1 + rowPadding
    return top + (math.max(0, asInt(rowIndex, 0)) * rowStep)
  end

  local function drawSectionTitle(bounds, rowIndex, title, tone)
    local b = copyRect(bounds)
    local y = rowY(b, rowIndex)
    safeText(
      b.x + 2,
      y,
      tostring(title or ""),
      tone or palette.info or colors.cyan,
      nil,
      math.max(1, b.w - 4),
      "left"
    )
  end

  local function drawLabelValue(bounds, rowIndex, label, value, valueTone, labelTone)
    local b = copyRect(bounds)
    local y = rowY(b, rowIndex)
    if y > b.y2 then return end
    local usable = math.max(6, b.w - 4)
    local keyW = clamp(math.floor(usable * 0.44), 4, math.max(4, usable - 2))
    local valW = math.max(1, usable - keyW - 1)
    safeText(
      b.x + 2,
      y,
      tostring(label or ""),
      labelTone or palette.textMuted or colors.lightGray,
      nil,
      keyW,
      "left"
    )
    safeText(
      b.x + 2 + keyW + 1,
      y,
      tostring(value or "N/A"),
      valueTone or palette.textPrimary or colors.white,
      nil,
      valW,
      "right"
    )
  end

  local function drawStatusBadge(bounds, rowIndex, textValue, tone)
    local b = copyRect(bounds)
    local y = rowY(b, rowIndex)
    if y > b.y2 then return end
    local badgeW = math.max(4, b.w - 4)
    local badgeH = math.max(1, asInt(sizes.badgeHeight, 1))
    if y + badgeH - 1 > b.y2 then
      badgeH = math.max(1, b.y2 - y + 1)
    end
    local bg = tone or palette.panelBgRaised or colors.gray
    safeFilledRect(b.x + 2, y, badgeW, badgeH, bg)
    safeText(
      b.x + 3,
      y + math.floor((badgeH - 1) / 2),
      string.upper(tostring(textValue or "")),
      palette.textPrimary or colors.white,
      bg,
      math.max(1, badgeW - 2),
      "left"
    )
  end

  local function drawGauge(bounds, rowIndex, ratio, opts)
    local b = copyRect(bounds)
    local y = rowY(b, rowIndex)
    if y > b.y2 then return end
    local cfg = type(opts) == "table" and opts or {}
    local gaugeW = math.max(4, b.w - 4)
    local gaugeH = math.max(1, asInt(cfg.thickness, sizes.gaugeThickness or 1))
    if y + gaugeH - 1 > b.y2 then
      gaugeH = math.max(1, b.y2 - y + 1)
    end
    local value = clamp(tonumber(ratio) or 0, 0, 1)
    local fillW = clamp(math.floor((value * gaugeW) + 0.5), 0, gaugeW)
    local bg = cfg.bg or palette.panelBgRaised or colors.gray
    local fg = cfg.fg or palette.info or colors.cyan

    safeFilledRect(b.x + 2, y, gaugeW, gaugeH, bg)
    if fillW > 0 then
      safeFilledRect(b.x + 2, y, fillW, gaugeH, fg)
    end
    safeRect(b.x + 2, y, gaugeW, gaugeH, palette.borderSoft or colors.gray)
    if cfg.label and gaugeW >= 6 then
      safeText(
        b.x + 2,
        y + math.floor((gaugeH - 1) / 2),
        tostring(cfg.label),
        palette.textPrimary or colors.white,
        nil,
        gaugeW,
        "center"
      )
    end
  end

  local function drawHorizontalBar(bounds, rowIndex, ratio, fg, bg, label)
    drawGauge(bounds, rowIndex, ratio, {
      fg = fg,
      bg = bg,
      label = label,
      thickness = sizes.gaugeThickness or 1,
    })
  end

  local function drawVerticalBar(bounds, ratio, fg, bg, label)
    local b = copyRect(bounds)
    local value = clamp(tonumber(ratio) or 0, 0, 1)
    local fillH = clamp(math.floor((value * b.h) + 0.5), 0, b.h)
    safeFilledRect(b.x, b.y, b.w, b.h, bg or palette.panelBgRaised or colors.gray)
    if fillH > 0 then
      safeFilledRect(b.x, b.y2 - fillH + 1, b.w, fillH, fg or palette.info or colors.cyan)
    end
    safeRect(b.x, b.y, b.w, b.h, palette.borderSoft or colors.gray)
    if label and b.w >= 4 then
      safeText(b.x, b.y + math.floor((b.h - 1) / 2), label, palette.textPrimary or colors.white, nil, b.w, "center")
    end
  end

  local function drawButton(bounds, label, opts)
    local b = copyRect(bounds)
    local cfg = type(opts) == "table" and opts or {}
    local border = cfg.border or palette.border or colors.lightBlue
    local face = cfg.bg or palette.buttonFace or colors.gray
    local textColor = cfg.fg or palette.textPrimary or colors.white
    safeFrame(b, border, face)
    if b.w >= 6 and b.h >= 2 then
      safeFilledRect(b.x + 1, b.y + 1, math.max(1, b.w - 2), 1, face)
    end
    safeText(
      b.x + 1,
      b.y + math.floor((b.h - 1) / 2),
      tostring(label or ""),
      textColor,
      face,
      math.max(1, b.w - 2),
      "center"
    )
  end

  local function drawButtonRow(bounds, items, opts)
    local b = copyRect(bounds)
    local list = type(items) == "table" and items or {}
    if #list <= 0 then return end
    local gap = math.max(1, asInt((opts and opts.gap) or spacing.sectionGap or 1, 1))
    local each = math.max(3, math.floor((b.w - ((#list - 1) * gap)) / #list))
    local x = b.x
    for i = 1, #list do
      local bw = each
      if i == #list then
        bw = math.max(3, (b.x + b.w) - x)
      end
      local item = list[i]
      drawButton(rect(x, b.y, bw, b.h), item.label or "", item)
      x = x + bw + gap
    end
  end

  local function reactorStateTone(model)
    local st = tostring((model and model.reactorState) or "idle")
    if st == "active" then return palette.reactorCoreActive or colors.orange end
    if st == "ready" then return palette.reactorCoreReady or colors.lime end
    if st == "warning" then return palette.reactorCoreWarn or colors.red end
    return palette.reactorCoreIdle or colors.cyan
  end

  local function flowTone(isOpen, activeColor)
    if isOpen then
      return activeColor
    end
    return palette.textMuted or colors.gray
  end

  local function drawPipe(path, color)
    for i = 1, #path do
      local p = path[i]
      safeFilledRect(p.x, p.y, p.w, p.h, color)
    end
  end

  local function drawThermalMarkers(bounds, reactorBounds, coreBounds, model)
    local b = copyRect(bounds)
    local reactor = copyRect(reactorBounds)
    local core = copyRect(coreBounds)
    local leftColor = palette.warning or colors.orange
    local rightColor = palette.critical or colors.red

    local leftText = "PLASMA " .. tostring((model and model.plasmaTemp) or "N/A")
    local rightText = "CASE " .. tostring((model and model.caseTemp) or "N/A")

    local leftLabelW = math.min(math.max(10, #leftText + 1), math.max(10, math.floor(b.w * 0.34)))
    local rightLabelW = math.min(math.max(10, #rightText + 1), math.max(10, math.floor(b.w * 0.34)))

    local leftY = math.max(b.y + 1, reactor.y - 2)
    local rightY = leftY

    local leftLabelX = b.x + 1
    safeText(leftLabelX, leftY, leftText, leftColor, nil, leftLabelW, "left")
    local leftLineX = math.min(core.x - 2, leftLabelX + leftLabelW + 1)
    if leftLineX > leftLabelX + leftLabelW then
      safeFilledRect(leftLabelX + leftLabelW, leftY, leftLineX - (leftLabelX + leftLabelW) + 1, 1, leftColor)
    end
    if core.y > leftY then
      safeFilledRect(leftLineX, leftY, 1, core.y - leftY + 1, leftColor)
    end

    local rightLabelX = math.max(reactor.x2 + 3, b.x2 - rightLabelW + 1)
    safeText(rightLabelX, rightY, rightText, rightColor, nil, rightLabelW, "left")
    local rightLineEnd = rightLabelX - 2
    local rightLineStart = math.max(core.x2 + 2, reactor.x2 + 1)
    if rightLineEnd >= rightLineStart then
      safeFilledRect(rightLineStart, rightY, rightLineEnd - rightLineStart + 1, 1, rightColor)
    end
    local rightAnchorX = math.max(reactor.x2 - 1, core.x2 + 1)
    if reactor.y >= rightY then
      safeFilledRect(rightAnchorX, rightY, 1, reactor.y - rightY + 1, rightColor)
    end
  end

  local function drawReactorCore(bounds, model)
    local b = copyRect(bounds)
    local inner = inset(b, 1, 1, 1, 1)
    safeFilledRect(inner.x, inner.y, inner.w, inner.h, palette.panelBg or colors.black)

    local topPad = math.max(3, math.floor(lineHeight * 1.0))
    local bottomPad = math.max(3, math.floor(lineHeight * 0.9))
    local sidePad = math.max(2, math.floor(lineHeight * 0.5))
    local reactorArea = inset(inner, sidePad, topPad, sidePad, bottomPad)
    local cx = reactorArea.x + math.floor(reactorArea.w / 2)
    local cy = reactorArea.y + math.floor(reactorArea.h / 2)

    local reactorW = clamp(math.floor(reactorArea.w * 0.70), math.max(16, math.floor(reactorArea.w * 0.52)), math.max(18, reactorArea.w - 2))
    local reactorH = clamp(math.floor(reactorArea.h * 0.64), math.max(10, math.floor(reactorArea.h * 0.48)), math.max(12, reactorArea.h - 2))
    local reactorX = clamp(cx - math.floor(reactorW / 2), reactorArea.x, reactorArea.x2 - reactorW + 1)
    local reactorY = clamp(cy - math.floor(reactorH / 2), reactorArea.y, reactorArea.y2 - reactorH + 1)
    local reactor = rect(reactorX, reactorY, reactorW, reactorH)

    local reactorDrawn = drawAsset("reactor", reactor.x, reactor.y, reactor.w, reactor.h)
    if not reactorDrawn then
      local shellColor = palette.reactorShell or colors.lightBlue
      local shellEdge = palette.reactorShellDark or colors.blue
      safeFrame(reactor, shellEdge, shellColor)
      safeFrame(inset(reactor, 2, 2, 2, 2), shellEdge, palette.panelBgSoft or colors.blue)
    end

    local anchors = type(model) == "table" and type(model.reactorAnchors) == "table" and model.reactorAnchors or {}
    local function point(anchor, fallbackX, fallbackY)
      if type(anchor) == "table" then
        local nx = tonumber(anchor.x)
        local ny = tonumber(anchor.y)
        if nx and ny then
          local px = reactor.x + math.floor((reactor.w - 1) * clamp(nx, 0, 1))
          local py = reactor.y + math.floor((reactor.h - 1) * clamp(ny, 0, 1))
          return px, py
        end
      end
      return fallbackX, fallbackY
    end

    local coreCx, coreCy = point(anchors.core, cx, cy)
    local tX, tY = point(anchors.tritium, reactor.x + math.floor(reactor.w * 0.24), reactor.y2)
    local dtX, dtY = point(anchors.dtfuel, coreCx, reactor.y2)
    local dX, dY = point(anchors.deuterium, reactor.x2 - math.floor(reactor.w * 0.24), reactor.y2)
    local energyX, energyY = point(anchors.energy, reactor.x2, coreCy)
    local laserX, laserY = point(anchors.laser, coreCx, reactor.y)

    local coreSize = clamp(math.floor(math.min(reactor.w, reactor.h) * 0.10), 4, 9)
    local core = rect(coreCx - math.floor(coreSize / 2), coreCy - math.floor(coreSize / 2), coreSize, coreSize)
    local coreColor = reactorStateTone(model)
    safeFilledRect(core.x, core.y, core.w, core.h, coreColor)
    safeRect(core.x, core.y, core.w, core.h, palette.borderStrong or colors.cyan)
    if core.w >= 6 then
      safeText(core.x + 1, core.y + math.floor((core.h - 1) / 2), "CORE", palette.textPrimary or colors.white, nil, core.w - 2, "center")
    end

    local leftInColor = flowTone((model and model.tOpen) == true, palette.reactorFlowT or colors.green)
    local dtInColor = flowTone((model and model.dtOpen) == true, palette.reactorFlowDT or colors.purple)
    local rightInColor = flowTone((model and model.dOpen) == true, palette.reactorFlowD or colors.red)
    local lineRaise = math.max(1, math.floor(lineHeight * 1.0))
    drawPipe({
      rect(tX, tY - lineRaise, 1, math.max(2, core.y2 - (tY - lineRaise) + 1)),
      rect(math.min(tX, coreCx), coreCy, math.max(1, math.abs(coreCx - tX) + 1), 1),
    }, leftInColor)
    drawPipe({
      rect(dtX, dtY - lineRaise, 1, math.max(2, core.y2 - (dtY - lineRaise) + 1)),
    }, dtInColor)
    drawPipe({
      rect(dX, dY - lineRaise, 1, math.max(2, core.y2 - (dY - lineRaise) + 1)),
      rect(math.min(coreCx, dX), coreCy, math.max(1, math.abs(dX - coreCx) + 1), 1),
    }, rightInColor)

    safeText(tX - 2, tY + 1, "T", leftInColor, nil, 4, "left")
    safeText(dtX - 2, dtY + 1, "DT", dtInColor, nil, 5, "center")
    safeText(dX - 1, dY + 1, "D", rightInColor, nil, 4, "right")
    safeText(energyX + 1, energyY - 1, "RF", palette.energy or colors.yellow, nil, 8, "left")

    local moduleCount = clamp(asInt((model and model.laserCount) or 1, 1), 1, 8)
    local moduleH = clamp(math.floor(lineHeight * 1.20), 6, 12)
    local moduleW = clamp(math.floor(moduleH * 6.8), 28, 96)
    local moduleGap = math.max(2, math.floor(moduleH * 0.30))
    local totalW = (moduleCount * moduleW) + ((moduleCount - 1) * moduleGap)
    local startX = clamp(coreCx - math.floor(totalW / 2), inner.x + 1, inner.x2 - totalW + 1)
    local modulesY = clamp(laserY - moduleH - 4, inner.y + 1, reactor.y - moduleH - 1)
    if modulesY < inner.y then
      modulesY = inner.y
    end

    for i = 1, moduleCount do
      local mx = startX + ((i - 1) * (moduleW + moduleGap))
      local drawnModule = drawAsset("laser_module", mx, modulesY, moduleW, moduleH)
      if not drawnModule then
        safeFilledRect(mx, modulesY, moduleW, moduleH, palette.ok or colors.lime)
        safeRect(mx, modulesY, moduleW, moduleH, palette.panelBg or colors.black)
      end
    end

    local emitterY = modulesY + moduleH
    safeFilledRect(coreCx, emitterY, 1, math.max(1, reactor.y - emitterY), palette.reactorLaserCharge or colors.lightBlue)
    local beamVisible = (model and model.laserActive) == true or (model and model.laserCharging) == true
    if beamVisible then
      local beamColor = (model and model.laserActive) and (palette.reactorLaser or colors.yellow)
        or (palette.reactorLaserCharge or colors.lightBlue)
      safeFilledRect(coreCx, emitterY, 1, math.max(1, core.y - emitterY), beamColor)
    end
    safeText(coreCx - 10, modulesY - 1, tostring((model and model.laserLabel) or "LAS"), palette.ok or colors.lime, nil, 20, "center")

    drawThermalMarkers(inner, reactor, core, model)
  end

  local function drawLaserStack(bounds, model)
    local b = copyRect(bounds)
    local inner = inset(b, 1, 1, 1, 1)
    local count = math.max(1, asInt((model and model.count) or 1, 1))
    local activeCount = clamp(asInt((model and model.activeCount) or count, count), 0, count)
    local pct = clamp(asInt((model and model.pct) or 0, 0), 0, 999)
    local stateText = tostring((model and model.state) or "ABS")
    local statusColor = model and model.tone or palette.warning or colors.orange
    local charging = (model and model.charging) == true

    safeFilledRect(inner.x, inner.y, inner.w, inner.h, palette.panelBg or colors.black)

    local modulesW = clamp(math.floor(inner.w * 0.22), 5, math.max(5, inner.w - 20))
    local infoX = inner.x + modulesW + 2
    local infoW = math.max(10, inner.x2 - infoX + 1)
    local moduleX = inner.x + 1

    local infoLine = math.max(1, math.floor(rowStep * 0.9))
    safeText(infoX, inner.y, "LASER ARRAY", palette.info or colors.cyan, nil, infoW, "left")
    safeText(infoX, inner.y + infoLine, "Count", palette.textMuted or colors.lightGray, nil, 9, "left")
    safeText(infoX + 10, inner.y + infoLine, tostring(count), palette.textPrimary or colors.white, nil, math.max(1, infoW - 10), "left")
    safeText(infoX, inner.y + (infoLine * 2), "Ready", palette.textMuted or colors.lightGray, nil, 9, "left")
    safeText(infoX + 10, inner.y + (infoLine * 2), tostring(activeCount) .. "/" .. tostring(count), palette.ok or colors.lime, nil, math.max(1, infoW - 10), "left")
    safeText(infoX, inner.y + (infoLine * 3), "State", palette.textMuted or colors.lightGray, nil, 9, "left")
    safeText(infoX + 10, inner.y + (infoLine * 3), stateText, statusColor, nil, math.max(1, infoW - 10), "left")

    local modulesTop = inner.y + math.max(1, math.floor(rowStep * 0.6))
    local modulesBottom = inner.y2 - 3
    local stackHeight = math.max(1, modulesBottom - modulesTop + 1)
    local moduleGap = math.max(0, asInt(spacing.denseGap or 0, 0))
    local moduleH = math.max(1, math.min(asInt(sizes.laserModuleHeight, 2), math.floor((stackHeight - ((count - 1) * moduleGap)) / count)))
    local moduleW = math.max(3, math.min(asInt(sizes.laserModuleWidth, 3), modulesW - 2))

    for i = 1, count do
      local y = modulesTop + (i - 1) * (moduleH + moduleGap)
      if y > modulesBottom then break end
      local active = i <= activeCount
      local color = active and (palette.ok or colors.lime) or (palette.textDim or colors.gray)
      safeFilledRect(moduleX, y, moduleW, moduleH, color)
      safeRect(moduleX, y, moduleW, moduleH, palette.panelBg or colors.black)
      if moduleW >= 3 then
        safeText(moduleX, y, active and "[] " or ".. ", palette.panelBg or colors.black, nil, moduleW, "left")
      end
    end

    local gaugeW = math.max(10, infoW)
    local gaugeY = inner.y2 - math.max(2, math.floor(lineHeight * 0.55))
    local gaugeH = math.max(1, asInt(sizes.gaugeThickness, 1))
    safeText(infoX, gaugeY - 1, "Charge", palette.textMuted or colors.lightGray, nil, 9, "left")
    safeFilledRect(infoX, gaugeY, gaugeW, gaugeH, palette.panelBgRaised or colors.gray)
    local fillW = clamp(math.floor((pct / 100) * gaugeW + 0.5), 0, gaugeW)
    if fillW > 0 then
      safeFilledRect(infoX, gaugeY, fillW, gaugeH, statusColor)
    end
    safeRect(infoX, gaugeY, gaugeW, gaugeH, palette.borderSoft or colors.gray)
    safeText(infoX, gaugeY + math.floor((gaugeH - 1) / 2), tostring(pct) .. "%", palette.textPrimary or colors.white, nil, gaugeW, "center")

    local cartoucheText = charging and "LAS CHG" or ("LAS " .. stateText)
    local cartoucheY = gaugeY + gaugeH + 1
    if cartoucheY <= inner.y2 then
      safeFilledRect(infoX, cartoucheY, gaugeW, 1, statusColor)
      safeText(infoX, cartoucheY, cartoucheText, palette.textPrimary or colors.white, statusColor, gaugeW, "center")
    end
  end

  local function drawHeader(bounds, leftText, centerText, rightText, centerTone, rightTone)
    local b = copyRect(bounds)
    local bg = palette.panelHeader or colors.blue
    local border = palette.borderStrong or colors.cyan
    safeFilledRect(b.x, b.y, b.w, b.h, bg)
    safeFilledRect(b.x, b.y2, b.w, 1, border)
    local y = b.y + math.floor((b.h - 1) / 2)
    local leftW = math.max(10, math.floor(b.w * 0.30))
    local rightW = math.max(12, math.floor(b.w * 0.30))
    safeText(b.x + 1, y, leftText or "", palette.textPrimary or colors.white, bg, leftW, "left")
    safeText(b.x + leftW, y, centerText or "", centerTone or palette.info or colors.cyan, bg, math.max(8, b.w - leftW - rightW), "center")
    safeText(b.x + b.w - rightW, y, rightText or "", rightTone or palette.warning or colors.orange, bg, rightW - 1, "right")
  end

  local function drawFooter(bounds, segments)
    local b = copyRect(bounds)
    local bg = palette.panelHeaderAlt or palette.panelBgSoft or colors.gray
    safeFilledRect(b.x, b.y, b.w, b.h, bg)
    safeFilledRect(b.x, b.y, b.w, 1, palette.borderStrong or colors.cyan)
    local y = b.y + math.floor((math.max(1, math.min(b.h, lineHeight)) - 1) / 2)

    local list = type(segments) == "table" and segments or {}
    if #list <= 0 then return end
    local x = b.x + 1
    local gap = 1
    local remaining = b.w - 2
    for i = 1, #list do
      if remaining <= 0 then break end
      local seg = list[i]
      local textValue = clipText(seg.text or "", remaining)
      safeText(x, y, textValue, seg.tone or palette.textMuted or colors.lightGray, bg, remaining, "left")
      local step = nativePixels and measureTextPixels(textValue) or #textValue
      x = x + step + gap
      remaining = (b.x + b.w - 1) - x
    end
  end

  return {
    width = width,
    height = height,
    rect = rect,
    inset = inset,
    clipText = clipText,
    safeWrite = safeText,
    safeFill = safeFilledRect,
    safeFrame = safeFrame,
    safeFilledRect = safeFilledRect,
    safeRect = safeRect,
    safeText = safeText,
    drawBackdrop = drawBackdrop,
    drawPanel = drawPanel,
    drawPanelHeader = drawPanelHeader,
    drawSectionTitle = drawSectionTitle,
    drawLabelValue = drawLabelValue,
    drawStatusBadge = drawStatusBadge,
    drawGauge = drawGauge,
    drawHorizontalBar = drawHorizontalBar,
    drawVerticalBar = drawVerticalBar,
    drawButton = drawButton,
    drawButtonRow = drawButtonRow,
    drawReactorCore = drawReactorCore,
    drawLaserStack = drawLaserStack,
    drawHeader = drawHeader,
    drawFooter = drawFooter,
  }
end

return M
