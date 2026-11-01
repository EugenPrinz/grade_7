-- Grade 8 Absolute Baryonic Perfection controller for GTNH 2.9.
local component = require("component")
local computer = require("computer")
local fs = require("filesystem")
local sides = require("sides")
local bindings = require("waterline.bindings")

local M = {}
local VERSION = "2.0.0"
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
    local line = raw:lower()
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
  return machine, routes
end

local function pauseMachine(machine, why)
  log("ERR", "%s", why)
  if machine.setWorkAllowed then
    local ok = pcall(machine.setWorkAllowed, false)
    if ok then log("WARN", "G8 остановлен до пополнения катализаторов") end
  end
end

local function runCycle(machine, routes, cfg, cycle)
  local count, matched = sensor(machine)
  if count == nil then log("ERR", "цикл %d: %s", cycle, matched); return false end
  if matched then log("INFO", "цикл %d уже разгадан", cycle); return true end
  if count ~= 0 then log("WARN", "цикл %d начат с %d катализаторами; пропускаю", cycle, count); return false end
  log("INFO", "цикл %d: поиск пары катализаторов G8", cycle)
  for index, key in ipairs(ORDER) do
    local prog, maxp = machineState(machine)
    if not prog or maxp == 0 or maxp - prog < 100 then
      log("WARN", "цикл %d: не хватило времени для катализатора %d", cycle, index)
      return false
    end
    local route = routes[key]
    local valid, why = checkSource(route, key)
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
        if cfg.onStatus then
          cfg.onStatus({ online = true, cycle = cycle, phase = "проверено " .. index .. "/18: " .. key,
            progress = prog, maxProgress = maxp, inserted = index })
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
      if not p or m == 0 then return false end
      if computer.uptime() > deadline then
        log("ERR", "цикл %d: машина не приняла катализатор %s за %.1f с",
          cycle, key, cfg.consumeTimeout)
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
    return bindings.run("G8 Baryonic Perfection", cfg, BIND_PATH, KEYS, "item", BIND_LABELS)
  end
  local machine, routes = init(cfg)
  log("INFO", "grade8 v%s запущен; цикл GTNH 2.9 — 120 с", VERSION)
  local previous, previousMax, cycle = nil, 0, 0
  while true do
    local prog, maxp = machineState(machine)
    if prog then
      if opts and opts.onStatus then
        opts.onStatus({ online = true, cycle = cycle, phase = "ожидание / цикл",
          progress = prog, maxProgress = maxp })
      end
      if previous == nil and maxp > 0 then
        log("INFO", "подключился посреди цикла; жду следующий")
      elseif maxp > 0 and previous ~= nil and (previousMax == 0 or prog < previous) then
        cycle = cycle + 1
        runCycle(machine, routes, cfg, cycle)
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
