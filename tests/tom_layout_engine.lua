-- tests/tom_layout_engine.lua
-- Validates adaptive layout generation for Tom UI.

local M = {}

local function inside(outer, inner)
  if type(outer) ~= "table" or type(inner) ~= "table" then
    return false
  end
  local ox2 = (outer.x or 1) + math.max(1, (outer.w or 1)) - 1
  local oy2 = (outer.y or 1) + math.max(1, (outer.h or 1)) - 1
  local ix2 = (inner.x or 1) + math.max(1, (inner.w or 1)) - 1
  local iy2 = (inner.y or 1) + math.max(1, (inner.h or 1)) - 1
  return (inner.x or 1) >= (outer.x or 1)
    and (inner.y or 1) >= (outer.y or 1)
    and ix2 <= ox2
    and iy2 <= oy2
end

function M.run(ctx)
  local fail = assert(ctx.fail, "ctx.fail required")
  local ok = assert(ctx.ok, "ctx.ok required")
  local toPath = assert(ctx.toPath, "ctx.toPath required")

  local okDesign, TomDesign = pcall(dofile, toPath("ui/tom_design.lua"))
  local okLayout, TomLayout = pcall(dofile, toPath("ui/tom_layout.lua"))
  if not okDesign or type(TomDesign) ~= "table" then
    fail(170, "Cannot load ui/tom_design.lua")
    return
  end
  if not okLayout or type(TomLayout) ~= "table" then
    fail(171, "Cannot load ui/tom_layout.lua")
    return
  end

  local cases = {
    { w = 30, h = 12, expectTooSmall = true },
    { w = 72, h = 24, expectDensity = "small" },
    { w = 116, h = 34, expectDensity = "medium" },
    { w = 170, h = 52, expectDensity = "large" },
  }

  for _, item in ipairs(cases) do
    local design = TomDesign.build(item.w, item.h)
    local layout = TomLayout.compute(item.w, item.h, design, "supervision")
    if type(layout) ~= "table" then
      fail(172, "Layout result invalid for " .. tostring(item.w) .. "x" .. tostring(item.h))
      return
    end

    if item.expectTooSmall then
      if not layout.tooSmall then
        fail(173, "Expected tooSmall layout for " .. tostring(item.w) .. "x" .. tostring(item.h))
        return
      end
    else
      if layout.tooSmall then
        fail(174, "Unexpected tooSmall layout for " .. tostring(item.w) .. "x" .. tostring(item.h))
        return
      end
      if item.expectDensity and layout.density ~= item.expectDensity then
        fail(175, "Density mismatch for " .. tostring(item.w) .. "x" .. tostring(item.h) .. ": " .. tostring(layout.density))
        return
      end

      if not inside(layout.root, layout.header) or not inside(layout.root, layout.footer) then
        fail(176, "Header/footer out of root bounds for " .. tostring(item.w) .. "x" .. tostring(item.h))
        return
      end
      if not inside(layout.root, layout.content) then
        fail(177, "Content out of root bounds for " .. tostring(item.w) .. "x" .. tostring(item.h))
        return
      end
      if not inside(layout.content, layout.columns.left)
        or not inside(layout.content, layout.columns.center)
        or not inside(layout.content, layout.columns.right) then
        fail(178, "Column out of content bounds for " .. tostring(item.w) .. "x" .. tostring(item.h))
        return
      end

      local controls = layout.controls or {}
      if type(controls.buttonBounds) ~= "table" then
        fail(179, "Missing button bounds for " .. tostring(item.w) .. "x" .. tostring(item.h))
        return
      end
      if not inside(layout.columns.right, controls.buttonBounds) then
        fail(180, "Button bounds out of right column for " .. tostring(item.w) .. "x" .. tostring(item.h))
        return
      end
      if controls.ioBounds and not inside(layout.columns.right, controls.ioBounds) then
        fail(181, "IO bounds out of right column for " .. tostring(item.w) .. "x" .. tostring(item.h))
        return
      end
    end
  end

  ok("Tom layout engine adaptive bounds OK")
end

return M
