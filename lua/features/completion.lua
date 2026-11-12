-- Completion while typing for every filetype except Java and Kotlin
-- (blink.cmp): language server, file paths and words from open buffers.
--
-- Java/Kotlin buffers keep intellij-lsp's own setup on Neovim's built-in
-- vim.lsp.completion (features/jvm/intellij.lua): IntelliJ's Kotlin items
-- insert nothing themselves and do the real edit through a follow-up server
-- command, which blink garbles (`println()()`), and the plugin's word
-- triggers, postfix-snippet indentation and follow-up menus are built on the
-- built-in. Revisit once intellij-lsp.nvim supports blink.
--
-- Keys follow the built-in menu, so they are the same in every buffer:
--   <C-space>       open the menu / toggle the documentation
--   <C-n> / <C-p>   next / previous item (also <Down> / <Up>)
--   <C-y>           accept           <C-e>   close without accepting
--   <C-b> / <C-f>   scroll the documentation
--   <C-k>           signature help
--   <Tab>/<S-Tab>   jump inside an expanded snippet
-- <CR> is never mapped: it stays a (mini.pairs-aware) newline.
--
-- The fuzzy matcher is a prebuilt Rust library that blink downloads for the
-- release it is on, so it is pinned to 1.x release tags, not a branch.
vim.pack.add({
  { src = 'https://github.com/saghen/blink.cmp', version = vim.version.range('1') },
})

-- Filetypes whose completion intellij-lsp owns (its default `filetypes`).
local builtin_filetypes = { java = true, kotlin = true }

require('blink.cmp').setup({
  -- Called on every completion attempt; blink's own exclusions (prompts,
  -- recording a macro, ...) still apply on top.
  enabled = function()
    return not builtin_filetypes[vim.bo.filetype]
  end,
  keymap = { preset = 'default' },
  sources = {
    default = { 'lsp', 'path', 'buffer' },
  },
  completion = {
    documentation = { auto_show = true, auto_show_delay_ms = 300 },
  },
  -- `:` keeps Neovim's own wildmenu.
  cmdline = { enabled = false },
})
