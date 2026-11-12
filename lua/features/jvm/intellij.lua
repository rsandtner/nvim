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
-- Ours, set on attach below:
--   <leader>ft          file template picker for an empty .java/.kt buffer
--                       (:IntellijLspFileTemplate; new files get it unasked)
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
  -- Loads server-plugins/lombok-config-fix so lombok.config is honoured
  -- (features/jvm/lombok.lua; drop this line to go without).
  jvm_args = require('features.jvm.lombok').jvm_args(),
  -- <CR> must not accept a completion; the mapping below keeps it a
  -- (mini.pairs-aware) newline.
  enter_accepts_completion = false,
})

-- <CR> in Java/Kotlin buffers never picks a completion item: it closes the
-- menu and inserts a newline through mini.pairs' <CR> (an indented block
-- between {}; plain <CR> without features/pairs.lua). Pick items with <C-y>.
local function termcodes(keys)
  return vim.api.nvim_replace_termcodes(keys, true, false, true)
end

-- Closes the completion menu without choosing anything new. Text already
-- inserted by <C-n>/<C-p> stays (<C-y>); an entry only highlighted with the
-- arrow keys, or no entry at all, leaves the typed text as it is (<C-e>).
local function close_menu()
  local info = vim.fn.complete_info({ 'selected', 'items' })
  local item = info.items[info.selected + 1]
  if item and item.word ~= '' then
    local before = vim.api.nvim_get_current_line():sub(1, vim.fn.col('.') - 1)
    if before:sub(-#item.word) == item.word then
      return termcodes('<C-y>')
    end
  end
  return termcodes('<C-e>')
end

vim.api.nvim_create_autocmd('LspAttach', {
  group = vim.api.nvim_create_augroup('features.jvm.intellij', { clear = true }),
  desc = 'IntelliJ: <CR> closes completion and continues pairs, <leader>ft file templates',
  callback = function(ev)
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if not client or client.name ~= 'intellij' then
      return
    end
    vim.keymap.set('i', '<CR>', function()
      local close = vim.fn.pumvisible() == 1 and close_menu() or ''
      return close .. (_G.MiniPairs and MiniPairs.cr() or termcodes('<CR>'))
    end, {
      buffer = ev.buf,
      expr = true,
      replace_keycodes = false,
      desc = 'Newline (pairs-aware), never accepts a completion',
    })
    -- IntelliJ's file templates (Class, Interface, Enum, Record, ...); the
    -- plugin only fills empty buffers and says so otherwise.
    vim.keymap.set('n', '<leader>ft', '<Cmd>IntellijLspFileTemplate<CR>', {
      buffer = ev.buf,
      desc = 'Find IntelliJ file templates',
    })
  end,
})
