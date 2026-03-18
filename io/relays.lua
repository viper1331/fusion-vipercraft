local M = {}

local function logDebug(logger, message, meta)
  if type(logger) == "table" and type(logger.debug) == "function" then
    logger.debug(message, meta)
  end
end

local function logInfo(logger, message, meta)
  if type(logger) == "table" and type(logger.info) == "function" then
    logger.info(message, meta)
  end
end

local function logWarn(logger, message, meta)
  if type(logger) == "table" and type(logger.warn) == "function" then
    logger.warn(message, meta)
  end
end

local VALID_SIDES = {
  top = true,
  bottom = true,
  left = true,
  right = true,
  front = true,
  back = true,
}

local RELAY_DEFAULTS = {
  laser_charge = { side = "top", analog = 0, pulse = false, forceZero = true, label = "LAS" },
  deuterium = { side = "front", analog = 15, pulse = false, label = "Tank Deuterium" },
  tritium = { side = "front", analog = 15, pulse = false, label = "Tank Tritium" },
  laser_fire = { side = "top", analog = 15, pulse = true, pulseTime = 0.15 },
}

local function normalizeSide(side, fallback)
  local s = tostring(side or "")
  if VALID_SIDES[s] then return s end
  return fallback or "top"
end

local function cleanRelayName(name)
  if type(name) ~= "string" then return nil end
  local trimmed = name:gsub("^%s+", ""):gsub("%s+$", "")
  if trimmed == "" then return nil end
  return trimmed
end

local function collectRelayNames(relays)
  local names = {}
  if type(relays) ~= "table" then return names end
  for name in pairs(relays) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

local function ensureActionDefaults(CFG)
  CFG.knownRelays = type(CFG.knownRelays) == "table" and CFG.knownRelays or {}
  CFG.actions = type(CFG.actions) == "table" and CFG.actions or {}

  for actionName, defaults in pairs(RELAY_DEFAULTS) do
    local known = type(CFG.knownRelays[actionName]) == "table" and CFG.knownRelays[actionName] or {}
    known.relay = cleanRelayName(known.relay)
    known.side = normalizeSide(known.side, defaults.side)
    known.label = tostring(known.label or defaults.label or actionName)
    CFG.knownRelays[actionName] = known

    local action = type(CFG.actions[actionName]) == "table" and CFG.actions[actionName] or {}
    action.relay = cleanRelayName(action.relay) or known.relay
    action.side = normalizeSide(action.side, known.side)
    if action.analog == nil then action.analog = defaults.analog end
    if action.pulse == nil then action.pulse = defaults.pulse end
    if action.pulseTime == nil and defaults.pulseTime ~= nil then action.pulseTime = defaults.pulseTime end
    if defaults.forceZero then action.forceZero = true end
    CFG.actions[actionName] = action
  end
end

function M.resolveKnownRelays(CFG, relays)
  if type(CFG) ~= "table" then return end
  ensureActionDefaults(CFG)

  local available = collectRelayNames(relays)
  if #available == 0 then
    return
  end

  local used = {}
  local function reserve(name)
    if type(name) == "string" and name ~= "" then
      used[name] = true
    end
  end

  local function isAvailable(name)
    return type(name) == "string" and type(relays) == "table" and relays[name] ~= nil
  end

  local function pickRelay(allowUsed)
    for _, name in ipairs(available) do
      if allowUsed or not used[name] then
        return name
      end
    end
    return nil
  end

  local function bindAction(actionName, allowUsed)
    local action = CFG.actions[actionName]
    local known = CFG.knownRelays[actionName]
    if type(action) ~= "table" or type(known) ~= "table" then
      return
    end

    local relayName = nil
    if isAvailable(action.relay) then
      relayName = action.relay
    elseif isAvailable(known.relay) then
      relayName = known.relay
    else
      relayName = pickRelay(allowUsed)
    end

    action.relay = relayName
    action.side = normalizeSide(action.side, known.side)
    known.relay = relayName
    known.side = action.side

    reserve(relayName)
  end

  bindAction("laser_charge", true)
  bindAction("deuterium", false)
  if not cleanRelayName(CFG.actions.deuterium and CFG.actions.deuterium.relay) then
    bindAction("deuterium", true)
  end
  bindAction("tritium", false)
  if not cleanRelayName(CFG.actions.tritium and CFG.actions.tritium.relay) then
    bindAction("tritium", true)
  end

  -- Le tir LAS doit reutiliser strictement la meme ligne que la ligne de charge.
  CFG.actions.laser_fire.relay = CFG.actions.laser_charge.relay
  CFG.actions.laser_fire.side = CFG.actions.laser_charge.side
