-- install.lua
-- Assistant d'installation Fusion ViperCraft

local CONFIG_FILE = "fusion_config.lua"
local VERSION_FILE = "fusion.version"
local DEFAULT_VERSION = "1.1.0"

local SIDES = { "top", "bottom", "left", "right", "front", "back" }

local function contains(str, sub)
  return type(str) == "string" and type(sub) == "string"
    and string.find(string.lower(str), string.lower(sub), 1, true) ~= nil
end

local function gatherPeripherals()
  local names = peripheral.getNames()
  table.sort(names)

  local devices = {
    all = names,
    byType = {},
    monitors = {},
    readers = {},
    relays = {},
  }

  for _, name in ipairs(names) do
    local ptype = peripheral.getType(name) or "unknown"
    devices.byType[ptype] = devices.byType[ptype] or {}
    table.insert(devices.byType[ptype], name)

    if ptype == "monitor" then table.insert(devices.monitors, name) end
    if ptype == "block_reader" or contains(name, "block_reader") then table.insert(devices.readers, name) end
    if ptype == "redstone_relay" or contains(name, "relay") then table.insert(devices.relays, name) end
  end

  return devices
end

local function suggestByName(names, keywords)
  for _, name in ipairs(names) do
    for _, key in ipairs(keywords) do
      if contains(name, key) then
        return name
      end
    end
  end
  return nil
end

local function listCandidates(devices)
  local generic = devices.all
  return {
    monitor = suggestByName(devices.monitors, { "monitor" }),
    reactorController = suggestByName(generic, { "fusion_reactor_controller", "reactor_controller", "fusionreactor" }),
    logicAdapter = suggestByName(generic, { "logic_adapter", "fusionreactorlogicadapter", "logic" }),
    laser = suggestByName(generic, { "laser", "amplifier" }),
    induction = suggestByName(generic, { "induction", "matrix", "port" }),
    relayLaser = suggestByName(devices.relays, { "relay_0", "laser", "las" }),
    relayTritium = suggestByName(devices.relays, { "relay_2", "tritium", "tank_t" }),
    relayDeuterium = suggestByName(devices.relays, { "relay_1", "deuterium", "tank_d" }),
    readerTritium = suggestByName(devices.readers, { "reader_2", "tritium" }),
    readerDeuterium = suggestByName(devices.readers, { "reader_1", "deuterium" }),
    readerAux = suggestByName(devices.readers, { "reader_6", "aux", "inventory" }),
  }
end

local function runMonitorTest(name)
  if not name then return false, "Monitor non configuré" end
  local mon = peripheral.wrap(name)
  if not mon then return false, "Monitor introuvable" end

  local ok = pcall(function()
    mon.setBackgroundColor(colors.blue)
    mon.setTextColor(colors.white)
    mon.clear()
    mon.setCursorPos(2, 2)
    mon.write("Fusion installer: monitor test")
    mon.setCursorPos(2, 4)
    mon.write("Touch this monitor now")
  end)

  if not ok then return false, "Échec écriture monitor" end
  local timer = os.startTimer(5)
  while true do
    local ev, p1 = os.pullEvent()
    if ev == "monitor_touch" and p1 == name then
      return true, "Touch monitor détecté"
    end
    if ev == "timer" and p1 == timer then
      return true, "Monitor visible (pas de touch détecté)"
    end
  end
end

local function runRelayTest(relayName, side)
  if not relayName then return false, "Relay non configuré" end
  local relay = peripheral.wrap(relayName)
  if not relay or type(relay.setOutput) ~= "function" then
    return false, "Relay introuvable"
  end

  local ok, err = pcall(function()
    relay.setOutput(side, true)
    sleep(0.2)
    relay.setOutput(side, false)
  end)

  if not ok then return false, "Test relais échoué: " .. tostring(err) end
  return true, "Pulse envoyé sur " .. relayName .. "." .. side
end

