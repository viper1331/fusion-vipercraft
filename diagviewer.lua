local config = {
  refreshDelay = 2,
  killAllRelaysOnExit = false,
  maxFlattenDepth = 5,
  maxFlattenLines = 260,
  defaultMonitorScale = 0.5,
  aliasFile = "diagviewer_aliases.lua",
  ui = {
    showBoxes = true,
    showTabBar = true,
    compactFooter = false,
    roleColors = {
      deuterium = colors.lightBlue,
      tritium = colors.pink,
      chemical = colors.cyan,
      active = colors.lime,
      inventory = colors.yellow,
      unknown = colors.lightGray,
    }
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
local selectedAliasIndex = 1
local aliasEditor = { active = false, target = nil, value = "" }

local SIDE_LIST = { "top", "bottom", "left", "right", "front", "back" }
local ROLE_ORDER = { "deuterium", "tritium", "chemical", "active", "inventory", "unknown" }
local PAGE_ORDER = {
  "summary",
  "block_readers",
  "relays",
  "network",
  "fusion",
  "relay_test",
  "methods",
  "aliases",
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
  aliases = "ALIAS MANAGER",
  monitors = "MONITOR MANAGEMENT",
  peripherals = "PERIPHERAL INVENTORY"
}

local SUGGESTED_ALIASES = {
  ["redstone_relay_0"] = "Charge Laser",
  ["redstone_relay_1"] = "Tank Deuterium",
  ["redstone_relay_2"] = "Tank Tritium",
  ["block_reader_1"] = "Reader Deuterium",
  ["block_reader_2"] = "Reader Tritium",
  ["block_reader_6"] = "Reader Aux",
  ["fusionReactorLogicAdapter_0"] = "Logic Adapter Fusion",
  ["mekanismgenerators:fusion_reactor_controller_3"] = "Fusion Reactor Controller",
  ["inductionPort_1"] = "Induction Matrix",
  ["laserAmplifier_1"] = "Laser Amplifier",
  ["monitor_2"] = "Moniteur Principal"
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
local aliases = {}
local statusState = { defaultMessage = "Ready", tempMessage = nil, tempUntil = 0 }
local hitboxes = { terminal = {}, monitor = {} }

local changePage
local scrollBy
local refreshData
local exportFormatted
local exportRaw
local allRelaysOff
local disableMonitorOutput
local cycleMonitorSelection
local selectMonitorByName
local redraw
local refreshMonitorSettings

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
  if statusState.tempMessage and os.clock() <= statusState.tempUntil then return statusState.tempMessage end
  statusState.tempMessage = nil
  return statusState.defaultMessage
end

local function encodeRaw(value, indent, visited, depth)
  indent = indent or 0
  visited = visited or {}
  depth = depth or 0
  if type(value) ~= "table" then
    if type(value) == "string" then return string.format("%q", value) end
    return tostring(value)
  end
  if visited[value] then return "\"<circular>\"" end
  if depth > config.maxFlattenDepth + 3 then return "\"<max depth>\"" end
  visited[value] = true
  local pad = string.rep(" ", indent)
  local nextPad = string.rep(" ", indent + 2)
  local parts = { "{" }
  for _, key in ipairs(sortedKeys(value)) do
    local keyRepr = type(key) == "string" and key:match("^[%a_][%w_]*$") and key or "[" .. encodeRaw(key, indent + 2, visited, depth + 1) .. "]"
    table.insert(parts, nextPad .. keyRepr .. " = " .. encodeRaw(value[key], indent + 2, visited, depth + 1) .. ",")
  end
  table.insert(parts, pad .. "}")
  visited[value] = nil
  return table.concat(parts, "\n")
end

local function loadAliases()
  aliases = {}
  if not fs.exists(config.aliasFile) then return end
  local ok, loaded = pcall(dofile, config.aliasFile)
  if ok and type(loaded) == "table" then
    for k, v in pairs(loaded) do
      if type(k) == "string" and type(v) == "string" and #v > 0 then aliases[k] = v end
    end
  else
    setStatus("Alias: fichier invalide", 3)
  end
end

local function saveAliases()
  local content = { "return " .. encodeRaw(aliases, 0, {}, 0) }
  local file = fs.open(config.aliasFile, "w")
  if not file then return false end
  file.write(content[1])
  file.close()
  return true
end

local function getAlias(name)
  return aliases[name]
end

local function setAlias(name, alias)
  if not name then return end
  local clean = tostring(alias or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if clean == "" then
    aliases[name] = nil
  else
    aliases[name] = clean
  end
  saveAliases()
end

local function removeAlias(name)
  aliases[name] = nil
  saveAliases()
end

local function getSuggestedAlias(name)
  return SUGGESTED_ALIASES[name]
end

local function getDisplayName(name)
  return getAlias(name) or name
end

local function flattenTable(tbl, indent, out, visited, options, state)
  indent = indent or 0; out = out or {}; visited = visited or {}; options = options or {}; state = state or { lines = 0 }
  local maxDepth = options.maxDepth or config.maxFlattenDepth
  local maxLines = options.maxLines or config.maxFlattenLines
  if state.lines >= maxLines then return out end
  if type(tbl) ~= "table" then
    table.insert(out, string.rep(" ", indent) .. tostring(tbl)); state.lines = state.lines + 1; return out
  end
  if visited[tbl] then table.insert(out, string.rep(" ", indent) .. "<circular reference>"); state.lines = state.lines + 1; return out end
  if indent / 2 >= maxDepth then table.insert(out, string.rep(" ", indent) .. "<max depth reached>"); state.lines = state.lines + 1; return out end
  visited[tbl] = true
  for _, key in ipairs(sortedKeys(tbl)) do
    if state.lines >= maxLines then table.insert(out, string.rep(" ", indent) .. "<line limit reached>"); break end
    local value = tbl[key]
    local prefix = string.rep(" ", indent) .. tostring(key) .. " = "
    if type(value) == "table" then
      table.insert(out, prefix .. "{"); state.lines = state.lines + 1
      flattenTable(value, indent + 2, out, visited, options, state)
      if state.lines < maxLines then table.insert(out, string.rep(" ", indent) .. "}"); state.lines = state.lines + 1 end
    else
      table.insert(out, prefix .. tostring(value)); state.lines = state.lines + 1
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
  if ok and type(methods) == "table" then table.sort(methods); return methods end
  return {}
end

local function hasMethods(methods, required)
  local set = {}
  for _, m in ipairs(methods or {}) do set[m] = true end
  for _, wanted in ipairs(required) do if not set[wanted] then return false end end
  return true
end

local function getPeripheralNamesByMatcher(matcher)
  local found = {}
  for _, name in ipairs(peripheral.getNames()) do
    local pType = tostring(peripheral.getType(name) or "")
    local methods = getPeripheralMethods(name)
    if matcher(name, pType, methods) then table.insert(found, name) end
  end
  table.sort(found)
  return found
end

local function getBlockReaders() return getPeripheralNamesByMatcher(function(_, pType, methods) return pType == "block_reader" or hasMethods(methods, { "getBlockData" }) end) end
local function getRedstoneRelays() return getPeripheralNamesByMatcher(function(_, pType, methods) return pType == "redstone_relay" or hasMethods(methods, { "setAnalogOutput", "getAnalogInput" }) end) end
local function getModems() return getPeripheralNamesByMatcher(function(_, pType, methods) return pType == "modem" or hasMethods(methods, { "getNamesRemote", "getNameLocal" }) end) end
local function getFusionControllers() return getPeripheralNamesByMatcher(function(name, pType) local s = string.lower(name .. " " .. pType) return s:find("fusion", 1, true) ~= nil end) end
local function getInductionPorts() return getPeripheralNamesByMatcher(function(name, pType) local s = string.lower(name .. " " .. pType) return s:find("induction", 1, true) ~= nil end) end
local function getLaserAmplifiers() return getPeripheralNamesByMatcher(function(name, pType) local s = string.lower(name .. " " .. pType) return s:find("laser", 1, true) ~= nil end) end

local function getMonitorCandidates()
  local found = {}
  for _, name in ipairs(peripheral.getNames()) do
    local pType = tostring(peripheral.getType(name) or "")
    local methods = getPeripheralMethods(name)
    local set = {}; for _, m in ipairs(methods) do set[m] = true end
    if pType == "monitor" or string.find(string.lower(name), "monitor", 1, true) or (set.getSize and set.write and set.setTextScale) then
      local info = { name = name, type = pType, methods = methods, width = "?", height = "?", ok = false }
      local mon = peripheral.wrap(name)
      if mon and set.getSize then
        local ok, size = safeCall(function() return { mon.getSize() } end)
        if ok then info.width = size[1] or "?"; info.height = size[2] or "?"; info.ok = true end
      end
      table.insert(found, info)
    end
  end
  table.sort(found, function(a, b) return a.name < b.name end)
  return found
end

local function getMonitors() local out = {}; for _, i in ipairs(getMonitorCandidates()) do table.insert(out, i.name) end; return out end
local function getMonitorInfo(name) for _, i in ipairs(getMonitorCandidates()) do if i.name == name then return i end end; return { name = name, type = "?", width = "?", height = "?", ok = false } end

selectMonitorByName = function(name, silent)
  local monitors = getMonitors()
  if type(name) ~= "string" or name == "" then return false end
  for i, monitorName in ipairs(monitors) do
    if monitorName == name then
      selectedMonitorName = monitorName
      selectedMonitorIndex = i
      if not silent then
        local info = getMonitorInfo(monitorName)
        setStatus("Moniteur actif: " .. monitorName .. " (" .. tostring(info.width) .. "x" .. tostring(info.height) .. ")", 2.5)
      end
      return true
    end
  end
  return false
end

local function selectMonitorByIndex(index)
  local monitors = getMonitors()
  if #monitors == 0 then selectedMonitorIndex = 0; selectedMonitorName = nil; setStatus("Aucun moniteur detecte", 2); return false end
  if type(index) ~= "number" then return false end
  local idx = math.floor(index)
  if idx < 1 or idx > #monitors then return false end
  return selectMonitorByName(monitors[idx])
end

local function refreshSelectedMonitor()
  local monitors = getMonitors()
  if #monitors == 0 then
    selectedMonitorIndex = 0
    selectedMonitorName = nil
    return nil
  end
  if selectedMonitorName then
    for i, monitorName in ipairs(monitors) do
      if monitorName == selectedMonitorName then
        selectedMonitorIndex = i
        return selectedMonitorName
      end
    end
    selectedMonitorName = nil
    selectedMonitorIndex = 0
    return nil
  end
  if selectedMonitorIndex >= 1 and selectedMonitorIndex <= #monitors then
    selectedMonitorName = monitors[selectedMonitorIndex]
    return selectedMonitorName
  end
  selectedMonitorIndex = 0
  selectedMonitorName = nil
  return nil
end

cycleMonitorSelection = function()
  local monitors = getMonitors()
  if #monitors == 0 then selectedMonitorIndex = 0; selectedMonitorName = nil; setStatus("Aucun moniteur detecte", 2); return false end
  refreshSelectedMonitor()
  local idx = 0
  if selectedMonitorName then
    for i, monitorName in ipairs(monitors) do if monitorName == selectedMonitorName then idx = i break end end
  end
  idx = (idx % #monitors) + 1
  return selectMonitorByName(monitors[idx])
end

local function selectNextMonitor() return cycleMonitorSelection() end
disableMonitorOutput = function() selectedMonitorIndex = 0; selectedMonitorName = nil; setStatus("Affichage moniteur desactive", 2) end
local function getSelectedMonitor() refreshSelectedMonitor(); return selectedMonitorName and peripheral.wrap(selectedMonitorName) or nil end

local function getReaderSummary(name)
  local reader = peripheral.wrap(name)
  if not reader then return { name = name, error = "wrap impossible" } end
  local ok, data = safeCall(function() return reader.getBlockData() end)
  if not ok or type(data) ~= "table" then return { name = name, error = tostring(data) } end
  local result = { name = name, raw = data, active = data.active_state, redstone = data.redstone, current_redstone = data.current_redstone, control_type = data.control_type, dumping = data.dumping }
  if data.chemical_tanks and data.chemical_tanks[1] and data.chemical_tanks[1].stored then
    result.chemical_id = data.chemical_tanks[1].stored.id
    result.chemical_amount = data.chemical_tanks[1].stored.amount
  end
  result.inventory_id = data.inventory_id
  return result
end

local function classifyReaderSummary(readerSummary)
  if readerSummary.error then return "unknown" end
  local chemId = string.lower(tostring(readerSummary.chemical_id or ""))
  if chemId:find("deuterium", 1, true) then return "deuterium" end
  if chemId:find("tritium", 1, true) then return "tritium" end
  if readerSummary.raw and readerSummary.raw.chemical_tanks then return "chemical" end
  if readerSummary.raw and readerSummary.raw.active_state ~= nil then return "active" end
  if readerSummary.inventory_id or (readerSummary.raw and readerSummary.raw.inventory_id) then return "inventory" end
  return "unknown"
end

local function classifyAllReaders(readerSummaries)
  local byName, counts = {}, {}
  for _, role in ipairs(ROLE_ORDER) do counts[role] = 0 end
  for _, summary in ipairs(readerSummaries or {}) do
    local role = classifyReaderSummary(summary)
    summary.role = role
    byName[summary.name] = role
    counts[role] = (counts[role] or 0) + 1
  end
  return { byName = byName, counts = counts }
end

local function getRelaySideInfo(relay, side)
  local okIn, valIn = safeCall(function() return relay.getAnalogInput(side) end)
  local okOut, valOut = safeCall(function() return relay.getAnalogOutput(side) end)
  local info = { analogInput = okIn and valIn or "ERR", analogOutput = okOut and valOut or "ERR" }
  info.digitalInput = type(info.analogInput) == "number" and info.analogInput > 0 or "ERR"
  info.digitalOutput = type(info.analogOutput) == "number" and info.analogOutput > 0 or "ERR"
  return info
end

local function getModemInfo(modem)
  local okL, localName = safeCall(function() return modem.getNameLocal() end)
  local okR, remotes = safeCall(function() return modem.getNamesRemote() end)
  return { nameLocal = okL and localName or "N/A", namesRemote = okR and remotes or {} }
end

local function safeWrap(name)
  local ok, wrapped = safeCall(function() return peripheral.wrap(name) end)
  if ok and wrapped then return wrapped end
  return nil
end

local function safeGetMethods(name)
  return getPeripheralMethods(name)
end

local function safeInvokeMethod(target, methodName, ...)
  if not target or type(target[methodName]) ~= "function" then
    return false, "method unavailable"
  end

  local args = { ... }
  return safeCall(function()
    return target[methodName](table.unpack(args))
  end)
end

local DANGEROUS_PREFIXES = {
  "set", "toggle", "write", "clear", "scroll", "turnOn", "turnOff", "open", "close",
  "push", "pull", "eject", "start", "stop", "activate", "deactivate", "fire", "launch",
}

local SAFE_PREFIXES = { "get", "is", "list", "size", "has" }

local EXPLICIT_SAFE_METHODS = {
  size = true,
  list = true,
  getEnergy = true,
  getEnergyStored = true,
  getMaxEnergy = true,
  getEnergyFilledPercentage = true,
  getEnergyNeeded = true,
  getLastInput = true,
  getLastOutput = true,
  getTransferCap = true,
  getInstalledCells = true,
  getInstalledProviders = true,
  getLength = true,
  getWidth = true,
  getHeight = true,
  isFormed = true,
  getNameLocal = true,
  getNamesRemote = true,
  getTypeRemote = true,
  getAnalogInput = true,
  getAnalogOutput = true,
  getInput = true,
  getOutput = true,
  getBlockData = true,
  getItemDetail = true,
  getItemLimit = true,
  tanks = true,
  isColour = true,
  isColor = true,
  getTextScale = true,
  getSize = true,
}

local METHODS_REQUIRING_PROFILES = {
  getAnalogInput = true,
  getAnalogOutput = true,
  getInput = true,
  getOutput = true,
  getTypeRemote = true,
  getItemDetail = true,
}

local function startsWith(text, prefix)
  return string.sub(text, 1, #prefix) == prefix
end

local function shouldSkipMethod(methodName)
  local low = string.lower(tostring(methodName or ""))
  if startsWith(low, "setcursor") then return true, "dangerous_prefix" end
  if low == "setmode" then return true, "dangerous_explicit" end
  for _, prefix in ipairs(DANGEROUS_PREFIXES) do
    if startsWith(low, string.lower(prefix)) then return true, "dangerous_prefix" end
  end
  return false
end

local function isSafeProbeMethod(methodName)
  if EXPLICIT_SAFE_METHODS[methodName] then return true end
  local low = string.lower(tostring(methodName or ""))
  for _, prefix in ipairs(SAFE_PREFIXES) do
    if startsWith(low, prefix) then return true end
  end
  return false
end

local function safeInvokeMethodMulti(target, methodName, ...)
  if not target or type(target[methodName]) ~= "function" then
    return false, nil, "method unavailable"
  end
  local args = { ... }
  local packed = table.pack(pcall(function()
    return target[methodName](table.unpack(args))
  end))
  if not packed[1] then return false, nil, tostring(packed[2]) end
  local values = {}
  for i = 2, packed.n do table.insert(values, packed[i]) end
  return true, values
end

local function normalizeProbeValues(values)
  local normalized = {}
  for i = 1, #(values or {}) do normalized[i] = values[i] end
  local returnType = (#normalized == 0) and "nil" or type(normalized[1])
  return normalized, returnType
end

local function probeCall(wrapped, methodName, callKey, ...)
  local ok, values, err = safeInvokeMethodMulti(wrapped, methodName, ...)
  if not ok then return callKey, { ok = false, error = tostring(err or "unknown error") } end
  local normalized, returnType = normalizeProbeValues(values)
  return callKey, { ok = true, returnType = returnType, values = normalized }
end

local function makeMethodSet(methods)
  local set = {}
  for _, methodName in ipairs(methods or {}) do set[methodName] = true end
  return set
end

local function registerProbeCall(targetTable, stats, wrapped, methodName, callKey, ...)
  local key, result = probeCall(wrapped, methodName, callKey, ...)
  targetTable[key] = result
  stats.attempted = stats.attempted + 1
  if result.ok then stats.ok = stats.ok + 1 else stats.failed = stats.failed + 1 end
  return key, result
end

local function probeInductionPort(name, wrapped, methods)
  local probes = {}
  local stats = { attempted = 0, ok = 0, failed = 0, skippedDangerous = 0, skippedNeedsArgs = 0 }
  if not wrapped then return probes, stats end
  local methodSet = makeMethodSet(methods)
  local orderedMethods = {
    "getEnergy", "getMaxEnergy", "getEnergyFilledPercentage", "getEnergyNeeded",
    "getLastInput", "getLastOutput", "getTransferCap", "getInstalledCells",
    "getInstalledProviders", "getLength", "getWidth", "getHeight", "isFormed", "getMode"
  }
  for _, methodName in ipairs(orderedMethods) do
    if methodSet[methodName] then registerProbeCall(probes, stats, wrapped, methodName, methodName) end
  end
  return probes, stats
end

local function probeFusionLogicAdapter(name, wrapped, methods)
  local probes = {}
  local stats = { attempted = 0, ok = 0, failed = 0, skippedDangerous = 0, skippedNeedsArgs = 0 }
  if not wrapped then return probes, stats end
  local methodSet = makeMethodSet(methods)
  local orderedMethods = {
    "isFormed", "isIgnited", "getCaseTemperature", "getPlasmaTemperature", "getPassiveGeneration",
    "getProductionRate", "getInjectionRate", "getIgnitionTemperature",
    "getEnvironmentalLoss", "getMinInjectionRate", "getMaxPlasmaTemperature", "getMaxCasingTemperature"
  }
  for _, methodName in ipairs(orderedMethods) do
    if methodSet[methodName] then registerProbeCall(probes, stats, wrapped, methodName, methodName) end
  end
  return probes, stats
end

local function probeFusionControllerInventory(name, wrapped, methods)
  local probes = {}
  local stats = { attempted = 0, ok = 0, failed = 0, skippedDangerous = 0, skippedNeedsArgs = 0 }
  if not wrapped then return probes, stats end
  local methodSet = makeMethodSet(methods)
  local occupiedSlots = {}

  if methodSet.size then registerProbeCall(probes, stats, wrapped, "size", "size") end
  if methodSet.list then
    local _, listProbe = registerProbeCall(probes, stats, wrapped, "list", "list")
    if listProbe.ok and type(listProbe.values[1]) == "table" then
      occupiedSlots = sortedKeys(listProbe.values[1])
    end
  end

  if methodSet.getItemDetail and #occupiedSlots > 0 then
    local count = 0
    for _, slot in ipairs(occupiedSlots) do
      count = count + 1
      if count > 72 then break end
      registerProbeCall(probes, stats, wrapped, "getItemDetail", "getItemDetail(" .. tostring(slot) .. ")", slot)
    end
  end

  if methodSet.getItemLimit and #occupiedSlots > 0 then
    local count = 0
    for _, slot in ipairs(occupiedSlots) do
      count = count + 1
      if count > 72 then break end
      registerProbeCall(probes, stats, wrapped, "getItemLimit", "getItemLimit(" .. tostring(slot) .. ")", slot)
    end
  end

  if methodSet.tanks then registerProbeCall(probes, stats, wrapped, "tanks", "tanks") end
  return probes, stats
end

local function getSpecializedProbes(name, pType, wrapped, methods)
  local lowName = string.lower(tostring(name or ""))
  local lowType = string.lower(tostring(pType or ""))
  if name == "inductionPort_1" or lowName:find("inductionport", 1, true) or lowType:find("induction", 1, true) then
    return probeInductionPort(name, wrapped, methods)
  end
  if name == "fusionReactorLogicAdapter_0" or lowName:find("fusionreactorlogicadapter", 1, true) then
    return probeFusionLogicAdapter(name, wrapped, methods)
  end
  if name == "mekanismgenerators:fusion_reactor_controller_3" then
    return probeFusionControllerInventory(name, wrapped, methods)
  end
  return {}, { attempted = 0, ok = 0, failed = 0, skippedDangerous = 0, skippedNeedsArgs = 0 }
end

local function mergeProbeStats(base, extra)
  return {
    attempted = (base and base.attempted or 0) + (extra and extra.attempted or 0),
    ok = (base and base.ok or 0) + (extra and extra.ok or 0),
    failed = (base and base.failed or 0) + (extra and extra.failed or 0),
    skippedDangerous = (base and base.skippedDangerous or 0) + (extra and extra.skippedDangerous or 0),
    skippedNeedsArgs = (base and base.skippedNeedsArgs or 0) + (extra and extra.skippedNeedsArgs or 0),
  }
end

local function probeDeviceMethods(name, pType, wrapped, methods)
  local probes, skippedDangerous, skippedNeedsArgs = {}, {}, {}
  local stats = { attempted = 0, ok = 0, failed = 0, skippedDangerous = 0, skippedNeedsArgs = 0 }
  if not wrapped then
    return probes, { skippedDangerous = skippedDangerous, skippedNeedsArgs = skippedNeedsArgs, wrapError = true }, stats
  end

  local methodSet = makeMethodSet(methods)

  for _, methodName in ipairs(methods or {}) do
    local skip, reason = shouldSkipMethod(methodName)
    if skip then
      skippedDangerous[methodName] = reason
      stats.skippedDangerous = stats.skippedDangerous + 1
    elseif isSafeProbeMethod(methodName) and not METHODS_REQUIRING_PROFILES[methodName] then
      registerProbeCall(probes, stats, wrapped, methodName, methodName)
    elseif METHODS_REQUIRING_PROFILES[methodName] then
      skippedNeedsArgs[methodName] = "profile_required"
      stats.skippedNeedsArgs = stats.skippedNeedsArgs + 1
    end
  end

  if methodSet.getAnalogInput then
    skippedNeedsArgs.getAnalogInput = nil
    for _, side in ipairs(SIDE_LIST) do registerProbeCall(probes, stats, wrapped, "getAnalogInput", "getAnalogInput(" .. side .. ")", side) end
  end
  if methodSet.getAnalogOutput then
    skippedNeedsArgs.getAnalogOutput = nil
    for _, side in ipairs(SIDE_LIST) do registerProbeCall(probes, stats, wrapped, "getAnalogOutput", "getAnalogOutput(" .. side .. ")", side) end
  end
  if methodSet.getInput then
    skippedNeedsArgs.getInput = nil
    for _, side in ipairs(SIDE_LIST) do registerProbeCall(probes, stats, wrapped, "getInput", "getInput(" .. side .. ")", side) end
  end
  if methodSet.getOutput then
    skippedNeedsArgs.getOutput = nil
    for _, side in ipairs(SIDE_LIST) do registerProbeCall(probes, stats, wrapped, "getOutput", "getOutput(" .. side .. ")", side) end
  end
  if methodSet.getTypeRemote and probes.getNamesRemote and probes.getNamesRemote.ok and type(probes.getNamesRemote.values[1]) == "table" then
    skippedNeedsArgs.getTypeRemote = nil
    for _, remoteName in ipairs(probes.getNamesRemote.values[1]) do
      registerProbeCall(probes, stats, wrapped, "getTypeRemote", "getTypeRemote(" .. tostring(remoteName) .. ")", remoteName)
    end
  end
  if methodSet.getItemDetail and probes.list and probes.list.ok and type(probes.list.values[1]) == "table" then
    skippedNeedsArgs.getItemDetail = nil
    local slots, count = sortedKeys(probes.list.values[1]), 0
    for _, slot in ipairs(slots) do
      count = count + 1
      if count > 12 then break end
      registerProbeCall(probes, stats, wrapped, "getItemDetail", "getItemDetail(" .. tostring(slot) .. ")", slot)
    end
  end

  stats.skippedNeedsArgs = #sortedKeys(skippedNeedsArgs)
  return probes, { skippedDangerous = skippedDangerous, skippedNeedsArgs = skippedNeedsArgs }, stats
end

local function summarizeProbeResult(probe)
  if not probe then return "N/A" end
  if not probe.ok then return "ERR -> " .. tostring(probe.error) end
  if not probe.values or #probe.values == 0 then return "OK -> nil" end
  local previews = {}
  for i = 1, #probe.values do
    local value = probe.values[i]
    if type(value) == "table" then
      local dump = flattenTable(value, 0, nil, nil, { maxDepth = 2, maxLines = 4 })
      previews[i] = "{" .. table.concat(dump, "; ") .. "}"
    else
      previews[i] = ellipsis(tostring(value), 120)
    end
  end
  return "OK -> " .. table.concat(previews, " | ")
end

local function getSuggestedRole(name, pType, methods, readerRole)
  local low = string.lower(tostring(name or "") .. " " .. tostring(pType or ""))
  if readerRole then return readerRole end
  if pType == "block_reader" then return "block_reader" end
  if pType == "redstone_relay" then return "relay" end
  if pType == "monitor" then return "monitor" end
  if pType == "modem" then return "modem" end
  if low:find("logic", 1, true) and low:find("fusion", 1, true) then return "logic_adapter" end
  if low:find("fusion", 1, true) then return "fusion_controller" end
  if low:find("induction", 1, true) then return "induction_port" end
  if low:find("laser", 1, true) then return "laser_amplifier" end
  if low:find("computer", 1, true) or low:find("turtle", 1, true) then return "computer" end
  if hasMethods(methods, { "setAnalogOutput", "getAnalogInput" }) then return "relay" end
  if hasMethods(methods, { "getBlockData" }) then return "block_reader" end
  if hasMethods(methods, { "getNamesRemote", "getNameLocal" }) then return "modem" end
  if hasMethods(methods, { "getSize", "setTextScale" }) then return "monitor" end
  return "other"
end

local function getDeviceSummaryByType(name, pType, wrapped, methods, readerSummaryMap)
  local summary, raw = {}, {}
  local low = string.lower(tostring(name or "") .. " " .. tostring(pType or ""))

  if pType == "block_reader" or hasMethods(methods, { "getBlockData" }) then
    local rs = readerSummaryMap and readerSummaryMap[name]
    if not rs then rs = getReaderSummary(name) end
    summary.readerRole = rs and rs.role or "unknown"
    summary.chemical_id = rs and rs.chemical_id or nil
    summary.chemical_amount = rs and rs.chemical_amount or nil
    summary.inventory_id = rs and rs.inventory_id or nil
    summary.active_state = rs and rs.active or nil
    summary.redstone = rs and rs.redstone or nil
    summary.current_redstone = rs and rs.current_redstone or nil
    raw.blockData = rs and rs.raw or nil
    if rs and rs.error then raw.error = rs.error end
    return summary, raw
  end

  if pType == "redstone_relay" or hasMethods(methods, { "setAnalogOutput", "getAnalogInput" }) then
    local activeSides, sideState = 0, {}
    if wrapped then
      for _, side in ipairs(SIDE_LIST) do
        local info = getRelaySideInfo(wrapped, side)
        sideState[side] = info
        if type(info.analogOutput) == "number" and info.analogOutput > 0 then activeSides = activeSides + 1 end
      end
    else
      raw.error = "wrap impossible"
    end
    summary.activeSides = activeSides
    summary.hasOutput = activeSides > 0
    raw.sides = sideState
    return summary, raw
  end

  if pType == "modem" or hasMethods(methods, { "getNamesRemote", "getNameLocal" }) then
    if wrapped then
      local info = getModemInfo(wrapped)
      local remoteTypes = {}
      for _, remoteName in ipairs(info.namesRemote or {}) do
        local ok, remoteType = safeCall(function() return peripheral.getType(remoteName) end)
        remoteTypes[remoteName] = ok and remoteType or "ERR"
      end
      summary.nameLocal = info.nameLocal
      summary.remoteCount = #(info.namesRemote or {})
      raw.namesRemote = info.namesRemote
      raw.remoteTypes = remoteTypes
    else
      raw.error = "wrap impossible"
    end
    return summary, raw
  end

  if pType == "monitor" or low:find("monitor", 1, true) then
    if wrapped then
      local ok, size = safeCall(function() return { wrapped.getSize() } end)
      summary.selected = name == selectedMonitorName
      summary.size = ok and { width = size[1], height = size[2] } or "ERR"
      raw.monitorInfo = { width = ok and size[1] or nil, height = ok and size[2] or nil }
    else
      raw.error = "wrap impossible"
    end
    return summary, raw
  end

  if low:find("fusion", 1, true) or low:find("logic", 1, true) or low:find("induction", 1, true) or low:find("laser", 1, true) then
    return summary, raw
  end

  summary.methodCount = #methods
  return summary, raw
end

local function buildAllDevicesDetailed(data)
  local result = {}
  local typeCounts = {}
  local aliasCount, roleCount, wrapOkCount = 0, 0, 0
  local probeTotals = { attempted = 0, ok = 0, failed = 0, skippedNeedsArgs = 0, skippedDangerous = 0 }
  local readerMap = {}
  for _, r in ipairs(data.readerSummaries or {}) do readerMap[r.name] = r end

  for _, name in ipairs(data.peripherals or {}) do
    local pType = tostring(peripheral.getType(name) or "unknown")
    local methods = safeGetMethods(name)
    local wrapped = safeWrap(name)
    local alias = getAlias(name)
    local suggestedRole = getSuggestedRole(name, pType, methods, readerMap[name] and readerMap[name].role or nil)
    local summary, raw = getDeviceSummaryByType(name, pType, wrapped, methods, readerMap)
    local genericProbes, probeMeta, genericProbeStats = probeDeviceMethods(name, pType, wrapped, methods)
    local specializedProbes, specializedProbeStats = getSpecializedProbes(name, pType, wrapped, methods)
    local probeStats = mergeProbeStats(genericProbeStats, specializedProbeStats)
    summary.probeCalls = probeStats.attempted
    summary.probeOk = probeStats.ok
    summary.probeFailed = probeStats.failed
    summary.probeSkippedNeedsArgs = probeStats.skippedNeedsArgs
    summary.probeSkippedDangerous = probeStats.skippedDangerous

    result[name] = {
      name = name,
      type = pType,
      alias = alias,
      suggestedRole = suggestedRole,
      methods = methods,
      wrapped = wrapped ~= nil,
      probes = {
        generic = genericProbes,
        specialized = specializedProbes,
      },
      probeMeta = probeMeta,
      probeStats = probeStats,
      summary = summary,
      raw = raw,
    }

    probeTotals.attempted = probeTotals.attempted + (probeStats.attempted or 0)
    probeTotals.ok = probeTotals.ok + (probeStats.ok or 0)
    probeTotals.failed = probeTotals.failed + (probeStats.failed or 0)
    probeTotals.skippedNeedsArgs = probeTotals.skippedNeedsArgs + (probeStats.skippedNeedsArgs or 0)
    probeTotals.skippedDangerous = probeTotals.skippedDangerous + (probeStats.skippedDangerous or 0)

    typeCounts[pType] = (typeCounts[pType] or 0) + 1
    if alias then aliasCount = aliasCount + 1 end
    if suggestedRole and suggestedRole ~= "other" then roleCount = roleCount + 1 end
    if wrapped then wrapOkCount = wrapOkCount + 1 end
  end

  data.deviceStats = {
    total = #data.peripherals,
    byType = typeCounts,
    withAlias = aliasCount,
    withSuggestedRole = roleCount,
    wrapOk = wrapOkCount,
    probeTotals = probeTotals,
  }
  return result
end

local function gatherAllData()
  local data = {}
  data.peripherals = peripheral.getNames(); table.sort(data.peripherals)
  data.blockReaders = getBlockReaders()
  data.redstoneRelays = getRedstoneRelays()
  data.monitors = getMonitors()
  data.monitorCandidates = getMonitorCandidates()
  data.modems = getModems()
  data.fusionControllers = getFusionControllers()
  data.inductionPorts = getInductionPorts()
  data.laserAmplifiers = getLaserAmplifiers()
  data.computers = getPeripheralNamesByMatcher(function(name, pType)
    local low = string.lower(name .. " " .. pType)
    return low:find("computer", 1, true) ~= nil or low:find("turtle", 1, true) ~= nil
  end)

  data.readerSummaries = {}
  for _, name in ipairs(data.blockReaders) do table.insert(data.readerSummaries, getReaderSummary(name)) end
  data.readerClassification = classifyAllReaders(data.readerSummaries)

  data.relaySummaries = {}
  for _, name in ipairs(data.redstoneRelays) do
    local relay = peripheral.wrap(name)
    local relayData = { name = name, methods = getPeripheralMethods(name), sides = {}, activeSides = 0 }
    if relay then
      for _, side in ipairs(SIDE_LIST) do
        relayData.sides[side] = getRelaySideInfo(relay, side)
        if type(relayData.sides[side].analogOutput) == "number" and relayData.sides[side].analogOutput > 0 then relayData.activeSides = relayData.activeSides + 1 end
      end
    else
      relayData.error = "wrap impossible"
    end
    table.insert(data.relaySummaries, relayData)
  end

  data.modemSummaries = {}
  for _, name in ipairs(data.modems) do
    local modem = peripheral.wrap(name)
    table.insert(data.modemSummaries, modem and { name = name, info = getModemInfo(modem) } or { name = name, error = "wrap impossible" })
  end
  local totalRemote = 0
  for _, m in ipairs(data.modemSummaries) do if m.info and m.info.namesRemote then totalRemote = totalRemote + #m.info.namesRemote end end
  data.totalRemotePeripherals = totalRemote

  data.aliases = aliases
  data.allDevicesDetailed = buildAllDevicesDetailed(data)
  return data
end

local function computeLayout(w, h)
  if w >= 95 and h >= 30 then return { mode = "large", columns = 3 } end
  if w >= 65 and h >= 20 then return { mode = "standard", columns = 2 } end
  return { mode = "compact", columns = 1 }
end

local function clearDevice(dev)
  dev.setBackgroundColor(colorsUI.bg); dev.setTextColor(colorsUI.text); dev.clear(); dev.setCursorPos(1, 1)
end
local function writeAt(dev, x, y, text, color, bg)
  if bg then dev.setBackgroundColor(bg) end
  dev.setCursorPos(x, y); dev.setTextColor(color or colorsUI.text); dev.write(tostring(text or "")); dev.setTextColor(colorsUI.text)
  if bg then dev.setBackgroundColor(colorsUI.bg) end
end
local function writeClipped(dev, x, y, text, color, bg)
  local w = ({ dev.getSize() })[1]
  if x > w then return end
  writeAt(dev, x, y, string.sub(tostring(text or ""), 1, w - x + 1), color, bg)
end
local function center(dev, y, text, color)
  local w = ({ dev.getSize() })[1]
  local t = tostring(text or "")
  writeAt(dev, math.max(1, math.floor((w - #t) / 2) + 1), y, t, color)
end
local function drawHLine(dev, y, color)
  local w = ({ dev.getSize() })[1]
  writeAt(dev, 1, y, string.rep("-", w), color or colorsUI.dim)
end
local function drawBox(dev, x, y, width, height, title, borderColor)
  if width < 3 or height < 3 then return end
  local right, bottom = x + width - 1, y + height - 1
  local bc = borderColor or colorsUI.box
  writeAt(dev, x, y, "+" .. string.rep("-", width - 2) .. "+", bc)
  for row = y + 1, bottom - 1 do writeAt(dev, x, row, "|", bc); writeAt(dev, right, row, "|", bc) end
  writeAt(dev, x, bottom, "+" .. string.rep("-", width - 2) .. "+", bc)
  if title and #title > 0 and width > 6 then writeClipped(dev, x + 2, y, " " .. title .. " ", colorsUI.title) end
end

local function getHitboxBucket(source)
  return source == "monitor" and hitboxes.monitor or hitboxes.terminal
end

local function clearHitboxes(source)
  if source then
    local bucket = getHitboxBucket(source)
    for i = #bucket, 1, -1 do bucket[i] = nil end
    return
  end
  clearHitboxes("terminal")
  clearHitboxes("monitor")
end

local function addHitbox(source, id, x1, y1, x2, y2, action)
  if type(action) ~= "function" then return end
  local bx1, by1 = math.floor(math.min(x1, x2)), math.floor(math.min(y1, y2))
  local bx2, by2 = math.floor(math.max(x1, x2)), math.floor(math.max(y1, y2))
  table.insert(getHitboxBucket(source), { id = id, x1 = bx1, y1 = by1, x2 = bx2, y2 = by2, action = action })
end

local function handleClick(x, y, source)
  local bucket = getHitboxBucket(source)
  for i = #bucket, 1, -1 do
    local hb = bucket[i]
    if x >= hb.x1 and x <= hb.x2 and y >= hb.y1 and y <= hb.y2 then
      hb.action(source, x, y, hb.id)
      return true
    end
  end
  return false
end

local function drawButton(dev, source, id, x, y, label, opts)
  opts = opts or {}
  local text = " " .. tostring(label or "") .. " "
  local fg = opts.fg or colors.white
  local bg = opts.bg or colors.gray
  local active = opts.active and true or false
  local activeBg = opts.activeBg or colorsUI.tabActiveBg
  local activeFg = opts.activeFg or colors.white
  writeAt(dev, x, y, text, active and activeFg or fg, active and activeBg or bg)
  addHitbox(source, id, x, y, x + #text - 1, y, opts.onClick)
  return #text
end

local function drawPanel(dev, panel)
  if config.ui.showBoxes then drawBox(dev, panel.x, panel.y, panel.w, panel.h, panel.title, colorsUI.dim) end
  local y = panel.y + 1
  for _, line in ipairs(panel.lines or {}) do
    if y >= panel.y + panel.h then break end
    writeClipped(dev, panel.x + 1, y, ellipsis(line.text, panel.w - 2), line.color)
    y = y + 1
  end
end

local function makeLine(text, color) return { text = tostring(text or ""), color = color or colorsUI.text } end
local function roleColor(role) return config.ui.roleColors[role or "unknown"] or colorsUI.text end
local function roleBadge(role) return "[" .. string.upper(role or "unknown") .. "]" end

local function pageLabel(page) return PAGE_TITLES[page] or page end
local function monitorStateText(data)
  if selectedMonitorName then
    local i = getMonitorInfo(selectedMonitorName)
    return string.format("Monitor: %s (%sx%s)", getDisplayName(selectedMonitorName), tostring(i.width), tostring(i.height))
  end
  return #data.monitors > 0 and string.format("Monitor: OFF (%d detected)", #data.monitors) or "Monitor: none"
end

local function drawHeader(dev)
  local w = ({ dev.getSize() })[1]
  writeAt(dev, 1, 1, string.rep(" ", w), colors.white, colorsUI.headerBg)
  center(dev, 1, ellipsis("VIPERCRAFT DIAGVIEWER :: " .. pageLabel(currentPage), w), colors.white)
  drawHLine(dev, 2, colorsUI.dim)
end

local function drawTabs(dev, source)
  if not config.ui.showTabBar then return end
  local w = ({ dev.getSize() })[1]
  local x = 1
  local labels = {
    summary = "Summary",
    block_readers = "Readers",
    relays = "Relays",
    network = "Network",
    fusion = "Fusion",
    relay_test = "Relay Test",
    methods = "Methods",
    monitors = "Monitors",
    aliases = "Aliases",
    peripherals = "Devices",
  }
  for _, page in ipairs(PAGE_ORDER) do
    local label = labels[page] or page
    local width = #label + 2
    if x + width - 1 <= w then
      x = x + drawButton(dev, source, "tab:" .. page, x, 3, label, {
        active = page == currentPage,
        bg = colorsUI.tabBg,
        activeBg = colorsUI.tabActiveBg,
        onClick = function() changePage(page) end,
      })
    else
      break
    end
  end
  drawHLine(dev, 4, colorsUI.dim)
end

local function drawStatusBar(dev, data)
  local w, h = dev.getSize()
  writeAt(dev, 1, h - 1, string.rep(" ", w), colors.white, colorsUI.statusBg)
  writeClipped(dev, 1, h - 1, ellipsis(getCurrentStatus() .. " | " .. monitorStateText(data), w), colors.yellow, colorsUI.statusBg)
end

local function drawFooter(dev, source)
  local w, h = dev.getSize()
  writeAt(dev, 1, h, string.rep(" ", w), colors.white, colorsUI.footerBg)
  local x = 1
  local actions = {
    { id = "refresh", label = "Refresh", onClick = function() setStatus("Rafraichissement...", 1); refreshData(true) end },
    { id = "export_report", label = "Export Report", onClick = function() exportFormatted() end },
    { id = "export_raw", label = "Export Raw", onClick = function() exportRaw() end },
    { id = "stop_relays", label = "Stop Relays", onClick = function() allRelaysOff(latestData.redstoneRelays); refreshData(true) end },
    { id = "scroll_up", label = "Up", onClick = function() scrollBy(-3) end },
    { id = "scroll_down", label = "Down", onClick = function() scrollBy(3) end },
    { id = "scroll_top", label = "Top", onClick = function() scrollOffset = 0; redraw() end },
    { id = "scroll_bottom", label = "Bottom", onClick = function() scrollOffset = 99999; redraw() end },
  }
  for _, action in ipairs(actions) do
    local width = #action.label + 2
    if x + width - 1 > w then break end
    x = x + drawButton(dev, source, "footer:" .. action.id, x, h, action.label, { bg = colorsUI.footerBg, onClick = action.onClick })
  end
end

local function renderScrollable(dev, lines)
  local w, h = dev.getSize()
  local contentTop, contentBottom = config.ui.showTabBar and 5 or 4, h - 2
  local viewHeight = contentBottom - contentTop + 1
  local maxOffset = math.max(0, #lines - viewHeight)
  if scrollOffset < 0 then scrollOffset = 0 end
  if scrollOffset > maxOffset then scrollOffset = maxOffset end
  if config.ui.showBoxes then drawBox(dev, 1, contentTop - 1, w, viewHeight + 2, "CONTENT", colorsUI.dim) end
  for i = 1, viewHeight do
    local line = lines[scrollOffset + i]
    if line then writeClipped(dev, 2, contentTop + i - 1, ellipsis(line.text, w - 3), line.color) end
  end
  local info = string.format("Rows %d-%d/%d", math.min(#lines, scrollOffset + 1), math.min(#lines, scrollOffset + viewHeight), #lines)
  writeClipped(dev, math.max(1, w - #info), h - 1, info, colorsUI.dim)
end

local function drawSummaryDashboard(dev, data)
  local w, h = dev.getSize()
  local top, bottom = config.ui.showTabBar and 5 or 4, h - 2
  local lh = bottom - top + 1
  local layout = computeLayout(w, lh)
  local cols = layout.columns
  local panelW = math.floor((w - (cols + 1)) / cols)
  local panelH = math.max(5, math.floor((lh - 3) / 2))
  local panels = {
    { title = "Hardware", lines = {
      makeLine("Peripherals: " .. #data.peripherals, colorsUI.info),
      makeLine("Block readers: " .. #data.blockReaders),
      makeLine("Relays: " .. #data.redstoneRelays),
      makeLine("Modems: " .. #data.modems),
      makeLine("Monitors: " .. #data.monitors)
    } },
    { title = "Readers by role", lines = {} },
    { title = "Relay activity", lines = {} },
    { title = "Network", lines = {
      makeLine("Remote peripherals: " .. (data.totalRemotePeripherals or 0), colorsUI.warn),
      makeLine("Modems detected: " .. #data.modemSummaries),
    } },
    { title = "Fusion stack", lines = {
      makeLine("Controllers: " .. #data.fusionControllers),
      makeLine("Induction ports: " .. #data.inductionPorts),
      makeLine("Laser amplifiers: " .. #data.laserAmplifiers),
    } },
    { title = "Display", lines = {
      makeLine(monitorStateText(data), colorsUI.info),
      makeLine("Layout: " .. layout.mode),
      makeLine("Alias file: " .. config.aliasFile, colorsUI.dim),
    } },
  }
  for _, role in ipairs(ROLE_ORDER) do table.insert(panels[2].lines, makeLine(role .. ": " .. tostring(data.readerClassification.counts[role] or 0), roleColor(role))) end
  local activeRelay = 0
  for _, r in ipairs(data.relaySummaries) do if (r.activeSides or 0) > 0 then activeRelay = activeRelay + 1 end end
  table.insert(panels[3].lines, makeLine("Relays actifs: " .. activeRelay, activeRelay > 0 and colorsUI.good or colorsUI.warn))
  for _, r in ipairs(data.relaySummaries) do if (r.activeSides or 0) > 0 then table.insert(panels[3].lines, makeLine("- " .. getDisplayName(r.name) .. " (" .. r.activeSides .. ")", colorsUI.good)) end end
  if activeRelay == 0 then table.insert(panels[3].lines, makeLine("Aucune sortie active", colorsUI.dim)) end

  for i, p in ipairs(panels) do
    local col = ((i - 1) % cols) + 1
    local row = math.floor((i - 1) / cols) + 1
    local px = 1 + (col - 1) * (panelW + 1)
    local py = top + (row - 1) * (panelH + 1)
    if py + panelH - 1 <= bottom then drawPanel(dev, { x = px, y = py, w = panelW, h = panelH, title = p.title, lines = p.lines }) end
  end
end

local function buildPageLines(data)
  local lines = {}
  if currentPage == "block_readers" then
    table.insert(lines, makeLine("DETAILED BLOCK READER DIAGNOSTICS", colorsUI.title))
    for _, r in ipairs(data.readerSummaries) do
      table.insert(lines, makeLine("[" .. getDisplayName(r.name) .. "] <" .. r.name .. "> " .. roleBadge(r.role), roleColor(r.role)))
      if r.error then table.insert(lines, makeLine("  ERROR: " .. r.error, colorsUI.bad)) else
        table.insert(lines, makeLine("  chemical_id=" .. short(r.chemical_id) .. " amount=" .. short(r.chemical_amount), colorsUI.info))
        for _, d in ipairs(flattenTable(r.raw, 0, nil, nil, { maxDepth = config.maxFlattenDepth, maxLines = config.maxFlattenLines })) do table.insert(lines, makeLine("  " .. d)) end
      end
      table.insert(lines, makeLine(""))
    end
  elseif currentPage == "relays" then
    table.insert(lines, makeLine("Use visual relay dashboard (non-scroll)", colorsUI.dim))
  elseif currentPage == "network" then
    table.insert(lines, makeLine("MODEM NETWORK DIAGNOSTICS", colorsUI.title))
    for _, m in ipairs(data.modemSummaries) do
      local head = "[" .. getDisplayName(m.name) .. "] <" .. m.name .. ">"
      table.insert(lines, makeLine(head, colorsUI.section))
      if m.error then table.insert(lines, makeLine("  " .. m.error, colorsUI.bad)) else
        table.insert(lines, makeLine("  local: " .. short(m.info.nameLocal), colorsUI.info))
        table.insert(lines, makeLine("  remotes: " .. #m.info.namesRemote, colorsUI.warn))
        for _, rn in ipairs(m.info.namesRemote) do table.insert(lines, makeLine("   - " .. getDisplayName(rn) .. " <" .. rn .. ">")) end
      end
    end
  elseif currentPage == "fusion" then
    table.insert(lines, makeLine("FUSION ECOSYSTEM", colorsUI.title))
    local function addList(title, arr)
      table.insert(lines, makeLine(title .. " (" .. #arr .. ")", colorsUI.section))
      for _, n in ipairs(arr) do table.insert(lines, makeLine(" - " .. getDisplayName(n) .. " <" .. n .. ">", colorsUI.text)) end
      table.insert(lines, makeLine(""))
    end
    addList("Fusion controllers", data.fusionControllers)
    addList("Induction ports", data.inductionPorts)
    addList("Laser amplifiers", data.laserAmplifiers)
    table.insert(lines, makeLine("Reader roles useful for fusion:", colorsUI.section))
    for _, r in ipairs(data.readerSummaries) do table.insert(lines, makeLine(" - " .. getDisplayName(r.name) .. " => " .. r.role, roleColor(r.role))) end
  elseif currentPage == "relay_test" then
    table.insert(lines, makeLine("RELAY TEST", colorsUI.title))
    if #data.redstoneRelays == 0 then table.insert(lines, makeLine("No relay detected", colorsUI.bad)) else
      local relayName = data.redstoneRelays[selectedRelayIndex] or data.redstoneRelays[1]
      local side = SIDE_LIST[selectedSideIndex]
      table.insert(lines, makeLine("Selected relay: " .. getDisplayName(relayName) .. " <" .. relayName .. ">", colorsUI.info))
      table.insert(lines, makeLine("Selected side: " .. side, colorsUI.info))
      table.insert(lines, makeLine("A/D relay | W/S side | O=15 F=0 P=pulse | 0-9 analog | Backspace or X off", colorsUI.section))
    end
  elseif currentPage == "methods" then
    local categories = { "all", "monitors", "block_readers", "redstone_relays", "modems", "fusion", "induction", "lasers" }
    local category = categories[selectedMethodsCategory]
    table.insert(lines, makeLine("METHOD EXPLORER :: " .. category, colorsUI.title))
    table.insert(lines, makeLine("Left/Right switch category", colorsUI.section))
    local function addMethods(title, names)
      table.insert(lines, makeLine("[" .. title .. "]", colorsUI.section))
      if #names == 0 then table.insert(lines, makeLine("  - none", colorsUI.bad)); return end
      for _, n in ipairs(names) do
        local suffix = latestData.readerClassification.byName[n] and (" role=" .. latestData.readerClassification.byName[n]) or ""
        table.insert(lines, makeLine("  " .. getDisplayName(n) .. " <" .. n .. ">" .. suffix, colorsUI.info))
        local methods = getPeripheralMethods(n)
        if #methods == 0 then table.insert(lines, makeLine("    (no methods)", colorsUI.bad)) else for _, m in ipairs(methods) do table.insert(lines, makeLine("    - " .. m)) end end
      end
    end
    if category == "all" or category == "monitors" then addMethods("monitors", data.monitors) end
    if category == "all" or category == "block_readers" then addMethods("block_readers", data.blockReaders) end
    if category == "all" or category == "redstone_relays" then addMethods("redstone_relays", data.redstoneRelays) end
    if category == "all" or category == "modems" then addMethods("modems", data.modems) end
    if category == "all" or category == "fusion" then addMethods("fusion controllers", data.fusionControllers) end
    if category == "all" or category == "induction" then addMethods("induction ports", data.inductionPorts) end
    if category == "all" or category == "lasers" then addMethods("laser amplifiers", data.laserAmplifiers) end
  elseif currentPage == "monitors" then
    table.insert(lines, makeLine("MONITOR MANAGEMENT", colorsUI.title))
    table.insert(lines, makeLine("Detected monitors: " .. #data.monitorCandidates, colorsUI.info))
    table.insert(lines, makeLine(selectedMonitorName and ("Active monitor: " .. getDisplayName(selectedMonitorName) .. " <" .. selectedMonitorName .. ">") or "Active monitor: OFF", selectedMonitorName and colorsUI.good or colorsUI.warn))
    table.insert(lines, makeLine("M: next monitor | N: disable output", colorsUI.section))
    for i, info in ipairs(data.monitorCandidates) do
      local mark = info.name == selectedMonitorName and "*" or " "
      table.insert(lines, makeLine(string.format("%s [%d] %s <%s> %sx%s", mark, i, getDisplayName(info.name), info.name, short(info.width), short(info.height)), info.name == selectedMonitorName and colorsUI.good or colorsUI.text))
    end
  elseif currentPage == "peripherals" then
    table.insert(lines, makeLine("PERIPHERAL INVENTORY", colorsUI.title))
    for _, n in ipairs(data.peripherals) do
      local alias = getAlias(n)
      local sug = getSuggestedAlias(n)
      local extra = alias and (" alias=" .. alias) or (sug and (" suggested=" .. sug) or "")
      table.insert(lines, makeLine(string.format("- %s <%s> type=%s%s", getDisplayName(n), n, tostring(peripheral.getType(n)), extra), colorsUI.text))
    end
  elseif currentPage == "aliases" then
    table.insert(lines, makeLine("Use dedicated alias editor panel", colorsUI.dim))
  end
  return lines
end

local function drawRelayBlock(dev, relay, x, y, w, h)
  drawBox(dev, x, y, w, h, getDisplayName(relay.name), colorsUI.dim)
  writeClipped(dev, x + 1, y + 1, "<" .. relay.name .. ">", colorsUI.dim)
  writeClipped(dev, x + 1, y + 2, "Active sides: " .. tostring(relay.activeSides or 0), (relay.activeSides or 0) > 0 and colorsUI.good or colorsUI.warn)
  local faceLine = { "top", "bottom", "left", "right", "front", "back" }
  for i, side in ipairs(faceLine) do
    local info = relay.sides[side]
    local out = info and info.analogOutput or "ERR"
    local active = type(out) == "number" and out > 0
    local line = string.format("%s:%s", string.sub(side, 1, 1), short(out))
    writeClipped(dev, x + 1 + ((i - 1) % 3) * math.floor((w - 2) / 3), y + 3 + math.floor((i - 1) / 3), line, active and colorsUI.good or colorsUI.dim)
  end
end

local function drawRelaysDashboard(dev, data)
  local w, h = dev.getSize()
  local top, bottom = config.ui.showTabBar and 5 or 4, h - 2
  local areaH = bottom - top + 1
  if #data.relaySummaries == 0 then writeClipped(dev, 2, top, "No redstone relay detected", colorsUI.bad); return end
  local cols = computeLayout(w, areaH).columns
  local blockW = math.max(20, math.floor((w - (cols + 1)) / cols))
  local blockH = 7
  local perPage = cols * math.max(1, math.floor(areaH / (blockH + 1)))
  local offset = math.max(0, scrollOffset)
  if offset > math.max(0, #data.relaySummaries - perPage) then offset = math.max(0, #data.relaySummaries - perPage); scrollOffset = offset end
  for i = 1, perPage do
    local idx = offset + i
    local relay = data.relaySummaries[idx]
    if not relay then break end
    local col = ((i - 1) % cols) + 1
    local row = math.floor((i - 1) / cols) + 1
    drawRelayBlock(dev, relay, 1 + (col - 1) * (blockW + 1), top + (row - 1) * (blockH + 1), blockW, blockH)
  end
end

local function buildAliasRows(data)
  local rows = {}
  for _, name in ipairs(data.peripherals or {}) do
    local pType = tostring(peripheral.getType(name) or "?")
    local role = data.readerClassification.byName[name]
    table.insert(rows, { name = name, pType = pType, alias = getAlias(name), suggested = getSuggestedAlias(name), role = role })
  end
  return rows
end

local function drawMonitorControls(dev, source, x, y, data)
  local curX = x
  for i, mon in ipairs(data.monitors or {}) do
    local label = "Select M" .. tostring(i - 1)
    curX = curX + drawButton(dev, source, "monitor:select:" .. mon, curX, y, label, {
      active = selectedMonitorName == mon,
      onClick = function() selectMonitorByName(mon); refreshMonitorSettings(); redraw() end,
    })
    if curX > ({ dev.getSize() })[1] - 8 then break end
  end
  curX = curX + drawButton(dev, source, "monitor:next", curX, y, "Next Monitor", { onClick = function() cycleMonitorSelection(); refreshMonitorSettings(); redraw() end })
  drawButton(dev, source, "monitor:off", curX, y, "Monitor Off", { onClick = function() disableMonitorOutput(); redraw() end })
end

local function drawMonitorsPage(dev, source, data)
  local w, h = dev.getSize()
  local top = config.ui.showTabBar and 5 or 4
  local bottom = h - 2
  drawBox(dev, 1, top - 1, w, bottom - top + 2, "MONITOR MANAGEMENT", colorsUI.dim)
  local active = selectedMonitorName and getMonitorInfo(selectedMonitorName) or nil
  writeClipped(dev, 3, top, "Detected: " .. tostring(#data.monitorCandidates), colorsUI.info)
  writeClipped(dev, 3, top + 1, selectedMonitorName and ("Active: " .. selectedMonitorName .. " (" .. tostring(active.width) .. "x" .. tostring(active.height) .. ")") or "Active: OFF", selectedMonitorName and colorsUI.good or colorsUI.warn)
  writeClipped(dev, 3, top + 2, "Output mode: " .. (selectedMonitorName and "monitor" or "terminal-only"), colorsUI.section)
  drawMonitorControls(dev, source, 3, top + 3, data)

  local rowY = top + 5
  for i, info in ipairs(data.monitorCandidates) do
    if rowY > bottom - 1 then break end
    local selected = info.name == selectedMonitorName
    local line = string.format("[%d] %s <%s> size=%sx%s type=%s status=%s selected=%s", i, getDisplayName(info.name), info.name, short(info.width), short(info.height), tostring(info.type), info.ok and "OK" or "ERR", selected and "yes" or "no")
    writeClipped(dev, 3, rowY, ellipsis(line, w - 6), selected and colorsUI.good or colorsUI.text)
    addHitbox(source, "monitor:line:" .. info.name, 3, rowY, w - 3, rowY, function() selectMonitorByName(info.name); refreshMonitorSettings(); redraw() end)
    local btnLabel = selected and "Using" or "Use"
    local btnX = math.max(3, w - (#btnLabel + 4))
    drawButton(dev, source, "monitor:use:" .. info.name, btnX, rowY, btnLabel, {
      active = selected,
      onClick = function() selectMonitorByName(info.name); refreshMonitorSettings(); redraw() end,
    })
    rowY = rowY + 1
  end
end

local function drawAliasesPage(dev, data)
  local w, h = dev.getSize()
  local top, bottom = config.ui.showTabBar and 5 or 4, h - 2
  local rows = buildAliasRows(data)
  if #rows == 0 then writeClipped(dev, 2, top, "No peripherals detected", colorsUI.bad); return end
  if selectedAliasIndex < 1 then selectedAliasIndex = 1 end
  if selectedAliasIndex > #rows then selectedAliasIndex = #rows end
  local view = bottom - top + 1
  if selectedAliasIndex - scrollOffset > view then scrollOffset = selectedAliasIndex - view end
  if selectedAliasIndex <= scrollOffset then scrollOffset = selectedAliasIndex - 1 end
  if scrollOffset < 0 then scrollOffset = 0 end

  drawBox(dev, 1, top - 1, w, view + 2, "ALIASES (Enter/T rename, Del/Bksp clear, Esc cancel)", colorsUI.dim)
  for i = 1, view do
    local idx = scrollOffset + i
    local row = rows[idx]
    if not row then break end
    local y = top + i - 1
    local selected = idx == selectedAliasIndex
    local aliasText = row.alias or "-"
    local suggestText = (not row.alias and row.suggested) and (" sugg=" .. row.suggested) or ""
    local roleText = row.role and (" role=" .. row.role) or ""
    local line = string.format("%s %-18s type=%-14s alias=%s%s%s", selected and ">" or " ", ellipsis(row.name, 18), ellipsis(row.pType, 14), ellipsis(aliasText, 20), suggestText, roleText)
    writeClipped(dev, 2, y, line, selected and colors.black or (row.role and roleColor(row.role) or colorsUI.text), selected and colorsUI.highlight or nil)
  end
  if aliasEditor.active then
    drawBox(dev, 2, bottom - 3, w - 2, 4, "EDIT ALIAS", colorsUI.title)
    writeClipped(dev, 4, bottom - 2, "Target: " .. aliasEditor.target, colorsUI.info)
    writeClipped(dev, 4, bottom - 1, "> " .. aliasEditor.value .. "_", colorsUI.good)
  end
end

local function relaySetAnalog(relayName, side, value)
  local relay = peripheral.wrap(relayName)
  if not relay then setStatus("Relay introuvable : " .. relayName, 2.5); return end
  local ok, err = safeCall(function() relay.setAnalogOutput(side, value) end)
  setStatus(ok and ("Sortie " .. relayName .. " / " .. side .. " = " .. tostring(value)) or ("Erreur sortie : " .. tostring(err)), 2)
end

local function relayPulse(relayName, side, value, duration) relaySetAnalog(relayName, side, value); sleep(duration or 1); relaySetAnalog(relayName, side, 0) end
allRelaysOff = function(relays)
  for _, relayName in ipairs(relays or {}) do
    local relay = peripheral.wrap(relayName)
    if relay then for _, side in ipairs(SIDE_LIST) do pcall(function() relay.setAnalogOutput(side, 0) end) end end
  end
  setStatus("Toutes les sorties redstone ont ete coupees", 2.5)
end

local function buildFormattedReport(data)
  local out = { "=== RAPPORT DIAGNOSTIC PREMIUM ===", "", "[SYNTHESIS]" }
  table.insert(out, "total_peripherals = " .. #data.peripherals)
  table.insert(out, "block_readers = " .. #data.blockReaders)
  table.insert(out, "redstone_relays = " .. #data.redstoneRelays)
  table.insert(out, "modems = " .. #data.modems)
  table.insert(out, "fusion_controllers = " .. #data.fusionControllers)
  table.insert(out, "induction_ports = " .. #data.inductionPorts)
  table.insert(out, "laser_amplifiers = " .. #data.laserAmplifiers)
  table.insert(out, "remote_peripherals = " .. (data.totalRemotePeripherals or 0))
  table.insert(out, "reader_roles = " .. encodeRaw(data.readerClassification.counts, 0, {}, 0))
  table.insert(out, "")

  table.insert(out, "[ALIASES]")
  for _, n in ipairs(data.peripherals) do
    table.insert(out, string.format("%s | alias=%s | suggested=%s", n, short(getAlias(n)), short(getSuggestedAlias(n))))
  end
  table.insert(out, "")

  table.insert(out, "[BLOCK_READERS]")
  for _, r in ipairs(data.readerSummaries) do
    table.insert(out, string.format("----- %s (%s) alias=%s role=%s -----", r.name, getDisplayName(r.name), short(getAlias(r.name)), short(r.role)))
    if r.error then table.insert(out, "Erreur : " .. r.error) else
      table.insert(out, "chemical_id=" .. short(r.chemical_id) .. " chemical_amount=" .. short(r.chemical_amount))
      local dump = flattenTable(r.raw, 0, nil, nil, { maxDepth = config.maxFlattenDepth, maxLines = config.maxFlattenLines })
      for _, line in ipairs(dump) do table.insert(out, line) end
    end
    table.insert(out, "")
  end

  table.insert(out, "[RELAYS]")
  for _, relay in ipairs(data.relaySummaries) do
    table.insert(out, string.format("----- %s (%s) activeSides=%d -----", relay.name, getDisplayName(relay.name), relay.activeSides or 0))
    if relay.error then table.insert(out, relay.error) else
      for _, side in ipairs(SIDE_LIST) do local i = relay.sides[side]; table.insert(out, side .. " | AOUT=" .. short(i.analogOutput) .. " | AIN=" .. short(i.analogInput)) end
    end
    table.insert(out, "")
  end

  table.insert(out, "[DEVICES COMPLETE]")
  local stats = data.deviceStats or {}
  table.insert(out, "total_devices = " .. short(stats.total))
  table.insert(out, "devices_with_alias = " .. short(stats.withAlias))
  table.insert(out, "devices_with_suggested_role = " .. short(stats.withSuggestedRole))
  table.insert(out, "devices_wrap_ok = " .. short(stats.wrapOk))
  table.insert(out, "probe_attempted = " .. short(stats.probeTotals and stats.probeTotals.attempted))
  table.insert(out, "probe_ok = " .. short(stats.probeTotals and stats.probeTotals.ok))
  table.insert(out, "probe_failed = " .. short(stats.probeTotals and stats.probeTotals.failed))
  table.insert(out, "probe_skipped_requires_args = " .. short(stats.probeTotals and stats.probeTotals.skippedNeedsArgs))
  table.insert(out, "probe_skipped_dangerous = " .. short(stats.probeTotals and stats.probeTotals.skippedDangerous))
  table.insert(out, "devices_by_type = " .. encodeRaw(stats.byType or {}, 0, {}, 0))
  table.insert(out, "")

  local function addDeviceSection(title, names)
    if #names == 0 then return end
    table.insert(out, "## " .. title .. " (" .. #names .. ")")
    for _, name in ipairs(names) do
      local d = data.allDevicesDetailed and data.allDevicesDetailed[name]
      if d then
        table.insert(out, "----- " .. d.name .. " -----")
        table.insert(out, "Type: " .. short(d.type))
        table.insert(out, "Alias: " .. short(d.alias))
        table.insert(out, "Role: " .. short(d.suggestedRole))
        table.insert(out, "Wrapped: " .. tostring(d.wrapped))
        table.insert(out, "Methods:")
        if #d.methods == 0 then table.insert(out, "- (none)") else for _, m in ipairs(d.methods) do table.insert(out, "- " .. m) end end
        table.insert(out, "Summary:")
        local summaryDump = flattenTable(d.summary, 0, nil, nil, { maxDepth = config.maxFlattenDepth, maxLines = 60 })
        if #summaryDump == 0 then table.insert(out, "- (none)") else for _, line in ipairs(summaryDump) do table.insert(out, "- " .. line) end end
        table.insert(out, "Probes:")
        local genericProbeKeys = sortedKeys(d.probes and d.probes.generic or {})
        if #genericProbeKeys == 0 then
          table.insert(out, "- Generic: (none)")
        else
          table.insert(out, "- Generic:")
          for _, callKey in ipairs(genericProbeKeys) do
            table.insert(out, "  - " .. callKey .. " -> " .. summarizeProbeResult(d.probes.generic[callKey]))
          end
        end
        local specializedProbeKeys = sortedKeys(d.probes and d.probes.specialized or {})
        if #specializedProbeKeys == 0 then
          table.insert(out, "- Specialized: (none)")
        else
          table.insert(out, "- Specialized:")
          for _, callKey in ipairs(specializedProbeKeys) do
            table.insert(out, "  - " .. callKey .. " -> " .. summarizeProbeResult(d.probes.specialized[callKey]))
          end
        end
        local skippedDangerous = sortedKeys(d.probeMeta and d.probeMeta.skippedDangerous or {})
        if #skippedDangerous > 0 then table.insert(out, "Skipped dangerous: " .. table.concat(skippedDangerous, ", ")) end
        local skippedNeedsArgs = sortedKeys(d.probeMeta and d.probeMeta.skippedNeedsArgs or {})
        if #skippedNeedsArgs > 0 then table.insert(out, "Skipped requires args: " .. table.concat(skippedNeedsArgs, ", ")) end
        table.insert(out, "")
      end
    end
  end

  local grouped = {
    monitors = data.monitors or {},
    block_readers = data.blockReaders or {},
    redstone_relays = data.redstoneRelays or {},
    modems = data.modems or {},
    fusion_controllers = data.fusionControllers or {},
    induction_ports = data.inductionPorts or {},
    laser_amplifiers = data.laserAmplifiers or {},
    computers = data.computers or {},
  }
  local seen = {}
  for _, arr in pairs(grouped) do for _, n in ipairs(arr) do seen[n] = true end end
  local others = {}
  for _, n in ipairs(data.peripherals or {}) do if not seen[n] then table.insert(others, n) end end
  table.sort(others)

  addDeviceSection("monitors", grouped.monitors)
  addDeviceSection("block_readers", grouped.block_readers)
  addDeviceSection("redstone_relays", grouped.redstone_relays)
  addDeviceSection("modems", grouped.modems)
  addDeviceSection("fusion controllers / logic adapters", grouped.fusion_controllers)
  addDeviceSection("induction ports", grouped.induction_ports)
  addDeviceSection("laser amplifiers", grouped.laser_amplifiers)
  addDeviceSection("computers", grouped.computers)
  addDeviceSection("other peripherals", others)

  return out
end

local function buildRawReport(data)
  local monitorStates = {}
  for i, info in ipairs(data.monitorCandidates or {}) do
    table.insert(monitorStates, {
      index = i,
      name = info.name,
      width = info.width,
      height = info.height,
      selected = info.name == selectedMonitorName,
      ok = info.ok,
    })
  end
  local snapshot = {
    generatedAt = os.date and os.date("%Y-%m-%d %H:%M:%S") or "N/A",
    selectedMonitorName = selectedMonitorName,
    selectedMonitorIndex = selectedMonitorIndex,
    monitorSelectionActive = selectedMonitorName ~= nil,
    monitorStates = monitorStates,
    currentPage = currentPage,
    aliases = aliases,
    allDevicesDetailed = data.allDevicesDetailed,
    deviceStats = data.deviceStats,
    latestData = data,
  }
  return { "-- blockreader_raw.txt", "return " .. encodeRaw(snapshot, 0, {}, 0) }
end

refreshMonitorSettings = function()
  local mon = getSelectedMonitor()
  if mon then pcall(function() mon.setTextScale(config.defaultMonitorScale) end); pcall(function() mon.setBackgroundColor(colorsUI.bg) end); pcall(function() mon.setTextColor(colorsUI.text) end) end
end

local function renderPage(dev, data, source)
  clearHitboxes(source)
  clearDevice(dev)
  drawHeader(dev)
  drawTabs(dev, source)
  if currentPage == "summary" then drawSummaryDashboard(dev, data)
  elseif currentPage == "relays" then drawRelaysDashboard(dev, data)
  elseif currentPage == "aliases" then drawAliasesPage(dev, data)
  elseif currentPage == "monitors" then drawMonitorsPage(dev, source, data)
  else renderScrollable(dev, buildPageLines(data)) end
  drawStatusBar(dev, data)
  drawFooter(dev, source)
end

redraw = function()
  renderPage(term, latestData, "terminal")
  local mon = getSelectedMonitor(); if mon then renderPage(mon, latestData, "monitor") else clearHitboxes("monitor") end
end

refreshData = function(skipDefaultStatus)
  refreshSelectedMonitor()
  latestData = gatherAllData()
  if not skipDefaultStatus then
    if selectedMonitorName then setStatus("Moniteur actif : " .. getDisplayName(selectedMonitorName))
    elseif #latestData.monitors == 1 then setStatus("1 moniteur detecte")
    else setStatus("Aucun moniteur selectionne") end
  end
  refreshMonitorSettings(); redraw()
end

exportFormatted = function()
  local ok, err = writeLinesToFile("blockreader_report.txt", buildFormattedReport(latestData))
  setStatus(ok and "Export OK : blockreader_report.txt" or ("Erreur export : " .. tostring(err)), ok and 3 or 4)
  redraw()
end

exportRaw = function()
  local ok, err = writeLinesToFile("blockreader_raw.txt", buildRawReport(latestData))
  setStatus(ok and "Export RAW OK : blockreader_raw.txt" or ("Erreur export RAW : " .. tostring(err)), ok and 3 or 4)
  redraw()
end

changePage = function(nextPage) currentPage = nextPage; scrollOffset = 0; setStatus("Page: " .. pageLabel(nextPage), 1.2); redraw() end
local function cyclePage(step)
  local idx = 1; for i, p in ipairs(PAGE_ORDER) do if p == currentPage then idx = i end end
  idx = idx + step; if idx < 1 then idx = #PAGE_ORDER end; if idx > #PAGE_ORDER then idx = 1 end
  changePage(PAGE_ORDER[idx])
end
scrollBy = function(delta) scrollOffset = math.max(0, scrollOffset + delta); redraw() end

local function startAliasEdit()
  local rows = buildAliasRows(latestData)
  local row = rows[selectedAliasIndex]
  if not row then return end
  aliasEditor.active = true
  aliasEditor.target = row.name
  aliasEditor.value = row.alias or ""
  setStatus("Edition alias: " .. row.name, 2)
  redraw()
end

local function commitAliasEdit()
  if not aliasEditor.active then return end
  setAlias(aliasEditor.target, aliasEditor.value)
  aliasEditor.active = false
  refreshData(true)
  setStatus("Alias enregistre", 2)
end

local function cancelAliasEdit() aliasEditor.active = false; setStatus("Edition alias annulee", 1.5); redraw() end

local function handleRelayTestKey(key)
  local relays = latestData.redstoneRelays or {}
  if #relays == 0 then return end
  local relayName = relays[selectedRelayIndex] or relays[1]
  local side = SIDE_LIST[selectedSideIndex]
  if key == keys.a then selectedRelayIndex = selectedRelayIndex - 1; if selectedRelayIndex < 1 then selectedRelayIndex = #relays end; redraw()
  elseif key == keys.d then selectedRelayIndex = selectedRelayIndex + 1; if selectedRelayIndex > #relays then selectedRelayIndex = 1 end; redraw()
  elseif key == keys.w then selectedSideIndex = selectedSideIndex - 1; if selectedSideIndex < 1 then selectedSideIndex = #SIDE_LIST end; redraw()
  elseif key == keys.s then selectedSideIndex = selectedSideIndex + 1; if selectedSideIndex > #SIDE_LIST then selectedSideIndex = 1 end; redraw()
  elseif key == keys.o then relaySetAnalog(relayName, side, 15); refreshData(true)
  elseif key == keys.f or key == keys.backspace then relaySetAnalog(relayName, side, 0); refreshData(true)
  elseif key == keys.p then relayPulse(relayName, side, 15, 1); refreshData(true)
  elseif key == keys.x then allRelaysOff(latestData.redstoneRelays); refreshData(true)
  elseif key >= keys.zero and key <= keys.nine then relaySetAnalog(relayName, side, key - keys.zero); refreshData(true) end
end

local function handleMonitorTouch(side, x, y)
  if not selectedMonitorName or side ~= selectedMonitorName then return end
  handleClick(x, y, "monitor")
end

local function handleTerminalClick(x, y)
  handleClick(x, y, "terminal")
end

local function handleInputEvents()
  while running do
    local ev = { os.pullEvent() }
    local event = ev[1]
    if event == "monitor_touch" then
      handleMonitorTouch(ev[2], ev[3], ev[4])
    elseif event == "mouse_click" then
      handleTerminalClick(ev[3], ev[4])
    elseif event == "char" then
      if aliasEditor.active then aliasEditor.value = aliasEditor.value .. ev[2]; redraw() end
    elseif event == "key" then
      local key = ev[2]
      if aliasEditor.active then
        if key == keys.enter then commitAliasEdit()
        elseif key == keys.backspace then aliasEditor.value = string.sub(aliasEditor.value, 1, math.max(0, #aliasEditor.value - 1)); redraw()
        elseif key == keys.escape then cancelAliasEdit() end
      else
        if key == keys.q then running = false
        elseif key == keys.one then changePage("summary")
        elseif key == keys.two then changePage("block_readers")
        elseif key == keys.three then changePage("relays")
        elseif key == keys.four then changePage("network")
        elseif key == keys.five then changePage("fusion")
        elseif key == keys.six then changePage("relay_test")
        elseif key == keys.seven then changePage("methods")
        elseif key == keys.eight then changePage("aliases")
        elseif key == keys.nine then changePage("monitors")
        elseif key == keys.zero then changePage("peripherals")
        elseif key == keys.m then selectNextMonitor(); refreshMonitorSettings(); refreshData(true)
        elseif key == keys.n then disableMonitorOutput(); refreshData(true)
        elseif key == keys.r then setStatus("Rafraichissement...", 1); refreshData(true)
        elseif key == keys.e then exportFormatted()
        elseif key == keys.j then exportRaw()
        elseif key == keys.x then allRelaysOff(latestData.redstoneRelays); refreshData(true)
        elseif key == keys.up then
          if currentPage == "aliases" then selectedAliasIndex = math.max(1, selectedAliasIndex - 1); redraw() else scrollBy(-1) end
        elseif key == keys.down then
          if currentPage == "aliases" then selectedAliasIndex = math.min(#(latestData.peripherals or {}), selectedAliasIndex + 1); redraw() else scrollBy(1) end
        elseif key == keys.pageUp then scrollBy(-8)
        elseif key == keys.pageDown then scrollBy(8)
        elseif key == keys.home then scrollOffset = 0; redraw()
        elseif key == keys.left then if currentPage == "methods" then selectedMethodsCategory = math.max(1, selectedMethodsCategory - 1); redraw() else cyclePage(-1) end
        elseif key == keys.right then if currentPage == "methods" then selectedMethodsCategory = math.min(8, selectedMethodsCategory + 1); redraw() else cyclePage(1) end
        elseif (key == keys.enter or key == keys.t) and currentPage == "aliases" then startAliasEdit()
        elseif (key == keys.delete or key == keys.backspace) and currentPage == "aliases" then
          local rows = buildAliasRows(latestData)
          if rows[selectedAliasIndex] then removeAlias(rows[selectedAliasIndex].name); refreshData(true); setStatus("Alias supprime", 2) end
        elseif currentPage == "relay_test" then handleRelayTestKey(key)
        end
      end
    end
  end
end

local function autoRefresh() while running do sleep(config.refreshDelay); if running and not aliasEditor.active then refreshData(true) end end end

loadAliases()
refreshSelectedMonitor()
refreshData(true)
setStatus("Diagnostic console online")
parallel.waitForAny(handleInputEvents, autoRefresh)

if config.killAllRelaysOnExit then allRelaysOff(latestData.redstoneRelays) end

term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
print("Programme termine.")
print("Fichiers :")
print("- blockreader_report.txt")
print("- blockreader_raw.txt")
print("- " .. config.aliasFile)
