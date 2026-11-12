-- LSP keymaps for every language server (servers themselves are configured by
-- their own feature, e.g. features/jvm/intellij.lua for Java and Kotlin).
--
-- Neovim's built-in LSP maps stay as they are:
--   K          hover                    grn   rename
--   CTRL-]     definition (tagfunc)     gra   code actions
--   grr        references               gri   implementations
--   grt        type definition          gO    document symbols (loclist)
--   [d / ]d    previous / next diagnostic, <C-w>d diagnostic float
--   <C-s>      signature help (insert mode)
-- On top of them:
--   gd         definition, opens a list when there are several
--   <leader>ca code actions in a small popup under the cursor (normal: cursor,
--              visual: selection); opens even when there is only one action
--   <leader>cf quick fixes for the problem under the cursor, same popup; a lone
--              fix applies right away
-- and fzf-lua pickers under <leader>s ("search", next to files and grep):
--   <leader>ss  symbols in this file      <leader>sS  symbols in the workspace
--   <leader>sr  references                <leader>si  implementations
--   <leader>sd  diagnostics in this file  <leader>sD  diagnostics in the workspace
local fzf = require('fzf-lua')
local map = vim.keymap.set

map('n', '<leader>ss', fzf.lsp_document_symbols, { desc = '[S]earch [S]ymbols in file' })
map('n', '<leader>sS', fzf.lsp_live_workspace_symbols, { desc = '[S]earch [S]ymbols in workspace' })
map('n', '<leader>sr', fzf.lsp_references, { desc = '[S]earch [R]eferences' })
map('n', '<leader>si', fzf.lsp_implementations, { desc = '[S]earch [I]mplementations' })
map('n', '<leader>sd', fzf.diagnostics_document, { desc = '[S]earch [D]iagnostics in file' })
map('n', '<leader>sD', fzf.diagnostics_workspace, { desc = '[S]earch [D]iagnostics in workspace' })

vim.api.nvim_create_autocmd('LspAttach', {
  group = vim.api.nvim_create_augroup('features.lsp', { clear = true }),
  desc = 'Buffer-local LSP keymaps',
  callback = function(ev)
    -- Built-in definition, not a picker: it follows jar:/jrt: locations into
    -- library and JDK sources that servers like intellij-lsp hand back.
    map('n', 'gd', vim.lsp.buf.definition, { buffer = ev.buf, desc = 'Go to definition' })
    -- jump1 off: fzf-lua would otherwise apply a lone action without asking.
    -- silent: fzf-lua is not our vim.ui.select backend, which it warns about.
    -- Like IntelliJ's Alt+Enter: a compact list just below the cursor (sizes
    -- above 1 are cells; fzf-lua shifts it up when it would leave the screen).
    local popup = { relative = 'cursor', row = 1, col = 0, height = 12, width = 60 }
    map({ 'n', 'x' }, '<leader>ca', function()
      fzf.lsp_code_actions({ jump1 = false, silent = true, previewer = false, winopts = popup })
    end, { buffer = ev.buf, desc = '[C]ode [A]ctions' })
    -- The same popup with only the fixes for the problem under the cursor:
    -- Neovim sends the diagnostics at the cursor and keeps actions of kind
    -- 'quickfix' (intellij-lsp tags its fixes so); a lone fix applies at once.
    map('n', '<leader>cf', function()
      fzf.lsp_code_actions({
        jump1 = true,
        silent = true,
        previewer = false,
        winopts = popup,
        context = { only = { 'quickfix' } },
      })
    end, { buffer = ev.buf, desc = '[C]ode [F]ixes for the problem' })
  end,
})
