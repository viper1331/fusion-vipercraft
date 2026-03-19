-- tests/toms_footer_controls.lua
-- Ensures Tom footer control mode exposes the expected action buttons.

local M = {}

function M.run(ctx)
  local fail = assert(ctx.fail, "ctx.fail required")
  local ok = assert(ctx.ok, "ctx.ok required")
  local toPath = assert(ctx.toPath, "ctx.toPath required")

  local loadOk, UIComponents = pcall(dofile, toPath("ui/components.lua"))
  if not loadOk or type(UIComponents) ~= "table" or type(UIComponents.buildButtons) ~= "function" then
    fail(188, "Cannot load ui/components.lua for tom footer controls test")
    return
  end

  local added = {}
  local function addButton(id, x, y, w, h, label, bg, fg, action, opts)
    added[#added + 1] = {
      id = id,
      label = label,
      opts = type(opts) == "table" and opts or {},
    }
  end

  local function addRowButton(id, x, y, w, h, label, bg, fg, action)
    addButton(id, x, y, w, h, label, bg, fg, action, {})
  end

  local function hasButton(id)
    for _, item in ipairs(added) do
      if item.id == id then
        return true, item
      end
    end
    return false, nil
  end

  local state = {
    choosingMonitor = false,
    injectionWritable = true,
    currentView = "supervision",
    controlBounds = { x = 2, y = 2, w = 90, h = 3 },
  }

  UIComponents.buildButtons({
    state = state,
    C = {
      btnAction = colors.cyan,
      warn = colors.orange,
      panelMid = colors.gray,
      inactive = colors.lightGray,
      bad = colors.red,
    },
    clamp = function(v, lo, hi)
      if v < lo then return lo end
      if v > hi then return hi end
      return v
    end,
    shortText = function(text)
      return tostring(text or "")
    end,
    addButton = addButton,
    addRowButton = addRowButton,
    drawBigButton = function() end,
    actions = {
      refreshNow = function() end,
      fireLaser = function() end,
      adjustInjectionRate = function() end,
      quitProgram = function() end,
      stopRequested = function() end,
    },
  }, {
    tomFooterControls = true,
    right = { x = 1, y = 1, w = 90, h = 6 },
    width = 96,
    bottom = 20,
  })

  local required = {
    "refreshNow",
    "manualPulse",
    "manualInjDown",
    "manualInjUp",
    "quit",
  }
  for _, id in ipairs(required) do
    local present = hasButton(id)
    if not present then
      fail(189, "Missing Tom footer button: " .. id)
      return
    end
  end

  local _, injDown = hasButton("manualInjDown")
  if not injDown or injDown.opts.disabled then
    fail(190, "Injection down should be enabled when injectionWritable is true")
    return
  end

  ok("Tom footer controls expose expected action buttons")
end

return M
