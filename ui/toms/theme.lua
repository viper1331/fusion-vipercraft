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
  if #text <= maxLen then
    return text
  end
  local compact = text:gsub("[%s_%-_]+", "")
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
  if width < 96 or height < 32 then
    return "small"
  end
  if width >= 156 and height >= 48 then
    return "large"
  end
  return "medium"
end

function M.build(width, height)
  local w = math.max(1, asInt(width, 1))
  local h = math.max(1, asInt(height, 1))
  local density = detectDensity(w, h)

  local baseScale = clamp(math.min(w / 140, h / 44), 0.72, 2.0)
  if density == "small" then
    baseScale = clamp(baseScale, 0.72, 0.92)
  elseif density == "large" then
    baseScale = clamp(baseScale, 1.10, 2.0)
  end

  local unit = math.max(1, asInt(baseScale, 1))
  local outerMargin = math.max(1, asInt(baseScale * 1.0, 1))
  local panelPadding = math.max(1, asInt(baseScale * 0.85, 1))
  local panelGap = math.max(1, asInt(baseScale * 1.1, 1))
  local sectionGap = math.max(1, asInt(baseScale * 0.9, 1))

  local headerHeight = (density == "large") and 3 or 2
  local footerHeight = (density == "small") and 5 or ((density == "large") and 7 or 6)
  local buttonHeight = (density == "small") and 2 or 3
  local gaugeThickness = (density == "large") and 2 or 1
  local badgeHeight = (density == "small") and 1 or 2

  return {
    width = w,
    height = h,
    density = density,
    scale = baseScale,
    palette = {
      bgRoot = colors.black,
      bgBackdrop = colors.gray,
      panelBg = colors.black,
      panelBgSoft = colors.gray,
      panelBgRaised = colors.blue,
      panelHeader = colors.blue,
      panelHeaderAlt = colors.gray,
      border = colors.lightBlue,
      borderStrong = colors.cyan,
      borderSoft = colors.blue,
      textPrimary = colors.white,
      textMuted = colors.lightGray,
      textDim = colors.gray,
      info = colors.cyan,
      ok = colors.lime,
      warning = colors.orange,
      critical = colors.red,
      accent = colors.purple,
      energy = colors.yellow,
      buttonFace = colors.gray,
      buttonPrimary = colors.blue,
      buttonWarn = colors.orange,
      buttonDanger = colors.red,
      reactorShell = colors.lightBlue,
      reactorShellDark = colors.blue,
      reactorCoreIdle = colors.cyan,
      reactorCoreReady = colors.lime,
      reactorCoreActive = colors.orange,
      reactorCoreWarn = colors.red,
      reactorFlowT = colors.green,
      reactorFlowDT = colors.purple,
      reactorFlowD = colors.red,
      reactorLaser = colors.yellow,
      reactorLaserCharge = colors.lightBlue,
    },
    spacing = {
      unit = unit,
      outerMargin = outerMargin,
      panelPadding = panelPadding,
      panelGap = panelGap,
      sectionGap = sectionGap,
      lineGap = 1,
      denseGap = 1,
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
      badgeHeight = badgeHeight,
      laserModuleHeight = (density == "small") and 1 or 2,
      laserModuleWidth = 3,
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
