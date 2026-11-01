-- WaterLineProgram settings. Enable modules on screen or edit this initial state.
return {
  enabled = {
    g7 = true,
    g8 = false, -- enable after Grade 8 is assembled and bound
  },
  baseGrade = 7,
  baseParallel = 1, -- planning only; set the actual value in the machine GUI
  ui = true, -- GPU T3 + screen T3; dashboard uses 100x30 for larger text
}
-- END waterline.cfg.lua
