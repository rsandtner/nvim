-- Diagnostics like IntelliJ's problem navigation, for every source (LSP or not):
--   <leader>e / <leader>E   next / previous problem: errors first; only when the
--                           buffer has no errors, warnings (IntelliJ's F2 /
--                           Shift+F2). Wraps around the buffer.
--   resting on a problem    after 'updatetime' (250 ms) its full message opens
--                           in a float under the cursor; moving closes it.
-- Quick fixes for the problem under the cursor (<leader>cf) live with the other
-- code action maps in features/lsp.lua.
-- Neovim's own [d / ]d (every severity) and <C-w>d (float on demand) stay.
local severity = vim.diagnostic.severity

--- Severity the jumps stop at: errors while there are any, warnings otherwise.
--- Hints and infos are never stops; nil when there is nothing to jump to.
local function problem_severity(bufnr)
  for _, level in ipairs({ severity.ERROR, severity.WARN }) do
    if #vim.diagnostic.get(bufnr, { severity = level }) > 0 then
      return level
    end
  end
end

local function jump(count)
  return function()
    local level = problem_severity(0)
    if not level then
      vim.notify('No problems in this buffer', vim.log.levels.INFO)
      return
    end
    -- float = false: the CursorHold float below shows the message.
    vim.diagnostic.jump({ count = count, severity = level, wrap = true, float = false })
  end
end

vim.keymap.set('n', '<leader>e', jump(1), { desc = 'Next problem (errors first)' })
vim.keymap.set('n', '<leader>E', jump(-1), { desc = 'Previous problem (errors first)' })

-- Details at the cursor, like IntelliJ's problem tooltip. A float rather than
-- virtual_lines = { current_line = true }: virtual lines push the code below
-- down and back up every time the cursor crosses a problem line.
vim.api.nvim_create_autocmd('CursorHold', {
  group = vim.api.nvim_create_augroup('features.diagnostics', { clear = true }),
  desc = 'Show the diagnostics under the cursor in a float',
  callback = function(ev)
    -- An open hover (K) or signature float belongs to the same preview slot;
    -- opening ours would close it.
    local preview = vim.b[ev.buf].lsp_floating_preview
    if preview and vim.api.nvim_win_is_valid(preview) then
      return
    end
    vim.diagnostic.open_float({
      scope = 'cursor',
      header = '', -- just the message, no "Diagnostics:" title
      focusable = false,
      close_events = { 'CursorMoved', 'InsertEnter', 'BufLeave', 'WinLeave', 'FocusLost' },
    })
  end,
})
