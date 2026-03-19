local M = {}

local function clamp(value, lo, hi)
  if value < lo then return lo end
  if value > hi then return hi end
  return value
end

local function rect(x, y, w, h)
  w = math.max(1, math.floor(tonumber(w) or 1))
  h = math.max(1, math.floor(tonumber(h) or 1))
  x = math.floor(tonumber(x) or 1)
  y = math.floor(tonumber(y) or 1)
  return {
    x = x,
    y = y,
    w = w,
    h = h,
    x2 = x + w - 1,
    y2 = y + h - 1,
  }
end

local function resolveGap(total, count, gap)
  local gapSize = math.max(0, math.floor(tonumber(gap) or 0))
  if count <= 1 then
    return 0
  end
  local maxGap = math.floor((math.max(0, total) - count) / (count - 1))
  if maxGap < 0 then
    maxGap = 0
  end
  if gapSize > maxGap then
    gapSize = maxGap
  end
  return gapSize
end

local function inset(bounds, left, top, right, bottom)
  left = math.max(0, math.floor(tonumber(left) or 0))
  top = math.max(0, math.floor(tonumber(top) or 0))
  right = math.max(0, math.floor(tonumber(right) or left))
  bottom = math.max(0, math.floor(tonumber(bottom) or top))

  local w = bounds.w - left - right
  local h = bounds.h - top - bottom
  if w < 1 then w = 1 end
  if h < 1 then h = 1 end
  local maxX = bounds.x + bounds.w - w
  local maxY = bounds.y + bounds.h - h
  local x = clamp(bounds.x + left, bounds.x, maxX)
  local y = clamp(bounds.y + top, bounds.y, maxY)
  return rect(x, y, w, h)
end

local function splitAxis(total, specs, gap)
  local count = #specs
  if count <= 0 then
    return {}
  end

  local gapSize = resolveGap(total, count, gap)
  local totalGap = gapSize * math.max(0, count - 1)
  local usable = math.max(1, total - totalGap)

  local sizes = {}
  local minSum = 0
  local weightSum = 0
  for i = 1, count do
    local minSize = math.max(1, math.floor(tonumber(specs[i].min) or 1))
    sizes[i] = minSize
    minSum = minSum + minSize
    weightSum = weightSum + math.max(0, tonumber(specs[i].weight) or 0)
  end

  if minSum > usable then
    local overflow = minSum - usable
    for i = count, 1, -1 do
      if overflow <= 0 then break end
      local canCut = math.max(0, sizes[i] - 1)
      local cut = math.min(canCut, overflow)
      sizes[i] = sizes[i] - cut
      overflow = overflow - cut
    end
  else
    local extra = usable - minSum
    if extra > 0 then
      if weightSum <= 0 then weightSum = count end
      for i = 1, count do
        local weight = math.max(0, tonumber(specs[i].weight) or 0)
        if weightSum == count and weight == 0 then
          weight = 1
        end
        if weight > 0 then
          local add = math.floor((extra * weight) / weightSum)
          sizes[i] = sizes[i] + add
        end
      end
      local used = 0
      for i = 1, count do used = used + sizes[i] end
      local rem = usable - used
      local idx = 1
      while rem > 0 do
        sizes[idx] = sizes[idx] + 1
        idx = (idx % count) + 1
        rem = rem - 1
      end
    end
  end

  return sizes, gapSize
end

local function splitColumns(bounds, specs, gap)
  local widths, gapSize = splitAxis(bounds.w, specs, gap)
  local out = {}
  local x = bounds.x
  for i = 1, #specs do
    out[specs[i].key] = rect(x, bounds.y, widths[i], bounds.h)
    x = x + widths[i] + gapSize
  end
  return out
end

local function splitRows(bounds, specs, gap)
  local heights, gapSize = splitAxis(bounds.h, specs, gap)
  local out = {}
  local y = bounds.y
  for i = 1, #specs do
    out[specs[i].key] = rect(bounds.x, y, bounds.w, heights[i])
    y = y + heights[i] + gapSize
  end
  return out
end

local function buildMainColumns(content, density, gap)
  if density == "small" and (content.w < 94 or content.h < 30) then
    local stack = splitRows(content, {
      { key = "left", min = 5, weight = 3 },
      { key = "center", min = 7, weight = 5 },
      { key = "right", min = 5, weight = 4 },
    }, gap)
    return stack, true
  end

  local columns = splitColumns(content, {
    { key = "left", min = (density == "large") and 28 or 22, weight = 28 },
    { key = "center", min = (density == "large") and 44 or 34, weight = 48 },
    { key = "right", min = (density == "large") and 26 or 20, weight = 24 },
  }, gap)
  return columns, false
