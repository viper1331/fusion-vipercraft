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
  if maxLen <= 0 then return "" end
  return txt:sub(1, maxLen)
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
  local laserState = tostring(state.laserState or "ABSENT")
  local laserStatus = tostring(state.laserStatusText or laserState)
  local laserStateTone = C.dim
  if laserState == "READY" then
    laserStateTone = C.ok
  elseif laserState == "CHARGING" or laserState == "INSUFFICIENT" then
    laserStateTone = C.warn
  elseif laserState == "ABSENT" then
    laserStateTone = C.bad
  end

  ctx.writeAt(rx, ry, "OUT", C.info, C.panelDark)
  if ry + 1 <= maxY then ctx.drawKeyValue(rx, ry + 1, "LAS OUT", ctx.yesno(state.laserLineOn), C.dim, state.laserLineOn and C.ok or C.warn, w - 6) end
  if ry + 2 <= maxY then ctx.drawKeyValue(rx, ry + 2, "LAS ST", laserStatus, C.dim, laserStateTone, w - 6) end
  if ry + 3 <= maxY then ctx.drawKeyValue(rx, ry + 3, "T", ctx.yesno(state.tOpen), C.dim, state.tOpen and C.tritium or C.warn, w - 6) end
  if ry + 4 <= maxY then ctx.drawKeyValue(rx, ry + 4, "D", ctx.yesno(state.dOpen), C.dim, state.dOpen and C.deuterium or C.warn, w - 6) end
  if ry + 5 <= maxY then ctx.drawKeyValue(rx, ry + 5, "DT", ctx.yesno(state.dtOpen), C.dim, state.dtOpen and C.dtFuel or C.warn, w - 6) end

  if ry + 6 <= maxY then ctx.writeAt(rx, ry + 6, "SENSE", C.info, C.panelDark) end
  if ry + 7 <= maxY then ctx.drawKeyValue(rx, ry + 7, "R-T", hw.readerRoles.tritium and "OK" or "FAIL", C.dim, hw.readerRoles.tritium and C.ok or C.bad, w - 6) end
  if ry + 8 <= maxY then ctx.drawKeyValue(rx, ry + 8, "R-D", hw.readerRoles.deuterium and "OK" or "FAIL", C.dim, hw.readerRoles.deuterium and C.ok or C.bad, w - 6) end
  if ry + 9 <= maxY then ctx.drawKeyValue(rx, ry + 9, "R-AUX", hw.readerRoles.inventory and "OK" or "FAIL", C.dim, hw.readerRoles.inventory and C.ok or C.bad, w - 6) end
end

