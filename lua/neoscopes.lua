local M = {}

---@class Scope
---@field public name string required, the scope name which identifies it uniquely.
---@field public dirs string[] required, the list of directories for this scope, could be absolute or relative.
---@field public on_select function optional, called when the scope is selected, either programmatically or using the UI.
local Scope = {}
---@class Config
---@field public scopes Scope[] the scopes to register.
---@field public add_dirs_to_all_scopes string[] the list of directories to include into all scopes.
---@field public current_scope string the current scope to select.
local Config = {}

local scopes = {}
local current_scope
local cross_scopes_dirs = {}

local function stat(filename)
  local s = vim.loop.fs_stat(filename)
  if not s then
    return nil
  end
  return s.type
end

local function dirname(filepath)
  local is_win = vim.loop.os_uname().sysname == "Windows"
  local path_sep = is_win and "\\" or "/"
  local result = filepath:gsub(path_sep .. "([^" .. path_sep .. "]+)$",
                   function()
      return ""
    end)
  return result
end

---Sets up the plugin. The scopes could be registered either in the setup function or also
---with the `add(scope)` separately.
---@param config Config the configuration object
M.setup = function(config)
  if not config then
    return
  end
  if config.scopes then
    for _, scope in ipairs(config.scopes) do
      M.add(scope)
    end
  end
  if config.add_dirs_to_all_scopes then
    M.add_dirs_to_all_scopes(config.add_dirs_to_all_scopes)
  end
  if config.current_scope then
    M.set_current(config.current_scope)
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
    if i > 1 and vim.v.argv[i - 1] ~= "-u" then
      local s = stat(arg)
      if s == "directory" then
        table.insert(dirs, arg)
      elseif s == "file" then
        table.insert(dirs, dirname(arg))
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

local function select_with_telescope()
  local pickers = require "telescope.pickers"
  local actions = require "telescope.actions"
  local action_state = require "telescope.actions.state"
  local previewers = require "telescope.previewers"
  local finders = require "telescope.finders"
  local conf = require"telescope.config".values
  local scope_list = {}
  for _, scope in pairs(scopes) do
    table.insert(scope_list, scope)
  end
  pickers.new({}, {
    prompt_title = "Select scope: ",
    finder = finders.new_table {
      results = scope_list,
      entry_maker = function(scope)
        return {
          value = scope.name,
          ordinal = scope.name,
          display = scope.name,
          scope = scope
        }
      end
    },
    sorter = conf.file_sorter({}),
    previewer = previewers.new_buffer_previewer {
      title = "Directories",
      define_preview = function(self, entry)
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false,
          entry.scope.dirs)
      end
    },
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

return M
