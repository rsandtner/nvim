-- Java and Kotlin through JetBrains' IntelliJ server (intellij-lsp.nvim): one
-- server for navigation, diagnostics, completion, quick fixes, refactorings,
-- formatting and hierarchies, with Maven/Gradle import. Pre-alpha: options and
-- maps may change without notice, so the revision is pinned in
-- nvim-pack-lock.json. The server bundle (~380 MB, own JBR) downloads on first
-- start into stdpath('data')/intellij-lsp/server and needs about 2 GB of memory.
--
-- Loaded at startup, not by filetype: `nvim` in a project directory starts the
-- import from the build file before any source file is open. Without a build
-- file or a Java/Kotlin buffer no server starts.
--
-- Licence: IntelliJ IDEA Ultimate through the JetBrains Account. The server
-- keeps it in ~/Library/Application Support/JetBrains/IntelliJServer, shared
-- with every project; `:IntellijLspLicense` shows or changes it.
--
-- Buffer-local maps in Java/Kotlin buffers (plugin defaults, no clash with ours):
--   grr                 references with live preview (also into libraries/JDK)
--   <leader>ts / tu     type hierarchy: subtypes / supertypes
--   <leader>ci / co     call hierarchy: incoming / outgoing
--   <leader>ws          workspace symbols (server prompt)
--   <leader>r* <leader>d* <leader>b/B   run, test, debug (need nvim-dap)
-- Server-agnostic LSP maps (gd, <leader>ss, <leader>sr, ...) live in
-- features/lsp.lua.
vim.pack.add({ 'https://github.com/JetBrains/intellij-lsp.nvim' })

-- JDK the server analyzes code with when the project configures none (Gradle
-- toolchains and Maven compiler settings win). $JAVA_HOME comes from mise, so
-- a project's mise pin carries over; mise's global JDK otherwise.
local function default_sdk()
  local home = vim.env.JAVA_HOME
  if home and home ~= '' and vim.uv.fs_stat(home) then
    return home
  end
  local global = vim.fs.normalize('~/.local/share/mise/installs/java/global')
  return vim.uv.fs_stat(global) and global or nil
end

require('intellij-lsp').setup({
  -- Keep Catppuccin (features/theme.lua) instead of the bundled islands-dark.
  colorscheme = false,
  -- Consent answers, so the first-start screens never show (and headless
  -- Neovim can start the server). EULA.txt ships in the bundle:
  -- `<bundle>/bin/intellij-server --show-eula`.
  accept_eula = true,
  region = 'europe',
  data_sharing = 'none',
  default_sdk = default_sdk(),
  -- Its buffer-local <CR> would hide mini.pairs' <CR> (features/pairs.lua);
  -- the combined mapping below does both.
  enter_accepts_completion = false,
})

-- <CR> in Java/Kotlin buffers: accept the completion when the menu is up (as
-- the plugin's own mapping does), otherwise mini.pairs' <CR>, which opens an
-- indented block between {} (plain <CR> without features/pairs.lua).
local function termcodes(keys)
  return vim.api.nvim_replace_termcodes(keys, true, false, true)
end

vim.api.nvim_create_autocmd('LspAttach', {
  group = vim.api.nvim_create_augroup('features.jvm.intellij', { clear = true }),
  desc = 'IntelliJ: <CR> accepts completion or continues pairs',
  callback = function(ev)
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if not client or client.name ~= 'intellij' then
      return
    end
    vim.keymap.set('i', '<CR>', function()
      if vim.fn.pumvisible() == 1 then
        -- Nothing selected: <C-y> alone would swallow the newline, so move
        -- onto the first entry first.
        local selected = vim.fn.complete_info({ 'selected' }).selected
        return termcodes(selected == -1 and '<C-n><C-y>' or '<C-y>')
      end
      return _G.MiniPairs and MiniPairs.cr() or termcodes('<CR>')
    end, {
      buffer = ev.buf,
      expr = true,
      replace_keycodes = false,
      desc = 'Accept completion, or newline (pairs-aware)',
    })
  end,
})
