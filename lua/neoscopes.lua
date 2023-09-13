local M = {}

---@class Scope
---@field public name string required, the scope name which identifies it uniquely.
---@field public dirs string[] required, the list of directories for this scope, could be absolute or relative.
---@field public files string[] required, the list of files for this scope, could be absolute or relative.
---@field public origin string optional, identifies the origin from which the scope was defined IE: "git" - diff with a git branch or "npm" - an npm workspace
---@field public on_select function optional, called when the scope is selected, either programmatically or using the UI.
local Scope = {}
---@class Config
---@field public scopes Scope[] the scopes to register.
---@field public add_dirs_to_all_scopes string[] the list of directories to include into all scopes.
---@field public current_scope string the current scope to select.
---@field public enable_scopes_from_npm boolean whether or not to load scopes from ./package.json workspaces
---@field public diff_branches_for_scopes string[] list of branch names to diff for git-diff scope definitions
---@field public diff_ancestors_for_scopes string[] list of branches to diff from git-ancestors scope definitions
---@field public neoscopes_config_filename string the name of the file that defines neoscopes configuration at a project-level
---@field public on_scope_selected - a callback function that takes a scope as an argument and is called when the scope is changed/selected
local Config = {}

local scopes = {}
local on_scope_selected = function(scope) end
local current_scope
local cross_scopes_dirs = {}

local function stat(filename)
  local s = vim.loop.fs_stat(filename)
  if not s then
    return nil
  end
  return s.type
end

local function get_scopes_from_package_json(name_prefix)
  if name_prefix == nil then
    name_prefix = "npm:"
  end
  local scope_list = {}
  if stat("package.json") ~= nil then
    local tab = vim.fn.json_decode(vim.fn.readfile("package.json"))
    if tab.workspaces ~= nil and tab.workspaces.packages ~= nil then
      local pkg_globs = tab.workspaces.packages
      for _, pkg_glob in pairs(pkg_globs) do
        for _, filename in ipairs(vim.fn.glob(pkg_glob .. "/package.json", true,
                                    true)) do
          filename = filename:gsub("/package.json$", "")
          table.insert(scope_list, {
            name = name_prefix .. filename,
            dirs = {filename},
            files = {},
            origin = "npm"
          })
        end
      end
    end
  end
  return scope_list
end

local function get_scopes_from_git_diffs(branches, name_prefix)
  if name_prefix == nil then
    name_prefix = "git:"
  end
  local scope_list = {}
  for _, to in pairs(branches) do
    local scope = {
      name = name_prefix .. to,
      dirs = {},
      files = {},
      origin = "git"
    }
    local handle = io.popen("git diff --name-only --relative " .. to)
    if handle ~= nil then
      local result = handle:read("*a")
      for line in result:gmatch("[^\r\n]+") do
        table.insert(scope.files, line)
      end
      scope.on_select = function()
        -- refresh a git scope every time the scope is selected so that the list of
        -- files that differ are updated in the scope
        local scopes_from_branch = get_scopes_from_git_diffs({to}, name_prefix)
        for _, refreshed_scope in ipairs(scopes_from_branch) do
          M.add(refreshed_scope)
        end
      end

      handle:close()
      table.insert(scope_list, scope)
    end
  end
  return scope_list
end

local function get_scopes_from_git_diffs_from_ancestors(branches, name_prefix)
  if name_prefix == nil then
    name_prefix = "git_ancestor:"
  end
  local scope_list = {}
  for _, to in pairs(branches) do
    local scope = {
      name = name_prefix .. to,
      dirs = {},
      files = {},
      origin = "git"
    }
    local handle = io.popen("git diff --name-only " .. to .. "...")
    local git_path_handle = io.popen("git rev-parse --show-toplevel")
    if handle ~= nil and git_path_handle ~= nil then
      local git_path = string.match(git_path_handle:read("*a"), "[^\r\n]+")
      git_path_handle:close()
      local result = handle:read("*a")
      for line in result:gmatch("[^\r\n]+") do
        table.insert(scope.files, git_path .. "/" .. line)
      end
      scope.on_select = function()
        -- refresh a git scope every time the scope is selected so that the list of
        -- files that differ are updated in the scope
        local scopes_from_branch = get_scopes_from_git_diffs({to}, name_prefix)
        for _, refreshed_scope in ipairs(scopes_from_branch) do
          M.add(refreshed_scope)
        end
      end

      handle:close()
      table.insert(scope_list, scope)
    end
  end
  return scope_list