local function runReaderTest(readerName)
  if not readerName then return false, "Reader non configuré" end
  local reader = peripheral.wrap(readerName)
  if not reader then return false, "Reader introuvable" end

  local methods = peripheral.getMethods(readerName) or {}
  if #methods == 0 then return false, "Aucune méthode reader" end
  return true, "Reader disponible (" .. tostring(#methods) .. " méthodes)"
end

local function runDevicePresenceTest(name)
  if not name then return false, "Non configuré" end
  if peripheral.isPresent(name) then return true, "Présent" end
  return false, "Manquant"
end

local function serializeValue(value, indent)
  indent = indent or 0
  local sp = string.rep("  ", indent)
  local sp2 = string.rep("  ", indent + 1)

  if type(value) == "table" then
    local keys = {}
    for k in pairs(value) do table.insert(keys, k) end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)

    local parts = { "{" }
    for _, key in ipairs(keys) do
      local encodedKey
      if type(key) == "string" and key:match("^[%a_][%w_]*$") then
        encodedKey = key
      else
        encodedKey = "[" .. string.format("%q", tostring(key)) .. "]"
      end
      local encodedValue = serializeValue(value[key], indent + 1)
      table.insert(parts, string.format("\n%s%s = %s,", sp2, encodedKey, encodedValue))
    end
    if #keys > 0 then table.insert(parts, "\n" .. sp) end
    table.insert(parts, "}")
    return table.concat(parts)
  end

  if type(value) == "string" then return string.format("%q", value) end
  return tostring(value)
end

local function writeConfig(config)
  local h = fs.open(CONFIG_FILE, "w")
  if not h then return false, "Impossible d'écrire " .. CONFIG_FILE end
  h.write("return ")
  h.write(serializeValue(config, 0))
  h.write("\n")
  h.close()
  return true
end

local function ensureVersionFile()
  if fs.exists(VERSION_FILE) then return end
  local h = fs.open(VERSION_FILE, "w")
  if h then
    h.write(DEFAULT_VERSION .. "\n")
    h.close()
  end
end

local state = {
  step = 1,
  running = true,
  devices = gatherPeripherals(),
  suggested = nil,
  status = "Bienvenue dans l'assistant d'installation Fusion.",
  setupName = "Fusion ViperCraft",
  monitorScale = 0.5,
  preferredView = "SUP",
  touchEnabled = true,
  uiOnMonitor = false,
  monitorScroll = 0,
  roleScroll = 0,
  relayScroll = { laser = 0, tritium = 0, deuterium = 0 },
  readerScroll = 0,
  activeRole = "reactorController",
  activeRelay = "laser",
  activeReaderRole = "tritium",
  tests = {},
  selected = {
    monitor = nil,
    reactorController = nil,
    logicAdapter = nil,
    laser = nil,
    induction = nil,
    relayLaser = nil,
    relayLaserSide = "top",
    relayTritium = nil,
    relayTritiumSide = "front",
    relayDeuterium = nil,
    relayDeuteriumSide = "front",
    readerTritium = nil,
    readerDeuterium = nil,
    readerAux = nil,
  },
}
state.suggested = listCandidates(state.devices)
for k, v in pairs(state.suggested) do
  if state.selected[k] == nil and v ~= nil then
    state.selected[k] = v
  end
end

local hitboxes = { term = {}, monitor = {} }
local nativeTerm = term.current()
local currentSource = "term"
local currentSurface = nativeTerm

local function clearHitboxes(source)
  hitboxes[source] = {}
end

local function addHitbox(source, id, x1, y1, x2, y2, action)
  table.insert(hitboxes[source], {
    id = id,
    x1 = math.min(x1, x2),
    y1 = math.min(y1, y2),
    x2 = math.max(x1, x2),
    y2 = math.max(y1, y2),
    action = action,
  })
end

local function handleClick(x, y, source)
  local list = hitboxes[source] or {}
  for i = #list, 1, -1 do
    local hb = list[i]
    if x >= hb.x1 and x <= hb.x2 and y >= hb.y1 and y <= hb.y2 then
      if hb.action then hb.action(hb.id) end
      return true
    end
  end
  return false
end

local function withSurface(fn)
  local previous = term.current()
  term.redirect(currentSurface)
  fn()
  term.redirect(previous)
end

local function drawText(x, y, text, fg, bg)
  currentSurface.setCursorPos(x, y)
  if bg then currentSurface.setBackgroundColor(bg) end
  if fg then currentSurface.setTextColor(fg) end
  currentSurface.write(text)
end

local function fitText(text, maxWidth)
  local value = tostring(text or "")
  if maxWidth <= 0 then return "" end
  if #value <= maxWidth then return value end
  if maxWidth <= 3 then return value:sub(1, maxWidth) end
  return value:sub(1, maxWidth - 3) .. "..."
end

