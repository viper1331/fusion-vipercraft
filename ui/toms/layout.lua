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

local function rect(x, y, w, h)
  local rw = math.max(1, asInt(w, 1))
  local rh = math.max(1, asInt(h, 1))
  local rx = asInt(x, 1)
  local ry = asInt(y, 1)
  return {
    x = rx,
    y = ry,
    w = rw,
    h = rh,
    x2 = rx + rw - 1,
    y2 = ry + rh - 1,
  }
end

local function inset(bounds, left, top, right, bottom)
  local l = math.max(0, asInt(left, 0))
  local t = math.max(0, asInt(top, 0))
  local r = math.max(0, asInt(right, l))
  local b = math.max(0, asInt(bottom, t))

  local w = bounds.w - l - r
  local h = bounds.h - t - b
  if w < 1 then w = 1 end
  if h < 1 then h = 1 end

  local x = clamp(bounds.x + l, bounds.x, bounds.x2 - w + 1)
  local y = clamp(bounds.y + t, bounds.y, bounds.y2 - h + 1)
  return rect(x, y, w, h)
end

local function resolveGap(total, count, wantedGap)
  local gap = math.max(0, asInt(wantedGap, 0))
  if count <= 1 then
    return 0
  end
  local maxGap = math.floor((math.max(0, total) - count) / (count - 1))
  if maxGap < 0 then
    maxGap = 0
  end
  if gap > maxGap then
    gap = maxGap
  end
  return gap
end

local function splitAxis(total, specs, wantedGap)
  local count = #specs
  if count <= 0 then
    return {}, 0
  end

  local gap = resolveGap(total, count, wantedGap)
  local usable = math.max(1, total - (gap * (count - 1)))

  local sizes = {}
  local minSum = 0
  local weightSum = 0
  for i = 1, count do
    local minSize = math.max(1, asInt(specs[i].min, 1))
    sizes[i] = minSize
    minSum = minSum + minSize
    weightSum = weightSum + math.max(0, tonumber(specs[i].weight) or 0)
  end

  if minSum > usable then
    local overflow = minSum - usable
    for i = count, 1, -1 do
      if overflow <= 0 then break end
      local reducible = math.max(0, sizes[i] - 1)
      local cut = math.min(reducible, overflow)
      sizes[i] = sizes[i] - cut
      overflow = overflow - cut
    end
  else
    local extra = usable - minSum
    if extra > 0 then
      if weightSum <= 0 then
        weightSum = count
      end
      for i = 1, count do
        local weight = math.max(0, tonumber(specs[i].weight) or 0)
        if weight == 0 and weightSum == count then
          weight = 1
        end
        if weight > 0 then
          local add = math.floor((extra * weight) / weightSum)
          sizes[i] = sizes[i] + add
        end
      end
      local used = 0
      for i = 1, count do
        used = used + sizes[i]
      end
      local rem = usable - used
      local idx = 1
      while rem > 0 do
        sizes[idx] = sizes[idx] + 1
        idx = (idx % count) + 1
        rem = rem - 1
      end
    end
  end

  return sizes, gap
end

local function splitHorizontal(bounds, specs, wantedGap)
  local widths, gap = splitAxis(bounds.w, specs, wantedGap)
  local out = {}
  local x = bounds.x
  for i = 1, #specs do
    out[specs[i].key] = rect(x, bounds.y, widths[i], bounds.h)
    x = x + widths[i] + gap
  end
  return out
end

local function splitVertical(bounds, specs, wantedGap)
  local heights, gap = splitAxis(bounds.h, specs, wantedGap)
  local out = {}
  local y = bounds.y
  for i = 1, #specs do
    out[specs[i].key] = rect(bounds.x, y, bounds.w, heights[i])
    y = y + heights[i] + gap
  end
  return out
end

