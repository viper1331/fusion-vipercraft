local refreshDelay = 2
local running = true
local statusMessage = ""
local currentPage = "summary"
local selectedRelayIndex = 1
local selectedSideIndex = 1
local selectedMonitorIndex = 0
local selectedMonitorName = nil

local SIDE_LIST = { "top", "bottom", "left", "right", "front", "back" }

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
  highlight = colors.blue
}

-- =========================
-- OUTILS
-- =========================
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
  if #text <= maxLen then
    return text
  end
  if maxLen <= 3 then
    return string.sub(text, 1, maxLen)
  end
  return string.sub(text, 1, maxLen - 3) .. "..."
end

local function sortedKeys(tbl)
  local keys = {}
  for k in pairs(tbl) do
    table.insert(keys, k)
  end
  table.sort(keys, function(a, b)
    return tostring(a) < tostring(b)
  end)
  return keys
end

local function flattenTable(tbl, indent, out, visited)
  indent = indent or 0
  out = out or {}
  visited = visited or {}

  if visited[tbl] then
    table.insert(out, string.rep(" ", indent) .. "<reference circulaire>")
    return out
  end

  visited[tbl] = true

  for _, key in ipairs(sortedKeys(tbl)) do
    local value = tbl[key]
    local prefix = string.rep(" ", indent) .. tostring(key) .. " = "

    if type(value) == "table" then
      table.insert(out, prefix .. "{")
      flattenTable(value, indent + 2, out, visited)
      table.insert(out, string.rep(" ", indent) .. "}")
    else
      table.insert(out, prefix .. tostring(value))
    end
  end

  return out
end

local function writeLinesToFile(filename, content)
  local file = fs.open(filename, "w")
  if not file then
    return false, "Impossible d'ouvrir le fichier"
  end

  for i, line in ipairs(content) do
    file.write(line)
    if i < #content then
      file.write("\n")
    end
  end

  file.close()
  return true
end

local function getPeripheralMethods(name)
  local ok, methods = safeCall(function()
    return peripheral.getMethods(name)
  end)

  if ok and type(methods) == "table" then
    table.sort(methods)
    return methods
  end

  return {}
end

local function hasMethod(name, wanted)
  local methods = getPeripheralMethods(name)
  for _, m in ipairs(methods) do
    if m == wanted then
      return true
    end
  end
  return false
end

-- =========================
-- DETECTION GENERALE
-- =========================
local function getPeripheralNamesByType(wantedType)
  local found = {}
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == wantedType then
      table.insert(found, name)
    end
  end
  table.sort(found)
  return found
end

local function getPeripheralNamesByTypeContains(text)
  local found = {}
  for _, name in ipairs(peripheral.getNames()) do
    local pType = tostring(peripheral.getType(name) or "")
    if string.find(pType, text, 1, true) then
      table.insert(found, name)
    end
  end
  table.sort(found)
  return found
end

local function getBlockReaders() return getPeripheralNamesByType("block_reader") end
local function getRedstoneRelays() return getPeripheralNamesByType("redstone_relay") end
local function getModems() return getPeripheralNamesByType("modem") end
local function getFusionControllers() return getPeripheralNamesByTypeContains("mekanismgenerators:fusion_reactor_controller") end
local function getInductionPorts() return getPeripheralNamesByType("inductionPort") end
local function getLaserAmplifiers() return getPeripheralNamesByType("laserAmplifier") end

-- =========================
-- DETECTION MONITEURS ROBUSTE
-- =========================
local function getMonitorCandidates()
  local found = {}

  for _, name in ipairs(peripheral.getNames()) do
    local pType = tostring(peripheral.getType(name) or "")
    local methods = getPeripheralMethods(name)

    local methodSet = {}
    for _, m in ipairs(methods) do
      methodSet[m] = true
    end

    local looksLikeMonitor =
      pType == "monitor"
      or string.find(string.lower(name), "monitor", 1, true)
      or (methodSet.getSize and methodSet.write and methodSet.setTextScale)

    if looksLikeMonitor then
      local info = {
        name = name,
        type = pType,
        methods = methods,
        width = "?",
        height = "?",
        ok = false
      }

      local wrapped = peripheral.wrap(name)
      if wrapped and methodSet.getSize then
        local ok, size = safeCall(function()
          return { wrapped.getSize() }
        end)
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
  local found = {}
  for _, info in ipairs(getMonitorCandidates()) do
    table.insert(found, info.name)
  end
  return found
