local M = {}

function M.applyPremiumPalette(C)
  C.bg = colors.black
  C.panel = colors.gray
  C.panelDark = colors.gray
  C.panelLight = colors.lightGray
  C.text = colors.white
  C.dim = colors.lightGray
  C.ok = colors.lime
  C.warn = colors.orange
  C.bad = colors.red
  C.info = colors.cyan
  C.accent = colors.lightBlue
  C.border = colors.lightGray
  C.borderDim = colors.gray
end

return M
