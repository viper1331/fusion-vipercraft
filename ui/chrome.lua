-- ui/chrome.lua
-- Rendu de la barre haute / basse (header + footer).
-- Module dedie pour sortir le code graphique de core/app.lua.

local M = {}

function M.build(api)
  local state = api.state
  local hw = api.hw
  local C = api.C
  local shortText = api.shortText
  local clamp = api.clamp
  local statusColor = api.statusColor
  local reactorPhase = api.reactorPhase
  local phaseColor = api.phaseColor
  local computeSafetyWarnings = api.computeSafetyWarnings
  local yesno = api.yesno
  local formatFuelLevel = api.formatFuelLevel
  local resolveViewName = api.resolveViewName
  local hline = api.hline
  local writeAt = api.writeAt
  local getSize = api.getSize

  -- Segment visuel marque: separateur franc sur les bords.
  local function drawSegment(x, y, w, key, value, tone, bg)
    if w < 6 then return end
    local keyText = shortText(string.upper(tostring(key or "?")), math.max(1, math.floor(w * 0.34) - 1))
    local valWidth = math.max(1, w - #keyText - 3)
    local valText = shortText(tostring(value or "N/A"), valWidth)

    hline(x, y, w, bg)
    writeAt(x, y, " ", C.text, C.border)
    if w >= 2 then
      writeAt(x + w - 1, y, " ", C.text, C.border)
    end
    writeAt(x + 1, y, keyText, C.dim, bg)
    writeAt(x + 1 + #keyText, y, " " .. valText, tone or C.text, bg)
  end

  local function computeSegmentWidths(tw, segments, minW)
    local count = #segments
    if count <= 0 then return {} end

    minW = math.max(6, tonumber(minW) or 8)
    if (minW * count) > tw then
      minW = math.max(6, math.floor(tw / count))
    end

    local minTotal = minW * count
    local extra = math.max(0, tw - minTotal)
    local weightSum = 0
    for i = 1, count do
      weightSum = weightSum + math.max(1, tonumber(segments[i].weight) or 1)
    end

    local widths = {}
    local used = 0
    for i = 1, count do
      local weight = math.max(1, tonumber(segments[i].weight) or 1)
      local add = (i == count) and 0 or math.floor((extra * weight) / weightSum)
      widths[i] = minW + add
      used = used + widths[i]
    end

    widths[count] = widths[count] + math.max(0, tw - used)
    return widths
  end

  local function drawSegmentRow(y, bg, segments, minW)
    local tw = getSize()
    local widths = computeSegmentWidths(tw, segments, minW)
    local x = 1
    for i = 1, #segments do
      local seg = segments[i]
      local w = widths[i] or 0
      if i == #segments then
        w = tw - x + 1
      end
      if w > 0 then
        drawSegment(x, y, w, seg.key, seg.value, seg.tone, bg)
      end
      x = x + w
      if x > tw then break end
    end
  end

  local function drawHeader(title, status)
    local tw = getSize()
    local phase = reactorPhase()
    local warnings, critical = computeSafetyWarnings()
    local pulse = (state.tick % 8 < 4)
    local mainAlert = status or state.alert or "INFO"
    local firstWarn = warnings[1] or "NONE"
    local sysText = "FUSION " .. resolveViewName(state.currentView or "supervision")

    if tw < 34 then
      hline(1, 1, tw, C.headerBg)
      writeAt(2, 1, shortText("SYS " .. sysText, tw - 2), C.headerText, C.headerBg)
      return
    end

    local segments
    if tw < 54 then
      segments = {
        { key = "SYS", value = sysText, tone = C.headerText, weight = 4 },
        { key = "PHS", value = shortText(phase, 14), tone = phaseColor(phase), weight = 2 },
        { key = "ALR", value = shortText(mainAlert, 14), tone = statusColor(mainAlert), weight = 2 },
      }
    else
      segments = {
        { key = "SYS", value = sysText, tone = C.headerText, weight = 4 },
        { key = "PHS", value = shortText(phase, 14), tone = phaseColor(phase), weight = 2 },
        { key = "ALR", value = shortText(mainAlert, 14), tone = statusColor(mainAlert), weight = 2 },
        {
          key = critical and "CRIT" or "INFO",
          value = shortText(firstWarn, 20),
          tone = critical and (pulse and C.bad or C.warn) or C.info,
          weight = 3,
        },
      }
    end

    drawSegmentRow(1, C.headerBg, segments, 8)
  end

  local function drawFooter()
    local tw, th = getSize()
    local phase = reactorPhase()
    local viewCode = resolveViewName(state.currentView or "supervision")
    local laserState = tostring(state.laserState or "ABSENT")
    local laserText = tostring(state.laserStatusText or laserState)
    local laserTone = C.dim
    if laserState == "READY" then
      laserTone = C.ok
    elseif laserState == "CHARGING" or laserState == "INSUFFICIENT" then
      laserTone = C.warn
    elseif laserState == "ABSENT" then
      laserTone = C.bad
    end
    local labels = {
      { key = "ACT", value = shortText(state.lastAction or "AUCUNE", 16), tone = C.text },
      { key = "VIEW", value = viewCode, tone = C.info },
      { key = "PHS", value = shortText(phase, 14), tone = phaseColor(phase) },
      { key = "LAS", value = laserText, tone = laserTone },
      { key = "GRID", value = state.energyKnown and string.format("%3.0f%%", state.energyPct) or "N/A", tone = C.energy },
      { key = "FUEL", value = "D " .. formatFuelLevel(state.deuteriumAmount) .. " T " .. formatFuelLevel(state.tritiumAmount), tone = C.fuel },
      { key = "OUT", value = shortText(tostring(hw.monitorName or "term"), 10), tone = C.info },
    }

    local compact
    if tw < 42 then
      compact = {
        { key = "PHS", value = shortText(phase, 10), tone = phaseColor(phase), weight = 2 },
        { key = "LAS", value = shortText(laserText, 10), tone = laserTone, weight = 2 },
        { key = "GRID", value = state.energyKnown and string.format("%3.0f%%", state.energyPct) or "N/A", tone = C.energy, weight = 1 },
      }
    elseif tw < 64 then
      compact = {
        { key = "ACT", value = shortText(state.lastAction or "AUCUNE", 12), tone = C.text, weight = 3 },
        { key = "VIEW", value = viewCode, tone = C.info, weight = 1 },
        { key = "PHS", value = shortText(phase, 10), tone = phaseColor(phase), weight = 2 },
        { key = "LAS", value = shortText(laserText, 10), tone = laserTone, weight = 2 },
        { key = "GRID", value = state.energyKnown and string.format("%3.0f%%", state.energyPct) or "N/A", tone = C.energy, weight = 1 },
      }
    else
      compact = {
        { key = labels[1].key, value = labels[1].value, tone = labels[1].tone, weight = 3 },
        { key = labels[2].key, value = labels[2].value, tone = labels[2].tone, weight = 1 },
        { key = labels[3].key, value = labels[3].value, tone = labels[3].tone, weight = 2 },
        { key = labels[4].key, value = labels[4].value, tone = labels[4].tone, weight = 2 },
        { key = labels[5].key, value = labels[5].value, tone = labels[5].tone, weight = 1 },
        { key = labels[6].key, value = labels[6].value, tone = labels[6].tone, weight = 2 },
        { key = labels[7].key, value = labels[7].value, tone = labels[7].tone, weight = 2 },
      }
    end

    drawSegmentRow(th, C.footerBg, compact, 8)
  end

  return {
    drawHeader = drawHeader,
    drawFooter = drawFooter,
  }
end

return M