end

local function getMonitorInfo(name)
  for _, info in ipairs(getMonitorCandidates()) do
    if info.name == name then
      return info
    end
  end

  return {
    name = name,
    type = "?",
    width = "?",
    height = "?",
    ok = false,
    methods = {}
  }
end

local function refreshSelectedMonitor()
  local monitors = getMonitors()

  if #monitors == 0 then
    selectedMonitorIndex = 0
    selectedMonitorName = nil
    return
  end

  -- Si aucun moniteur n'est choisi et qu'il n'y en a qu'un, on le prend automatiquement
  if selectedMonitorIndex == 0 and #monitors == 1 then
    selectedMonitorIndex = 1
  end

  if selectedMonitorIndex == 0 then
    selectedMonitorName = nil
    return
  end

  if selectedMonitorIndex < 1 then
    selectedMonitorIndex = 1
  end

  if selectedMonitorIndex > #monitors then
    selectedMonitorIndex = 1
  end

  selectedMonitorName = monitors[selectedMonitorIndex]
end

local function selectNextMonitor()
  local monitors = getMonitors()

  if #monitors == 0 then
    selectedMonitorIndex = 0
    selectedMonitorName = nil
    statusMessage = "Aucun moniteur detecte"
    return
  end

  if selectedMonitorIndex == 0 then
    selectedMonitorIndex = 1
  else
    selectedMonitorIndex = selectedMonitorIndex + 1
    if selectedMonitorIndex > #monitors then
      selectedMonitorIndex = 1
    end
  end

  selectedMonitorName = monitors[selectedMonitorIndex]
  local info = getMonitorInfo(selectedMonitorName)
  statusMessage = "Moniteur: " .. selectedMonitorName .. " (" .. tostring(info.width) .. "x" .. tostring(info.height) .. ")"
end

local function disableMonitorOutput()
  selectedMonitorIndex = 0
  selectedMonitorName = nil
  statusMessage = "Affichage moniteur desactive"
end

local function getSelectedMonitor()
  refreshSelectedMonitor()

  if not selectedMonitorName then
    return nil
  end

  local mon = peripheral.wrap(selectedMonitorName)
  if not mon then
    selectedMonitorIndex = 0
    selectedMonitorName = nil
    return nil
  end

  return mon
end

-- =========================
-- DONNEES
-- =========================
local function safeGetBlockData(reader)
  return safeCall(function()
    return reader.getBlockData()
  end)
end

local function getRelaySideInfo(relay, side)
  local info = {}

  local okAIn, valAIn = safeCall(function()
    return relay.getAnalogInput(side)
  end)

  local okAOut, valAOut = safeCall(function()
    return relay.getAnalogOutput(side)
  end)

  info.analogInput = okAIn and valAIn or "ERR"
  info.analogOutput = okAOut and valAOut or "ERR"

  if type(info.analogInput) == "number" then
    info.digitalInput = info.analogInput > 0
  else
    info.digitalInput = "ERR"
  end

  if type(info.analogOutput) == "number" then
    info.digitalOutput = info.analogOutput > 0
  else
    info.digitalOutput = "ERR"
  end

  return info
end

local function getModemInfo(modem)
  local info = {}

  local okLocalName, valLocalName = safeCall(function()
    return modem.getNameLocal()
  end)

  local okNamesRemote, valNamesRemote = safeCall(function()
    return modem.getNamesRemote()
  end)

  info.nameLocal = okLocalName and valLocalName or "N/A"
  info.namesRemote = okNamesRemote and valNamesRemote or {}

  return info
end

