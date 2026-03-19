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
  C.headerText = colors.black
  C.btnOn = colors.green
  C.btnOff = colors.red
  C.btnAction = colors.cyan
  C.btnWarn = colors.orange
  C.btnText = colors.black
  C.tritium = colors.green
  C.deuterium = colors.orange
  C.dtFuel = colors.purple
  C.inactive = colors.gray
  C.variant = "cc"
end

function M.applyTomPalette(C)
  -- Palette sombre "console HUD" dediee au rendu Tom.
  C.bg = colors.black
  C.panel = colors.blue
  C.panelDark = colors.black
  C.panelMid = colors.gray
  C.panelInner = colors.lightBlue
  C.panelShadow = colors.black
  C.text = colors.white
  C.dim = colors.lightGray
  C.ok = colors.lime
  C.warn = colors.yellow
  C.bad = colors.red
  C.info = colors.cyan
  C.border = colors.lightBlue
  C.borderDim = colors.blue
  C.energy = colors.yellow
  C.fuel = colors.orange
  C.headerBg = colors.blue
  C.footerBg = colors.blue
  C.headerText = colors.white
  C.btnOn = colors.green
  C.btnOff = colors.red
  C.btnAction = colors.blue
  C.btnWarn = colors.orange
  C.btnText = colors.white
  C.tritium = colors.green
  C.deuterium = colors.orange
  C.dtFuel = colors.purple
  C.inactive = colors.gray
  C.variant = "tom"
end

return M
