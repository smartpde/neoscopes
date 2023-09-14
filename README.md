# neoscopes

A lightweight Neovim plugin for simple project management or getting around in large
monorepos.

## Concept

This plugin lets you define the scopes and select the registered scopes.
The scope is simply a named collection of directories - it could be your
project, your directories in a large monorepo, some favorite directories, etc.

Note that this plugin does not actually do anything with the registered scopes,
you need to add the desired functionalily yourself. For example, see how to
integrate with [Telescope file search and live grep](#telescope-integration).

This simple setup can cover various workflows:
- Switching between different projects without leaving neovim.
- Limiting the "working area" in a large monorepo.
- Changing the working session when switching between projects, for example
  navigating to the project directory or opening certain files.
- Running commands when switching projects, for example running `git pull`.

Note: it is not a goal to enforce a certain format or structure of the
"projects". Is is more of a bookmark-style project management approach with
extension hooks for your custom logic.

## Installation

```lua
-- Optionally, install telescope for nicer scope selection UI.
use {"nvim-telescope/telescope.nvim"}

-- Install neoscopes.
use {"smartpde/neoscopes"}
```

## Registering scopes

The scopes can be registered as absolute paths (e.g. for different projects) or
as relative paths (e.g. for directories in a monorepo).

Registering scopes for different project directories:

```lua
require("neoscopes").setup({
  scopes = {
    {
      name = "project 1",
      dirs = {
        "~/projects/project1",
        "/tmp/out/project1",
      }
    },
    {
      name = "project 2",
      dirs = {
        "~/projects/project2",
      },
    }
  }
})
```

The scopes can also be added separately:

```lua
local scopes = require("neoscopes")
scopes.add({
  name = "project 1",
  dirs = {
    "~/projects/project1",
    "/tmp/out/project1",
  },
})
scopes.add({
  name = "project 2",
  dirs = {
    "~/projects/project2",
  },
})
```

The scopes can also be constrained to very specific files (instead of directories):
```lua
local scopes = require("neoscopes")
scopes.add({
  name = "specific file set 1",
  dirs = {
  },
  files = {
      '/path/to/file.txt',
      './path/to/other/file.txt'
    }
})
```

Registering directories of a large monorepo. You can register relative paths
as scope directories, and then set the current directory in neovim to the repo
root.

```lua
local scopes = require("neoscopes")
-- Let's say you are working on the networking area in the project.
scopes.add({
  name = "networking",
  dirs = {
    -- Relative directories in the repo.
    "src/net",
    "src/http",
  },
})
-- And sometimes you also like doing some UI changes.
scopes.add({
  name = "ui",
  dirs = {
    -- Relative directories in the repo.
    "ui/web",
    "ui/desktop",
  },
})
```

## Selecting scopes

Once the scope are registered, the current scope should be selected. This can
be done by calling `require("neoscopes").select()` to select with the UI, or
`require("neoscopes").set_current(scope_name)` to select programmatically.

Mapping example:

```lua
-- Select the current scope with telescope (if installed) or native UI
-- otherwise.
vim.api.nvim_set_keymap("n", "<Leader>fs",
  [[<cmd>lua require("neoscopes").select()<CR>]], {noremap = true})
```

Config example:

```lua
-- This can be done in e.g. init.lua, or in a project-specific config file.
local scopes = require("neoscopes")
-- ... register scopes
-- Then select the desired one.
scopes.set_current("project_1")
```

## Scope selection callback

When the scope is selected (either from UI or programmatically), the `on_select`
callback is invoked. This is where you can integrate any applicable logic for
the given project or directory, e.g. run `git pull`, changing the working
directory, etc.

Example:

```lua
local scopes = require("neoscopes")
scopes.add({
  name = "My git project",
  dirs = {"~/projects/git_project"},
  on_select = function()
    -- Change the current dir in neovim.
    -- Run `git pull`, etc.
  end
})
```

## Adding directories to all scopes

It's often useful to add certain directories to all registered scopes, e.g. the
directory with neovim's config files so that they are always at hand. This can
be done by using the `add_dirs_to_all_scopes(dirs)` function.

```lua
require("neoscopes").setup({
  -- register some scopes ...
  scopes = {},
  -- These directories will be present in all scopes, both current and future.
  add_dirs_to_all_scopes = {
    "~/dots",
    "~/Downloads"
  }
})
```

The same can also be done using the separate function:

```lua
local scopes = require("neoscopes")
-- ... register some scopes
-- These directories will be present in all scopes, both current and future.
scopes.add_dirs_to_all_scopes({
  "~/dots",
  "~/Downloads"
})
```

## Predefined scopes from `npm` workspaces 
neoscopes supports automatically defining scopes for npm projects that have multiple workspaces defined. When enabled, this will result in one workspace getting created for each npm workspace defined within the project's package.json file. 

npm defined scopes can be enabled by passing the following setup configuration parameter
```lua
require("neoscopes").setup({
  enable_scopes_from_npm = true
})
```

## Predefined scopes from `git` differences 
neoscopes supports defining scopes on files that differ between the current project's source-controlled files and other defined branches. Each configured branch will result in its own scope. 
```lua
require("neoscopes").setup({
  diff_branches_for_scopes = {"main", "origin/main" } 
})
```

### Predefined scopes from `git` differences from ancestors
in addition, neoscopes supports defining scopes on files that differ between the current project's source-controlled files and other defined branches that are considered ancestors of the current branch. This way you can create scopes of files you were working on in the current branch after branching it from the parent (ancestor) branch. Each configured branch will result in its own scope.

```lua
require("neoscopes").setup({
  diff_ancestors_for_scopes = {"main", "origin/main" }
})
```


## Project level configuration
By default, neoscopes will look for a file named `neoscopes.config.json` in the current working directory. If this file exists, the following configuration keys will be respected by the setup routine `enable_scopes_from_npm`, `scopes`, `diff_branches_for_scopes`, `diff_ancestors_for_scopes`, `add_dirs_to_all_scopes`. This provides a mechanism by which to define project specific neoscope settings without cluttering your neovim configuration.


## Telescope integration

This is just an example of how the scopes can be used.

Let's say that you want to limit the Telescopes's `live_grep` and `find_files`
to the current scope:

```lua
local scopes = require("neoscopes")

-- Helper functions to fetch the current scope and set `search_dirs`
_G.find_files = function()
  require('telescope.builtin').find_files({
    search_dirs = scopes.get_current_dirs()
  })
end
_G.live_grep = function()
  require('telescope.builtin').live_grep({
    search_dirs = scopes.get_current_dirs()
  })
end

vim.api.nvim_set_keymap("n", "<Leader>ff", ":lua find_files()<CR>",
  {noremap = true})
vim.api.nvim_set_keymap("n", "<Leader>fg", ":lua live_grep()<CR>",
  {noremap = true})
```

### including current scope files in the field of view of telescope pickers

Note the use of `get_current_paths` instead of `get_current_dirs` to combine scoped directories and files.

```lua
-- previous configuration settings

_G.find_files = function()
  require('telescope.builtin').find_files({
    search_dirs = scopes.get_current_paths()
  })
end
_G.live_grep = function()
  require('telescope.builtin').live_grep({
    search_dirs = scopes.get_current_paths()
  })
end

-- subsequent configuration settings
```

## Startup scope

The startup scope is the special scope which encompasses the directory of the
file you open directly with neovim. Let's say you run
`nvim /tmp/logs/test.log`. It's often helpful to have /tmp/logs automatically
in scope for looking around. The startup scope does that.

If neovim is launched without file/directory arguments, the startup scope will
contain the current directory. This covers the case when you first `cd` into the
directory and the run neovim from there.

```lua
local scopes = require("neoscopes")
-- The startup scope must be added explicitly, if needed.
scopes.add_startup_scope()
```

