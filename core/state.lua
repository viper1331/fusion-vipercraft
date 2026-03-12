local M = {}

function M.new(initial)
  local state = {}
  for k, v in pairs(initial or {}) do
    state[k] = v
  end
  return state
end

function M.defaultRuntimeState(localVersion, updateEnabled)
  return {
    running = true,
    uiDrawn = false,
    choosingMonitor = false,
    monitorList = {},
    monitorPage = 1,

    autoMaster = true,
    chargeAuto = true,
    fusionAuto = true,
    gasAuto = true,

    reactorPresent = false,
    reactorFormed = false,
    ignition = false,
    plasmaTemp = 0,
    ignitionTemp = 0,
    caseTemp = 0,

    laserPresent = false,
    laserEnergy = 0,
    laserMax = 1,
    laserPct = 0,
    laserChargeOn = false,

    energyPresent = false,
    energyKnown = false,
    energyStored = 0,
    energyMax = 1,
    energyPct = 0,

    inductionPresent = false,
    inductionFormed = false,
    inductionEnergy = 0,
    inductionMax = 1,
    inductionPct = 0,
    inductionNeeded = 0,
    inductionInput = 0,
    inductionOutput = 0,
    inductionTransferCap = 0,
    inductionCells = 0,
    inductionProviders = 0,
    inductionLength = 0,
    inductionHeight = 0,
    inductionWidth = 0,
    inductionPortMode = "UNKNOWN",

    deuteriumName = "N/A",
    deuteriumAmount = 0,
    tritiumName = "N/A",
    tritiumAmount = 0,

    auxPresent = false,
    auxActive = false,
    auxRedstone = 0,

    dtOpen = false,
    dOpen = false,
    tOpen = false,

    laserLineOn = false,
    knownLabels = {
      laser = "Charge Laser",
      deuterium = "Tank Deuterium",
      tritium = "Tank Tritium",
      readerD = "Reader Deuterium",
      readerT = "Reader Tritium",
      readerAux = "Reader Aux",
    },

    ignitionSequencePending = false,
    lastIgnitionAttempt = 0,

    status = "Init",
    lastAction = "Aucune",
    alert = "INFO",

    currentView = "supervision",
    setup = {
      loaded = nil,
      working = nil,
      deviceStatus = {},
      dirty = false,
      lastMessage = "Ready",
      lastTestResult = "N/A",
      saveStatus = "N/A",
      rebindRole = nil,
      rebindCandidates = {},
      rebindCursor = 1,
    },
    safetyWarnings = {},
    ignitionChecklist = {},
    ignitionBlockers = {},
    eventLog = {},
    maxEventLog = 8,

    update = {
      localVersion = localVersion,
      remoteVersion = "UNKNOWN",
      status = updateEnabled and "IDLE" or "DISABLED",
      httpStatus = "UNKNOWN",
      lastCheckResult = "Never",
      lastApplyResult = "Never",
      lastError = "",
      available = false,
      restartRequired = false,
      downloaded = false,
      manifestLoaded = false,
      filesToUpdate = 0,
      lastManifestError = "",
      lastCheckClock = 0,
      lastManifest = nil,
    },

    tick = 0,
    debugHitboxes = false,
  }
end

function M.defaultHardwareState()
  return {
    monitor = nil,
    monitorName = nil,
    reactor = nil,
    reactorName = nil,
    logic = nil,
    logicName = nil,
    laser = nil,
    laserName = nil,
    induction = nil,
    inductionName = nil,
    relays = {},
    blockReaders = {},
    readerRoles = {
      deuterium = nil,
      tritium = nil,
      inventory = nil,
      energy = nil,
      active = {},
      unknown = {},
    },
  }
end

return M
