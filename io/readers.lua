local M = {}
local lastReaderSignature = nil

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
  knownReaders = type(knownReaders) == "table" and knownReaders or {}
  local byName = {}
  for _, entry in ipairs(hw.blockReaders) do
    byName[entry.name] = entry
  end

  if type(knownReaders.deuterium) == "string" and byName[knownReaders.deuterium] then
    hw.readerRoles.deuterium = byName[knownReaders.deuterium]
    hw.readerRoles.deuterium.role = "deuterium"
  end

  if type(knownReaders.tritium) == "string" and byName[knownReaders.tritium] then
    hw.readerRoles.tritium = byName[knownReaders.tritium]
    hw.readerRoles.tritium.role = "tritium"
  end

  if type(knownReaders.inventory) == "string" and byName[knownReaders.inventory] then
    hw.readerRoles.inventory = byName[knownReaders.inventory]
    hw.readerRoles.inventory.role = "inventory"
  end
end

function M.reconcileKnownReaders(hw, knownReaders)
  if type(knownReaders) ~= "table" then return end

  if hw.readerRoles.deuterium and type(hw.readerRoles.deuterium.name) == "string" then
    knownReaders.deuterium = hw.readerRoles.deuterium.name
  end

  if hw.readerRoles.tritium and type(hw.readerRoles.tritium.name) == "string" then
    knownReaders.tritium = hw.readerRoles.tritium.name
  end

  local aux = hw.readerRoles.inventory or hw.readerRoles.active[1]
  if aux and type(aux.name) == "string" then
    knownReaders.inventory = aux.name
  end
end

function M.scanBlockReaders(hw, knownReaders, logger)
  hw.readerRoles = {
    deuterium = nil,
    tritium = nil,
    inventory = nil,
    energy = nil,
    active = {},
    unknown = {},
  }

  M.resolveKnownReaders(hw, knownReaders)

  local roleCounts = {
    deuterium = 0,
    tritium = 0,
    inventory = 0,
    energy = 0,
    active = 0,
    unknown = 0,
  }

  for _, entry in ipairs(hw.blockReaders) do
    entry.role = "unknown"
    entry.data = nil

    if entry.obj and type(entry.obj.getBlockData) == "function" then
      local ok, data = pcall(entry.obj.getBlockData)
      if ok then
        entry.data = data
        entry.role = M.classifyBlockReaderData(data)
      else
        logDebug(logger, "Block reader probe failed", { name = tostring(entry.name) })
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

    roleCounts[entry.role] = (roleCounts[entry.role] or 0) + 1
  end

  -- Synchronise les noms connus sur les roles effectivement detectes
  -- pour absorber automatiquement les changements du terrain.
  M.reconcileKnownReaders(hw, knownReaders)
  local signature = table.concat({
    tostring(#(hw.blockReaders or {})),
    tostring(roleCounts.deuterium or 0),
    tostring(roleCounts.tritium or 0),
    tostring(roleCounts.inventory or 0),
    tostring(roleCounts.active or 0),
    tostring(roleCounts.unknown or 0),
    hw.readerRoles.deuterium and hw.readerRoles.deuterium.name or "none",
    hw.readerRoles.tritium and hw.readerRoles.tritium.name or "none",
    hw.readerRoles.inventory and hw.readerRoles.inventory.name or "none",
  }, "|")
  if signature ~= lastReaderSignature then
    lastReaderSignature = signature
    logInfo(logger, "Block reader roles updated", {
      total = tostring(#(hw.blockReaders or {})),
      deuterium = tostring(roleCounts.deuterium or 0),
      tritium = tostring(roleCounts.tritium or 0),
      inventory = tostring(roleCounts.inventory or 0),
      active = tostring(roleCounts.active or 0),
      unknown = tostring(roleCounts.unknown or 0),
    })
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
