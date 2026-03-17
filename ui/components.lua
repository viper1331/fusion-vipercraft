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
  local sectionGap = 1
  local b4h = panel.h - b1h - b2h - b3h - (sectionGap * 3) - 3
  if b4h < 4 then
    b4h = 4
  end

  ctx.drawBox(x, y, w, b1h, "PHASE", C.borderDim)
  local phase = ctx.reactorPhase()
  ctx.drawBadge(x + 2, y + 1, "STATE", phase, ctx.phaseColor(phase))
  ctx.drawBadge(x + 2, y + 2, "CORE", state.reactorPresent and (state.reactorFormed and "FORMED" or "UNFORMED") or "OFFLINE")
  if b1h > 5 then ctx.drawKeyValue(x + 2, y + 3, "Temp P", ctx.fmt(state.plasmaTemp), C.dim, C.info, w - 6) end

  local y2 = y + b1h + sectionGap
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

  local y3 = y2 + b2h + sectionGap
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

  local y4 = y3 + b3h + sectionGap
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
    addButton("cancelMon", x + 1, layout.bottom - 4, boxW - 2, 3, "ANNULER", C.bad, nil, actions.stopMonitorSelection)
  end

  if state.choosingMonitor then
    buildMonitorSelectionButtons()
    return
  end

  local ctrl = layout.right or layout.left
  local bounds = type(state.controlBounds) == "table" and state.controlBounds or nil
  local bx = bounds and bounds.x or (ctrl.x + 2)
  local bw = bounds and math.max(10, bounds.w) or math.max(12, ctrl.w - 4)
  local y = bounds and bounds.y or (ctrl.y + 1)
  local maxY = bounds and (bounds.y + bounds.h - 1) or (layout.bottom - 1)
  local gapY = 1

  local function addGridRow(items, rowH, gapX)
    if #items == 0 then return end
    if y + rowH - 1 > maxY then return end
    gapX = gapX or 1
    local totalGap = gapX * (#items - 1)
    local available = bw - totalGap
    if available < (#items * 3) then
      gapX = 0
      totalGap = 0
      available = bw
    end
    local cell = math.max(3, math.floor(available / #items))
    local used = (cell * #items) + totalGap
    local x = bx + math.max(0, math.floor((bw - used) / 2))
    for i, item in ipairs(items) do
      local wBtn = cell
      if i == #items then
        wBtn = math.max(3, (bx + bw) - x)
      end
      addButton(item.id, x, y, wBtn, rowH, item.label, item.bg, item.fg, item.action, { hitPadX = 0, hitPadY = 0 })
      x = x + wBtn + gapX
    end
    y = y + rowH + gapY
  end

  local function buildNavigationButtons()
    addGridRow({
      { id = "viewSup", label = "SUP", bg = state.currentView == "supervision" and C.btnOn or C.panelMid, action = function() actions.setView("supervision") end },
      { id = "viewDiag", label = "DIAG", bg = state.currentView == "diagnostic" and C.btnOn or C.panelMid, action = function() actions.setView("diagnostic") end },
      { id = "viewMan", label = "MAN", bg = state.currentView == "manual" and C.btnOn or C.panelMid, action = function() actions.setView("manual") end },
      { id = "viewInd", label = "IND", bg = state.currentView == "induction" and C.btnOn or C.panelMid, action = function() actions.setView("induction") end },
    }, 3, 1)
    addGridRow({
      { id = "viewUpd", label = "UPD", bg = state.currentView == "update" and C.btnOn or C.panelMid, action = function() actions.setView("update") end },
      { id = "viewCfg", label = "CFG", bg = state.currentView == "config" and C.btnOn or C.panelMid, action = function() actions.setView("config") end },
      { id = "viewSetup", label = "SET", bg = state.currentView == "setup" and C.btnOn or C.panelMid, action = function() actions.setView("setup") end },
    }, 3, 1)
  end

  local function buildRefreshButton()
    addGridRow({
      { id = "refreshNow", label = "REFRESH", bg = C.btnAction, action = actions.refreshNow },
    }, 3, 0)
  end

  local function buildUpdateButtons()
    addGridRow({
      { id = "updCheck", label = "CHECK", bg = C.btnAction, action = actions.checkForUpdate },
    }, 3, 0)
    addGridRow({
      { id = "updApply", label = "UPDATE", bg = state.update.available and C.warn or C.inactive, action = actions.performUpdate },
    }, 3, 0)
    if state.update.restartRequired then
      addGridRow({
        { id = "updRestart", label = "RESTART", bg = C.ok, action = actions.restartProgram },
      }, 3, 0)
    end
    addGridRow({
      { id = "updDebug", label = state.debugHitboxes and "DEBUG ON" or "DEBUG OFF", bg = state.debugHitboxes and C.info or C.panelMid, action = actions.toggleDebugHitboxes },
    }, 3, 0)
    addGridRow({
      { id = "updRollback", label = "ROLLBACK", bg = actions.hasRollback() and C.bad or C.inactive, action = actions.rollbackUpdate },
      { id = "monitor", label = "MONITOR", bg = C.btnWarn, action = actions.startMonitorSelection },
    }, 3, 1)
  end

  local function buildManualButtons()
    addGridRow({
      { id = "manualStart", label = "DEMARRAGE", bg = actions.canIgnite() and C.warn or C.inactive, action = actions.startReactorSequence },
    }, 4, 0)
    addGridRow({
      { id = "manualStop", label = "ARRET", bg = C.bad, action = actions.stopManualReactor },
    }, 4, 0)
    addGridRow({
      { id = "manualT", label = "T LOCK", bg = state.tOpen and C.tritium or C.inactive, action = actions.toggleTritium },
      { id = "manualDT", label = "DT LOCK", bg = state.dtOpen and C.dtFuel or C.inactive, action = actions.toggleDTFuel },
      { id = "manualD", label = "D LOCK", bg = state.dOpen and C.deuterium or C.inactive, action = actions.toggleDeuterium },
    }, 3, 1)
    addGridRow({
      { id = "manualPulse", label = "PULSE LAS", bg = C.warn, action = actions.fireLaser },
    }, 3, 0)
    addGridRow({
      { id = "monitor", label = "MONITOR", bg = C.btnWarn, action = actions.startMonitorSelection },
      { id = "manualBack", label = "RETOUR SUP", bg = C.btnAction, action = function() actions.setView("supervision") end },
    }, 3, 1)
  end

  local function buildSetupButtons()
    local setupState = type(state.setup) == "table" and state.setup or {}
    local rebindCandidates = type(setupState.rebindCandidates) == "table" and setupState.rebindCandidates or {}

    local function addPair(idA, labelA, bgA, actionA, idB, labelB, bgB, actionB)
      addGridRow({
        { id = idA, label = labelA, bg = bgA, action = actionA },
        { id = idB, label = labelB, bg = bgB, action = actionB },
      }, 3, 1)
    end

    if setupState.rebindRole and #rebindCandidates > 0 then
      for i = 1, math.min(3, #rebindCandidates) do
        local idx = i
        local name = rebindCandidates[i]
        addGridRow({
          { id = "setupSel" .. i, label = ctx.shortText("-> " .. name, bw - 2), bg = C.info, action = function() actions.setupApplySelection(idx) end },
        }, 3, 0)
      end
    end

    addPair("setupTestMon", "TEST MON", C.btnAction, function() actions.runSetupTest("MONITOR") end, "setupTestLas", "TEST LAS", C.btnAction, function() actions.runSetupTest("LAS") end)
    addPair("setupTestT", "TEST T", C.btnAction, function() actions.runSetupTest("T") end, "setupTestD", "TEST D", C.btnAction, function() actions.runSetupTest("D") end)
    addPair("setupTestRT", "TEST R-T", C.btnAction, function() actions.runSetupTest("READER T") end, "setupTestRD", "TEST R-D", C.btnAction, function() actions.runSetupTest("READER D") end)
    addPair("setupTestInd", "TEST IND", C.btnAction, function() actions.runSetupTest("INDUCTION") end, "setupTestLaser", "TEST LASER", C.btnAction, function() actions.runSetupTest("LASER") end)
    addPair("setupBindMon", "BIND MON", C.panelMid, function() actions.setupStartRebind("monitor") end, "setupBindReactor", "BIND CTRL", C.panelMid, function() actions.setupStartRebind("reactorController") end)
    addPair("setupBindLogic", "BIND LOGIC", C.panelMid, function() actions.setupStartRebind("logicAdapter") end, "setupBindLaser", "BIND LASER", C.panelMid, function() actions.setupStartRebind("laser") end)
    addPair("setupBindInd", "BIND IND", C.panelMid, function() actions.setupStartRebind("induction") end, "setupBindRelayL", "BIND R-LAS", C.panelMid, function() actions.setupStartRebind("relayLaser") end)
    addPair("setupBindRelayT", "BIND R-T", C.panelMid, function() actions.setupStartRebind("relayTritium") end, "setupBindRelayD", "BIND R-D", C.panelMid, function() actions.setupStartRebind("relayDeuterium") end)
    addPair("setupBindReaderT", "BIND RD-T", C.panelMid, function() actions.setupStartRebind("readerTritium") end, "setupBindReaderD", "BIND RD-D", C.panelMid, function() actions.setupStartRebind("readerDeuterium") end)
    addGridRow({
      { id = "setupBindReaderA", label = "BIND RD-AUX", bg = C.panelMid, action = function() actions.setupStartRebind("readerAux") end },
    }, 3, 0)
    addPair("setupSave", "SAVE CONFIG", C.ok, actions.saveSetupConfig, "setupInstaller", "RUN INSTALLER", C.warn, actions.runInstallerFromSetup)
  end

  local function buildConfigButtons()
    local outputMode = "monitor"
    if type(state.setup) == "table" and type(state.setup.working) == "table" and type(state.setup.working.ui) == "table" then
      outputMode = string.lower(tostring(state.setup.working.ui.output or "monitor"))
    end
    if outputMode ~= "terminal" and outputMode ~= "both" and outputMode ~= "monitor" then
      outputMode = "monitor"
    end

    addGridRow({
      { id = "cfgUiDown", label = "UI -", bg = C.panelMid, action = function() actions.adjustDisplayScale(-0.1) end },
      { id = "cfgUiUp", label = "UI +", bg = C.btnAction, action = function() actions.adjustDisplayScale(0.1) end },
    }, 3, 1)
    addGridRow({
      { id = "cfgTextDown", label = "TXT -", bg = C.panelMid, action = function() actions.adjustTextScale(-0.5) end },
      { id = "cfgTextUp", label = "TXT +", bg = C.btnAction, action = function() actions.adjustTextScale(0.5) end },
    }, 3, 1)
    addGridRow({
      { id = "cfgOutTerm", label = "TERM", bg = outputMode == "terminal" and C.btnOn or C.panelMid, action = function() actions.setDisplayOutput("terminal") end },
      { id = "cfgOutMon", label = "MON", bg = outputMode == "monitor" and C.btnOn or C.panelMid, action = function() actions.setDisplayOutput("monitor") end },
      { id = "cfgOutBoth", label = "BOTH", bg = outputMode == "both" and C.btnOn or C.panelMid, action = function() actions.setDisplayOutput("both") end },
    }, 3, 1)
    addGridRow({
      { id = "cfgSave", label = "SAVE CONFIG", bg = C.ok, action = actions.saveSetupConfig },
      { id = "cfgReload", label = "RELOAD", bg = C.btnWarn, action = actions.reloadSetupConfig },
    }, 3, 1)
    addGridRow({
      { id = "monitor", label = "MONITOR", bg = C.btnWarn, action = actions.startMonitorSelection },
    }, 3, 0)
  end

  local function buildSupervisorCoreButtons()
    addGridRow({
      { id = "master", label = "MASTER", bg = state.autoMaster and C.btnOn or C.btnOff, action = actions.toggleMaster },
      { id = "fusion", label = "FUSION", bg = state.fusionAuto and C.btnOn or C.btnOff, action = actions.toggleFusion },
      { id = "charge", label = "CHARGE", bg = state.chargeAuto and C.btnOn or C.btnOff, action = actions.toggleCharge },
    }, 3, 1)
    if y + 4 <= maxY then
      drawBigButton("demarrage", bx, y, bw, "DEMARRAGE", actions.canIgnite() and C.warn or C.inactive, actions.startReactorSequence)
      y = y + 6
    end
    addGridRow({
      { id = "monitor", label = "MONITOR", bg = C.btnWarn, action = actions.startMonitorSelection },
      { id = "arret", label = "ARRET", bg = C.bad, action = actions.stopRequested },
    }, 3, 1)

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

  buildNavigationButtons()
  buildRefreshButton()

  if state.currentView == "update" then
    buildUpdateButtons()
    return
  end

  if state.currentView == "setup" then
    buildSetupButtons()
    return
  end

  if state.currentView == "config" then
    buildConfigButtons()
    return
  end

  if state.currentView == "diagnostic" or state.currentView == "induction" then
    addGridRow({
      { id = "monitor", label = "MONITOR", bg = C.btnWarn, action = actions.startMonitorSelection },
    }, 4, 0)
    return
  end

  if state.currentView == "manual" then
    buildManualButtons()
    return
  end

  buildSupervisorCoreButtons()
end

return M
