-- tests/reactor_diagram_render.lua
-- Verifie que le renderer reacteur peut dessiner les etats visuels principaux
-- sans erreur (coeur, animation coeur, LAS charge).

local M = {}

function M.run(ctx)
  local fail = assert(ctx.fail, "ctx.fail requis")
  local ok = assert(ctx.ok, "ctx.ok requis")
  local toPath = assert(ctx.toPath, "ctx.toPath requis")

  local path = toPath("ui/reactor_diagram.lua")
  local loadOk, ReactorDiagram = pcall(dofile, path)
  if not loadOk or type(ReactorDiagram) ~= "table" or type(ReactorDiagram.build) ~= "function" then
    fail(100, "Impossible de charger ui/reactor_diagram.lua")
    return
  end

  local writes = 0
  local laserModuleWrites = {}
  local state = {
    tick = 0,
    alert = "NONE",
    reactorPresent = true,
    reactorFormed = true,
    ignition = false,
    ignitionSequencePending = false,
    tOpen = false,
    dtOpen = false,
    dOpen = false,
    laserState = "READY",
    laserStatusText = "READY",
    laserDetectedCount = 3,
    laserLineOn = false,
    lastLaserPulseAt = -1,
    laserPct = 100,
    hohlraumPresent = true,
    plasmaTemp = 295,
    caseTemp = 295,
  }

  local C = {
    border = colors.cyan,
    borderDim = colors.lightBlue,
    panel = colors.lightGray,
    panelDark = colors.white,
    panelMid = colors.lightGray,
    text = colors.black,
    dim = colors.gray,
    ok = colors.green,
    warn = colors.orange,
    bad = colors.red,
    info = colors.cyan,
    energy = colors.yellow,
    tritium = colors.green,
    dtFuel = colors.purple,
  }

  local function writeAt(x, y, txt, fg, bg)
    writes = writes + #(tostring(txt or ""))
    if txt == "[]" and bg == colors.green and y <= 16 then
      table.insert(laserModuleWrites, { x = x, y = y, fg = fg, bg = bg })
    end
  end

  local function drawBox(_, _, _, _, _, _)
    writes = writes + 1
  end

  local function shortText(text, maxLen)
    text = tostring(text or "")
    if #text <= maxLen then return text end
    return text:sub(1, maxLen)
  end

  local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
  end

  local draw = ReactorDiagram.build({
    state = state,
    CFG = { laserCount = 3 },
    C = C,
    drawBox = drawBox,
    writeAt = writeAt,
    shortText = shortText,
    clamp = clamp,
    formatTemperature = function(v)
      return string.format("%.1f C", tonumber(v) or 0)
    end,
  })

  local scenarios = {
    { name = "idle", mutate = function() state.tick = 1; state.laserState = "READY"; state.ignition = false; state.laserLineOn = false end },
    { name = "charging", mutate = function() state.tick = 7; state.laserState = "CHARGING"; state.ignition = false; state.laserLineOn = false end },
    { name = "firing", mutate = function() state.tick = 12; state.laserState = "READY"; state.ignition = true; state.laserLineOn = true end },
  }

  for _, scenario in ipairs(scenarios) do
    local before = writes
    scenario.mutate()
    local okDraw, errDraw = pcall(draw, 1, 1, 120, 38)
    if not okDraw then
      fail(101, "Renderer reacteur en erreur (" .. scenario.name .. "): " .. tostring(errDraw))
      return
    end
    if writes <= before then
      fail(102, "Aucune sortie graphique detectee (" .. scenario.name .. ")")
      return
    end
  end

  -- Verification specifique: en mode READY et multi-lasers, les modules
  -- LAS doivent former une pile verticale (meme colonne, plusieurs lignes).
  laserModuleWrites = {}
  state.tick = 4
  state.ignition = false
  state.laserLineOn = false
  state.laserState = "READY"
  local okStack, errStack = pcall(draw, 1, 1, 120, 38)
  if not okStack then
    fail(103, "Erreur rendu verification pile LAS: " .. tostring(errStack))
    return
  end

  local perColumn = {}
  for _, cell in ipairs(laserModuleWrites) do
    perColumn[cell.x] = perColumn[cell.x] or {}
    perColumn[cell.x][cell.y] = true
  end
  local bestVertical = 0
  for _, rows in pairs(perColumn) do
    local count = 0
    for _ in pairs(rows) do count = count + 1 end
    if count > bestVertical then bestVertical = count end
  end
  if bestVertical < 3 then
    fail(104, "Pile verticale LAS non detectee (1 module = 1 laser)")
    return
  end

  ok("Renderer reacteur stable (idle/charging/firing)")
end

return M
