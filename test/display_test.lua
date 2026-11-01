-- Two connected T3 screens: the UI should choose the physically larger one.
local current = "small"
local size = { small = { 1, 1 }, large = { 3, 2 } }
local resolution = { small = { 80, 25 }, large = { 80, 25 } }
local bindings = {}
local gpu = {
  getScreen = function() return current end,
  bind = function(address, reset)
    assert(reset == false, "probing a screen must not clear it")
    if not size[address] then return false, "unknown screen" end
    current = address
    bindings[#bindings + 1] = address
    return true
  end,
  getSize = function() return table.unpack(size[current]) end,
  maxResolution = function() return 160, 50 end,
  getResolution = function() return table.unpack(resolution[current]) end,
  setResolution = function(w, h) resolution[current] = { w, h }; return true end,
  setBackground = function() end, setForeground = function() end, fill = function() end,
}
local component = {
  list = function(t)
    assert(t == "screen")
    local items = { "small", "large" }
    local i = 0
    return function() i = i + 1; return items[i] end
  end,
}
local display = require("waterline.display")
local session = assert(display.select(component, gpu, { width = 100, height = 30 }))
assert(current == "large", "the larger screen was not selected")
assert(session.selected.blocksW == 3 and session.selected.blocksH == 2)
assert(resolution.large[1] == 100 and resolution.large[2] == 30)
display.restore(session)
assert(current == "small" and resolution.small[1] == 80 and resolution.large[1] == 80,
  "screen and resolutions were not restored")

local preferred = assert(display.select(component, gpu,
  { width = 100, height = 30, preferred = "small" }))
assert(current == "small", "explicit screen selection was ignored")
display.restore(preferred)
assert(#bindings >= 4)
print("largest screen selection: OK")
