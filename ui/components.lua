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

function M.drawValueBlock(ctx, x, y, w, label, value, unit, tone)
  local C = ctx.C
  if w < 12 then
    ctx.drawKeyValue(x, y, label, tostring(value), C.dim, tone or C.text, w - 3)
    return
  end
  ctx.writeAt(x, y, ctx.shortText(string.upper(label), w - 1), C.dim, C.panelDark)
  local valText = tostring(value or "N/A")
  if unit and unit ~= "" then
    valText = valText .. " " .. unit
  end
  ctx.writeAt(x, y + 1, ctx.shortText(valText, w - 1), tone or C.text, C.panel)
end

function M.drawStateBlock(ctx, x, y, w, label, stateText)
  local C = ctx.C
  local tone = M.statusColor(stateText, C)
  ctx.writeAt(x, y, ctx.shortText(string.upper(label), w - 1), C.dim, C.panelDark)
  ctx.writeAt(x, y + 1, " " .. ctx.shortText(string.upper(tostring(stateText or "UNKNOWN")), w - 3) .. " ", C.text, tone)
end

function M.drawIoPanel(ctx, x, y, w, h)
  if h < 4 then return end
  local C = ctx.C
  local state = ctx.state
  local hw = ctx.hw

  ctx.drawBox(x, y, w, h, "REAL I/O", C.border)
  local rx = x + 2
  local ry = y + 1
  local maxY = y + h - 2
  ctx.writeAt(rx, ry, "OUT", C.info, C.panelDark)
  if ry + 1 <= maxY then ctx.drawKeyValue(rx, ry + 1, "LAS", ctx.yesno(state.laserLineOn), C.dim, state.laserLineOn and C.ok or C.warn, w - 6) end
  if ry + 2 <= maxY then ctx.drawKeyValue(rx, ry + 2, "T", ctx.yesno(state.tOpen), C.dim, state.tOpen and C.tritium or C.warn, w - 6) end
  if ry + 3 <= maxY then ctx.drawKeyValue(rx, ry + 3, "D", ctx.yesno(state.dOpen), C.dim, state.dOpen and C.deuterium or C.warn, w - 6) end
  if ry + 4 <= maxY then ctx.drawKeyValue(rx, ry + 4, "DT", ctx.yesno(state.dtOpen), C.dim, state.dtOpen and C.dtFuel or C.warn, w - 6) end

  if ry + 5 <= maxY then ctx.writeAt(rx, ry + 5, "SENSE", C.info, C.panelDark) end
  if ry + 6 <= maxY then ctx.drawKeyValue(rx, ry + 6, "R-T", hw.readerRoles.tritium and "OK" or "FAIL", C.dim, hw.readerRoles.tritium and C.ok or C.bad, w - 6) end
  if ry + 7 <= maxY then ctx.drawKeyValue(rx, ry + 7, "R-D", hw.readerRoles.deuterium and "OK" or "FAIL", C.dim, hw.readerRoles.deuterium and C.ok or C.bad, w - 6) end
  if ry + 8 <= maxY then ctx.drawKeyValue(rx, ry + 8, "R-AUX", hw.readerRoles.inventory and "OK" or "FAIL", C.dim, hw.readerRoles.inventory and C.ok or C.bad, w - 6) end
end

