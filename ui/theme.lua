local M = {}

function M.applyPremiumPalette(C)
  C.bg = colors.black
  C.panel = colors.gray
  C.panelDark = colors.black
  C.panelLight = colors.lightGray
  C.text = colors.white
  C.dim = colors.lightGray
  C.ok = colors.green
  C.warn = colors.orange
  C.bad = colors.red
  C.info = colors.cyan
  C.accent = colors.lightBlue
  C.border = colors.lightBlue
  C.borderDim = colors.gray
  C.energy = colors.yellow
  C.tritium = colors.green
  C.deuterium = colors.red
  C.dtFuel = colors.purple
  C.headerBg = colors.gray
  C.footerBg = colors.gray
end

return M
