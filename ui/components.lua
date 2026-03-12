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


function M.buildButtons(ctx, layout)
  local state = ctx.state
  local C = ctx.C
  local addButton = ctx.addButton
  local addRowButton = ctx.addRowButton
  local drawBigButton = ctx.drawBigButton
  local actions = ctx.actions

  local function buildMonitorSelectionButtons()
    local boxW = ctx.clamp(layout.width - 6, 24, 60)
    local x = math.floor((layout.width - boxW) / 2) + 1
    local y0 = layout.top + 4
    for i = 1, 4 do
      local rowY = y0 + (i - 1) * 3
      local rowAction = function() actions.selectMonitorByIndex(i) end
      addRowButton("mrow" .. i, x + 1, rowY, boxW - 2, 2, "", C.panelDark, C.text, rowAction)
      addButton("m" .. i, x + boxW - 8, rowY, 6, 2, tostring(i), C.btnAction, nil, rowAction, { kind = "small" })
    end
    addButton("cancelMon", x + 1, layout.bottom - 4, boxW - 2, 4, "ANNULER", C.bad, nil, actions.stopMonitorSelection)
  end

  local function buildNavigationButtons(ctrl, bx, bw)
    local navW = math.max(5, math.floor(bw / 6))
    addButton("viewSup", bx, ctrl.y + 1, navW, 4, "SUP", state.currentView == "supervision" and C.btnOn or C.panelMid, nil, function() actions.setView("supervision") end)
    addButton("viewDiag", bx + navW, ctrl.y + 1, navW, 4, "DIAG", state.currentView == "diagnostic" and C.btnOn or C.panelMid, nil, function() actions.setView("diagnostic") end)
    addButton("viewMan", bx + (navW * 2), ctrl.y + 1, navW, 4, "MAN", state.currentView == "manual" and C.btnOn or C.panelMid, nil, function() actions.setView("manual") end)
    addButton("viewInd", bx + (navW * 3), ctrl.y + 1, navW, 4, "IND", state.currentView == "induction" and C.btnOn or C.panelMid, nil, function() actions.setView("induction") end)
    addButton("viewUpd", bx + (navW * 4), ctrl.y + 1, navW, 4, "UPD", state.currentView == "update" and C.btnOn or C.panelMid, nil, function() actions.setView("update") end)
    addButton("viewSetup", bx + (navW * 5), ctrl.y + 1, bw - (navW * 5), 4, "SET", state.currentView == "setup" and C.btnOn or C.panelMid, nil, function() actions.setView("setup") end)
  end

  local function buildRefreshButton(ctrl, bx, bw)
    addButton("refreshNow", bx, ctrl.y + 6, bw, 4, "REFRESH", C.btnAction, nil, actions.refreshNow)
  end

  local function buildUpdateButtons(bx, bw, baseY)
    addButton("updCheck", bx, baseY, bw, 4, "CHECK", C.btnAction, nil, actions.checkForUpdate)
    addButton("updApply", bx, baseY + 5, bw, 4, "UPDATE", state.update.available and C.warn or C.inactive, nil, actions.performUpdate)
    addButton("updDebug", bx, baseY + 10, bw, 4, state.debugHitboxes and "DEBUG ON" or "DEBUG OFF", state.debugHitboxes and C.info or C.panelMid, nil, actions.toggleDebugHitboxes)
    local splitGap = 1
    local splitW = math.max(8, math.floor((bw - splitGap) / 2))
    addButton("updRollback", bx, baseY + 15, splitW, 4, "ROLLBACK", actions.hasRollback() and C.bad or C.inactive, nil, actions.rollbackUpdate)
    addButton("monitor", bx + splitW + splitGap, baseY + 15, bw - splitW - splitGap, 4, "MONITOR", C.btnWarn, nil, actions.startMonitorSelection)
  end

  local function buildManualButtons(bx, bw, baseY)
    drawBigButton("manualStart", bx, baseY, bw, "DEMARRAGE", actions.canIgnite() and C.warn or C.inactive, actions.startReactorSequence)
    drawBigButton("manualStop", bx, baseY + 7, bw, "ARRET", C.bad, actions.stopManualReactor)
    addButton("manualT", bx, baseY + 14, bw, 5, "T LOCK", state.tOpen and C.tritium or C.inactive, nil, actions.toggleTritium)
    addButton("manualDT", bx, baseY + 20, bw, 5, "DT LOCK", state.dtOpen and C.dtFuel or C.inactive, nil, actions.toggleDTFuel)
    addButton("manualD", bx, baseY + 26, bw, 5, "D LOCK", state.dOpen and C.deuterium or C.inactive, nil, actions.toggleDeuterium)
    addButton("manualPulse", bx, baseY + 32, bw, 5, "PULSE LAS", C.warn, nil, actions.fireLaser)
    addButton("monitor", bx, baseY + 38, bw, 4, "MONITOR", C.btnWarn, nil, actions.startMonitorSelection)
    addButton("manualBack", bx, baseY + 43, bw, 4, "RETOUR SUP", C.btnAction, nil, function() actions.setView("supervision") end)
  end

  local function buildSetupButtons(ctrl, bx, bw)
    local by = ctrl.y + 6
    local half = math.max(6, math.floor((bw - 1) / 2))
    addButton("setupTestMon", bx, by, half, 3, "TEST MON", C.btnAction, nil, function() actions.runSetupTest("MONITOR") end)
    addButton("setupTestLas", bx + half + 1, by, bw - half - 1, 3, "TEST LAS", C.btnAction, nil, function() actions.runSetupTest("LAS") end)
    addButton("setupTestT", bx, by + 4, half, 3, "TEST T", C.btnAction, nil, function() actions.runSetupTest("T") end)
    addButton("setupTestD", bx + half + 1, by + 4, bw - half - 1, 3, "TEST D", C.btnAction, nil, function() actions.runSetupTest("D") end)
    addButton("setupTestRT", bx, by + 8, half, 3, "TEST R-T", C.btnAction, nil, function() actions.runSetupTest("READER T") end)
    addButton("setupTestRD", bx + half + 1, by + 8, bw - half - 1, 3, "TEST R-D", C.btnAction, nil, function() actions.runSetupTest("READER D") end)
    addButton("setupTestInd", bx, by + 12, half, 3, "TEST IND", C.btnAction, nil, function() actions.runSetupTest("INDUCTION") end)
    addButton("setupTestLaser", bx + half + 1, by + 12, bw - half - 1, 3, "TEST LASER", C.btnAction, nil, function() actions.runSetupTest("LASER") end)
    addButton("setupBindMon", bx, by + 16, half, 3, "BIND MON", C.panelMid, nil, function() actions.setupStartRebind("monitor") end)
    addButton("setupBindReactor", bx + half + 1, by + 16, bw - half - 1, 3, "BIND CTRL", C.panelMid, nil, function() actions.setupStartRebind("reactorController") end)
    addButton("setupBindLogic", bx, by + 20, half, 3, "BIND LOGIC", C.panelMid, nil, function() actions.setupStartRebind("logicAdapter") end)
    addButton("setupBindLaser", bx + half + 1, by + 20, bw - half - 1, 3, "BIND LASER", C.panelMid, nil, function() actions.setupStartRebind("laser") end)
    addButton("setupBindInd", bx, by + 24, half, 3, "BIND IND", C.panelMid, nil, function() actions.setupStartRebind("induction") end)
    addButton("setupBindRelayL", bx + half + 1, by + 24, bw - half - 1, 3, "BIND R-LAS", C.panelMid, nil, function() actions.setupStartRebind("relayLaser") end)
    addButton("setupBindRelayT", bx, by + 28, half, 3, "BIND R-T", C.panelMid, nil, function() actions.setupStartRebind("relayTritium") end)
    addButton("setupBindRelayD", bx + half + 1, by + 28, bw - half - 1, 3, "BIND R-D", C.panelMid, nil, function() actions.setupStartRebind("relayDeuterium") end)
    addButton("setupBindReaderT", bx, by + 32, half, 3, "BIND RD-T", C.panelMid, nil, function() actions.setupStartRebind("readerTritium") end)
    addButton("setupBindReaderD", bx + half + 1, by + 32, bw - half - 1, 3, "BIND RD-D", C.panelMid, nil, function() actions.setupStartRebind("readerDeuterium") end)
    addButton("setupBindReaderA", bx, by + 36, bw, 3, "BIND RD-AUX", C.panelMid, nil, function() actions.setupStartRebind("readerAux") end)
    addButton("setupSave", bx, by + 40, half, 3, "SAVE CONFIG", C.ok, nil, actions.saveSetupConfig)
    addButton("setupInstaller", bx + half + 1, by + 40, bw - half - 1, 3, "RUN INSTALLER", C.warn, nil, actions.runInstallerFromSetup)

    if state.setup.rebindRole and #state.setup.rebindCandidates > 0 then
      local listY = ctrl.y + 6
      for i = 1, math.min(3, #state.setup.rebindCandidates) do
        local idx = i
        local name = state.setup.rebindCandidates[i]
        addButton("setupSel" .. i, bx, listY + ((i - 1) * 4), bw, 3, ctx.shortText("-> " .. name, bw - 2), C.info, nil, function() actions.setupApplySelection(idx) end)
      end
    end
  end

  local function buildSupervisorCoreButtons(ctrl, bx, by, bw, bh, bGap)
    addButton("master", bx, by, bw, bh, "MASTER", state.autoMaster and C.btnOn or C.btnOff, nil, actions.toggleMaster)
    addButton("fusion", bx, by + (bh + bGap), bw, bh, "FUSION", state.fusionAuto and C.btnOn or C.btnOff, nil, actions.toggleFusion)
    addButton("charge", bx, by + (bh + bGap) * 2, bw, bh, "CHARGE", state.chargeAuto and C.btnOn or C.btnOff, nil, actions.toggleCharge)
    drawBigButton("demarrage", bx, by + (bh + bGap) * 3, bw, "DEMARRAGE", actions.canIgnite() and C.warn or C.inactive, actions.startReactorSequence)
    addButton("monitor", bx, by + (bh + bGap) * 3 + 7, bw, 4, "MONITOR", C.btnWarn, nil, actions.startMonitorSelection)
    addButton("arret", bx, by + (bh + bGap) * 3 + 12, bw, 4, "ARRET", C.bad, nil, actions.stopRequested)

    local center = layout.center
    if not center or layout.mode == "compact" or state.currentView ~= "supervision" then return end

    local innerX = center.x + 2
    local innerW = center.w - 4
    local barY = center.y + center.h - 5
    local btnH = 5
    local gap = 3
    local btnW = math.max(10, math.floor((innerW - (gap * 2)) / 3))
    local totalW = (btnW * 3) + (gap * 2)
    local startX = innerX + math.max(0, math.floor((innerW - totalW) / 2))

    addButton("lock_t", startX, barY, btnW, btnH, "T LOCK", state.tOpen and C.tritium or C.inactive, C.btnText, actions.toggleTritium)
    addButton("lock_dt", startX + btnW + gap, barY, btnW, btnH, "DT LOCK", state.dtOpen and C.dtFuel or C.inactive, C.btnText, actions.toggleDTFuel)
    addButton("lock_d", startX + (btnW + gap) * 2, barY, btnW, btnH, "D LOCK", state.dOpen and C.deuterium or C.inactive, C.btnText, actions.toggleDeuterium)
  end

  if state.choosingMonitor then
    buildMonitorSelectionButtons()
    return
  end

  local ctrl = layout.right or layout.left
  local bx = ctrl.x + 2
  local bw = math.max(12, ctrl.w - 4)
  local by = ctrl.y + 10
  local bh = (layout.mode == "compact") and 4 or 5
  local bGap = 2

  buildNavigationButtons(ctrl, bx, bw)
  buildRefreshButton(ctrl, bx, bw)

  if state.currentView == "update" then
    buildUpdateButtons(bx, bw, by)
    return
  end

  if state.currentView == "setup" then
    buildSetupButtons(ctrl, bx, bw)
    return
  end

  if state.currentView == "diagnostic" or state.currentView == "induction" then
    drawBigButton("monitor", bx, ctrl.y + 12, bw, "MONITOR", C.btnWarn, actions.startMonitorSelection)
    return
  end

  if state.currentView == "manual" then
    buildManualButtons(bx, bw, by)
    return
  end

  buildSupervisorCoreButtons(ctrl, bx, by, bw, bh, bGap)
end

return M
