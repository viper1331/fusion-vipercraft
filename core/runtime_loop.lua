-- core/runtime_loop.lua
-- Boucle principale runtime.

local EventRouter = require("core.event_router")

local M = {}

function M.run(api)
  local state = api.state
  local CFG = api.CFG

  while state.running do
    api.refreshAll()
    api.fullAuto()
    api.drawUI()

    local timer = os.startTimer(CFG.refreshDelay)
    local ev, p1, p2, p3 = os.pullEvent()

    if ev == "timer" and p1 == timer then
      -- Tick normal: rien a faire, la boucle reprend.
    else
      EventRouter.route(ev, p1, p2, p3, api)
    end
  end
end

return M
