local M = {}

local function clamp(value, lo, hi)
  if value < lo then return lo end
  if value > hi then return hi end
  return value
end

local function normalizeText(value)
  return tostring(value or ""):gsub("\r", " "):gsub("\n", " ")
end

local function truncate(text, maxLen)
  text = normalizeText(text)
  maxLen = math.max(0, math.floor(tonumber(maxLen) or 0))
  if maxLen <= 0 then return "" end
  if #text <= maxLen then return text end
  if maxLen <= 3 then
    return text:sub(1, maxLen)
  end
  return text:sub(1, maxLen - 3) .. "..."
end

local function abbreviate(text, maxLen)
  text = normalizeText(text)
  maxLen = math.max(1, math.floor(tonumber(maxLen) or 1))
  if #text <= maxLen then return text end

  local reduced = text:gsub("[AEIOUaeiou]", "")
  if #reduced >= 3 and #reduced <= maxLen then
    return reduced
  end

  local compact = text:gsub("[%s_%-]+", "")
  if #compact <= maxLen then
    return compact
  end

  return truncate(text, maxLen)
end

local function resolveDensity(width, height)
  if width < 88 or height < 28 then
    return "small"
  end
  if width >= 146 and height >= 44 then
    return "large"
  end
  return "medium"
end

function M.build(width, height)
  width = math.max(1, math.floor(tonumber(width) or 1))
  height = math.max(1, math.floor(tonumber(height) or 1))

  local density = resolveDensity(width, height)
  local scale = 1
  if density == "medium" then
    scale = 1.2
  elseif density == "large" then
    scale = 1.45
  end

  local unit = (density == "small") and 1 or 2
  local outerMargin = (density == "large") and 2 or 1
  local panelGap = (density == "small") and 1 or 2
  local innerPadding = (density == "small") and 1 or 2

  return {
    width = width,
    height = height,
    density = density,
    scale = scale,
    palette = {
      bg = colors.black,
      panelBg = colors.blue,
      panelAlt = colors.black,
      panelSoft = colors.gray,
      border = colors.lightBlue,
      borderStrong = colors.cyan,
      textPrimary = colors.white,
      textMuted = colors.lightGray,
      infoBlue = colors.cyan,
      okGreen = colors.lime,
      warningOrange = colors.orange,
      criticalRed = colors.red,
      neutral = colors.gray,
      accent = colors.purple,
      gaugeBase = colors.gray,
      gaugeFill = colors.cyan,
    },
    spacing = {
      unit = unit,
      outerMargin = outerMargin,
      innerPadding = innerPadding,
      panelGap = panelGap,
      lineGap = 1,
    },
    sizes = {
      headerHeight = (density == "large") and 3 or 2,
      footerHeight = (density == "large") and 2 or 1,
      titleHeight = 1,
      subtitleHeight = 1,
      rowHeight = 1,
      buttonHeight = (density == "small") and 2 or 3,
      badgeHeight = 1,
      gaugeThickness = (density == "large") and 2 or 1,
    },
    text = {
      truncate = truncate,
      abbreviate = abbreviate,
      normalize = normalizeText,
    },
    clamp = clamp,
  }
end

return M
