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

  if data.inventory ~= nil or data.items ~= nil or data.slotCount ~= nil or data.slots ~= nil then
    return "inventory"
  end

  if data.active_state ~= nil or data.redstone ~= nil or data.current_redstone ~= nil then
    return "active"
  end

  return "unknown"
end

function M.resolveKnownReaders(hw, knownReaders)
  local byName = {}
  for _, entry in ipairs(hw.blockReaders) do
    byName[entry.name] = entry
  end

  if byName[knownReaders.deuterium] then
    hw.readerRoles.deuterium = byName[knownReaders.deuterium]
    hw.readerRoles.deuterium.role = "deuterium"
  end

  if byName[knownReaders.tritium] then
    hw.readerRoles.tritium = byName[knownReaders.tritium]
    hw.readerRoles.tritium.role = "tritium"
  end

  if byName[knownReaders.inventory] then
    hw.readerRoles.inventory = byName[knownReaders.inventory]
    hw.readerRoles.inventory.role = "inventory"
  end
end

function M.scanBlockReaders(hw, knownReaders)
  hw.readerRoles = {
    deuterium = nil,
    tritium = nil,
    inventory = nil,
    energy = nil,
    active = {},
    unknown = {},
  }

  M.resolveKnownReaders(hw, knownReaders)

  for _, entry in ipairs(hw.blockReaders) do
    entry.role = "unknown"
    entry.data = nil

    if entry.obj and type(entry.obj.getBlockData) == "function" then
      local ok, data = pcall(entry.obj.getBlockData)
      if ok then
        entry.data = data
        entry.role = M.classifyBlockReaderData(data)
      end
    end

    if entry == hw.readerRoles.deuterium or entry == hw.readerRoles.tritium or entry == hw.readerRoles.inventory then
    elseif entry.role == "deuterium" and not hw.readerRoles.deuterium then
      hw.readerRoles.deuterium = entry
    elseif entry.role == "tritium" and not hw.readerRoles.tritium then
      hw.readerRoles.tritium = entry
    elseif entry.role == "inventory" and not hw.readerRoles.inventory then
      hw.readerRoles.inventory = entry
    elseif entry.role == "energy" and not hw.readerRoles.energy then
      hw.readerRoles.energy = entry
    elseif entry.role == "active" then
      table.insert(hw.readerRoles.active, entry)
    else
      table.insert(hw.readerRoles.unknown, entry)
    end
  end
end

function M.extractChemicalData(raw, toNumber)
  if type(raw) ~= "table" then return "N/A", 0 end
  local tanks = raw.chemical_tanks
  if type(tanks) ~= "table" or type(tanks[1]) ~= "table" then return "N/A", 0 end
  local stored = tanks[1].stored
  if type(stored) ~= "table" then return "VIDE", 0 end
  return tostring(stored.id or "UNKNOWN"), toNumber(stored.amount, 0)
end

function M.readChemicalFromReader(entry, toNumber)
  if not entry or not entry.data then return "N/A", 0 end
  return M.extractChemicalData(entry.data, toNumber)
end

function M.readActiveFromReader(entry, toNumber)
  if not entry or not entry.data then return false, 0 end
  local a = entry.data.active_state
  local active = (a == true) or (tonumber(a) == 1)
  return active, toNumber(entry.data.current_redstone or entry.data.redstone, 0)
end

return M