function M.compute(width, height, theme, currentView)
  local w = math.max(1, asInt(width, 1))
  local h = math.max(1, asInt(height, 1))
  local nativeMetrics = type(theme.metrics) == "table" and theme.metrics.nativePixels == true
  local minW, minH = nativeMetrics and 96 or 72, nativeMetrics and 64 or 32

  if w < minW or h < minH then
    return {
      tooSmall = true,
      minW = minW,
      minH = minH,
      view = currentView or "supervision",
      density = (theme and theme.density) or "small",
      root = rect(1, 1, w, h),
    }
  end

  local spacing = theme.spacing
  local sizes = theme.sizes
  local metrics = type(theme.metrics) == "table" and theme.metrics or {}
  local root = rect(1, 1, w, h)

  local headerH = clamp(math.max(2, asInt(metrics.headerHeightPx or sizes.headerHeight, 3)), 2, math.max(2, h - 14))
  local footerH = clamp(math.max(4, asInt(metrics.footerHeightPx or sizes.footerHeight, 7)), 4, math.max(4, h - headerH - 10))
  local navWanted = nativeMetrics
    and clamp(
      asInt(((sizes.lineHeight or 8) * 1.9) + (spacing.panelPadding or 2) + 4, 15),
      11,
      24
    )
    or 4
  local navMax = math.max(3, h - headerH - footerH - 6)
  local navH = clamp(navWanted, 3, navMax)
  local header = rect(1, 1, w, headerH)
  local navBar = rect(1, header.y2 + 1, w, navH)
  local footer = rect(1, h - footerH + 1, w, footerH)
  if footer.y <= navBar.y2 then
    footer = rect(1, navBar.y2 + 1, w, 4)
  end

  local content = rect(1, navBar.y2 + 1, w, math.max(1, footer.y - (navBar.y2 + 1)))
  local contentInner = inset(content, spacing.outerMargin, spacing.outerMargin, spacing.outerMargin, spacing.outerMargin)
  local stacked = (theme.density == "small" and (contentInner.w < 148 or contentInner.h < 92))
    or (nativeMetrics and (contentInner.w < 300 or contentInner.h < 200))

  local columns = {}
  local panels = {}
  local controlsButtonBounds = nil
  local controlsIoBounds = nil

  if stacked then
    local rows = splitVertical(contentInner, {
      { key = "reactor", min = nativeMetrics and 30 or 6, weight = 18 },
      { key = "temperatures", min = nativeMetrics and 24 or 5, weight = 16 },
      { key = "laser", min = nativeMetrics and 26 or 6, weight = 17 },
      { key = "core", min = nativeMetrics and 44 or 10, weight = 28 },
      { key = "status", min = nativeMetrics and 28 or 6, weight = 21 },
    }, spacing.panelGap)

    panels.reactor = rows.reactor
    panels.temperatures = rows.temperatures
    panels.laser = rows.laser
    panels.core = rows.core
    panels.status = rows.status

    columns.left = rows.reactor
    columns.center = rows.core
    columns.right = rows.status
    controlsButtonBounds = nil
    controlsIoBounds = inset(rows.laser, 1, 1, 1, 1)
  else
    local mainCols = splitHorizontal(contentInner, {
      { key = "left", min = nativeMetrics and 88 or 24, weight = 26 },
      { key = "center", min = nativeMetrics and 150 or 42, weight = 48 },
      { key = "right", min = nativeMetrics and 88 or 24, weight = 26 },
    }, spacing.panelGap)

    columns.left = mainCols.left
    columns.center = mainCols.center
    columns.right = mainCols.right

    local leftPanels = splitVertical(inset(mainCols.left, 1, 1, 1, 1), {
      { key = "reactor", min = nativeMetrics and 30 or 6, weight = 24 },
      { key = "temperatures", min = nativeMetrics and 26 or 6, weight = 24 },
      { key = "status", min = nativeMetrics and 38 or 10, weight = 52 },
    }, spacing.sectionGap)

    local rightPanels = splitVertical(inset(mainCols.right, 1, 1, 1, 1), {
      { key = "laser", min = nativeMetrics and 44 or 8, weight = 46 },
      { key = "io", min = nativeMetrics and 44 or 8, weight = 54 },
    }, spacing.sectionGap)

    panels.reactor = leftPanels.reactor
    panels.temperatures = leftPanels.temperatures
    panels.status = leftPanels.status
    panels.core = inset(mainCols.center, 1, 1, 1, 1)
    panels.laser = rightPanels.laser

    controlsButtonBounds = nil
    controlsIoBounds = rightPanels.io
  end

  local footerInsetY = nativeMetrics and math.max(2, math.floor((metrics.textLineGapPx or 1) * 0.8)) or 1
  local navMarginX = nativeMetrics and clamp(math.floor((spacing.outerMargin or 1) * 0.5), 1, 8) or 1
  local navInnerW = math.max(1, navBar.w - (navMarginX * 2))
  local navTitleH = nativeMetrics and ((navBar.h >= 6) and 2 or 1) or 1
  navTitleH = clamp(navTitleH, 1, math.max(1, navBar.h - 1))
  local navButtonsY = math.min(navBar.y2, navBar.y + navTitleH)
  local navButtonsH = math.max(1, navBar.y2 - navButtonsY + 1)
  local footerInner = inset(footer, spacing.outerMargin, footerInsetY, spacing.outerMargin, footerInsetY)
  local statusHeight = nativeMetrics
    and math.max(1, math.min(math.max(1, footerInner.h - 1), asInt(metrics.subtitleHeightPx or sizes.lineHeight, 2)))
    or (theme.nativeLike and math.max(1, math.min(footerInner.h - 1, math.floor(sizes.lineHeight * 0.75))) or 1)
  local statusBounds = rect(footerInner.x, footerInner.y, footerInner.w, statusHeight)
  local controlsTop = math.min(footerInner.y2, statusBounds.y2 + 1)
  local controlsHeight = math.max(1, footerInner.y2 - controlsTop + 1)
  local footerControlsBounds = rect(footerInner.x, controlsTop, footerInner.w, controlsHeight)
  local buttonBounds = controlsButtonBounds or footerControlsBounds
  local legacyMode = stacked and "compact" or ((theme.density == "large") and "large" or "standard")

  return {
    tooSmall = false,
    minW = minW,
    minH = minH,
    density = theme.density,
    stacked = stacked,
    view = currentView or "supervision",
    root = root,
    header = header,
    navBar = navBar,
    content = content,
    footer = footer,
    columns = columns,
    panels = panels,
    left = {
      reactor = panels.reactor,
      temperatures = panels.temperatures,
      status = panels.status,
    },
    center = {
      laser = panels.laser,
      core = panels.core,
      runtime = panels.status,
    },
    right = {
      io = panels.laser,
      events = panels.status,
      debug = panels.status,
    },
    controls = {
      statusBounds = statusBounds,
      buttonBounds = buttonBounds,
      ioBounds = controlsIoBounds or panels.status,
      navTitleBounds = rect(navBar.x + navMarginX, navBar.y, navInnerW, navTitleH),
      navBounds = rect(navBar.x + navMarginX, navButtonsY, navInnerW, navButtonsH),
      footerBounds = footerInner,
    },
    legacy = {
      mode = legacyMode,
      top = content.y,
      bottom = content.y2,
      height = content.h,
      width = w,
      tooSmall = false,
      left = columns.left,
      center = columns.center,
      right = columns.right,
    },
  }
end

M.rect = rect
M.inset = inset
M.splitHorizontal = splitHorizontal
M.splitVertical = splitVertical

return M
