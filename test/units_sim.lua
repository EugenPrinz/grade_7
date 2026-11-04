-- G1–G6 simulator: unit models follow GT5-Unofficial 5.09.54.265 (GTNH 2.9) sources,
-- the real waterline.g1..g6 modules run through core.main on mocked OpenComputers.
-- usage: lua test/units_sim.lua [grade|all] [cycles] [seed]
local GRADE, NCYC, SEED = arg[1] or "all", tonumber(arg[2] or 25), tonumber(arg[3] or 1)
package.path = "./?.lua;" .. package.path

local SIDES = { [0] = "down", "up", "north", "south", "west", "east",
  down = 0, up = 1, north = 2, south = 3, west = 4, east = 5 }
local CYCLE, GAP, FLUID_PER_CALL = 2400, 20, 16000
local MAX_OZONE = 1024000
local LENSES = { "Orundum Lens", "Amber Lens", "Infused Air Lens", "Emerald Lens", "Mana Diamond Lens",
  "Blue Topaz Lens", "Amethyst Lens", "Fluor-Buergerite Lens", "Dilithium Lens" }

local function fmtChance(c) return string.format("%.1f%%", c) end

---------------------------------------------------------------- world + unit models
local W -- current world

local function newTank(name, amount, cap) return { name = name, amount = amount or 0, capacity = cap } end
local function newInv(size) return { size = size, slots = {} } end

local function drainAll(tank, name)
  if tank.name == name and tank.amount > 0 then
    local a = tank.amount; tank.amount = 0; tank.name = nil; return a
  end
  return 0
end

local Units = {}

Units[1] = function(o)
  return { base = 70 + (o.boost and 15 or 0),
    start = function(u) u.chance = u.base end,
    final = function(u) return u.chance end,
    lines = function(u) return {} end }
end

Units[2] = function(o)
  local hatch = newTank(nil, 0, o.cap or 2048000)
  return { hatch = hatch,
    canStart = function(u)
      if hatch.name == "ozone" and hatch.amount > MAX_OZONE then W.exploded = true end
      return hatch.name == "ozone" and hatch.amount >= 128000
    end,
    start = function(u)
      local tier = 0
      for i, t in ipairs({ 128000, 256000, 512000, 1024000 }) do if hatch.amount >= t then tier = i end end
      hatch.amount = hatch.amount - 1000 * 2 ^ (tier + 6)
      if hatch.amount == 0 then hatch.name = nil end
      u.chance = math.min(100, tier * 20 + (o.boost and 15 or 0))
    end,
    final = function(u) return u.chance end,
    lines = function() return {} end }
end

Units[3] = function(o)
  local hatch = newTank(nil, 0, o.cap or 256000)
  return { hatch = hatch, base = 10 + (o.boost and 15 or 0),
    start = function(u) u.consumed = 0 end,
    second = function(u) u.consumed = u.consumed + drainAll(hatch, "pac") end,
    final = function(u)
      local levels = math.floor(u.consumed / 100000)
      local over = u.consumed - levels * 100000
      local c = math.min(100, u.base + 10 * levels)
      if over > 0 then c = math.max(0, c * 2 ^ (over / 100000 * -10)) end
      return c
    end,
    lines = function(u, raw)
      if raw then return { "GT5U.infodata.purification_unit_flocculation.consumed\\\\Polyaluminium Chloride\\\\§c" .. math.floor(u.consumed or 0) } end
      return { "Polyaluminium Chloride consumed this cycle: §c" .. math.floor(u.consumed or 0) .. "L" }
    end }
end

Units[4] = function(o)
  local bus, acid = newInv(4), newTank(nil, 0, o.cap or 64000)
  local function r2(x) return math.floor(x * 100 + 0.5) / 100 end
  return { bus = bus, hatch = acid,
    start = function(u) u.ph = r2(7 + (math.random(-1000, 999) / 1000) * 2.5) end,
    second = function(u)
      local dust = 0
      for i = bus.size, 1, -1 do
        local st = bus.slots[i]
        if st and st.damage == 2685 then dust = dust + st.size; bus.slots[i] = nil end
      end
      local mult = 0
      if acid.name == "hcl" then mult = math.floor(acid.amount / 10); acid.amount = 0; acid.name = nil end
      u.ph = r2(math.min(14, math.max(0, u.ph + dust * 0.01 - mult * 0.01)))
    end,
    final = function(u) return math.abs(u.ph - 7) <= 0.05 + 1e-9 and 100 or 0 end,
    lines = function(u, raw)
      local v = u.ph == math.floor(u.ph) and string.format("%.1f", u.ph) or tostring(u.ph)
      if raw then return { "GT5U.infodata.purification_unit_ph_adjustment.ph\\\\§e" .. v } end
      return { "Current pH Value: §e" .. v .. " pH" }
    end }
