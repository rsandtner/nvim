-- Fuzzy finding with fzf-lua: files, grep, commands, keymaps, help, buffers,
-- recent files. Needs the `fzf`, `fd` and `rg` CLIs (see Brewfile).
-- Search (IntelliJ-style popups) lives under <leader>s: files <leader>sf, text
-- <leader>sg, word under cursor / selection <leader>sw. The other pickers live
-- under <leader>f ("find").
vim.pack.add({ 'https://github.com/ibhagwan/fzf-lua' })

local fzf = require('fzf-lua')

-- Formatter `path.module_first` (IntelliJ "Search File" look):
--   KeycloakConfig.java  idp-core/…/config
-- The file name comes first; after it, dimmed, the containing module: the
-- nearest ancestor with a build.gradle(.kts) or pom.xml. Standard source roots
-- (src/<set>/java|kotlin|…) are stripped, and deeper paths collapse to
-- `module/…/<parent>`. Files outside any module show their parent relative to
-- the cwd. The full path is appended after a U+00A0 and 200 spaces, off-screen
-- (`--no-hscroll`), so typing still matches the whole path and `from` can get
-- the real path back; fzf-lua's `path.filename_first` v2 uses the same trick.
--
-- Grep hits (`path.module_first_grep`) get the same treatment, rearranged by
-- fzf's --with-nth so the module sits between location and text:
--   KeycloakConfig.java:42:  idp-core/…/config  realm = "acme"
-- fzf-lua appends `:line:col:text` after the formatted name, so the module
-- travels in the postfix between two U+00A0 (which double as fzf field
-- delimiters, next to `:`) and the full path follows as the last field.
--
-- `to` runs in fzf-lua's headless helper process, which receives it through
-- string.dump: the returned function must not use upvalues, so everything
-- lives in its body (the module lookup cache in a global). Only the highlight
-- code and the grep switch are spliced in.
local module_first_to = [[
  return function(s, o, m)
    local hl_dir = __HL_DIR__
    local grep = __GREP__
    local uv = vim.uv or vim.loop
    local root = vim.fs.normalize((o and o.cwd) or uv.cwd())
    _G.__fzf_module_first = _G.__fzf_module_first or {}
    -- dir relative to root ('' = root) -> module dir, or false
    local cache = _G.__fzf_module_first[root] or {}
    _G.__fzf_module_first[root] = cache

    local tail = s:match('[^/]+$') or s
    local dir = s:match('^(.*)/[^/]+$') or ''
    local shown = dir
    if not s:match('^[/~]') then
      -- nearest ancestor (up to root) with a build file
      local walked, mod, d = {}, nil, dir
      while true do
        if cache[d] ~= nil then mod = cache[d] break end
        walked[#walked + 1] = d
        local abs = d == '' and root or (root .. '/' .. d)
        if uv.fs_stat(abs .. '/build.gradle') or uv.fs_stat(abs .. '/build.gradle.kts')
            or uv.fs_stat(abs .. '/pom.xml') then
          mod = d
          break
        end
        if d == '' then mod = false break end
        d = d:match('^(.*)/[^/]+$') or ''
      end
      for _, w in ipairs(walked) do cache[w] = mod end

      if mod then
        local name = (mod == '' and root or mod):match('([^/]+)/*$')
        local rel = mod == '' and dir or dir:sub(#mod + 2)
        local prefix, lang = rel:match('^(src/[^/]+/([^/]+))')
        if prefix and (lang == 'java' or lang == 'kotlin' or lang == 'groovy'
              or lang == 'scala' or lang == 'resources') then
          rel = rel:sub(#prefix + 2)
        end
        if rel == '' then
          shown = name
        elseif not rel:find('/', 1, true) then
          shown = name .. '/' .. rel
        else
          shown = name .. '/…/' .. rel:match('[^/]+$')
        end
      end
    end

    if shown ~= '' and #hl_dir > 0 then shown = hl_dir .. shown .. m.utils.ansi_escseq.clear end
    local hidden = '\xc2\xa0' .. string.rep(' ', 200) .. s
    if grep then
      return tail, '\xc2\xa0  ' .. shown .. '  ' .. hidden
    end
    if shown == '' then return tail, hidden end
    return tail .. '  ' .. shown, hidden
  end
]]

-- Builds the formatter spec; `grep` selects the layout for `file:line:col:text`
-- entries.
local function module_first(grep)
  local fzf_opts = {
    -- Keep the hidden full path off-screen and drop the `..` ellipsis.
    ['--ellipsis'] = ' ',
    ['--no-hscroll'] = true,
  }
  if grep then
    -- Fields: 1 `name:`, 2 `line:`, 3 `col:`, 4..-3 text, -2 module, -1 full path.
    fzf_opts['--delimiter'] = '[:\u{a0}]'
    fzf_opts['--with-nth'] = '1,2,-2,4..-3'
  end
  return {
    enrich = function(o)
      o.fzf_opts = vim.tbl_extend('keep', o.fzf_opts or {}, fzf_opts)
      return o
    end,
    _to = function(o)
      local _, hl_dir = require('fzf-lua.utils').ansi_from_hl(o.hls.dir_part, 'x')
      return (module_first_to
        :gsub('__HL_DIR__', function() return ('%q'):format(hl_dir or '') end)
        :gsub('__GREP__', tostring(grep)))
    end,
    -- files: `<icons>name  dir<U+00A0><spaces>full/path`
    -- grep:  `<icons>name:l:c:text<U+00A0>  dir  <U+00A0><spaces>full/path`
    -- both -> `<icons>full/path` + `:l:c:text` for grep
    from = function(s)
      local utils = require('fzf-lua.utils')
      s = utils.strip_ansi_coloring(s)
      local hidden = s:find('\xc2\xa0 *[^\xa0]*$')
      if not hidden then return s end
      local full = s:sub(hidden + 2):gsub('^ +', '')
      local shown = s:sub(1, hidden - 1)
      if not grep then
        local icons = shown:match('^(.*' .. utils.nbsp .. ')') or ''
        return icons .. full
      end
      shown = shown:sub(1, (shown:find('\xc2\xa0[^\xa0]*$') or #shown + 1) - 1)
      local tail = full:match('[^/]+$') or full
      local i = shown:find(tail .. ':', 1, true)
      if not i then return full end
      return shown:sub(1, i - 1) .. full .. shown:sub(i + #tail)
    end,
  }
end

-- The file picker's defaults already fit: fd respects .gitignore, includes
-- dotfiles (toggle with <A-h>) and excludes .git/ and .jj/.
fzf.setup({
  formatters = {
    path = {
      module_first = module_first(false),
      module_first_grep = module_first(true),
    },
  },
  files = {
    formatter = 'path.module_first',
    -- Compact list centered on screen, prompt on top with results right under
    -- it; <F4> (fzf-lua default) toggles a preview below the list.
    winopts = {
      height = 0.45,
      width = 0.5,
      row = 0.6, -- 0 = top, 0.5 = centered, 1 = bottom
      col = 0.5,
      preview = { hidden = true, layout = 'vertical', vertical = 'down:55%' },
    },
  },
  -- Text search (live_grep, grep_cword, grep_visual): IntelliJ "Find in Files".
  -- rg regex, smart case (all lowercase = case-insensitive). Narrow by file glob
  -- after ` -- `, e.g. `realm -- *.kt` or `realm -- !*Test*`. <C-g> switches to
  -- fuzzy-filtering the current hits; <A-a> selects all, <A-q> sends the
  -- selection to quickfix.
  grep = {
    formatter = 'path.module_first_grep',
    -- Same scope as the file picker; rg skips dotfiles unless told otherwise.
    -- --trim drops leading indentation from the shown text (columns stay exact).
    rg_opts = '--column --line-number --no-heading --color=always --smart-case'
      .. ' --max-columns=4096 --trim --hidden --glob=!.git/ --glob=!.jj/ -e',
    -- Larger than file search, preview below the list on by default (<F4> hides it).
    winopts = {
      height = 0.8,
      width = 0.7,
      row = 0.6,
      col = 0.5,
      preview = { hidden = false, layout = 'vertical', vertical = 'down:50%' },
    },
  },
  commands = {
    actions = {
      -- Run the selected command; <C-e> puts it on the command line to add arguments.
      ['enter'] = fzf.actions.ex_run_cr,
      ['ctrl-e'] = fzf.actions.ex_run,
    },
  },
  oldfiles = {
    -- Also list files opened in this session, not only those in ShaDa.
    include_current_session = true,
  },
})

-- Keymap search (<leader>fk). Replaces fzf-lua's `keymaps` provider, which shows
-- the leader as <Space>, cuts descriptions at 33 characters next to a detail
-- column (`function: 0x…`) and lists maps without a description:
--   n   │ <leader>cf │ Code fixes for the problem
-- Only described maps are listed: global ones plus the current buffer's, so LSP
-- maps show where a server is attached. A buffer map hides a global one with the
-- same mode and keys, as it does when typed. <CR> runs the selected map.
local keymap_query_modes = { 'n', 'x', 's', 'o', 'i', 'c', 't' }
-- nvim_get_keymap reports maps set for several modes under one letter.
local keymap_mode_labels = { [' '] = 'nvo', ['!'] = 'ic' }
local keymap_mode_colors = { n = 'blue', i = 'red', c = 'yellow', t = 'green' }

-- `lhs` arrives with the leader already expanded (a space stays a raw space).
local function keymap_key_label(lhs)
  local leader = vim.g.mapleader or '\\'
  local localleader = vim.g.maplocalleader or '\\'
  local prefix = ''
  if lhs:sub(1, #leader) == leader then
    prefix, lhs = '<leader>', lhs:sub(#leader + 1)
  elseif lhs:sub(1, #localleader) == localleader then
    prefix, lhs = '<localleader>', lhs:sub(#localleader + 1)
  end
  return prefix .. lhs:gsub(' ', '<Space>')
end

-- Feeds the map's keys as if typed; visual maps reselect the last selection first.
local function keymap_run(keymap)
  local keys = keymap.lhs
  local mode = keymap.mode
  if mode == 'x' or mode == 'v' or mode == 's' then
    keys = 'gv' .. keys
  elseif mode ~= 'n' and mode ~= ' ' then
    vim.notify(('Keymap search runs only normal and visual maps, not mode %q'):format(mode),
      vim.log.levels.WARN)
    return
  end
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'm', false)
end

local function keymap_search()
  local utils = require('fzf-lua.utils')
  local found, order = {}, {}
  local function add(keymap)
    if not keymap.desc or keymap.desc == '' or keymap.lhs:match('^<Plug>')
        or keymap.lhs:match('^<SNR>') then
      return
    end
    local id = keymap.mode .. '\0' .. keymap.lhs
    if not found[id] then order[#order + 1] = id end
    if not found[id] or keymap.buffer ~= 0 then found[id] = keymap end
  end
  for _, mode in ipairs(keymap_query_modes) do
    for _, keymap in ipairs(vim.api.nvim_get_keymap(mode)) do add(keymap) end
  end
  for _, mode in ipairs(keymap_query_modes) do
    for _, keymap in ipairs(vim.api.nvim_buf_get_keymap(0, mode)) do add(keymap) end
  end

  local rows, key_width, mode_width = {}, 0, 0
  for _, id in ipairs(order) do
    local keymap = found[id]
    local row = {
      keymap = keymap,
      mode = keymap_mode_labels[keymap.mode] or keymap.mode,
      key = keymap_key_label(keymap.lhs),
      desc = keymap.desc:gsub('%s*\n%s*', ' '),
    }
    key_width = math.max(key_width, vim.fn.strdisplaywidth(row.key))
    mode_width = math.max(mode_width, #row.mode)
    rows[#rows + 1] = row
  end
  -- By key, case-insensitive first so <leader>sd and <leader>sD sit together.
  table.sort(rows, function(a, b)
    local ka, kb = a.key:lower(), b.key:lower()
    if ka ~= kb then return ka < kb end
    if a.key ~= b.key then return a.key < b.key end
    return a.mode < b.mode
  end)

  local entries, by_entry = {}, {}
  local separator = utils.ansi_codes.grey(' │ ')
  for _, row in ipairs(rows) do
    local color = utils.ansi_codes[keymap_mode_colors[row.mode] or 'magenta']
    local key_pad = string.rep(' ', key_width - vim.fn.strdisplaywidth(row.key))
    local entry = color(row.mode .. string.rep(' ', mode_width - #row.mode))
      .. separator .. row.key .. key_pad .. separator .. row.desc
    entries[#entries + 1] = entry
    by_entry[utils.strip_ansi_coloring(entry)] = row.keymap
  end

  fzf.fzf_exec(entries, {
    prompt = 'Keymaps> ',
    fzf_opts = { ['--no-multi'] = true, ['--tiebreak'] = 'index' },
    winopts = { height = 0.6, width = 0.7, row = 0.6, col = 0.5 },
    actions = {
      ['enter'] = function(selected)
        local keymap = selected[1] and by_entry[utils.strip_ansi_coloring(selected[1])]
        if keymap then keymap_run(keymap) end
      end,
    },
  })
end

local map = vim.keymap.set
map('n', '<leader>sf', fzf.files, { desc = 'Find files' })
map('n', '<leader>sg', fzf.live_grep, { desc = 'Search by grep' })
map('n', '<leader>sw', fzf.grep_cword, { desc = 'Search the word under the cursor' })
map('x', '<leader>sw', fzf.grep_visual, { desc = 'Search the selection' })
map('n', '<leader>fc', fzf.commands, { desc = 'Find commands' })
map('n', '<leader>fk', keymap_search, { desc = 'Find keymaps' })
map('n', '<leader>fh', fzf.helptags, { desc = 'Find help tags' })
map('n', '<leader>fb', fzf.buffers, { desc = 'Find buffers' })
map('n', '<leader>fr', fzf.oldfiles, { desc = 'Find recent files' })
map('n', '<leader>f.', fzf.resume, { desc = 'Resume last picker' })
