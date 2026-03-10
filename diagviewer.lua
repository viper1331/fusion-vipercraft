local config = {
  refreshDelay = 2,
  killAllRelaysOnExit = false,
  maxFlattenDepth = 5,
  maxFlattenLines = 260,
  defaultMonitorScale = 0.5,
  ui = {
    showBoxes = true,
    showTabBar = true,
    compactFooter = false,
  }
}

local running = true
local currentPage = "summary"
local scrollOffset = 0
local selectedRelayIndex = 1
local selectedSideIndex = 1
local selectedMonitorIndex = 0
local selectedMonitorName = nil
local selectedMethodsCategory = 1

local SIDE_LIST = { "top", "bottom", "left", "right", "front", "back" }
local PAGE_ORDER = {
  "summary",
  "block_readers",
  "relays",
  "network",
  "fusion",
  "relay_test",
  "methods",
  "monitors",
  "peripherals"
}

local PAGE_TITLES = {
  summary = "SYNTHESIS",
  block_readers = "BLOCK READERS",
  relays = "REDSTONE RELAYS",
  network = "MODEM / NETWORK",
  fusion = "FUSION EQUIPMENT",
  relay_test = "RELAY TEST",
  methods = "METHOD EXPLORER",
  monitors = "MONITOR MANAGEMENT",
  peripherals = "PERIPHERAL INVENTORY"
}

local colorsUI = {
  bg = colors.black,
  text = colors.white,
  title = colors.cyan,
  good = colors.lime,
  warn = colors.yellow,
  bad = colors.red,
  info = colors.lightBlue,
  section = colors.orange,
  dim = colors.lightGray,
  headerBg = colors.gray,
  tabBg = colors.black,
  tabActiveBg = colors.blue,
  statusBg = colors.gray,
  footerBg = colors.gray,
  box = colors.gray,
  highlight = colors.blue,
}

local latestData = {}
local statusState = {
  defaultMessage = "Ready",
  tempMessage = nil,
  tempUntil = 0,
}

local function safeCall(fn, ...)
  local ok, result = pcall(fn, ...)
  if ok then return true, result end
  return false, result
end

local function short(v)
  if v == nil then return "nil" end
  return tostring(v)
end

local function ellipsis(text, maxLen)
  text = tostring(text or "")
  if maxLen <= 0 then return "" end
  if #text <= maxLen then return text end
  if maxLen <= 3 then return string.sub(text, 1, maxLen) end
  return string.sub(text, 1, maxLen - 3) .. "..."
end

local function sortedKeys(tbl)
  local keys = {}
  for k in pairs(tbl or {}) do table.insert(keys, k) end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  return keys
end

local function setStatus(message, duration)
  if duration and duration > 0 then
    statusState.tempMessage = tostring(message or "")
    statusState.tempUntil = os.clock() + duration
  else
    statusState.defaultMessage = tostring(message or "")
  end
end

local function getCurrentStatus()
  if statusState.tempMessage and os.clock() <= statusState.tempUntil then
    return statusState.tempMessage
  end
  statusState.tempMessage = nil
  return statusState.defaultMessage
end

local function flattenTable(tbl, indent, out, visited, options, state)
  indent = indent or 0
  out = out or {}
  visited = visited or {}
  options = options or {}
  state = state or { lines = 0 }

  local maxDepth = options.maxDepth or config.maxFlattenDepth
  local maxLines = options.maxLines or config.maxFlattenLines

  if state.lines >= maxLines then
    return out
  end

  if type(tbl) ~= "table" then
    table.insert(out, string.rep(" ", indent) .. tostring(tbl))
    state.lines = state.lines + 1
    return out
  end

  if visited[tbl] then
    table.insert(out, string.rep(" ", indent) .. "<circular reference>")
    state.lines = state.lines + 1
    return out
  end

  if indent / 2 >= maxDepth then
    table.insert(out, string.rep(" ", indent) .. "<max depth reached>")
    state.lines = state.lines + 1
    return out
  end

  visited[tbl] = true

  for _, key in ipairs(sortedKeys(tbl)) do
    if state.lines >= maxLines then
      table.insert(out, string.rep(" ", indent) .. "<line limit reached>")
      state.lines = state.lines + 1
      break
    end

    local value = tbl[key]
    local prefix = string.rep(" ", indent) .. tostring(key) .. " = "
    if type(value) == "table" then
      table.insert(out, prefix .. "{")
      state.lines = state.lines + 1
      flattenTable(value, indent + 2, out, visited, options, state)
      if state.lines < maxLines then
        table.insert(out, string.rep(" ", indent) .. "}")
        state.lines = state.lines + 1
      end
    else
      table.insert(out, prefix .. tostring(value))
      state.lines = state.lines + 1
    end
  end

  visited[tbl] = nil
  return out
end

local function writeLinesToFile(filename, content)
  local file = fs.open(filename, "w")
  if not file then return false, "Impossible d'ouvrir le fichier" end
  for i, line in ipairs(content) do
    file.write(line)
    if i < #content then file.write("\n") end
  end
  file.close()
  return true
end

local function getPeripheralMethods(name)
  local ok, methods = safeCall(function() return peripheral.getMethods(name) end)
  if ok and type(methods) == "table" then
    table.sort(methods)
    return methods
  end
  return {}
end

local function getPeripheralNamesByMatcher(matcher)
  local found = {}
  for _, name in ipairs(peripheral.getNames()) do
    local pType = tostring(peripheral.getType(name) or "")
    local methods = getPeripheralMethods(name)
    if matcher(name, pType, methods) then
      table.insert(found, name)
    end
  end
  table.sort(found)
  return found
end

local function hasMethods(methods, required)
  local set = {}
  for _, m in ipairs(methods or {}) do set[m] = true end
  for _, wanted in ipairs(required) do
    if not set[wanted] then return false end
  end
  return true
end

local function getBlockReaders()
  return getPeripheralNamesByMatcher(function(_, pType, methods)
    return pType == "block_reader" or hasMethods(methods, { "getBlockData" })
  end)
end

