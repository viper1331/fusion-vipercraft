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

return M