end

local function resolveRelayConfig(actions, relays, actionName)
  if type(actions) ~= "table" then return nil, nil, nil end
  local cfg = actions[actionName]
  if type(cfg) ~= "table" then return nil, nil, nil end
  local relayName = cleanRelayName(cfg.relay)
  local side = normalizeSide(cfg.side, "top")
  if not relayName then return cfg, nil, side end
  if type(relays) ~= "table" then return cfg, nil, side end
  local relay = relays[relayName]
  return cfg, relay, side
end

local function setAnalogSafe(relay, side, value)
  if type(relay.setAnalogOutput) == "function" then
    local ok = pcall(relay.setAnalogOutput, side, value)
    if ok then return true end
  end
  if type(relay.setAnalogueOutput) == "function" then
    local ok = pcall(relay.setAnalogueOutput, side, value)
    if ok then return true end
  end
  return false
end

local function setDigitalSafe(relay, side, value)
  if type(relay.setOutput) ~= "function" then return false end
  return pcall(relay.setOutput, side, value and true or false)
end

local function getAnalogSafe(relay, side, toNumber)
  if type(relay.getAnalogOutput) == "function" then
    local ok, v = pcall(relay.getAnalogOutput, side)
    if ok then return true, toNumber(v, 0) end
  end
  if type(relay.getAnalogueOutput) == "function" then
    local ok, v = pcall(relay.getAnalogueOutput, side)
    if ok then return true, toNumber(v, 0) end
  end
  return false, 0
end

function M.ensureRelayLow(actions, relays, actionName, logger)
  local _, relay, side = resolveRelayConfig(actions, relays, actionName)
  if not relay then
    logDebug(logger, "ensureRelayLow skipped: relay missing", { action = actionName })
    return false
  end
  if setAnalogSafe(relay, side, 0) then
    return true
  end
  local ok = setDigitalSafe(relay, side, false)
  if not ok then
    logWarn(logger, "ensureRelayLow failed", { action = actionName, side = side })
  end
  return ok
end

function M.relayWrite(actions, relays, actionName, on, logger)
  local cfg, relay, side = resolveRelayConfig(actions, relays, actionName)
  if not cfg or not relay then
    logWarn(logger, "relayWrite failed: relay missing", { action = actionName, on = tostring(on) })
    return false
  end

  if cfg.pulse then
    if on then
      local high = cfg.analog or 15
      if setAnalogSafe(relay, side, high) then
        sleep(cfg.pulseTime or 0.2)
        setAnalogSafe(relay, side, 0)
        logInfo(logger, "relay pulse sent", { action = actionName, side = side, analog = tostring(high) })
        return true
      end
      if setDigitalSafe(relay, side, true) then
        sleep(cfg.pulseTime or 0.2)
        setDigitalSafe(relay, side, false)
        logInfo(logger, "relay digital pulse sent", { action = actionName, side = side })
        return true
      end
    end
    logWarn(logger, "relay pulse failed", { action = actionName, side = side })
    return false
  end

  -- `forceZero` garantit que la ligne reste coupee (0) meme si `on = true`.
  local wantsOn = (on == true) and (cfg.forceZero ~= true)
  if setAnalogSafe(relay, side, wantsOn and (cfg.analog or 15) or 0) then
    logDebug(logger, "relay analog write", { action = actionName, side = side, value = wantsOn and (cfg.analog or 15) or 0 })
    return true
  end
  local ok = setDigitalSafe(relay, side, wantsOn)
  if ok then
    logDebug(logger, "relay digital write", { action = actionName, side = side, on = wantsOn and "true" or "false" })
  else
    logWarn(logger, "relay write failed", { action = actionName, side = side, on = tostring(on) })
  end
  return ok
end

function M.readRelayOutputState(actions, relays, actionName, fallback, toNumber, logger)
  local _, relay, side = resolveRelayConfig(actions, relays, actionName)
  if not relay then
    logDebug(logger, "readRelayOutputState fallback: relay missing", { action = actionName })
    return fallback
  end

  local okAnalog, analog = getAnalogSafe(relay, side, toNumber)
  if okAnalog then return analog > 0 end

  if type(relay.getOutput) == "function" then
    local ok, v = pcall(relay.getOutput, side)
    if ok then return v == true end
  end

  logDebug(logger, "readRelayOutputState fallback", { action = actionName, side = side })
  return fallback
end

return M
