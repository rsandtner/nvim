-- Auto-close brackets and quotes while typing (mini.pairs, insert mode only):
--   ( [ { " ' `   insert the pair, cursor in between
--   ) ] } " ' `   step over the closing char when it is next
--   <BS>          inside an empty pair deletes both halves
--   <CR>          between (), [] or {} opens an indented block
-- `<` is not paired, so generics and comparisons type as before; `'` after a
-- letter stays single ("don't"). Text inserted by completion is never paired,
-- so accepting `println()` does not become `println(())`.
--
-- Java/Kotlin buffers: intellij-lsp maps <CR> for accepting completions, so
-- features/intellij.lua owns <CR> there and calls MiniPairs.cr() itself.
vim.pack.add({ 'https://github.com/nvim-mini/mini.pairs' })

require('mini.pairs').setup({
  mappings = {
    -- Default, except no pair right after another `"`: the third quote of a
    -- Java text block / Kotlin raw string (`"""`) would otherwise open a new
    -- pair and leave a stray `"` behind.
    ['"'] = { action = 'closeopen', pair = '""', neigh_pattern = '^[^\\"]', register = { cr = false } },
  },
})
