local M = {}

function M.resolveViewName(currentView)
  if currentView == "diagnostic" then return "DIAG" end
  if currentView == "manual" then return "MAN" end
  if currentView == "induction" then return "IND" end
  if currentView == "update" then return "UPDATE" end
  return "SUP"
end

return M
