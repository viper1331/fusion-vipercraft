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

  local function drawHeader(title, status)
    local tw = getSize()
    local phase = reactorPhase()
    local warnings, critical = computeSafetyWarnings()
    local pulse = (state.tick % 8 < 4)
    local mainAlert = status or state.alert or "INFO"
    local firstWarn = warnings[1] or "NONE"
    local sysText = "FUSION " .. resolveViewName(state.currentView or "supervision")

    if tw < 40 then
      hline(1, 1, tw, C.headerBg)
      writeAt(2, 1, shortText("SYS " .. sysText, tw - 2), C.headerText, C.headerBg)
      return
    end

    local segments = {
      { key = "SYS", value = sysText, tone = C.headerText },
      { key = "PHS", value = shortText(phase, 14), tone = phaseColor(phase) },
      { key = "ALR", value = shortText(mainAlert, 14), tone = statusColor(mainAlert) },
      {
        key = critical and "CRIT" or "INFO",
        value = shortText(firstWarn, 20),
        tone = critical and (pulse and C.bad or C.warn) or C.info,
      },
    }

    local widths = {
      clamp(math.floor(tw * 0.35), 14, tw - 28),
      clamp(math.floor(tw * 0.18), 10, tw - 22),
      clamp(math.floor(tw * 0.19), 10, tw - 16),
    }
    local used = widths[1] + widths[2] + widths[3]
    widths[4] = math.max(10, tw - used)

    local x = 1
    for i, seg in ipairs(segments) do
      local w = (i == #segments) and (tw - x + 1) or widths[i]
      drawSegment(x, 1, w, seg.key, seg.value, seg.tone, C.headerBg)
      x = x + w
    end
  end

  local function drawFooter()
    local tw, th = getSize()
    local phase = reactorPhase()
    local viewCode = resolveViewName(state.currentView or "supervision")
    local labels = {
      { key = "ACT", value = shortText(state.lastAction or "AUCUNE", 16), tone = C.text },
      { key = "VIEW", value = viewCode, tone = C.info },
      { key = "PHS", value = shortText(phase, 14), tone = phaseColor(phase) },
      { key = "LAS", value = yesno(state.laserLineOn), tone = state.laserLineOn and C.warn or C.dim },
      { key = "GRID", value = state.energyKnown and string.format("%3.0f%%", state.energyPct) or "N/A", tone = C.energy },
      { key = "FUEL", value = "D " .. formatFuelLevel(state.deuteriumAmount) .. " T " .. formatFuelLevel(state.tritiumAmount), tone = C.fuel },
      { key = "OUT", value = shortText(tostring(hw.monitorName or "term"), 10), tone = C.info },
    }

    local segCount = #labels
    local baseW = math.max(9, math.floor(tw / segCount))
    local x = 1
    for i, seg in ipairs(labels) do
      local w = (i == segCount) and (tw - x + 1) or baseW
      drawSegment(x, th, w, seg.key, seg.value, seg.tone, C.footerBg)
      x = x + w
    end
  end

  return {
    drawHeader = drawHeader,
    drawFooter = drawFooter,
  }
end

return M
