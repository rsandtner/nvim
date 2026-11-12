-- Entry point. Core settings first, then one module per feature.
-- Plugins are managed by the built-in vim.pack; each feature module calls
-- vim.pack.add() for what it needs. Revisions are pinned in nvim-pack-lock.json
-- (committed), so a fresh machine installs exactly the locked versions.

-- Leader must be set before any mapping is defined.
vim.g.mapleader = ' '
vim.g.maplocalleader = '\\'

require('config.options')
require('config.keymaps')
require('config.autocmds')

-- Features: one module under lua/features/ each. Remove a line to drop a feature.
local features = {}

for _, feature in ipairs(features) do
  require('features.' .. feature)
end
