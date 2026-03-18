-- core/runtime_loop.lua
-- Boucle principale runtime.

local EventRouter = require("core.event_router")

local M = {}

function M.run(api)
  local state = api.state
  local CFG = api.CFG
  local log = api.log or {}
  local logDebug = type(log.debug) == "function" and log.debug or function() end
  local logError = type(log.captureError) == "function" and log.captureError
    or (type(log.error) == "function" and function(context, err, meta)
      local payload = type(meta) == "table" and meta or {}
      payload.error = tostring(err)
      log.error(context, payload)
    end)
    or function() end

  logDebug("Runtime loop started", { refreshDelay = CFG.refreshDelay })

  while state.running do
    local okRefresh, errRefresh = pcall(api.refreshAll)
    if not okRefresh then
      logError("refreshAll failed", errRefresh)
      error(errRefresh, 0)
    end

    local okAuto, errAuto = pcall(api.fullAuto)
    if not okAuto then
      logError("fullAuto failed", errAuto)
      error(errAuto, 0)
    end

    local okDraw, errDraw = pcall(api.drawUI)
    if not okDraw then
      logError("drawUI failed", errDraw)
      error(errDraw, 0)
    end

    local timer = os.startTimer(CFG.refreshDelay)
    local ev, p1, p2, p3 = os.pullEvent()

    if ev == "timer" and p1 == timer then
      -- Tick normal: rien a faire, la boucle reprend.
    else
      logDebug("Runtime event", { event = ev })
      local okRoute, errRoute = pcall(EventRouter.route, ev, p1, p2, p3, api)
      if not okRoute then
        logError("EventRouter.route failed", errRoute, { event = ev })
        error(errRoute, 0)
      end
    end
  end

  logDebug("Runtime loop stopped")
end

return M
