-- Симуляция Degasser по MTEPurificationUnitDegasser.java + моки OC API.
-- usage: texlua sim.lua <program.lua> <scenario> <cycles> <seed>
local PROG, SCEN, NCYC, SEED = arg[1], arg[2] or "normal", tonumber(arg[3] or 300), tonumber(arg[4] or 1)
math.randomseed(SEED)

local SIDES = { [0]="down","up","north","south","west","east", down=0, up=1, north=2, south=3, west=4, east=5 }

---------------------------------------------------------------- world
local T = 0
local CYCLE = 2400
local GAP = 20 -- тиков простоя между циклами (контроллер плана)

local FL = { coolant="supercoolant", helium="helium", neon="neon", krypton="krypton", xenon="xenon",
             superconductor=(SCEN == "uv284") and "molten.longasssuperconductornameforuvwire"
               or (SCEN == "uhv284") and "molten.longasssuperconductornameforuhvwire"
               or "molten.superconductoruevbase",
             neutronium="molten.neutronium" }
local REQ = { [FL.coolant]=10000, [FL.helium]=10000, [FL.neon]=7500, [FL.krypton]=5000, [FL.xenon]=2500,
              [FL.superconductor]=1440, [FL.neutronium]=4608 }
local GAS = { FL.helium, FL.neon, FL.krypton, FL.xenon }

local function tank(name, amount, cap) return { name=name, amount=amount, capacity=cap } end
local HATCH_CAP = (SCEN == "smallhatch") and 2000 or 8000
-- два transposer'а, у каждого хэтч сверху
local hatchA = tank(nil, 0, HATCH_CAP)
local hatchB = tank(nil, 0, HATCH_CAP)
local water  = tank("purifiedwatergrade6", 64000, 64000) -- невалидная жидкость в машине не трогается
local bufAmt = (SCEN == "lowstock") and 9000 or 10^9
local buffers = {
  A = { [SIDES.north]=tank(FL.coolant, bufAmt, 10^9), [SIDES.south]=tank(FL.helium, bufAmt, 10^9),
        [SIDES.east]=tank(FL.neon, bufAmt, 10^9), [SIDES.west]=tank(FL.krypton, bufAmt, 10^9) },
  B = { [SIDES.north]=tank(FL.xenon, bufAmt, 10^9), [SIDES.south]=tank(FL.superconductor, bufAmt, 10^9),
        [SIDES.east]=tank(FL.neutronium, (SCEN=="lowstock") and 9300 or bufAmt, 10^9) },
}
if SCEN == "lowstock" then buffers.B[SIDES.east].amount = 9300 end -- хватит на 2 подачи нейтрония

-- Режим ME Dual Interface: источники ёмкостью 8000 L, AE доливает их из сети каждые 5 тиков.
local IFACE = SCEN:sub(1, 5) == "iface"
local net = {}
if IFACE then
  for _, side in pairs(buffers) do
    for _, t in pairs(side) do t.capacity = 8000; t.amount = 8000; net[t.name] = 10^8 end
  end
  if SCEN:find("dry") then net[FL.neutronium] = 6000 end -- сеть кончится через пару подач
end
local function aeRefill()
  for _, side in pairs(buffers) do
    for _, t in pairs(side) do
      local want = t.capacity - t.amount
      local give = math.min(want, net[t.name] or 0, 4000)
      if give > 0 then t.amount = t.amount + give; net[t.name] = net[t.name] - give end
    end
  end
end

local mach = { running=false, prog=0, maxp=0, idle=5, sig=0, inserted={}, res={ok=0, fail=0}, cycles=0,
               failsWithSig={} }

local function randomize()
  local s = math.random(0, 7)
  if math.random(0, 4) == 0 then s = s + 8 end
  return s
end
local function bit(s, n) return (s >> n) & 1 == 1 end

local function evaluate()
  local s, ins = mach.sig, mach.inserted
  local function exact(name) return ins[name] == REQ[name] end
  if s == 0 then
    local ok = exact(FL.coolant)
    for k in pairs(ins) do if k ~= FL.coolant then ok = false end end
    return ok
  end
  if bit(s, 3) then return next(ins) == nil end
  local need = {}
  if bit(s, 0) then need[GAS[((s >> 1) & 3) + 1]] = true end
  if bit(s, 1) then need[FL.superconductor] = true end
  if bit(s, 2) then need[FL.neutronium] = true end
  for k in pairs(need) do if not exact(k) then return false end end
  for k in pairs(ins) do if not need[k] then return false end end
  return true
