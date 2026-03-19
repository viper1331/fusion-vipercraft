local M = {}

local function clamp(value, lo, hi)
  if value < lo then return lo end
  if value > hi then return hi end
  return value
end

local function toInt(value, fallback)
  local n = tonumber(value)
  if n == nil then
    n = fallback or 0
  end
  return math.floor(n + 0.5)
end

local function copyRect(bounds)
  local b = type(bounds) == "table" and bounds or {}
  local x = toInt(b.x, 1)
  local y = toInt(b.y, 1)
  local w = math.max(1, toInt(b.w, 1))
  local h = math.max(1, toInt(b.h, 1))
  return {
    x = x,
    y = y,
    w = w,
    h = h,
    x2 = x + w - 1,
    y2 = y + h - 1,
  }
end

local function clipRect(bounds, screenW, screenH)
  local r = copyRect(bounds)
  local x1 = clamp(r.x, 1, screenW)
  local y1 = clamp(r.y, 1, screenH)
  local x2 = clamp(r.x2, 1, screenW)
  local y2 = clamp(r.y2, 1, screenH)
  if x2 < x1 or y2 < y1 then
    return nil
  end
  return {
    x = x1,
    y = y1,
    w = x2 - x1 + 1,
    h = y2 - y1 + 1,
    x2 = x2,
    y2 = y2,
  }
end

local function normalizeText(value)
  return tostring(value or ""):gsub("\r", " "):gsub("\n", " ")
end

