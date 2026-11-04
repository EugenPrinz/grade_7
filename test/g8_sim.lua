-- GTNH 2.9 Grade 8 simulator, modelled on MTEPurificationUnitBaryonicPerfection (GT5U 5.09.54.265):
--   * every 20 ticks while running, every catalyst stack in the bus is consumed; its cost
--     144 L * 2^(same catalyst already in history) is drained from ONE input hatch, otherwise
--     stopMachine(): progress = 0, machine disabled, endCycle never runs (catalysts lost)
--   * success iff the hidden unordered pair appears as two ADJACENT history entries
--   * endCycle returns every inserted catalyst except the matched pair to the output bus
--   * getInfoData: raw GT5U.infodata.pubp.* keys, English or Russian translation
-- Run: lua test/g8_sim.lua [up down [parallels]]
package.path = "./?.lua;" .. package.path
local names = { "up", "down", "strange", "charm", "bottom", "top" }
local damage = { up = 32235, down = 32236, strange = 32237, charm = 32238, bottom = 32239, top = 32240 }
local label = {}
for k in pairs(damage) do label[k] = k:sub(1, 1):upper() .. k:sub(2) .. "-Quark Releasing Catalyst" end
local keyOf = {}
for k, d in pairs(damage) do keyOf[d] = k end

local W -- current scenario
package.loaded.component = { list = function() return function() end end,
  get = function(a) return W and W.proxies and W.proxies[a] and a or nil end,
  proxy = function(a) return W.proxies[a] end,
  invoke = function() error("no component") end }
package.loaded.computer = { uptime = function() return W.t / 20 end }
package.loaded.filesystem = {}
package.loaded.sides = {}
package.loaded.event = {}
package.loaded.unicode = {}
package.loaded["waterline.bindings"] = {}

local function inv(size) return { size = size, slots = {} } end

