local M = {}

function M.setupMonitor(nativeTerm, hw, CFG, C)
  if hw.monitor then
    term.redirect(nativeTerm)
    hw.monitor.setTextScale(CFG.monitorScale)
    hw.monitor.setBackgroundColor(C.bg)
    hw.monitor.setTextColor(C.text)
    term.redirect(hw.monitor)
  else
    term.redirect(nativeTerm)
  end
  term.setCursorBlink(false)
end

return M
