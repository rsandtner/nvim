local group = vim.api.nvim_create_augroup('config', { clear = true })

vim.api.nvim_create_autocmd('TextYankPost', {
  group = group,
  desc = 'Briefly highlight yanked text',
  callback = function()
    vim.hl.on_yank()
  end,
})

-- A file without a final newline is read with 'noeol'. The LSP client then
-- sends its text without that newline, but sends edits at the end of the file
-- for one line further down. rust-analyzer silently drops those edits, so its
-- copy falls behind the buffer ("Invalid offset LineCol ..." errors, formatting
-- on stale text), and semantic token requests reach past its last line.
-- 'fixeol' (on by default) writes the newline anyway, so assume it from the
-- start: the file on disk ends up the same, and every server sees it.
-- Upstream: https://github.com/neovim/neovim/issues/20129
vim.api.nvim_create_autocmd('BufReadPost', {
  group = group,
  desc = "Treat a file without a final newline as having one ('fixeol' adds it on write)",
  callback = function(ev)
    local bo = vim.bo[ev.buf]
    if bo.fixeol and not bo.binary and not bo.eol then
      bo.eol = true
    end
  end,
})

-- Quickfix and location-list windows (failed tests, grep, references) close
-- with q or <Esc>, like a float. <Esc> elsewhere still clears the search
-- highlight (config/keymaps.lua).
vim.api.nvim_create_autocmd('FileType', {
  group = group,
  pattern = 'qf',
  desc = 'Close quickfix/location-list windows with q or <Esc>',
  callback = function(ev)
    for _, lhs in ipairs({ 'q', '<Esc>' }) do
      vim.keymap.set('n', lhs, '<Cmd>close<CR>', { buffer = ev.buf, nowait = true, desc = 'Close this list' })
    end
  end,
})
