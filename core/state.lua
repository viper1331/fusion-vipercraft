local M = {}

function M.new(initial)
  local state = {}
  for k, v in pairs(initial or {}) do
    state[k] = v
  end
  return state
end

return M
