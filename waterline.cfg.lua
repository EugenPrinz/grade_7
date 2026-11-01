-- WaterLineProgram settings. Enable modules on screen or edit this initial state.
return {
  enabled = {
    g7 = true,
    g8 = false, -- enable after Grade 8 is assembled and bound
  },
  baseGrade = 7,
  baseParallel = 1, -- planning only; set the actual value in the machine GUI
  ui = true, -- GPU + screen 80x25 or larger; false = text log
}
-- END waterline.cfg.lua
