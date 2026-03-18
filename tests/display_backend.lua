-- tests/display_backend.lua
-- Verifie la couche de compatibilite d'affichage (CC classique + Tom's GPU).

local M = {}

function M.run(ctx)
  local fail = assert(ctx.fail, "ctx.fail requis")
  local ok = assert(ctx.ok, "ctx.ok requis")
  local toPath = assert(ctx.toPath, "ctx.toPath requis")

  local loadOk, backend = pcall(dofile, toPath("io/display_backend.lua"))
  if not loadOk or type(backend) ~= "table" then
    fail(80, "Chargement io/display_backend.lua impossible: " .. tostring(backend))
    return
  end
  ok("Module display backend charge")

  local ccMonitor = {
    getSize = function() return 80, 40 end,
    setCursorPos = function() end,
    write = function() end,
    clear = function() end,
    setTextColor = function() end,
    setBackgroundColor = function() end,
  }

  local ccCandidate = backend.detectCandidate("monitor_0", ccMonitor, function()
    return "monitor"
  end)
  if type(ccCandidate) ~= "table" or ccCandidate.kind ~= "cc_monitor" then
    fail(81, "Detection monitor CC invalide")
  else
    ok("Detection monitor CC OK")
  end

  local ccCandidateNoName = backend.detectCandidate("display_anything", ccMonitor, function()
    return "monitor"
  end)
  if type(ccCandidateNoName) ~= "table" or ccCandidateNoName.kind ~= "cc_monitor" then
    fail(810, "Detection monitor CC ne doit pas dependre du nom")
  else
    ok("Detection monitor CC sans nom hardcode OK")
  end

  local ccSurface, ccMeta = backend.createSurface(ccCandidate, { monitorScale = 0.5 })
  if ccSurface ~= ccMonitor then
    fail(82, "Surface CC doit reutiliser l'objet monitor natif")
  else
    ok("Surface CC preservee")
  end
  if type(ccMeta) ~= "table" or ccMeta.touchEvent ~= "monitor_touch" then
    fail(83, "Meta CC invalide")
  else
    ok("Meta CC valide")
  end

  local gpu = {
    getResolution = function() return 192, 108 end,
    fill = function() end,
    filledRectangle = function() end,
    drawText = function() end,
    drawChar = function() end,
    getTextLength = function(text) return math.max(1, #tostring(text or "")) * 4 end,
    sync = function() end,
  }

  local gpuCandidate = backend.detectCandidate("display_any_42", gpu, function()
    return "tm_gpu"
  end)
  if type(gpuCandidate) ~= "table" or gpuCandidate.kind ~= "toms_gpu" then
    fail(84, "Detection Tom GPU invalide")
    return
  end
  ok("Detection Tom GPU OK")

  local gpuCapsOnly = backend.detectCandidate("unknown_device", gpu, function()
    return "vendor_device"
  end)
  if type(gpuCapsOnly) ~= "table" or gpuCapsOnly.kind ~= "toms_gpu" then
    fail(841, "Detection Tom GPU doit fonctionner par capacites meme sans type explicite")
    return
  end
  ok("Detection Tom GPU par capacites OK")

  local gpuSurface, gpuMeta = backend.createSurface(gpuCandidate, { monitorScale = 1 })
  if type(gpuSurface) ~= "table" then
    fail(85, "Surface Tom GPU non creee")
    return
  end

  local requiredMethods = {
    "getSize",
    "setCursorPos",
    "write",
    "blit",
    "clear",
    "setTextColor",
    "setBackgroundColor",
    "flush",
    "mapPixel",
  }
  for _, methodName in ipairs(requiredMethods) do
    if type(gpuSurface[methodName]) ~= "function" then
      fail(86, "Surface Tom GPU: methode manquante " .. tostring(methodName))
      return
    end
  end
  ok("Surface Tom GPU expose les primitives attendues")

  local w, h = gpuSurface.getSize()
  if tonumber(w) == nil or tonumber(h) == nil or w < 1 or h < 1 then
    fail(87, "Surface Tom GPU: taille invalide")
    return
  end
  ok("Surface Tom GPU taille valide: " .. tostring(w) .. "x" .. tostring(h))

  gpuSurface.setBackgroundColor(colors.black)
  gpuSurface.setTextColor(colors.white)
  gpuSurface.clear()
  gpuSurface.setCursorPos(1, 1)
  gpuSurface.write("OK")
  gpuSurface.setCursorPos(1, 2)
  gpuSurface.blit("OK", "0f", "f0")
  gpuSurface.flush()
  ok("Surface Tom GPU ecriture/flush OK")

  local tx, ty = gpuSurface.mapPixel(12, 18)
  if tonumber(tx) == nil or tonumber(ty) == nil then
    fail(88, "mapPixel doit retourner des coordonnees")
  else
    ok("mapPixel OK")
  end

  local noCandidate = backend.detectCandidate("weird_periph", {}, function()
    return "modem"
  end)
  if noCandidate ~= nil then
    fail(89, "Un peripherique non display ne doit pas etre detecte")
  else
    ok("Filtrage non-display OK")
  end
end

return M
