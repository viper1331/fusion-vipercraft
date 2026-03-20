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

  ok("Tom assets integration OK")
end

return M
