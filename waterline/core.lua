-- Shared runtime for grade modules: machine polling, cycle detection, sensor parsing,
-- exact fluid/item transfers, ME stock, logging and a module runner.
-- A grade module provides { defaults, fields, init?, onCycle?, onIdle?, onGuard?, scanExtra? }
-- and calls core.main(spec, impl, args, opts).
local component = require("component")
local computer  = require("computer")
local sides     = require("sides")

local M = {}
M.CFG_PATH = "/home/waterline.cfg.lua"
function M.bindPath(id) return "/home/waterline." .. id .. ".bindings.lua" end

local function int(x) return math.floor(tonumber(x) or 0) end
M.int = int
local function now() return computer.uptime() end

---------------------------------------------------------------- sensor
-- Numbers: "1,024" -> 1024, "7.03" -> 7.03, "1,5" -> 1.5. Takes the last number in the text.
function M.lastNumber(text)
  local num
  for tok in tostring(text):gmatch("%-?%d[%d,%.]*") do num = tok end
  if not num then return nil end
  num = num:gsub("[,%.]+$", "")
  if num:find(",") and not num:find("%.") and #(num:match(",(%d*)$") or "") == 3 then
    num = num:gsub(",", "")
  else
    num = num:gsub(",", ".")
  end
  return tonumber(num)
end

local function clean(s)
  return (tostring(s or ""):gsub("§.", ""):gsub("%c", " "))
end
M.clean = clean

-- string.lower plus Cyrillic А–Я, Ё (UTF-8), so Russian sensor lines match lower-case words
function M.lower(s)
  s = tostring(s or ""):lower()
  s = s:gsub("\208([\144-\159])", function(c) return "\208" .. string.char(c:byte() + 32) end)
  s = s:gsub("\208([\160-\175])", function(c) return "\209" .. string.char(c:byte() - 32) end)
  s = s:gsub("\208\129", "\209\145")
  return s
end