local function getRedstoneRelays()
  return getPeripheralNamesByMatcher(function(_, pType, methods)
    return pType == "redstone_relay" or hasMethods(methods, { "setAnalogOutput", "getAnalogInput" })
  end)
end

local function getModems()
  return getPeripheralNamesByMatcher(function(_, pType, methods)
    return pType == "modem" or hasMethods(methods, { "getNamesRemote", "getNameLocal" })
  end)
end

local function getFusionControllers()
  return getPeripheralNamesByMatcher(function(name, pType)
    local lName = string.lower(name)
    local lType = string.lower(pType)
    return lType:find("fusion_reactor_controller", 1, true) ~= nil
      or lName:find("fusion", 1, true) ~= nil
  end)
end

local function getInductionPorts()
  return getPeripheralNamesByMatcher(function(name, pType)
    local lName = string.lower(name)
    local lType = string.lower(pType)
    return pType == "inductionPort"
      or lType:find("induction", 1, true) ~= nil
      or lName:find("induction", 1, true) ~= nil
  end)
end

local function getLaserAmplifiers()
  return getPeripheralNamesByMatcher(function(name, pType)
    local lName = string.lower(name)
    local lType = string.lower(pType)
    return pType == "laserAmplifier"
      or lType:find("laser", 1, true) ~= nil
      or lName:find("laser", 1, true) ~= nil
  end)
end

local function getMonitorCandidates()
  local found = {}
  for _, name in ipairs(peripheral.getNames()) do
    local pType = tostring(peripheral.getType(name) or "")
    local methods = getPeripheralMethods(name)
    local methodSet = {}
    for _, m in ipairs(methods) do methodSet[m] = true end

    local looksLikeMonitor =
      pType == "monitor"
      or string.find(string.lower(name), "monitor", 1, true)
      or (methodSet.getSize and methodSet.write and methodSet.setTextScale)

    if looksLikeMonitor then
      local info = { name = name, type = pType, methods = methods, width = "?", height = "?", ok = false }
      local wrapped = peripheral.wrap(name)
      if wrapped and methodSet.getSize then
        local ok, size = safeCall(function() return { wrapped.getSize() } end)
        if ok and type(size) == "table" then
          info.width = size[1] or "?"
          info.height = size[2] or "?"
          info.ok = true
        end
      end
      table.insert(found, info)
    end
  end
  table.sort(found, function(a, b) return a.name < b.name end)
  return found
end

local function getMonitors()
  local out = {}
  for _, info in ipairs(getMonitorCandidates()) do table.insert(out, info.name) end
  return out
end

local function getMonitorInfo(name)
  for _, info in ipairs(getMonitorCandidates()) do
    if info.name == name then return info end
  end
  return { name = name, type = "?", width = "?", height = "?", ok = false, methods = {} }
end

local function refreshSelectedMonitor()
  local monitors = getMonitors()
  if #monitors == 0 then
    selectedMonitorIndex = 0
    selectedMonitorName = nil
    return
  end

  if selectedMonitorName then
    for i, name in ipairs(monitors) do
      if name == selectedMonitorName then
        selectedMonitorIndex = i
        return
      end
    end
  end

  if selectedMonitorIndex == 0 and #monitors == 1 then
    selectedMonitorIndex = 1
  end
  if selectedMonitorIndex < 0 then selectedMonitorIndex = 0 end
  if selectedMonitorIndex > #monitors then selectedMonitorIndex = 1 end

  if selectedMonitorIndex == 0 then
    selectedMonitorName = nil
  else
    selectedMonitorName = monitors[selectedMonitorIndex]
  end
end

local function selectNextMonitor()
  local monitors = getMonitors()
  if #monitors == 0 then
    selectedMonitorIndex = 0
    selectedMonitorName = nil
    setStatus("Aucun moniteur detecte", 2.5)
    return
  end

  if selectedMonitorName then
    local currentIndex = nil
    for i, name in ipairs(monitors) do
      if name == selectedMonitorName then currentIndex = i break end
    end
    if currentIndex then selectedMonitorIndex = currentIndex end
  end

  if selectedMonitorIndex == 0 then
    selectedMonitorIndex = 1
  else
    selectedMonitorIndex = selectedMonitorIndex + 1
    if selectedMonitorIndex > #monitors then selectedMonitorIndex = 1 end
  end

  selectedMonitorName = monitors[selectedMonitorIndex]
  local info = getMonitorInfo(selectedMonitorName)
  setStatus("Moniteur: " .. selectedMonitorName .. " (" .. tostring(info.width) .. "x" .. tostring(info.height) .. ")", 3)
end

local function disableMonitorOutput()
  selectedMonitorIndex = 0
  selectedMonitorName = nil
  setStatus("Affichage moniteur desactive", 2.5)
end

local function getSelectedMonitor()
  refreshSelectedMonitor()
  if not selectedMonitorName then return nil end
  local mon = peripheral.wrap(selectedMonitorName)
  if not mon then
    selectedMonitorIndex = 0
    selectedMonitorName = nil
    return nil
  end
  return mon
end

local function safeGetBlockData(reader)
  return safeCall(function() return reader.getBlockData() end)
end

local function getRelaySideInfo(relay, side)
  local info = {}
  local okAIn, valAIn = safeCall(function() return relay.getAnalogInput(side) end)
  local okAOut, valAOut = safeCall(function() return relay.getAnalogOutput(side) end)
  info.analogInput = okAIn and valAIn or "ERR"
  info.analogOutput = okAOut and valAOut or "ERR"
  info.digitalInput = type(info.analogInput) == "number" and info.analogInput > 0 or "ERR"
  info.digitalOutput = type(info.analogOutput) == "number" and info.analogOutput > 0 or "ERR"
  return info
end

local function getModemInfo(modem)
  local info = {}
  local okLocalName, valLocalName = safeCall(function() return modem.getNameLocal() end)
  local okNamesRemote, valNamesRemote = safeCall(function() return modem.getNamesRemote() end)
  info.nameLocal = okLocalName and valLocalName or "N/A"
  info.namesRemote = okNamesRemote and valNamesRemote or {}
  return info
