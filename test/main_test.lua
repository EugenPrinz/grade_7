-- Shared program starts, toggles, binds and stops grade workers on one computer.
local starts, binds, saved = { g7 = 0, g8 = 0 }, { g7 = 0, g8 = 0 }, nil
local events = {
  { "touch", "screen", 5, 25, 0 }, -- select G8
  { "key_down", "kb", 32, 57 }, -- enable G8
  { "key_down", "kb", 98, 48 }, -- bind G8 (stop, bind, restart)
  {}, -- scheduler tick while waiting for G8 to stop
  { "key_down", "kb", 112, 25 }, -- edit G8 parallel plan
  { "key_down", "kb", 49, 2 },
  { "key_down", "kb", 48, 11 },
  { "key_down", "kb", 0, 28 },
  { "key_down", "kb", 113, 16 }, -- quit
}
local workers = {}
local pulls = 0
package.loaded.component = {
  isAvailable = function(t) return t == "gpu" end,
  gpu = {
    maxResolution = function() return 160, 50 end,
    getResolution = function() return 80, 25 end,
    setResolution = function() end, setBackground = function() end,
    setForeground = function() end, fill = function() end, set = function() end,
    getScreen = function() return "screen" end,
  },
}
package.loaded.unicode = { sub = function(s, i, j) return s:sub(i, j) end }
package.loaded["waterline.bindings"] = {
  load = function() return saved or {} end,
  save = function(_, value) saved = value; return true end,
}
package.loaded.event = {
  pull = function()
    pulls = pulls + 1
    assert(pulls < 20, "event loop did not exit; starts=" .. starts.g7 .. "/" .. starts.g8 ..
      " binds=" .. binds.g8 .. " remaining=" .. #events)
    for _, worker in ipairs(workers) do
      if coroutine.status(worker) ~= "dead" then
        local ok, err = coroutine.resume(worker)
        assert(ok, err)
      end
    end
    local item = table.remove(events, 1)
    if item then return table.unpack(item) end
  end,
}
package.loaded.thread = {
  create = function(fn)
    local co = coroutine.create(fn)
    workers[#workers + 1] = co
    local ok, err = coroutine.resume(co)
    assert(ok, err)
    return { status = function() return coroutine.status(co) == "dead" and "dead" or "running" end }
  end,
}
for _, id in ipairs({ "g7", "g8" }) do
  package.loaded["waterline." .. id] = {
    main = function(args, opts)
      if args[1] == "bind" then binds[id] = binds[id] + 1; return end
      starts[id] = starts[id] + 1
      opts.onStatus({ online = true, cycle = 1, phase = "работает", progress = 20, maxProgress = 2400 })
      while not opts.shouldStop() do coroutine.yield() end
      return true
    end,
  }
end
local originalLoadfile = loadfile
loadfile = function(p)
  if p == "/home/waterline.cfg.lua" then return function() return { enabled = { g7 = true, g8 = false }, ui = true } end end
  return originalLoadfile(p)
end
require("waterline.main").main({})
assert(starts.g7 == 1 and starts.g8 == 2, "workers did not start/restart as expected")
assert(binds.g8 == 1 and binds.g7 == 0, "selected G8 binding was not opened")
assert(saved and saved.enabled.g7 and saved.enabled.g8, "module toggle was not saved")
assert(saved.baseGrade == 8 and saved.baseParallel == 10, "parallel plan was not saved")
for _, worker in ipairs(workers) do assert(coroutine.status(worker) == "dead", "worker remained running") end
print("single program orchestration: OK")
