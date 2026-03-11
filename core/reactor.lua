local M = {}

function M.canIgnite(state)
  return state.reactorPresent and state.reactorFormed and (not state.ignition)
end

return M