end

---@return Config - a configuration table representing the project level configuration
local function get_project_level_config(config_filename)
  if not config_filename or stat(config_filename) == nil then
    return {}
  end
  local tab = vim.fn.json_decode(vim.fn.readfile(config_filename))
  return tab
end

---Sets up the plugin. The scopes could be registered either in the setup function or also
---with the `add(scope)` separately.
---@param config Config the configuration object
M.setup = function(config)
  if not config then
    return
  end
  local project_level_config_filename = config.neoscopes_config_filename or
                                          'neoscopes.config.json'
  local project_level_config = get_project_level_config(
                                 project_level_config_filename)
  if config.scopes then
    M.add_all(config.scopes)
  end
  if project_level_config.scopes then
    M.add_all(project_level_config.scopes)
  end
  if config.enable_scopes_from_npm or
    project_level_config.enable_scopes_from_npm then
    local npm_scopes = get_scopes_from_package_json()
    for _, scope in ipairs(npm_scopes) do
      M.add(scope)
    end
  end
  if config.diff_branches_for_scopes then
    local git_scopes =
      get_scopes_from_git_diffs(config.diff_branches_for_scopes)
    M.add_all(git_scopes)
  end
  if project_level_config.diff_branches_for_scopes then
    local git_scopes = get_scopes_from_git_diffs(
                         project_level_config.diff_branches_for_scopes)
    M.add_all(git_scopes)
  end
  if config.diff_ancestors_for_scopes then
    local git_scopes =
      get_scopes_from_git_diffs_from_ancestors(config.diff_ancestors_for_scopes)
    M.add_all(git_scopes)
  end
  if project_level_config.diff_ancestors_for_scopes then
    local git_scopes = get_scopes_from_git_diffs_from_ancestors(
                         project_level_config.diff_ancestors_for_scopes)
    M.add_all(git_scopes)
  end
  if config.add_dirs_to_all_scopes then
    M.add_dirs_to_all_scopes(config.add_dirs_to_all_scopes)
  end
  if config.current_scope then
    M.set_current(config.current_scope)
  end
  if config.on_scope_selected then
    on_scope_selected = config.on_scope_selected
  end
end

---Registers a list of scopes. If the scope with the same name already exists, it will
---be overwritten.
---@param scopes_to_add Scope[] a list of scope definitions
M.add_all = function(scopes_to_add)
  for _, scope in ipairs(scopes_to_add) do
    M.add(scope)
  end
end

---Registers the scope. If the scope with the same name already exists, it will
---be overwritten.
---@param scope Scope the scope definition
M.add = function(scope)
  if not scope.name then
    error("scope.name must be set")
  elseif not scope.dirs or type(scope.dirs) ~= "table" then
    error("scope.dirs must be a table of directory paths")
  elseif not scope.files then
    scope.files = {}
  elseif type(scope.files) ~= "table" then
    error(
      "scope.files must be a table of individual files to include in the scope (it is okay to be empty)")
  end
  for _, dir in ipairs(cross_scopes_dirs) do
    table.insert(scope.dirs, dir)
  end
  scopes[scope.name] = scope
end

