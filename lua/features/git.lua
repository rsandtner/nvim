-- Git signs, hunks and blame (gitsigns.nvim).
--
-- Signs mark added / changed / deleted lines against the index. In this
-- colocated jj setup the index tracks the parent of the working copy, so the
-- signs show what the current change touches. Each kind has its own glyph
-- (+ added, ~ changed, _ / ‾ deleted below / above) and the line number takes
-- the same colour, so the kinds stay apart even when the colours are close.
--
--   ]h / [h       next / previous hunk (in diff mode: ]c / [c behaviour)
--   <leader>hp    preview hunk          <leader>hb   blame line (popup)
--   <leader>hs    stage hunk / lines    <leader>hB   toggle inline blame
--   <leader>hr    reset hunk / lines    <leader>hd   diff against index
--   <leader>hS    stage buffer          ih           hunk text object
--   <leader>hR    reset buffer
--   <leader>hw    toggle word diff      <leader>hl   toggle line highlight
vim.pack.add({ 'https://github.com/lewis6991/gitsigns.nvim' })

local gitsigns = require('gitsigns')

local signs = {
  add = { text = '+' },
  change = { text = '~' },
  delete = { text = '_' },
  topdelete = { text = '‾' },
  changedelete = { text = '≃' },
}

gitsigns.setup({
  signs = vim.tbl_extend('force', signs, { untracked = { text = '┆' } }),
  signs_staged = signs,
  numhl = true,
  current_line_blame_opts = { delay = 300 },
  current_line_blame_formatter = '<author>, <author_time:%Y-%m-%d> · <summary>',
  preview_config = { border = 'rounded' },
  on_attach = function(bufnr)
    local function map(mode, lhs, rhs, desc)
      vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, desc = desc })
    end

    local function nav(direction, diff_key)
      return function()
        if vim.wo.diff then
          vim.cmd.normal({ diff_key, bang = true })
        else
          gitsigns.nav_hunk(direction)
        end
      end
    end

    local function visual_lines()
      return { vim.fn.line('.'), vim.fn.line('v') }
    end

    map('n', ']h', nav('next', ']c'), 'Next git hunk')
    map('n', '[h', nav('prev', '[c'), 'Previous git hunk')

    map('n', '<leader>hp', gitsigns.preview_hunk, 'Preview hunk')
    map('n', '<leader>hs', gitsigns.stage_hunk, 'Stage hunk')
    map('n', '<leader>hr', gitsigns.reset_hunk, 'Reset hunk')
    map('v', '<leader>hs', function() gitsigns.stage_hunk(visual_lines()) end, 'Stage lines')
    map('v', '<leader>hr', function() gitsigns.reset_hunk(visual_lines()) end, 'Reset lines')
    map('n', '<leader>hS', gitsigns.stage_buffer, 'Stage buffer')
    map('n', '<leader>hR', gitsigns.reset_buffer, 'Reset buffer')
    map('n', '<leader>hd', gitsigns.diffthis, 'Diff against index')

    map('n', '<leader>hb', function() gitsigns.blame_line({ full = true }) end, 'Blame line')
    map('n', '<leader>hB', gitsigns.toggle_current_line_blame, 'Toggle inline blame')
    map('n', '<leader>hw', gitsigns.toggle_word_diff, 'Toggle word diff')
    map('n', '<leader>hl', gitsigns.toggle_linehl, 'Toggle line highlight')

    map({ 'o', 'x' }, 'ih', gitsigns.select_hunk, 'Inside hunk')
  end,
})
