local M = {}

function M.writeAt(x, y, txt, tc, bc)
  if bc then term.setBackgroundColor(bc) end
  if tc then term.setTextColor(tc) end
  term.setCursorPos(x, y)
  term.write(txt)
end

function M.fillArea(x, y, w, h, bg)
  term.setBackgroundColor(bg)
  for yy = y, y + h - 1 do
    term.setCursorPos(x, yy)
    term.write(string.rep(" ", w))
  end
end

return M
