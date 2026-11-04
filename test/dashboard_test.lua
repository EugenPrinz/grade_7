-- 8-grade dashboard: draws inside 100x30, digit keys select a grade, Space starts it, state is saved.
package.path = "./?.lua;" .. package.path
local W, H = 100, 30
local saved
local started = {}
local writes = 0
local events = {
  {}, -- let enabled workers report status
  { "key_down", "kb", 52, 5 }, -- '4' selects G4
  { "key_down", "kb", 32, 57 }, -- Space enables G4
  {},
  { "key_down", "kb", 0, 208 }, -- ↓ selects G5
  { "touch", "scr", 10, 5 + 7 * 2, 0 }, -- touch row of G8
  { "key_down", "kb", 113, 16 }, -- quit
}
local workers = {}
local pulls = 0
local function inBounds(x, y, w, h)
  assert(x >= 1 and y >= 1 and x + (w or 1) - 1 <= W and y + (h or 1) - 1 <= H,
    string.format("draw out of bounds x=%d y=%d w=%s h=%s", x, y, tostring(w), tostring(h)))
end
package.loaded.component = {
  isAvailable = function(t) return t == "gpu" end,
  list = function() local done = false; return function() if not done then done = true; return "scr" end end end,
  gpu = {
    maxResolution = function() return 160, 50 end, getResolution = function() return 160, 50 end,
    getSize = function() return 4, 3 end, bind = function() return true end,
    setResolution = function() return true end, getScreen = function() return "scr" end,
    setBackground = function() end, setForeground = function() end,
    fill = function(x, y, w, h) inBounds(x, y, w, h) end,
    set = function(x, y, s)
      writes = writes + 1
      local len = utf8.len(s) or #s
      inBounds(x, y, len, 1)
    end,
  },
}
package.loaded.unicode = {
  sub = function(s, i, j)
    local a = utf8.offset(s, i) or #s + 1
    local b = j and ((utf8.offset(s, j + 1) or #s + 1) - 1) or #s
    return s:sub(a, b)
  end,
  len = utf8.len,
}
package.loaded["waterline.bindings"] = {
  load = function() return saved or {} end,
  save = function(_, value) saved = value; return true end,
}
package.loaded.event = {
  pull = function()
    for _, co in ipairs(workers) do
      if coroutine.status(co) ~= "dead" then assert(coroutine.resume(co)) end
    end
    pulls = pulls + 1
    assert(pulls < 40, "event loop did not exit")
    local item = table.remove(events, 1)
    if item then return table.unpack(item) end
  end,
}
package.loaded.thread = {
  create = function(fn)
    local co = coroutine.create(fn)
    workers[#workers + 1] = co
    assert(coroutine.resume(co))
    return { status = function() return coroutine.status(co) == "dead" and "dead" or "running" end }
  end,
}
for g = 1, 8 do
  local id = "g" .. g
  package.loaded["waterline." .. id] = {
    main = function(args, opts)
      started[id] = (started[id] or 0) + 1
      opts.onStatus({ online = true, cycle = 3, chance = 99.5, success = 2, failed = 1,
        phase = string.rep("очень длинная фаза ", 10), progress = 1200, maxProgress = 2400 })
      opts.onLog("INFO", string.rep("длинное событие ", 12))
      while not opts.shouldStop() do coroutine.yield() end
      return true
    end,
  }
end
local realLoadfile = loadfile
loadfile = function(p)
  if p == "/home/waterline.cfg.lua" then
    return function() return { enabled = { g1 = true, g7 = true }, ui = true } end
  end
  return realLoadfile(p)
end
require("waterline.main").main({})
loadfile = realLoadfile
assert(started.g1 == 1 and started.g7 == 1, "enabled grades did not start")
assert(started.g4 == 1, "G4 was not started from the dashboard")
assert(not started.g5 and not started.g8, "unselected grades started")
assert(saved and saved.enabled.g4 and saved.enabled.g1 and not saved.enabled.g5, "enabled state not saved")
local count = 0
for _ in pairs(saved.enabled) do count = count + 1 end
assert(count == 8, "state must list all 8 grades, got " .. count)
for _, co in ipairs(workers) do assert(coroutine.status(co) == "dead", "worker left running") end
assert(writes > 50, "dashboard did not draw")
print("8-grade dashboard: OK")
