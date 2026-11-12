-- LSP keymaps for every language server (servers themselves are configured by
-- their own feature, e.g. features/intellij.lua for Java and Kotlin).
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
  end,
})
