-- ui/reactor_diagram.lua
-- Renderer dedie au schema top-down du reacteur.
-- Objectif: sortir la logique visuelle complexe de core/app.lua
-- pour faciliter la maintenance et les evolutions UI.

local M = {}

function M.build(api)
  local state = api.state
  local CFG = api.CFG or {}
  local C = api.C
  local drawBox = api.drawBox
  local writeAt = api.writeAt
  local shortText = api.shortText
  local clamp = api.clamp
  local formatTemperature = type(api.formatTemperature) == "function"
    and api.formatTemperature
    or function(value, opts)
      opts = type(opts) == "table" and opts or {}
      local decimals = tonumber(opts.decimals)
      if decimals == nil then decimals = 2 end
      return string.format("%." .. tostring(math.max(0, decimals)) .. "f C", tonumber(value) or 0)
    end

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

  local function drawCompactReactorDiagram(x, y, w, h)
    drawBox(x, y, w, h, "FUSION CHAMBER", C.border)
    if w < 20 or h < 9 then
      writeAt(x + 2, y + 2, shortText("Reactor UI too small", math.max(1, w - 4)), C.dim, C.panelDark)
      return
    end

    local pulse = (state.tick % 6 < 3)
    local blink = (state.tick % 4 < 2)
    local laserState = tostring(state.laserState or "ABSENT")
    local laserTone = C.dim
    if laserState == "READY" then
      laserTone = C.ok
    elseif laserState == "CHARGING" or laserState == "INSUFFICIENT" then
      laserTone = C.warn
    elseif laserState == "ABSENT" then
      laserTone = C.bad
    end

    local statusLabel = state.reactorPresent and (state.reactorFormed and "FORMED" or "UNFORMED") or "ABSENT"
    writeAt(x + 2, y + 1, shortText("CORE " .. statusLabel, w - 4), state.reactorPresent and C.info or C.bad, C.panelDark)
    if h >= 10 then
      writeAt(x + 2, y + 2, shortText("LAS " .. laserState, w - 4), laserTone, C.panelDark)
    end

    local bodyW = clamp(math.floor(w * 0.44), 10, math.max(10, w - 6))
    local bodyH = clamp(math.floor(h * 0.45), 5, math.max(5, h - 6))
    local bodyX = x + math.floor((w - bodyW) / 2)
    local bodyY = y + math.floor((h - bodyH) / 2)
    local shell = state.reactorPresent and C.info or C.panelMid
    for yy = bodyY, bodyY + bodyH - 1 do
      writeAt(bodyX, yy, string.rep(" ", bodyW), C.text, shell)
    end
    writeAt(bodyX, bodyY, string.rep(" ", bodyW), C.text, colors.black)
    writeAt(bodyX, bodyY + bodyH - 1, string.rep(" ", bodyW), C.text, colors.black)
    for yy = bodyY + 1, bodyY + bodyH - 2 do
      writeAt(bodyX, yy, " ", C.text, colors.black)
      writeAt(bodyX + bodyW - 1, yy, " ", C.text, colors.black)
    end

    local coreX = bodyX + math.floor(bodyW / 2) - 1
    local coreY = bodyY + math.floor(bodyH / 2)
    local coreColor = state.ignition and (pulse and colors.red or colors.green) or (blink and colors.purple or colors.cyan)
    writeAt(coreX, coreY, pulse and "##" or "[]", C.text, coreColor)

    if h >= 12 then
      local tLabel = "T " .. (state.tOpen and "ON" or "OFF")
      local dtLabel = "DT " .. (state.dtOpen and "ON" or "OFF")
      local dLabel = "D " .. (state.dOpen and "ON" or "OFF")
      writeAt(x + 2, y + h - 3, shortText(tLabel, 8), state.tOpen and C.tritium or C.dim, C.panelDark)
      writeAt(x + math.floor((w - #dtLabel) / 2), y + h - 3, dtLabel, state.dtOpen and C.dtFuel or C.dim, C.panelDark)
      writeAt(x + w - #dLabel - 2, y + h - 3, dLabel, state.dOpen and C.bad or C.dim, C.panelDark)
    end

    if h >= 13 then
      local plas = formatTemperature(state.plasmaTemp, { compact = true, decimals = 1 })
      local struct = formatTemperature(state.caseTemp, { compact = true, decimals = 1 })
      writeAt(x + 2, y + h - 2, shortText("P " .. tostring(plas), math.max(8, math.floor((w - 4) / 2))), C.warn, C.panelDark)
      writeAt(x + math.floor(w / 2), y + h - 2, shortText("S " .. tostring(struct), math.max(8, math.floor((w - 4) / 2))), C.bad, C.panelDark)
    end
  end

  local function drawReactorDiagram(x, y, w, h)
    if w < 30 or h < 16 then
      drawCompactReactorDiagram(x, y, w, h)
      return
    end
    drawBox(x, y, w, h, "FUSION CHAMBER", C.border)

    local innerX, innerY = x + 1, y + 1
    local innerW, innerH = w - 2, h - 2
    local pulse = (state.tick % 6 < 3)
    local blink = (state.tick % 4 < 2)
    local now = os.clock()

    syncLockAnimation(now)

    local tAnimating = now < lockAnimUntil.t
    local dtAnimating = now < lockAnimUntil.dt
    local dAnimating = now < lockAnimUntil.d
    local laserState = tostring(state.laserState or "ABSENT")
    local configuredLaserCount = math.max(1, math.floor(tonumber(CFG.laserCount) or 1))
    local detectedLaserCount = math.max(0, math.floor(tonumber(state.laserDetectedCount) or 0))
    local displayedLaserCount = configuredLaserCount

    local laserStateTone = C.dim
    if laserState == "READY" then
      laserStateTone = C.ok
    elseif laserState == "CHARGING" or laserState == "INSUFFICIENT" then
      laserStateTone = C.warn
    elseif laserState == "ABSENT" then
      laserStateTone = C.bad
    end

    local function cellColor(base)
      if state.alert == "DANGER" then return C.bad end
      return base
    end

    -- Ecriture d'un pixel de repere. Si le point tombe sur la grille reacteur,
    -- le fond actuel est conserve pour ne pas casser les couleurs de cuve/coeur.
    local writeGuidePixel = function(xx, yy, ch, tone)
      local xa = math.floor(xx)
      local ya = math.floor(yy)
      if xa >= x + 2 and xa <= x + w - 2 and ya >= y + 1 and ya <= y + h - 2 then
        writeAt(xa, ya, ch, tone, C.panelDark)
      end
    end

    local function drawGuideH(x1, x2, yy, tone)
      local ya = math.floor(yy)
      if ya < y + 1 or ya > y + h - 2 then return end
      local xa = math.floor(math.min(x1, x2))
      local xb = math.floor(math.max(x1, x2))
      for xx = xa, xb do
        if xx >= x + 2 and xx <= x + w - 2 then
          writeGuidePixel(xx, ya, "-", tone)
        end
      end
    end

    local function drawGuideV(xx, y1, y2, tone)
      local xa = math.floor(xx)
      if xa < x + 2 or xa > x + w - 2 then return end
      local ya = math.floor(math.min(y1, y2))
      local yb = math.floor(math.max(y1, y2))
      for yy = ya, yb do
        if yy >= y + 1 and yy <= y + h - 2 then
          writeGuidePixel(xa, yy, "|", tone)
        end
      end
    end

    local function drawGuideCorner(xx, yy, tone)
      local xa = math.floor(xx)
      local ya = math.floor(yy)
      if xa >= x + 2 and xa <= x + w - 2 and ya >= y + 1 and ya <= y + h - 2 then
        writeGuidePixel(xa, ya, "+", tone)
      end
    end

    local function drawGuideEnd(xx, yy, tone, glyph)
      local xa = math.floor(xx)
      local ya = math.floor(yy)
      if xa >= x + 2 and xa <= x + w - 2 and ya >= y + 1 and ya <= y + h - 2 then
        writeGuidePixel(xa, ya, glyph or "+", tone)
      end
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
    -- On garde aussi la couleur de fond pour les overlays (repères thermiques).
    local gridBg = {}
    local function drawCell(gx, gy, bg, ch, tc)
      if gx < 1 or gx > gw or gy < 1 or gy > gh then return end
      local sx = rx + (gx - 1) * cellW
      local sy = ry + gy - 1
      local text = ch or "  "
      if #text == 1 then text = text .. " " end
      if not gridBg[gy] then gridBg[gy] = {} end
      gridBg[gy][gx] = bg
      writeAt(sx, sy, text, tc or C.text, bg)
    end

    writeGuidePixel = function(xx, yy, ch, tone)
      local xa = math.floor(xx)
      local ya = math.floor(yy)
      if xa < x + 2 or xa > x + w - 2 or ya < y + 1 or ya > y + h - 2 then return end

      local gx = math.floor((xa - rx) / cellW) + 1
      local gy = (ya - ry) + 1
      local bg = C.panelDark
      if gx >= 1 and gx <= gw and gy >= 1 and gy <= gh and gridBg[gy] and gridBg[gy][gx] then
        bg = gridBg[gy][gx]
      end
      writeAt(xa, ya, ch, tone, bg)
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

    local function isContourCell(gx, gy)
      local layer = getLayer(gx, gy)
      if layer <= 0 then return false end
      return getLayer(gx - 1, gy) == 0
        or getLayer(gx + 1, gy) == 0
        or getLayer(gx, gy - 1) == 0
        or getLayer(gx, gy + 1) == 0
    end

    -- Contour du reacteur impose en noir (demande explicite UX).
    local contourColor = colors.black
    for gy = 1, gh do
      for gx = 1, gw do
        if isContourCell(gx, gy) then
          drawCell(gx, gy, contourColor, "[]", C.text)
        end
      end
    end

    local function findContourAnchor(side)
      local centerX = rx + (gcx - 1) * cellW + 1
      local bestX, bestY = nil, nil
      for gy = 1, gh do
        for gx = 1, gw do
          if isContourCell(gx, gy) then
            local sx = rx + (gx - 1) * cellW + 1
            local sy = ry + gy - 1
            local candidate = (side == "left" and sx < centerX) or (side == "right" and sx > centerX)
            if candidate then
              local betterY = (bestY == nil) or (sy < bestY)
              local betterX = (sy == bestY) and (
                (side == "left" and (bestX == nil or sx < bestX))
                or (side == "right" and (bestX == nil or sx > bestX))
              )
              if betterY or betterX then
                bestX, bestY = sx, sy
              end
            end
          end
        end
      end
      return bestX, bestY
    end

    -- Spine horizontal structurel.
    for i = -spineR, spineR do
      drawCell(gcx + i, gcy, spineColor)
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
    local hohlraumPresent = state.hohlraumPresent == true
    local hohlGlyph = hohlraumPresent and "H+" or "H-"
    local coreCenterGlyph = hohlGlyph
    if state.ignition then
      coreCenterGlyph = pulse and hohlGlyph or "**"
    elseif state.ignitionSequencePending then
      coreCenterGlyph = blink and hohlGlyph or "::"
    end
    local hohlTone = hohlraumPresent and C.ok or C.bad
    local function redrawCoreCluster()
      -- Motif coeur 3x3 (capture cible): alternance cyan/violet
      -- + noyau anime, redessine en dernier pour rester lisible.
      local violetTone = state.reactorPresent and (pulse and colors.purple or C.dtFuel) or C.panelMid
      local cyanTone = state.reactorPresent and (blink and C.info or colors.cyan) or C.panel
      local swapGlyph = (math.floor(state.tick / 2) % 2) == 1
      local shellGlyph = swapGlyph and "[]" or "##"
      local nodeGlyph = swapGlyph and "##" or "[]"

      for dy = -1, 1 do
        for dx = -1, 1 do
          if dx == 0 and dy == 0 then
            drawCell(gcx, gcy, coreColor, coreCenterGlyph, hohlTone)
          else
            local checker = ((dx + dy) % 2 == 0)
            local bg = checker and violetTone or cyanTone
            local glyph = checker and shellGlyph or nodeGlyph
            drawCell(gcx + dx, gcy + dy, bg, glyph, C.text)
          end
        end
      end
    end
    redrawCoreCluster()

    -- Lignes de flux:
    -- - D a droite rouge quand ouvert, orange quand ferme
    -- - DT violet quand ouvert, orange quand ferme
    -- Les 3 flux sont separes jusqu'au coeur.
    local lastPulseAt = tonumber(state.lastLaserPulseAt or -1)
    local laserPulseActive = lastPulseAt > 0 and (now - lastPulseAt) <= 0.7
    local laserBeamActive = (state.laserLineOn == true) or laserPulseActive
    local laserChargingAnim = laserState == "CHARGING"
    local laserReady = laserState == "READY"
    local laserTone = laserStateTone
    local closedFuelColor = C.warn
    local dFlowColor = state.dOpen and C.bad or closedFuelColor
    local dtFlowColor = state.dtOpen and colors.purple or closedFuelColor
    local dTone = state.dOpen and dFlowColor or C.dim
    local tTone = state.tOpen and C.tritium or C.dim
    local dtTone = state.dtOpen and dtFlowColor or C.dim

    local conduitTone = C.borderDim
    if state.alert == "WARN" then conduitTone = C.warn end
    if state.alert == "DANGER" then conduitTone = C.bad end

    local laserPathTone = laserBeamActive and C.bad or conduitTone
    local tPathTone = state.tOpen and C.tritium or closedFuelColor
    local dPathTone = dFlowColor
    local dtPathTone = dtFlowColor

    -- Zone LAS:
    -- 1) ligne d'information en haut
    -- 2) bloc laser (cartouche + modules) juste en dessous
    -- 3) reacteur ensuite
    local moduleW = clamp(math.min(gw * cellW - 2, 14), 10, 14)
    if moduleW % 2 ~= 0 then moduleW = moduleW - 1 end
    local beamX = rx + (gcx - 1) * cellW
    local moduleX = clamp(beamX - math.floor(moduleW / 2) + 1, x + 2, x + w - moduleW - 1)
    -- Hierarchie visuelle LAS forcee:
    -- niveau 1 (info) en haut, niveau 2 (bloc laser) juste dessous.
    local infoY = clamp(ry - 11, y + 1, ry - 7)
    local moduleY = clamp(infoY + 2, y + 3, ry - 4)
    local gapTop = moduleY + 1
    local gapBottom = ry - 1
    local moduleBg = C.panelMid
    local moduleFg = C.dim
    local moduleLabel = "LAS IDLE"

    if laserState == "ABSENT" then
      moduleBg = C.bad
      moduleFg = colors.white
      moduleLabel = "LAS ABS"
    elseif laserBeamActive then
      moduleBg = C.bad
      moduleFg = colors.white
      moduleLabel = "LAS FIRE"
    elseif laserChargingAnim then
      moduleBg = blink and C.warn or C.panelMid
      moduleFg = blink and colors.white or C.warn
      moduleLabel = pulse and "LAS CHG" or "CHG LAS"
    elseif laserReady then
      moduleBg = C.ok
      moduleFg = colors.white
      moduleLabel = "LAS READY"
    elseif laserState == "INSUFFICIENT" then
      moduleBg = C.warn
      moduleFg = C.text
      moduleLabel = "LAS LOW"
    end

    for gxCol = moduleX, moduleX + moduleW - 1 do
      writeAt(gxCol, moduleY, " ", C.text, moduleBg)
    end
    writeAt(moduleX + math.floor((moduleW - #moduleLabel) / 2), moduleY, moduleLabel, moduleFg, moduleBg)

    -- Representation LAS: 1 petit module = 1 laser.
    -- Les modules sont empiles verticalement (plus d'alignement horizontal).
    -- Pile LAS centree sur l'axe du reacteur pour eviter l'effet "decale a gauche".
    local stackX = clamp(beamX, x + 2, x + w - 3)

    local stackCount = math.max(1, math.floor(tonumber(displayedLaserCount) or 1))
    -- La pile de modules appartient visuellement au bloc LAS et reste
    -- sous la ligne d'information pour conserver une separation nette.
    local stackMinY = math.max(y + 2, infoY + 1)
    local stackMaxY = math.min(y + h - 3, ry - 2)
    if stackMaxY < stackMinY then stackMaxY = stackMinY end
    local stackCapacity = math.max(1, stackMaxY - stackMinY + 1)
    local visibleStackCount = math.min(stackCount, stackCapacity)
    local hiddenStackCount = math.max(0, stackCount - visibleStackCount)
    local stackStartY = math.max(stackMinY, moduleY + 1)
    if stackStartY + visibleStackCount - 1 > stackMaxY then
      stackStartY = stackMaxY - visibleStackCount + 1
    end
    if stackStartY < stackMinY then stackStartY = stackMinY end

    for i = 0, visibleStackCount - 1 do
      local active = laserBeamActive
        or laserReady
        or (laserChargingAnim and (((state.tick + i) % 3) == 0))
      local cellBg = C.panelMid
      local cellFg = colors.black
      if laserState == "ABSENT" then
        cellBg = C.bad
        cellFg = colors.white
      elseif laserBeamActive then
        cellBg = C.bad
        cellFg = colors.white
      elseif active then
        cellBg = laserReady and C.ok or C.warn
      elseif laserState == "INSUFFICIENT" then
        cellBg = C.warn
        cellFg = C.text
      end
      writeAt(stackX, stackStartY + i, "[]", cellFg, cellBg)
    end

    if hiddenStackCount > 0 and stackStartY > (y + 1) then
      writeAt(stackX, stackStartY - 1, "+" .. tostring(hiddenStackCount), C.dim, C.panelDark)
    end

    if laserBeamActive then
      for yLine = gapTop, gapBottom do
        writeAt(beamX, yLine, pulse and "!!" or "||", colors.white, C.panelDark)
      end

      for gyLine = 2, gcy - 2 do
        drawCell(gcx, gyLine, laserPathTone, pulse and "!!" or "||", colors.white)
      end
    else
      for yLine = gapTop, gapBottom do
        writeAt(beamX, yLine, "  ", C.text, C.panelDark)
      end
      for gyLine = 2, gcy - 2 do
        drawCell(gcx, gyLine, conduitTone, "  ", C.text)
      end
      if laserChargingAnim and gapBottom >= gapTop then
        local travel = (gapBottom - gapTop) + 1
        local yAnim = gapTop + (state.tick % travel)
        for yLine = gapTop, gapBottom do
          writeAt(beamX, yLine, pulse and "::" or "..", C.dim, C.panelDark)
        end
        writeAt(beamX, yAnim, pulse and "##" or "[]", C.warn, C.panelDark)

        local beamTravel = math.max(1, (gcy - 2) - 2 + 1)
        local gyAnim = 2 + (state.tick % beamTravel)
        for gyLine = 2, gcy - 2 do
          local beamBg = ((state.tick + gyLine) % 2 == 0) and C.panelMid or conduitTone
          drawCell(gcx, gyLine, beamBg, "..", C.warn)
        end
        drawCell(gcx, gyAnim, C.warn, pulse and "<>" or "##", colors.white)
      end
    end

    -- Branches carburant vers les locks.
    -- Trajets independants: T, DT et D arrivent separement au coeur.
    local legY = math.min(gh - 1, gcy + outerR + 1)
    local splitY = math.min(gh - 2, gcy + 3)

    -- Montantes principales depuis les vannes.
    for gyLine = splitY, legY do
      drawCell(gcx - branchOffset, gyLine, tPathTone)
      drawCell(gcx, gyLine, dtPathTone)
      drawCell(gcx + branchOffset, gyLine, dPathTone)
    end

    -- Branche T vers entree gauche du coeur.
    for gxLine = gcx - branchOffset + 1, gcx - 2 do
      drawCell(gxLine, splitY, tPathTone)
    end
    for gyLine = splitY - 1, gcy + 1, -1 do
      drawCell(gcx - 2, gyLine, tPathTone)
    end
    drawCell(gcx - 1, gcy + 1, tPathTone)

    -- Branche D vers entree droite du coeur.
    for gxLine = gcx + 2, gcx + branchOffset - 1 do
      drawCell(gxLine, splitY, dPathTone)
    end
    for gyLine = splitY - 1, gcy + 1, -1 do
      drawCell(gcx + 2, gyLine, dPathTone)
    end
    drawCell(gcx + 1, gcy + 1, dPathTone)

    -- Branche DT vers entree basse du coeur.
    drawCell(gcx, gcy + 1, dtPathTone)

    local tValveGlyph = state.tOpen and (tAnimating and (blink and "<>" or ">>") or "TT") or (tAnimating and (blink and "xx" or "x ") or "T ")
    local dValveGlyph = state.dOpen and (dAnimating and (blink and "<>" or "<<") or "DD") or (dAnimating and (blink and "xx" or " x") or "D ")
    local dtValveGlyph = state.dtOpen and (dtAnimating and (blink and "<>" or "><") or "DT") or (dtAnimating and (blink and "xx" or "::") or "  ")
    drawCell(gcx - branchOffset, legY, tPathTone, tValveGlyph, C.text)
    drawCell(gcx + branchOffset, legY, dPathTone, dValveGlyph, C.text)
    drawCell(gcx, legY - 1, dtPathTone, dtValveGlyph, C.text)

    -- Libelles d'etat (haut/bas du diagramme).
    if infoY >= y + 1 then
      local laserTxt = shortText(string.format("LAS x%d (%d) %3.0f%% %s", displayedLaserCount, detectedLaserCount, state.laserPct, tostring(state.laserStatusText or laserState)), gw * cellW - 2)
      local laserTxtX = beamX - math.floor(#laserTxt / 2) + 1
      local laserTxtMinX = x + 2
      local laserTxtMaxX = x + w - #laserTxt - 1
      if laserTxtX < laserTxtMinX then laserTxtX = laserTxtMinX end
      if laserTxtX > laserTxtMaxX then laserTxtX = laserTxtMaxX end
      local infoSepY = infoY - 1
      if infoSepY >= y + 2 then
        local sepW = clamp(moduleW + 6, 14, math.max(14, gw * cellW - 4))
        local sepX = clamp(beamX - math.floor(sepW / 2) + 1, x + 2, x + w - sepW - 1)
        writeAt(sepX, infoSepY, string.rep("-", sepW), C.borderDim, C.panelDark)
      end
      writeAt(laserTxtX, infoY, laserTxt, laserTone, C.panelDark)
    elseif moduleX + moduleW + 1 <= x + w - 2 then
      local laserTxt = string.format("%3.0f%%", state.laserPct)
      writeAt(moduleX + moduleW + 1, moduleY, laserTxt, laserTone, C.panelDark)
    end

    -- Telemetries temperature:
    -- - T PLAS ancree visuellement dans la zone coeur.
    -- - T STRUCT ancree sur le contour reacteur.
    -- Traces orthogonales uniquement (pas de diagonales).
    local tempY = math.min(math.max(y + 2, ry - 2), y + h - 4)
    if tempY >= y + 2 and tempY <= y + h - 4 and w >= 50 then
      local plasText = "T PLAS " .. (state.reactorPresent and formatTemperature(state.plasmaTemp, { compact = true, decimals = 2 }) or "N/A")
      local structText = "T STRUCT " .. (state.reactorPresent and formatTemperature(state.caseTemp, { compact = true, decimals = 2 }) or "N/A")
      local leftTextX = x + 3
      local rightTextX = x + w - #structText - 3
      if leftTextX + #plasText < rightTextX - 3 then
        local plasTone = state.reactorPresent and C.warn or C.dim
        local structTone = state.reactorPresent and C.bad or C.dim
        writeAt(leftTextX, tempY, plasText, plasTone, C.panelDark)
        writeAt(rightTextX, tempY, structText, structTone, C.panelDark)

        local plasmaGuideY = math.max(tempY + 1, ry - 1)
        local plasmaGuideStartX = leftTextX + #plasText + 1
        local coreTargetX = rx + (gcx - 1) * cellW + 1
        local coreTargetY = ry + gcy - 1
        local coreEntryX = rx + (clamp(gcx - 2, 1, gw) - 1) * cellW + 1
        local plasmaDropX = clamp(rx + (gcx - 2) * cellW + 1, plasmaGuideStartX, coreEntryX)
        drawGuideH(plasmaGuideStartX, plasmaDropX, plasmaGuideY, plasTone)
        drawGuideCorner(plasmaDropX, plasmaGuideY, plasTone)
        drawGuideV(plasmaDropX, plasmaGuideY, coreTargetY, plasTone)
        drawGuideCorner(plasmaDropX, coreTargetY, plasTone)
        drawGuideH(plasmaDropX, coreEntryX, coreTargetY, plasTone)
        drawGuideEnd(coreEntryX, coreTargetY, plasTone, ">")

        local contourX, contourY = findContourAnchor("right")
        local structGuideY = math.max(tempY + 1, ry - 1)
        local structGuideStartX = rightTextX - 2
        local structTargetX = contourX or (rx + (gcx + outerR) * cellW + 1)
        local structTargetY = contourY or (ry + math.max(1, gcy - outerR + 1))
        local structDropX = clamp(structTargetX + 1, structTargetX, structGuideStartX)
        drawGuideH(structGuideStartX, structDropX, structGuideY, structTone)
        drawGuideCorner(structDropX, structGuideY, structTone)
        drawGuideV(structDropX, structGuideY, structTargetY, structTone)
        drawGuideH(structDropX, structTargetX, structTargetY, structTone)
        drawGuideEnd(structTargetX, structTargetY, structTone, "<")
      end
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
        local tIndicatorTone = state.tOpen and tPathTone or C.dim
        local dtIndicatorTone = state.dtOpen and dtPathTone or C.dim
        local dIndicatorTone = state.dOpen and dPathTone or C.dim
        writeAt(leftBranchX, labelY, tAnimating and (blink and "<>" or "||") or "||", tIndicatorTone, C.panelDark)
        writeAt(centerBranchX, labelY, dtAnimating and (blink and "<>" or "||") or "||", dtIndicatorTone, C.panelDark)
        writeAt(rightBranchX, labelY, dAnimating and (blink and "<>" or "||") or "||", dIndicatorTone, C.panelDark)

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

          writeAt(tLockX, lockY, tLock, state.tOpen and C.text or C.dim, tLockBg)
          writeAt(dtLockX, lockY, dtLock, state.dtOpen and C.text or C.dim, dtLockBg)
          writeAt(dLockX, lockY, dLock, state.dOpen and C.text or C.dim, dLockBg)
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

    -- Redessine le noyau en dernier pour garantir sa lisibilite.
    redrawCoreCluster()
    writeAt(
      x + 3,
      y + 2,
      shortText(
        "CORE "
          .. (state.reactorPresent and (state.reactorFormed and "FORMED" or "UNFORMED") or "ABSENT")
          .. " | HOHL "
          .. (hohlraumPresent and "OK" or "MISSING"),
        math.max(8, math.floor(w * 0.45))
      ),
      state.reactorPresent and C.info or C.bad,
      C.panelDark
    )
  end

  return drawReactorDiagram
end

return M