local function tick()
  W.t = W.t + 1
  local m = W.m
  if W.refill and W.t % 10 == 0 then W.refill() end
  if not m.running then return end
  m.prog = m.prog + 1
  if m.prog % 20 == 0 then
    for slot = 1, W.bus.size do
      local st = W.bus.slots[slot]
      if st then
        local key = keyOf[st.damage]
        local prior = 0
        for _, h in ipairs(m.history) do if h == key then prior = prior + 1 end end
        local cost = 144 * 2 ^ prior
        if W.hatch.amount < cost then
          -- stopMachine: cycle aborted, history kept until the next start clears it
          m.running, m.prog, m.maxp, m.disabled = false, 0, 0, true
          m.stopped = true
          m.lost = #m.history
          return
        end
        W.hatch.amount = W.hatch.amount - cost
        W.infinityUsed = W.infinityUsed + cost
        for _ = 1, st.size do m.history[#m.history + 1] = key end
        W.bus.slots[slot] = nil
      end
    end
    if not m.matched then
      for i = 1, #m.history - 1 do
        local a, b = m.history[i], m.history[i + 1]
        if (a == m.first and b == m.second) or (a == m.second and b == m.first) then
          m.matched = true; m.baryonic = 2000; break
        end
      end
    end
  end
  if m.prog >= m.maxp then
    m.running, m.prog, m.maxp = false, 0, 0
    local returned = #m.history - (m.matched and 2 or 0)
    m.result = { success = m.matched, returned = returned, inserted = #m.history,
      water = m.matched and 900 * W.parallel or 0,
      baryonic = m.matched and (m.baryonic + 500 * W.parallel) or 0 }
  end
end
os.sleep = function(seconds) for _ = 1, math.max(1, math.floor(seconds * 20 + 0.5)) do tick() end end

local function startCycle(first, second)
  local m = W.m
  m.running, m.prog, m.maxp = true, 0, 2400
  m.history, m.matched, m.first, m.second, m.baryonic, m.result = {}, false, first, second, 0, nil
end

local function sensorInfo()
  local m, loc, out = W.m, W.locale, {}
  local function add(s) out[#out + 1] = s end
  if loc == "raw" then
    add("GT5U.infodata.purification_unit_base.linked_at\\\\1\\\\2\\\\3")
    if m.maxp > 0 then add("GT5U.infodata.purification_unit_base.success_chance\\\\§e" .. (m.matched and 100 or 0) .. "%§r") end
    add("GT5U.infodata.parallel.current\\\\§e" .. W.parallel)
    add("GT5U.infodata.pubp.catalyst_history")
    for i, k in ipairs(m.history) do add("GT5U.infodata.pubp.catalyst_entry\\\\§e" .. i .. "\\\\§9" .. label[k]) end
    add("GT5U.infodata.pubp.quark_combination\\\\" .. (m.matched and "§aYes" or "§cNo"))
  elseif loc == "en" then
    add("This Purification Unit is linked to the Water Purification Plant at 1, 2, 3.")
    if m.maxp > 0 then add("Success chance: §e" .. (m.matched and 100 or 0) .. "%§r") end
    add("Current Parallel: §e" .. W.parallel)
    add("Catalyst insertion history for this recipe cycle")
    for i, k in ipairs(m.history) do add("§e" .. i .. ": §9" .. label[k]) end
    add("Quark Combination correctly identified: " .. (m.matched and "§aYes" or "§cNo"))
  else
    add("Эта установка очистки связана с заводом по адресу 1, 2, 3.")
    add("История добавления катализаторов за этот цикл рецептов")
    for i, k in ipairs(m.history) do add(i .. ": " .. label[k]) end
    add("Правильно идентифицированая кварковая комбинация: " .. (m.matched and "Yes" or "No"))
  end
  out.n = #out
  return out
end

-- Two transposers share the catalyst bus (one transposer has only 6 sides).
local function transposer(id, sidesMap)
  local p = { address = id }
  local function obj(s) return sidesMap[s] end
  function p.getInventorySize(s) local o = obj(s); return o and o.size or nil end
  function p.getStackInSlot(s, slot)
    local o = obj(s); local st = o and o.size and o.slots[slot]
    if not st then return nil end
    return { name = "gregtech:gt.metaitem.03", damage = st.damage, label = label[keyOf[st.damage]], size = st.size }
  end
  function p.transferItem(from, to, count, slot)
    tick()
    local a, b = obj(from), obj(to)
    local st = a and a.slots[slot]
    if not st or not b then return 0 end
    if to == W.busSide[id] then
      for _, other in pairs(W.bus.slots) do
        if other then W.violation = "second catalyst arrived before previous was consumed" end
      end
    end
    local n = math.min(count, st.size)
    local target
    for j = 1, b.size do local d = b.slots[j]; if d and d.damage == st.damage then target = j; break end end
    if not target then for j = 1, b.size do if not b.slots[j] then target = j; break end end end
    if not target then return 0 end
    local d = b.slots[target] or { damage = st.damage, size = 0 }
    d.size, st.size = d.size + n, st.size - n
    b.slots[target] = d
    if st.size == 0 then a.slots[slot] = nil end
    return n
  end
  function p.getTankCount(s) local o = obj(s); return (o and o.capacity) and 1 or 0 end
  function p.getFluidInTank(s)
    local o = obj(s)
    if not o or not o.capacity then return { n = 0 } end
    return { { name = o.amount > 0 and "molten.infinity" or nil, amount = o.amount, capacity = o.capacity }, n = 1 }
  end
  function p.transferFluid(from, to, count)
    tick()
    local a, b = obj(from), obj(to)
    if not a or not b or not a.capacity or not b.capacity or a.amount <= 0 then return false, "empty" end
    local n = math.min(count, a.amount, b.capacity - b.amount, 16000)
    a.amount, b.amount = a.amount - n, b.amount + n
    return true, n
  end
  return p
end

local function scenario(first, second, o)
  o = o or {}
  W = { t = 0, parallel = o.parallel or 1, locale = o.locale or "raw", infinityUsed = 0,
    m = { running = false, prog = 0, maxp = 0, history = {}, disabled = false },
    bus = inv(4), busSide = { tA = 1, tB = 1 } }
  W.hatch = { amount = o.hatch or 6048, capacity = o.hatchCap or 64000 }
  local src = {}
  for _, k in ipairs(names) do
    src[k] = inv(1)
    local n = o.stock and o.stock[k] or 3
    if n > 0 then src[k].slots[1] = { damage = damage[k], size = n } end
  end
  local tA = transposer("tA", { [2] = src.up, [3] = src.down, [4] = src.strange, [5] = src.charm, [1] = W.bus })
  local infSrc = { amount = o.infSource or 0, capacity = 16000 }
  local tB = transposer("tB", { [2] = src.bottom, [3] = src.top, [1] = W.bus, [4] = infSrc, [5] = W.hatch })
  W.src, W.infSrc = src, infSrc
  local routes = {}
  for i, k in ipairs(names) do
    local onA = i <= 4
    routes[k] = { proxy = onA and tA or tB, from = onA and (i + 1) or (i - 3), to = 1, slot = 1 }
  end
  if o.stale then W.bus.slots[1] = { damage = damage[o.stale], size = 1 } end
  local machine = {
    getWorkProgress = function() return W.m.prog end,
    getWorkMaxProgress = function() return W.m.maxp end,
    getSensorInformation = sensorInfo,
    setWorkAllowed = function(v) W.m.disabled = not v; return true end, -- current cycle continues
  }
  local cfg = { pollInterval = 0.25, consumeTimeout = 5, refillWait = 3 }
  local core = require("waterline.core")
  if o.infRoute then
    W.proxies = { tB = tB }
    routes.infinity = core.fluidRoute("infinity", { transposer = "tB", from = 4, to = 5, fluid = "molten.infinity" }, false)
  end
  if o.meNet then
    -- ME stocking hatch: the network stock is what the hatch can drain
    cfg.meObj = { address = "me", at = 1e9, map = setmetatable({}, { __index = function(_, k)
      if k == "molten.infinity" then return W.hatch.amount end end }) }
  end
  return machine, routes, cfg
end

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

local logs
local function run(first, second, o)
  local machine, routes, cfg = scenario(first, second, o)
  logs = {}
  package.loaded["waterline.g8"] = nil
  g8 = require("waterline.g8")
  local realPrint = print
  print = function(...) logs[#logs + 1] = table.concat({ ... }, " ") end
  startCycle(first, second)
  os.sleep(0.05)
  local ok = g8.runCycle(machine, routes, cfg, 1)
  -- let the cycle finish
  local guard = 0
  while W.m.running and guard < 3000 do tick(); guard = guard + 1 end
  print = realPrint
  return ok, W
end
local function hasLog(pattern) for _, l in ipairs(logs) do if l:find(pattern) then return true end end return false end

local chosenA, chosenB = arg[1], arg[2]
local parallel = tonumber(arg[3] or 1)
if (chosenA and not chosenB) or (chosenB and not chosenA) then error("use two keys, e.g. lua test/g8_sim.lua up down") end
print("pair                 in  Infinity L  returned  G8 L  baryonic L")
print("----------------------------------------------------------------")
local successes, worst, idx = 0, 0, 0
for i = 1, #names do
  for j = i + 1, #names do
    local a, b = names[i], names[j]
    if not chosenA or (a == chosenA and b == chosenB) or (a == chosenB and b == chosenA) then
      idx = idx + 1
      local locale = ({ "raw", "en", "ru" })[idx % 3 + 1]
      local ok, w = run(a, b, { locale = locale, parallel = parallel })
      assert(ok and w.m.result and w.m.result.success, a .. "+" .. b .. " (" .. locale .. ") not found")
      assert(not w.violation, w.violation or "")
      local r = w.m.result
      assert(r.returned == r.inserted - 2 and r.water == 900 * parallel and r.baryonic == 2000 + 500 * parallel)
      local total, rep = 0, {}
      for _, k in ipairs(w.m.history) do total = total + 144 * 2 ^ (rep[k] or 0); rep[k] = (rep[k] or 0) + 1 end
      assert(w.infinityUsed == total, "wrong Infinity cost")
      successes, worst = successes + 1, math.max(worst, w.infinityUsed)
      print(string.format("%-20s %2d %11d %9d %5d %11d", a .. "+" .. b .. " " .. locale, r.inserted,
        w.infinityUsed, r.returned, r.water, r.baryonic))
    end
  end
end
assert(successes > 0)
if not chosenA then
  local ok, w
  -- 1. Infinity runs out, nothing can see it: the machine stops, catalysts are lost, bus is cleaned up
  ok, w = run("charm", "top", { hatch = 700 })
  assert(not ok and w.m.stopped and w.m.disabled, "shortage must stop the machine in this setup")
  assert(next(w.bus.slots) == nil, "catalyst left in the bus after stopMachine")
  assert(hasLog("остановилась"), "stopMachine was not reported")
  -- 2. Same shortage but ME shows the stock: insertion stops in time, cycle ends normally, nothing lost
  ok, w = run("charm", "top", { hatch = 700, meNet = 700 })
  assert(not ok and not w.m.stopped and w.m.result and w.m.result.returned == w.m.result.inserted,
    "ME pre-check must prevent stopMachine and return every catalyst")
  -- 3. Infinity route: empty hatch is topped up from a Dual Interface, full search succeeds
  ok, w = run("charm", "top", { hatch = 0, hatchCap = 8000, infSource = 16000, infRoute = true })
  assert(ok and not w.m.stopped and w.m.result.success, "infinity route did not top up the hatch")
  -- 4. Infinity route with too little Infinity: refuses before inserting, nothing lost
  ok, w = run("charm", "top", { hatch = 0, infSource = 1000, infRoute = true })
  assert(not ok and not w.m.stopped and w.m.result.returned == w.m.result.inserted, "route shortage")
  -- 5. A stale catalyst left in the bus is returned before the cycle starts
  ok, w = run("up", "down", { stale = "top" })
  assert(ok and w.m.result.success and w.m.history[1] == g8.order[1], "stale catalyst polluted the history")
  assert(hasLog("возвращены"), "stale catalyst return was not logged")
  -- 6. Empty catalyst source: controller pauses the machine, the cycle still ends and returns catalysts
  ok, w = run("up", "down", { stock = { bottom = 0 } })
  assert(not ok and w.m.disabled and not w.m.stopped and w.m.result.returned == w.m.result.inserted,
    "empty source must pause without losing catalysts")
  -- 7. Dual Interface refill: source with 1 item refilled every 10 ticks is enough
  local refillStock = { up = 1, down = 1, strange = 1, charm = 1, bottom = 1, top = 1 }
  ok, w = (function()
    local machine, routes, cfg = scenario("charm", "top", { stock = refillStock })
    W.refill = function()
      for _, k in ipairs(names) do if not W.src[k].slots[1] then W.src[k].slots[1] = { damage = damage[k], size = 1 } end end
    end
    logs = {}
    local realPrint = print
    print = function(...) logs[#logs + 1] = table.concat({ ... }, " ") end
    startCycle("charm", "top"); os.sleep(0.05)
    local r = g8.runCycle(machine, routes, cfg, 1)
    print = realPrint
    return r, W
  end)()
  assert(ok and not w.m.disabled, "momentarily empty Dual Interface must not pause the machine")
  print("OK: shortage (stop / ME / route), stale bus, empty source, Dual Interface refill")
end
print(string.format("OK: %d pair(s), worst Infinity %d L", successes, worst))
-- END test/g8_sim.lua
