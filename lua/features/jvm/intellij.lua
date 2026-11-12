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
-- Run, test and debug (through nvim-dap, features/dap.lua; every launch is
-- built by Gradle/Maven first, output in :IntellijLspOutput):
--   <leader>rr / rd     run / debug the main class at the cursor
--   <leader>rl          run the code lens on this line (Run/Debug, Run/Debug Test)
--   <leader>rt / dt     run / debug the test method at the cursor, else its class
--   <leader>rT          run the last test run again, same mode
--                       failed tests go to quickfix (:copen), on the assert line
--   <leader>b / B       toggle breakpoint / conditional breakpoint
--   <leader>dc dn di do continue, step over / into / out
--   <leader>dq de dw dv stop, evaluate, watch, debug panel (frames, locals, watches)
-- Ours, set on attach below:
--   <leader>ft          file template picker for an empty .java/.kt buffer
--                       (:IntellijLspFileTemplate; new files get it unasked)
--   <leader>f           format the changed lines only (git hunks; a file
--                       without git info whole). Shares the <leader>f prefix
--                       with the pickers, so it fires after 'timeoutlen'
--   <leader>o           organize imports (IntelliJ's Optimize Imports)
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

-- Formats only the lines git sees as changed: IntelliJ's formatter rewrites far
-- more than you touched, which is noise in a repository that does not run it.
-- Hunks go bottom-up and synchronously, so a reflowed hunk never shifts the
-- line numbers of one still to come. Without gitsigns data (no repository) the
-- whole file is formatted; an untracked file is one big hunk anyway.
local function format_changed(bufnr)
  local ok, gitsigns = pcall(require, 'gitsigns')
  local hunks = ok and gitsigns.get_hunks(bufnr) or nil
  local format = function(range)
    vim.lsp.buf.format({ bufnr = bufnr, name = 'intellij', range = range, async = false, timeout_ms = 5000 })
  end
  if not hunks then
    return format(nil)
  end
  local ranges = {}
  for _, hunk in ipairs(hunks) do
    if hunk.added.count > 0 then -- pure deletions leave nothing to format
      ranges[#ranges + 1] = { hunk.added.start, hunk.added.start + hunk.added.count - 1 }
    end
  end
  if #ranges == 0 then
    return vim.notify('No changed lines to format', vim.log.levels.INFO)
  end
  table.sort(ranges, function(a, b) return a[1] > b[1] end)
  for _, r in ipairs(ranges) do
    local last = vim.api.nvim_buf_get_lines(bufnr, r[2] - 1, r[2], false)[1] or ''
    format({ start = { r[1], 0 }, ['end'] = { r[2], #last } })
  end
end

-- IntelliJ's Optimize Imports, offered as a `source.organizeImports` code
-- action; the title match covers a server that files it under another kind.
local function organize_imports()
  vim.lsp.buf.code_action({
    context = { only = { 'source.organizeImports', 'source' }, diagnostics = {} },
    filter = function(action)
      local kind = action.kind or ''
      return kind:find('^source%.organizeImports') ~= nil
        or (action.title or ''):lower():find('optimi[sz]e imports') ~= nil
        or (action.title or ''):lower():find('organi[sz]e imports') ~= nil
    end,
    apply = true,
  })
end

vim.api.nvim_create_autocmd('LspAttach', {
  group = vim.api.nvim_create_augroup('features.jvm.intellij', { clear = true }),
  desc = 'IntelliJ: <CR> closes completion and continues pairs, <leader>ft/f/o templates, format, imports',
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
    vim.keymap.set('n', '<leader>f', function() format_changed(ev.buf) end, {
      buffer = ev.buf,
      desc = 'Format changed lines (IntelliJ)',
    })
    vim.keymap.set('n', '<leader>o', organize_imports, {
      buffer = ev.buf,
      desc = 'Organize imports (IntelliJ)',
    })
  end,
})
