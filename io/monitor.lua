local M = {}

function M.setupMonitor(nativeTerm, hw, CFG, C)
  local outputMode = string.lower(tostring((CFG and CFG.displayOutput) or "monitor"))

  term.redirect(nativeTerm)
  if hw.monitor then
    pcall(hw.monitor.setTextScale, CFG.monitorScale)
    pcall(hw.monitor.setBackgroundColor, C.bg)
    pcall(hw.monitor.setTextColor, C.text)

    if outputMode == "monitor" then
      term.redirect(hw.monitor)
    end
  end
  term.setCursorBlink(false)
end

return M
