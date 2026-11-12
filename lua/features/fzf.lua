-- Fuzzy finding with fzf-lua: files, grep, commands, keymaps, help, buffers,
-- recent files. Needs the `fzf`, `fd` and `rg` CLIs (see Brewfile).
-- File search is <leader>sf; the other pickers live under <leader>f ("find").
vim.pack.add({ 'https://github.com/ibhagwan/fzf-lua' })

local fzf = require('fzf-lua')

-- The file picker's defaults already fit: fd respects .gitignore, includes
-- dotfiles (toggle with <A-h>) and excludes .git/ and .jj/.
fzf.setup({
  grep = {
    -- Same scope as the file picker; rg skips dotfiles unless told otherwise.
    rg_opts = '--column --line-number --no-heading --color=always --smart-case'
      .. ' --max-columns=4096 --hidden --glob=!.git/ --glob=!.jj/ -e',
  },
  commands = {
    actions = {
      -- Run the selected command; <C-e> puts it on the command line to add arguments.
      ['enter'] = fzf.actions.ex_run_cr,
      ['ctrl-e'] = fzf.actions.ex_run,
    },
  },
  oldfiles = {
    -- Also list files opened in this session, not only those in ShaDa.
    include_current_session = true,
  },
})

local map = vim.keymap.set
map('n', '<leader>sf', fzf.files, { desc = 'Find files' })
map('n', '<leader>fg', fzf.live_grep, { desc = 'Find by grep' })
map('n', '<leader>fc', fzf.commands, { desc = 'Find commands' })
map('n', '<leader>fk', fzf.keymaps, { desc = 'Find keymaps' })
map('n', '<leader>fh', fzf.helptags, { desc = 'Find help tags' })
map('n', '<leader>fb', fzf.buffers, { desc = 'Find buffers' })
map('n', '<leader>fr', fzf.oldfiles, { desc = 'Find recent files' })
map('n', '<leader>f.', fzf.resume, { desc = 'Resume last picker' })
