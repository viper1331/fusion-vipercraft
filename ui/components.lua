local M = {}

function M.statusColor(status, C)
  if status == "RUN" or status == "READY" or status == "OK" then return C.ok end
  if status == "WARN" then return C.warn end
  if status == "ALERT" or status == "STOP" or status == "BAD" then return C.bad end
  return C.info
end

function M.shortText(txt, maxLen)
  txt = tostring(txt or "")
  if #txt <= maxLen then return txt end
  if maxLen <= 1 then return txt:sub(1, maxLen) end
  return txt:sub(1, maxLen - 1) .. "…"
end

return M