function M.drawStatusPanel(ctx, panel)
  local C = ctx.C
  local state = ctx.state

  ctx.drawBox(panel.x, panel.y, panel.w, panel.h, "REACTOR STATUS", C.border)
  local x = panel.x + 2
  local y = panel.y + 1
  local w = panel.w - 3
  local maxY = panel.y + panel.h - 2

  -- Mode compact pour petites surfaces: informations essentielles uniquement.
  if panel.h < 22 or panel.w < 20 then
    local phase = ctx.reactorPhase()
    local tempDisplay = ctx.fmt(state.plasmaTemp)
    if type(ctx.formatTemperature) == "function" then
      tempDisplay = ctx.formatTemperature(state.plasmaTemp, { compact = true, decimals = 2 })
    end
    local rows = {
      { "State", phase, ctx.phaseColor(phase) },
      { "Core", state.reactorPresent and (state.reactorFormed and "FORMED" or "UNFORMED") or "OFFLINE", state.reactorPresent and C.info or C.bad },
      { "Temp P", tempDisplay, C.info },
      { "Ign", state.ignition and "RUNNING" or "IDLE", state.ignition and C.ok or C.warn },
    }
    local ry = y + 1
    for i = 1, #rows do
      if ry > maxY then break end
      local row = rows[i]
      ctx.drawKeyValue(x, ry, row[1], row[2], C.dim, row[3], w - 2)
      ry = ry + 1
    end

    if ry <= maxY then
      local warnings = state.safetyWarnings or {}
      if #warnings > 0 then
        ctx.writeAt(x + 1, ry, ctx.shortText("- " .. tostring(warnings[1]), w - 3), C.warn, C.panelDark)
        ry = ry + 1
      end
    end
    if ry <= maxY then
      local logs = state.eventLog or {}
      local log = logs[1] or "No event"
      ctx.writeAt(x + 1, ry, ctx.shortText(log, w - 3), C.info, C.panelDark)
    end
    return
  end

  local b1h = ctx.clamp(math.floor(panel.h * 0.23), 5, 7)
  local b2h = ctx.clamp(math.floor(panel.h * 0.22), 5, 7)
  local b3h = ctx.clamp(math.floor(panel.h * 0.26), 6, 8)
  local sectionGap = 1
  local budget = panel.h - 2 - (sectionGap * 3)
  local b4h = budget - b1h - b2h - b3h
  while b4h < 4 do
    if b3h > 5 then
      b3h = b3h - 1
    elseif b2h > 5 then
      b2h = b2h - 1
    elseif b1h > 5 then
      b1h = b1h - 1
    else
      break
    end
    b4h = budget - b1h - b2h - b3h
  end
  if b4h < 4 then
    b4h = 4
  end

  ctx.drawBox(x, y, w, b1h, "PHASE", C.borderDim)
  local phase = ctx.reactorPhase()
  ctx.drawBadge(x + 2, y + 1, "STATE", phase, ctx.phaseColor(phase))
  ctx.drawBadge(x + 2, y + 2, "CORE", state.reactorPresent and (state.reactorFormed and "FORMED" or "UNFORMED") or "OFFLINE")
  if b1h > 5 then
    local tempDisplay = ctx.fmt(state.plasmaTemp)
    if type(ctx.formatTemperature) == "function" then
      tempDisplay = ctx.formatTemperature(state.plasmaTemp, { compact = true, decimals = 2 })
    end
    ctx.drawKeyValue(x + 2, y + 3, "Temp P", tempDisplay, C.dim, C.info, w - 6)
  end

  local y2 = y + b1h + sectionGap
  if state.ignition then
    ctx.drawBox(x, y2, w, b2h, "RUNTIME FUEL", C.borderDim)
    local mode = ctx.getRuntimeFuelMode()
    local flowOk = ctx.isRuntimeFuelOk()
    local injText = tostring(math.floor(tonumber(state.injectionRate) or 0))
    local flowMbT = tonumber(state.fuelFlowMbT) or 0
    local flowText = string.format("%.1f mB/t", flowMbT)
    local flowSource = tostring(state.fuelFlowSource or mode)
    local rows = {
      { "Fuel Mode", mode, mode == "STARVED" and C.bad or C.ok },
      { "Fuel Flow", flowText, flowMbT > 0 and C.ok or C.bad },
      { "Flow Src", flowSource, flowOk and C.info or C.warn },
      { "Injection", injText .. " mB/t", state.injectionWritable and C.info or C.warn },
      { "Hohlraum", state.hohlraumPresent and "PRESENT" or "MISSING", state.hohlraumPresent and C.ok or C.bad },
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
  local yTop = infoPanel.y + 1
  local yBottom = infoPanel.y + infoPanel.h - 2

  local function drawSection(title, rows, maxRowsWanted)
    if yTop > yBottom then return false end
    local available = yBottom - yTop + 1
    if available < 4 then return false end
    local rowCap = math.max(1, available - 2)
    local wanted = maxRowsWanted or #rows
    local rowsToDraw = math.min(#rows, wanted, rowCap)
    local h = rowsToDraw + 2
    ctx.drawBox(x - 1, yTop, w, h, title, C.borderDim)
    for i = 1, rowsToDraw do
      local row = rows[i]
      if row.kind == "kv" then
        ctx.drawKeyValue(x, yTop + i, row.key, row.value, C.dim, row.tone or C.info, w - 4)
      else
        ctx.writeAt(x, yTop + i, ctx.shortText(row.text, w - 3), row.tone or C.info, C.panelDark)
      end
    end
    yTop = yTop + h + 1
    return true
  end

  drawSection("VERSIONS", {
    { kind = "kv", key = "Local", value = state.update.localVersion, tone = C.ok },
    { kind = "kv", key = "Remote", value = state.update.remoteVersion, tone = C.info },
    { kind = "kv", key = "Manifest", value = state.update.manifestLoaded and "LOADED" or "MISSING", tone = state.update.manifestLoaded and C.ok or C.warn },
    { kind = "kv", key = "Files", value = tostring(state.update.filesToUpdate or 0), tone = C.info },
    { kind = "kv", key = "Status", value = state.update.status, tone = ctx.statusColor(state.update.available and "WARN" or "OK", C) },
  }, 5)

  drawSection("NETWORK", {
    { kind = "kv", key = "HTTP", value = state.update.httpStatus, tone = state.update.httpStatus == "OK" and C.ok or C.warn },
    { kind = "kv", key = "Enabled", value = ctx.UPDATE_ENABLED and "YES" or "NO", tone = ctx.UPDATE_ENABLED and C.ok or C.bad },
    { kind = "kv", key = "Error", value = state.update.lastError ~= "" and state.update.lastError or "None", tone = state.update.lastError ~= "" and C.bad or C.info },
  }, 3)

  local hasBackup = false
  if type(ctx.rollbackTargetList) == "function" and type(ctx.hasAnyRollbackBackup) == "function" then
    hasBackup = ctx.hasAnyRollbackBackup(ctx.rollbackTargetList(true))
  end
  drawSection("RESULT", {
    { kind = "txt", text = "Check: " .. tostring(state.update.lastCheckResult or "Never"), tone = C.info },
    { kind = "txt", text = "Update: " .. tostring(state.update.lastApplyResult or "Never"), tone = C.info },
    { kind = "txt", text = "Manifest err: " .. (state.update.lastManifestError ~= "" and state.update.lastManifestError or "None"), tone = C.dim },
    { kind = "txt", text = "Backup set: " .. (hasBackup and "AVAILABLE" or "MISSING"), tone = hasBackup and C.ok or C.warn },
    { kind = "txt", text = "Temp dir: " .. (ctx.fs.exists(ctx.UPDATE_TEMP_DIR) and "READY" or "EMPTY"), tone = C.dim },
    { kind = "txt", text = "Restart: " .. (state.update.restartRequired and "REQUIRED" or "NOT REQUIRED"), tone = state.update.restartRequired and C.warn or C.ok },
  })
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
    local monitorList = type(state.monitorList) == "table" and state.monitorList or {}
    local usableRows = math.max(1, math.floor((layout.bottom - y0 - 4) / 3))
    local visibleCount = math.min(#monitorList, usableRows, 9)
    for i = 1, visibleCount do
      local rowY = y0 + (i - 1) * 3
      local rowAction = function() actions.selectMonitorByIndex(i) end
      addRowButton("mrow" .. i, x + 1, rowY, boxW - 2, 2, "", C.panelDark, C.text, rowAction)
      addButton("m" .. i, x + boxW - 8, rowY, 6, 2, tostring(i), C.btnAction, nil, rowAction, { kind = "small" })
    end
    local cancelY = math.max(y0 + (visibleCount * 3), layout.bottom - 3)
    addButton("cancelMon", x + 1, cancelY, boxW - 2, 2, "ANNULER", C.bad, nil, actions.stopMonitorSelection)
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
    rowH = math.max(2, rowH or 2)
    gapX = gapX or 1

    local function minButtonWidth(item)
      local label = tostring(item.label or "")
      return math.max(3, #label + 2)
    end

    local index = 1
    while index <= #items do
      if y + rowH - 1 > maxY then return end

      local rowItems = {}
      local cursor = index
      local used = 0
      while cursor <= #items do
        local item = items[cursor]
        local wMin = minButtonWidth(item)
        local nextUsed = used + ((#rowItems > 0) and gapX or 0) + wMin
        if #rowItems > 0 and nextUsed > bw then
          break
        end
        rowItems[#rowItems + 1] = item
        used = nextUsed
        cursor = cursor + 1
        if used >= bw then break end
      end

      if #rowItems == 0 then
        rowItems[1] = items[index]
        cursor = index + 1
      end

      local minWidths = {}
      local minTotal = 0
      for i, item in ipairs(rowItems) do
        local wMin = minButtonWidth(item)
        minWidths[i] = wMin
        minTotal = minTotal + wMin
      end

      local totalGap = gapX * (#rowItems - 1)
      local rowWidth = minTotal + totalGap
      local extra = math.max(0, bw - rowWidth)
      local x = bx + math.max(0, math.floor((bw - math.min(rowWidth, bw)) / 2))

      if rowWidth > bw and #rowItems == 1 then
        minWidths[1] = bw
        totalGap = 0
        extra = 0
        x = bx
      end

      for i, item in ipairs(rowItems) do
        local stretch = 0
        if extra > 0 then
          local slots = #rowItems - i + 1
          stretch = math.floor(extra / slots)
          extra = extra - stretch
        end
        local wBtn = minWidths[i] + stretch
        if i == #rowItems then
          wBtn = math.max(minWidths[i], (bx + bw) - x)
        end
        addButton(item.id, x, y, wBtn, rowH, item.label, item.bg, item.fg, item.action, {
          hitPadX = 0,
          hitPadY = 0,
          disabled = item.disabled and true or false,
        })
        x = x + wBtn + gapX
      end

      y = y + rowH + gapY
      index = cursor
    end
  end

  local function buildNavigationButtons()
    addGridRow({
      { id = "viewSup", label = "SUP", bg = state.currentView == "supervision" and C.btnOn or C.panelMid, action = function() actions.setView("supervision") end },
      { id = "viewDiag", label = "DIAG", bg = state.currentView == "diagnostic" and C.btnOn or C.panelMid, action = function() actions.setView("diagnostic") end },
      { id = "viewMan", label = "MAN", bg = state.currentView == "manual" and C.btnOn or C.panelMid, action = function() actions.setView("manual") end },
      { id = "viewInd", label = "IND", bg = state.currentView == "induction" and C.btnOn or C.panelMid, action = function() actions.setView("induction") end },
    }, 2, 1)
    addGridRow({
      { id = "viewUpd", label = "UPD", bg = state.currentView == "update" and C.btnOn or C.panelMid, action = function() actions.setView("update") end },
      { id = "viewCfg", label = "CFG", bg = state.currentView == "config" and C.btnOn or C.panelMid, action = function() actions.setView("config") end },
      { id = "viewSetup", label = "SET", bg = state.currentView == "setup" and C.btnOn or C.panelMid, action = function() actions.setView("setup") end },
    }, 2, 1)
  end

  local function buildRefreshButton()
    addGridRow({
      { id = "refreshNow", label = "REFRESH", bg = C.btnAction, action = actions.refreshNow },
    }, 2, 0)
  end

  local function buildUpdateButtons()
    addGridRow({
      { id = "updCheck", label = "CHECK", bg = C.btnAction, action = actions.checkForUpdate },
    }, 2, 0)
    addGridRow({
      { id = "updApply", label = "UPDATE", bg = state.update.available and C.warn or C.inactive, action = actions.performUpdate },
    }, 2, 0)
    if state.update.restartRequired then
      addGridRow({
        { id = "updRestart", label = "RESTART", bg = C.ok, action = actions.restartProgram },
      }, 2, 0)
    end
    addGridRow({
      { id = "updDebug", label = state.debugHitboxes and "DEBUG ON" or "DEBUG OFF", bg = state.debugHitboxes and C.info or C.panelMid, action = actions.toggleDebugHitboxes },
    }, 2, 0)
    addGridRow({
      { id = "updRollback", label = "ROLLBACK", bg = actions.hasRollback() and C.bad or C.inactive, action = actions.rollbackUpdate },
      { id = "monitor", label = "MONITOR", bg = C.btnWarn, action = actions.startMonitorSelection },
    }, 2, 1)
  end

  local function buildManualButtons()
    local injAvailable = state.injectionWritable == true
    local injLabel = "INJ " .. tostring(math.floor(tonumber(state.injectionRate) or 0))

    addGridRow({
      { id = "manualStart", label = "DEMARRAGE", bg = actions.canIgnite() and C.warn or C.inactive, action = actions.startReactorSequence },
    }, 2, 0)
    addGridRow({
      { id = "manualStop", label = "ARRET", bg = C.bad, action = actions.stopManualReactor },
    }, 2, 0)
    addGridRow({
      { id = "manualT", label = "T LOCK", bg = state.tOpen and C.tritium or C.inactive, action = actions.toggleTritium },
      { id = "manualDT", label = "DT LOCK", bg = state.dtOpen and C.dtFuel or C.inactive, action = actions.toggleDTFuel },
      { id = "manualD", label = "D LOCK", bg = state.dOpen and C.deuterium or C.inactive, action = actions.toggleDeuterium },
    }, 2, 1)
    addGridRow({
      { id = "manualInjDown", label = "INJ -", bg = injAvailable and C.panelMid or C.inactive, action = function() actions.adjustInjectionRate(-1) end, disabled = not injAvailable },
      { id = "manualInjValue", label = injLabel, bg = C.panel, action = function() end, disabled = true },
      { id = "manualInjUp", label = "INJ +", bg = injAvailable and C.btnAction or C.inactive, action = function() actions.adjustInjectionRate(1) end, disabled = not injAvailable },
    }, 2, 1)
    addGridRow({
      { id = "manualPulse", label = "PULSE LAS", bg = C.warn, action = actions.fireLaser },
    }, 2, 0)
    addGridRow({
      { id = "monitor", label = "MONITOR", bg = C.btnWarn, action = actions.startMonitorSelection },
      { id = "manualBack", label = "RETOUR SUP", bg = C.btnAction, action = function() actions.setView("supervision") end },
    }, 2, 1)
  end

  local function buildSetupButtons()
    local setupState = type(state.setup) == "table" and state.setup or {}
    local rebindCandidates = type(setupState.rebindCandidates) == "table" and setupState.rebindCandidates or {}

    local function addPair(idA, labelA, bgA, actionA, idB, labelB, bgB, actionB)
      addGridRow({
        { id = idA, label = labelA, bg = bgA, action = actionA },
        { id = idB, label = labelB, bg = bgB, action = actionB },
      }, 2, 1)
    end

    if setupState.rebindRole and #rebindCandidates > 0 then
      for i = 1, math.min(3, #rebindCandidates) do
        local idx = i
        local name = rebindCandidates[i]
        addGridRow({
          { id = "setupSel" .. i, label = ctx.shortText("-> " .. name, bw - 2), bg = C.info, action = function() actions.setupApplySelection(idx) end },
        }, 2, 0)
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
    }, 2, 0)
    addPair("setupSave", "SAVE CONFIG", C.ok, actions.saveSetupConfig, "setupInstaller", "RUN INSTALLER", C.warn, actions.runInstallerFromSetup)
  end

  local function buildConfigButtons()
    local outputMode = "monitor"
    local energyUnit = "j"
    local laserCount = 1
    if type(state.setup) == "table" and type(state.setup.working) == "table" and type(state.setup.working.ui) == "table" then
      outputMode = string.lower(tostring(state.setup.working.ui.output or "monitor"))
      energyUnit = string.lower(tostring(state.setup.working.ui.energyUnit or "j"))
      laserCount = math.max(1, math.floor(tonumber(state.setup.working.ui.laserCount) or 1))
    end
    if outputMode ~= "terminal" and outputMode ~= "both" and outputMode ~= "monitor" then
      outputMode = "monitor"
    end
    if energyUnit ~= "j" and energyUnit ~= "fe" then
      energyUnit = "j"
    end

    addGridRow({
      { id = "cfgUiDown", label = "UI -", bg = C.panelMid, action = function() actions.adjustDisplayScale(-0.1) end },
      { id = "cfgUiUp", label = "UI +", bg = C.btnAction, action = function() actions.adjustDisplayScale(0.1) end },
    }, 2, 1)
    addGridRow({
      { id = "cfgTextDown", label = "TXT -", bg = C.panelMid, action = function() actions.adjustTextScale(-0.5) end },
      { id = "cfgTextUp", label = "TXT +", bg = C.btnAction, action = function() actions.adjustTextScale(0.5) end },
    }, 2, 1)
    addGridRow({
      { id = "cfgOutTerm", label = "TERM", bg = outputMode == "terminal" and C.btnOn or C.panelMid, action = function() actions.setDisplayOutput("terminal") end },
      { id = "cfgOutMon", label = "MON", bg = outputMode == "monitor" and C.btnOn or C.panelMid, action = function() actions.setDisplayOutput("monitor") end },
      { id = "cfgOutBoth", label = "BOTH", bg = outputMode == "both" and C.btnOn or C.panelMid, action = function() actions.setDisplayOutput("both") end },
    }, 2, 1)
    addGridRow({
      { id = "cfgUnitJ", label = "UNIT J", bg = energyUnit == "j" and C.btnOn or C.panelMid, action = function() actions.setEnergyUnit("j") end },
      { id = "cfgUnitFE", label = "UNIT FE", bg = energyUnit == "fe" and C.btnOn or C.panelMid, action = function() actions.setEnergyUnit("fe") end },
    }, 2, 1)
    addGridRow({
      { id = "cfgLasDown", label = "LAS -", bg = C.panelMid, action = function() actions.adjustLaserCount(-1) end },
      { id = "cfgLasValue", label = "LAS " .. tostring(laserCount), bg = C.panel, action = function() end, disabled = true },
      { id = "cfgLasUp", label = "LAS +", bg = C.btnAction, action = function() actions.adjustLaserCount(1) end },
    }, 2, 1)
    addGridRow({
      { id = "cfgSave", label = "SAVE CONFIG", bg = C.ok, action = actions.saveSetupConfig },
      { id = "cfgReload", label = "RELOAD", bg = C.btnWarn, action = actions.reloadSetupConfig },
    }, 2, 1)
    addGridRow({
      { id = "monitor", label = "MONITOR", bg = C.btnWarn, action = actions.startMonitorSelection },
    }, 2, 0)
  end

  local function buildSupervisorCoreButtons()
    local injAvailable = state.injectionWritable == true
    local injLabel = "INJ " .. tostring(math.floor(tonumber(state.injectionRate) or 0))

    addGridRow({
      { id = "master", label = "MASTER", bg = state.autoMaster and C.btnOn or C.btnOff, action = actions.toggleMaster },
      { id = "fusion", label = "FUSION", bg = state.fusionAuto and C.btnOn or C.btnOff, action = actions.toggleFusion },
      { id = "charge", label = "CHARGE", bg = state.chargeAuto and C.btnOn or C.btnOff, action = actions.toggleCharge },
    }, 2, 1)
    addGridRow({
      { id = "injDown", label = "INJ -", bg = injAvailable and C.panelMid or C.inactive, action = function() actions.adjustInjectionRate(-1) end, disabled = not injAvailable },
      { id = "injValue", label = injLabel, bg = C.panel, action = function() end, disabled = true },
      { id = "injUp", label = "INJ +", bg = injAvailable and C.btnAction or C.inactive, action = function() actions.adjustInjectionRate(1) end, disabled = not injAvailable },
    }, 2, 1)
    if y + 2 <= maxY then
      drawBigButton("demarrage", bx, y, bw, "DEMARRAGE", actions.canIgnite() and C.warn or C.inactive, actions.startReactorSequence)
      y = y + 3
    end
    addGridRow({
      { id = "monitor", label = "MONITOR", bg = C.btnWarn, action = actions.startMonitorSelection },
      { id = "arret", label = "ARRET", bg = C.bad, action = actions.stopRequested },
    }, 2, 1)

    local center = layout.center
    if not center or layout.mode == "compact" or state.currentView ~= "supervision" then return end

    local innerX = center.x + 2
    local innerW = center.w - 4
    local btnH = 3
    local gap = 2
    local barY = center.y + center.h - btnH - 6
    local minBtnW = math.max(#"T LOCK", #"DT LOCK", #"D LOCK") + 2
    local btnW = math.max(minBtnW, math.floor((innerW - (gap * 2)) / 3))
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
    }, 2, 0)
    return
  end

  if state.currentView == "manual" then
    buildManualButtons()
    return
  end

  buildSupervisorCoreButtons()
end

return M