end

function M.compute(width, height, design, currentView)
  local minW, minH = 34, 14
  if width < minW or height < minH then
    return {
      tooSmall = true,
      minW = minW,
      minH = minH,
      density = (design and design.density) or "small",
      view = currentView or "supervision",
      root = rect(1, 1, math.max(1, width), math.max(1, height)),
    }
  end

  local spacing = design.spacing
  local sizes = design.sizes
  local density = design.density

  local root = rect(1, 1, width, height)
  local headerH = clamp(math.max(1, sizes.headerHeight or 1), 1, math.max(1, height - 2))
  local footerH = clamp(math.max(1, sizes.footerHeight or 1), 1, math.max(1, height - headerH - 1))
  local header = rect(1, 1, width, headerH)
  local footerY = math.max(header.y2 + 1, height - footerH + 1)
  local footer = rect(1, footerY, width, footerH)

  if footer.y < header.y2 + 1 then
    footer = rect(1, header.y2 + 1, width, 1)
  end

  local contentY = header.y2 + 1
  local contentH = footer.y - contentY
  if contentH < 1 then
    contentH = 1
    contentY = math.min(height, header.y2 + 1)
  end
  local content = rect(1, contentY, width, contentH)

  local inner = inset(content, spacing.outerMargin, spacing.outerMargin, spacing.outerMargin, spacing.outerMargin)
  local columns, stacked = buildMainColumns(inner, density, spacing.panelGap)

  local leftInner = inset(columns.left, spacing.innerPadding, spacing.innerPadding, spacing.innerPadding, spacing.innerPadding)
  local centerInner = inset(columns.center, spacing.innerPadding, spacing.innerPadding, spacing.innerPadding, spacing.innerPadding)
  local rightInner = inset(columns.right, spacing.innerPadding, spacing.innerPadding, spacing.innerPadding, spacing.innerPadding)

  local leftRows = splitRows(leftInner, {
    { key = "summary", min = 4, weight = 3 },
    { key = "warnings", min = 4, weight = 3 },
    { key = "events", min = 4, weight = 4 },
  }, spacing.lineGap)

  local centerRows = splitRows(centerInner, {
    { key = "summary", min = 3, weight = 2 },
    { key = "reactor", min = 8, weight = 6 },
    { key = "temps", min = 3, weight = 2 },
    { key = "laser", min = 3, weight = 2 },
    { key = "status", min = 3, weight = 2 },
  }, spacing.lineGap)

  local rightRows = splitRows(rightInner, {
    { key = "nav", min = 4, weight = 3 },
    { key = "actions", min = 6, weight = 5 },
    { key = "io", min = 4, weight = 4 },
  }, spacing.lineGap)

  local navBounds = rightRows.nav
  local actionsBounds = rightRows.actions
  local ioBounds = rightRows.io

  local combinedButtonTop = math.min(navBounds.y, actionsBounds.y)
  local combinedButtonBottom = math.max(navBounds.y2, actionsBounds.y2)
  local combinedButtonBounds = rect(
    rightInner.x,
    combinedButtonTop,
    rightInner.w,
    math.max(1, (combinedButtonBottom - combinedButtonTop) + 1)
  )
  local buttonBounds = inset(combinedButtonBounds, 1, 1, 1, 1)
  if buttonBounds.h < 3 then
    buttonBounds.h = math.max(1, math.min(3, combinedButtonBounds.h))
    buttonBounds.y2 = buttonBounds.y + buttonBounds.h - 1
  end
  if buttonBounds.w < 6 then
    buttonBounds.w = math.max(1, math.min(6, combinedButtonBounds.w))
    buttonBounds.x2 = buttonBounds.x + buttonBounds.w - 1
  end

  local legacyMode = "standard"
  if stacked then
    legacyMode = "compact"
  elseif density == "large" then
    legacyMode = "large"
  end

  return {
    tooSmall = false,
    density = density,
    stacked = stacked,
    view = currentView or "supervision",
    root = root,
    header = header,
    content = content,
    footer = footer,
    columns = columns,
    left = leftRows,
    center = centerRows,
    right = rightRows,
    controls = {
      navBounds = navBounds,
      actionsBounds = actionsBounds,
      buttonBounds = buttonBounds,
      ioBounds = ioBounds,
    },
    legacy = {
      mode = legacyMode,
      top = content.y,
      bottom = content.y2,
      height = content.h,
      width = width,
      tooSmall = false,
      left = columns.left,
      center = columns.center,
      right = columns.right,
    },
  }
end

M.rect = rect
M.inset = inset

return M
