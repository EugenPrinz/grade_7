-- GTNH 2.9 Grade 8 cycle simulator. Run: lua test/g8_sim.lua [up down [parallels]]
-- Models the 120 s cycle, one catalyst per 20 ticks, Infinity costs,
-- the hidden pair, unused catalysts and successful recipe outputs.
local names = { "up", "down", "strange", "charm", "bottom", "top" }
local damage = { up = 32235, down = 32236, strange = 32237,
  charm = 32238, bottom = 32239, top = 32240 }
local current
package.loaded.component = {}
package.loaded.computer = { uptime = function() return current.now end }
package.loaded.filesystem = {}
package.loaded.sides = {}
package.loaded.event = {}
package.loaded.unicode = {}
package.loaded["waterline.bindings"] = {}

local function scenario(first, second, options)
  options = options or {}
  local s = {
    first = first, second = second, now = 0, nextConsume = 1,
    infinity = options.infinity or 6048, parallel = options.parallel or 1,
    locale = options.locale or "ru", history = {}, bus = {},
    sources = {}, success = false, running = true, consume = options.consume ~= false,
    reason = nil, output = nil,
  }
  if options.infinity == 0 then s.infinity = 0 end
  for _, key in ipairs(names) do s.sources[key] = 3 end
  if options.missing then s.sources[options.missing] = 0 end

  function s:consumeOne()
    if not self.running or not self.consume or #self.bus == 0 then return end
    local key = self.bus[1]
    local prior = 0
    for _, previous in ipairs(self.history) do if previous == key then prior = prior + 1 end end
    local cost = 144 * 2 ^ prior -- GTUtility.powInt(2, count) * one ingot
    if self.infinity < cost then
      self.running, self.reason = false, "out of molten Infinity"
      return -- item remains in input bus because the machine did not consume it
    end
    self.infinity = self.infinity - cost
    table.remove(self.bus, 1)
    self.history[#self.history + 1] = key
    local n = #self.history
    if n > 1 then
      local a, b = self.history[n - 1], self.history[n]
      if (a == self.first and b == self.second) or (a == self.second and b == self.first) then
        self.success = true
      end
    end
  end
  function s:advance(seconds)
    local untilTime = self.now + seconds
    while self.nextConsume <= untilTime and self.nextConsume < 120 do
      self.now = self.nextConsume
      self:consumeOne()
      self.nextConsume = self.nextConsume + 1
    end
    self.now = untilTime
  end
  function s:finish()
    if not self.running or self.now < 120 then return nil end
    local inserted = #self.history
    self.output = {
      water = self.success and 900 * self.parallel or 0,
      baryonic = self.success and (2000 + 500 * self.parallel) or 0,
      unaligned = self.success and 2 or 0,
      returned = inserted - (self.success and 2 or 0),
      spent = self.success and 2 or 0,
    }
    self.running = false
    return self.output
  end
  local machine = {
    getWorkProgress = function() return s.running and math.floor(s.now * 20) or 0 end,
    getWorkMaxProgress = function() return s.running and s.now < 120 and 2400 or 0 end,
    setWorkAllowed = function(allowed)
      if not allowed then s.running, s.reason = false, "stopped by controller" end
    end,
    getSensorInformation = function()
      local info = {}
      if s.locale == "raw" then
        info[#info + 1] = "GT5U.infodata.pubp.catalyst_history"
      else
        info[#info + 1] = "История добавления катализаторов за этот цикл рецептов"
      end
      for i, key in ipairs(s.history) do info[#info + 1] = i .. ": " .. key end
      if s.locale == "raw" then
        info[#info + 1] = "GT5U.infodata.pubp.quark_combination: " .. (s.success and "Yes" or "No")
      else
        info[#info + 1] = "Правильно идентифицированая кварковая комбинация: " .. (s.success and "Yes" or "No")
      end
      return info
    end,
  }
  local transposer = {
    getStackInSlot = function(_, slot)
      local key = names[slot]
      return { name = "gregtech:gt.metaitem.03", damage = damage[key],
        label = key, size = s.sources[key] }
    end,
    transferItem = function(_, _, amount, slot)
      assert(amount == 1 and #s.bus == 0, "second catalyst arrived before previous was consumed")
      local key = names[slot]
      if s.sources[key] < 1 then return 0 end
      s.sources[key] = s.sources[key] - 1
      s.bus[#s.bus + 1] = key
      return 1
    end,
  }
  local routes = {}
  for slot, key in ipairs(names) do
    routes[key] = { proxy = transposer, from = 2, to = 1, slot = slot }
  end
  return s, machine, routes
end
os.sleep = function(seconds) current:advance(seconds) end
local g8 = require("waterline.g8")
local seen = {}
for i = 2, #g8.order do
  local a, b = g8.order[i - 1], g8.order[i]
  if a > b then a, b = b, a end
  seen[a .. ":" .. b] = true
end
local count = 0
for _ in pairs(seen) do count = count + 1 end
assert(#g8.order == 18 and count == 15, "plan does not cover all 15 unordered pairs")
local realPrint = print
local function run(first, second, options)
  local s, machine, routes = scenario(first, second, options)
  current = s
  print = function() end -- the program logs are tested through the result table below
  local ok = g8.runCycle(machine, routes, { pollInterval = 0.25, consumeTimeout = 5 }, 1)
  print = realPrint
  return s, ok
end

local chosenA, chosenB = arg[1], arg[2]
local parallel = tonumber(arg[3] or 1)
if not parallel or parallel % 1 ~= 0 or parallel < 1 then error("parallels must be a positive integer") end
if (chosenA and not chosenB) or (chosenB and not chosenA) then
  error("use two catalyst keys, for example: lua test/g8_sim.lua up down")
end
local valid = {}
for _, key in ipairs(names) do valid[key] = true end
if chosenA and (not valid[chosenA] or not valid[chosenB] or chosenA == chosenB) then
  error("choose two different keys: " .. table.concat(names, ", "))
end
print("pair                 in  Infinity L  returned  G8 L  baryonic L")
print("----------------------------------------------------------------")
local successes, worst = 0, 0
for i = 1, #names do
  for j = i + 1, #names do
    local a, b = names[i], names[j]
    if not chosenA or (a == chosenA and b == chosenB) or (a == chosenB and b == chosenA) then
      local s, ok = run(a, b, { locale = (i + j) % 2 == 0 and "raw" or "ru", parallel = parallel })
      assert(ok and s.success, "hidden pair " .. a .. "+" .. b .. " was not found")
      s:advance(120 - s.now)
      local output = assert(s:finish(), "cycle did not finish")
      local consumed = 6048 - s.infinity
      assert(output.returned == #s.history - 2 and output.spent == 2)
      assert(output.water == 900 * parallel
        and output.baryonic == 2000 + 500 * parallel and output.unaligned == 2)
      assert(#s.history <= 18 and #s.bus == 0, "extra item or unconsumed bus item")
      local total = 0
      local repeated = {}
      for _, key in ipairs(s.history) do
        total = total + 144 * 2 ^ (repeated[key] or 0)
        repeated[key] = (repeated[key] or 0) + 1
      end
      assert(consumed == total, "wrong Infinity cost")
      successes, worst = successes + 1, math.max(worst, consumed)
      print(string.format("%-20s %2d %11d %9d %5d %11d",
        a .. "+" .. b, #s.history, consumed, output.returned, output.water, output.baryonic))
    end
  end
end
local low, lowOk = run("up", "down", { infinity = 0 })
assert(not lowOk and low.reason == "out of molten Infinity" and #low.bus == 1
  and #low.history == 0, "empty Infinity hatch must stop before consuming the catalyst")
local missing, missingOk = run("up", "down", { missing = "bottom" })
assert(not missingOk and missing.reason == "stopped by controller" and #missing.history == 0,
  "empty catalyst source must stop the controller")
local stalled, stalledOk = run("up", "down", { consume = false })
assert(not stalledOk and #stalled.bus == 1 and #stalled.history == 0,
  "unresponsive machine must time out without sending a second catalyst")
print(string.format("OK: %d pair(s), worst Infinity %d L; shortage and timeout checks passed",
  successes, worst))
-- END test/g8_sim.lua
