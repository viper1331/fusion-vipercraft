local M = {}

function M.getFillRatio(state)
  if not state.inductionPresent then return 0 end
  if (state.inductionMax or 0) <= 0 then return 0 end
  return math.max(0, math.min(1, (state.inductionEnergy or 0) / state.inductionMax))
end

return M
