-- lombok.config support for the IntelliJ server (features/jvm/intellij.lua).
--
-- The server's Lombok plugin looks every lombok.config key up in
-- LombokConfigIndex, which stays empty on the IntelliJ server, so every setting
-- falls back to its default (@CustomLog fails, lombok.log.fieldName and
-- lombok.accessors.chain are ignored). server-plugins/lombok-config-fix/ is a
-- tiny server plugin that overrides Lombok's ConfigDiscovery service and reads
-- lombok.config from disk instead (background: github.com/rsandtner/nvim/issues/22).
--
-- Not a feature on its own (not listed in init.lua): features/jvm/intellij.lua
-- passes jvm_args() to the server. The plugin is compiled here, on demand, with
-- the server bundle's own JBR (the bundle's classes are newer bytecode than a
-- project JDK can read) and cached per bundle version and source hash under
-- stdpath('data')/intellij-lsp/plugins/lombok-config-fix/. A failed build warns
-- once per start and the server runs without the plugin.
--
-- RE-VERIFY AFTER EVERY SERVER BUNDLE BUMP (intellij-lsp.nvim update): the
-- override relies on the platform accepting a service override that is not
-- declared open=true. Bundle 271.2085.0 only logs a WARN
-- (InstanceNotOverridableException) and applies it; a later build may refuse
-- it, and then lombok.config is silently ignored again. Check a @CustomLog
-- class with a lombok.config declaring lombok.log.custom.declaration.
--
-- lombok.config is read once per file and cached by the server: after editing
-- it, :LspRestart.

local M = {}

local NAME = 'lombok-config-fix'

-- Repo root of this config: lua/features/jvm/lombok.lua -> four levels up.
local source_dir = vim.fs.joinpath(
  vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2))))),
  'server-plugins',
  NAME
)

local function exists(path)
  return vim.uv.fs_stat(path) ~= nil
end

-- Root and version of the downloaded server bundle, or nil when it isn't there
-- yet (very first start downloads it). server_bundles/server_download are
-- internal modules of a pre-alpha plugin; if they move, the plugin is skipped.
local function bundle()
  local ok_b, bundles = pcall(require, 'intellij-lsp.server_bundles')
  local ok_d, download = pcall(require, 'intellij-lsp.server_download')
  if not (ok_b and ok_d and bundles.version and download.cache_root) then
    return nil
  end
  local root = vim.fs.joinpath(download.cache_root(), bundles.version)
  local javac = vim.fs.joinpath(root, 'jbr/Contents/Home/bin/javac')
  if not exists(javac) then
    javac = vim.fs.joinpath(root, 'jbr/bin/javac') -- Linux layout
  end
  if not exists(javac) then
    return nil
  end
  return { root = root, version = bundles.version, javac = javac }
end

-- Source files (sorted, relative to source_dir) and a short hash over their
-- names and contents, so any edit gives a new cache directory.
local function sources()
  local files = {}
  for name, type in vim.fs.dir(source_dir, { depth = math.huge }) do
    if type == 'file' then
      files[#files + 1] = name
    end
  end
  table.sort(files)
  local parts = {}
  for _, name in ipairs(files) do
    local f = assert(io.open(vim.fs.joinpath(source_dir, name), 'rb'))
    parts[#parts + 1] = name .. '\0' .. f:read('a')
    f:close()
  end
  return files, vim.fn.sha256(table.concat(parts, '\0')):sub(1, 12)
end

local function run(cmd, cwd)
  local res = vim.system(cmd, { cwd = cwd, text = true }):wait()
  if res.code ~= 0 then
    return nil, vim.trim((res.stderr or '') .. '\n' .. (res.stdout or ''))
  end
  return true
end

-- Compiles and packs the plugin into <dest>/lib/<NAME>.jar via a staging
-- directory, so a half-built plugin never sits in the cache.
local function build(b, files, dest)
  local staging = dest .. '.tmp'
  vim.fn.delete(staging, 'rf')
  local classes = vim.fs.joinpath(staging, 'classes')
  vim.fn.mkdir(vim.fs.joinpath(classes, 'META-INF'), 'p')
  vim.fn.mkdir(vim.fs.joinpath(staging, 'lib'), 'p')

  local java = vim.tbl_filter(function(f)
    return f:match('%.java$')
  end, files)
  -- Platform, Java and Lombok plugin jars (javac expands `dir/*`, not
  -- recursively, so the modules/ subfolders are listed too).
  local cp = {}
  local dirs = {
    'lib',
    'lib/modules',
    'plugins/java/lib',
    'plugins/java/lib/modules',
    'plugins/lombok/lib',
    'plugins/lombok/lib/modules',
  }
  for _, dir in ipairs(dirs) do
    cp[#cp + 1] = vim.fs.joinpath(b.root, dir, '*')
  end
  local cmd = {
    b.javac,
    '--release',
    '21',
    '-nowarn',
    '-cp',
    table.concat(cp, ':'),
    '-d',
    classes,
  }
  for _, f in ipairs(java) do
    cmd[#cmd + 1] = vim.fs.joinpath(source_dir, f)
  end
  local ok, err = run(cmd)
  if ok then
    vim.uv.fs_copyfile(
      vim.fs.joinpath(source_dir, 'META-INF/plugin.xml'),
      vim.fs.joinpath(classes, 'META-INF/plugin.xml')
    )
    -- The JBR ships no `jar` tool; a jar is a zip.
    ok, err = run({ '/usr/bin/zip', '-qr', vim.fs.joinpath(staging, 'lib', NAME .. '.jar'), '.' }, classes)
  end
  if not ok then
    vim.fn.delete(staging, 'rf')
    return nil, err
  end
  vim.fn.delete(classes, 'rf')
  vim.fn.delete(dest, 'rf')
  assert(vim.uv.fs_rename(staging, dest))
  return true
end

-- Drops cached builds for other bundle versions or older sources.
local function prune(cache, keep)
  for name in vim.fs.dir(cache) do
    if name ~= keep then
      vim.fn.delete(vim.fs.joinpath(cache, name), 'rf')
    end
  end
end

--- JVM options that load the plugin into the server, building it first when
--- the cache has no build for this bundle and source. Empty when the bundle
--- isn't downloaded yet or the build fails.
--- @return string[]
function M.jvm_args()
  local b = bundle()
  if not b or not exists(source_dir) then
    return {}
  end
  local files, hash = sources()
  local cache = vim.fs.joinpath(vim.fn.stdpath('data'), 'intellij-lsp/plugins', NAME)
  local key = b.version .. '-' .. hash
  local dest = vim.fs.joinpath(cache, key)

  if not exists(vim.fs.joinpath(dest, 'lib', NAME .. '.jar')) then
    vim.notify(('%s: building for server bundle %s…'):format(NAME, b.version), vim.log.levels.INFO)
    vim.fn.mkdir(cache, 'p')
    local ok, err = build(b, files, dest)
    if not ok then
      vim.notify(
        ('%s disabled for server bundle %s (lombok.config is ignored):\n%s'):format(NAME, b.version, err),
        vim.log.levels.WARN
      )
      return {}
    end
    prune(cache, key)
  end
  return { '-Dplugin.path=' .. dest }
end

return M