local function fillRect(x1, y1, x2, y2, bg)
  currentSurface.setBackgroundColor(bg)
  for y = y1, y2 do
    currentSurface.setCursorPos(x1, y)
    currentSurface.write(string.rep(" ", math.max(0, x2 - x1 + 1)))
  end
end

local function buttonColors(kind, pressed)
  if kind == "primary" then
    return pressed and colors.blue or colors.cyan, colors.white, colors.lightBlue
  elseif kind == "danger" then
    return pressed and colors.red or colors.orange, colors.white, colors.red
  end
  return pressed and colors.gray or colors.lightGray, colors.black, colors.gray
end

local function computeLayout(w, h)
  local compact = w < 56 or h < 22
  local large = w >= 90 and h >= 30
  local marginX = compact and 2 or 3
  local contentTop = 5
  local footerHeight = compact and 4 or 3
  local navY = h - footerHeight - 3

  return {
    compact = compact,
    large = large,
    marginX = marginX,
    contentTop = contentTop,
    contentBottom = navY - 1,
    navY = navY,
    footerHeight = footerHeight,
    listTop = contentTop + 2,
  }
end

local function isCompactLayout(layout)
  return layout.compact
end

local function isLargeLayout(layout)
  return layout.large
end

local function drawButtonRow(source, y, defs, left, right, gap)
  local count = #defs
  if count == 0 then return end
  local totalGap = gap * (count - 1)
  local available = right - left + 1 - totalGap
  if available < count * 6 then return end
  local base = math.floor(available / count)
  local extra = available - (base * count)
  local x = left

  for i, def in ipairs(defs) do
    local width = base + (i <= extra and 1 or 0)
    local label = fitText(def.label, math.max(1, width - 2))
    drawButton(source, def.id, x, y, width, label, def.kind, def.action)
    x = x + width + gap
  end
end

