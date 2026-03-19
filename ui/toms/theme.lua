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

local function computeLineHeight(width, height, density, nativePreferred)
  local nativeLike = nativePreferred == true or (width >= 220 and height >= 120)
  if nativeLike then
    if density == "large" then
      return clamp(math.floor(height / 34), 8, 13)
    end
    if density == "medium" then
      return clamp(math.floor(height / 40), 6, 10)
    end
    return clamp(math.floor(height / 42), 5, 8)
  end
  if density == "small" then
    return 1
  end
  return 2
end

local function buildNativeMetrics(width, height, density, lineHeight)
  local uiScale = clamp(math.min(width / 512, height / 384), 0.72, 2.10)
  if density == "small" then
    uiScale = clamp(uiScale, 0.72, 1.00)
  elseif density == "large" then
    uiScale = clamp(uiScale, 1.10, 2.10)
  end

  local outerMarginPx = clamp(math.floor((math.min(width, height) * 0.024) + 0.5), 6, 24)
  local panelGapPx = clamp(math.floor((outerMarginPx * 0.72) + 0.5), 4, 16)
  local panelPaddingPx = clamp(math.floor((outerMarginPx * 0.55) + 0.5), 3, 12)
  local sectionGapPx = clamp(math.floor((panelGapPx * 0.72) + 0.5), 3, 12)
  local textLineGapPx = clamp(math.floor((lineHeight * 0.28) + 0.5), 1, 4)

  local headerHeightPx = clamp(math.floor((height * 0.12) + 0.5), 30, 66)
  local footerHeightPx = clamp(math.floor((height * 0.14) + 0.5), 34, 74)
  local titleHeightPx = clamp(math.floor((lineHeight * 1.10) + 0.5), 7, 16)
  local subtitleHeightPx = clamp(math.floor((lineHeight * 0.88) + 0.5), 6, 14)
  local rowHeightPx = clamp(lineHeight + textLineGapPx, 7, 18)
  local panelHeaderHeightPx = clamp(math.floor((lineHeight * 1.05) + 0.5), 6, 14)
  local buttonHeightPx = clamp(math.floor((lineHeight * 1.45) + 0.5), 9, 20)
  local gaugeThicknessPx = clamp(math.floor((lineHeight * 0.45) + 0.5), 3, 8)
  local badgeHeightPx = clamp(math.floor((lineHeight * 0.80) + 0.5), 5, 14)
  local fontCharWidthPx = clamp(math.floor((lineHeight * 0.62) + 0.5), 4, 10)
  local fontCharHeightPx = lineHeight

  return {
    nativePixels = true,
    uiScale = uiScale,
    outerMarginPx = outerMarginPx,
    panelGapPx = panelGapPx,
    panelPaddingPx = panelPaddingPx,
    sectionGapPx = sectionGapPx,
    textLineGapPx = textLineGapPx,
    titleHeightPx = titleHeightPx,
    subtitleHeightPx = subtitleHeightPx,
    rowHeightPx = rowHeightPx,
    headerHeightPx = headerHeightPx,
    footerHeightPx = footerHeightPx,
    panelHeaderHeightPx = panelHeaderHeightPx,
    buttonHeightPx = buttonHeightPx,
    gaugeThicknessPx = gaugeThicknessPx,
    badgeHeightPx = badgeHeightPx,
    fontCharWidthPx = fontCharWidthPx,
    fontCharHeightPx = fontCharHeightPx,
    laserModuleWidthPx = clamp(math.floor((lineHeight * 0.92) + 0.5), 6, 14),
    laserModuleHeightPx = clamp(math.floor((lineHeight * 0.86) + 0.5), 6, 14),
  }
end

function M.build(width, height, options)
  options = type(options) == "table" and options or {}
  local w = math.max(1, asInt(width, 1))
  local h = math.max(1, asInt(height, 1))
  local density = detectDensity(w, h)
  local backendFamily = string.lower(tostring(options.backendFamily or ""))
  local nativePreferred = backendFamily == "toms_native"
  local lineHeight = computeLineHeight(w, h, density, nativePreferred)
  local nativeLike = nativePreferred or lineHeight >= 5
  local metrics = nativeLike and buildNativeMetrics(w, h, density, lineHeight) or {
    nativePixels = false,
    uiScale = 1,
    outerMarginPx = 1,
    panelGapPx = 1,
    panelPaddingPx = 1,
    sectionGapPx = 1,
    textLineGapPx = 1,
    titleHeightPx = 1,
    subtitleHeightPx = 1,
    rowHeightPx = math.max(1, lineHeight),
    headerHeightPx = (density == "large") and 4 or 3,
    footerHeightPx = (density == "small") and 6 or 8,
    panelHeaderHeightPx = 1,
    buttonHeightPx = (density == "small") and 2 or 3,
    gaugeThicknessPx = 1,
    badgeHeightPx = 1,
    fontCharWidthPx = 1,
    fontCharHeightPx = 1,
    laserModuleWidthPx = 3,
    laserModuleHeightPx = (density == "small") and 1 or 2,
  }

  local baseScale = clamp(math.min(w / 180, h / 70), 0.70, 3.00)
  if density == "small" then
    baseScale = clamp(baseScale, 0.70, 1.00)
  elseif density == "large" then
    baseScale = clamp(baseScale, 1.10, 3.00)
  end
  if nativeLike then
    baseScale = metrics.uiScale
  end

  local unit = math.max(1, asInt(baseScale, 1))
  local outerMargin = metrics.outerMarginPx
  local panelPadding = metrics.panelPaddingPx
  local panelGap = metrics.panelGapPx
  local sectionGap = metrics.sectionGapPx
  local panelHeaderHeight = metrics.panelHeaderHeightPx
  local headerHeight = metrics.headerHeightPx
  local footerHeight = metrics.footerHeightPx
  local buttonHeight = metrics.buttonHeightPx
  local gaugeThickness = metrics.gaugeThicknessPx
  local badgeHeight = metrics.badgeHeightPx
  local rowPadding = nativeLike and clamp(math.floor(lineHeight * 0.18), 1, 3) or 0

  return {
    width = w,
    height = h,
    density = density,
    scale = baseScale,
    nativeLike = nativeLike,
    metrics = metrics,
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
      lineGap = metrics.textLineGapPx,
      denseGap = nativeLike and math.max(1, math.floor(lineHeight * 0.10)) or 1,
      rowPadding = rowPadding,
    },
    sizes = {
      headerHeight = headerHeight,
      footerHeight = footerHeight,
      panelHeaderHeight = panelHeaderHeight,
      titleHeight = metrics.titleHeightPx,
      subtitleHeight = metrics.subtitleHeightPx,
      lineHeight = lineHeight,
      dataRowHeight = metrics.rowHeightPx,
      gaugeThickness = gaugeThickness,
      buttonHeight = buttonHeight,
      badgeHeight = badgeHeight,
      laserModuleHeight = metrics.laserModuleHeightPx,
      laserModuleWidth = metrics.laserModuleWidthPx,
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
