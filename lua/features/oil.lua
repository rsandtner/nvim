-- File browser with oil.nvim: a directory is a buffer. Edit the listing like
-- text (add a line to create, change a name to rename or move, delete a line to
-- delete) and `:w` applies it after a confirmation listing every change.
-- `-` opens the current file's directory in a sidebar split on the right (and
-- goes up inside oil). Picking a file there closes the sidebar and opens the
-- file in the window you came from. `nvim .` still opens oil full-window.
-- Icons come from mini.icons (see features/theme.lua).
vim.pack.add({ 'https://github.com/stevearc/oil.nvim' })

-- Same scope as the fzf-lua file picker: dotfiles are shown, .git/ and .jj/ are
-- hidden. `g.` toggles hidden entries.
local hidden = { ['.git'] = true, ['.jj'] = true }

local oil = require('oil')

-- Sidebar: a fixed-width split on the right. `w:oil_sidebar` marks its window
-- and `w:oil_target` remembers the window files open in.
local SIDEBAR_WIDTH = 40

local function find_sidebar()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.w[win].oil_sidebar then
      return win
    end
  end
end

local function close_sidebar()
  local win = find_sidebar()
  if not win then
    return
  end
  if #vim.api.nvim_tabpage_list_wins(0) == 1 then
    vim.cmd.enew() -- last window: keep it, drop the listing
  else
    vim.api.nvim_win_close(win, false)
  end
end

local function open_sidebar()
  local target = vim.api.nvim_get_current_win()
  -- Directory of the current file; oil resolves nil to the cwd.
  local dir = vim.bo.buftype == '' and vim.fn.expand('%:p:h') or nil
  local win = find_sidebar()
  if win then
    vim.api.nvim_set_current_win(win)
  else
    vim.cmd('botright vsplit')
    win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_width(win, SIDEBAR_WIDTH)
    vim.wo[win].winfixwidth = true
    vim.w[win].oil_sidebar = true
  end
  vim.w[win].oil_target = target
  oil.open(dir)
end

-- <CR> and the split keys. In the sidebar a file opens in the target window
-- and the sidebar closes; directories (and anything outside the sidebar) use
-- oil's own select.
local select_opts = {
  edit = {},
  split = { horizontal = true },
  vsplit = { vertical = true },
  tabedit = { tab = true },
}

local function open_entry(cmd)
  local entry, dir = oil.get_cursor_entry(), oil.get_current_dir()
  if not (vim.w.oil_sidebar and entry and dir) then
    return oil.select(select_opts[cmd])
  end
  local path = dir .. entry.name
  if vim.fn.isdirectory(path) == 1 then
    return oil.select()
  end
  local target = vim.w.oil_target
  close_sidebar()
  if target and vim.api.nvim_win_is_valid(target) then
    vim.api.nvim_set_current_win(target)
  end
  vim.cmd[cmd](vim.fn.fnameescape(path))
end

oil.setup({
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
    -- Open keys go through open_entry so the sidebar closes on a file.
    -- Split keys match fzf-lua: <C-s> split, <C-v> vsplit, <C-t> tab.
    ['<CR>'] = { callback = function() open_entry('edit') end, desc = 'Open entry' },
    ['<C-s>'] = { callback = function() open_entry('split') end, desc = 'Open in a split' },
    ['<C-v>'] = { callback = function() open_entry('vsplit') end, desc = 'Open in a vertical split' },
    ['<C-t>'] = { callback = function() open_entry('tabedit') end, desc = 'Open in a new tab' },
    ['q'] = { callback = close_sidebar, desc = 'Close the sidebar' },
    ['gR'] = 'actions.refresh',
  },
})

vim.keymap.set('n', '-', open_sidebar, { desc = 'File browser (sidebar)' })
