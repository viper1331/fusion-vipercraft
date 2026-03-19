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
  local r = copyRect(bounds)
  local x1 = clamp(r.x, 1, maxW)
  local y1 = clamp(r.y, 1, maxH)
  local x2 = clamp(r.x2, 1, maxW)
  local y2 = clamp(r.y2, 1, maxH)
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

  local theme = options.theme or {}
  local palette = theme.palette or {}
  local spacing = theme.spacing or {}
  local sizes = theme.sizes or {}
  local text = theme.text or {}
  local truncate = type(text.truncate) == "function"
    and text.truncate
    or function(value, maxLen)
      local raw = tostring(value or "")
      maxLen = math.max(0, asInt(maxLen, 0))
      if #raw <= maxLen then return raw end
      return raw:sub(1, maxLen)
    end

  local function safeWrite(x, y, value, fg, bg, maxWidth, align)
    local yy = asInt(y, 1)
    if yy < 1 or yy > height then return end

    local xx = asInt(x, 1)
    local widthLimit = asInt(maxWidth, #tostring(value or ""))
    if widthLimit <= 0 then return end
    local raw = tostring(value or "")
    local out = truncate(raw, widthLimit)
    local outLen = #out
    if outLen <= 0 then return end

    if align == "center" then
      xx = xx + math.floor((widthLimit - outLen) / 2)
    elseif align == "right" then
      xx = xx + (widthLimit - outLen)
    end

    if xx > width or (xx + outLen - 1) < 1 then
      return
    end

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
    end
    if outLen <= 0 then return end

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

  local function safeFill(x, y, w, h, bg)
    local clipped = fitRect(rect(x, y, w, h), width, height)
    if not clipped then return end
    if type(target.setBackgroundColor) == "function" and bg ~= nil then
      pcall(target.setBackgroundColor, bg)
    end
    local line = makeSpaces(clipped.w)
    if line == "" then return end
    for yy = clipped.y, clipped.y2 do
      if type(target.setCursorPos) == "function" and type(target.write) == "function" then
        pcall(target.setCursorPos, clipped.x, yy)
        pcall(target.write, line)
      end
    end
  end

  local function safeFrame(bounds, stroke, fill)
    local b = fitRect(bounds, width, height)
    if not b then return end
    local borderColor = stroke or palette.border or colors.lightBlue
    safeFill(b.x, b.y, b.w, 1, borderColor)
    safeFill(b.x, b.y2, b.w, 1, borderColor)
    if b.h > 2 then
      safeFill(b.x, b.y + 1, 1, b.h - 2, borderColor)
      safeFill(b.x2, b.y + 1, 1, b.h - 2, borderColor)
    end
    if b.w > 2 and b.h > 2 then
      safeFill(b.x + 1, b.y + 1, b.w - 2, b.h - 2, fill or palette.panelBg or colors.black)
    end
  end

  local function drawPanel(bounds, title, opts)
    local b = copyRect(bounds)
    local cfg = type(opts) == "table" and opts or {}
    local panelBg = cfg.bg or palette.panelBg or colors.black
    local panelBorder = cfg.border or palette.border or colors.lightBlue
    local headerBg = cfg.headerBg or palette.panelBgSoft or colors.blue
    local headerText = cfg.headerText or palette.textPrimary or colors.white

    safeFrame(b, panelBorder, panelBg)
    if title and b.w >= 8 then
      local hh = math.max(1, asInt(sizes.panelHeaderHeight, 1))
      safeFill(b.x + 1, b.y + 1, math.max(1, b.w - 2), hh, headerBg)
      safeWrite(
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
    local bg = palette.panelBgSoft or colors.blue
    safeFill(b.x + 1, b.y + 1, math.max(1, b.w - 2), 1, bg)
    safeWrite(b.x + 2, b.y + 1, title, tone or palette.textPrimary or colors.white, bg, math.max(1, b.w - 4), "left")
  end

  local function rowY(bounds, rowIndex)
    local b = copyRect(bounds)
    local base = b.y + 2
    return base + math.max(0, asInt(rowIndex, 0))
  end

  local function drawSectionTitle(bounds, rowIndex, title, tone)
    local b = copyRect(bounds)
    local y = rowY(b, rowIndex)
    safeWrite(b.x + 2, y, title, tone or palette.info or colors.cyan, b.bg, math.max(1, b.w - 4), "left")
  end

  local function drawLabelValue(bounds, rowIndex, label, value, valueTone, labelTone)
    local b = copyRect(bounds)
    local y = rowY(b, rowIndex)
    local usable = math.max(6, b.w - 4)
    local keyW = clamp(math.floor(usable * 0.45), 4, math.max(4, usable - 2))
    local valW = math.max(1, usable - keyW - 1)
    safeWrite(b.x + 2, y, label, labelTone or palette.textMuted or colors.lightGray, nil, keyW, "left")
    safeWrite(b.x + 2 + keyW + 1, y, value, valueTone or palette.textPrimary or colors.white, nil, valW, "left")
  end

  local function drawStatusBadge(bounds, rowIndex, textValue, tone)
    local b = copyRect(bounds)
    local y = rowY(b, rowIndex)
    local badgeW = math.max(4, b.w - 4)
    local badgeColor = tone or palette.panelBgRaised or colors.gray
    safeFill(b.x + 2, y, badgeW, math.max(1, asInt(sizes.badgeHeight, 1)), badgeColor)
    safeWrite(b.x + 3, y, string.upper(tostring(textValue)), palette.textPrimary or colors.white, badgeColor, math.max(1, badgeW - 2), "left")
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

    safeFill(b.x + 2, y, gaugeW, gaugeH, bg)
    if fillW > 0 then
      safeFill(b.x + 2, y, fillW, gaugeH, fg)
    end

    if cfg.label and gaugeW >= 8 then
      safeWrite(b.x + 2, y, cfg.label, palette.textPrimary or colors.white, nil, gaugeW, "center")
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
    safeFill(b.x, b.y, b.w, b.h, bg or palette.panelBgRaised or colors.gray)
    if fillH > 0 then
      safeFill(b.x, b.y2 - fillH + 1, b.w, fillH, fg or palette.info or colors.cyan)
    end
    if label and b.w >= 4 then
      safeWrite(b.x, b.y + math.floor((b.h - 1) / 2), label, palette.textPrimary or colors.white, nil, b.w, "center")
    end
  end

  local function drawButton(bounds, label, opts)
    local b = copyRect(bounds)
    local cfg = type(opts) == "table" and opts or {}
    safeFrame(
      b,
      cfg.border or palette.borderStrong or colors.cyan,
      cfg.bg or palette.buttonFace or colors.gray
    )
    safeWrite(
      b.x + 1,
      b.y + math.floor((b.h - 1) / 2),
      label or "",
      cfg.fg or palette.textPrimary or colors.white,
      cfg.bg or palette.buttonFace or colors.gray,
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
      drawButton(
        rect(x, b.y, bw, b.h),
        item.label or "",
        item
      )
      x = x + bw + gap
    end
  end

  local function reactorStateTone(model)
    local st = tostring((model and model.reactorState) or "offline")
    if st == "active" then return palette.reactorCoreActive or colors.orange end
    if st == "ready" then return palette.reactorCoreReady or colors.lime end
    if st == "warning" then return palette.reactorCoreWarn or colors.red end
    return palette.reactorCoreIdle or colors.cyan
  end

  local function flowTone(isOpen, flowColor)
    if isOpen then
      return flowColor
    end
    return palette.textMuted or colors.gray
  end

  local function drawPipePath(path, color)
    for i = 1, #path do
      local p = path[i]
      safeFill(p.x, p.y, p.w, p.h, color)
    end
  end

  local function drawReactorCore(bounds, model)
    local b = copyRect(bounds)
    local inner = inset(b, 1, 1, 1, 1)
    safeFill(inner.x, inner.y, inner.w, inner.h, palette.panelBg or colors.black)

    local cx = inner.x + math.floor(inner.w / 2)
    local cy = inner.y + math.floor(inner.h / 2)
    local reactorW = clamp(math.floor(inner.w * 0.58), 14, math.max(14, inner.w - 4))
    local reactorH = clamp(math.floor(inner.h * 0.56), 8, math.max(8, inner.h - 4))
    local shellX = clamp(cx - math.floor(reactorW / 2), inner.x + 1, inner.x2 - reactorW + 1)
    local shellY = clamp(cy - math.floor(reactorH / 2), inner.y + 1, inner.y2 - reactorH + 1)
    local shell = rect(shellX, shellY, reactorW, reactorH)

    safeFrame(shell, palette.reactorShellDark or colors.blue, palette.reactorShell or colors.lightBlue)
    local shellMid = inset(shell, 2, 1, 2, 1)
    safeFill(shellMid.x, shellMid.y, shellMid.w, shellMid.h, palette.reactorShell or colors.lightBlue)
    local shellCoreArea = inset(shellMid, 2, 2, 2, 2)
    safeFill(shellCoreArea.x, shellCoreArea.y, shellCoreArea.w, shellCoreArea.h, palette.panelBgSoft or colors.blue)

    local ringY = cy
    safeFill(shell.x + 1, ringY, shell.w - 2, 1, palette.reactorFlowT or colors.green)

    local pulse = asInt((model and model.tick) or 0, 0) % 6
    local coreColor = reactorStateTone(model)
    if pulse >= 3 and tostring((model and model.reactorState) or "") == "active" then
      coreColor = palette.accent or colors.purple
    end

    local coreSize = clamp(math.floor(math.min(shellCoreArea.w, shellCoreArea.h) * 0.24), 3, 7)
    local core = rect(
      cx - math.floor(coreSize / 2),
      cy - math.floor(coreSize / 2),
      coreSize,
      coreSize
    )
    safeFill(core.x, core.y, core.w, core.h, coreColor)
    safeFrame(core, palette.borderStrong or colors.cyan, coreColor)

    local beamVisible = (model and model.laserActive) or (model and model.laserCharging)
    if beamVisible then
      safeFill(cx, shell.y - 4, 1, (core.y - (shell.y - 4)), palette.reactorLaser or colors.yellow)
    end

    local tColor = flowTone((model and model.tOpen) == true, palette.reactorFlowT or colors.green)
    local dtColor = flowTone((model and model.dtOpen) == true, palette.reactorFlowDT or colors.purple)
    local dColor = flowTone((model and model.dOpen) == true, palette.reactorFlowD or colors.orange)

    drawPipePath({
      rect(shell.x + math.floor(shell.w * 0.22), shell.y2 - 2, 1, 3),
      rect(shell.x + math.floor(shell.w * 0.22), shell.y2 - 2, math.max(1, cx - (shell.x + math.floor(shell.w * 0.22)) + 1), 1),
    }, tColor)
    drawPipePath({
      rect(cx, shell.y2 - 1, 1, 3),
      rect(cx, shell.y2 - 1, 1, math.max(1, core.y2 - (shell.y2 - 1) + 1)),
    }, dtColor)
    drawPipePath({
      rect(shell.x2 - math.floor(shell.w * 0.22), shell.y2 - 2, 1, 3),
      rect(cx, shell.y2 - 2, math.max(1, (shell.x2 - math.floor(shell.w * 0.22)) - cx + 1), 1),
    }, dColor)

    safeWrite(shell.x + 1, shell.y2 + 1, "T", tColor, nil, 3, "left")
    safeWrite(cx - 1, shell.y2 + 1, "DT", dtColor, nil, 4, "center")
    safeWrite(shell.x2 - 1, shell.y2 + 1, "D", dColor, nil, 3, "right")
  end

  local function drawHeader(bounds, leftText, centerText, rightText, centerTone, rightTone)
    local b = copyRect(bounds)
    safeFill(b.x, b.y, b.w, b.h, palette.panelBgSoft or colors.blue)
    safeFill(b.x, b.y2, b.w, 1, palette.borderStrong or colors.cyan)
    local y = b.y + math.floor((b.h - 1) / 2)
    local leftW = math.max(8, math.floor(b.w * 0.28))
    safeWrite(b.x + 1, y, leftText or "", palette.textPrimary or colors.white, palette.panelBgSoft or colors.blue, leftW, "left")
    safeWrite(b.x, y, centerText or "", centerTone or palette.info or colors.cyan, palette.panelBgSoft or colors.blue, b.w, "center")
    safeWrite(b.x + 1, y, rightText or "", rightTone or palette.warning or colors.orange, palette.panelBgSoft or colors.blue, math.max(6, b.w - 2), "right")
  end

  local function drawFooter(bounds, segments)
    local b = copyRect(bounds)
    safeFill(b.x, b.y, b.w, b.h, palette.panelBgSoft or colors.blue)
    safeFill(b.x, b.y, b.w, 1, palette.borderStrong or colors.cyan)
    local y = b.y + math.floor((b.h - 1) / 2)
    local x = b.x + 1
    local remaining = b.w - 2
    local list = type(segments) == "table" and segments or {}
    for i = 1, #list do
      if remaining <= 0 then break end
      local seg = list[i]
      local textValue = truncate(seg.text or "", remaining)
      safeWrite(x, y, textValue, seg.tone or palette.textMuted or colors.lightGray, palette.panelBgSoft or colors.blue, remaining, "left")
      x = x + #textValue + 1
      remaining = (b.x + b.w - 1) - x
    end
  end

  return {
    width = width,
    height = height,
    rect = rect,
    inset = inset,
    safeWrite = safeWrite,
    safeFill = safeFill,
    safeFrame = safeFrame,
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
    drawHeader = drawHeader,
    drawFooter = drawFooter,
  }
end

return M
