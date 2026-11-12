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
local features = {
  'theme',
  'treesitter',
  'fzf',
  'oil',
  'lsp', -- after fzf: its pickers are fzf-lua
  'diagnostics',
  'dap', -- before jvm.intellij: its run/test/debug need nvim-dap
  'jvm.intellij',
  'jvm.lens', -- Run/Test lenses at the end of the @Test line
  'jvm.debug_panel', -- debug panel order: Watches, Locals, Call stack
  'completion', -- blink.cmp everywhere except Java/Kotlin (built-in there)
  'pairs',
  'git',
}

for _, feature in ipairs(features) do
  require('features.' .. feature)
end
