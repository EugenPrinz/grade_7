-- GTNH 2.9 Grade 8 controller. Install in /home/grade8.cfg.lua.
-- Addresses, sides and slots can be chosen on-screen with "grade8 bind".
return {
  machine = nil, -- Adapter next to Absolute Baryonic Perfection controller
  routes = {
    up = {}, down = {}, strange = {}, charm = {}, bottom = {}, top = {},
  },
  pollInterval = 0.25,
  consumeTimeout = 5, -- seconds to wait for a single catalyst to appear in machine history
}
-- END grade8.cfg.lua
