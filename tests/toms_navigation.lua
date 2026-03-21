-- tests/toms_navigation.lua
-- Validates the dedicated Tom navigation module behavior.

local M = {}

function M.run(ctx)
  local fail = assert(ctx.fail, "ctx.fail required")
  local ok = assert(ctx.ok, "ctx.ok required")
  local toPath = assert(ctx.toPath, "ctx.toPath required")

  local originalRequire = _G.require
  _G.require = function(name)
    if name == "ui.toms.pages.registry" then
      return assert(dofile(toPath("ui/toms/pages/registry.lua")))
    end
    if type(originalRequire) == "function" then
      return originalRequire(name)
    end
    error("module not found: " .. tostring(name))
  end

  local loadOk, TomNav = pcall(dofile, toPath("ui/toms/nav.lua"))
  _G.require = originalRequire
  if not loadOk or type(TomNav) ~= "table" then
    fail(191, "Cannot load ui/toms/nav.lua")
    return
  end

  local state = { currentView = "supervision", choosingMonitor = false }
  local tabs = TomNav.getTabs(state)
  if type(tabs) ~= "table" or #tabs < 7 then
    fail(192, "Tom nav tabs list is incomplete")
    return
  end

  local expectedOrder = {
    "supervision",
    "diagnostic",
    "manual",
    "induction",
    "update",
    "config",
    "setup",
  }
  for index, key in ipairs(expectedOrder) do
    local entry = tabs[index]
    if type(entry) ~= "table" or entry.key ~= key then
      fail(193, "Tom nav tab order mismatch at index " .. tostring(index))
      return
    end
  end

  local palette = { btnOn = colors.lime, panelMid = colors.gray }
  local setViewCalled = nil
  local items = TomNav.buildButtonItems(state, palette, {
    setView = function(viewKey)
      setViewCalled = tostring(viewKey)
    end,
  }, { compact = false })
  if type(items) ~= "table" or #items ~= #expectedOrder then
    fail(194, "Tom nav button items count mismatch")
    return
  end

  local hasViewCfg = false
  local hasViewSetup = false
  for _, item in ipairs(items) do
    if item.id == "viewCfg" then
      hasViewCfg = true
    elseif item.id == "viewSetup" then
      hasViewSetup = true
    end
  end
  if not hasViewCfg or not hasViewSetup then
    fail(195, "Tom nav button mapping is missing CFG/SETUP")
    return
  end

  items[5].action()
  if setViewCalled ~= "update" then
    fail(196, "Tom nav button action did not route to expected view")
    return
  end

  local changed, resolved = TomNav.handleHotkey(state, "6")
  if changed ~= true or resolved ~= "config" or state.currentView ~= "config" then
    fail(197, "Tom nav hotkey routing failed for key 6")
    return
  end

  local changedAlias, resolvedAlias = TomNav.setActiveView(state, "setup")
  if changedAlias ~= true or resolvedAlias ~= "setup" or state.currentView ~= "setup" then
    fail(198, "Tom nav active state update failed")
    return
  end

  local touchBounds = TomNav.resolveTouchBounds({
    controls = {
      navBounds = { x = 5, y = 7, w = 20, h = 3 },
    },
  }, nil, nil)
  if type(touchBounds) ~= "table" or touchBounds.x ~= 5 or touchBounds.y ~= 7 then
    fail(199, "Tom nav touch bounds resolution failed")
    return
  end

  local uiMock = {
    safeFilledRect = function() end,
    safeText = function() end,
  }
  local drawOk, drawErr = pcall(TomNav.drawBar, uiMock, { x = 1, y = 1, w = 30, h = 3, y2 = 3 }, { x = 1, y = 1, w = 30, h = 1 }, {
    palette = {
      panelBgSoft = colors.gray,
      panelBg = colors.black,
      borderStrong = colors.cyan,
      border = colors.lightBlue,
      panelHeader = colors.blue,
      info = colors.cyan,
      textOnDark = colors.white,
      textPrimary = colors.white,
    },
  }, "setup")
  if not drawOk then
    fail(200, "Tom nav drawBar crashed: " .. tostring(drawErr))
    return
  end

  ok("Tom navigation module centralized behavior OK")
end

return M
