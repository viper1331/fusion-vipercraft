-- tests/tom_surface_compat.lua
-- Verifie la compatibilite du renderer Tom avec signatures API variables.

local M = {}

function M.run(ctx)
  local fail = assert(ctx.fail, "ctx.fail requis")
  local ok = assert(ctx.ok, "ctx.ok requis")
  local toPath = assert(ctx.toPath, "ctx.toPath requis")

  local loadOk, backend = pcall(dofile, toPath("io/display_backend.lua"))
  if not loadOk or type(backend) ~= "table" then
    fail(140, "Chargement io/display_backend.lua impossible")
    return
  end

  local calls = {
    fillRect = 0,
    drawText = 0,
    sync = 0,
  }

  -- Stub "Tom permissif" avec signatures alternatives:
  -- fillRect(x1,y1,x2,y2,color) et drawText(text,x,y,color)
  local gpu = {
    getResolution = function() return 96, 72 end,
    getTextLength = function(text) return #tostring(text or "") end,
    fillRect = function(x1, y1, x2, y2, color)
      calls.fillRect = calls.fillRect + 1
      if type(x1) ~= "number" or type(x2) ~= "number" then
        error("fillRect invalid args")
      end
      return true
    end,
    drawText = function(text, x, y, color)
      calls.drawText = calls.drawText + 1
      if type(text) ~= "string" then
        error("drawText text-first signature attendue")
      end
      return true
    end,
    sync = function()
      calls.sync = calls.sync + 1
      return true
    end,
  }

  local candidate, rejectReason = backend.detectCandidate("tm_gpu_test", gpu, function()
    return "tm_gpu"
  end)

  if type(candidate) ~= "table" or candidate.kind ~= "toms_gpu" then
    fail(141, "Detection toms_gpu echouee: " .. tostring(rejectReason))
    return
  end
  ok("Detection Tom compatible OK")

  local surface, meta = backend.createSurface(candidate, { monitorScale = 0.5 })
  if type(surface) ~= "table" then
    fail(142, "Surface Tom non creee")
    return
  end
  if type(meta) ~= "table" or meta.kind ~= "toms_gpu" then
    fail(143, "Meta Tom invalide")
    return
  end

  surface.setBackgroundColor(colors.black)
  surface.setTextColor(colors.white)
  surface.clear()
  surface.setCursorPos(1, 1)
  surface.write("OK")
  surface.flush()

  if calls.fillRect < 1 then
    fail(144, "fillRect n'a pas ete utilise")
    return
  end
  if calls.drawText < 1 then
    fail(145, "drawText n'a pas ete utilise")
    return
  end
  if calls.sync < 1 then
    fail(146, "sync n'a pas ete appele")
    return
  end

  ok("Compatibilite signatures Tom validee")

  -- Variante API observee sur certains setups:
  -- drawText(x, y, color, text)
  local callsAlt = {
    fillRect = 0,
    drawText = 0,
    sync = 0,
  }
  local gpuAlt = {
    getResolution = function() return 96, 72 end,
    getTextLength = function(text) return #tostring(text or "") end,
    fillRect = function(_, _, _, _, _)
      callsAlt.fillRect = callsAlt.fillRect + 1
      return true
    end,
    drawText = function(a, b, c, d)
      callsAlt.drawText = callsAlt.drawText + 1
      if type(a) ~= "number" or type(b) ~= "number" or type(c) ~= "number" or type(d) ~= "string" then
        error("drawText xycolortext signature attendue")
      end
      return true
    end,
    sync = function()
      callsAlt.sync = callsAlt.sync + 1
      return true
    end,
  }

  local candidateAlt = backend.detectCandidate("tm_gpu_alt", gpuAlt, function()
    return "tm_gpu"
  end)
  if type(candidateAlt) ~= "table" or candidateAlt.kind ~= "toms_gpu" then
    fail(147, "Detection toms_gpu alternative echouee")
    return
  end

  local surfaceAlt, metaAlt = backend.createSurface(candidateAlt, { monitorScale = 0.5 })
  if type(surfaceAlt) ~= "table" or type(metaAlt) ~= "table" then
    fail(148, "Surface Tom alternative non creee")
    return
  end

  surfaceAlt.setBackgroundColor(colors.black)
  surfaceAlt.setTextColor(colors.white)
  surfaceAlt.clear()
  surfaceAlt.setCursorPos(1, 1)
  surfaceAlt.write("ALT")
  surfaceAlt.flush()

  if callsAlt.drawText < 1 then
    fail(149, "drawText signature alternative non supportee")
    return
  end
  if callsAlt.sync < 1 then
    fail(150, "sync alternatif non appele")
    return
  end

  ok("Compatibilite drawText(x,y,color,text) validee")
end

return M
