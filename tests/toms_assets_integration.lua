-- tests/toms_assets_integration.lua
-- Verifies Tom reactor/module assets are loadable and drawable.

local M = {}

function M.run(ctx)
  local fail = assert(ctx.fail, "ctx.fail required")
  local ok = assert(ctx.ok, "ctx.ok required")
  local toPath = assert(ctx.toPath, "ctx.toPath required")

  local loadOk, Assets = pcall(dofile, toPath("ui/toms/assets.lua"))
  if not loadOk or type(Assets) ~= "table" then
    fail(215, "Cannot load ui/toms/assets.lua")
    return
  end

  local draws = 0
  local surface = {
    filledRectangle = function()
      draws = draws + 1
      return true
    end,
  }

  local reactorOk = Assets.draw(surface, "reactor", 20, 20, 96, 96)
  if reactorOk ~= true then
    fail(216, "Reactor asset draw failed")
    return
  end

  local moduleOk = Assets.draw(surface, "laser_module", 32, 8, 64, 10)
  if moduleOk ~= true then
    fail(217, "Laser module asset draw failed")
    return
  end

  if draws <= 0 then
    fail(218, "Asset drawing did not emit fill operations")
    return
  end

  local anchors = Assets.getAnchors("reactor", 20, 20, 96, 96)
  if type(anchors) ~= "table" then
    fail(219, "Reactor anchors are missing")
    return
  end

  local required = { "core", "tritium", "dtfuel", "deuterium", "energy", "laser" }
  for _, key in ipairs(required) do
    local point = anchors[key]
    if type(point) ~= "table" or type(point.x) ~= "number" or type(point.y) ~= "number" then
      fail(220, "Missing reactor anchor: " .. tostring(key))
      return
    end
  end

  local unknownOk = Assets.draw(surface, "unknown_asset", 1, 1, 8, 8)
  if unknownOk == true then
    fail(221, "Unknown asset should not draw")
    return
  end

  local resolvedCount = Assets.resolveLaserModuleCount({ laserCount = 7 }, { laserCount = 2 }, 1)
  if resolvedCount ~= 7 then
    fail(222, "resolveLaserModuleCount should prioritize CFG laserCount")
    return
  end

  local fallbackCount = Assets.resolveLaserModuleCount({}, { laserCount = 3 }, 1)
  if fallbackCount ~= 3 then
    fail(223, "resolveLaserModuleCount should fallback to runtime state")
    return
  end

  local stackPlan = Assets.planVerticalStack({ x = 10, y = 5, w = 40, h = 30 }, {
    count = 5,
    aspect = Assets.getSpriteAspect("laser_module", 6.75),
    centerX = 30,
    widthRatio = 0.5,
    minWidth = 8,
    maxWidth = 24,
  })
  if type(stackPlan) ~= "table" or type(stackPlan.modules) ~= "table" or #stackPlan.modules ~= 5 then
    fail(224, "planVerticalStack returned invalid module placement")
    return
  end

  if stackPlan.centerX ~= 30 then
    fail(225, "planVerticalStack did not preserve requested center axis")
    return
  end

  local scene = Assets.planReactorScene({ x = 1, y = 1, w = 120, h = 90 }, {
    laserCount = 6,
    moduleAspect = Assets.getSpriteAspect("laser_module", 6.75),
    laserGap = 2,
  })
  if type(scene) ~= "table" or type(scene.reactor) ~= "table" or type(scene.stack) ~= "table" then
    fail(226, "planReactorScene returned invalid scene")
    return
  end

  if #scene.stack.modules ~= 6 then
    fail(227, "planReactorScene does not expose the expected laser stack size")
    return
  end

  local reactorCenter = scene.reactor.x + math.floor((scene.reactor.w - 1) / 2)
  if math.abs((scene.centerX or reactorCenter) - reactorCenter) > 1 then
    fail(228, "planReactorScene center axis is not aligned with reactor")
    return
  end

  ok("Tom assets integration OK")
end

return M
