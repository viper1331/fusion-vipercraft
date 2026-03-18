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
    local maxY = y + h - 2
    local infoX = clamp(geo.infoX, x + 2, x + w - 2)
    local infoW = math.max(8, (x + w - 2) - infoX + 1)

    writeAt(x + 2, y + 1, shortText(string.format("STATE %s", status), w - 4), tone, C.panelDark)
    local rows = {
      { text = string.format("FILL  %5.1f%%", state.inductionPct), tone = C.energy },
      { text = string.format("STORED %s", formatEnergy(state.inductionEnergy)), tone = C.text },
      { text = string.format("MAX    %s", formatEnergy(state.inductionMax)), tone = C.dim },
      { text = string.format("NEEDED %s", formatEnergy(state.inductionNeeded)), tone = C.dim },
      { text = string.format("IN   %s", formatEnergyPerTick(state.inductionInput)), tone = C.ok },
      { text = string.format("OUT  %s", formatEnergyPerTick(state.inductionOutput)), tone = C.warn },
      { text = string.format("CAP  %s", formatEnergyPerTick(state.inductionTransferCap)), tone = C.info },
      { text = string.format("PORT %s", state.inductionPortMode), tone = C.info },
      { text = string.format("CELLS %d", state.inductionCells), tone = C.info },
      { text = string.format("PROV  %d", state.inductionProviders), tone = C.info },
      { text = string.format("DIM %dx%dx%d", state.inductionLength, state.inductionWidth, state.inductionHeight), tone = C.text },
    }
    local rowY = geo.sy + 1
    for i = 1, #rows do
      if rowY > maxY then break end
      local row = rows[i]
      writeAt(infoX, rowY, shortText(row.text, infoW), row.tone, C.panelDark)
      rowY = rowY + 1
    end
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

  local function drawCompactInductionDiagram(x, y, w, h, status, tone)
    drawBox(x, y, w, h, "INDUCTION MATRIX", C.border)
    if w < 20 or h < 8 then
      writeAt(x + 2, y + 2, shortText("Matrix UI too small", math.max(1, w - 4)), C.dim, C.panelDark)
      return
    end

    local innerX = x + 2
    local innerY = y + 2
    local innerW = math.max(10, w - 4)
    local barW = math.max(6, innerW - 2)
    local fill = clamp(math.floor((barW * getInductionFillRatio()) + 0.5), 0, barW)

    writeAt(innerX, innerY - 1, shortText("STATE " .. tostring(status), innerW), tone, C.panelDark)
    writeAt(innerX, innerY, "[" .. string.rep("#", fill) .. string.rep("-", barW - fill) .. "]", C.energy, C.panelDark)

    local rows = {
      "FILL " .. string.format("%5.1f%%", state.inductionPct),
      "E " .. formatEnergy(state.inductionEnergy),
      "IN " .. formatEnergyPerTick(state.inductionInput),
      "OUT " .. formatEnergyPerTick(state.inductionOutput),
      "PORT " .. tostring(state.inductionPortMode or "N/A"),
    }
    local rowY = innerY + 2
    for i = 1, #rows do
      if rowY > y + h - 2 then break end
      writeAt(innerX, rowY, shortText(rows[i], innerW), C.text, C.panelDark)
      rowY = rowY + 1
    end
  end

  return function(x, y, w, h)
    local status, tone = inductionStatus()
    if w < 34 or h < 16 then
      drawCompactInductionDiagram(x, y, w, h, status, tone)
      return
    end

    drawBox(x, y, w, h, "INDUCTION MATRIX", C.border)
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
