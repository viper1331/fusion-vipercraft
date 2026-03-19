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
  if width < 120 or height < 52 then
    return "small"
  end
  if width >= 240 and height >= 140 then
    return "large"
  end
  return "medium"
end

local function computeLineHeight(width, height, density)
  local nativeLike = width >= 220 and height >= 120
  if nativeLike then
    if density == "large" then
      return clamp(math.floor(height / 34), 8, 13)
    end
    return clamp(math.floor(height / 38), 6, 10)
  end
  if density == "small" then
    return 1
  end
  return 2
end

function M.build(width, height)
  local w = math.max(1, asInt(width, 1))
  local h = math.max(1, asInt(height, 1))
  local density = detectDensity(w, h)
  local lineHeight = computeLineHeight(w, h, density)
  local nativeLike = lineHeight >= 5

  local baseScale = clamp(math.min(w / 180, h / 70), 0.70, 3.00)
  if density == "small" then
    baseScale = clamp(baseScale, 0.70, 1.00)
  elseif density == "large" then
    baseScale = clamp(baseScale, 1.10, 3.00)
  end

  local unit = math.max(1, asInt(baseScale, 1))
  local outerMargin = nativeLike and clamp(math.floor(lineHeight * 0.55), 2, 8) or 1
  local panelPadding = nativeLike and clamp(math.floor(lineHeight * 0.35), 1, 4) or 1
  local panelGap = nativeLike and clamp(math.floor(lineHeight * 0.45), 2, 6) or 1
  local sectionGap = nativeLike and clamp(math.floor(lineHeight * 0.30), 1, 4) or 1

  local panelHeaderHeight = nativeLike and clamp(math.floor(lineHeight * 0.95), 6, 12) or 1
  local headerHeight = nativeLike and clamp((lineHeight * 2) + panelHeaderHeight, 18, 38) or ((density == "large") and 4 or 3)
  local footerHeight = nativeLike and clamp((lineHeight * 2) + panelHeaderHeight + 2, 20, 42) or ((density == "small") and 6 or 8)

  local buttonHeight = nativeLike and clamp(lineHeight + 2, 8, 16) or ((density == "small") and 2 or 3)
  local gaugeThickness = nativeLike and clamp(math.floor(lineHeight * 0.45), 3, 7) or 1
  local badgeHeight = nativeLike and clamp(math.floor(lineHeight * 0.65), 4, 9) or 1
  local rowPadding = nativeLike and clamp(math.floor(lineHeight * 0.18), 1, 3) or 0

  return {
    width = w,
    height = h,
    density = density,
    scale = baseScale,
    nativeLike = nativeLike,
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
      lineGap = nativeLike and math.max(1, math.floor(lineHeight * 0.20)) or 1,
      denseGap = nativeLike and math.max(1, math.floor(lineHeight * 0.10)) or 1,
      rowPadding = rowPadding,
    },
    sizes = {
      headerHeight = headerHeight,
      footerHeight = footerHeight,
      panelHeaderHeight = panelHeaderHeight,
      titleHeight = nativeLike and math.max(1, math.floor(lineHeight * 0.9)) or 1,
      subtitleHeight = nativeLike and math.max(1, math.floor(lineHeight * 0.75)) or 1,
      lineHeight = lineHeight,
      dataRowHeight = lineHeight,
      gaugeThickness = gaugeThickness,
      buttonHeight = buttonHeight,
      badgeHeight = badgeHeight,
      laserModuleHeight = nativeLike and clamp(math.floor(lineHeight * 0.9), 6, 14) or ((density == "small") and 1 or 2),
      laserModuleWidth = nativeLike and clamp(math.floor(lineHeight * 0.8), 5, 10) or 3,
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