local function drawButton(source, id, x, y, w, label, kind, action)
  if w < 4 then return end
  local clipped = fitText(label, w - 2)
  local bg, fg, shade = buttonColors(kind, false)
  fillRect(x, y, x + w - 1, y + 2, shade)
  fillRect(x, y, x + w - 1, y + 1, bg)
  local tx = x + math.floor((w - #clipped) / 2)
  drawText(tx, y + 1, clipped, fg, bg)
  addHitbox(source, id, x, y, x + w - 1, y + 2, function()
    local pbg, pfg = buttonColors(kind, true)
    fillRect(x, y, x + w - 1, y + 2, pbg)
    drawText(tx, y + 1, clipped, pfg, pbg)
    sleep(0.05)
    action()
  end)
end

local function sanitizeScale(v)
  local n = tonumber(v) or 0.5
  if n < 0.5 then n = 0.5 end
  if n > 5 then n = 5 end
  return n
end

local stepTitles = {
  "Accueil",
  "Scan devices",
  "Sélection monitor",
  "Devices principaux",
  "Relays & faces",
  "Readers",
  "Tests matériels",
  "Récapitulatif",
}

local function drawSteps(w, layout)
  local txt = string.format("STEP %d/%d - %s", state.step, #stepTitles, stepTitles[state.step])
  fillRect(1, 1, w, 3, colors.gray)
  local title = isLargeLayout(layout) and "Fusion ViperCraft Installer" or "Fusion Installer"
  drawText(2, 1, fitText(title, w - 2), colors.white, colors.gray)
  drawText(2, 2, fitText(txt, w - 2), colors.yellow, colors.gray)
  local hint = isCompactLayout(layout)
    and "Touch: souris/monitor"
    or "Navigation tactile: clic souris + monitor_touch"
  drawText(2, 3, fitText(hint, w - 2), colors.white, colors.gray)
end

local function drawFooter(w, h, layout)
  local top = h - layout.footerHeight + 1
  fillRect(1, top, w, h, colors.black)

  local status = fitText(state.status or "", w - 2)
  drawText(2, top + 1, status, colors.lightGray, colors.black)

  if layout.compact then
    drawText(2, top + 2, fitText("Back/Next: naviguer", w - 2), colors.gray, colors.black)
    drawText(2, top + 3, fitText("Click ligne: sélectionner", w - 2), colors.gray, colors.black)
  else
    local help = "Back/Next pour naviguer • Cliquer une ligne pour sélectionner"
    drawText(2, top + 2, fitText(help, w - 2), colors.gray, colors.black)
  end
end

local function scanNow()
  state.devices = gatherPeripherals()
  state.suggested = listCandidates(state.devices)
  for k, v in pairs(state.suggested) do
    if state.selected[k] == nil and v ~= nil then
      state.selected[k] = v
    end
  end
  state.status = string.format("SCAN COMPLETE - %d DEVICES FOUND", #state.devices.all)
end

local function createListRows(items, selected, startY, rows, scroll, source, onSelect, x1, x2)
  local w, _ = currentSurface.getSize()
  x1 = x1 or 3
  x2 = x2 or (w - 3)
  fillRect(x1, startY, x2, startY + rows - 1, colors.black)
  for i = 1, rows do
    local idx = scroll + i
    local y = startY + i - 1
    local name = items[idx]
    if name then
      local isSel = selected == name
      local bg = isSel and colors.blue or colors.black
      local fg = isSel and colors.white or colors.lightGray
      fillRect(x1, y, x2, y, bg)
      local ptype = peripheral.getType(name) or "unknown"
      local text = string.format("[%02d] %s (%s)", idx, name, ptype)
      drawText(x1 + 1, y, fitText(text, x2 - x1 - 1), fg, bg)
      addHitbox(source, "row_" .. tostring(idx), x1, y, x2, y, function() onSelect(name) end)
    end
  end
end

local function drawNavigation(source, w, _, layout)
  local y = layout.navY
  local left = layout.marginX
  local right = w - layout.marginX
  if state.step > 1 then
    drawButton(source, "back", left, y, 12, "BACK", "secondary", function()
      state.step = math.max(1, state.step - 1)
    end)
  end
  if state.step < #stepTitles then
    drawButton(source, "next", right - 11, y, 12, "NEXT", "primary", function()
      state.step = math.min(#stepTitles, state.step + 1)
    end)
  end
end

local function drawWelcome(source, w, h, layout)
  local left = layout.marginX
  local right = w - layout.marginX
  local panelTop = layout.contentTop
  local panelBottom = layout.contentBottom

  fillRect(left, panelTop, right, panelBottom, colors.black)
  fillRect(left, panelTop, right, panelTop, colors.gray)
  fillRect(left, panelTop + 2, right, panelTop + 2, colors.gray)

  local y = panelTop + 1
  drawText(left + 1, y, fitText("FUSION VIPERCRAFT INSTALLER", right - left - 1), colors.white, colors.gray)
  y = y + 2
  drawText(left + 1, y, fitText("Version " .. DEFAULT_VERSION, right - left - 1), colors.lightGray, colors.black)
  y = y + 2
  drawText(left + 1, y, fitText("Objectif", right - left - 1), colors.white, colors.black)
  y = y + 1
  drawText(left + 2, y, fitText("Configurer rapidement le setup Fusion + périphériques.", right - left - 3), colors.lightGray, colors.black)
  y = y + 2

  local monitorInfo = state.selected.monitor and ("Monitor: " .. state.selected.monitor) or "Monitor: non sélectionné"
  drawText(left + 1, y, fitText("État scan", right - left - 1), colors.white, colors.black)
  y = y + 1
  drawText(left + 2, y, fitText("Devices détectés: " .. tostring(#state.devices.all), right - left - 3), colors.lightGray, colors.black)
  y = y + 1
  drawText(left + 2, y, fitText(monitorInfo, right - left - 3), colors.lightGray, colors.black)

  local actionsY = math.max(y + 2, panelBottom - 3)
  drawButtonRow(source, actionsY, {
    { id = "start", label = "START INSTALL", kind = "primary", action = function() state.step = 2 end },
    { id = "rescan", label = "RESCAN", kind = "secondary", action = function() scanNow() end },
    { id = "exit", label = "EXIT", kind = "danger", action = function() state.running = false end },
  }, left + 1, right - 1, layout.compact and 1 or 2)
end

local function drawScan(source, w, h, layout)
  local left = layout.marginX
  local right = w - layout.marginX
  local y = layout.contentTop
  drawText(left, y, fitText(string.format("Total devices: %d", #state.devices.all), w - left * 2), colors.white, colors.black)
  y = y + 2

  local entries = {
    { "Monitors", #state.devices.monitors },
    { "Relays", #state.devices.relays },
    { "Readers", #state.devices.readers },
    { "Reactor devices", #(state.devices.byType["fusion_reactor_controller"] or {}) + #(state.devices.byType["fusionReactorLogicAdapter"] or {}) },
    { "Induction/Laser", #(state.devices.byType["laser_amplifier"] or {}) + #(state.devices.byType["induction_port"] or {}) },
    { "Modems", #(state.devices.byType["modem"] or {}) },
  }

  for _, e in ipairs(entries) do
    local line = string.format("- %-16s : %d", e[1], e[2])
    drawText(left + 1, y, fitText(line, right - left - 1), colors.lightGray, colors.black)
    y = y + 1
    if y >= layout.navY - 4 then break end
  end

  drawButton(source, "scan", left, layout.navY - 4, math.min(16, right - left + 1), "SCAN", "primary", function() scanNow() end)
end

local function drawMonitorStep(source, w, h, layout)
  local left = layout.marginX
  local right = w - layout.marginX
  local listTop = layout.contentTop + 2
  local scrollX = right - 8

  drawText(left, layout.contentTop, fitText("Choisissez le monitor principal:", right - left + 1), colors.white, colors.black)
  local rows = math.max(3, layout.navY - listTop - 2)
  local maxScroll = math.max(0, #state.devices.monitors - rows)
  if state.monitorScroll > maxScroll then state.monitorScroll = maxScroll end

  createListRows(state.devices.monitors, state.selected.monitor, listTop, rows, state.monitorScroll, source, function(name)
    state.selected.monitor = name
    state.status = "Monitor sélectionné: " .. name
  end, left, scrollX - 1)

  drawButton(source, "mup", scrollX, listTop, 8, "UP", "secondary", function()
    state.monitorScroll = math.max(0, state.monitorScroll - 1)
  end)
  drawButton(source, "mdown", scrollX, listTop + 4, 8, "DOWN", "secondary", function()
    state.monitorScroll = math.min(maxScroll, state.monitorScroll + 1)
  end)

  drawButtonRow(source, layout.navY - 4, {
    { id = "test_monitor", label = "TEST MONITOR", kind = "primary", action = function()
      local ok, msg = runMonitorTest(state.selected.monitor)
      state.tests.monitor = { ok = ok, msg = msg }
      state.status = (ok and "OK: " or "FAIL: ") .. msg
    end },
    { id = "toggle_surface", label = state.uiOnMonitor and "USE TERMINAL UI" or "DISPLAY ON MONITOR", kind = "secondary", action = function()
      if state.uiOnMonitor then
        state.uiOnMonitor = false
        state.status = "Affichage revenu sur terminal."
        return
      end
      if not state.selected.monitor then
        state.status = "Sélectionnez un monitor avant d'afficher l'UI dessus."
        return
      end
      local mon = peripheral.wrap(state.selected.monitor)
      if not mon then
        state.status = "Monitor introuvable."
        return
      end
      pcall(function() mon.setTextScale(sanitizeScale(state.monitorScale)) end)
      state.uiOnMonitor = true
      state.status = "UI affichée sur monitor. Utilisez monitor_touch."
    end },
  }, left, right, layout.compact and 1 or 2)
end

local function currentRoleValue()
  if state.activeRole == "reactorController" then return state.selected.reactorController end
  if state.activeRole == "logicAdapter" then return state.selected.logicAdapter end
  if state.activeRole == "laser" then return state.selected.laser end
  return state.selected.induction
end

local function setCurrentRole(name)
  if state.activeRole == "reactorController" then state.selected.reactorController = name
  elseif state.activeRole == "logicAdapter" then state.selected.logicAdapter = name
  elseif state.activeRole == "laser" then state.selected.laser = name
  else state.selected.induction = name end
end

local function drawCoreDevices(source, w, h, layout)
  local left = layout.marginX
  local right = w - layout.marginX
  local scrollX = right - 8
  drawText(left, layout.contentTop, fitText("Choisissez un rôle puis cliquez un device.", right - left + 1), colors.white, colors.black)

  local roles = {
    { "reactorController", "Reactor Ctrl" },
    { "logicAdapter", "Logic Adapter" },
    { "laser", "Laser" },
    { "induction", "Induction" },
  }

  local defs = {}
  for _, r in ipairs(roles) do
    local active = state.activeRole == r[1]
    table.insert(defs, {
      id = "role_" .. r[1],
      label = active and ("> " .. r[2]) or r[2],
      kind = active and "primary" or "secondary",
      action = function() state.activeRole = r[1] end,
    })
  end
  drawButtonRow(source, layout.contentTop + 2, defs, left, right, 1)

  local listTop = layout.contentTop + 6
  local rows = math.max(3, layout.navY - listTop - 1)
  local maxScroll = math.max(0, #state.devices.all - rows)
  if state.roleScroll > maxScroll then state.roleScroll = maxScroll end

  createListRows(state.devices.all, currentRoleValue(), listTop, rows, state.roleScroll, source, function(name)
    setCurrentRole(name)
    state.status = "Assignation " .. state.activeRole .. " -> " .. name
  end, left, scrollX - 1)

  drawButton(source, "rup", scrollX, listTop, 8, "UP", "secondary", function() state.roleScroll = math.max(0, state.roleScroll - 1) end)
  drawButton(source, "rdown", scrollX, listTop + 4, 8, "DOWN", "secondary", function() state.roleScroll = math.min(maxScroll, state.roleScroll + 1) end)
end

local relayRoleMap = {
  laser = { key = "relayLaser", side = "relayLaserSide", label = "Relay LAS" },
  tritium = { key = "relayTritium", side = "relayTritiumSide", label = "Relay T" },
  deuterium = { key = "relayDeuterium", side = "relayDeuteriumSide", label = "Relay D" },
}

local function drawRelays(source, w, h, layout)
  local left = layout.marginX
  local right = w - layout.marginX
  local scrollX = right - 8

  local roleDefs = {}
  for _, role in ipairs({ "laser", "tritium", "deuterium" }) do
    local active = state.activeRelay == role
    table.insert(roleDefs, {
      id = "relay_role_" .. role,
      label = active and ("> " .. relayRoleMap[role].label) or relayRoleMap[role].label,
      kind = active and "primary" or "secondary",
      action = function() state.activeRelay = role end,
    })
  end
  drawButtonRow(source, layout.contentTop, roleDefs, left, right, 1)

  local meta = relayRoleMap[state.activeRelay]
  local selectedRelay = state.selected[meta.key]
  local listTop = layout.contentTop + 4
  local rows = math.max(3, layout.navY - listTop - 6)
  local maxScroll = math.max(0, #state.devices.relays - rows)
  local scroll = state.relayScroll[state.activeRelay]
  if scroll > maxScroll then scroll = maxScroll end
  state.relayScroll[state.activeRelay] = scroll

  drawText(left, listTop - 1, fitText("Sélection relay:", right - left + 1), colors.white, colors.black)
  createListRows(state.devices.relays, selectedRelay, listTop, rows, scroll, source, function(name)
    state.selected[meta.key] = name
    state.status = meta.label .. " -> " .. name
  end, left, scrollX - 1)

  drawButton(source, "lup", scrollX, listTop, 8, "UP", "secondary", function()
    state.relayScroll[state.activeRelay] = math.max(0, state.relayScroll[state.activeRelay] - 1)
  end)
  drawButton(source, "ldown", scrollX, listTop + 4, 8, "DOWN", "secondary", function()
    state.relayScroll[state.activeRelay] = math.min(maxScroll, state.relayScroll[state.activeRelay] + 1)
  end)

  local sideY = layout.navY - 8
  drawText(left, sideY - 1, fitText("Sélection face:", right - left + 1), colors.white, colors.black)
  local sideDefs = {}
  for _, side in ipairs(SIDES) do
    local selectedSide = state.selected[meta.side] == side
    table.insert(sideDefs, {
      id = "side_" .. side,
      label = side:upper(),
      kind = selectedSide and "primary" or "secondary",
      action = function() state.selected[meta.side] = side end,
    })
  end
  drawButtonRow(source, sideY, sideDefs, left, right, 1)

  drawButton(source, "test_relay", left, layout.navY - 4, math.min(18, right - left + 1), "TEST RELAY", "primary", function()
    local ok, msg = runRelayTest(state.selected[meta.key], state.selected[meta.side])
    state.tests[meta.key] = { ok = ok, msg = msg }
    state.status = (ok and "OK: " or "FAIL: ") .. msg
  end)
end

local readerRoleMap = {
  tritium = { key = "readerTritium", label = "Reader T" },
  deuterium = { key = "readerDeuterium", label = "Reader D" },
  aux = { key = "readerAux", label = "Reader Aux" },
}

local function drawReaders(source, w, h, layout)
  local left = layout.marginX
  local right = w - layout.marginX
  local scrollX = right - 8

  local roleDefs = {}
  for _, role in ipairs({ "tritium", "deuterium", "aux" }) do
    local active = state.activeReaderRole == role
    table.insert(roleDefs, {
      id = "reader_role_" .. role,
      label = active and ("> " .. readerRoleMap[role].label) or readerRoleMap[role].label,
      kind = active and "primary" or "secondary",
      action = function() state.activeReaderRole = role end,
    })
  end
  drawButtonRow(source, layout.contentTop, roleDefs, left, right, 1)

  local meta = readerRoleMap[state.activeReaderRole]
  local listTop = layout.contentTop + 4
  local rows = math.max(3, layout.navY - listTop - 1)
  local maxScroll = math.max(0, #state.devices.readers - rows)
  if state.readerScroll > maxScroll then state.readerScroll = maxScroll end

  createListRows(state.devices.readers, state.selected[meta.key], listTop, rows, state.readerScroll, source, function(name)
    state.selected[meta.key] = name
    state.status = meta.label .. " -> " .. name
  end, left, scrollX - 1)

  drawButton(source, "reader_up", scrollX, listTop, 8, "UP", "secondary", function() state.readerScroll = math.max(0, state.readerScroll - 1) end)
  drawButton(source, "reader_down", scrollX, listTop + 4, 8, "DOWN", "secondary", function() state.readerScroll = math.min(maxScroll, state.readerScroll + 1) end)
end

local function runNamedTest(id)
  local ok, msg = false, ""
  if id == "monitor" then
    ok, msg = runMonitorTest(state.selected.monitor)
  elseif id == "relayLaser" then
    ok, msg = runRelayTest(state.selected.relayLaser, state.selected.relayLaserSide)
  elseif id == "relayTritium" then
    ok, msg = runRelayTest(state.selected.relayTritium, state.selected.relayTritiumSide)
  elseif id == "relayDeuterium" then
    ok, msg = runRelayTest(state.selected.relayDeuterium, state.selected.relayDeuteriumSide)
  elseif id == "readerTritium" then
    ok, msg = runReaderTest(state.selected.readerTritium)
  elseif id == "readerDeuterium" then
    ok, msg = runReaderTest(state.selected.readerDeuterium)
  elseif id == "laser" then
    ok, msg = runDevicePresenceTest(state.selected.laser)
  elseif id == "induction" then
    ok, msg = runDevicePresenceTest(state.selected.induction)
  end
  state.tests[id] = { ok = ok, msg = msg }
  state.status = (ok and "OK: " or "FAIL: ") .. msg
end

local function drawTests(source, w, h, layout)
  local tests = {
    { "monitor", "TEST MONITOR" },
    { "relayLaser", "TEST RELAY LAS" },
    { "relayTritium", "TEST RELAY T" },
    { "relayDeuterium", "TEST RELAY D" },
    { "readerTritium", "TEST READER T" },
    { "readerDeuterium", "TEST READER D" },
    { "laser", "TEST LASER" },
    { "induction", "TEST INDUCTION" },
  }

  local left = layout.marginX
  local right = w - layout.marginX
  local statusX = math.min(right, left + (layout.compact and 16 or 22))
  local buttonW = math.max(14, statusX - left - 1)
  local y = layout.contentTop

  for _, t in ipairs(tests) do
    if y + 2 > layout.navY - 1 then break end
    drawButton(source, "test_" .. t[1], left, y, buttonW, t[2], "primary", function() runNamedTest(t[1]) end)
    local status = state.tests[t[1]] and (state.tests[t[1]].ok and "OK" or "FAIL") or "PENDING"
    local color = status == "OK" and colors.lime or (status == "FAIL" and colors.red or colors.gray)
    drawText(statusX + 1, y + 1, fitText(status, right - statusX), color, colors.black)
    y = y + 4
  end
end
local function buildConfig()
  return {
    configVersion = 1,
    setupName = state.setupName,
    monitor = {
      name = state.selected.monitor,
      scale = sanitizeScale(state.monitorScale),
    },
    devices = {
      reactorController = state.selected.reactorController,
      logicAdapter = state.selected.logicAdapter,
      laser = state.selected.laser,
      induction = state.selected.induction,
    },
    relays = {
      laser = { name = state.selected.relayLaser, side = state.selected.relayLaserSide },
      tritium = { name = state.selected.relayTritium, side = state.selected.relayTritiumSide },
      deuterium = { name = state.selected.relayDeuterium, side = state.selected.relayDeuteriumSide },
    },
    readers = {
      tritium = state.selected.readerTritium,
      deuterium = state.selected.readerDeuterium,
      aux = state.selected.readerAux,
    },
    ui = {
      preferredView = state.preferredView,
      touchEnabled = state.touchEnabled,
      refreshDelay = 0.20,
    },
    update = {
      enabled = true,
    },
  }
end

local function drawSummary(source, w, h, layout)
  local left = layout.marginX
  local right = w - layout.marginX
  local lines = {
    "Monitor: " .. tostring(state.selected.monitor),
    "Reactor controller: " .. tostring(state.selected.reactorController),
    "Logic adapter: " .. tostring(state.selected.logicAdapter),
    "Laser: " .. tostring(state.selected.laser),
    "Induction: " .. tostring(state.selected.induction),
    "Relay LAS: " .. tostring(state.selected.relayLaser) .. " / " .. tostring(state.selected.relayLaserSide),
    "Relay T: " .. tostring(state.selected.relayTritium) .. " / " .. tostring(state.selected.relayTritiumSide),
    "Relay D: " .. tostring(state.selected.relayDeuterium) .. " / " .. tostring(state.selected.relayDeuteriumSide),
    "Reader T: " .. tostring(state.selected.readerTritium),
    "Reader D: " .. tostring(state.selected.readerDeuterium),
    "Reader Aux: " .. tostring(state.selected.readerAux),
  }

  local y = layout.contentTop
  for _, line in ipairs(lines) do
    drawText(left, y, fitText(line, right - left + 1), colors.lightGray, colors.black)
    y = y + 1
    if y > layout.navY - 5 then break end
  end

  drawButtonRow(source, layout.navY - 4, {
    { id = "save", label = "SAVE CONFIG", kind = "primary", action = function()
      local ok, err = writeConfig(buildConfig())
      if not ok then
        state.status = "Erreur sauvegarde: " .. tostring(err)
        return
      end
      ensureVersionFile()
      state.status = "CONFIG SAVED - INSTALLATION COMPLETE - READY TO LAUNCH"
    end },
    { id = "launch", label = "LAUNCH FUSION", kind = "primary", action = function()
      local ok = writeConfig(buildConfig())
      if ok then ensureVersionFile() end
      state.running = false
      state.launch = true
    end },
  }, left, right, 2)
end

local function render()
  if state.uiOnMonitor and state.selected.monitor then
    local mon = peripheral.wrap(state.selected.monitor)
    if mon then
      currentSource = "monitor"
      currentSurface = mon
      pcall(function() mon.setTextScale(sanitizeScale(state.monitorScale)) end)
    else
      currentSource = "term"
      currentSurface = nativeTerm
      state.uiOnMonitor = false
    end
  else
    currentSource = "term"
    currentSurface = nativeTerm
  end

  withSurface(function()
    local w, h = currentSurface.getSize()
    clearHitboxes(currentSource)
    currentSurface.setBackgroundColor(colors.black)
    currentSurface.setTextColor(colors.white)
    currentSurface.clear()

    local layout = computeLayout(w, h)

    drawSteps(w, layout)
    if state.step == 1 then drawWelcome(currentSource, w, h, layout)
    elseif state.step == 2 then drawScan(currentSource, w, h, layout)
    elseif state.step == 3 then drawMonitorStep(currentSource, w, h, layout)
    elseif state.step == 4 then drawCoreDevices(currentSource, w, h, layout)
    elseif state.step == 5 then drawRelays(currentSource, w, h, layout)
    elseif state.step == 6 then drawReaders(currentSource, w, h, layout)
    elseif state.step == 7 then drawTests(currentSource, w, h, layout)
    elseif state.step == 8 then drawSummary(currentSource, w, h, layout)
    end

    drawNavigation(currentSource, w, h, layout)
    drawFooter(w, h, layout)
  end)
end

scanNow()
render()

while state.running do
  local ev, p1, p2, p3 = os.pullEvent()
  if ev == "mouse_click" and currentSource == "term" then
    handleClick(p2, p3, "term")
    render()
  elseif ev == "monitor_touch" and currentSource == "monitor" and p1 == state.selected.monitor then
    handleClick(p2, p3, "monitor")
    render()
  elseif ev == "key" and p1 == keys.q then
    state.running = false
  elseif ev == "peripheral" or ev == "peripheral_detach" then
    scanNow()
    render()
  end
end

if state.launch then
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)
  shell.run("fusion.lua")
else
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)
  print("Installateur fermé.")
end