local function getReaderSummary(name)
  local reader = peripheral.wrap(name)
  if not reader then
    return { name = name, error = "wrap impossible" }
  end

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
  for _, name in ipairs(data.blockReaders) do
    table.insert(data.readerSummaries, getReaderSummary(name))
  end

  data.relaySummaries = {}
  for _, name in ipairs(data.redstoneRelays) do
    local relay = peripheral.wrap(name)
    local relayData = {
      name = name,
      methods = getPeripheralMethods(name),
      sides = {}
    }

    if relay then
      for _, side in ipairs(SIDE_LIST) do
        relayData.sides[side] = getRelaySideInfo(relay, side)
      end
    else
      relayData.error = "wrap impossible"
    end

    table.insert(data.relaySummaries, relayData)
  end

  data.modemSummaries = {}
  for _, name in ipairs(data.modems) do
    local modem = peripheral.wrap(name)
    if modem then
      table.insert(data.modemSummaries, {
        name = name,
        info = getModemInfo(modem)
      })
    else
      table.insert(data.modemSummaries, {
        name = name,
        error = "wrap impossible"
      })
    end
  end

  return data
end

-- =========================
-- AFFICHAGE
-- =========================
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
  text = tostring(text)
  if x <= w then
    writeAt(dev, x, y, string.sub(text, 1, w - x + 1), color, bg)
  end
end

