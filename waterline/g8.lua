-- Grade 8 Absolute Baryonic Perfection controller for GTNH 2.9.
local component = require("component")
local computer = require("computer")
local fs = require("filesystem")
local sides = require("sides")
local bindings = require("waterline.bindings")
local core = require("waterline.core")

local M = {}
local VERSION = "2.1.0"
local INFINITY = "molten.infinity"
local INGOT = 144
local CFG_PATH = "/home/grade8.cfg.lua"
local BIND_PATH = "/home/grade8.bindings.lua"
local logSink
local KEYS = { "up", "down", "strange", "charm", "bottom", "top" }
local META = { up = 32235, down = 32236, strange = 32237, charm = 32238, bottom = 32239, top = 32240 }
local LABELS = {
  up = "Up-Quark Releasing Catalyst", down = "Down-Quark Releasing Catalyst",
  strange = "Strange-Quark Releasing Catalyst", charm = "Charm-Quark Releasing Catalyst",
  bottom = "Bottom-Quark Releasing Catalyst", top = "Top-Quark Releasing Catalyst",
}
local BIND_LABELS = {}
for key, label in pairs(LABELS) do BIND_LABELS[key] = { label = label, damage = META[key] } end
local ROLES = {}
for _, key in ipairs(KEYS) do
  ROLES[#ROLES + 1] = { id = key, kind = "item", slot = "fixed", label = key, expect = BIND_LABELS[key] }
end
-- Optional: transposer between a Dual Interface with Molten Infinity and the Infinity input hatch.
ROLES[#ROLES + 1] = { id = "infinity", kind = "fluid", optional = true, label = "infinity (необяз.)" }
M.stats = { ok = 0, fail = 0 }
-- Euler trail of K6 with two repeated edges. All 15 unordered pairs occur,
-- and each catalyst appears exactly three times. Stop as soon as the machine says Yes.
local ORDER = { "bottom", "up", "down", "strange", "up", "charm", "down", "bottom",
  "strange", "charm", "bottom", "top", "up", "down", "top", "strange", "charm", "top" }
M.order = ORDER

local function int(n) return math.floor(tonumber(n) or 0) end
local function log(level, fmt, ...)
  local message = string.format(fmt, ...)
  if logSink then logSink(level, message)
  else print(string.format("[%s] %-4s %s", os.date("%H:%M:%S"), level, message)) end
end
local function resolve(addr, t)
  if not addr then
    local found
    for a in component.list(t, true) do
      if found then error("несколько " .. t .. "; назначь адрес через grade8 bind", 0) end
      found = a
    end
    addr = found
  end
  local full = addr and component.get(addr, t)
  if not full then error("не найден " .. t .. " " .. tostring(addr) .. "; запусти grade8 bind", 0) end
  return component.proxy(full)
end
local function machineState(machine)
  local ok1, prog = pcall(machine.getWorkProgress)
  local ok2, maxp = pcall(machine.getWorkMaxProgress)
  if not ok1 or not ok2 then return nil end
  return int(prog), int(maxp)
end
local function sensor(machine)
  local ok, info = pcall(machine.getSensorInformation)
  if not ok or type(info) ~= "table" then return nil, "нет данных сенсора" end
  local history, count, match = false, 0, nil
  for i = 1, (info.n or #info) do
    local raw = tostring(info[i] or ""):gsub("§.", "")
    local line = core.lower(raw)
    if line:find("catalyst_history", 1, true)
      or line:find("catalyst insertion history", 1, true)
      or line:find("история добавления катализаторов", 1, true)
      or raw:find("История добавления катализаторов", 1, true) then
      history = true
    elseif line:find("quark_combination", 1, true)
      or line:find("combination correctly", 1, true)
      or line:find("кварковая комбинация", 1, true) then
      if line:find("yes", 1, true) then match = true
      elseif line:find("no", 1, true) then match = false end
      break
    elseif history then count = count + 1 end
  end
  if not history or match == nil then return nil, "не удалось прочитать историю/результат катализаторов" end
  return count, match
end
M.sensor = sensor

local function sourceStack(route)
  local ok, stack = pcall(route.proxy.getStackInSlot, route.from, route.slot)
  if not ok then return nil end
  return stack
end
local function checkSource(route, key)
  local stack = sourceStack(route)
  if not stack or int(stack.size) < 1 then return nil, "нет " .. key .. " в слоте источника" end
  if int(stack.damage) ~= META[key] or not tostring(stack.name or ""):find("gt.metaitem.03", 1, true) then
    return nil, string.format("%s: в слоте %s (damage %s), ожидался %s",
      key, tostring(stack.label or stack.name), tostring(stack.damage), LABELS[key])
  end
  return true
end

local function loadConfig()
  local chunk, err = loadfile(CFG_PATH)
  if not chunk then error("конфиг " .. CFG_PATH .. ": " .. tostring(err), 0) end
  local cfg = chunk()
  if type(cfg) ~= "table" then error("конфиг должен возвращать таблицу", 0) end
  cfg = bindings.apply(cfg, bindings.load(BIND_PATH))
  cfg.pollInterval = cfg.pollInterval or 0.25
  cfg.consumeTimeout = cfg.consumeTimeout or 5
  return cfg
end
local function init(cfg)
  local machine = resolve(cfg.machine, "gt_machine")
  local routes = {}
  for _, key in ipairs(KEYS) do
    local r = cfg.routes and cfg.routes[key]
    if not r or not r.transposer or r.from == nil or r.to == nil or not r.slot then
      error(key .. ": назначь transposer, источник, слот и вход через grade8 bind", 0)
    end
    local proxy = resolve(r.transposer, "transposer")
    local ok, size = pcall(proxy.getInventorySize, r.to)
    if not ok or int(size) < 1 then error(key .. ": на стороне to нет input bus", 0) end
    routes[key] = { proxy = proxy, from = r.from, to = r.to, slot = r.slot }
    local valid, why = checkSource(routes[key], key)
    if not valid then error(why, 0) end
  end
  local inf = cfg.routes and cfg.routes.infinity
  if inf and inf.transposer and inf.from ~= nil and inf.to ~= nil then
    routes.infinity = core.fluidRoute("infinity", inf, cfg.refillSources ~= false)
    routes.infinity.fluid = routes.infinity.fluid or INFINITY
  end
  if cfg.me ~= false then cfg.meObj = core.resolveME(cfg.me, log) end
  if not routes.infinity and not cfg.meObj then
    log("WARN", "Molten Infinity не виден (нет маршрута infinity и ME): нехватка остановит машину и сожжёт катализаторы цикла")
  end
  return machine, routes
end

-- Infinity cost of the next catalyst: 144 L * 2^(times this catalyst was already inserted this cycle)
function M.cost(key, used) return INGOT * 2 ^ ((used and used[key]) or 0) end

-- The machine drains the cost from ONE input hatch; if it cannot, it calls stopMachine:
-- the cycle is aborted, endCycle never runs and every catalyst inserted this cycle is lost.
-- So never insert a catalyst whose cost is not covered.
local function ensureInfinity(routes, cfg, cost)
  local inf = routes.infinity
  if inf then
    local mine, foreign = inf:sink()
    if foreign > 0 then return false, "в хэтче Infinity чужая жидкость" end
    if mine >= cost then return true end
    local target = math.max(cost, math.min(cfg.infinityBuffer or 6048, select(3, inf:sink()) or cost))
    local need = target - mine
    local avail, _, err = inf:available(cfg.meObj)
    if err then return false, "Infinity: " .. err end
    if avail < cost - mine then
      return false, string.format("Molten Infinity: доступно %d L, нужно %d L", avail, cost - mine)
    end
    need = math.min(need, avail)
    local moved, why = inf:pump(need, { stall = cfg.stallTimeout or 15 })
    if mine + moved < cost then return false, "Infinity: " .. tostring(why or "не долилось") end
    return true
  end
  if cfg.meObj then
    local net = core.networkFluids(cfg.meObj)
    local have = net and (net[INFINITY] or 0)
    if have and have < cost then
      return false, string.format("в ME-сети %d L Molten Infinity, нужно %d L", have, cost)
    end
  end
  return true
end

-- Catalysts sitting in the input bus, returned to their own sources. Each route returns only
-- its own catalyst (the bus may be seen by several transposers); `stuck` is what is left.
local function returnBus(routes)
  local back = 0
  for _, key in ipairs(KEYS) do
    local r = routes[key]
    if r then
      local ok, size = pcall(r.proxy.getInventorySize, r.to)
      for slot = 1, (ok and int(size) or 0) do
        local got, st = pcall(r.proxy.getStackInSlot, r.to, slot)
        if got and st and int(st.size) > 0 and int(st.damage) == META[key] then
          local okT, n = pcall(r.proxy.transferItem, r.to, r.from, int(st.size), slot)
          back = back + (okT and int(n) or 0)
        end
      end
    end
  end
  local stuck = 0
  for _, key in ipairs(KEYS) do
    local r, n = routes[key], 0
    if r then
      local ok, size = pcall(r.proxy.getInventorySize, r.to)
      for slot = 1, (ok and int(size) or 0) do
        local got, st = pcall(r.proxy.getStackInSlot, r.to, slot)
        if got and st then n = n + int(st.size) end
      end
    end
    stuck = math.max(stuck, n)
  end
  return back, stuck
end
M.returnBus = returnBus

local function pauseMachine(machine, why)
  log("ERR", "%s", why)
  if machine.setWorkAllowed then
    local ok = pcall(machine.setWorkAllowed, false)
    if ok then log("WARN", "G8 остановлен до пополнения катализаторов") end
  end
end

local function runCycle(machine, routes, cfg, cycle)
  local back, stuck = returnBus(routes)
  if back > 0 then log("WARN", "цикл %d: в басе лежало %d катализаторов — возвращены в источники", cycle, back) end
  if stuck > 0 then log("ERR", "цикл %d: в басе %d предметов, которые некуда вернуть; пропускаю", cycle, stuck); return false end
  local count, matched = sensor(machine)
  if count == nil then log("ERR", "цикл %d: %s", cycle, matched); return false end
  if matched then log("INFO", "цикл %d уже разгадан", cycle); return true end
  if count ~= 0 then log("WARN", "цикл %d начат с %d катализаторами; пропускаю", cycle, count); return false end
  log("INFO", "цикл %d: поиск пары катализаторов G8", cycle)
  local used = {}
  for index, key in ipairs(ORDER) do
    local prog, maxp = machineState(machine)
    if not prog or maxp == 0 or maxp - prog < 100 then
      log("WARN", "цикл %d: не хватило времени для катализатора %d", cycle, index)
      return false
    end
    local route = routes[key]
    local cost = M.cost(key, used)
    local okInf, whyInf = ensureInfinity(routes, cfg, cost)
    if not okInf then
      log("ERR", "цикл %d: %s — подача остановлена, вставленные катализаторы вернутся в конце цикла", cycle, whyInf)
      return false
    end
    local valid, why = checkSource(route, key)
    if not valid then
      -- a Dual Interface can be empty for a moment between AE refills
      local wait = computer.uptime() + (cfg.refillWait or 3)
      repeat
        os.sleep(cfg.pollInterval)
        valid, why = checkSource(route, key)
      until valid or computer.uptime() > wait
    end
    if not valid then pauseMachine(machine, why); return false end
    local ok, moved = pcall(route.proxy.transferItem, route.from, route.to, 1, route.slot)
    if not ok or int(moved) ~= 1 then
      pauseMachine(machine, key .. ": transferItem не передал один катализатор")
      return false
    end
    local deadline = computer.uptime() + cfg.consumeTimeout
    while true do
      local seen, success = sensor(machine)
      if seen == nil then log("ERR", "%s", success); return false end
      if seen == count + 1 then
        count = seen
        used[key] = (used[key] or 0) + 1
        if cfg.onStatus then
          cfg.onStatus({ online = true, cycle = cycle, phase = "проверено " .. index .. "/18: " .. key,
            progress = prog, maxProgress = maxp, inserted = index,
            success = M.stats.ok, failed = M.stats.fail, chance = success and 100 or 0 })
        end
        if success then
          log("OK", "цикл %d: правильная пара найдена после %d катализаторов", cycle, index)
          return true
        end
        break
      end
      if seen > count + 1 then
        log("ERR", "цикл %d: появились чужие катализаторы в input bus", cycle)
        return false
      end
      local p, m = machineState(machine)
      if not p or m == 0 then
        local b = returnBus(routes)
        log("ERR", "цикл %d: машина остановилась при подаче %s (нужно %d L Molten Infinity в одном хэтче). "
          .. "Катализаторы этого цикла потеряны, %d возвращено из баса; включи машину после пополнения",
          cycle, key, cost, b)
        return false
      end
      if computer.uptime() > deadline then
        local b = returnBus(routes)
        log("ERR", "цикл %d: машина не приняла катализатор %s за %.1f с (возвращено из баса: %d)",
          cycle, key, cfg.consumeTimeout, b)
        return false
      end
      os.sleep(cfg.pollInterval)
    end
  end
  log("ERR", "цикл %d: все 15 пар проверены, но машина не подтвердила успех", cycle)
  return false
end
M.runCycle = runCycle

local function scan()
  print("gt_machine:")
  for a in component.list("gt_machine", true) do
    print("  " .. a)
    local ok, info = pcall(component.invoke, a, "getSensorInformation")
    if ok and type(info) == "table" then
      for i = 1, math.min(info.n or #info, 8) do print("    " .. tostring(info[i]):gsub("§.", "")) end
    end
  end
  print("transposer (инвентари и катализаторы):")
  for a in component.list("transposer", true) do
    local p = component.proxy(a)
    print("  " .. a)
    for s = 0, 5 do
      local ok, size = pcall(p.getInventorySize, s)
      if ok and int(size) > 0 then
        print(string.format("    %s: %d слотов", sides[s], size))
        for slot = 1, size do
          local got, item = pcall(p.getStackInSlot, s, slot)
          if got and item and int(item.size) > 0 then
            print(string.format("      %d: %s ×%d (damage %s)",
              slot, tostring(item.label or item.name), item.size, tostring(item.damage)))
          end
        end
      end
    end
  end
end

function M.main(args, opts)
  logSink = opts and opts.onLog or nil
  if args[1] == "scan" then scan(); return end
  local cfg = loadConfig()
  if opts then cfg.onStatus = opts.onStatus end
  if args[1] == "bind" then
    return bindings.run("G8 Baryonic Perfection", cfg, BIND_PATH, ROLES, { me = true })
  end
  local machine, routes = init(cfg)
  log("INFO", "grade8 v%s запущен; цикл GTNH 2.9 — 120 с", VERSION)
  local previous, previousMax, cycle = nil, 0, 0
  local lastPhase, lastChance = "ожидание цикла", nil
  while true do
    local prog, maxp = machineState(machine)
    if prog then
      if opts and opts.onStatus then
        opts.onStatus({ online = true, cycle = cycle, phase = lastPhase, progress = prog, maxProgress = maxp,
          success = M.stats.ok, failed = M.stats.fail, lastChance = lastChance })
      end
      if previous == nil and maxp > 0 then
        log("INFO", "подключился посреди цикла; жду следующий")
      elseif maxp > 0 and previous ~= nil and (previousMax == 0 or prog < previous) then
        cycle = cycle + 1
        local ok, found = pcall(runCycle, machine, routes, cfg, cycle)
        if not ok then log("ERR", "цикл %d: %s", cycle, tostring(found)); found = false end
        if found then M.stats.ok = M.stats.ok + 1 else M.stats.fail = M.stats.fail + 1 end
        lastChance = found and 100 or 0
        lastPhase = found and "пара найдена · 100%" or "пара не найдена · 0%"
        prog, maxp = machineState(machine)
      end
      previous, previousMax = prog, maxp
    else
      previous, previousMax = nil, 0
      log("ERR", "нет связи с контроллером G8")
    end
    if opts and opts.shouldStop and opts.shouldStop() then break end
    os.sleep(cfg.pollInterval)
  end
end

return M
-- END waterline/g8.lua