---Registers the scope which contains either:
--- - the directory of the opened file
--- - the opened directory
--- - the current directory
M.add_startup_scope = function()
  local dirs = {}
  for i, arg in ipairs(vim.v.argv) do
    -- Skip program name and ignore known argmuments like -u
    if i > 1 and vim.v.argv[i - 1] ~= "-u" and arg:sub(1, 1) ~= "-" then
      local s = stat(arg)
      if s == "directory" then
        table.insert(dirs, arg)
      elseif s == "file" then
        local dir = vim.fn.fnamemodify(arg, ":h")
        table.insert(dirs, dir)
      end
    end
  end
  if #dirs == 0 then
    table.insert(dirs, vim.fn.getcwd())
  end
  M.add({name = "<startup>", dirs = dirs})
  M.set_current("<startup>")
end

---Adds the directories to all scopes, both currently registered and future.
---@param dirs string[] the list of directories, relative or absolute
M.add_dirs_to_all_scopes = function(dirs)
  if not dirs or type(dirs) ~= "table" then
    error("dirs must be a table of directory paths")
  end
  for _, dir in ipairs(dirs) do
    table.insert(cross_scopes_dirs, dir)
    for _, scope in pairs(scopes) do
      table.insert(scope.dirs, dir)
    end
  end
end

---Sets the current scope. The scope with the given name must be registred first.
---@param scope_name string the scope name
M.set_current = function(scope_name)
  local scope = scopes[scope_name]
  if scope == nil then
    error("Scope " .. scope_name .. " does not exist, call add(scope) first")
  end
  current_scope = scope
  if scope.on_select then
    scope.on_select()
  end
  on_scope_selected(scope)
end

---Returns the list of directories for the current scope. If no scope is selected, throws an error.
---@return string[] the list of directories for the current scope
M.get_current_dirs = function()
  if current_scope == nil then
    error(
      "Current scope not set, call set_current(scope_name) or select() first")
  end
  return current_scope.dirs
end

---Returns the list of paths for the current scope. If no scope is selected, throws an error.
---scope.dirs and scope.files are merged together.
---@return string[] the list of directories for the current scope
M.get_current_paths = function()
  if current_scope == nil then
    error(
      "Current scope not set, call set_current(scope_name) or select() first")
  end
  return { unpack(current_scope.dirs), unpack(current_scope.files) }
end

---Returns the entire, currently selected scope object. If no scope is selected, returns nil.
---@return Scope the current scope object or nil if no scope is set.
M.get_current_scope = function()
  return current_scope
end

local function select_with_telescope()
  local pickers = require("telescope.pickers")
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local previewers = require("telescope.previewers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local scope_list = {}
  for _, scope in pairs(scopes) do
    table.insert(scope_list, scope)
  end
  pickers.new({}, {
    prompt_title = "Select scope: ",
    finder = finders.new_table({
      results = scope_list,
      entry_maker = function(scope)
        return {
          value = scope.name,
          ordinal = scope.name,
          display = scope.name,
          scope = scope
        }
      end
    }),
    sorter = conf.file_sorter({}),
    previewer = previewers.new_buffer_previewer({
      title = "Directories",
      define_preview = function(self, entry)
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false,
          entry.scope.dirs)
      end
    }),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if selection then
          M.set_current(selection.value)
        end
      end)
      return true
    end
  }):find()
end

local function select_with_native_ui()
  local names = {}
  for name, _ in pairs(scopes) do
    table.insert(names, name)
  end
  table.sort(names)
  vim.ui.select(names, {prompt = "Select scope: "}, function(selected)
    if selected then
      M.set_current(selected)
    end
  end)
end

---Selects the current scope, eithers using telescope if it is installed, or with native UI otherwise.
M.select = function()
  if pcall(require, "telescope") then
    select_with_telescope()
  else
    select_with_native_ui()
  end
end

---Clears all registered scopes.
M.clear = function()
  scopes = {}
  current_scope = nil
end

---Returns the map of all registered scopes keyed by the scope name.
M.get_all_scopes = function()
  return scopes
end

return M