function M.build(api)
  local writeAt = assert(api.writeAt, "writeAt is required")
  local fillArea = assert(api.fillArea, "fillArea is required")
  local shortText = type(api.shortText) == "function"
    and api.shortText
    or function(text, maxLen)
      text = normalizeText(text)
      maxLen = math.max(0, toInt(maxLen, 0))
      if #text <= maxLen then return text end
      if maxLen <= 0 then return "" end
      return text:sub(1, maxLen)
    end
  local design = assert(api.design, "design tokens are required")

  local screenW = math.max(1, toInt(design.width, 1))
  local screenH = math.max(1, toInt(design.height, 1))
  local palette = design.palette or {}
  local spacing = design.spacing or {}
  local sizes = design.sizes or {}
  local textRules = design.text or {}

  local bgMain = palette.bg or colors.black
  local panelBg = palette.panelBg or colors.black
  local panelAlt = palette.panelAlt or colors.gray
  local panelSoft = palette.panelSoft or colors.lightGray
  local border = palette.border or colors.cyan
  local borderStrong = palette.borderStrong or colors.lightBlue
  local textPrimary = palette.textPrimary or colors.white
  local textMuted = palette.textMuted or colors.lightGray
  local okTone = palette.okGreen or colors.lime
  local warnTone = palette.warningOrange or colors.orange
  local badTone = palette.criticalRed or colors.red
  local infoTone = palette.infoBlue or colors.cyan
  local gaugeBase = palette.gaugeBase or colors.gray
  local gaugeFill = palette.gaugeFill or colors.cyan

  local function truncate(text, maxLen)
    if type(textRules.truncate) == "function" then
      return textRules.truncate(text, maxLen)
    end
    return shortText(text, maxLen)
  end

  local function safeWrite(x, y, text, fg, bg, maxWidth, align)
    local yy = toInt(y, 1)
    if yy < 1 or yy > screenH then return end

    local xx = toInt(x, 1)
    local raw = normalizeText(text)
    local width = toInt(maxWidth, #raw)
    if width <= 0 then return end
    local clipped = truncate(raw, width)
    local textLen = #clipped
    if textLen <= 0 then return end

    if align == "center" then
      xx = xx + math.floor((width - textLen) / 2)
    elseif align == "right" then
      xx = xx + (width - textLen)
    end

    if xx > screenW or (xx + textLen - 1) < 1 then
      return
    end
    writeAt(xx, yy, clipped, fg or textPrimary, bg)
  end

  local function safeFill(x, y, w, h, bg)
    local clipped = clipRect({ x = x, y = y, w = w, h = h }, screenW, screenH)
    if not clipped then return end
    fillArea(clipped.x, clipped.y, clipped.w, clipped.h, bg or panelBg)
  end

  local function safeFrame(bounds, stroke, inner)
    local clipped = clipRect(bounds, screenW, screenH)
    if not clipped then return end
    local strokeColor = stroke or border
    safeFill(clipped.x, clipped.y, clipped.w, 1, strokeColor)
    safeFill(clipped.x, clipped.y2, clipped.w, 1, strokeColor)
    if clipped.h > 2 then
      safeFill(clipped.x, clipped.y + 1, 1, clipped.h - 2, strokeColor)
      safeFill(clipped.x2, clipped.y + 1, 1, clipped.h - 2, strokeColor)
    end
    if clipped.w > 2 and clipped.h > 2 then
      safeFill(clipped.x + 1, clipped.y + 1, clipped.w - 2, clipped.h - 2, inner or panelBg)
    end
  end

  local function inset(bounds, padX, padY)
    local base = copyRect(bounds)
    local dx = math.max(0, toInt(padX, spacing.innerPadding or 1))
    local dy = math.max(0, toInt(padY, spacing.innerPadding or 1))
    return copyRect({
      x = base.x + dx,
      y = base.y + dy,
      w = math.max(1, base.w - (dx * 2)),
      h = math.max(1, base.h - (dy * 2)),
    })
  end

  local function drawPanel(bounds, title, opts)
    local panel = copyRect(bounds)
    local options = type(opts) == "table" and opts or {}
    local panelBgColor = options.bg or panelBg
    local borderColor = options.border or border
    local headerBg = options.headerBg or panelAlt
    local headerFg = options.headerFg or textPrimary

    safeFrame(panel, borderColor, panelBgColor)
    if title and panel.w >= 8 then
      local headH = math.max(1, toInt(sizes.titleHeight, 1))
      safeFill(panel.x + 1, panel.y + 1, math.max(1, panel.w - 2), headH, headerBg)
      safeWrite(
        panel.x + 2,
        panel.y + 1,
        string.upper(normalizeText(title)),
        headerFg,
        headerBg,
        math.max(1, panel.w - 4),
        "left"
      )
    end
  end

  local function drawPanelHeader(bounds, title, tone)
    local panel = copyRect(bounds)
    if panel.w < 5 then return end
    local bg = panelAlt
    safeFill(panel.x + 1, panel.y + 1, math.max(1, panel.w - 2), 1, bg)
    safeWrite(panel.x + 2, panel.y + 1, title, tone or textPrimary, bg, math.max(1, panel.w - 4), "left")
  end

  local function rowY(bounds, row)
    local panel = copyRect(bounds)
    local first = panel.y + 2
    return first + math.max(0, toInt(row, 0))
  end

  local function drawSectionTitle(bounds, row, title, tone)
    local panel = copyRect(bounds)
    local y = rowY(panel, row)
    safeWrite(panel.x + 2, y, title, tone or infoTone, panelBg, math.max(1, panel.w - 4), "left")
  end

  local function drawLabelValue(bounds, row, label, value, valueTone, labelTone)
    local panel = copyRect(bounds)
    local y = rowY(panel, row)
    local usable = math.max(6, panel.w - 4)
    local keyW = clamp(math.floor(usable * 0.42), 4, math.max(4, usable - 3))
    local valueW = math.max(1, usable - keyW - 1)

    safeWrite(panel.x + 2, y, label, labelTone or textMuted, panelBg, keyW, "left")
    safeWrite(panel.x + 2 + keyW + 1, y, value, valueTone or textPrimary, panelBg, valueW, "left")
  end

  local function drawStatusBadge(bounds, row, text, tone)
    local panel = copyRect(bounds)
    local y = rowY(panel, row)
    local badgeH = math.max(1, toInt(sizes.badgeHeight, 1))
    local w = math.max(4, panel.w - 4)
    safeFill(panel.x + 2, y, w, badgeH, tone or panelSoft)
    safeWrite(panel.x + 3, y, string.upper(text), textPrimary, tone or panelSoft, w - 2, "left")
  end

  local function drawHorizontalBar(bounds, row, ratio, fg, bg, label)
    local panel = copyRect(bounds)
    local y = rowY(panel, row)
    local width = math.max(4, panel.w - 4)
    local barH = math.max(1, toInt(sizes.gaugeThickness, 1))
    local fill = clamp(math.floor((tonumber(ratio) or 0) * width + 0.5), 0, width)
    safeFill(panel.x + 2, y, width, barH, bg or gaugeBase)
    if fill > 0 then
      safeFill(panel.x + 2, y, fill, barH, fg or gaugeFill)
    end
    if label and width >= 6 then
      safeWrite(panel.x + 2, y, label, textPrimary, nil, width, "center")
    end
  end

  local function drawButton(bounds, label, options)
    local b = copyRect(bounds)
    local opts = type(options) == "table" and options or {}
    local face = opts.bg or panelSoft
    local tone = opts.fg or textPrimary
    local stroke = opts.border or borderStrong
    safeFrame(b, stroke, face)
    safeWrite(b.x + 1, b.y + math.floor((b.h - 1) / 2), label, tone, face, math.max(1, b.w - 2), "center")
  end

  local function drawHeader(bounds, leftText, centerText, rightText, centerTone, rightTone)
    local area = copyRect(bounds)
    safeFill(area.x, area.y, area.w, area.h, panelAlt)
    safeFill(area.x, area.y2, area.w, 1, borderStrong)
    local textY = area.y + math.floor((area.h - 1) / 2)
    safeWrite(area.x + 1, textY, leftText, textPrimary, panelAlt, math.max(1, math.floor(area.w * 0.33)), "left")
    safeWrite(area.x, textY, centerText, centerTone or infoTone, panelAlt, area.w, "center")
    safeWrite(area.x + 1, textY, rightText, rightTone or warnTone, panelAlt, math.max(1, area.w - 2), "right")
  end

  local function drawFooter(bounds, segments)
    local area = copyRect(bounds)
    safeFill(area.x, area.y, area.w, area.h, panelAlt)
    safeFill(area.x, area.y, area.w, 1, borderStrong)

    segments = type(segments) == "table" and segments or {}
    if #segments == 0 then
      return
    end

    local y = area.y + math.floor((area.h - 1) / 2)
    local x = area.x + 1
    local gap = math.max(1, toInt(spacing.lineGap, 1))
    local remaining = area.w - 2
    for i = 1, #segments do
      local seg = segments[i]
      if remaining <= 0 then break end
      local raw = tostring(seg.text or "")
      local segText = truncate(raw, remaining)
      local tone = seg.tone or textMuted
      safeWrite(x, y, segText, tone, panelAlt, remaining, "left")
      x = x + #segText + gap
      remaining = (area.x + area.w - 1) - x
    end
  end

  return {
    screenW = screenW,
    screenH = screenH,
    palette = {
      bgMain = bgMain,
      panelBg = panelBg,
      panelAlt = panelAlt,
      panelSoft = panelSoft,
      border = border,
      borderStrong = borderStrong,
      textPrimary = textPrimary,
      textMuted = textMuted,
      ok = okTone,
      warn = warnTone,
      bad = badTone,
      info = infoTone,
      gaugeBase = gaugeBase,
      gaugeFill = gaugeFill,
    },
    safeWrite = safeWrite,
    safeFill = safeFill,
    safeFrame = safeFrame,
    inset = inset,
    drawPanel = drawPanel,
    drawPanelHeader = drawPanelHeader,
    drawSectionTitle = drawSectionTitle,
    drawLabelValue = drawLabelValue,
    drawStatusBadge = drawStatusBadge,
    drawHorizontalBar = drawHorizontalBar,
    drawButton = drawButton,
    drawHeader = drawHeader,
    drawFooter = drawFooter,
  }
end

return M
