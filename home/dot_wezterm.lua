local wezterm = require 'wezterm'
local act = wezterm.action

local config = wezterm.config_builder()
local is_macos = wezterm.target_triple and wezterm.target_triple:find('darwin') ~= nil
local home = os.getenv('HOME')

config.font = wezterm.font 'FiraMono Nerd Font'
config.font_size = 12
config.color_scheme = 'Galizur'
config.initial_cols = 120
config.initial_rows = 28
config.scrollback_lines = 1000000
config.use_fancy_tab_bar = false
config.tab_bar_at_bottom = true
config.hide_tab_bar_if_only_one_tab = false
config.status_update_interval = 1000

-- Use a local mux domain so windows, tabs and panes can persist without zellij.
config.unix_domains = {
  {
    name = 'local_mux',
  },
}
config.default_gui_startup_args = { 'connect', 'local_mux' }
if home then
  config.default_prog = { home .. '/.local/bin/wezterm-session-log' }
end

if is_macos then
  -- Make left Option behave like Meta for shell editing while preserving right Option for accents.
  config.send_composed_key_when_left_alt_is_pressed = true
  config.send_composed_key_when_right_alt_is_pressed = false
end

-- Use the standard tmux prefix.
config.leader = { key = 'b', mods = 'CTRL', timeout_milliseconds = 1000 }

wezterm.on('update-status', function(window, _pane)
  local status = { window:active_workspace() }
  local key_table = window:active_key_table()

  if key_table then
    table.insert(status, key_table)
  end

  if window:leader_is_active() then
    table.insert(status, 'LEADER')
  end

  window:set_right_status(' ' .. table.concat(status, ' | ') .. ' ')
end)

local keys = {
  { key = 'b', mods = 'LEADER', action = act.SendKey { key = 'b', mods = 'CTRL' } },
  { key = 'c', mods = 'LEADER', action = act.SpawnTab 'CurrentPaneDomain' },
  { key = '"', mods = 'LEADER', action = act.SplitVertical { domain = 'CurrentPaneDomain' } },
  { key = '%', mods = 'LEADER', action = act.SplitHorizontal { domain = 'CurrentPaneDomain' } },
  { key = 's', mods = 'LEADER', action = act.SplitVertical { domain = 'CurrentPaneDomain' } },
  { key = 'v', mods = 'LEADER', action = act.SplitHorizontal { domain = 'CurrentPaneDomain' } },
  { key = 'h', mods = 'LEADER', action = act.ActivatePaneDirection 'Left' },
  { key = 'j', mods = 'LEADER', action = act.ActivatePaneDirection 'Down' },
  { key = 'k', mods = 'LEADER', action = act.ActivatePaneDirection 'Up' },
  { key = 'l', mods = 'LEADER', action = act.ActivatePaneDirection 'Right' },
  { key = 'LeftArrow', mods = 'LEADER', action = act.AdjustPaneSize { 'Left', 5 } },
  { key = 'DownArrow', mods = 'LEADER', action = act.AdjustPaneSize { 'Down', 5 } },
  { key = 'UpArrow', mods = 'LEADER', action = act.AdjustPaneSize { 'Up', 5 } },
  { key = 'RightArrow', mods = 'LEADER', action = act.AdjustPaneSize { 'Right', 5 } },
  { key = 'z', mods = 'LEADER', action = act.TogglePaneZoomState },
  { key = 'x', mods = 'LEADER', action = act.CloseCurrentPane { confirm = true } },
  { key = '&', mods = 'LEADER', action = act.CloseCurrentTab { confirm = true } },
  { key = 'n', mods = 'LEADER', action = act.ActivateTabRelative(1) },
  { key = 'p', mods = 'LEADER', action = act.ActivateTabRelative(-1) },
  { key = 'o', mods = 'LEADER', action = act.ActivateLastTab },
  { key = '[', mods = 'LEADER', action = act.ActivateCopyMode },
  {
    key = ',',
    mods = 'LEADER',
    action = act.PromptInputLine {
      description = 'Rename tab',
      action = wezterm.action_callback(function(window, _pane, line)
        if line then
          window:active_tab():set_title(line)
        end
      end),
    },
  },
  {
    key = 'w',
    mods = 'LEADER',
    action = act.ShowLauncherArgs {
      flags = 'FUZZY|TABS|WORKSPACES|DOMAINS|COMMANDS',
      title = 'WezTerm Launcher',
    },
  },
  {
    key = 'W',
    mods = 'LEADER',
    action = act.PromptInputLine {
      description = 'New workspace name',
      action = wezterm.action_callback(function(window, pane, line)
        if line and line ~= '' then
          window:perform_action(
            act.SwitchToWorkspace {
              name = line,
            },
            pane
          )
        end
      end),
    },
  },
  { key = 'd', mods = 'LEADER', action = act.DetachDomain 'CurrentPaneDomain' },
}

for index = 1, 9 do
  table.insert(keys, {
    key = tostring(index),
    mods = 'LEADER',
    action = act.ActivateTab(index - 1),
  })
end

table.insert(keys, {
  key = '0',
  mods = 'LEADER',
  action = act.ActivateTab(9),
})

if is_macos then
  table.insert(keys, { key = 'LeftArrow', mods = 'OPT', action = act.SendString '\x1bb' })
  table.insert(keys, { key = 'RightArrow', mods = 'OPT', action = act.SendString '\x1bf' })
  table.insert(keys, { key = 'Backspace', mods = 'OPT', action = act.SendString '\x1b\x7f' })
end

config.keys = keys

return config