end

local valid = {}
for _, n in pairs(FL) do valid[n] = true end

local function worldTick()
  T = T + 1
  if IFACE and T % 5 == 0 then aeRefill() end
  if mach.running then
    mach.prog = mach.prog + 1
    if T % 20 == 0 then
      for _, h in ipairs({ hatchA, hatchB }) do
        if h.name and valid[h.name] and h.amount > 0 then
          mach.inserted[h.name] = (mach.inserted[h.name] or 0) + h.amount
          h.amount = 0; h.name = nil
        end
      end
    end
    if mach.prog >= mach.maxp then
      local ok = evaluate()
      if mach.cycles > mach.skipFirst then
        if ok then mach.res.ok = mach.res.ok + 1 else
          mach.res.fail = mach.res.fail + 1
          mach.failsWithSig[#mach.failsWithSig + 1] = mach.sig
        end
      end
      mach.running = false; mach.prog = 0; mach.maxp = 0; mach.idle = GAP
    end
  else
    mach.idle = mach.idle - 1
    if mach.idle <= 0 then
      mach.cycles = mach.cycles + 1
      if mach.cycles > NCYC then error("interrupted", 0) end
      mach.running = true; mach.prog = 0; mach.maxp = CYCLE
      mach.sig = randomize(); mach.inserted = {}
    end
  end
  -- лёгкий шум: буферы пополняются AE (кроме lowstock)
end
mach.skipFirst = 0
if SCEN == "midstart" then
  -- программа стартует посреди цикла: первый цикл засчитывать нельзя
  mach.running = true; mach.prog = 1000; mach.maxp = CYCLE; mach.sig = 3; mach.cycles = 1; mach.skipFirst = 1
end

local timers = {}
local inTimer = false
local SNAP_AT = { cycle = 6, prog = 400 }
local snapshots = {}
local takeSnapshot -- defined later
local function advance(sec)
  local n = math.max(1, math.floor(sec * 20 + 0.5))
  for _ = 1, n do
    worldTick()
    if not inTimer then
      for _, tm in pairs(timers) do
        if T >= tm.next then
          tm.next = T + tm.every; inTimer = true
          local ok, e = pcall(tm.fn); inTimer = false
          if not ok then error(e, 0) end
        end
      end
    end
    if takeSnapshot and mach.cycles == SNAP_AT.cycle and mach.prog == SNAP_AT.prog then takeSnapshot("mid") end
    if takeSnapshot and mach.cycles == SNAP_AT.cycle + 3 and mach.prog == 2370 then takeSnapshot("late") end
  end
end

---------------------------------------------------------------- OC mocks
local function hatchOf(tp) return tp == "A" and hatchA or hatchB end
local function sideTank(tp, side)
  if side == SIDES.up then return hatchOf(tp) end
  return buffers[tp][side]
end
local function fluidTable(t)
  if not t then return { n = 0 } end
  if t.name and t.amount > 0 then return { { name=t.name, amount=t.amount, capacity=t.capacity, label=t.name }, n=1 } end
  return { { amount=0, capacity=t.capacity }, n=1 }
end
local function canFill(dst, name)
  if dst == hatchA or dst == hatchB then return dst.name == nil or dst.name == name end
  return dst.name == name or dst.name == nil
end
local function mkTransposer(id)
  return {
    address = id .. "-0000-transposer",
    type = "transposer",
    getTankCount = function(side) return sideTank(id, side) and 1 or 0 end,
    getFluidInTank = function(side) return fluidTable(sideTank(id, side)) end,
    transferFluid = function(from, to, count)
      worldTick() -- вызов стоит тик
      local s, d = sideTank(id, from), sideTank(id, to)
      if not s or not d then return false, "no tank" end
      if not s.name or s.amount <= 0 then return false, "empty" end
      if not canFill(d, s.name) then return true, 0 end
      local room = d.capacity - d.amount
      local mv = math.min(count, s.amount, room, 2048) -- лимит тира transposer'а за вызов
      if mv <= 0 then return true, 0 end
      s.amount = s.amount - mv; if s.amount == 0 and (s == hatchA or s == hatchB) then s.name = nil end
      d.name = s.name or d.name; d.amount = d.amount + mv
      return true, mv
    end,
  }
end
local comps = {
  ["tA-0000-transposer"] = mkTransposer("tA"),
  ["tB-0000-transposer"] = mkTransposer("tB"),
}
-- fix ids used inside sideTank
comps["tA-0000-transposer"] = mkTransposer("A"); comps["tA-0000-transposer"].address = "tA-0000-transposer"
comps["tB-0000-transposer"] = mkTransposer("B"); comps["tB-0000-transposer"].address = "tB-0000-transposer"
comps["gt-0000-machine"] = {
  address = "gt-0000-machine", type = "gt_machine",
  getWorkProgress = function() return mach.prog end,
  getWorkMaxProgress = function() return mach.maxp end,
  isMachineActive = function() return mach.running end,
  getSensorInformation = function()
    if not mach.running then return { "Linked to Purification Plant at 1, 2, 3", "Current parallel: 1,024" } end
    local ch = evaluate() and 100 or 0
    local mult = 1.0
    if bit(mach.sig, 1) and not bit(mach.sig, 3) and mach.inserted[FL.superconductor] == REQ[FL.superconductor] then
      mult = (SCEN == "uv284") and 1.0 or (SCEN == "uhv284") and 1.25 or 1.5
    end
    if SCEN == "rawkeys" then
      return { "GT5U.infodata.purification_unit_base.linked_at 1 2 3",
               "GT5U.infodata.purification_unit_base.success_chance §e" .. ch .. ".0%§r",
               "GT5U.infodata.parallel.current §e1,024",
               "GT5U.infodata.purification_unit_degasser.control_signal §e" .. mach.sig,
               "GT5U.infodata.purification_unit_degasser.output_multiplier §e" .. mult }
    end
    return { "Linked to Purification Plant at 1, 2, 3", "Success chance: §e" .. ch .. "%§r",
             "Current parallel: §e1,024", "Control signal: §e0101", "Output multiplier: §e" .. mult,
             "Bit 1: §aOK", "4608 Molten Neutronium inserted" }
  end,
}
comps["rs-0000-io"] = {
  address = "rs-0000-io", type = "redstone",
  getInput = function(side)
    local t = { [0]=0, 0, 0, 0, 0, 0 }
    t[SIDES.west] = mach.sig -- control hatch к west
    t[SIDES.east] = (SCEN == "noise") and 3 or 0
    if side then return t[side] end
    return t
  end,
}

if IFACE and not SCEN:find("nome") then
  comps["me-0000-iface"] = {
    address = "me-0000-iface", type = "me_interface",
    getFluidsInNetwork = function()
      local l = {}
      for name, amt in pairs(net) do if amt > 0 then l[#l + 1] = { name = name, amount = amt, label = name } end end
      l.n = #l
      return l
    end,
  }
end
local SW, SH = 160, 50
local scr, sbg = {}, {}
local function clearScr() for y = 1, SH do scr[y] = {}; sbg[y] = {} for x = 1, SW do scr[y][x] = " "; sbg[y][x] = 0 end end end
clearScr()
local gbg = 0
local BARCOL = { [0x4FB3FF]=1, [0x3DDC6B]=1, [0xF2C14E]=1, [0xFF5C5C]=1, [0x2E7D4F]=1 }
local gpuCalls = 0
comps["gpu-0000"] = {
  address = "gpu-0000", type = "gpu",
  maxResolution = function() return (SCEN == "t2screen") and 80 or 160, (SCEN == "t2screen") and 25 or 50 end,
  getResolution = function() return 80, 25 end,
  setResolution = function() return true end,
  setForeground = function() gpuCalls = gpuCalls + 1 end,
  setBackground = function(c) gbg = c; gpuCalls = gpuCalls + 1 end,
  set = function(x, y, str)
    gpuCalls = gpuCalls + 1
    assert(y >= 1 and y <= SH, "set y out of range " .. y)
    local i = 0
    for _, cp in utf8.codes(str) do
      local cx = x + i
      if cx >= 1 and cx <= SW then scr[y][cx] = utf8.char(cp); sbg[y][cx] = gbg end
      i = i + 1
    end
    assert(x + i - 1 <= SW, string.format("set overflow x=%d len=%d y=%d: %s", x, i, y, str))
  end,
  fill = function(x, y, w, h, ch)
    gpuCalls = gpuCalls + 1
    for yy = y, y + h - 1 do for xx = x, x + w - 1 do
      assert(xx >= 1 and xx <= SW and yy >= 1 and yy <= SH, "fill out of range")
      scr[yy][xx] = ch; sbg[yy][xx] = gbg
    end end
  end,
}
takeSnapshot = function(tag)
  local f = io.open("snap-" .. SCEN .. "-" .. tag .. ".txt", "w")
  for y = 1, SH do
    local row = {}
    for x = 1, SW do
      local ch = scr[y][x]
      if ch == " " and BARCOL[sbg[y][x]] then ch = "█" elseif ch == " " and sbg[y][x] == 0x2A323C then ch = "░" end
      row[#row + 1] = ch
    end
    f:write(table.concat(row), "\n")
  end
  f:close()
end
package.preload["event"] = function()
  local id = 0
  return {
    timer = function(iv, fn) id = id + 1; timers[id] = { every = math.floor(iv * 20), next = T, fn = fn }; return id end,
    cancel = function(i) timers[i] = nil end,
  }
end
package.preload["unicode"] = function()
  return { len = utf8.len, sub = function(s, i, j)
    local a = utf8.offset(s, i) or #s + 1
    local b = j and ((utf8.offset(s, j + 1) or #s + 1) - 1) or #s
    return s:sub(a, b) end }
end
package.preload["term"] = function() return { setCursor = function() end } end
package.preload["component"] = function()
  local c = {}
  function c.list(ctype)
    local k = nil
    return function()
      repeat k = next(comps, k) until k == nil or comps[k].type == ctype
      return k
    end
  end
  function c.get(addr, ctype)
    for a, p in pairs(comps) do
      if a:sub(1, #addr) == addr and (not ctype or p.type == ctype) then return a end
    end
    return nil, "no such component"
  end
  function c.proxy(a) return comps[a] end
  function c.invoke(a, m, ...) return comps[a][m](...) end
  function c.isAvailable(t) for _, p in pairs(comps) do if p.type == t then return true end end return false end
  c.gpu = comps["gpu-0000"]
  return c
end
package.preload["computer"] = function() return { uptime = function() return T / 20 end } end
package.preload["sides"] = function() return SIDES end
package.preload["filesystem"] = function()
  return {
    exists = function(p) local f = io.open(p) if f then f:close() return true end return false end,
    size = function(p) local f = io.open(p) if not f then return 0 end local s = f:seek("end") f:close() return s end,
    remove = os.remove, rename = os.rename,
  }
end
os.sleep = advance
for _, m in ipairs({ "component", "computer", "sides", "filesystem", "event", "unicode", "term" }) do
  package.loaded[m] = package.preload[m]()
end

local LOG = "sim-" .. SCEN .. ".log"
os.remove(LOG)
local realLoadfile = loadfile
loadfile = function(p)
  if p == "/home/degasser.cfg.lua" then
    return function()
      local sides = SIDES
      return {
        machine = "gt", redstone = "rs", redstoneSide = (SCEN == "noise") and sides.west or nil,
        routes = {
          coolant        = { transposer = "tA", from = sides.north, to = sides.up },
          helium         = { transposer = "tA", from = sides.south, to = sides.up },
          neon           = { transposer = "tA", from = sides.east,  to = sides.up },
          krypton        = { transposer = "tA", from = sides.west,  to = sides.up },
          xenon          = { transposer = "tB", from = sides.north, to = sides.up },
          superconductor = { transposer = "tB", from = sides.south, to = sides.up },
          neutronium     = { transposer = "tB", from = sides.east,  to = sides.up },
        },
        logFile = LOG, logMaxBytes = 10^9, outputPerParallel = 900, ui = (SCEN ~= "noui"),
        refillSources = IFACE,
      }
    end
  end
  return realLoadfile(p)
end

-- глушим вывод программы
local realPrint = print
print = function() end

local chunk = assert(realLoadfile(PROG))
chunk()

print = realPrint
if SCEN == "uv284" or SCEN == "uhv284" then
  local f = assert(io.open(LOG, "r"))
  local events = f:read("*a")
  f:close()
  local tier = (SCEN == "uv284") and "UV" or "UHV"
  assert(events:find("SC base: " .. tier, 1, true), "2.8.4 " .. tier .. " base was not recognized")
end
local evaluated = mach.res.ok + mach.res.fail
local hist = {}
for _, s in ipairs(mach.failsWithSig) do hist[s] = (hist[s] or 0) + 1 end
local ht = {}
for s, c in pairs(hist) do ht[#ht + 1] = s .. ":" .. c end
table.sort(ht)
print("gpu calls", gpuCalls)
print(string.format("[%s] seed=%d циклов оценено %d  успех %d  провал %d  (%.1f%%)  провалы по сигналам {%s}",
  SCEN, SEED, evaluated, mach.res.ok, mach.res.fail, 100 * mach.res.ok / math.max(1, evaluated), table.concat(ht, " ")))
