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

function M.new(options)
  options = type(options) == "table" and options or {}
  local target = options.target or term.current()
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

  -- Safe drawing helpers inherited from fusion_panel_v2 philosophy:
  -- clip before drawing, never assume coordinates are valid, never crash on boundaries.
  local function safeFilledRect(x, y, w, h, bg)
    local clipped = fitRect(rect(x, y, w, h), width, height)
    if not clipped then return end
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
    local widthLimit = asInt(maxWidth, #textRaw)
    if widthLimit <= 0 then return end

    local out = clipText(textRaw, widthLimit)
    local outLen = #out
    if outLen <= 0 then return end

    if align == "center" then
      xx = xx + math.floor((widthLimit - outLen) / 2)
    elseif align == "right" then
      xx = xx + (widthLimit - outLen)
    end

    if xx > width or (xx + outLen - 1) < 1 then return end
    if xx < 1 then
      local cut = 1 - xx
      if cut >= outLen then return end
      out = out:sub(cut + 1)
      outLen = #out
      xx = 1
    end
    if xx + outLen - 1 > width then
      out = out:sub(1, width - xx + 1)
      outLen = #out
      if outLen <= 0 then return end
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

  local function drawBackdrop(bounds)
    local b = copyRect(bounds)
    safeFilledRect(b.x, b.y, b.w, b.h, palette.bgRoot or colors.black)
    local stride = (type(theme.density) == "string" and theme.density == "large") and 3 or 4
    for y = b.y + 1, b.y2, stride do
      safeFilledRect(b.x, y, b.w, 1, palette.bgBackdrop or palette.bgRoot or colors.black)
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

    if b.w < 4 or b.h < 3 then
      safeFilledRect(b.x, b.y, b.w, b.h, innerBg)
      return
    end

    if b.w >= 6 and b.h >= 4 then
      safeFilledRect(b.x + 1, b.y + 1, b.w - 1, b.h - 1, shadow)
    end
    safeFrame(b, border, innerBg)

    if title and b.w >= 8 then
      local hh = math.max(1, asInt(sizes.panelHeaderHeight, 1))
      safeFilledRect(b.x + 1, b.y + 1, math.max(1, b.w - 2), hh, headerBg)
      safeText(
        b.x + 2,
        b.y + 1,
        string.upper(tostring(title)),
        headerText,
        headerBg,
        math.max(1, b.w - 4),
        "left"
      )
    end
  end

  local function drawPanelHeader(bounds, title, tone)
    local b = copyRect(bounds)
    if b.w < 6 then return end
    local bg = palette.panelHeaderAlt or palette.panelBgSoft or colors.gray
    safeFilledRect(b.x + 1, b.y + 1, math.max(1, b.w - 2), 1, bg)
    safeText(
      b.x + 2,
      b.y + 1,
      tostring(title or ""),
      tone or palette.textPrimary or colors.white,
      bg,
      math.max(1, b.w - 4),
      "left"
    )
  end

  local function rowY(bounds, rowIndex)
    local b = copyRect(bounds)
    return b.y + 2 + math.max(0, asInt(rowIndex, 0))
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
    local usable = math.max(6, b.w - 4)
    local keyW = clamp(math.floor(usable * 0.42), 4, math.max(4, usable - 2))
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
      "left"
    )
  end

  local function drawStatusBadge(bounds, rowIndex, textValue, tone)
    local b = copyRect(bounds)
    local y = rowY(b, rowIndex)
    local badgeW = math.max(4, b.w - 4)
    local badgeH = math.max(1, asInt(sizes.badgeHeight, 1))
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
    local cfg = type(opts) == "table" and opts or {}
    local gaugeW = math.max(4, b.w - 4)
    local gaugeH = math.max(1, asInt(cfg.thickness, sizes.gaugeThickness or 1))
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

  local function drawThermalMarkers(bounds, reactorBounds, coreBounds)
    local b = copyRect(bounds)
    local reactor = copyRect(reactorBounds)
    local core = copyRect(coreBounds)

    local leftColor = palette.warning or colors.orange
    local rightColor = palette.critical or colors.red

    local leftText = "T PLAS"
    local rightText = "T STRUCT"
    local leftAnchorY = reactor.y + 2
    local rightAnchorY = reactor.y + 2

    local leftLabelX = b.x + 1
    local leftLineStart = leftLabelX + #leftText + 1
    local leftLineEnd = math.max(leftLineStart, core.x - 2)
    safeText(leftLabelX, leftAnchorY, leftText, leftColor, nil, math.max(4, reactor.x - b.x - 1), "left")
    if leftLineEnd > leftLineStart then
      safeFilledRect(leftLineStart, leftAnchorY, leftLineEnd - leftLineStart + 1, 1, leftColor)
    end
    if core.y > leftAnchorY then
      safeFilledRect(leftLineEnd, leftAnchorY, 1, core.y - leftAnchorY + 1, leftColor)
    end

    local rightTextW = #rightText + 2
    local rightLabelX = math.max(reactor.x2 + 2, b.x2 - rightTextW + 1)
    safeText(rightLabelX, rightAnchorY, rightText, rightColor, nil, rightTextW, "left")
    local rightLineStart = reactor.x2 + 1
    local rightLineEnd = rightLabelX - 2
    if rightLineEnd >= rightLineStart then
      safeFilledRect(rightLineStart, rightAnchorY, rightLineEnd - rightLineStart + 1, 1, rightColor)
    end
    safeFilledRect(reactor.x2, rightAnchorY, 1, math.max(1, reactor.y - rightAnchorY + 1), rightColor)
  end

  local function drawReactorCore(bounds, model)
    local b = copyRect(bounds)
    local inner = inset(b, 1, 1, 1, 1)
    safeFilledRect(inner.x, inner.y, inner.w, inner.h, palette.panelBg or colors.black)

    local cx = inner.x + math.floor(inner.w / 2)
    local cy = inner.y + math.floor(inner.h / 2)

    local reactorW = clamp(math.floor(inner.w * 0.58), 14, math.max(14, inner.w - 4))
    local reactorH = clamp(math.floor(inner.h * 0.60), 9, math.max(9, inner.h - 5))
    local reactorX = clamp(cx - math.floor(reactorW / 2), inner.x + 1, inner.x2 - reactorW + 1)
    local reactorY = clamp(cy - math.floor(reactorH / 2), inner.y + 2, inner.y2 - reactorH)
    local reactor = rect(reactorX, reactorY, reactorW, reactorH)

    local bodyColor = palette.reactorShell or colors.lightBlue
    local borderColor = palette.reactorShellDark or colors.blue
    safeFrame(reactor, borderColor, bodyColor)

    local shoulderW = math.max(4, math.floor(reactor.w * 0.24))
    safeFilledRect(reactor.x - 2, cy - 1, 2, 2, borderColor)
    safeFilledRect(reactor.x2 + 1, cy - 1, 2, 2, borderColor)
    safeFilledRect(reactor.x + math.floor((reactor.w - shoulderW) / 2), reactor.y - 1, shoulderW, 1, borderColor)

    local chamber = inset(reactor, 2, 2, 2, 2)
    safeFilledRect(chamber.x, chamber.y, chamber.w, chamber.h, palette.panelBgSoft or colors.blue)

    local coreSize = clamp(math.floor(math.min(chamber.w, chamber.h) * 0.24), 3, 7)
    local core = rect(cx - math.floor(coreSize / 2), cy - math.floor(coreSize / 2), coreSize, coreSize)
    local pulse = asInt((model and model.tick) or 0, 0) % 8
    local coreColor = reactorStateTone(model)
    if tostring((model and model.reactorState) or "") == "active" and pulse >= 4 then
      coreColor = palette.accent or colors.purple
    end
    safeFilledRect(core.x, core.y, core.w, core.h, coreColor)
    safeRect(core.x, core.y, core.w, core.h, palette.borderStrong or colors.cyan)
    if core.w >= 3 and core.h >= 3 then
      safeText(core.x, core.y + math.floor(core.h / 2), "##", palette.textPrimary or colors.white, nil, core.w, "center")
      safeText(core.x, core.y + math.floor((core.h - 1) / 2), "[]", palette.textPrimary or colors.white, nil, core.w, "center")
    end

    drawThermalMarkers(inner, reactor, core)

    local leftInColor = flowTone((model and model.tOpen) == true, palette.reactorFlowT or colors.green)
    local dtInColor = flowTone((model and model.dtOpen) == true, palette.reactorFlowDT or colors.purple)
    local rightInColor = flowTone((model and model.dOpen) == true, palette.reactorFlowD or colors.red)

    local leftX = reactor.x + math.floor(reactor.w * 0.24)
    local rightX = reactor.x2 - math.floor(reactor.w * 0.24)
    local bottomY = reactor.y2 + 1

    drawPipe({
      rect(leftX, bottomY - 2, 1, 3),
      rect(leftX, cy + 1, math.max(1, cx - leftX), 1),
      rect(cx - 1, cy, 1, 2),
    }, leftInColor)
    drawPipe({
      rect(cx, bottomY - 2, 1, 3),
      rect(cx, cy + 1, 1, 2),
    }, dtInColor)
    drawPipe({
      rect(rightX, bottomY - 2, 1, 3),
      rect(cx + 1, cy + 1, math.max(1, rightX - cx), 1),
      rect(cx + 1, cy, 1, 2),
    }, rightInColor)

    local ringY = cy
    safeFilledRect(reactor.x + 1, ringY, reactor.w - 2, 1, palette.reactorFlowT or colors.green)
    safeText(reactor.x + 1, bottomY + 1, "T", leftInColor, nil, 3, "left")
    safeText(cx - 1, bottomY + 1, "DT", dtInColor, nil, 4, "center")
    safeText(reactor.x2 - 1, bottomY + 1, "D", rightInColor, nil, 3, "right")

    local beamVisible = (model and model.laserActive) == true or (model and model.laserCharging) == true
    if beamVisible then
      local beamColor = (model and model.laserActive) and (palette.reactorLaser or colors.yellow)
        or (palette.reactorLaserCharge or colors.lightBlue)
      local beamTop = reactor.y - 4
      local beamHeight = core.y - beamTop
      if beamHeight > 0 then
        safeFilledRect(cx, beamTop, 1, beamHeight, beamColor)
      end
      safeText(cx - 3, beamTop - 1, (model and model.laserLabel) or "LAS", beamColor, nil, 7, "center")
    end
  end

  local function drawLaserStack(bounds, model)
    local b = copyRect(bounds)
    local inner = inset(b, 1, 1, 1, 1)
    local count = math.max(1, asInt((model and model.count) or 1, 1))
    local activeCount = clamp(asInt((model and model.activeCount) or count, count), 0, count)
    local pct = clamp(asInt((model and model.pct) or 0, 0), 0, 999)
    local stateText = tostring((model and model.state) or "ABS")
    local statusColor = model and model.tone or palette.warning or colors.orange

    safeFilledRect(inner.x, inner.y, inner.w, inner.h, palette.panelBg or colors.black)

    local infoLine = string.format("LAS x%d (%d) %d%% %s", count, activeCount, pct, stateText)
    safeText(inner.x + 1, inner.y, infoLine, statusColor, nil, math.max(1, inner.w - 2), "center")

    local modulesTop = inner.y + 2
    local modulesBottom = inner.y2 - 2
    local stackHeight = math.max(1, modulesBottom - modulesTop + 1)
    local moduleGap = (count >= 5) and 0 or math.max(0, asInt(spacing.denseGap or 0, 0))
    local moduleH = math.max(1, math.floor((stackHeight - ((count - 1) * moduleGap)) / count))
    if moduleH <= 0 then
      moduleH = 1
      moduleGap = 0
    end
    local moduleW = math.max(3, math.min(5, asInt(sizes.laserModuleWidth, 3)))
    local moduleX = inner.x + math.floor((inner.w - moduleW) / 2)

    for i = 1, count do
      local y = modulesTop + (i - 1) * (moduleH + moduleGap)
      if y > modulesBottom then break end
      local color = (i <= activeCount) and (palette.ok or colors.lime) or (palette.textMuted or colors.gray)
      safeFilledRect(moduleX, y, moduleW, moduleH, color)
      safeRect(moduleX, y, moduleW, moduleH, palette.panelBg or colors.black)
    end

    local cartoucheText = "LAS " .. stateText
    local cartoucheY = inner.y2 - 1
    safeFilledRect(inner.x + 2, cartoucheY, math.max(4, inner.w - 4), 1, statusColor)
    safeText(inner.x + 2, cartoucheY, cartoucheText, palette.textPrimary or colors.white, statusColor, math.max(4, inner.w - 4), "center")
  end

  local function drawHeader(bounds, leftText, centerText, rightText, centerTone, rightTone)
    local b = copyRect(bounds)
    local bg = palette.panelHeader or colors.blue
    local border = palette.borderStrong or colors.cyan
    safeFilledRect(b.x, b.y, b.w, b.h, bg)
    safeFilledRect(b.x, b.y2, b.w, 1, border)
    local y = b.y + math.floor((b.h - 1) / 2)
    local leftW = math.max(8, math.floor(b.w * 0.28))
    safeText(b.x + 1, y, leftText or "", palette.textPrimary or colors.white, bg, leftW, "left")
    safeText(b.x, y, centerText or "", centerTone or palette.info or colors.cyan, bg, b.w, "center")
    safeText(b.x + 1, y, rightText or "", rightTone or palette.warning or colors.orange, bg, math.max(8, b.w - 2), "right")
  end

  local function drawFooter(bounds, segments)
    local b = copyRect(bounds)
    local bg = palette.panelHeaderAlt or palette.panelBgSoft or colors.gray
    safeFilledRect(b.x, b.y, b.w, b.h, bg)
    safeFilledRect(b.x, b.y, b.w, 1, palette.borderStrong or colors.cyan)
    local y = b.y + math.floor((b.h - 1) / 2)

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
      x = x + #textValue + gap
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
