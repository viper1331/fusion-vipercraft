local M = {}

function M.resolveKnownRelays(CFG)
  for action, cfg in pairs(CFG.knownRelays) do
    if CFG.actions[action] == nil then
      CFG.actions[action] = { relay = cfg.relay, side = cfg.side, analog = 15, pulse = false }
    else
      CFG.actions[action].relay = cfg.relay
      CFG.actions[action].side = cfg.side
      CFG.actions[action].analog = CFG.actions[action].analog or 15
      CFG.actions[action].pulse = false
    end
  end
end

function M.relayWrite(actions, relays, actionName, on)
  local cfg = actions[actionName]
  if not cfg then return false end

  local relay = relays[cfg.relay]
  if not relay then return false end

  if cfg.pulse then
    if on then
      if type(relay.setAnalogOutput) == "function" then
        relay.setAnalogOutput(cfg.side, cfg.analog or 15)
        sleep(cfg.pulseTime or 0.2)
        relay.setAnalogOutput(cfg.side, 0)
        return true
      elseif type(relay.setOutput) == "function" then
        relay.setOutput(cfg.side, true)
        sleep(cfg.pulseTime or 0.2)
        relay.setOutput(cfg.side, false)
        return true
      end
    end
  else
    if type(relay.setAnalogOutput) == "function" then
      relay.setAnalogOutput(cfg.side, on and (cfg.analog or 15) or 0)
      return true
    elseif type(relay.setOutput) == "function" then
      relay.setOutput(cfg.side, on and true or false)
      return true
    end
  end

  return false
end

function M.readRelayOutputState(actions, relays, actionName, fallback, toNumber)
  local cfg = actions[actionName]
  if not cfg then return fallback end
  local relay = relays[cfg.relay]
  if not relay then return fallback end

  if type(relay.getAnalogOutput) == "function" then
    local ok, v = pcall(relay.getAnalogOutput, cfg.side)
    if ok then return toNumber(v, 0) > 0 end
  end

  if type(relay.getOutput) == "function" then
    local ok, v = pcall(relay.getOutput, cfg.side)
    if ok then return v == true end
  end

  return fallback
end

return M
