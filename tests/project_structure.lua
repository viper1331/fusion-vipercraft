-- tests/project_structure.lua
-- Verifie la structure minimale du projet local.

local M = {}

function M.run(ctx)
  local fail = assert(ctx.fail, "ctx.fail requis")
  local ok = assert(ctx.ok, "ctx.ok requis")
  local toPath = assert(ctx.toPath, "ctx.toPath requis")
  local exists = assert(ctx.exists, "ctx.exists requis")

  local requiredDirs = {
    "core",
    "io",
    "ui",
    "tests",
  }

  local requiredFiles = {
    "fusion.lua",
    "fusion.version",
    "fusion.manifest.json",
    "install.lua",
    "core/app.lua",
    "core/energy.lua",
    "core/logger.lua",
    "core/temperature.lua",
    "core/runtime_loop.lua",
    "io/display_backend.lua",
    "tests/energy_units.lua",
    "tests/temperature_units.lua",
    "tests/laser_device_selection.lua",
    "tests/laser_threshold.lua",
    "tests/ignition_blockers.lua",
    "tests/config_laser_count.lua",
    "tests/logger.lua",
    "tests/display_backend.lua",
    "tests/install_display_dtfuel_config.lua",
    "tests/reactor_diagram_render.lua",
    "tests/responsive_render.lua",
    "ui/chrome.lua",
    "ui/views.lua",
    "ui/components.lua",
    "ui/induction_diagram.lua",
  }

  for _, dir in ipairs(requiredDirs) do
    local fullPath = toPath(dir)
    if not exists(fullPath) or not fs.isDir(fullPath) then
      fail(30, "Dossier requis manquant: " .. dir)
    else
      ok("Dossier present: " .. dir)
    end
  end

  for _, filePath in ipairs(requiredFiles) do
    local fullPath = toPath(filePath)
    if not exists(fullPath) or fs.isDir(fullPath) then
      fail(31, "Fichier structurel manquant: " .. filePath)
    else
      ok("Fichier structurel present: " .. filePath)
    end
  end
end

return M