-- Raw GT infodata: "GT5U.infodata.<key>" .. "\\" .. "\\" .. arg ... (two backslashes between parts).
local SEP = "\\\\"
local function splitRaw(line)
  local key = line:match("^%s*GT5U%.infodata%.([%w_%.]+)")
  if not key then return nil end
  local args, rest = {}, line
  local i = rest:find(SEP, 1, true)
  while i do
    rest = rest:sub(i + #SEP)
    local j = rest:find(SEP, 1, true)
    args[#args + 1] = j and rest:sub(1, j - 1) or rest
    i = j
  end
  return key, args
end
M.splitRaw = splitRaw

-- fields: { { field = "ph", key = "purification_unit_ph_adjustment.ph", words = { "%f[%a]ph%f[%A]" },
--             type = "number" | "text" }, ... }
-- words are Lua patterns tried against the lower-cased translated line (en/ru).
local BASE_FIELDS = {
  { field = "chance", key = "purification_unit_base.success_chance", words = { "%%" }, type = "number" },
  { field = "parallel", key = "parallel.current", words = { "parallel", "паралл" }, type = "number" },
}

function M.parseSensor(info, fields)
  local r = { lines = {} }
  if type(info) ~= "table" then return nil end
  local all = {}
  for _, f in ipairs(BASE_FIELDS) do all[#all + 1] = f end
  for _, f in ipairs(fields or {}) do all[#all + 1] = f end
  for i = 1, (info.n or #info) do
    local line = clean(info[i])
    r.lines[#r.lines + 1] = line
    local key, args = splitRaw(line)
    for _, f in ipairs(all) do
      if r[f.field] == nil then
        local value
        if key then
          if key == f.key then
            local arg = args[#args] or ""
            if f.type == "text" then value = (arg:gsub("^%s+", ""):gsub("%s+$", ""))
            elseif f.type == "flag" then value = true
            else value = M.lastNumber(arg) end
          end
        else
          local low = M.lower(line)
          for _, w in ipairs(f.words or {}) do
            if low:find(w) then
              if f.type == "text" then
                value = line:match(":%s*(.-)%s*$") or line
              elseif f.type == "flag" then
                value = true
              elseif f.field == "chance" then
                value = tonumber((((line:match("(%-?%d[%d%.,]*)%s*%%") or ""):gsub(",", "."))))
              else
                value = M.lastNumber(line:match(":%s*(.-)$") or line)
              end
              break
            end
          end
        end
        if value ~= nil and value ~= "" then r[f.field] = value end
      end
    end
  end
  return r
end

---------------------------------------------------------------- components
function M.resolve(addr, ctype, hint)
  if addr == nil or addr == false then
    local found
    for a in component.list(ctype, true) do
      if found then error("несколько '" .. ctype .. "' — " .. (hint or "назначь адрес через bind"), 0) end
      found = a
    end
    if not found then error("не найден компонент '" .. ctype .. "'", 0) end
    return component.proxy(found)
  end
  local full = component.get(addr, ctype)
  if not full then error("'" .. ctype .. "' " .. tostring(addr) .. " не найден — " .. (hint or "запусти bind"), 0) end
  return component.proxy(full)
end

function M.tanksOf(t, side)
  local out = {}
  local ok, res = pcall(t.getFluidInTank, side)
  if not ok or type(res) ~= "table" then return out, nil end
  local cap
  for i = 1, (res.n or #res) do
    local f = res[i]
    if type(f) == "table" then
      if int(f.capacity) > 0 then cap = (cap or 0) + int(f.capacity) end
      if f.name and int(f.amount) > 0 then out[#out + 1] = f end
    end
  end
  return out, cap
end

---------------------------------------------------------------- ME stock
local ME_TYPES = { "me_interface", "me_controller", "me_dual_interface" }
M.ME_TYPES = ME_TYPES

function M.resolveME(addr, log)
  if addr == false then return nil end
  local full
  if addr then
    full = component.get(addr)
    if not full then if log then log("WARN", "ME-компонент %s не найден", tostring(addr)) end return nil end
  else
    local found = {}
    for _, t in ipairs(ME_TYPES) do for a in component.list(t, true) do found[#found + 1] = a end end
    if #found ~= 1 then
      if #found > 1 and log then log("WARN", "найдено %d ME-компонентов — назначь ME в bind", #found) end
      return nil
    end
    full = found[1]
  end
  local ok, list = pcall(component.invoke, full, "getFluidsInNetwork")
  if not ok or type(list) ~= "table" then
    if log then log("WARN", "%s не отдаёт getFluidsInNetwork", full:sub(1, 8)) end
    return nil
  end
  return { address = full, at = -100, map = nil }
end

function M.networkFluids(me)
  if not me then return nil end
  if me.map and now() - me.at < 3 then return me.map end
  local ok, list = pcall(component.invoke, me.address, "getFluidsInNetwork")
  if not ok or type(list) ~= "table" then return nil end
  local map = {}
  for i = 1, (list.n or #list) do
    local f = list[i]
    if type(f) == "table" and f.name then map[f.name] = (map[f.name] or 0) + int(f.amount) end
  end
  me.at, me.map = now(), map
  return map
end

---------------------------------------------------------------- fluid routes
local Fluid = {}
Fluid.__index = Fluid

function M.fluidRoute(key, rc, defaultRefill)
  local t = M.resolve(rc.transposer, "transposer")
  local r = setmetatable({ key = key, kind = "fluid", t = t, from = rc.from, to = rc.to,
    fluid = rc.fluid, refill = rc.refill == nil and defaultRefill or rc.refill }, Fluid)
  local ok, cnt = pcall(t.getTankCount, r.to)
  if not ok or int(cnt) == 0 then error(key .. ": на стороне входа нет хэтча", 0) end
  return r
end

function Fluid:name() return self.fluid or self.learned end

-- Source content; the source must hold exactly one fluid.
function Fluid:stock()
  local amt, name = 0, nil
  local tanks, cap = M.tanksOf(self.t, self.from)
  for _, f in ipairs(tanks) do
    if name and f.name ~= name then return 0, "в источнике несколько жидкостей (" .. name .. ", " .. f.name .. ")" end
    name = f.name
    amt = amt + int(f.amount)
  end
  self.cap = cap or self.cap
  if name then
    local want = self:name()
    if want and want ~= name then return 0, "в источнике '" .. name .. "', ожидалось '" .. want .. "'" end
    self.learned = self.learned or name
  end
  return amt
end

-- Amount of this route's fluid in the machine hatch, count of foreign fluids, hatch capacity.
function Fluid:sink()
  local name = self:name()
  local mine, foreign = 0, 0
  local tanks, cap = M.tanksOf(self.t, self.to)
  for _, f in ipairs(tanks) do
    if name and f.name == name then mine = mine + int(f.amount) else foreign = foreign + 1 end
  end
  return mine, foreign, cap
end

-- Deliverable this cycle: source + ME network (or "AE will refill" when the source is full and ME is unknown).
function Fluid:available(me)
  local amt, err = self:stock()
  if err then return 0, amt, err end
  if not self.refill then return amt, amt end
  local name, net = self:name(), M.networkFluids(me)
  if net and name then return amt + (net[name] or 0), amt end
  if self.cap and amt >= self.cap * 0.9 then return math.huge, amt end
  return amt, amt
end

-- Move exactly `need` mB source -> hatch. o: { abort = fn -> reason|nil, stall = s, onProgress = fn(moved) }
function Fluid:pump(need, o)
  o = o or {}
  local left, lastMove = need, now()
  while left > 0 do
    local why = o.abort and o.abort()
    if why then return need - left, why end
    if now() - lastMove > (o.stall or 15) then
      return need - left, string.format("нет поступления %d с (источник пуст или хэтч не сливается)", o.stall or 15)
    end
    local ok, moved = self.t.transferFluid(self.from, self.to, left)
    if ok and type(moved) ~= "number" then return need - left, "transferFluid не вернул количество" end
    moved = ok and int(moved) or 0
    if moved > left then return need - left + moved, "перелив (" .. moved .. " > " .. left .. ")" end
    if moved > 0 then
      left = left - moved
      lastMove = now()
      if o.onProgress then o.onProgress(need - left) end
    else
      os.sleep(o.wait or 0.25)
    end
  end
  return need
end

-- Return this route's fluid from the hatch to the source. Only when the hatch holds nothing else.
function Fluid:rollback()
  local mine, foreign = self:sink()
  if mine == 0 then return 0, 0 end
  if foreign > 0 then return 0, mine end
  local ok, moved = self.t.transferFluid(self.to, self.from, mine)
  moved = ok and int(moved) or 0
  return moved, mine - moved
end

---------------------------------------------------------------- item routes
local Item = {}
Item.__index = Item

function M.itemRoute(key, rc)
  local t = M.resolve(rc.transposer, "transposer")
  local r = setmetatable({ key = key, kind = "item", t = t, from = rc.from, to = rc.to,
    slot = rc.slot, item = rc.item }, Item)
  local ok, size = pcall(t.getInventorySize, r.to)
  if not ok or int(size) < 1 then error(key .. ": на стороне входа нет input bus", 0) end
  return r
end

local function sameItem(stack, item)
  if not stack or int(stack.size) < 1 then return false end
  if not item then return true end
  if item.name and stack.name ~= item.name then return false end
  if item.damage ~= nil and int(stack.damage) ~= int(item.damage) then return false end
  if item.label and not item.name and clean(stack.label) ~= clean(item.label) then return false end
  return true
end
M.sameItem = sameItem

function Item:stacks(side, match)
  local out = {}
  local ok, size = pcall(self.t.getInventorySize, side)
  if not ok then return out end
  for slot = 1, int(size) do
    local got, stack = pcall(self.t.getStackInSlot, side, slot)
    if got and stack and int(stack.size) > 0 and (not match or match(stack)) then
      out[#out + 1] = { slot = slot, stack = stack }
    end
  end
  return out
end

function Item:matcher() local item = self.item; return function(s) return sameItem(s, item) end end

function Item:count(side, match)
  local n = 0
  for _, e in ipairs(self:stacks(side or self.from, match or self:matcher())) do n = n + int(e.stack.size) end
  return n
end

-- Move `count` matching items source -> bus, retrying while the machine drains the bus.
function Item:move(count, match, o)
  o = o or {}
  match = match or self:matcher()
  local moved, lastMove = 0, now()
  while moved < count do
    local why = o.abort and o.abort()
    if why then return moved, why end
    if now() - lastMove > (o.stall or 15) then return moved, "предметы не перемещаются (пусто или бас полон)" end
    local progress = false
    for _, e in ipairs(self:stacks(self.from, match)) do
      local n = math.min(count - moved, int(e.stack.size))
      local ok, got = pcall(self.t.transferItem, self.from, self.to, n, e.slot)
      got = ok and int(got) or 0
      if got > 0 then moved, progress, lastMove = moved + got, true, now() end
      if moved >= count then break end
    end
    if o.onProgress and progress then o.onProgress(moved) end
    if not progress and moved < count then os.sleep(o.wait or 0.25) end
  end
  return moved
end

-- Return matching items from the bus back to the source.
function Item:rollback(match)
  local back = 0
  for _, e in ipairs(self:stacks(self.to, match or self:matcher())) do
    local ok, got = pcall(self.t.transferItem, self.to, self.from, int(e.stack.size), e.slot)
    back = back + (ok and int(got) or 0)
  end
  return back, self:count(self.to, match)
end

---------------------------------------------------------------- config
local function copy(t)
  local out = {}
  for k, v in pairs(t or {}) do out[k] = type(v) == "table" and copy(v) or v end
  return out
end
M.copy = copy

function M.loadConfig(spec, defaults)
  local bindings = require("waterline.bindings")
  local cfg = copy(defaults)
  local chunk = loadfile(M.CFG_PATH)
  if chunk then
    local ok, all = pcall(chunk)
    if ok and type(all) == "table" and type(all.grades) == "table" and type(all.grades[spec.id]) == "table" then
      for k, v in pairs(all.grades[spec.id]) do cfg[k] = v end
    end
  end
  cfg.routes = cfg.routes or {}
  return bindings.apply(cfg, bindings.load(M.bindPath(spec.id)))
end

---------------------------------------------------------------- scan
function M.scan(spec, impl)
  print("gt_machine:")
  for a in component.list("gt_machine", true) do
    print("  " .. a)
    local ok, info = pcall(component.invoke, a, "getSensorInformation")
    if ok and type(info) == "table" then
      for i = 1, math.min(info.n or #info, 14) do print("      " .. clean(info[i])) end
    end
  end
  print("ME:")
  for _, t in ipairs(ME_TYPES) do
    for a in component.list(t, true) do
      local ok, list = pcall(component.invoke, a, "getFluidsInNetwork")
      print(string.format("  %s  %s  жидкостей в сети: %s", a, t,
        ok and type(list) == "table" and tostring(list.n or #list) or "нет getFluidsInNetwork"))
    end
  end
  print("transposer:")
  for a in component.list("transposer", true) do
    local p = component.proxy(a)
    print("  " .. a)
    for s = 0, 5 do
      local okT, cnt = pcall(p.getTankCount, s)
      if okT and int(cnt) > 0 then
        local t = {}
        local tanks, cap = M.tanksOf(p, s)
        for _, f in ipairs(tanks) do t[#t + 1] = string.format("%s %d", f.name, int(f.amount)) end
        print(string.format("    %-6s жидкость (ёмк. %s): %s", sides[s], cap and tostring(cap) or "?",
          #t > 0 and table.concat(t, ", ") or "пусто"))
      end
      local okI, size = pcall(p.getInventorySize, s)
      if okI and int(size) > 0 then
        local t = {}
        for slot = 1, int(size) do
          local got, st = pcall(p.getStackInSlot, s, slot)
          if got and st and int(st.size) > 0 then
            t[#t + 1] = string.format("%d:%s×%d", slot, clean(st.label or st.name), int(st.size))
          end
        end
        print(string.format("    %-6s предметы (%d сл.): %s", sides[s], int(size),
          #t > 0 and table.concat(t, ", ") or "пусто"))
      end
    end
  end
  if impl and impl.scanExtra then impl.scanExtra() end
end

---------------------------------------------------------------- runner
-- ctx (passed to module hooks):
--   cfg, spec, machine, routes[roleId], me, cycle, log(level, fmt, ...), phase(text),
--   progress() -> prog, maxp | nil, ticksLeft() -> n | nil, sensor() -> parsed | nil,
--   abortIfLate(reserveTicks) -> fn for pump/move abort, data (per-cycle scratch), stats
function M.main(spec, impl, args, opts)
  opts = opts or {}
  args = args or {}
  local logSink = opts.onLog
  local function log(level, fmt, ...)
    local msg = select("#", ...) > 0 and string.format(fmt, ...) or tostring(fmt)
    if logSink then logSink(level, msg)
    else print(string.format("[%s] %-4s %s", os.date("%H:%M:%S"), level, msg)) end
  end
  if args[1] == "scan" then return M.scan(spec, impl) end
  local cfg = M.loadConfig(spec, impl.defaults or {})
  if args[1] == "bind" then
    return require("waterline.bindings").run(spec.name, cfg, M.bindPath(spec.id), spec.roles or {},
      { me = spec.me, redstone = spec.redstone })
  end

  cfg.pollInterval = cfg.pollInterval or 0.5
  cfg.guardTicks = cfg.guardTicks or 60
  local machine = M.resolve(cfg.machine, "gt_machine", "назначь контроллер через WaterLineProgram bind " .. spec.id)
  local routes = {}
  for _, role in ipairs(spec.roles or {}) do
    local rc = cfg.routes[role.id]
    if rc and rc.transposer and rc.from ~= nil and rc.to ~= nil then
      if role.kind == "fluid" then routes[role.id] = M.fluidRoute(role.id, rc, cfg.refillSources ~= false)
      else routes[role.id] = M.itemRoute(role.id, rc) end
    elseif not role.optional then
      error(role.id .. ": назначь transposer, источник и вход через WaterLineProgram bind " .. spec.id, 0)
    end
  end
  local me = spec.me and M.resolveME(cfg.me, log) or nil

  local stats = { cycles = 0, ok = 0, fail = 0, chanceSum = 0, errors = 0 }
  local status = { online = false, cycle = 0, phase = "ожидание цикла" }
  local ctx = { cfg = cfg, spec = spec, machine = machine, routes = routes, me = me,
    log = log, stats = stats, data = {} }

  function ctx.progress()
    local ok1, prog = pcall(machine.getWorkProgress)
    local ok2, maxp = pcall(machine.getWorkMaxProgress)
    if not (ok1 and ok2) then return nil end
    return int(prog), int(maxp)
  end
  function ctx.ticksLeft()
    local p, m = ctx.progress()
    if not p or m == 0 then return nil end
    return m - p
  end
  function ctx.sensor()
    local ok, info = pcall(machine.getSensorInformation)
    if not ok then return nil end
    local parsed = M.parseSensor(info, impl.fields)
    if parsed then status.chance = parsed.chance or status.chance; status.parallel = parsed.parallel or status.parallel end
    return parsed
  end
  local function push()
    if opts.onStatus then
      status.success, status.failed = stats.ok, stats.fail
      opts.onStatus(M.copy(status))
    end
  end
  function ctx.phase(text, extra)
    status.phase = text
    if extra then for k, v in pairs(extra) do status[k] = v end end
    push()
  end
  -- abort function for pump/move: stop when the cycle ended or fewer than `reserve` ticks are left
  function ctx.abortIfLate(reserve)
    return function()
      local left = ctx.ticksLeft()
      if not left then return "цикл закончился" end
      if left < reserve then return "до конца цикла меньше " .. reserve .. " тиков" end
      if opts.shouldStop and opts.shouldStop() and impl.abortOnStop then return "остановка модуля" end
      return nil
    end
  end

  if impl.init then impl.init(ctx) end
  log("INFO", "%s запущен", spec.name)

  local last, lastMax, guarded = nil, 0, false
  while true do
    local prog, maxp = ctx.progress()
    if not prog then
      if status.online then log("ERR", "нет связи с контроллером %s", spec.short) end
      status.online = false
    else
      status.online = true
      status.progress, status.maxProgress = prog, maxp
      local started = maxp > 0 and last ~= nil and (lastMax == 0 or prog < last)
      if last == nil and maxp > 0 then
        log("INFO", "подключился посреди цикла (%d/%d) — жду следующий", prog, maxp)
        guarded = true
      end
      last, lastMax = prog, maxp
      if started then
        guarded = false
        stats.cycles = stats.cycles + 1
        status.cycle = stats.cycles
        ctx.cycle = stats.cycles
        ctx.data = {}
        if impl.onCycle then
          local ok, err = pcall(impl.onCycle, ctx)
          if not ok then stats.errors = stats.errors + 1; log("ERR", "цикл %d: %s", ctx.cycle, tostring(err)) end
        end
        prog, maxp = ctx.progress()
        if prog then last, lastMax, status.progress, status.maxProgress = prog, maxp, prog, maxp end
      end
      if prog and maxp > 0 and not guarded and maxp - prog <= cfg.guardTicks then
        guarded = true
        local s = ctx.sensor()
        if s and s.chance and ctx.cycle then
          local expect = math.min(100, impl.expectChance and impl.expectChance(ctx) or 100)
          local good = s.chance >= expect - 0.01
          if good then stats.ok = stats.ok + 1 else stats.fail = stats.fail + 1 end
          stats.chanceSum = stats.chanceSum + s.chance
          status.lastChance = s.chance
          log(good and "OK" or "WARN", "цикл %d: шанс машины %s%% (ожидалось ≥ %s%%)",
            ctx.cycle, tostring(s.chance), tostring(expect))
        end
        if impl.onGuard then
          local ok, err = pcall(impl.onGuard, ctx)
          if not ok then log("ERR", "guard: %s", tostring(err)) end
        end
      end
      if impl.onIdle then
        local ok, err = pcall(impl.onIdle, ctx, prog, maxp)
        if not ok then log("ERR", "%s", tostring(err)) end
      end
      if maxp == 0 and status.phase ~= "ожидание цикла" then status.phase = "ожидание цикла" end
    end
    push()
    if opts.shouldStop and opts.shouldStop() then break end
    os.sleep(cfg.pollInterval)
  end
  log("INFO", "%s остановлен: циклов %d, подтверждено %d/%d", spec.short, stats.cycles, stats.ok, stats.ok + stats.fail)
  return true
end

return M
-- END waterline/core.lua
