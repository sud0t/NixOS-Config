-- Require All seperate config files

debug = {
  disable_logs = true,
}

require("configs.monitors")
require("configs.autostart")
require("configs.environment")
require("configs.looks")
require("configs.windows")
require("configs.misc")
require("configs.binds")
require("configs.inputs")
require("configs.hyprtheme")
-- require("noctalia.noctalia-colors.conf")

-- For Noctalia Color templates
require("noctalia").apply_theme()
