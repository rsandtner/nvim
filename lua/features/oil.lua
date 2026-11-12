-- File browser with oil.nvim: a directory is a buffer. Edit the listing like
-- text (add a line to create, change a name to rename or move, delete a line to
-- delete) and `:w` applies it after a confirmation listing every change.
-- `-` opens the parent directory of the current file (and goes up inside oil).
-- Icons come from mini.icons (see features/theme.lua).
vim.pack.add({ 'https://github.com/stevearc/oil.nvim' })

-- Same scope as the fzf-lua file picker: dotfiles are shown, .git/ and .jj/ are
-- hidden. `g.` toggles hidden entries.
local hidden = { ['.git'] = true, ['.jj'] = true }

require('oil').setup({
  -- Oil opens directories instead of netrw (`nvim .`, `:e some/dir`).
  default_file_explorer = true,
  columns = { 'icon' },
  -- Deleted files go to the macOS Trash (`g\` browses it) instead of being gone.
  delete_to_trash = true,
  -- Every change is confirmed before it touches the disk, even a single rename.
  skip_confirm_for_simple_edits = false,
  view_options = {
    show_hidden = false,
    is_hidden_file = function(name)
      return hidden[name] == true
    end,
  },
  keymaps = {
    -- Keep <C-h>/<C-l> for window navigation (config/keymaps.lua).
    ['<C-h>'] = false,
    ['<C-l>'] = false,
    -- Split keys match fzf-lua: <C-s> split, <C-v> vsplit, <C-t> tab.
    ['<C-s>'] = { 'actions.select', opts = { horizontal = true } },
    ['<C-v>'] = { 'actions.select', opts = { vertical = true } },
    ['gR'] = 'actions.refresh',
  },
})

vim.keymap.set('n', '-', '<cmd>Oil<CR>', { desc = 'Open parent directory' })