local function center(dev, y, text, color)
  local w, _ = dev.getSize()
  local x = math.max(1, math.floor((w - #text) / 2) + 1)
  writeAt(dev, x, y, text, color)
end

local function drawHeader(dev, title)
  local w, _ = dev.getSize()
  dev.setBackgroundColor(colorsUI.headerBg)
  dev.setTextColor(colors.white)
  dev.setCursorPos(1, 1)
  dev.write(string.rep(" ", w))
  center(dev, 1, ellipsis(title, w), colors.white)
  dev.setBackgroundColor(colorsUI.bg)
  dev.setTextColor(colorsUI.text)
end

local function drawFooter(dev)
  local w, h = dev.getSize()
  dev.setBackgroundColor(colorsUI.headerBg)
  dev.setTextColor(colors.white)
  dev.setCursorPos(1, h)
  dev.write(string.rep(" ", w))

  local footer = "1 Res 2 Read 3 Rel 4 Net 5 Fus 6 Test 7 Meth | M Mon | N Off | X Stop | Q Quit"
  dev.setCursorPos(1, h)
  dev.write(ellipsis(footer, w))

  dev.setBackgroundColor(colorsUI.bg)
  dev.setTextColor(colorsUI.text)
end

local function drawStatus(dev)
  local w, h = dev.getSize()
  local y = h - 1

  dev.setBackgroundColor(colors.black)
  dev.setTextColor(colors.yellow)
  dev.setCursorPos(1, y)
  dev.write(string.rep(" ", w))

  local monitorInfo = selectedMonitorName and (" | Moniteur: " .. selectedMonitorName) or " | Moniteur: aucun"
  local fullStatus = (statusMessage or "") .. monitorInfo

  dev.setCursorPos(1, y)
  dev.write(ellipsis(fullStatus, w))

  dev.setTextColor(colorsUI.text)
  dev.setBackgroundColor(colorsUI.bg)
end

local function drawSummaryPage(dev, data)
  drawHeader(dev, "TABLEAU DE BORD DIAGNOSTIC")

  local w, h = dev.getSize()
  local y = 3
  local maxY = h - 3

  local function line(label, value, color)
    if y > maxY then return end
    local txt = string.format("%-18s %s", label, tostring(value))
    writeClipped(dev, 2, y, ellipsis(txt, w - 2), color or colorsUI.text)
    y = y + 1
  end

  line("Peripherals:", #data.peripherals, colorsUI.info)
  line("Block Readers:", #data.blockReaders, colorsUI.section)
  line("Relays:", #data.redstoneRelays, colorsUI.section)
  line("Monitors:", #data.monitors, colorsUI.section)
  line("Modems:", #data.modems, colorsUI.section)
  line("Fusion Ctrl:", #data.fusionControllers, colorsUI.section)
  line("Induction:", #data.inductionPorts, colorsUI.section)
  line("Laser Amp:", #data.laserAmplifiers, colorsUI.section)

  y = y + 1
  if y <= maxY then
    writeClipped(dev, 2, y, "Etat Block Readers :", colorsUI.title)
    y = y + 1
  end

  for _, r in ipairs(data.readerSummaries) do
    if y > maxY then break end

    local txt = ""
    local color = colorsUI.text

    if r.error then
      txt = r.name .. " | ERREUR"
      color = colorsUI.bad
    elseif r.chemical_id then
      local chem = tostring(r.chemical_id):gsub("mekanismgenerators:", "")
      txt = r.name .. " | " .. chem
      color = colorsUI.info
    elseif r.active ~= nil then
      txt = r.name .. " | " .. ((r.active == 1 and "ACTIF") or "INACTIF")
      txt = txt .. " | rs=" .. short(r.redstone)
      txt = txt .. " | crs=" .. short(r.current_redstone)
      color = (r.active == 1) and colorsUI.good or colorsUI.bad
    else
      txt = r.name .. " | Donnees"
      color = colorsUI.dim
    end

    writeClipped(dev, 4, y, ellipsis(txt, w - 4), color)
    y = y + 1
  end

  y = y + 1
  if y <= maxY then
    local monText
    if selectedMonitorName then
      local info = getMonitorInfo(selectedMonitorName)
      monText = "Moniteur actif : " .. selectedMonitorName .. " (" .. tostring(info.width) .. "x" .. tostring(info.height) .. ")"
    else
      monText = "Moniteur actif : aucun"
    end
    writeClipped(dev, 2, y, ellipsis(monText, w - 2), colorsUI.warn)
    y = y + 1
  end

  if y <= maxY then
    writeClipped(dev, 2, y, "M=moniteur suivant | N=aucun | 7=methodes", colorsUI.warn)
  end

  drawStatus(dev)
  drawFooter(dev)
end

local function drawBlockReadersPage(dev, data)
  drawHeader(dev, "DETAIL BLOCK READERS")
  local y = 3
  local _, h = dev.getSize()
  local maxY = h - 3

  if #data.blockReaders == 0 then
    writeClipped(dev, 2, y, "Aucun block_reader detecte", colorsUI.bad)
  else
    for _, name in ipairs(data.blockReaders) do
      if y > maxY then break end

      writeClipped(dev, 2, y, "[" .. name .. "]", colorsUI.title)
      y = y + 1

      local reader = peripheral.wrap(name)
      if reader then
        local ok, blockData = safeGetBlockData(reader)
        if ok and type(blockData) == "table" then
          local lines = flattenTable(blockData)
          for _, line in ipairs(lines) do
            if y > maxY then break end
            writeClipped(dev, 4, y, ellipsis(line, 999), colorsUI.text)
            y = y + 1
          end
        else
          writeClipped(dev, 4, y, "Erreur getBlockData : " .. tostring(blockData), colorsUI.bad)
          y = y + 1
        end
      else
        writeClipped(dev, 4, y, "Wrap impossible", colorsUI.bad)
        y = y + 1
      end

      y = y + 1
    end
  end

  drawStatus(dev)
  drawFooter(dev)
end

local function drawRelaysPage(dev, data)
  drawHeader(dev, "DETAIL REDSTONE RELAYS")
  local y = 3
  local _, h = dev.getSize()
  local maxY = h - 3

  if #data.relaySummaries == 0 then
    writeClipped(dev, 2, y, "Aucun redstone_relay detecte", colorsUI.bad)
  else
    for _, relay in ipairs(data.relaySummaries) do
      if y > maxY then break end

      writeClipped(dev, 2, y, "[" .. relay.name .. "]", colorsUI.title)
      y = y + 1

      if relay.error then
        writeClipped(dev, 4, y, relay.error, colorsUI.bad)
        y = y + 2
      else
        for _, side in ipairs(SIDE_LIST) do
          if y > maxY then break end
          local info = relay.sides[side]
          local line = string.format(
            "%-6s IN:%s OUT:%s AIN:%s AOUT:%s",
            side,
            short(info.digitalInput),
            short(info.digitalOutput),
            short(info.analogInput),
            short(info.analogOutput)
          )
          writeClipped(dev, 4, y, ellipsis(line, 999), colorsUI.text)
          y = y + 1
        end
        y = y + 1
      end
    end
  end

  drawStatus(dev)
  drawFooter(dev)
end

local function drawNetworkPage(dev, data)
  drawHeader(dev, "MODEM / RESEAU")
  local y = 3
  local _, h = dev.getSize()
  local maxY = h - 3

  if #data.modemSummaries == 0 then
    writeClipped(dev, 2, y, "Aucun modem detecte", colorsUI.bad)
  else
    for _, modemData in ipairs(data.modemSummaries) do
      if y > maxY then break end

      writeClipped(dev, 2, y, "[" .. modemData.name .. "]", colorsUI.title)
      y = y + 1

      if modemData.error then
        writeClipped(dev, 4, y, modemData.error, colorsUI.bad)
        y = y + 1
      else
        writeClipped(dev, 4, y, "Nom local : " .. short(modemData.info.nameLocal), colorsUI.info)
        y = y + 1
        writeClipped(dev, 4, y, "Peripherals distants : " .. #modemData.info.namesRemote, colorsUI.info)
        y = y + 1

        for _, remoteName in ipairs(modemData.info.namesRemote) do
          if y > maxY then break end

          local remoteType = "?"
          local modem = peripheral.wrap(modemData.name)
          if modem then
            local okType, valType = safeCall(function()
              return modem.getTypeRemote(remoteName)
            end)
            if okType then
              remoteType = tostring(valType)
            end
          end

          writeClipped(dev, 6, y, ellipsis("- " .. remoteName .. " -> " .. remoteType, 999), colorsUI.text)
          y = y + 1
        end

        y = y + 1
      end
    end
  end

  drawStatus(dev)
  drawFooter(dev)
end

local function drawFusionPage(dev, data)
  drawHeader(dev, "MEKANISM / FUSION")
  local y = 3

  writeClipped(dev, 2, y, "Fusion Controllers : " .. #data.fusionControllers, colorsUI.section); y = y + 1
  for _, name in ipairs(data.fusionControllers) do
    writeClipped(dev, 4, y, ellipsis("- " .. name, 999), colorsUI.text)
    y = y + 1
  end
  y = y + 1

  writeClipped(dev, 2, y, "Induction Ports : " .. #data.inductionPorts, colorsUI.section); y = y + 1
  for _, name in ipairs(data.inductionPorts) do
    writeClipped(dev, 4, y, ellipsis("- " .. name, 999), colorsUI.text)
    y = y + 1
  end
  y = y + 1

  writeClipped(dev, 2, y, "Laser Amplifiers : " .. #data.laserAmplifiers, colorsUI.section); y = y + 1
  for _, name in ipairs(data.laserAmplifiers) do
    writeClipped(dev, 4, y, ellipsis("- " .. name, 999), colorsUI.text)
    y = y + 1
  end

  drawStatus(dev)
  drawFooter(dev)
end

local function drawMethodsPage(dev, data)
  drawHeader(dev, "METHODES / DIAGNOSTIC")
  local y = 3
  local _, h = dev.getSize()
  local maxY = h - 3

  if y <= maxY then
    writeClipped(dev, 2, y, "Moniteurs detectes :", colorsUI.title)
    y = y + 1
  end

  if #data.monitorCandidates == 0 then
    if y <= maxY then
      writeClipped(dev, 4, y, "Aucun moniteur detecte", colorsUI.bad)
      y = y + 2
    end
  else
    for i, info in ipairs(data.monitorCandidates) do
      if y > maxY then break end
      local line = string.format("[%d] %s | type=%s | %sx%s", i, info.name, short(info.type), short(info.width), short(info.height))
      local color = (selectedMonitorName == info.name) and colorsUI.good or colorsUI.info
      writeClipped(dev, 4, y, ellipsis(line, 999), color)
      y = y + 1
    end
    y = y + 1
  end

  if y <= maxY then
    writeClipped(dev, 2, y, "Methodes redstone_relay :", colorsUI.title)
    y = y + 1
  end

  if #data.relaySummaries == 0 then
    if y <= maxY then
      writeClipped(dev, 4, y, "Aucun redstone_relay detecte", colorsUI.bad)
    end
  else
    for _, relay in ipairs(data.relaySummaries) do
      if y > maxY then break end
      writeClipped(dev, 4, y, "[" .. relay.name .. "]", colorsUI.section)
      y = y + 1

      if relay.methods and #relay.methods > 0 then
        for _, m in ipairs(relay.methods) do
          if y > maxY then break end
          writeClipped(dev, 6, y, "- " .. m, colorsUI.text)
          y = y + 1
        end
      else
        if y <= maxY then
          writeClipped(dev, 6, y, "Aucune methode detectee", colorsUI.bad)
          y = y + 1
        end
      end

      y = y + 1
    end
  end

  drawStatus(dev)
  drawFooter(dev)
end

local function relaySetAnalog(relayName, side, value)
  local relay = peripheral.wrap(relayName)
  if not relay then
    statusMessage = "Relay introuvable : " .. relayName
    return
  end

  local ok, err = safeCall(function()
    relay.setAnalogOutput(side, value)
  end)

  if ok then
    statusMessage = "Sortie " .. relayName .. " / " .. side .. " = " .. tostring(value)
  else
    statusMessage = "Erreur sortie : " .. tostring(err)
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
        pcall(function()
          relay.setAnalogOutput(side, 0)
        end)
      end
    end
  end
  statusMessage = "Toutes les sorties redstone ont ete coupees"
end

local function drawRelayTestPage(dev, data)
  drawHeader(dev, "MODE TEST REDSTONE RELAY")
  local y = 3

  if #data.redstoneRelays == 0 then
    writeClipped(dev, 2, y, "Aucun redstone_relay detecte", colorsUI.bad)
    drawStatus(dev)
    drawFooter(dev)
    return
  end

  if selectedRelayIndex < 1 then selectedRelayIndex = 1 end
  if selectedRelayIndex > #data.redstoneRelays then selectedRelayIndex = #data.redstoneRelays end
  if selectedSideIndex < 1 then selectedSideIndex = 1 end
  if selectedSideIndex > #SIDE_LIST then selectedSideIndex = #SIDE_LIST end

  local relayName = data.redstoneRelays[selectedRelayIndex]
  local side = SIDE_LIST[selectedSideIndex]
  local relay = peripheral.wrap(relayName)

  writeClipped(dev, 2, y, "Relay : " .. relayName, colorsUI.title); y = y + 1
  writeClipped(dev, 2, y, "Face  : " .. side, colorsUI.title); y = y + 2

  if relay then
    local info = getRelaySideInfo(relay, side)
    writeClipped(dev, 2, y, "Digital In  : " .. short(info.digitalInput), colorsUI.text); y = y + 1
    writeClipped(dev, 2, y, "Digital Out : " .. short(info.digitalOutput), colorsUI.text); y = y + 1
    writeClipped(dev, 2, y, "Analog In   : " .. short(info.analogInput), colorsUI.text); y = y + 1
    writeClipped(dev, 2, y, "Analog Out  : " .. short(info.analogOutput), colorsUI.text); y = y + 2
  else
    writeClipped(dev, 2, y, "Impossible de wrap le relay", colorsUI.bad); y = y + 2
  end

  writeClipped(dev, 2, y, "A/D relay | W/S face", colorsUI.section); y = y + 1
  writeClipped(dev, 2, y, "O=15 | F=0 | P=pulse", colorsUI.good); y = y + 1
  writeClipped(dev, 2, y, "0-9 analogique | X=stop", colorsUI.warn); y = y + 1
  writeClipped(dev, 2, y, "Backspace = 0", colorsUI.warn); y = y + 1

  drawStatus(dev)
  drawFooter(dev)
end

local function renderPage(dev, data)
  clearDevice(dev)

  if currentPage == "summary" then
    drawSummaryPage(dev, data)
  elseif currentPage == "block_readers" then
    drawBlockReadersPage(dev, data)
  elseif currentPage == "relays" then
    drawRelaysPage(dev, data)
  elseif currentPage == "network" then
    drawNetworkPage(dev, data)
  elseif currentPage == "fusion" then
    drawFusionPage(dev, data)
  elseif currentPage == "relay_test" then
    drawRelayTestPage(dev, data)
  elseif currentPage == "methods" then
    drawMethodsPage(dev, data)
  else
    drawSummaryPage(dev, data)
  end
end

-- =========================
-- EXPORT
-- =========================
local function buildFormattedReport(data)
  local out = {}
  table.insert(out, "=== RAPPORT DIAGNOSTIC ===")
  table.insert(out, "")

  table.insert(out, "[PERIPHERALS]")
  for _, name in ipairs(data.peripherals) do
    table.insert(out, name .. " -> " .. tostring(peripheral.getType(name)))
  end
  table.insert(out, "")

  table.insert(out, "[MONITORS DETECTES]")
  if #data.monitorCandidates == 0 then
    table.insert(out, "Aucun moniteur detecte")
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
        local lines = flattenTable(blockData)
        for _, line in ipairs(lines) do
          table.insert(out, line)
        end
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
    for _, m in ipairs(relayData.methods or {}) do
      table.insert(out, "- " .. m)
    end
    if relayData.error then
      table.insert(out, relayData.error)
    else
      for _, side in ipairs(SIDE_LIST) do
        local info = relayData.sides[side]
        table.insert(out,
          side ..
          " | DIN=" .. short(info.digitalInput) ..
          " | DOUT=" .. short(info.digitalOutput) ..
          " | AIN=" .. short(info.analogInput) ..
          " | AOUT=" .. short(info.analogOutput)
        )
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
      for _, remoteName in ipairs(modemData.info.namesRemote) do
        table.insert(out, "- " .. remoteName)
      end
    end
    table.insert(out, "")
  end

  return out
end

-- =========================
-- RAFRAICHISSEMENT
-- =========================
local latestData = {}

local function refreshMonitorSettings()
  local mon = getSelectedMonitor()
  if mon then
    pcall(function() mon.setTextScale(0.5) end)
    pcall(function() mon.setBackgroundColor(colorsUI.bg) end)
    pcall(function() mon.setTextColor(colorsUI.text) end)
  end
end

local function redraw()
  renderPage(term, latestData)

  local mon = getSelectedMonitor()
  if mon then
    renderPage(mon, latestData)
  end
end

local function refreshData()
  refreshSelectedMonitor()
  latestData = gatherAllData()
  if selectedMonitorName then
  statusMessage = "Moniteur actif : " .. selectedMonitorName
  elseif #latestData.monitors == 1 then
    statusMessage = "1 moniteur detecte"
  else
    statusMessage = "Aucun moniteur selectionne"
  end
  refreshMonitorSettings()
  redraw()
end

local function exportFormatted()
  local content = buildFormattedReport(latestData)
  local ok, err = writeLinesToFile("blockreader_report.txt", content)
  if ok then
    statusMessage = "Export OK : blockreader_report.txt"
  else
    statusMessage = "Erreur export : " .. tostring(err)
  end
  redraw()
end

local function exportRaw()
  local content = buildFormattedReport(latestData)
  local ok, err = writeLinesToFile("blockreader_raw.txt", content)
  if ok then
    statusMessage = "Export OK : blockreader_raw.txt"
  else
    statusMessage = "Erreur export : " .. tostring(err)
  end
  redraw()
end

-- =========================
-- CLAVIER
-- =========================
local function handleRelayTestKeys(key)
  local relays = latestData.redstoneRelays
  if #relays == 0 then return end

  local relayName = relays[selectedRelayIndex]
  local side = SIDE_LIST[selectedSideIndex]

  if key == keys.a then
    selectedRelayIndex = selectedRelayIndex - 1
    if selectedRelayIndex < 1 then selectedRelayIndex = #relays end
    statusMessage = "Relay : " .. relays[selectedRelayIndex]
    redraw()

  elseif key == keys.d then
    selectedRelayIndex = selectedRelayIndex + 1
    if selectedRelayIndex > #relays then selectedRelayIndex = 1 end
    statusMessage = "Relay : " .. relays[selectedRelayIndex]
    redraw()

  elseif key == keys.w then
    selectedSideIndex = selectedSideIndex - 1
    if selectedSideIndex < 1 then selectedSideIndex = #SIDE_LIST end
    statusMessage = "Face : " .. SIDE_LIST[selectedSideIndex]
    redraw()

  elseif key == keys.s then
    selectedSideIndex = selectedSideIndex + 1
    if selectedSideIndex > #SIDE_LIST then selectedSideIndex = 1 end
    statusMessage = "Face : " .. SIDE_LIST[selectedSideIndex]
    redraw()

  elseif key == keys.o then
    relaySetAnalog(relayName, side, 15)
    refreshData()

  elseif key == keys.f then
    relaySetAnalog(relayName, side, 0)
    refreshData()

  elseif key == keys.p then
    statusMessage = "Pulse " .. relayName .. " / " .. side
    redraw()
    relayPulse(relayName, side, 15, 1)
    refreshData()

  elseif key == keys.backspace then
    relaySetAnalog(relayName, side, 0)
    refreshData()

  elseif key == keys.x then
    allRelaysOff(latestData.redstoneRelays)
    refreshData()

  elseif key == keys.zero then relaySetAnalog(relayName, side, 0); refreshData()
  elseif key == keys.one then relaySetAnalog(relayName, side, 1); refreshData()
  elseif key == keys.two then relaySetAnalog(relayName, side, 2); refreshData()
  elseif key == keys.three then relaySetAnalog(relayName, side, 3); refreshData()
  elseif key == keys.four then relaySetAnalog(relayName, side, 4); refreshData()
  elseif key == keys.five then relaySetAnalog(relayName, side, 5); refreshData()
  elseif key == keys.six then relaySetAnalog(relayName, side, 6); refreshData()
  elseif key == keys.seven then relaySetAnalog(relayName, side, 7); refreshData()
  elseif key == keys.eight then relaySetAnalog(relayName, side, 8); refreshData()
  elseif key == keys.nine then relaySetAnalog(relayName, side, 9); refreshData()
  end
end

local function handleKeyboard()
  while running do
    local _, key = os.pullEvent("key")

    if key == keys.q then
      running = false

    elseif key == keys.one then
      currentPage = "summary"
      statusMessage = "Vue resume"
      redraw()

    elseif key == keys.two then
      currentPage = "block_readers"
      statusMessage = "Vue block readers"
      redraw()

    elseif key == keys.three then
      currentPage = "relays"
      statusMessage = "Vue redstone relays"
      redraw()

    elseif key == keys.four then
      currentPage = "network"
      statusMessage = "Vue reseau"
      redraw()

    elseif key == keys.five then
      currentPage = "fusion"
      statusMessage = "Vue fusion"
      redraw()

    elseif key == keys.six then
      currentPage = "relay_test"
      statusMessage = "Mode test relay"
      redraw()

    elseif key == keys.seven then
      currentPage = "methods"
      statusMessage = "Vue methodes"
      redraw()

    elseif key == keys.m then
      selectNextMonitor()
      refreshMonitorSettings()
      refreshData()

    elseif key == keys.n then
      disableMonitorOutput()
      refreshData()

    elseif key == keys.r then
      statusMessage = "Rafraichissement..."
      refreshData()

    elseif key == keys.e then
      exportFormatted()

    elseif key == keys.j then
      exportRaw()

    elseif key == keys.x then
      allRelaysOff(latestData.redstoneRelays)
      refreshData()

    else
      if currentPage == "relay_test" then
        handleRelayTestKeys(key)
      end
    end
  end
end

local function autoRefresh()
  while running do
    sleep(refreshDelay)
    if running then
      refreshData()
    end
  end
end

-- =========================
-- DEMARRAGE
-- =========================
refreshSelectedMonitor()
refreshData()
parallel.waitForAny(handleKeyboard, autoRefresh)

allRelaysOff(latestData.redstoneRelays)

term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
print("Programme termine.")
print("Fichiers :")
print("- blockreader_report.txt")
print("- blockreader_raw.txt")