function M.drawStatusPanel(ctx, panel)
  local C = ctx.C
  local state = ctx.state

  ctx.drawBox(panel.x, panel.y, panel.w, panel.h, "REACTOR STATUS", C.border)
  local x = panel.x + 2
  local y = panel.y + 1
  local w = panel.w - 3

  local b1h = ctx.clamp(math.floor(panel.h * 0.23), 5, 7)
  local b2h = ctx.clamp(math.floor(panel.h * 0.22), 5, 7)
  local b3h = ctx.clamp(math.floor(panel.h * 0.26), 6, 8)
  local b4h = panel.h - b1h - b2h - b3h - 3

  ctx.drawBox(x, y, w, b1h, "PHASE", C.borderDim)
  local phase = ctx.reactorPhase()
  ctx.drawBadge(x + 2, y + 1, "STATE", phase, ctx.phaseColor(phase))
  ctx.drawBadge(x + 2, y + 2, "CORE", state.reactorPresent and (state.reactorFormed and "FORMED" or "UNFORMED") or "OFFLINE")
  if b1h > 5 then ctx.drawKeyValue(x + 2, y + 3, "Temp P", ctx.fmt(state.plasmaTemp), C.dim, C.info, w - 6) end

  local y2 = y + b1h
  if state.ignition then
    ctx.drawBox(x, y2, w, b2h, "RUNTIME FUEL", C.borderDim)
    local mode = ctx.getRuntimeFuelMode()
    local flowOk = ctx.isRuntimeFuelOk()
    local rows = {
      { "Fuel Mode", mode, mode == "STARVED" and C.bad or C.ok },
      { "Fuel Flow", flowOk and "OK" or "NO FLOW", flowOk and C.ok or C.bad },
      { "D Line", state.dOpen and "OPEN" or "CLOSED", state.dOpen and C.deuterium or C.warn },
      { "T Line", state.tOpen and "OPEN" or "CLOSED", state.tOpen and C.tritium or C.warn },
      { "DT Line", state.dtOpen and "OPEN" or "CLOSED", state.dtOpen and C.dtFuel or C.warn },
    }
    for i = 1, math.min(#rows, b2h - 2) do
      local r = rows[i]
      ctx.drawKeyValue(x + 2, y2 + i, r[1], r[2], C.dim, r[3], w - 6)
    end
  else
    ctx.drawBox(x, y2, w, b2h, "IGNITION CHECK", C.borderDim)
    local checklist = state.ignitionChecklist or {}
    for i = 1, math.min(#checklist, b2h - 2) do
      local item = checklist[i]
      local tone = item.ok and C.ok or (item.wait and C.warn or C.bad)
      local mark = item.ok and "[OK]" or (item.wait and "[...]" or "[NO]")
      ctx.writeAt(x + 2, y2 + i, ctx.shortText(mark .. " " .. item.key, w - 4), tone, C.panelDark)
    end
  end

  local y3 = y2 + b2h
  ctx.drawBox(x, y3, w, b3h, "SAFETY", C.borderDim)
  local warnings = state.safetyWarnings or {}
  if #warnings == 0 then
    ctx.writeAt(x + 2, y3 + 1, "NO CRITICAL WARNING", C.ok, C.panelDark)
  else
    for i = 1, math.min(#warnings, b3h - 2) do
      local blink = (state.tick % 6 < 3)
      local tone = (i == 1 and blink) and C.bad or C.warn
      ctx.writeAt(x + 2, y3 + i, ctx.shortText("- " .. warnings[i], w - 4), tone, C.panelDark)
    end
  end

  local y4 = y3 + b3h
  ctx.drawBox(x, y4, w, b4h, "EVENT LOG", C.borderDim)
  local logs = state.eventLog or {}
  for i = 1, math.min(#logs, b4h - 2) do
    ctx.writeAt(x + 2, y4 + i, ctx.shortText(logs[i], w - 4), C.info, C.panelDark)
  end
end

function M.drawUpdateInfoPanel(ctx, infoPanel)
  local C = ctx.C
  local state = ctx.state

  ctx.drawBox(infoPanel.x, infoPanel.y, infoPanel.w, infoPanel.h, "UPDATE CENTER", C.info)
  local x = infoPanel.x + 2
  local w = infoPanel.w - 4

  ctx.drawBox(x - 1, infoPanel.y + 1, w, 7, "VERSIONS", C.borderDim)
  ctx.drawKeyValue(x, infoPanel.y + 2, "Local", state.update.localVersion, C.dim, C.ok, w - 4)
  ctx.drawKeyValue(x, infoPanel.y + 3, "Remote", state.update.remoteVersion, C.dim, C.info, w - 4)
  ctx.drawKeyValue(x, infoPanel.y + 4, "Manifest", state.update.manifestLoaded and "LOADED" or "MISSING", C.dim, state.update.manifestLoaded and C.ok or C.warn, w - 4)
  ctx.drawKeyValue(x, infoPanel.y + 5, "Files", tostring(state.update.filesToUpdate or 0), C.dim, C.info, w - 4)
  ctx.drawKeyValue(x, infoPanel.y + 6, "Status", state.update.status, C.dim, ctx.statusColor(state.update.available and "WARN" or "OK", C), w - 4)

  ctx.drawBox(x - 1, infoPanel.y + 8, w, 6, "NETWORK", C.borderDim)
  ctx.drawKeyValue(x, infoPanel.y + 9, "HTTP", state.update.httpStatus, C.dim, state.update.httpStatus == "OK" and C.ok or C.warn, w - 4)
  ctx.drawKeyValue(x, infoPanel.y + 10, "Enabled", ctx.UPDATE_ENABLED and "YES" or "NO", C.dim, ctx.UPDATE_ENABLED and C.ok or C.bad, w - 4)
  ctx.drawKeyValue(x, infoPanel.y + 11, "Error", state.update.lastError ~= "" and state.update.lastError or "None", C.dim, state.update.lastError ~= "" and C.bad or C.info, w - 4)

  local resultY = infoPanel.y + 14
  local resultH = math.max(8, infoPanel.h - 15)
  ctx.drawBox(x - 1, resultY, w, resultH, "RESULT", C.borderDim)
  ctx.writeAt(x, resultY + 1, ctx.shortText("Check: " .. tostring(state.update.lastCheckResult or "Never"), w - 3), C.info, C.panelDark)
  ctx.writeAt(x, resultY + 2, ctx.shortText("Update: " .. tostring(state.update.lastApplyResult or "Never"), w - 3), C.info, C.panelDark)
  ctx.writeAt(x, resultY + 3, ctx.shortText("Manifest err: " .. (state.update.lastManifestError ~= "" and state.update.lastManifestError or "None"), w - 3), C.dim, C.panelDark)
  local hasBackup = false
  if type(ctx.rollbackTargetList) == "function" and type(ctx.hasAnyRollbackBackup) == "function" then
    hasBackup = ctx.hasAnyRollbackBackup(ctx.rollbackTargetList(true))
  end
  ctx.writeAt(x, resultY + 4, ctx.shortText("Backup set: " .. (hasBackup and "AVAILABLE" or "MISSING"), w - 3), hasBackup and C.ok or C.warn, C.panelDark)
  ctx.writeAt(x, resultY + 5, ctx.shortText("Temp dir: " .. (ctx.fs.exists(ctx.UPDATE_TEMP_DIR) and "READY" or "EMPTY"), w - 3), C.dim, C.panelDark)
  ctx.writeAt(x, resultY + 6, ctx.shortText("Restart: " .. (state.update.restartRequired and "REQUIRED" or "NOT REQUIRED"), w - 3), state.update.restartRequired and C.warn or C.ok, C.panelDark)
end

return M
