-- Pull in the wezterm API
local wezterm = require 'wezterm'

-- This will hold the configuration.
local config = wezterm.config_builder()

-- This is where you actually apply your config choices.

-- Make Option send Meta (ESC-prefix) for readline/zle/fish bindings
config.send_composed_key_when_left_alt_is_pressed = true
config.send_composed_key_when_right_alt_is_pressed = false

-- Optional: dedicate Cmd + [ / ] for prev/next tab and leave splits to Zellij
config.keys = wezterm.gui.default_key_tables().default -- start from defaults if you prefer

send_composed_key_when_left_alt_is_pressed  = true
send_composed_key_when_right_alt_is_pressed = true
-- Map Option+Arrows to ESC-b / ESC-f (word back/forward)
config.keys = {
  -- {key="LeftArrow", mods="ALT",  action=wezterm.action{SendString="\x1bb"}}, -- M-b
  -- {key="RightArrow",mods="ALT",  action=wezterm.action{SendString="\x1bf"}}, -- M-f
  -- Command + Right = Move forward one word (Alt + f)
  { key = "RightArrow", mods = "OPT", action = wezterm.action.SendString("\x1bf") },
  -- Command + Left = Move backward one word (Alt + b)
  { key = "LeftArrow",  mods = "OPT", action = wezterm.action.SendString("\x1bb") },
  -- {key="Backspace", mods="ALT",  action=wezterm.action{SendString="\x1b\x7f"}}, -- M-backspace
}

-- Increase emulator scrollback for “whole session” search
config.scrollback_lines = 1000000

-- For example, changing the initial geometry for new windows:
config.initial_cols = 120
config.initial_rows = 28

-- or, changing the font size and color scheme.
config.font = wezterm.font 'FiraMono Nerd Font'
config.font_size = 12
config.color_scheme = 'Galizur'

-- Finally, return the configuration to wezterm:
return config
