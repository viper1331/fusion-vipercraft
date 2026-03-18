-- ui/induction_diagram.lua
-- Renderer dedie au schema induction matrix.
-- Permet de garder core/app.lua concentre sur l'orchestration.

local M = {}

function M.build(api)
  local state = api.state
  local C = api.C
  local drawBox = api.drawBox
  local writeAt = api.writeAt
  local fillArea = api.fillArea
  local shortText = api.shortText
  local clamp = api.clamp
  local inductionStatus = api.inductionStatus
  local getInductionFillRatio = api.getInductionFillRatio
  local formatEnergy = api.formatEnergy
  local formatEnergyPerTick = api.formatEnergyPerTick

  local function inductionFillTone(status, pulse)
    if status == "CHARGING" then return pulse and C.info or C.energy end
    if status == "DISCHARGING" then return pulse and C.warn or C.energy end
    if status == "LOW" or status == "EMPTY" then return pulse and C.bad or C.warn end
    if status == "FULL" then return pulse and C.ok or C.info end
    return C.energy
  end

  local function inductionDiagramGeometry(x, y, w, h)
    local geo = {
      ix = x + 2,
      iy = y + 2,
      iw = w - 4,
      ih = h - 4,
      gapRight = 4,
    }

    local infoMinW = 22
    local profileMaxW = math.max(12, geo.iw - infoMinW - geo.gapRight - 2)
    geo.profileW = clamp(math.floor(geo.iw * 0.52), 12, profileMaxW)
    geo.profileH = clamp(math.floor(geo.ih * 0.78), 8, geo.ih - 3)

    local dimsKnown = state.inductionLength > 0 and state.inductionWidth > 0 and state.inductionHeight > 0
    if dimsKnown then
      local footprint = clamp((state.inductionLength + state.inductionWidth) / 2, 3, 18)
      local maxFootprint = math.max(footprint, state.inductionHeight, 3)
      local footprintRatio = clamp(footprint / maxFootprint, 0.35, 1.0)
      local verticalRatio = clamp(state.inductionHeight / maxFootprint, 0.35, 1.0)
      geo.profileW = clamp(math.floor(profileMaxW * (0.30 + footprintRatio * 0.55)), 12, profileMaxW)
      geo.profileH = clamp(math.floor((geo.ih - 3) * (0.40 + verticalRatio * 0.46)), 8, geo.ih - 3)
    end

    geo.sx = geo.ix + 2
    geo.sy = geo.iy + math.floor((geo.ih - geo.profileH) / 2)
    geo.ex = geo.sx + geo.profileW - 1
    geo.ey = geo.sy + geo.profileH - 1
    geo.capDepth = clamp(math.floor(geo.profileW * 0.20), 2, 6)
    geo.fillRows = clamp(math.floor(getInductionFillRatio() * (geo.profileH - 2) + 0.5), 0, geo.profileH - 2)
    geo.infoX = geo.ix + geo.profileW + geo.capDepth + geo.gapRight
    return geo
  end

  local function drawInductionProfileBase(geo)
    fillArea(geo.ix, geo.iy, geo.iw, geo.ih, C.panelDark)
    drawBox(geo.sx - 1, geo.sy - 1, geo.profileW + geo.capDepth + 2, geo.profileH + 2, "SIDE PROFILE", C.borderDim)

    for yy = geo.sy, geo.ey do
      local depthDiv = math.max(1, geo.profileH / math.max(1, geo.capDepth))
      local rowDepth = clamp(geo.capDepth - math.floor((yy - geo.sy) / depthDiv), 0, geo.capDepth)
      writeAt(geo.sx, yy, string.rep(" ", geo.profileW), C.text, C.panel)
      if rowDepth > 0 then
        writeAt(geo.ex + 1, yy, string.rep(" ", rowDepth), C.text, C.panelMid)
      end
    end
  end

  local function drawInductionProfileFill(geo, status, pulse, fillTone)
    local waveOffset = (status == "CHARGING" and pulse) and 1 or 0
    for i = 0, geo.fillRows - 1 do
      local yy = geo.ey - 1 - i
      local waveCut = ((state.tick + yy) % 5 == 0) and waveOffset or 0
      local fillWidth = clamp(geo.profileW - 2 - waveCut, 1, geo.profileW - 2)
      writeAt(geo.sx + 1, yy, string.rep(" ", fillWidth), C.text, fillTone)
      if fillWidth < (geo.profileW - 2) then
        writeAt(geo.sx + 1 + fillWidth, yy, string.rep(" ", (geo.profileW - 2) - fillWidth), C.text, C.panel)
      end
    end

    local levelY = geo.ey - geo.fillRows
    if geo.fillRows > 0 and levelY >= geo.sy + 1 and levelY <= geo.ey - 1 then
      writeAt(geo.sx + 1, levelY, string.rep(" ", geo.profileW - 2), C.text, pulse and C.info or fillTone)
    end
  end

  local function drawInductionProfileDecor(geo, status)
    local cellDensity = clamp(math.floor((math.max(1, state.inductionCells) + 3) / 4), 1, 8)
    for i = 0, cellDensity - 1 do
      local yy = geo.sy + math.floor((i + 1) * geo.profileH / (cellDensity + 1))
      writeAt(geo.sx + 1, yy, string.rep(" ", math.max(1, geo.profileW - 2)), C.text, C.borderDim)
    end

    local providerColor = status == "DISCHARGING" and C.warn or C.info
    local providerDensity = clamp(math.max(1, state.inductionProviders), 1, 6)
    for i = 0, providerDensity - 1 do
      local py = geo.sy + math.floor((i + 1) * geo.profileH / (providerDensity + 1))
      writeAt(geo.sx - 3, py, "  ", C.text, providerColor)
      writeAt(geo.ex + geo.capDepth + 2, py, "  ", C.text, providerColor)
    end
  end

  local function drawInductionDiagramInfo(x, y, w, h, geo, status, tone)
    writeAt(x + 2, y + 1, string.format("STATE %s", status), tone, C.panelDark)
    writeAt(geo.infoX, geo.sy + 1, string.format("FILL  %5.1f%%", state.inductionPct), C.energy, C.panelDark)
    writeAt(geo.infoX, geo.sy + 2, string.format("STORED %s", formatEnergy(state.inductionEnergy)), C.text, C.panelDark)
    writeAt(geo.infoX, geo.sy + 3, string.format("MAX    %s", formatEnergy(state.inductionMax)), C.dim, C.panelDark)
    writeAt(geo.infoX, geo.sy + 4, string.format("NEEDED %s", formatEnergy(state.inductionNeeded)), C.dim, C.panelDark)
    writeAt(geo.infoX, geo.sy + 6, string.format("IN   %s", formatEnergyPerTick(state.inductionInput)), C.ok, C.panelDark)
    writeAt(geo.infoX, geo.sy + 7, string.format("OUT  %s", formatEnergyPerTick(state.inductionOutput)), C.warn, C.panelDark)
    writeAt(geo.infoX, geo.sy + 8, string.format("CAP  %s", formatEnergyPerTick(state.inductionTransferCap)), C.info, C.panelDark)
    writeAt(geo.infoX, geo.sy + 9, string.format("PORT  %s", state.inductionPortMode), C.info, C.panelDark)
    writeAt(geo.infoX, geo.sy + 10, string.format("CELLS %d", state.inductionCells), C.info, C.panelDark)
    writeAt(geo.infoX, geo.sy + 11, string.format("PROV  %d", state.inductionProviders), C.info, C.panelDark)
    writeAt(geo.infoX, geo.sy + 12, string.format("DIM   %dx%dx%d", state.inductionLength, state.inductionWidth, state.inductionHeight), C.text, C.panelDark)
    writeAt(
      x + 2,
      y + h - 2,
      shortText(
        string.format("CELLS %d | PROVIDERS %d | %dx%dx%d", state.inductionCells, state.inductionProviders, state.inductionLength, state.inductionWidth, state.inductionHeight),
        w - 4
      ),
      C.dim,
      C.panelDark
    )
  end

  return function(x, y, w, h)
    drawBox(x, y, w, h, "INDUCTION MATRIX", C.border)
    if w < 34 or h < 16 then
      writeAt(x + 2, y + 2, "Schema matrix indisponible", C.dim, C.panelDark)
      return
    end

    local status, tone = inductionStatus()
    local geo = inductionDiagramGeometry(x, y, w, h)
    local pulse = (state.tick % 6 < 3)
    local fillTone = inductionFillTone(status, pulse)

    drawInductionProfileBase(geo)
    drawInductionProfileFill(geo, status, pulse, fillTone)
    drawInductionProfileDecor(geo, status)
    drawInductionDiagramInfo(x, y, w, h, geo, status, tone)
  end
end

return M
