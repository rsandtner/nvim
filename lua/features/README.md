# Features

One Lua module per feature (`<name>.lua`), enabled by listing `<name>` in the
`features` table in `init.lua`. A module owns its own `vim.pack.add()` call,
setup, and keymaps, so deleting the file and its line removes the feature.
