-- WaterLineProgram settings. Modules are switched on the dashboard (Space); this is the initial state.
-- Components are bound on screen: WaterLineProgram bind gN (saved to /home/waterline.gN.bindings.lua).
return {
  enabled = {
    g1 = false, g2 = false, g3 = false, g4 = false,
    g5 = false, g6 = false,
    g7 = true,
    g8 = false, -- enable after Grade 8 is assembled and bound
  },
  baseGrade = 7,
  baseParallel = 1, -- planning only; set the actual value in the machine GUI
  ui = true, -- GPU T3 + screen T3; dashboard uses 100x30 for larger text

  -- Per-grade tuning (G1–G6). Everything is optional; defaults are in waterline/gN.lua.
  -- refillSources = true: sources are ME Dual Interfaces that AE refills while pumping.
  grades = {
    g2 = {
      ozoneTarget = 1024000, -- 128000 | 256000 | 512000 | 1024000 → 20/40/60/80%; never above 1 024 000
    },
    g3 = {
      reserveTicks = 200, -- stop dosing PAC this many ticks before the cycle ends
    },
    g4 = {
      tolerance = 0.02, -- aim for |pH - 7| <= 0.02 (machine accepts 0.05)
    },
    g5 = {
      maxCycles = 4, -- heating cycles per run; 3 fit into 120 s (99%), water boost makes 100%
    },
    g6 = {
      pollInterval = 0.25, -- how often the requested lens is checked
    },
  },
}
-- END waterline.cfg.lua
