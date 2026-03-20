-- tests/toms_text_reflow.lua
-- Phase 4 guardrail: no automatic ellipsis truncation and pixel-native text reflow availability.

local M = {}

local function newNativeTarget(width, height)
  local writes = {}
  local fills = 0

  local target = {
    getSize = function()
      return width, height
    end,
    getTextLength = function(text)
      return #(tostring(text or "")) * 8
    end,
    drawText = function(x, y, text, _color)
      writes[#writes + 1] = {
        x = x,
        y = y,
        text = tostring(text or ""),
      }
      return true
    end,
    filledRectangle = function()
      fills = fills + 1
      return true
    end,
    fillRect = function()
      fills = fills + 1
      return true
    end,
  }

  return target, writes, function()
    return fills
  end
end

function M.run(ctx)
  local fail = assert(ctx.fail, "ctx.fail required")
  local ok = assert(ctx.ok, "ctx.ok required")
  local toPath = assert(ctx.toPath, "ctx.toPath required")

  local okTheme, Theme = pcall(dofile, toPath("ui/toms/theme.lua"))
  local okComponents, Components = pcall(dofile, toPath("ui/toms/components.lua"))
  if not okTheme or type(Theme) ~= "table" then
    fail(230, "Cannot load ui/toms/theme.lua")
    return
  end
  if not okComponents or type(Components) ~= "table" then
    fail(231, "Cannot load ui/toms/components.lua")
    return
  end

  local theme = Theme.build(512, 384, { backendFamily = "toms_native" })
  local target, writes, getFillCount = newNativeTarget(512, 384)
  local ui = Components.new({
    target = target,
    width = 512,
    height = 384,
    theme = theme,
  })

  if type(theme.text) ~= "table" or type(theme.text.truncate) ~= "function" then
    fail(232, "Theme text helpers are missing")
    return
  end

  local sample = "REACTOR-LONG-TEXT-SHOULD-NOT-BE-ELLIPSIZED"
  local passthrough = theme.text.truncate(sample, 6)
  if passthrough ~= sample then
    fail(233, "Theme truncate still alters text in Phase 4 mode")
    return
  end

  ui.safeText(4, 6, sample, colors.white, nil, 40, "left")
  if #writes == 0 then
    fail(234, "safeText did not emit native drawText")
    return
  end

  local firstWrite = writes[#writes]
  if firstWrite.text:find("%.%.%.") then
    fail(235, "safeText inserted ellipsis, which is forbidden in Phase 4")
    return
  end
  if #(firstWrite.text or "") > 5 then
    fail(236, "safeText pixel clipping did not respect native width constraints")
    return
  end

  local lineCount, clipped = ui.safeTextBlock(
    ui.rect(4, 20, 120, 40),
    "alpha beta gamma delta epsilon zeta eta theta iota kappa",
    colors.white,
    nil,
    {
      lineStep = 8,
      lineHeight = 8,
      align = "left",
    }
  )

  if type(lineCount) ~= "number" or lineCount < 2 then
    fail(237, "safeTextBlock did not produce wrapped multi-line output")
    return
  end

  if getFillCount() < 0 then
    fail(238, "Unexpected fill accounting failure")
    return
  end

  if clipped ~= true and clipped ~= false then
    fail(239, "safeTextBlock clipped flag is invalid")
    return
  end

  ok("Tom text Phase 4 reflow/truncation guardrails OK")
end

return M
