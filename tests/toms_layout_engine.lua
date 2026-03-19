-- tests/toms_layout_engine.lua
-- Validates adaptive layout bounds for the new Tom UI.

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

  local okTheme, Theme = pcall(dofile, toPath("ui/toms/theme.lua"))
  local okLayout, Layout = pcall(dofile, toPath("ui/toms/layout.lua"))
  if not okTheme or type(Theme) ~= "table" then
    fail(170, "Cannot load ui/toms/theme.lua")
    return
  end
  if not okLayout or type(Layout) ~= "table" then
    fail(171, "Cannot load ui/toms/layout.lua")
    return
  end

  local cases = {
    { w = 36, h = 14, expectTooSmall = true },
    { w = 74, h = 24, expectTooSmall = true },
    { w = 122, h = 36, density = "small" },
    { w = 170, h = 52, density = "medium" },
    { w = 320, h = 200, density = "large" },
  }

  for _, item in ipairs(cases) do
    local theme = Theme.build(item.w, item.h)
    local layout = Layout.compute(item.w, item.h, theme, "supervision")
    if type(layout) ~= "table" then
      fail(172, "Layout result invalid for " .. tostring(item.w) .. "x" .. tostring(item.h))
      return
    end

    if item.expectTooSmall then
      if not layout.tooSmall then
        fail(173, "Expected tooSmall for " .. tostring(item.w) .. "x" .. tostring(item.h))
        return
      end
    else
      if layout.tooSmall then
        fail(174, "Unexpected tooSmall for " .. tostring(item.w) .. "x" .. tostring(item.h))
        return
      end
      if item.density and layout.density ~= item.density then
        fail(175, "Density mismatch for " .. tostring(item.w) .. "x" .. tostring(item.h))
        return
      end

      if not inside(layout.root, layout.header)
        or not inside(layout.root, layout.content)
        or not inside(layout.root, layout.footer) then
        fail(176, "Root bounds violation for " .. tostring(item.w) .. "x" .. tostring(item.h))
        return
      end

      if not inside(layout.content, layout.columns.left)
        or not inside(layout.content, layout.columns.center)
        or not inside(layout.content, layout.columns.right) then
        fail(177, "Column bounds violation for " .. tostring(item.w) .. "x" .. tostring(item.h))
        return
      end

      local controls = layout.controls or {}
      if type(controls.buttonBounds) ~= "table" then
        fail(178, "Missing controls.buttonBounds for " .. tostring(item.w) .. "x" .. tostring(item.h))
        return
      end
      if not inside(layout.footer, controls.buttonBounds) then
        fail(179, "Button bounds outside footer for " .. tostring(item.w) .. "x" .. tostring(item.h))
        return
      end
    end
  end

  ok("Tom layout engine v2 adaptive bounds OK")
end

return M
