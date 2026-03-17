local M = {}

function M.applyPremiumPalette(C)
  C.bg = colors.white
  C.panel = colors.lightGray
  C.panelDark = colors.white
  C.panelLight = colors.lightGray
  C.text = colors.black
  C.dim = colors.gray
  C.ok = colors.green
  C.warn = colors.orange
  C.bad = colors.red
  C.info = colors.cyan
  C.accent = colors.lightBlue
  C.border = colors.cyan
  C.borderDim = colors.lightBlue
  C.energy = colors.yellow
  C.tritium = colors.green
  C.deuterium = colors.orange
  C.dtFuel = colors.purple
  C.headerBg = colors.lightGray
  C.footerBg = colors.lightGray
end

return M
