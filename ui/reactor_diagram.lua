-- ui/reactor_diagram.lua
-- Renderer dedie au schema top-down du reacteur.
-- Objectif: sortir la logique visuelle complexe de core/app.lua
-- pour faciliter la maintenance et les evolutions UI.

local M = {}

function M.build(api)
  local state = api.state
  local C = api.C
  local drawBox = api.drawBox
  local writeAt = api.writeAt
  local shortText = api.shortText
  local clamp = api.clamp

  -- Etat d'animation local au renderer:
  -- chaque lock (T/DT/D) declenche une animation courte lors d'un changement.
  local lockAnimUntil = { t = 0, dt = 0, d = 0 }
  local lockLastState = {
    t = state.tOpen and true or false,
    dt = state.dtOpen and true or false,
    d = state.dOpen and true or false,
  }
  local lockAnimDuration = 0.8

  -- Synchronise les transitions d'etat des vannes pour demarrer
  -- une animation visuelle au changement.
  local function syncLockAnimation(now)
    if lockLastState.t ~= state.tOpen then
      lockLastState.t = state.tOpen
      lockAnimUntil.t = now + lockAnimDuration
    end
    if lockLastState.dt ~= state.dtOpen then
      lockLastState.dt = state.dtOpen
      lockAnimUntil.dt = now + lockAnimDuration
    end
    if lockLastState.d ~= state.dOpen then
      lockLastState.d = state.dOpen
      lockAnimUntil.d = now + lockAnimDuration
    end
  end

  local function drawReactorDiagram(x, y, w, h)
    drawBox(x, y, w, h, "FUSION CHAMBER", C.border)
    if w < 30 or h < 16 then
      writeAt(x + 2, y + 2, "Schema top-down indisponible", C.dim, C.panelDark)
      return
    end

    local innerX, innerY = x + 1, y + 1
    local innerW, innerH = w - 2, h - 2
    local pulse = (state.tick % 6 < 3)
    local blink = (state.tick % 4 < 2)
    local now = os.clock()

    syncLockAnimation(now)

    local tAnimating = now < lockAnimUntil.t
    local dtAnimating = now < lockAnimUntil.dt
    local dAnimating = now < lockAnimUntil.d

    local function cellColor(base)
      if state.alert == "DANGER" then return C.bad end
      return base
    end

    -- Teintes principales du reacteur (coque / coeur).
    local structureColor = C.borderDim
    if state.reactorPresent and state.reactorFormed then
      structureColor = cellColor(C.info)
    elseif state.reactorPresent then
      structureColor = C.dim
    end

    local ringColor = state.reactorPresent and cellColor(C.border) or C.borderDim
    local spineColor = state.reactorPresent and C.info or C.borderDim
    if state.alert == "WARN" then spineColor = C.warn end

    local coreColor
    if not state.reactorPresent then
      coreColor = C.panel
    elseif state.ignition then
      -- Clignotement multicolore du coeur pendant l'ignition.
      local ignitionCycle = { colors.green, colors.red, colors.purple }
      local frame = (math.floor(state.tick / 2) % #ignitionCycle) + 1
      coreColor = ignitionCycle[frame]
    elseif state.ignitionSequencePending then
      coreColor = blink and C.warn or colors.yellow
    elseif state.reactorFormed then
      coreColor = blink and colors.cyan or C.info
    else
      coreColor = C.panel
    end
    if state.alert == "DANGER" then coreColor = pulse and C.bad or C.warn end

    -- Geometrie adaptative du schema pour rester lisible selon la resolution.
    local cellW = 2
    local maxGw = math.floor((innerW - 4) / cellW)
    local gwUpper = math.min(29, maxGw)
    local gwLower = math.min(17, gwUpper)
    local gw = clamp(math.floor(maxGw * 0.92), gwLower, gwUpper)
    if gw % 2 == 0 then gw = gw - 1 end

    local maxGh = innerH - 4
    local ghUpper = math.min(23, maxGh)
    local ghLower = math.min(15, ghUpper)
    local gh = clamp(math.floor(maxGh * 0.92), ghLower, ghUpper)
    if gh % 2 == 0 then gh = gh - 1 end

    local rx = innerX + math.floor((innerW - (gw * cellW)) / 2)
    local ryBase = innerY + math.floor((innerH - gh) / 2)
    local ry = math.min(innerY + innerH - gh, ryBase + 1)

    local gcx = math.floor((gw + 1) / 2)
    local gcy = math.floor((gh + 1) / 2)
    local outerR = clamp(math.floor(math.min(gw, gh) * 0.36), 5, 8)
    local ringR = math.max(3, outerR - 1)
    local armR = outerR + 2
    local spineR = math.max(5, outerR)
    local branchOffset = clamp(math.floor(outerR * 0.8), 4, 6)

    -- Ecrit une cellule logique (2 caracteres) dans la grille reacteur.
    local function drawCell(gx, gy, bg, ch, tc)
      if gx < 1 or gx > gw or gy < 1 or gy > gh then return end
      local sx = rx + (gx - 1) * cellW
      local sy = ry + gy - 1
      local text = ch or "  "
      if #text == 1 then text = text .. " " end
      writeAt(sx, sy, text, tc or C.text, bg)
    end

    -- Construire les couches de forme (coque, anneau, coeur).
    local layers = {}
    for gy = 1, gh do
      local row = {}
      layers[gy] = row
      for gx = 1, gw do
        local dx = math.abs(gx - gcx)
        local dy = math.abs(gy - gcy)
        local layer = 0

        if math.max(dx, dy) <= outerR then layer = 1 end
        if math.max(dx, dy) <= ringR then layer = 2 end
        if dx <= 1 and dy <= armR then layer = math.max(layer, 1) end
        if dy <= 1 and dx <= armR then layer = math.max(layer, 1) end
        if dx == 0 and dy <= (armR - 1) then layer = math.max(layer, 2) end
        if dy == 0 and dx <= (armR - 1) then layer = math.max(layer, 2) end
        if dx == outerR and dy == outerR then layer = 0 end
        if dx <= 1 and dy <= 1 then layer = 3 end

        row[gx] = layer
      end
    end

    -- Peinture de base des couches.
    for gy = 1, gh do
      for gx = 1, gw do
        local layer = layers[gy][gx]
        if layer == 1 then
          drawCell(gx, gy, structureColor)
        elseif layer == 2 then
          drawCell(gx, gy, ringColor)
        elseif layer == 3 then
          local coreGlyph = state.ignition and (pulse and "<>" or "##")
            or (state.ignitionSequencePending and (blink and "::" or "..") or "[]")
          drawCell(gx, gy, coreColor, coreGlyph, C.text)
        end
      end
    end

    local function getLayer(gx, gy)
      if gx < 1 or gx > gw or gy < 1 or gy > gh then return 0 end
      return layers[gy][gx] or 0
    end

    -- Contour du reacteur impose en noir (demande explicite UX).
    local contourColor = colors.black
    for gy = 1, gh do
      for gx = 1, gw do
        local layer = getLayer(gx, gy)
        if layer > 0 then
          if getLayer(gx - 1, gy) == 0 or getLayer(gx + 1, gy) == 0 or getLayer(gx, gy - 1) == 0 or getLayer(gx, gy + 1) == 0 then
            drawCell(gx, gy, contourColor, "[]", C.text)
          end
        end
      end
    end

    -- Croix centrale / spine.
    for i = -spineR, spineR do
      drawCell(gcx + i, gcy, spineColor)
      drawCell(gcx, gcy + i, spineColor)
    end

    -- Flux RF gauche/droite.
    local rfRunning = state.ignition and state.reactorFormed
    local rfOffset = state.tick % 4
    local rfBaseTone = rfRunning and colors.lime or C.energy
    local rfPulseTone = rfRunning and C.ok or C.energy
    for step = 2, spineR do
      local leftPulse = ((step + rfOffset) % 3 == 0)
      local rightPulse = ((step + rfOffset + 1) % 3 == 0)
      local leftGlyph = rfRunning and (leftPulse and "<<" or "::") or "--"
      local rightGlyph = rfRunning and (rightPulse and ">>" or "::") or "--"
      drawCell(gcx - step, gcy, leftPulse and rfPulseTone or rfBaseTone, leftGlyph, C.text)
      drawCell(gcx + step, gcy, rightPulse and rfPulseTone or rfBaseTone, rightGlyph, C.text)
    end

    -- Coeur + croix proche coeur.
    drawCell(gcx, gcy, coreColor, state.ignition and (pulse and "**" or "##") or (state.ignitionSequencePending and (blink and "!!" or "::") or "[]"), C.text)
    drawCell(gcx - 1, gcy, ringColor, "[]", C.text)
    drawCell(gcx + 1, gcy, ringColor, "[]", C.text)
    drawCell(gcx, gcy - 1, ringColor, "[]", C.text)
    drawCell(gcx, gcy + 1, ringColor, "[]", C.text)

    -- Lignes de flux:
    -- - D de droite en rouge (deuterium)
    -- - DT en violet
    local laserOn = state.laserChargeOn or state.laserLineOn or state.ignitionSequencePending
    local laserTone = laserOn and C.bad or C.dim
    local dFlowColor = C.bad
    local dtFlowColor = colors.purple
    local dTone = state.dOpen and dFlowColor or C.dim
    local tTone = state.tOpen and C.tritium or C.dim
    local dtTone = state.dtOpen and dtFlowColor or C.dim

    local conduitTone = C.borderDim
    if state.alert == "WARN" then conduitTone = C.warn end
    if state.alert == "DANGER" then conduitTone = C.bad end

    local laserPathTone = laserOn and C.bad or conduitTone
    local tPathTone = state.tOpen and C.tritium or conduitTone
    local dPathTone = dFlowColor
    local dtPathTone = dtFlowColor

    -- Module LAS au-dessus du coeur.
    local moduleW = clamp(math.min(gw * cellW - 2, 14), 10, 14)
    if moduleW % 2 ~= 0 then moduleW = moduleW - 1 end
    local moduleX = rx + math.floor((gw * cellW - moduleW) / 2)
    local moduleY = math.max(y + 1, ry - 3)
    local gapTop = moduleY + 1
    local gapBottom = ry - 1

    for gxCol = moduleX, moduleX + moduleW - 1 do
      writeAt(gxCol, moduleY, " ", C.text, laserOn and C.bad or C.panelMid)
    end
    local moduleLabel = laserOn and "LAS ON" or "LAS"
    writeAt(moduleX + math.floor((moduleW - #moduleLabel) / 2), moduleY, moduleLabel, laserOn and colors.white or C.dim, laserOn and C.bad or C.panelMid)

    for yLine = gapTop, gapBottom do
      writeAt(rx + (gcx - 1) * cellW, yLine, laserOn and (pulse and "!!" or "||") or "..", laserOn and colors.white or C.dim, C.panelDark)
    end

    for gyLine = 2, gcy - 2 do
      drawCell(gcx, gyLine, laserPathTone, laserOn and (pulse and "!!" or "||") or "  ", laserOn and colors.white or C.text)
    end

    -- Branches carburant vers les locks.
    local legY = math.min(gh - 1, gcy + outerR + 1)
    for gyLine = gcy + 2, legY do
      drawCell(gcx - branchOffset, gyLine, tPathTone)
      drawCell(gcx + branchOffset, gyLine, dPathTone)
    end
    for gxLine = gcx - (branchOffset - 1), gcx - 1 do
      drawCell(gxLine, gcy + 2, tPathTone)
    end
    for gxLine = gcx + 1, gcx + (branchOffset - 1) do
      drawCell(gxLine, gcy + 2, dPathTone)
    end
    drawCell(gcx, gcy + 2, dtPathTone)

    local tValveGlyph = state.tOpen and (tAnimating and (blink and "<>" or ">>") or "TT") or (tAnimating and (blink and "xx" or "x ") or "T ")
    local dValveGlyph = state.dOpen and (dAnimating and (blink and "<>" or "<<") or "DD") or (dAnimating and (blink and "xx" or " x") or "D ")
    local dtValveGlyph = state.dtOpen and (dtAnimating and (blink and "<>" or "><") or "DT") or (dtAnimating and (blink and "xx" or "::") or "  ")
    drawCell(gcx - branchOffset, legY, tPathTone, tValveGlyph, C.text)
    drawCell(gcx + branchOffset, legY, dPathTone, dValveGlyph, C.text)
    drawCell(gcx, legY - 1, dtPathTone, dtValveGlyph, C.text)

    -- Libelles d'etat (haut/bas du diagramme).
    local topY = moduleY - 1
    if topY >= y + 1 then
      local laserTxt = string.format("LAS %3.0f%%", state.laserPct)
      writeAt(rx + math.floor((gw * cellW - #laserTxt) / 2), topY, laserTxt, laserTone, C.panelDark)
    elseif moduleX + moduleW + 1 <= x + w - 2 then
      local laserTxt = string.format("%3.0f%%", state.laserPct)
      writeAt(moduleX + moduleW + 1, moduleY, laserTxt, laserTone, C.panelDark)
    end

    local bottomY = ry + gh
    if bottomY <= y + h - 2 then
      local tTxt = "T " .. (state.tOpen and "OUVERT" or "FERME")
      local dTxt = "D " .. (state.dOpen and "OUVERT" or "FERME")
      local tX = rx + 1
      local dX = rx + gw * cellW - #dTxt - 1
      if tX >= x + 2 then
        writeAt(tX, bottomY, tTxt, tTone, C.panelDark)
      end
      if dX + #dTxt <= x + w - 2 then
        writeAt(dX, bottomY, dTxt, dTone, C.panelDark)
      end

      local fuelTxt = "DT " .. (state.dtOpen and "OUVERT" or "FERME")
      writeAt(rx + math.floor((gw * cellW - #fuelTxt) / 2), bottomY - 1, fuelTxt, dtTone, C.panelDark)

      local labelY = bottomY + 1
      if labelY <= y + h - 3 then
        local leftBranchX = rx + (gcx - branchOffset - 1) * cellW
        local rightBranchX = rx + (gcx + branchOffset - 1) * cellW
        local centerBranchX = rx + (gcx - 1) * cellW
        writeAt(leftBranchX, labelY, tAnimating and (blink and "<>" or "||") or "||", tPathTone, C.panelDark)
        writeAt(centerBranchX, labelY, dtAnimating and (blink and "<>" or "||") or "||", dtPathTone, C.panelDark)
        writeAt(rightBranchX, labelY, dAnimating and (blink and "<>" or "||") or "||", dPathTone, C.panelDark)

        local lockY = labelY + 1
        if lockY <= y + h - 2 then
          local tLock = state.tOpen and " T OUVERT " or " T FERME "
          local dtLock = state.dtOpen and " DT OUVERT " or " DT FERME "
          local dLock = state.dOpen and " D OUVERT " or " D FERME "
          local tLockX = leftBranchX - math.floor((#tLock - 2) / 2)
          local dtLockX = centerBranchX - math.floor((#dtLock - 2) / 2)
          local dLockX = rightBranchX - math.floor((#dLock - 2) / 2)

          local tLockBg = state.tOpen and C.tritium or C.panelMid
          local dtLockBg = state.dtOpen and dtFlowColor or C.panelMid
          local dLockBg = state.dOpen and dFlowColor or C.panelMid
          if tAnimating then tLockBg = blink and C.warn or tLockBg end
          if dtAnimating then dtLockBg = blink and C.warn or dtLockBg end
          if dAnimating then dLockBg = blink and C.warn or dLockBg end

          writeAt(tLockX, lockY, tLock, C.text, tLockBg)
          writeAt(dtLockX, lockY, dtLock, C.text, dtLockBg)
          writeAt(dLockX, lockY, dLock, C.text, dLockBg)
        end
      end
    end

    local tdModuleY = math.min(y + h - 3, ry + gh + 1)
    if tdModuleY <= y + h - 2 then
      local tMx = rx
      local dMx = rx + gw * cellW - 6
      writeAt(tMx, tdModuleY, " TANK T", state.tOpen and C.text or C.dim, state.tOpen and C.tritium or C.panelMid)
      writeAt(dMx, tdModuleY, " TANK D", state.dOpen and C.text or C.dim, state.dOpen and dFlowColor or C.panelMid)
    end

    writeAt(
      x + 3,
      y + 2,
      shortText("CORE " .. (state.reactorPresent and (state.reactorFormed and "FORMED" or "UNFORMED") or "ABSENT"), math.max(8, math.floor(w * 0.31))),
      state.reactorPresent and C.info or C.bad,
      C.panelDark
    )
  end

  return drawReactorDiagram
end

return M