end

local function getReaderSummary(name)
  local reader = peripheral.wrap(name)
  if not reader then return { name = name, error = "wrap impossible" } end
  local ok, data = safeGetBlockData(reader)
  if not ok or type(data) ~= "table" then
    return { name = name, error = tostring(data) }
  end
  local result = {
    name = name,
    raw = data,
    active = data.active_state,
    redstone = data.redstone,
    current_redstone = data.current_redstone,
    control_type = data.control_type,
    dumping = data.dumping,
  }
  if data.chemical_tanks and data.chemical_tanks[1] and data.chemical_tanks[1].stored then
    result.chemical_id = data.chemical_tanks[1].stored.id
    result.chemical_amount = data.chemical_tanks[1].stored.amount
  end
  return result
end

local function gatherAllData()
  local data = {}
  data.peripherals = peripheral.getNames()
  table.sort(data.peripherals)
  data.blockReaders = getBlockReaders()
  data.redstoneRelays = getRedstoneRelays()
  data.monitors = getMonitors()
  data.monitorCandidates = getMonitorCandidates()
  data.modems = getModems()
  data.fusionControllers = getFusionControllers()
  data.inductionPorts = getInductionPorts()
  data.laserAmplifiers = getLaserAmplifiers()

  data.readerSummaries = {}
  for _, name in ipairs(data.blockReaders) do table.insert(data.readerSummaries, getReaderSummary(name)) end

  data.relaySummaries = {}
  for _, name in ipairs(data.redstoneRelays) do
    local relay = peripheral.wrap(name)
    local relayData = { name = name, methods = getPeripheralMethods(name), sides = {} }
    if relay then
      for _, side in ipairs(SIDE_LIST) do relayData.sides[side] = getRelaySideInfo(relay, side) end
    else
      relayData.error = "wrap impossible"
    end
    table.insert(data.relaySummaries, relayData)
  end

  data.modemSummaries = {}
  for _, name in ipairs(data.modems) do
    local modem = peripheral.wrap(name)
    if modem then
      table.insert(data.modemSummaries, { name = name, info = getModemInfo(modem) })
    else
      table.insert(data.modemSummaries, { name = name, error = "wrap impossible" })
    end
  end

  local remoteCount = 0
  for _, modemData in ipairs(data.modemSummaries) do
    if modemData.info and modemData.info.namesRemote then
      remoteCount = remoteCount + #modemData.info.namesRemote
    end
  end
  data.totalRemotePeripherals = remoteCount

  return data
end

local function clearDevice(dev)
  dev.setBackgroundColor(colorsUI.bg)
  dev.setTextColor(colorsUI.text)
  dev.clear()
  dev.setCursorPos(1, 1)
end

local function writeAt(dev, x, y, text, color, bg)
  if bg then dev.setBackgroundColor(bg) end
  dev.setCursorPos(x, y)
  dev.setTextColor(color or colorsUI.text)
  dev.write(text)
  dev.setTextColor(colorsUI.text)
  if bg then dev.setBackgroundColor(colorsUI.bg) end
end

local function writeClipped(dev, x, y, text, color, bg)
  local w, _ = dev.getSize()
  text = tostring(text or "")
  if x > w then return end
  writeAt(dev, x, y, string.sub(text, 1, w - x + 1), color, bg)
end

