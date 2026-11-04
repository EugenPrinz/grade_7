-- GTNH 2.9 Grade 8 controller. Install in /home/grade8.cfg.lua.
-- Addresses, sides and slots can be chosen on-screen with "grade8 bind".
return {
  machine = nil, -- Adapter next to Absolute Baryonic Perfection controller
  routes = {
    up = {}, down = {}, strange = {}, charm = {}, bottom = {}, top = {},
  },
  pollInterval = 0.25,
  consumeTimeout = 5, -- seconds to wait for a single catalyst to appear in machine history
  refillWait = 3, -- seconds to wait for an empty Dual Interface slot before pausing the machine
  infinityBuffer = 6048, -- with the optional "infinity" route: top the hatch up to this (worst case per cycle)
  -- me = false disables the ME stock check; nil = auto-detect the single ME component
}
-- END grade8.cfg.lua