end

Units[5] = function(o)
  local plasma, cool = newTank(nil, 0, o.cap or 16000), newTank(nil, 0, o.cap or 16000)
  return { plasmaHatch = plasma, coolHatch = cool, base = o.boost and 15 or 0,
    start = function(u) u.temp, u.cycles, u.ruined, u.heating = 0, 0, false, true end,
    second = function(u)
      local p = 0
      if plasma.name == "plasma.helium" then p = math.min(10, plasma.amount); plasma.amount = plasma.amount - p
        if plasma.amount == 0 then plasma.name = nil end end
      local c = 0
      if cool.name == "supercoolant" then c = math.min(100, cool.amount); cool.amount = cool.amount - c
        if cool.amount == 0 then cool.name = nil end end
      u.temp = math.max(0, u.temp + p * 100 - c * 5)
      if u.temp > 12500 then u.ruined = true; W.ruined = (W.ruined or 0) + 1 end
      if u.heating then if u.temp >= 10000 then u.heating = false end
      elseif u.temp == 0 then u.heating = true; u.cycles = u.cycles + 1 end
    end,
    final = function(u) if u.ruined then return 0 end return math.min(100, u.cycles * 33 + u.base) end,
    lines = function(u, raw)
      if raw then return { "GT5U.infodata.purification_unit_plasma_heater.temperature\\\\§e" .. (u.temp or 0),
        "GT5U.infodata.purification_unit_plasma_heater.heating_cycles\\\\§e" .. (u.cycles or 0) } end
      return { "Current temperature: §e" .. (u.temp or 0) .. "K", "Heating cycles completed this run: §e" .. (u.cycles or 0) }
    end }
end

