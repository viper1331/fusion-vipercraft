local M = {}

local function clamp(value, lo, hi)
  if value < lo then return lo end
  if value > hi then return hi end
  return value
end

local function asInt(value, fallback)
  local n = tonumber(value)
  if n == nil then
    n = fallback or 0
  end
  return math.floor(n + 0.5)
end

local function normalizeText(text)
  return tostring(text or ""):gsub("[%c]", " ")
end

local function truncate(text, maxLen)
  text = normalizeText(text)
  maxLen = math.max(0, asInt(maxLen, 0))
  if maxLen <= 0 then return "" end
  if #text <= maxLen then return text end
  if maxLen <= 3 then
    return text:sub(1, maxLen)
  end
  return text:sub(1, maxLen - 3) .. "..."
end

local function abbreviate(text, maxLen)
  text = normalizeText(text)
  maxLen = math.max(1, asInt(maxLen, 1))
  if #text <= maxLen then return text end
  local compact = text:gsub("[%s_%-]+", "")
  if #compact <= maxLen then
    return compact
  end
  local vowelless = compact:gsub("[AEIOUaeiou]", "")
  if #vowelless >= 3 and #vowelless <= maxLen then
    return vowelless
  end
  return truncate(text, maxLen)
end

local function detectDensity(width, height)
  if width < 92 or height < 28 then
    return "small"
  end
  if width >= 150 and height >= 44 then
    return "large"
  end
  return "medium"
end

function M.build(width, height)
  local w = math.max(1, asInt(width, 1))
  local h = math.max(1, asInt(height, 1))
  local density = detectDensity(w, h)

  local baseScale = clamp(math.min(w / 120, h / 40), 0.75, 1.8)
  if density == "small" then
    baseScale = clamp(baseScale, 0.75, 0.95)
  elseif density == "large" then
    baseScale = clamp(baseScale, 1.2, 1.8)
  end

  local outerMargin = math.max(1, asInt(baseScale * 1.2, 1))
  local panelPadding = math.max(1, asInt(baseScale * 1.0, 1))
  local panelGap = math.max(1, asInt(baseScale * 1.4, 1))
  local sectionGap = math.max(1, asInt(baseScale * 1.0, 1))
  local lineSpacing = 1

  local headerHeight = (density == "large") and 3 or 2
  local footerHeight = (density == "small") and 1 or 2
  local buttonHeight = (density == "small") and 2 or 3
  local gaugeThickness = (density == "large") and 2 or 1

  return {
    width = w,
    height = h,
    density = density,
    scale = baseScale,
    palette = {
      bgRoot = colors.black,
      bgNoise = colors.gray,
      panelBg = colors.black,
      panelBgSoft = colors.blue,
      panelBgRaised = colors.gray,
      border = colors.lightBlue,
      borderStrong = colors.cyan,
      textPrimary = colors.white,
      textMuted = colors.lightGray,
      info = colors.cyan,
      ok = colors.lime,
      warning = colors.orange,
      critical = colors.red,
      accent = colors.purple,
      energy = colors.yellow,
      buttonFace = colors.gray,
      buttonActive = colors.blue,
      reactorShell = colors.lightBlue,
      reactorShellDark = colors.blue,
      reactorCoreIdle = colors.cyan,
      reactorCoreReady = colors.lime,
      reactorCoreActive = colors.orange,
      reactorCoreWarn = colors.red,
      reactorFlowT = colors.green,
      reactorFlowDT = colors.purple,
      reactorFlowD = colors.orange,
      reactorLaser = colors.yellow,
    },
    spacing = {
      outerMargin = outerMargin,
      panelPadding = panelPadding,
      panelGap = panelGap,
      sectionGap = sectionGap,
      lineSpacing = lineSpacing,
    },
    sizes = {
      headerHeight = headerHeight,
      footerHeight = footerHeight,
      panelHeaderHeight = 1,
      titleHeight = 1,
      subtitleHeight = 1,
      dataRowHeight = 1,
      gaugeThickness = gaugeThickness,
      buttonHeight = buttonHeight,
      badgeHeight = 1,
    },
    text = {
      normalize = normalizeText,
      truncate = truncate,
      abbreviate = abbreviate,
    },
    clamp = clamp,
    asInt = asInt,
  }
end

return M
