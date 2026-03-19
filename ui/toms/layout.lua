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
  local minW, minH = 52, 24

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
  local root = rect(1, 1, w, h)

  local headerH = clamp(math.max(1, asInt(sizes.headerHeight, 2)), 1, math.max(1, h - 2))
  local footerH = clamp(math.max(3, asInt(sizes.footerHeight, 5)), 3, math.max(3, h - headerH - 2))
  local header = rect(1, 1, w, headerH)
  local footer = rect(1, h - footerH + 1, w, footerH)
  if footer.y <= header.y2 then
    footer = rect(1, header.y2 + 1, w, 3)
  end

  local content = rect(1, header.y2 + 1, w, math.max(1, footer.y - (header.y2 + 1)))
  local contentInner = inset(content, spacing.outerMargin, spacing.outerMargin, spacing.outerMargin, spacing.outerMargin)
  local isSmallStack = theme.density == "small" and (contentInner.w < 112 or contentInner.h < 36)

  local columns
  local stacked = false
  if isSmallStack then
    stacked = true
    columns = splitVertical(contentInner, {
      { key = "left", min = 4, weight = 5 },
      { key = "center", min = 6, weight = 7 },
      { key = "right", min = 4, weight = 5 },
    }, spacing.panelGap)
  else
    columns = splitHorizontal(contentInner, {
      { key = "left", min = (theme.density == "large") and 30 or 24, weight = 28 },
      { key = "center", min = (theme.density == "large") and 66 or 50, weight = 46 },
      { key = "right", min = (theme.density == "large") and 30 or 24, weight = 26 },
    }, spacing.panelGap)
  end

  local leftInner = inset(columns.left, spacing.panelPadding, spacing.panelPadding, spacing.panelPadding, spacing.panelPadding)
  local centerInner = inset(columns.center, spacing.panelPadding, spacing.panelPadding, spacing.panelPadding, spacing.panelPadding)
  local rightInner = inset(columns.right, spacing.panelPadding, spacing.panelPadding, spacing.panelPadding, spacing.panelPadding)

  local leftPanels = splitVertical(leftInner, {
    { key = "reactor", min = 4, weight = 4 },
    { key = "temperatures", min = 3, weight = 3 },
    { key = "status", min = 4, weight = 5 },
  }, spacing.sectionGap)

  local centerPanels = splitVertical(centerInner, {
    { key = "laser", min = 4, weight = 4 },
    { key = "core", min = 8, weight = 10 },
    { key = "runtime", min = 4, weight = 4 },
  }, spacing.sectionGap)

  local rightPanels = splitVertical(rightInner, {
    { key = "io", min = 4, weight = 5 },
    { key = "events", min = 4, weight = 4 },
    { key = "debug", min = 3, weight = 3 },
  }, spacing.sectionGap)

  local footerInner = inset(footer, spacing.outerMargin, 1, spacing.outerMargin, 1)
  local statusBounds = rect(footerInner.x, footerInner.y, footerInner.w, 1)
  local controlsTop = math.min(footerInner.y2, statusBounds.y2 + 1)
  local controlsHeight = math.max(1, footerInner.y2 - controlsTop + 1)
  local buttonBounds = rect(footerInner.x, controlsTop, footerInner.w, controlsHeight)
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
    content = content,
    footer = footer,
    columns = columns,
    left = leftPanels,
    center = centerPanels,
    right = rightPanels,
    controls = {
      statusBounds = statusBounds,
      buttonBounds = buttonBounds,
      ioBounds = rightPanels.io,
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