Units[6] = function(o)
  local housing = newInv(1)
  return { housing = housing, base = o.boost and 15 or 0,
    start = function(u) u.idx, u.timer, u.swaps, u.early = 1, 0, 0, false end,
    tick = function(u)
      local cur = housing.slots[1]
      local want = LENSES[u.idx]
      if u.timer > 0 then
        u.timer = u.timer - 1
        if not cur or cur.label ~= want then u.early = true end
        if u.timer == 0 then
          if u.idx < #LENSES then u.idx = u.idx + 1 else u.timer = CYCLE + 1 end
        end
      elseif cur and cur.label == want then
        u.swaps = u.swaps + 1
        u.timer = math.random(75, 299)
      end
    end,
    final = function(u) if u.early then return 0 end return math.min(100, u.swaps * 10 + u.base) end,
    lines = function(u, raw)
      local want = LENSES[u.idx or 1]
      local out
      if raw then out = { "GT5U.infodata.purification_unit_uv_treatment.lens_swaps\\\\§e" .. (u.swaps or 0),
        "GT5U.infodata.purification_unit_uv_treatment.lens_requested\\\\§a" .. want }
      else out = { "Lens swaps performed this run:", "Current lens requested: §a" .. want } end
      if u.early then out[#out + 1] = raw and "GT5U.infodata.purification_unit_uv_treatment.removed_too_early"
        or "Removed lens too early. Failing this recipe." end
      return out
    end }
end

---------------------------------------------------------------- OC mocks
local function tick()
  W.t = W.t + 1
  -- Dual Interface sources: AE tops tanks up by 4000 L every 5 ticks, item slot 1 to 64 every second
  if W.iface then
    if W.t % 5 == 0 then
      for _, src in ipairs(W.iface.tanks) do
        src.tank.name = src.name
        src.tank.amount = math.min(src.tank.capacity, src.tank.amount + 4000)
      end
    end
    if W.t % 20 == 0 then
      for _, src in ipairs(W.iface.items) do
        local st = src.inv.slots[1] or { name = src.name, damage = src.damage, label = src.label, size = 0 }
        st.size = 64; src.inv.slots[1] = st
      end
    end
  end
  local m, u = W.m, W.unit
  if m.running then
    m.prog = m.prog + 1
    if u.tick then u:tick() end
    if W.t % 20 == 0 and u.second then u:second() end
    if m.prog >= m.maxp then
      local c = u:final()
      if u.early then W.early = (W.early or 0) + 1 end
      W.results[#W.results + 1] = c
      m.running, m.prog, m.maxp, m.idle = false, 0, 0, GAP
    end
  else
    m.idle = m.idle - 1
    if m.idle <= 0 then
      W.cycles = W.cycles + 1
      if not u.canStart or u:canStart() then
        m.running, m.prog, m.maxp = true, 0, CYCLE
        u:start()
      else
        W.results[#W.results + 1] = "idle"
        m.idle = CYCLE + GAP
      end
    end
  end
end
local function advance(sec) for _ = 1, math.max(1, math.floor(sec * 20 + 0.5)) do tick() end end

local function sideObj(tp, side) return W.sides[tp] and W.sides[tp][side] end
local function fluidInfo(t)
  if not t or t.size then return { n = 0 } end
  if t.name and t.amount > 0 then return { { name = t.name, amount = t.amount, capacity = t.capacity }, n = 1 } end
  return { { amount = 0, capacity = t.capacity }, n = 1 }
end
local function mkTransposer(id)
  return { address = id .. "-transposer", type = "transposer",
    getTankCount = function(s) local o = sideObj(id, s); return (o and not o.size) and 1 or 0 end,
    getFluidInTank = function(s) return fluidInfo(sideObj(id, s)) end,
    getInventorySize = function(s) local o = sideObj(id, s); return o and o.size or nil end,
    getStackInSlot = function(s, slot)
      local o = sideObj(id, s); local st = o and o.size and o.slots[slot]
      if not st then return nil end
      return { name = st.name, damage = st.damage, label = st.label, size = st.size, maxSize = 64 }
    end,
    transferFluid = function(from, to, count)
      tick(); W.calls = W.calls + 1
      local a, b = sideObj(id, from), sideObj(id, to)
      if not a or not b or a.size or b.size then return false, "no tank" end
      if not a.name or a.amount <= 0 then return false, "empty" end
      if b.name and b.name ~= a.name then return true, 0 end
      local mv = math.min(count, a.amount, b.capacity - b.amount, FLUID_PER_CALL)
      if mv <= 0 then return true, 0 end
      local name = a.name
      a.amount = a.amount - mv; if a.amount == 0 and a.capacity < 10 ^ 8 then a.name = nil end
      b.name, b.amount = name, b.amount + mv
      return true, mv
    end,
    transferItem = function(from, to, count, fromSlot)
      tick(); W.calls = W.calls + 1
      local a, b = sideObj(id, from), sideObj(id, to)
      if not a or not b or not a.size or not b.size then return 0 end
      local moved = 0
      local list = fromSlot and { fromSlot } or {}
      if not fromSlot then for i = 1, a.size do list[#list + 1] = i end end
      for _, si in ipairs(list) do
        local st = a.slots[si]
        while st and moved < count and st.size > 0 do
          local target
          for j = 1, b.size do
            local d = b.slots[j]
            if d and d.name == st.name and d.damage == st.damage and d.label == st.label and d.size < 64 then target = j; break end
          end
          if not target then for j = 1, b.size do if not b.slots[j] then target = j; break end end end
          if not target then break end
          local d = b.slots[target] or { name = st.name, damage = st.damage, label = st.label, size = 0 }
          local n = math.min(count - moved, st.size, 64 - d.size)
          d.size, st.size, moved = d.size + n, st.size - n, moved + n
          b.slots[target] = d
          if st.size == 0 then a.slots[si] = nil; st = nil end
        end
        if moved >= count then break end
      end
      return moved
    end }
end

local function sensorLines()
  local u, raw = W.unit, W.raw
  local out = { raw and "GT5U.infodata.purification_unit_base.linked_at\\\\1\\\\2\\\\3"
    or "This Purification Unit is linked to the Water Purification Plant at 1, 2, 3." }
  if W.m.running then
    local c = u.chance or (u.final and u:final()) or 0
    out[#out + 1] = raw and ("GT5U.infodata.purification_unit_base.success_chance\\\\§e" .. fmtChance(c) .. "§r")
      or ("Success chance: §e" .. fmtChance(c) .. "§r")
  end
  out[#out + 1] = raw and "GT5U.infodata.parallel.current\\\\§e1,024" or "Current Parallel: §e1,024"
  if W.m.running then for _, l in ipairs(u:lines(raw)) do out[#out + 1] = l end end
  out.n = #out
  return out
end

local comps = {}
local function install()
  comps = {
    ["gt-machine"] = { address = "gt-machine", type = "gt_machine",
      getWorkProgress = function() return W.m.prog end,
      getWorkMaxProgress = function() return W.m.maxp end,
      getSensorInformation = function() return sensorLines() end,
      setWorkAllowed = function(v) W.workAllowed = v; return true end },
    ["tA-transposer"] = mkTransposer("tA"),
    ["tB-transposer"] = mkTransposer("tB"),
  }
end
package.loaded.component = {
  list = function(t)
    local k
    return function() repeat k = next(comps, k) until k == nil or comps[k].type == t; return k end
  end,
  get = function(a, t) for addr, p in pairs(comps) do if addr:sub(1, #a) == a and (not t or p.type == t) then return addr end end end,
  proxy = function(a) return comps[a] end,
  invoke = function(a, m, ...) return comps[a][m](...) end,
  isAvailable = function() return false end,
}
package.loaded.computer = { uptime = function() return W.t / 20 end }
package.loaded.sides = SIDES
package.loaded.event = { pull = function() end }
package.loaded.unicode = { sub = function(s, i, j) return s:sub(i, j) end, len = function(s) return #s end }
package.loaded.filesystem = { exists = function(p) return p:find("bindings", 1, true) ~= nil end }
os.sleep = advance

---------------------------------------------------------------- scenarios
local function chest(name, damage, label, total, size)
  local inv = newInv(size or 27)
  local i = 1
  while total > 0 do
    local n = math.min(64, total)
    inv.slots[i] = { name = name, damage = damage, label = label, size = n }
    total, i = total - n, i + 1
  end
  return inv
end

local function setup(grade, o)
  W = { t = 0, cycles = 0, calls = 0, results = {}, raw = o.raw, logs = {},
    m = { running = false, prog = 0, maxp = 0, idle = 5 } }
  W.unit = Units[grade](o)
  local u = W.unit
  W.sides = { tA = {}, tB = {} }
  local routes = {}
  local big = 10 ^ 9
  local function src(name)
    if not o.iface then return newTank(name, big, big) end
    local t = newTank(name, 16000, 16000)
    W.iface = W.iface or { tanks = {}, items = {} }
    table.insert(W.iface.tanks, { tank = t, name = name })
    return t
  end
  if grade == 2 then
    W.sides.tA[SIDES.north] = src("ozone"); W.sides.tA[SIDES.up] = u.hatch
    routes.ozone = { transposer = "tA", from = SIDES.north, to = SIDES.up }
  elseif grade == 3 then
    W.sides.tA[SIDES.north] = src("pac"); W.sides.tA[SIDES.up] = u.hatch
    routes.pac = { transposer = "tA", from = SIDES.north, to = SIDES.up }
  elseif grade == 4 then
    if o.iface then
      local inv = newInv(9)
      W.sides.tA[SIDES.north] = inv
      W.iface = W.iface or { tanks = {}, items = {} }
      table.insert(W.iface.items, { inv = inv, name = "gt.metaitem.01", damage = 2685, label = "Sodium Hydroxide Dust" })
    else
      W.sides.tA[SIDES.north] = chest("gt.metaitem.01", 2685, "Sodium Hydroxide Dust", o.dust or 64 * 100, 120)
    end
    W.sides.tA[SIDES.west] = chest("gt.metaitem.01", 2000, "Other Dust", 64, 1)
    W.sides.tA[SIDES.up] = u.bus
    W.sides.tA[SIDES.south] = src("hcl"); W.sides.tA[SIDES.east] = u.hatch
    routes.naoh = { transposer = "tA", from = SIDES.north, to = SIDES.up,
      item = { name = "gt.metaitem.01", damage = 2685, label = "Sodium Hydroxide Dust" } }
    routes.hcl = { transposer = "tA", from = SIDES.south, to = SIDES.east }
  elseif grade == 5 then
    W.sides.tA[SIDES.north] = src("plasma.helium"); W.sides.tA[SIDES.up] = u.plasmaHatch
    W.sides.tB[SIDES.north] = src("supercoolant"); W.sides.tB[SIDES.up] = u.coolHatch
    routes.plasma = { transposer = "tA", from = SIDES.north, to = SIDES.up }
    routes.coolant = { transposer = "tB", from = SIDES.north, to = SIDES.up }
  elseif grade == 6 then
    local c = newInv(27)
    local order = {}
    for i = 1, #LENSES do order[i] = i end
    for i = #order, 2, -1 do local j = math.random(i); order[i], order[j] = order[j], order[i] end
    for slot, i in ipairs(order) do c.slots[slot + 3] = { name = "lens" .. i, damage = i, label = LENSES[i], size = 1 } end
    if o.missing then for s, st in pairs(c.slots) do if st.label == o.missing then c.slots[s] = nil end end end
    W.sides.tA[SIDES.north] = c; W.sides.tA[SIDES.up] = u.housing
    routes.lens = { transposer = "tA", from = SIDES.north, to = SIDES.up }
  end
  install()
  return routes
end

local function run(grade, o)
  for k in pairs(package.loaded) do if k:match("^waterline%.") then package.loaded[k] = nil end end
  local routes = setup(grade, o)
  local realLoadfile = loadfile
  loadfile = function(p)
    if p == "/home/waterline.cfg.lua" then return function() return { grades = { ["g" .. grade] = o.cfg or {} } } end end
    if p:find("/home/waterline%.g%d%.bindings%.lua") then
      return function() return { machine = "gt-machine", routes = routes } end
    end
    return realLoadfile(p)
  end
  local mod = require("waterline.g" .. grade)
  local ok, err = pcall(mod.main, {}, {
    shouldStop = function() return W.cycles > NCYC end,
    onLog = function(level, msg) W.logs[#W.logs + 1] = level .. " " .. msg end,
  })
  loadfile = realLoadfile
  if not ok then error("g" .. grade .. ": " .. tostring(err), 0) end
  return W
end

---------------------------------------------------------------- checks
local failures = 0
local function report(name, w, expect, opts)
  opts = opts or {}
  local counted, good, sum, idle = 0, 0, 0, 0
  for i, c in ipairs(w.results) do
    if c == "idle" then idle = idle + 1
    elseif i > (opts.skip or 1) then
      counted = counted + 1
      sum = sum + c
      if c >= expect - 1e-6 then good = good + 1 end
    end
  end
  local errs = 0
  for _, l in ipairs(w.logs) do if l:match("^ERR") then errs = errs + 1 end end
  local pass = counted > 0 and good == counted and not w.exploded and (w.ruined or 0) == 0 and (w.early or 0) == 0
    and (opts.errors == nil or errs <= opts.errors)
  if opts.expectFail then pass = not pass end
  if not pass then failures = failures + 1 end
  print(string.format("%-4s %-24s циклов %3d  ≥%5.1f%%: %3d  средний %5.1f%%  idle %d  ERR %d  вызовов %d",
    pass and "ok" or "FAIL", name, counted, expect, good, counted > 0 and sum / counted or 0, idle, errs, w.calls))
  if not pass and not opts.expectFail then
    for i = math.max(1, #w.logs - 6), #w.logs do print("      " .. w.logs[i]) end
  end
end

math.randomseed(SEED)
local want = GRADE == "all" and nil or tonumber((GRADE:gsub("^g", "")))
local function on(g) return not want or want == g end

if on(1) then
  report("g1 raw", run(1, { raw = true }), 70)
  report("g1 en boost", run(1, { boost = true }), 85)
end
if on(2) then
  report("g2 raw 1024k", run(2, { raw = true }), 80, { skip = 2 })
  report("g2 en boost", run(2, { boost = true }), 95, { skip = 2 })
  report("g2 hatch 600k → 512k", run(2, { raw = true, cap = 600000 }), 60, { skip = 2 })
  local w = run(2, { raw = true, cfg = { ozoneTarget = 256000 } })
  report("g2 target 256k", w, 40, { skip = 2 })
  report("g2 Dual Interface 16k", run(2, { raw = true, iface = true }), 80, { skip = 2 })
end
if on(3) then
  report("g3 raw 900k", run(3, { raw = true }), 100)
  report("g3 en boost 800k", run(3, { boost = true }), 100)
  report("g3 small hatch 32k", run(3, { raw = true, cap = 32000 }), 100)
  report("g3 Dual Interface 16k", run(3, { raw = true, iface = true }), 100)
end
if on(4) then
  report("g4 raw", run(4, { raw = true }), 100)
  report("g4 en", run(4, {}), 100)
  report("g4 acid hatch 1000", run(4, { raw = true, cap = 1000 }), 100)
  report("g4 Dual Interface 64 пыли", run(4, { raw = true, iface = true }), 100)
  -- source runs dry mid-run: cycles needing NaOH fail, but nothing is dosed blindly
  local w = run(4, { raw = true, dust = 300 })
  report("g4 NaOH кончается", w, 100, { expectFail = true })
end
if on(5) then
  report("g5 raw (3 цикла)", run(5, { raw = true }), 99)
  report("g5 en boost", run(5, { boost = true }), 100)
  report("g5 hatch 1000 L", run(5, { raw = true, cap = 1000 }), 99)
  report("g5 Dual Interface 16k", run(5, { raw = true, iface = true }), 99)
end
if on(6) then
  report("g6 raw", run(6, { raw = true }), 90)
  report("g6 en boost", run(6, { boost = true }), 100)
  local w = run(6, { raw = true, missing = "Emerald Lens" })
  report("g6 нет Emerald (ожид. 30%)", w, 30)
end

print(failures == 0 and "ALL OK" or (failures .. " FAILED"))
if failures > 0 then os.exit(1) end