local function center(dev, y, text, color)
  local w, _ = dev.getSize()
  local x = math.max(1, math.floor((w - #text) / 2) + 1)
  writeAt(dev, x, y, text, color)
end

local function drawHLine(dev, y, color)
  local w, _ = dev.getSize()
  writeAt(dev, 1, y, string.rep("-", w), color or colorsUI.dim)
end

local function drawBox(dev, x, y, width, height, title, borderColor)
  if width < 3 or height < 3 then return end
  local right = x + width - 1
  local bottom = y + height - 1
  local bc = borderColor or colorsUI.box

  writeAt(dev, x, y, "+" .. string.rep("-", width - 2) .. "+", bc)
  for row = y + 1, bottom - 1 do
    writeAt(dev, x, row, "|", bc)
    writeAt(dev, right, row, "|", bc)
  end
  writeAt(dev, x, bottom, "+" .. string.rep("-", width - 2) .. "+", bc)

  if title and #title > 0 and width > 6 then
    local t = " " .. ellipsis(title, width - 6) .. " "
    writeAt(dev, x + 2, y, t, colorsUI.title)
  end
end

local function makeLine(text, color)
  return { text = tostring(text or ""), color = color or colorsUI.text }
end

local function renderScrollable(dev, lines)
  local w, h = dev.getSize()
  local contentTop = 4
  local contentBottom = h - 2
  if config.ui.showTabBar then contentTop = 5 end
  local viewHeight = contentBottom - contentTop + 1
  if viewHeight < 1 then return end

  local total = #lines
  local maxOffset = math.max(0, total - viewHeight)
  if scrollOffset < 0 then scrollOffset = 0 end
  if scrollOffset > maxOffset then scrollOffset = maxOffset end

  if config.ui.showBoxes then
    drawBox(dev, 1, contentTop - 1, w, viewHeight + 2, "CONTENT", colorsUI.dim)
  end

  local y = contentTop
  for i = 1, viewHeight do
    local idx = scrollOffset + i
    local line = lines[idx]
    if line then
      writeClipped(dev, 2, y, ellipsis(line.text, w - 3), line.color)
    end
    y = y + 1
  end

  local scrollInfo = string.format("Rows %d-%d/%d", math.min(total, scrollOffset + 1), math.min(total, scrollOffset + viewHeight), total)
  writeClipped(dev, math.max(1, w - #scrollInfo), h - 1, scrollInfo, colorsUI.dim)
end

local function pageLabel(page)
  return PAGE_TITLES[page] or page
end

local function drawHeader(dev)
  local w, _ = dev.getSize()
  local title = "VIPERCRAFT DIAGVIEWER :: " .. pageLabel(currentPage)
  writeAt(dev, 1, 1, string.rep(" ", w), colors.white, colorsUI.headerBg)
  center(dev, 1, ellipsis(title, w), colors.white)
  drawHLine(dev, 2, colorsUI.dim)
end

local function drawTabs(dev)
  if not config.ui.showTabBar then return end
  local w, _ = dev.getSize()
  local x = 1
  for _, page in ipairs(PAGE_ORDER) do
    local label = string.sub(page, 1, 3):upper()
    local text = " " .. label .. " "
    local bg = (page == currentPage) and colorsUI.tabActiveBg or colorsUI.tabBg
    if x + #text - 1 <= w then
      writeAt(dev, x, 3, text, colors.white, bg)
      x = x + #text
    end
  end
  drawHLine(dev, 4, colorsUI.dim)
end

local function monitorStateText(data)
  if selectedMonitorName then
    local info = getMonitorInfo(selectedMonitorName)
    return string.format("Monitor: %s (%sx%s)", selectedMonitorName, tostring(info.width), tostring(info.height))
  end
  if #data.monitors > 0 then
    return string.format("Monitor: OFF (%d detected)", #data.monitors)
  end
  return "Monitor: none"
end

local function drawStatusBar(dev, data)
  local w, h = dev.getSize()
  local status = getCurrentStatus() .. " | " .. monitorStateText(data)
  writeAt(dev, 1, h - 1, string.rep(" ", w), colors.white, colorsUI.statusBg)
  writeClipped(dev, 1, h - 1, ellipsis(status, w), colors.yellow, colorsUI.statusBg)
end

local function drawFooter(dev)
  local w, h = dev.getSize()
  local help = "1-7 pages | 8 monitors | 9 peripherals | arrows scroll | <- -> tabs | R refresh | E report | J raw | M nextMon | N monOff | X allOff | Q quit"
  writeAt(dev, 1, h, string.rep(" ", w), colors.white, colorsUI.footerBg)
  writeClipped(dev, 1, h, ellipsis(help, w), colors.white, colorsUI.footerBg)
end

local function listMethodsForCategory(data, category)
  local out = {}
  local function addPeripheralMethods(title, names)
    table.insert(out, makeLine("[" .. title .. "]", colorsUI.section))
    if #names == 0 then
      table.insert(out, makeLine("  - none", colorsUI.bad))
      return
    end
    for _, name in ipairs(names) do
      table.insert(out, makeLine("  " .. name, colorsUI.info))
      local methods = getPeripheralMethods(name)
      if #methods == 0 then
        table.insert(out, makeLine("    (no methods)", colorsUI.bad))
      else
        for _, m in ipairs(methods) do
          table.insert(out, makeLine("    - " .. m, colorsUI.text))
        end
      end
    end
  end

  if category == "all" or category == "monitors" then addPeripheralMethods("monitors", data.monitors) end
  if category == "all" or category == "block_readers" then addPeripheralMethods("block_readers", data.blockReaders) end
  if category == "all" or category == "redstone_relays" then addPeripheralMethods("redstone_relays", data.redstoneRelays) end
  if category == "all" or category == "modems" then addPeripheralMethods("modems", data.modems) end
  if category == "all" or category == "fusion" then addPeripheralMethods("fusion controllers", data.fusionControllers) end
  if category == "all" or category == "induction" then addPeripheralMethods("induction ports", data.inductionPorts) end
  if category == "all" or category == "lasers" then addPeripheralMethods("laser amplifiers", data.laserAmplifiers) end

  return out
end

local function buildPageLines(data)
  local lines = {}

  if currentPage == "summary" then
    table.insert(lines, makeLine("SYSTEM OVERVIEW", colorsUI.title))
    table.insert(lines, makeLine("Total peripherals: " .. #data.peripherals, colorsUI.info))
    table.insert(lines, makeLine("Block readers:     " .. #data.blockReaders, colorsUI.text))
    table.insert(lines, makeLine("Redstone relays:   " .. #data.redstoneRelays, colorsUI.text))
    table.insert(lines, makeLine("Modems:            " .. #data.modems, colorsUI.text))
    table.insert(lines, makeLine("Fusion ctrl:       " .. #data.fusionControllers, colorsUI.text))
    table.insert(lines, makeLine("Induction ports:   " .. #data.inductionPorts, colorsUI.text))
    table.insert(lines, makeLine("Laser amplifiers:  " .. #data.laserAmplifiers, colorsUI.text))
    table.insert(lines, makeLine("Remote peripherals via modem: " .. (data.totalRemotePeripherals or 0), colorsUI.warn))
    table.insert(lines, makeLine("", colorsUI.text))
    table.insert(lines, makeLine("BLOCK READER QUICK STATUS", colorsUI.section))
    if #data.readerSummaries == 0 then
      table.insert(lines, makeLine("No block_reader detected", colorsUI.bad))
    else
      for _, r in ipairs(data.readerSummaries) do
        if r.error then
          table.insert(lines, makeLine("- " .. r.name .. " | ERROR: " .. r.error, colorsUI.bad))
        else
          local state = (r.active == 1) and "ACTIVE" or "IDLE"
          local chem = r.chemical_id and (" | chem=" .. tostring(r.chemical_id)) or ""
          table.insert(lines, makeLine(string.format("- %s | %s | rs=%s | crs=%s%s", r.name, state, short(r.redstone), short(r.current_redstone), chem), (r.active == 1) and colorsUI.good or colorsUI.warn))
        end
      end
    end
    table.insert(lines, makeLine("", colorsUI.text))
    table.insert(lines, makeLine(monitorStateText(data), colorsUI.info))

  elseif currentPage == "block_readers" then
    table.insert(lines, makeLine("DETAILED BLOCK READER DIAGNOSTICS", colorsUI.title))
    if #data.blockReaders == 0 then
      table.insert(lines, makeLine("No block_reader detected", colorsUI.bad))
    else
      for _, name in ipairs(data.blockReaders) do
        table.insert(lines, makeLine("[" .. name .. "]", colorsUI.section))
        local reader = peripheral.wrap(name)
        if reader then
          local ok, blockData = safeGetBlockData(reader)
          if ok and type(blockData) == "table" then
            local dump = flattenTable(blockData, 0, nil, nil, { maxDepth = config.maxFlattenDepth, maxLines = config.maxFlattenLines })
            for _, d in ipairs(dump) do
              table.insert(lines, makeLine("  " .. d, colorsUI.text))
            end
          else
            table.insert(lines, makeLine("  Error getBlockData: " .. tostring(blockData), colorsUI.bad))
          end
        else
          table.insert(lines, makeLine("  Wrap impossible", colorsUI.bad))
        end
        table.insert(lines, makeLine("", colorsUI.text))
      end
    end

  elseif currentPage == "relays" then
    table.insert(lines, makeLine("REDSTONE RELAY DETAILS", colorsUI.title))
    if #data.relaySummaries == 0 then
      table.insert(lines, makeLine("No redstone_relay detected", colorsUI.bad))
    else
      for _, relay in ipairs(data.relaySummaries) do
        table.insert(lines, makeLine("[" .. relay.name .. "]", colorsUI.section))
        if relay.error then
          table.insert(lines, makeLine("  " .. relay.error, colorsUI.bad))
        else
          for _, side in ipairs(SIDE_LIST) do
            local info = relay.sides[side]
            table.insert(lines, makeLine(string.format("  %-6s DIN:%s DOUT:%s AIN:%s AOUT:%s", side, short(info.digitalInput), short(info.digitalOutput), short(info.analogInput), short(info.analogOutput)), colorsUI.text))
          end
        end
        table.insert(lines, makeLine("", colorsUI.text))
      end
    end

  elseif currentPage == "network" then
    table.insert(lines, makeLine("MODEM NETWORK DIAGNOSTICS", colorsUI.title))
    if #data.modemSummaries == 0 then
      table.insert(lines, makeLine("No modem detected", colorsUI.bad))
    else
      for _, modemData in ipairs(data.modemSummaries) do
        table.insert(lines, makeLine("[" .. modemData.name .. "]", colorsUI.section))
        if modemData.error then
          table.insert(lines, makeLine("  " .. modemData.error, colorsUI.bad))
        else
          table.insert(lines, makeLine("  localName: " .. short(modemData.info.nameLocal), colorsUI.info))
          table.insert(lines, makeLine("  remoteCount: " .. #modemData.info.namesRemote, colorsUI.info))
          local modem = peripheral.wrap(modemData.name)
          for _, remoteName in ipairs(modemData.info.namesRemote) do
            local remoteType = "?"
            if modem then
              local okType, valType = safeCall(function() return modem.getTypeRemote(remoteName) end)
              if okType then remoteType = tostring(valType) end
            end
            table.insert(lines, makeLine("    - " .. remoteName .. " -> " .. remoteType, colorsUI.text))
          end
        end
        table.insert(lines, makeLine("", colorsUI.text))
      end
    end

  elseif currentPage == "fusion" then
    table.insert(lines, makeLine("MEKANISM / FUSION EQUIPMENT", colorsUI.title))
    table.insert(lines, makeLine("Fusion Controllers: " .. #data.fusionControllers, colorsUI.section))
    for _, name in ipairs(data.fusionControllers) do table.insert(lines, makeLine("  - " .. name, colorsUI.text)) end
    table.insert(lines, makeLine("", colorsUI.text))
    table.insert(lines, makeLine("Induction Ports: " .. #data.inductionPorts, colorsUI.section))
    for _, name in ipairs(data.inductionPorts) do table.insert(lines, makeLine("  - " .. name, colorsUI.text)) end
    table.insert(lines, makeLine("", colorsUI.text))
    table.insert(lines, makeLine("Laser Amplifiers: " .. #data.laserAmplifiers, colorsUI.section))
    for _, name in ipairs(data.laserAmplifiers) do table.insert(lines, makeLine("  - " .. name, colorsUI.text)) end

  elseif currentPage == "relay_test" then
    table.insert(lines, makeLine("RELAY TEST CONSOLE", colorsUI.title))
    if #data.redstoneRelays == 0 then
      table.insert(lines, makeLine("No redstone_relay detected", colorsUI.bad))
    else
      if selectedRelayIndex < 1 then selectedRelayIndex = 1 end
      if selectedRelayIndex > #data.redstoneRelays then selectedRelayIndex = #data.redstoneRelays end
      if selectedSideIndex < 1 then selectedSideIndex = 1 end
      if selectedSideIndex > #SIDE_LIST then selectedSideIndex = #SIDE_LIST end

      local relayName = data.redstoneRelays[selectedRelayIndex]
      local side = SIDE_LIST[selectedSideIndex]
      local relay = peripheral.wrap(relayName)

      table.insert(lines, makeLine("Relay selected: " .. relayName .. " (" .. selectedRelayIndex .. "/" .. #data.redstoneRelays .. ")", colorsUI.good))
      table.insert(lines, makeLine("Side selected : " .. side .. " (" .. selectedSideIndex .. "/" .. #SIDE_LIST .. ")", colorsUI.good))
      table.insert(lines, makeLine("", colorsUI.text))

      if relay then
        local info = getRelaySideInfo(relay, side)
        table.insert(lines, makeLine("Digital In  : " .. short(info.digitalInput), colorsUI.text))
        table.insert(lines, makeLine("Digital Out : " .. short(info.digitalOutput), colorsUI.text))
        table.insert(lines, makeLine("Analog In   : " .. short(info.analogInput), colorsUI.text))
        table.insert(lines, makeLine("Analog Out  : " .. short(info.analogOutput), colorsUI.text))
      else
        table.insert(lines, makeLine("Impossible to wrap selected relay", colorsUI.bad))
      end

      table.insert(lines, makeLine("", colorsUI.text))
      table.insert(lines, makeLine("Controls:", colorsUI.section))
      table.insert(lines, makeLine("A/D relay  | W/S side", colorsUI.info))
      table.insert(lines, makeLine("O=15 | F=0 | P=pulse", colorsUI.info))
      table.insert(lines, makeLine("0-9 analog | Backspace=0", colorsUI.warn))
      table.insert(lines, makeLine("X=stop all relays", colorsUI.warn))
      table.insert(lines, makeLine("Touch monitor buttons to run quick actions.", colorsUI.dim))
    end

  elseif currentPage == "methods" then
    local categories = { "all", "monitors", "block_readers", "redstone_relays", "modems", "fusion", "induction", "lasers" }
    if selectedMethodsCategory < 1 then selectedMethodsCategory = 1 end
    if selectedMethodsCategory > #categories then selectedMethodsCategory = #categories end
    local active = categories[selectedMethodsCategory]
    table.insert(lines, makeLine("METHOD EXPLORER", colorsUI.title))
    table.insert(lines, makeLine("Category (<-/->): " .. active, colorsUI.info))
    table.insert(lines, makeLine("", colorsUI.text))

    local methodLines = listMethodsForCategory(data, active)
    for _, line in ipairs(methodLines) do table.insert(lines, line) end

  elseif currentPage == "monitors" then
    table.insert(lines, makeLine("MONITOR MANAGEMENT", colorsUI.title))
    table.insert(lines, makeLine("Detected monitors: " .. #data.monitorCandidates, colorsUI.info))
    if selectedMonitorName then
      table.insert(lines, makeLine("Active monitor: " .. selectedMonitorName, colorsUI.good))
    else
      table.insert(lines, makeLine("Active monitor: OFF", colorsUI.warn))
    end
    table.insert(lines, makeLine("M: next monitor | N: disable output", colorsUI.section))
    table.insert(lines, makeLine("", colorsUI.text))
    if #data.monitorCandidates == 0 then
      table.insert(lines, makeLine("No monitor detected", colorsUI.bad))
    else
      for i, info in ipairs(data.monitorCandidates) do
        local flag = (info.name == selectedMonitorName) and "*" or " "
        table.insert(lines, makeLine(string.format("%s [%d] %s | type=%s | %sx%s", flag, i, info.name, short(info.type), short(info.width), short(info.height)), (info.name == selectedMonitorName) and colorsUI.good or colorsUI.text))
      end
    end

  elseif currentPage == "peripherals" then
    table.insert(lines, makeLine("PERIPHERAL INVENTORY", colorsUI.title))
    for _, name in ipairs(data.peripherals) do
      table.insert(lines, makeLine(string.format("- %s -> %s", name, tostring(peripheral.getType(name))), colorsUI.text))
    end
  end

  return lines
end

local function relaySetAnalog(relayName, side, value)
  local relay = peripheral.wrap(relayName)
  if not relay then
    setStatus("Relay introuvable : " .. relayName, 3)
    return
  end
  local ok, err = safeCall(function() relay.setAnalogOutput(side, value) end)
  if ok then
    setStatus("Sortie " .. relayName .. " / " .. side .. " = " .. tostring(value), 2)
  else
    setStatus("Erreur sortie : " .. tostring(err), 3)
  end
end

local function relayPulse(relayName, side, value, duration)
  relaySetAnalog(relayName, side, value)
  sleep(duration or 1)
  relaySetAnalog(relayName, side, 0)
end

local function allRelaysOff(relays)
  for _, relayName in ipairs(relays or {}) do
    local relay = peripheral.wrap(relayName)
    if relay then
      for _, side in ipairs(SIDE_LIST) do
        pcall(function() relay.setAnalogOutput(side, 0) end)
      end
    end
  end
  setStatus("Toutes les sorties redstone ont ete coupees", 2.5)
end

local function renderPage(dev, data)
  clearDevice(dev)
  drawHeader(dev)
  drawTabs(dev)
  local lines = buildPageLines(data)
  renderScrollable(dev, lines)
  drawStatusBar(dev, data)
  drawFooter(dev)
end

local function buildFormattedReport(data)
  local out = {}
  table.insert(out, "=== RAPPORT DIAGNOSTIC PREMIUM ===")
  table.insert(out, "")

  table.insert(out, "[SYNTHESIS]")
  table.insert(out, "total_peripherals = " .. #data.peripherals)
  table.insert(out, "block_readers = " .. #data.blockReaders)
  table.insert(out, "redstone_relays = " .. #data.redstoneRelays)
  table.insert(out, "modems = " .. #data.modems)
  table.insert(out, "fusion_controllers = " .. #data.fusionControllers)
  table.insert(out, "induction_ports = " .. #data.inductionPorts)
  table.insert(out, "laser_amplifiers = " .. #data.laserAmplifiers)
  table.insert(out, "remote_peripherals = " .. (data.totalRemotePeripherals or 0))
  table.insert(out, "")

  table.insert(out, "[MONITORS]")
  if #data.monitorCandidates == 0 then
    table.insert(out, "none")
  else
    for i, info in ipairs(data.monitorCandidates) do
      table.insert(out, string.format("[%d] %s | type=%s | %sx%s | selected=%s", i, info.name, short(info.type), short(info.width), short(info.height), tostring(selectedMonitorName == info.name)))
    end
  end
  table.insert(out, "")

  table.insert(out, "[BLOCK_READERS]")
  for _, name in ipairs(data.blockReaders) do
    table.insert(out, "----- " .. name .. " -----")
    local reader = peripheral.wrap(name)
    if reader then
      local ok, blockData = safeGetBlockData(reader)
      if ok and type(blockData) == "table" then
        local dump = flattenTable(blockData, 0, nil, nil, { maxDepth = config.maxFlattenDepth, maxLines = config.maxFlattenLines })
        for _, line in ipairs(dump) do table.insert(out, line) end
      else
        table.insert(out, "Erreur : " .. tostring(blockData))
      end
    else
      table.insert(out, "Wrap impossible")
    end
    table.insert(out, "")
  end

  table.insert(out, "[RELAYS]")
  for _, relayData in ipairs(data.relaySummaries) do
    table.insert(out, "----- " .. relayData.name .. " -----")
    table.insert(out, "Methodes:")
    for _, m in ipairs(relayData.methods or {}) do table.insert(out, "- " .. m) end
    if relayData.error then
      table.insert(out, relayData.error)
    else
      for _, side in ipairs(SIDE_LIST) do
        local info = relayData.sides[side]
        table.insert(out, side .. " | DIN=" .. short(info.digitalInput) .. " | DOUT=" .. short(info.digitalOutput) .. " | AIN=" .. short(info.analogInput) .. " | AOUT=" .. short(info.analogOutput))
      end
    end
    table.insert(out, "")
  end

  table.insert(out, "[MODEMS]")
  for _, modemData in ipairs(data.modemSummaries) do
    table.insert(out, "----- " .. modemData.name .. " -----")
    if modemData.error then
      table.insert(out, modemData.error)
    else
      table.insert(out, "nameLocal = " .. short(modemData.info.nameLocal))
      table.insert(out, "remote count = " .. #modemData.info.namesRemote)
      for _, remoteName in ipairs(modemData.info.namesRemote) do table.insert(out, "- " .. remoteName) end
    end
    table.insert(out, "")
  end

  return out
end

local function encodeRaw(value, indent, visited, depth)
  indent = indent or 0
  visited = visited or {}
  depth = depth or 0

  if type(value) ~= "table" then
    if type(value) == "string" then
      return string.format("%q", value)
    end
    return tostring(value)
  end

  if visited[value] then return "\"<circular>\"" end
  if depth > config.maxFlattenDepth + 2 then return "\"<max depth>\"" end

  visited[value] = true
  local pad = string.rep(" ", indent)
  local nextPad = string.rep(" ", indent + 2)
  local parts = { "{" }

  for _, key in ipairs(sortedKeys(value)) do
    local v = value[key]
    local keyRepr
    if type(key) == "string" and key:match("^[%a_][%w_]*$") then
      keyRepr = key
    else
      keyRepr = "[" .. encodeRaw(key, indent + 2, visited, depth + 1) .. "]"
    end
    table.insert(parts, nextPad .. keyRepr .. " = " .. encodeRaw(v, indent + 2, visited, depth + 1) .. ",")
  end

  table.insert(parts, pad .. "}")
  visited[value] = nil
  return table.concat(parts, "\n")
end

local function buildRawReport(data)
  local snapshot = {
    generatedAt = os.date and os.date("%Y-%m-%d %H:%M:%S") or "N/A",
    selectedMonitorName = selectedMonitorName,
    currentPage = currentPage,
    latestData = data,
  }

  return {
    "-- blockreader_raw.txt",
    "return " .. encodeRaw(snapshot, 0, {}, 0)
  }
end

local function refreshMonitorSettings()
  local mon = getSelectedMonitor()
  if mon then
    pcall(function() mon.setTextScale(config.defaultMonitorScale) end)
    pcall(function() mon.setBackgroundColor(colorsUI.bg) end)
    pcall(function() mon.setTextColor(colorsUI.text) end)
  end
end

local function redraw()
  renderPage(term, latestData)
  local mon = getSelectedMonitor()
  if mon then renderPage(mon, latestData) end
end

local function refreshData(skipDefaultStatus)
  refreshSelectedMonitor()
  latestData = gatherAllData()
  if not skipDefaultStatus then
    if selectedMonitorName then
      setStatus("Moniteur actif : " .. selectedMonitorName)
    elseif #latestData.monitors == 1 then
      setStatus("1 moniteur detecte")
    else
      setStatus("Aucun moniteur selectionne")
    end
  end
  refreshMonitorSettings()
  redraw()
end

local function exportFormatted()
  local content = buildFormattedReport(latestData)
  local ok, err = writeLinesToFile("blockreader_report.txt", content)
  if ok then
    setStatus("Export OK : blockreader_report.txt", 3)
  else
    setStatus("Erreur export : " .. tostring(err), 4)
  end
  redraw()
end

local function exportRaw()
  local content = buildRawReport(latestData)
  local ok, err = writeLinesToFile("blockreader_raw.txt", content)
  if ok then
    setStatus("Export RAW OK : blockreader_raw.txt", 3)
  else
    setStatus("Erreur export RAW : " .. tostring(err), 4)
  end
  redraw()
end

local function changePage(nextPage)
  currentPage = nextPage
  scrollOffset = 0
  setStatus("Page: " .. pageLabel(nextPage), 1.5)
  redraw()
end

local function cyclePage(step)
  local idx = 1
  for i, p in ipairs(PAGE_ORDER) do
    if p == currentPage then idx = i break end
  end
  idx = idx + step
  if idx < 1 then idx = #PAGE_ORDER end
  if idx > #PAGE_ORDER then idx = 1 end
  changePage(PAGE_ORDER[idx])
end

local function scrollBy(delta)
  scrollOffset = scrollOffset + delta
  redraw()
end

local function relayActionFromKey(key)
  local relays = latestData.redstoneRelays or {}
  if #relays == 0 then return end

  local relayName = relays[selectedRelayIndex]
  local side = SIDE_LIST[selectedSideIndex]

  if key == keys.a then
    selectedRelayIndex = selectedRelayIndex - 1
    if selectedRelayIndex < 1 then selectedRelayIndex = #relays end
    setStatus("Relay : " .. relays[selectedRelayIndex], 2)
    redraw()
  elseif key == keys.d then
    selectedRelayIndex = selectedRelayIndex + 1
    if selectedRelayIndex > #relays then selectedRelayIndex = 1 end
    setStatus("Relay : " .. relays[selectedRelayIndex], 2)
    redraw()
  elseif key == keys.w then
    selectedSideIndex = selectedSideIndex - 1
    if selectedSideIndex < 1 then selectedSideIndex = #SIDE_LIST end
    setStatus("Face : " .. SIDE_LIST[selectedSideIndex], 2)
    redraw()
  elseif key == keys.s then
    selectedSideIndex = selectedSideIndex + 1
    if selectedSideIndex > #SIDE_LIST then selectedSideIndex = 1 end
    setStatus("Face : " .. SIDE_LIST[selectedSideIndex], 2)
    redraw()
  elseif key == keys.o then
    relaySetAnalog(relayName, side, 15)
    refreshData(true)
  elseif key == keys.f then
    relaySetAnalog(relayName, side, 0)
    refreshData(true)
  elseif key == keys.p then
    setStatus("Pulse " .. relayName .. " / " .. side, 2)
    redraw()
    relayPulse(relayName, side, 15, 1)
    refreshData(true)
  elseif key == keys.backspace then
    relaySetAnalog(relayName, side, 0)
    refreshData(true)
  elseif key == keys.x then
    allRelaysOff(latestData.redstoneRelays)
    refreshData(true)
  elseif key == keys.zero then relaySetAnalog(relayName, side, 0); refreshData(true)
  elseif key == keys.one then relaySetAnalog(relayName, side, 1); refreshData(true)
  elseif key == keys.two then relaySetAnalog(relayName, side, 2); refreshData(true)
  elseif key == keys.three then relaySetAnalog(relayName, side, 3); refreshData(true)
  elseif key == keys.four then relaySetAnalog(relayName, side, 4); refreshData(true)
  elseif key == keys.five then relaySetAnalog(relayName, side, 5); refreshData(true)
  elseif key == keys.six then relaySetAnalog(relayName, side, 6); refreshData(true)
  elseif key == keys.seven then relaySetAnalog(relayName, side, 7); refreshData(true)
  elseif key == keys.eight then relaySetAnalog(relayName, side, 8); refreshData(true)
  elseif key == keys.nine then relaySetAnalog(relayName, side, 9); refreshData(true)
  end
end

local function handleMonitorTouch()
  while running do
    local _, side, x, y = os.pullEvent("monitor_touch")
    if not selectedMonitorName or side ~= selectedMonitorName then
      -- allow touch only on active monitor
    else
      if y == 1 then
        cyclePage(1)
      elseif y == 3 then
        local slot = math.floor((x - 1) / 5) + 1
        if slot >= 1 and slot <= #PAGE_ORDER then
          changePage(PAGE_ORDER[slot])
        end
      elseif y == 2 then
        if x <= 6 then
          scrollBy(-5)
        elseif x >= 7 and x <= 12 then
          scrollBy(5)
        elseif x >= 13 and x <= 18 then
          selectNextMonitor()
          refreshMonitorSettings()
          refreshData(true)
        elseif x >= 19 and x <= 24 then
          disableMonitorOutput()
          refreshData(true)
        elseif x >= 25 and x <= 30 then
          exportFormatted()
        elseif x >= 31 and x <= 36 then
          exportRaw()
        elseif x >= 37 then
          if currentPage == "relay_test" then
            allRelaysOff(latestData.redstoneRelays)
            refreshData(true)
          end
        end
      else
        if currentPage == "relay_test" then
          if y >= 6 and y <= 7 then
            relayActionFromKey(keys.a)
          elseif y >= 8 and y <= 9 then
            relayActionFromKey(keys.d)
          elseif y >= 10 and y <= 11 then
            relayActionFromKey(keys.w)
          elseif y >= 12 and y <= 13 then
            relayActionFromKey(keys.s)
          elseif y >= 14 and y <= 15 then
            relayActionFromKey(keys.o)
          elseif y >= 16 and y <= 17 then
            relayActionFromKey(keys.f)
          elseif y >= 18 and y <= 19 then
            relayActionFromKey(keys.p)
          end
        else
          if y > 10 then scrollBy(3) else scrollBy(-3) end
        end
      end
    end
  end
end

local function handleKeyboard()
  while running do
    local _, key = os.pullEvent("key")

    if key == keys.q then
      running = false
    elseif key == keys.one then changePage("summary")
    elseif key == keys.two then changePage("block_readers")
    elseif key == keys.three then changePage("relays")
    elseif key == keys.four then changePage("network")
    elseif key == keys.five then changePage("fusion")
    elseif key == keys.six then changePage("relay_test")
    elseif key == keys.seven then changePage("methods")
    elseif key == keys.eight then changePage("monitors")
    elseif key == keys.nine then changePage("peripherals")
    elseif key == keys.m then selectNextMonitor(); refreshMonitorSettings(); refreshData(true)
    elseif key == keys.n then disableMonitorOutput(); refreshData(true)
    elseif key == keys.r then setStatus("Rafraichissement...", 1.2); refreshData(true)
    elseif key == keys.e then exportFormatted()
    elseif key == keys.j then exportRaw()
    elseif key == keys.x then allRelaysOff(latestData.redstoneRelays); refreshData(true)
    elseif key == keys.up then scrollBy(-1)
    elseif key == keys.down then scrollBy(1)
    elseif key == keys.pageUp then scrollBy(-8)
    elseif key == keys.pageDown then scrollBy(8)
    elseif key == keys.home then scrollOffset = 0; redraw()
    elseif key == keys.left then
      if currentPage == "methods" then
        selectedMethodsCategory = selectedMethodsCategory - 1
        if selectedMethodsCategory < 1 then selectedMethodsCategory = 8 end
        scrollOffset = 0
        redraw()
      else
        cyclePage(-1)
      end
    elseif key == keys.right then
      if currentPage == "methods" then
        selectedMethodsCategory = selectedMethodsCategory + 1
        if selectedMethodsCategory > 8 then selectedMethodsCategory = 1 end
        scrollOffset = 0
        redraw()
      else
        cyclePage(1)
      end
    else
      if currentPage == "relay_test" then relayActionFromKey(key) end
    end
  end
end

local function autoRefresh()
  while running do
    sleep(config.refreshDelay)
    if running then refreshData(true) end
  end
end

refreshSelectedMonitor()
refreshData(true)
setStatus("Diagnostic console online")
parallel.waitForAny(handleKeyboard, autoRefresh, handleMonitorTouch)

if config.killAllRelaysOnExit then
  allRelaysOff(latestData.redstoneRelays)
end

term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
print("Programme termine.")
print("Fichiers :")
print("- blockreader_report.txt")
print("- blockreader_raw.txt")
