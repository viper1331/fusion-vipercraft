local M = {}

function M.contains(str, sub)
  return tostring(str or ""):find(sub, 1, true) ~= nil
end

function M.classifyBlockReaderData(data)
  if type(data) ~= "table" then return "unknown" end

  if type(data.chemical_tanks) == "table" and type(data.chemical_tanks[1]) == "table" then
    local stored = data.chemical_tanks[1].stored
    if type(stored) == "table" then
      local chemId = tostring(stored.id or "")
      if M.contains(chemId, "deuterium") then
        return "deuterium"
      elseif M.contains(chemId, "tritium") then
        return "tritium"
      end
    end
    return "chemical"
  end

  if type(data.energy_containers) == "table" then
    return "energy"
  end

  if data.inventory ~= nil or data.items ~= nil or data.slotCount ~= nil then
    return "inventory"
  end

  return "unknown"
end

function M.extractChemicalData(raw)
  local tank = raw and raw.chemical_tanks and raw.chemical_tanks[1]
  local stored = tank and tank.stored
  if type(stored) == "table" then
    return tostring(stored.name or stored.id or "N/A"), tonumber(stored.amount) or 0
  end
  return "N/A", 0
end

return M
