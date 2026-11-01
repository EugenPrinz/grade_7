-- degasser.lua — автоматизация Residual Decontaminant Degasser (GTNH, Grade 7 water)
-- Механика по MTEPurificationUnitDegasser.java (GT5-Unofficial):
--   * сигнал 0..15 на Degasser Control Hatch выставляется в startCycle()
--   * сигнал 0 -> 10000 L Super Coolant; бит 3 (8) -> ничего не лить
--   * бит 0 -> инертный газ по битам 1-2; бит 1 -> 1440 L SC base; бит 2 -> 4608 L Neutronium
--   * количества сверяются ТОЧНО, лишняя валидная жидкость = провал
--   * хэтчи сливаются каждые 20 тиков и только пока машина работает
-- Запуск:  degasser        — основной цикл (с экраном, если есть GPU/экран T3)
--          degasser scan   — показать компоненты, стороны и жидкости (для заполнения конфига)
local component = require("component")
local computer  = require("computer")
local event     = require("event")
local sides     = require("sides")
local fs        = require("filesystem")
local uni       = require("unicode")

local VERSION  = "2.0.0"
local CFG_PATH = "/home/degasser.cfg.lua"
local BIND_PATH = "/home/degasser.bindings.lua"
local bindings = require("waterline.bindings")

local AMOUNT = {
  coolant = 10000, helium = 10000, neon = 7500, krypton = 5000, xenon = 2500,
  superconductor = 1440, neutronium = 4608,
}
local KEYS  = { "coolant", "helium", "neon", "krypton", "xenon", "superconductor", "neutronium" }
local GASES = { "helium", "neon", "krypton", "xenon" } -- индекс = биты 1-2 + 1
local LABEL = {
  coolant = "Super Coolant", helium = "Helium", neon = "Neon", krypton = "Krypton", xenon = "Xenon",
  superconductor = "SC base", neutronium = "Neutronium",
}
-- тир SC по имени жидкости (длинные совпадения первыми)
local SC_TIERS = {
  { "umvbase", 2.0, "UMV" }, { "uivbase", 1.75, "UIV" }, { "uevbase", 1.5, "UEV" },
  { "uhvbase", 1.25, "UHV" }, { "uvbase", 1.0, "UV" },
  { "longasssuperconductornameforuhvwire", 1.25, "UHV" },
  { "longasssuperconductornameforuvwire", 1.0, "UV" },
}
local P_SC_BIT = 0.4 -- доля циклов, где требуется SC (биты 1 и не бит 3): 0.5 * 0.8

local cfg -- заполняется в main

---------------------------------------------------------------- util
local function int(x) return math.floor(tonumber(x) or 0) end
local function bit(s, n) return math.floor(s / 2 ^ n) % 2 == 1 end
local function bin4(s)
  local t = {}
  for i = 3, 0, -1 do t[#t + 1] = bit(s, i) and "1" or "0" end
  return table.concat(t)
end
local function fmtNum(n)
  local s = tostring(int(n))
  local r = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
  return (r:gsub("^ ", ""):gsub("^%- ", "-"))
end

---------------------------------------------------------------- state (общий для логики и экрана)
local state = {
  online = false, prog = 0, maxp = 0,
  cycle = 0, known = false, sig = nil, plan = {}, phase = "ожидание старта цикла", phaseLevel = "dim",
  pumped = {}, drained = {}, predChance = nil,
  sensor = nil, sensorAt = -1, buffers = {}, buffersAt = -1,
  events = {}, startedAt = 0,
}

local ui = { on = false }
local logSink

local function log(level, fmt, ...)
  local msg = string.format(fmt, ...)
  local line = string.format("[%s] %-4s %s", os.date("%H:%M:%S"), level, msg)
  table.insert(state.events, 1, { t = os.date("%H:%M:%S"), level = level, msg = msg })
  if #state.events > 40 then state.events[#state.events] = nil end
  if logSink then logSink(level, msg)
  elseif not ui.on then print(line) end
  if cfg and cfg.logFile then
    pcall(function()
      if fs.exists(cfg.logFile) and fs.size(cfg.logFile) > (cfg.logMaxBytes or 65536) then
        if fs.exists(cfg.logFile .. ".1") then fs.remove(cfg.logFile .. ".1") end
        fs.rename(cfg.logFile, cfg.logFile .. ".1")
      end
      local f = io.open(cfg.logFile, "a")
      if f then f:write(line .. "\n"); f:close() end
    end)
  end
end

local function setPhase(text, level) state.phase = text; state.phaseLevel = level or "fg" end

local function resolve(addr, ctype)
  if addr == nil then
    local found
    for a in component.list(ctype, true) do
      if found then error("в сети несколько '" .. ctype .. "' — укажи адрес в конфиге (degasser scan)", 0) end
      found = a
    end
    if not found then error("не найден компонент '" .. ctype .. "'", 0) end
    return component.proxy(found)
  end
  local full = component.get(addr, ctype)
  if not full then error("'" .. ctype .. "' с адресом " .. tostring(addr) .. " не найден (degasser scan)", 0) end
  return component.proxy(full)
end

-- Непустые танки на стороне side: { {name=, amount=, capacity=}, ... }
local function tanksOf(t, side)
  local out = {}
  local ok, res = pcall(t.getFluidInTank, side)
  if not ok or type(res) ~= "table" then return out end
  for i = 1, (res.n or #res) do
    local f = res[i]
    if type(f) == "table" and f.name and int(f.amount) > 0 then out[#out + 1] = f end
  end
  return out
end

---------------------------------------------------------------- plan
-- Сигнал -> список шагов { {key, amount}, ... }. Пустой список = ничего не лить.
local function planFor(sig)
  if sig == 0 then return { { "coolant", AMOUNT.coolant } } end
  if bit(sig, 3) then return {} end
  local p = {}
  if bit(sig, 0) then
    local g = GASES[math.floor(sig / 2) % 4 + 1]
    p[#p + 1] = { g, AMOUNT[g] }
  end
  if bit(sig, 1) then p[#p + 1] = { "superconductor", AMOUNT.superconductor } end
  if bit(sig, 2) then p[#p + 1] = { "neutronium", AMOUNT.neutronium } end
  return p
end

local function describe(plan)
  if #plan == 0 then return "ничего" end
  local t = {}
  for _, s in ipairs(plan) do t[#t + 1] = s[2] .. " L " .. s[1] end
  return table.concat(t, " + ")
end

---------------------------------------------------------------- routes
local routes = {}

local function fluidName(r) return r.fluid or r.learned end

local function scTierFor(name)
  if not name then return nil end
  for _, t in ipairs(SC_TIERS) do
    if name:lower():find(t[1], 1, true) then return t end
  end
  return nil
end
local function scTier()
  local r = routes.superconductor
  return scTierFor(r and fluidName(r))
end

-- Остаток нужной жидкости в буфере. Буфер должен содержать ровно один тип жидкости.
local function sourceStock(r)
  local amt, name = 0, nil
  for _, f in ipairs(tanksOf(r.t, r.from)) do
    if name and f.name ~= name then
      return 0, "в буфере несколько жидкостей (" .. name .. ", " .. f.name .. ")"
    end
    name = f.name
    amt = amt + int(f.amount)
    if int(f.capacity) > 0 then r.cap = int(f.capacity) end
  end
  if name then
    local want = fluidName(r)
    if want and want ~= name then
      local oldTier, newTier = scTierFor(want), scTierFor(name)
      if r.key == "superconductor" and oldTier and newTier and oldTier[3] == newTier[3]
        and want:find("longasssuperconductornamefor", 1, true)
        and name:find("superconductor", 1, true) then
        r.fluid = name -- migration from the 2.8.4 name to the 2.9 name
        log("INFO", "SC base %s: имя жидкости изменилось на %s", newTier[3], name)
      else
        return 0, "в буфере '" .. name .. "', ожидалось '" .. want .. "'"
      end
    end
    r.learned = r.learned or name
  end
  return amt
end

-- Запас ME-сети (Adapter у любого ME-блока). Кэш 3 с: getFluidsInNetwork() тяжёлый на больших сетях.
local me
local meCache = { at = -100, map = nil }
local function networkFluids()
  if not me then return nil end
  local now = computer.uptime()
  if meCache.map and now - meCache.at < 3 then return meCache.map end
  local ok, list = pcall(component.invoke, me.address, "getFluidsInNetwork")
  if not ok or type(list) ~= "table" then return nil end
  local map = {}
  for i = 1, (list.n or #list) do
    local f = list[i]
    if type(f) == "table" and f.name then map[f.name] = (map[f.name] or 0) + int(f.amount) end
  end
  meCache.at, meCache.map = now, map
  return map
end

-- Сколько можно подать за цикл.
--   буфер-танк:          содержимое танка
--   интерфейс + сеть:    содержимое интерфейса + запас сети
--   интерфейс без сети:  если интерфейс заполнен (≥90%) — считаем, что AE дольёт (math.huge)
-- Возвращает available, local, err, net (net = nil, если сеть не видна)
local function available(r)
  local amt, err = sourceStock(r)
  if err then return 0, amt, err end
  if r.key == "superconductor" and fluidName(r) and not scTier() then
    return 0, amt, "неизвестная SC base: " .. tostring(fluidName(r))
  end
  if not r.refill then return amt, amt end
  local name = fluidName(r)
  local net = networkFluids()
  if net and name then
    local n = net[name] or 0
    return amt + n, amt, nil, n
  end
  if r.cap and amt >= r.cap * 0.9 then return math.huge, amt end
  return amt, amt
end

-- Сколько катализатора маршрута r лежит в его хэтче.
local function sinkAmount(r)
  local name = fluidName(r)
  if not name then return 0, 0 end
  local mine, foreign = 0, 0
  for _, f in ipairs(tanksOf(r.t, r.to)) do
    if f.name == name then mine = mine + int(f.amount) else foreign = foreign + 1 end
  end
  return mine, foreign
end

-- Перекачать ровно need мБ. Возвращает фактически перекачанное и ошибку.
local function pump(r, need, deadline)
  local left = need
  state.pumped[r.key] = 0
  local lastMove = computer.uptime()
  while left > 0 do
    local now = computer.uptime()
    if now > deadline then return need - left, "не успел до дедлайна" end
    if now - lastMove > cfg.stallTimeout then
      return need - left, string.format("нет поступления %d с (источник не доливается или хэтч не сливается)", cfg.stallTimeout)
    end
    local ok, moved = r.t.transferFluid(r.from, r.to, left)
    if ok and type(moved) ~= "number" then
      return need - left, "transferFluid не вернул количество (старая версия OC?) — точная подача невозможна"
    end
    moved = ok and int(moved) or 0
    if moved > left then return need - left + moved, "перелив (" .. moved .. " > " .. left .. ")" end
    if moved > 0 then
      left = left - moved
      lastMove = computer.uptime()
      state.pumped[r.key] = need - left
    else
      os.sleep(0.25) -- хэтч полон (ждём слива, каждые 20 тиков) или интерфейс пуст (ждём долива AE)
    end
  end
  return need
end

-- Вернуть катализаторы из хэтчей в буферы (только если в хэтче лежит одна жидкость —
-- иначе transposer может слить не ту и смешать буферы).
local function rollbackAll(reason)
  local leftAny = false
  for _, key in ipairs(KEYS) do
    local r = routes[key]
    local mine, foreign = sinkAmount(r)
    if mine > 0 then
      if foreign == 0 then
        local ok, moved = r.t.transferFluid(r.to, r.from, mine)
        moved = ok and int(moved) or 0
        log("WARN", "откат %s: %d/%d L из хэтча в буфер (%s)", key, moved, mine, reason)
        if moved < mine then leftAny = true end
      else
        log("ERR", "в хэтче %s %d L вперемешку с другими жидкостями — откат небезопасен", key, mine)
        leftAny = true
      end
    end
  end
  if leftAny then log("ERR", "в хэтчах остался катализатор — следующий цикл, скорее всего, провалится") end
  return not leftAny
end

local function sinksClean()
  for _, key in ipairs(KEYS) do
    if sinkAmount(routes[key]) > 0 then return false end
  end
  return true
end

local function waitDrained(plan, timeout)
  local t0 = computer.uptime()
  repeat
    local busy = false
    for _, s in ipairs(plan) do
      if sinkAmount(routes[s[1]]) > 0 then busy = true else state.drained[s[1]] = true end
    end
    if not busy then return true end
    os.sleep(0.25)
  until computer.uptime() - t0 > timeout
  return false
end

---------------------------------------------------------------- machine / signal
local machine, rs

local function machineState()
  local ok1, prog = pcall(machine.getWorkProgress)
  local ok2, maxp = pcall(machine.getWorkMaxProgress)
  if not (ok1 and ok2) then return nil end
  return int(prog), int(maxp)
end

local function readSignal()
  local v
  if cfg.redstoneSide then
    v = int(rs.getInput(cfg.redstoneSide))
  else
    v = 0
    local all = rs.getInput()
    for s = 0, 5 do
      local x = int(type(all) == "table" and all[s] or 0)
      if x > v then v = x end
    end
  end
  if v < 0 then v = 0 elseif v > 15 then v = 15 end
  return v
end

-- Данные из сканера машины: шанс успеха (live, по уже слитым жидкостям), множитель выхода, параллели.
-- Строки могут прийти переведёнными или ключами локализации — ищем по словам из обоих вариантов.
-- Последнее число в строке (значение всегда в конце; в ключах вида GT5U.* цифры стоят раньше).
local function tailNumber(line)
  local num
  for tok in line:gmatch("%d[%d,%.]*") do num = tok end
  if not num then return nil end
  num = num:gsub("[,%.]+$", "")
  if num:find(",") and not num:find("%.") and #num:match(",(%d*)$") == 3 then
    num = num:gsub(",", "")          -- 1,024 -> 1024
  else
    num = num:gsub(",", ".")         -- 1,5 -> 1.5
  end
  return tonumber(num)
end

local function readSensor()
  local ok, info = pcall(machine.getSensorInformation)
  if not ok or type(info) ~= "table" then return nil end
  local r = {}
  for i = 1, (info.n or #info) do
    local l = tostring(info[i] or ""):gsub("§.", ""):gsub("%c", " ")
    local low = l:lower()
    local pct = l:match("([%d][%d%.,]*)%s*%%")
    if pct and r.chance == nil then r.chance = tonumber((pct:gsub(",", "."))) end
    if low:find("multiplier", 1, true) or low:find("множител", 1, true) then r.mult = tailNumber(l) or r.mult end
    if low:find("parallel", 1, true) or low:find("паралл", 1, true) then r.parallel = tailNumber(l) or r.parallel end
  end
  return r
end

---------------------------------------------------------------- stats
local stats = { cycles = 0, ok = 0, nothing = 0, skipped = 0, failed = 0, used = {},
                mOk = 0, mFail = 0, multSum = 0 }
for _, k in ipairs(KEYS) do stats.used[k] = 0 end

local function printStats()
  log("STAT", "циклов %d | залито OK %d | бит4 (ничего) %d | пропущено %d | ошибок подачи %d",
    stats.cycles, stats.ok, stats.nothing, stats.skipped, stats.failed)
  if stats.mOk + stats.mFail > 0 then
    log("STAT", "машина подтвердила: успех %d, провал %d (%.1f%%), средний множитель ×%.3f",
      stats.mOk, stats.mFail, 100 * stats.mOk / (stats.mOk + stats.mFail), stats.multSum / math.max(1, stats.mOk))
  end
  local t = {}
  for _, k in ipairs(KEYS) do
    if stats.used[k] > 0 then t[#t + 1] = k .. " " .. stats.used[k] end
  end
  if #t > 0 then log("STAT", "расход, L: %s", table.concat(t, ", ")) end
end

---------------------------------------------------------------- UI (T3, 160x50)
local gpu
local C = {
  bg = 0x0F1216, panel = 0x181D24, head = 0x123A5A, fg = 0xD8DEE9, dim = 0x6E7A88,
  acc = 0x4FB3FF, ok = 0x3DDC6B, warn = 0xF2C14E, err = 0xFF5C5C, barbg = 0x2A323C,
  on = 0x2E7D4F, off = 0x262C34,
}
local LEVEL_COLOR = { OK = "ok", INFO = "fg", WARN = "warn", ERR = "err", STAT = "acc" }
local FONT = {
  ["0"] = { "111", "101", "101", "101", "111" }, ["1"] = { "010", "110", "010", "010", "111" },
  ["2"] = { "111", "001", "111", "100", "111" }, ["3"] = { "111", "001", "111", "001", "111" },
  ["4"] = { "101", "101", "111", "001", "001" }, ["5"] = { "111", "100", "111", "001", "111" },
  ["6"] = { "111", "100", "111", "101", "111" }, ["7"] = { "111", "001", "001", "001", "001" },
  ["8"] = { "111", "101", "111", "101", "111" }, ["9"] = { "111", "101", "111", "001", "111" },
  ["%"] = { "101", "001", "010", "100", "101" }, ["-"] = { "000", "000", "111", "000", "000" },
}

local curFg, curBg
local function setFg(c) if c ~= curFg then gpu.setForeground(c); curFg = c end end
local function setBg(c) if c ~= curBg then gpu.setBackground(c); curBg = c end end
local function fit(s, w)
  s = tostring(s)
  local l = uni.len(s)
  if l > w then return uni.sub(s, 1, w) end
  return s .. string.rep(" ", w - l)
end
local function text(x, y, s, w, fg, bg)
  setBg(bg or C.panel); setFg(fg or C.fg)
  gpu.set(x, y, w and fit(s, w) or tostring(s))
end
local function rect(x, y, w, h, bg)
  if w <= 0 or h <= 0 then return end
  setBg(bg); gpu.fill(x, y, w, h, " ")
end
local function bar(x, y, w, frac, col, h)
  frac = math.max(0, math.min(1, frac or 0))
  local n = math.floor(w * frac + 0.5)
  rect(x, y, n, h or 1, col)
  rect(x + n, y, w - n, h or 1, C.barbg)
end
local function bigText(x, y, s, col)
  rect(x, y, 34, 5, C.panel)
  local cx = x
  for ch in s:gmatch(".") do
    local g = FONT[ch]
    if g then
      for r = 1, 5 do
        local c = 1
        while c <= 3 do -- рисуем подряд идущие пиксели одним fill
          if g[r]:sub(c, c) == "1" then
            local e = c
            while e < 3 and g[r]:sub(e + 1, e + 1) == "1" do e = e + 1 end
            rect(cx + (c - 1) * 2, y + r - 1, (e - c + 1) * 2, 1, col)
            c = e + 1
          else
            c = c + 1
          end
        end
      end
      cx = cx + 8
    end
  end
end
local memo = {}
local function once(id, sig, fn)
  if memo[id] ~= sig then memo[id] = sig; fn() end
end

local W, H = 160, 50
local LX, LW = 2, 108   -- левая колонка
local RX, RW = 112, 47  -- правая колонка
local bindRequested = false

local function drawFrame()
  rect(1, 1, W, H, C.bg)
  rect(LX, 3, LW, 4, C.panel)   -- цикл
  rect(LX, 8, LW, 4, C.panel)   -- сигнал
  rect(LX, 13, LW, 5, C.panel)  -- подача
  rect(RX, 3, RW, 15, C.panel)  -- шанс
  rect(LX, 19, LW, 9, C.panel)  -- буферы
  rect(RX, 19, RW, 9, C.panel)  -- статистика
  rect(LX, 29, W - 2, 21, C.panel) -- события
  text(LX + 1, 8, "СИГНАЛ", nil, C.acc)
  text(LX + 1, 19, "БУФЕРЫ", nil, C.acc)
  text(RX + 1, 3, "ШАНС НА ВЫХОД", nil, C.acc)
  text(RX + 1, 19, "СТАТИСТИКА СЕССИИ", nil, C.acc)
  text(LX + 1, 29, "СОБЫТИЯ", nil, C.acc)
  memo = {}
end

local function refreshData()
  local now = computer.uptime()
  if now - state.sensorAt >= 1 then
    state.sensorAt = now
    state.sensor = state.online and readSensor() or nil
  end
  if now - state.buffersAt >= 2 then
    state.buffersAt = now
    for _, key in ipairs(KEYS) do
      local r = routes[key]
      if r then
        local avail, loc, err, net = available(r)
        state.buffers[key] = { avail = avail, loc = loc, net = net, err = err, refill = r.refill, cap = r.cap }
      end
    end
  end
end

local function render()
  refreshData()
  local st = state

  -- шапка
  local right = (st.online and "● ONLINE " or "● OFFLINE") .. "   " .. os.date("%H:%M:%S") .. " "
  once("hdr", right, function()
    rect(1, 1, W, 1, C.head)
    text(2, 1, "DEGASSER · Grade 7 Water · v" .. VERSION, nil, C.fg, C.head)
    text(57, 1, "[ ПРИВЯЗКА ]", nil, C.acc, C.head)
    text(W - uni.len(right) + 1, 1, right, nil, st.online and C.ok or C.err, C.head)
  end)

  -- цикл
  local frac = st.maxp > 0 and st.prog / st.maxp or 0
  once("cyc", table.concat({ st.cycle, st.phase, math.floor(frac * 192), st.maxp }, "|"), function()
    text(LX + 1, 3, "ЦИКЛ #" .. st.cycle, 14, C.acc)
    text(LX + 16, 3, st.phase, LW - 17, C[st.phaseLevel] or C.fg)
    bar(LX + 1, 4, LW - 9, frac, C.acc, 2)
    text(LX + LW - 7, 4, string.format("%5.1f%%", frac * 100), 7, C.fg)
    local left = math.max(0, math.floor((st.maxp - st.prog) / 20))
    text(LX + 1, 6, st.maxp > 0 and string.format("%d / %d тиков · до конца %d с", st.prog, st.maxp, left)
      or "машина простаивает", LW - 2, C.dim)
  end)

  -- сигнал
  once("sig", tostring(st.sig) .. "|" .. st.cycle, function()
    local names = { "ПРОПУСК", "НЕЙТРОНИЙ", "SC BASE", "ГАЗ" }
    for i = 0, 3 do
      local b = 3 - i
      local on = st.sig ~= nil and bit(st.sig, b)
      local x = LX + 1 + i * 22
      rect(x, 9, 20, 2, on and C.on or C.off)
      text(x + 1, 9, string.format("бит %d · %s", b + 1, names[i + 1]), 19, on and C.fg or C.dim, on and C.on or C.off)
      text(x + 1, 10, on and "1" or "0", 19, on and C.ok or C.dim, on and C.on or C.off)
    end
    local s = st.sig and string.format("= %d  [%s]", st.sig, bin4(st.sig)) or "= ?"
    if st.sig == 0 then s = s .. "  все нули → Super Coolant" end
    text(LX + 90, 9, s, LW - 90, C.fg)
    text(LX + 90, 10, st.known and "" or "цикл не отслежен", LW - 90, C.dim)
  end)

  -- подача
  local psig = {}
  for _, s in ipairs(st.plan) do
    psig[#psig + 1] = s[1] .. (st.pumped[s[1]] or 0) .. tostring(st.drained[s[1]])
  end
  once("plan", st.cycle .. "|" .. table.concat(psig, ","), function()
    text(LX + 1, 13, "ПОДАЧА", 8, C.acc)
    text(LX + 10, 13, #st.plan == 0 and (st.sig and bit(st.sig, 3) and "бит 4: ничего не льём, хэтчи пустые"
      or "—") or describe(st.plan), LW - 11, C.dim)
    for i = 1, 3 do
      local y = 13 + i
      local s = st.plan[i]
      if s then
        local key, need = s[1], s[2]
        local got = st.pumped[key] or 0
        local done = st.drained[key]
        text(LX + 1, y, LABEL[key], 15, C.fg)
        bar(LX + 17, y, 56, got / need, done and C.ok or C.acc)
        text(LX + 75, y, fmtNum(got) .. " / " .. fmtNum(need) .. " L", 20, C.fg)
        local stt = done and "✓ слито" or (got >= need and "в хэтче" or (got > 0 and "качаю…" or "ожидание"))
        text(LX + 96, y, stt, LW - 97, done and C.ok or C.dim)
      else
        rect(LX + 1, y, LW - 2, 1, C.panel)
      end
    end
  end)

  -- шанс на выход
  local sen = st.sensor
  local chance = sen and sen.chance
  local tier = scTier()
  local cycleMult = (sen and sen.mult) or ((st.sig and bit(st.sig, 1) and not bit(st.sig, 3) and tier) and tier[2] or 1.0)
  local parallel = sen and sen.parallel
  once("chance", table.concat({ tostring(chance), tostring(st.predChance), tostring(cycleMult),
    tostring(parallel), tier and tier[3] or "-", st.phase }, "|"), function()
    local shown = chance or st.predChance
    local col = shown == nil and C.dim or (shown >= 99.9 and C.ok or (shown > 0 and C.warn or C.err))
    bigText(RX + 2, 5, shown and string.format("%d%%", math.floor(shown + 0.5)) or "--%", col)
    text(RX + 1, 11, chance and "по данным машины (live)" or "машина не отвечает — прогноз", RW - 2, C.dim)
    text(RX + 1, 12, "прогноз программы: " .. (st.predChance and (math.floor(st.predChance) .. "%") or "—"), RW - 2, C.fg)
    text(RX + 1, 13, string.format("множитель цикла ×%.2f", cycleMult), RW - 2, cycleMult > 1 and C.ok or C.fg)
    text(RX + 1, 14, "параллели: " .. (parallel and fmtNum(parallel) or "?"), RW - 2, C.fg)
    if cfg.outputPerParallel and parallel then
      local exp = parallel * cfg.outputPerParallel * cycleMult * ((shown or 0) / 100)
      text(RX + 1, 15, "ожидаемо G7 ≈ " .. fmtNum(exp) .. " L", RW - 2, C.acc)
    else
      text(RX + 1, 15, "outputPerParallel не задан (см. конфиг)", RW - 2, C.dim)
    end
    local avg = tier and (1 + P_SC_BIT * (tier[2] - 1)) or 1
    text(RX + 1, 16, string.format("SC %s · в среднем ×%.2f", tier and tier[3] or "?", avg), RW - 2, C.dim)
  end)

  -- буферы
  local bsig = {}
  for _, key in ipairs(KEYS) do
    local b = st.buffers[key]
    bsig[#bsig + 1] = b and (tostring(b.avail) .. ":" .. tostring(b.loc) .. tostring(b.err)) or "-"
  end
  once("buf", table.concat(bsig, ","), function()
    for i, key in ipairs(KEYS) do
      local y = 19 + i
      local b = st.buffers[key]
      local need = AMOUNT[key]
      text(LX + 1, y, LABEL[key], 15, C.fg)
      if not b then
        text(LX + 17, y, "—", LW - 18, C.dim)
      elseif b.err then
        rect(LX + 17, y, 50, 1, C.err)
        text(LX + 69, y, b.err, LW - 70, C.err)
      elseif b.avail == math.huge then
        -- интерфейс без данных сети: показываем заполненность интерфейса
        local frac = b.cap and b.cap > 0 and b.loc / b.cap or 1
        bar(LX + 17, y, 50, frac, C.ok)
        text(LX + 69, y, fmtNum(b.loc) .. " L", 16, C.fg)
        text(LX + 86, y, "AE доливает", 12, C.dim)
        text(LX + 99, y, "сеть ?", LW - 100, C.dim)
      else
        local uses = math.floor(b.avail / need)
        local col = uses < 1 and C.err or (uses < cfg.lowStockCycles and C.warn or C.ok)
        bar(LX + 17, y, 50, uses / (cfg.lowStockCycles * 4), col)
        text(LX + 69, y, fmtNum(b.avail) .. " L", 16, C.fg)
        text(LX + 86, y, uses >= 1000 and "≥1000 сраб." or (uses .. " сраб."), 12, col)
        local tag = uses < 1 and "ПУСТО" or (uses < cfg.lowStockCycles and "мало" or (b.net and "сеть" or ""))
        text(LX + 99, y, tag, LW - 100, uses < cfg.lowStockCycles and col or C.dim)
      end
    end
  end)

  -- статистика
  local up = computer.uptime() - st.startedAt
  once("stat", table.concat({ stats.cycles, stats.ok, stats.nothing, stats.skipped, stats.failed,
    stats.mOk, stats.mFail, math.floor(up / 60) }, "|"), function()
    local m = stats.mOk + stats.mFail
    local rate = m > 0 and 100 * stats.mOk / m or nil
    local lines = {
      { "циклов отслежено", tostring(stats.cycles), C.fg },
      { "подтверждено машиной", m > 0 and string.format("%d ✓ / %d ✗  (%.1f%%)", stats.mOk, stats.mFail, rate) or "—",
        rate and (rate >= 99.9 and C.ok or C.warn) or C.dim },
      { "средний множитель", stats.mOk > 0 and string.format("×%.3f", stats.multSum / stats.mOk) or "—", C.fg },
      { "залито / бит 4", stats.ok .. " / " .. stats.nothing, C.fg },
      { "пропущено (нехватка)", tostring(stats.skipped), stats.skipped > 0 and C.warn or C.fg },
      { "ошибок подачи", tostring(stats.failed), stats.failed > 0 and C.err or C.fg },
      { "время работы", string.format("%d ч %02d мин", math.floor(up / 3600), math.floor((up % 3600) / 60)), C.dim },
    }
    for i, l in ipairs(lines) do
      text(RX + 1, 19 + i, l[1], 22, C.dim)
      text(RX + 23, 19 + i, l[2], RW - 24, l[3])
    end
  end)

  -- события
  local top = st.events[1]
  once("ev", tostring(#st.events) .. (top and (top.t .. top.msg) or ""), function()
    for i = 1, 20 do
      local e = st.events[i]
      local y = 29 + i
      if e then
        text(LX + 1, y, e.t, 9, C.dim)
        text(LX + 10, y, e.level, 5, C[LEVEL_COLOR[e.level] or "fg"])
        text(LX + 16, y, e.msg, W - LX - 18, C.fg)
      else
        rect(LX + 1, y, W - 4, 1, C.panel)
      end
    end
  end)
end

local renderTimer, oldRes, uiFailed, touchHandler
local function startUI()
  if cfg.ui == false then return end
  if not component.isAvailable("gpu") then return end
  gpu = component.gpu
  local mw, mh = gpu.maxResolution()
  if mw < W or mh < H then
    print(string.format("экран %dx%d < 160x50 (нужны GPU и монитор T3) — работаю без экрана", mw, mh))
    return
  end
  oldRes = { gpu.getResolution() }
  gpu.setResolution(W, H)
  uiFailed = false
  curFg, curBg = nil, nil
  drawFrame()
  ui.on = true
  if event.listen then
    touchHandler = function(_, screen, x, y)
      if ui.on and y == 1 and x >= 57 and x <= 69
        and (not gpu.getScreen or screen == gpu.getScreen()) then
        bindRequested = true
        log("INFO", "запрошена привязка: открою экран после безопасной точки цикла")
      end
    end
    event.listen("touch", touchHandler)
  end
  renderTimer = event.timer(cfg.uiInterval, function()
    if uiFailed then return end
    local ok, err = pcall(render)
    if not ok then
      uiFailed = true
      ui.on = false
      log("ERR", "экран отключён: %s", tostring(err))
    end
  end, math.huge)
end

local function stopUI()
  if renderTimer then event.cancel(renderTimer) end
  if touchHandler and event.ignore then event.ignore("touch", touchHandler) end
  touchHandler = nil
  if gpu and oldRes then
    gpu.setBackground(0x000000); gpu.setForeground(0xFFFFFF)
    gpu.setResolution(oldRes[1], oldRes[2])
    gpu.fill(1, 1, oldRes[1], oldRes[2], " ")
    require("term").setCursor(1, 1)
  end
  ui.on = false
end

---------------------------------------------------------------- cycle
local function resetCycleState()
  state.sig, state.plan, state.pumped, state.drained, state.predChance = nil, {}, {}, {}, nil
end

local function handleCycle()
  stats.cycles = stats.cycles + 1
  local n = stats.cycles
  resetCycleState()
  state.cycle, state.known = n, true
  setPhase("чтение сигнала", "fg")
  os.sleep(cfg.signalDelay)
  local sig = readSignal()
  os.sleep(0.1)
  local sig2 = readSignal()
  if sig2 ~= sig then
    log("WARN", "сигнал нестабилен (%d -> %d), беру последний", sig, sig2)
    sig = sig2
  end

  local plan = planFor(sig)
  state.sig, state.plan = sig, plan
  log("INFO", "цикл #%d  сигнал %2d [%s] -> %s", n, sig, bin4(sig), describe(plan))

  if #plan == 0 then
    stats.nothing = stats.nothing + 1
    if not sinksClean() then rollbackAll("бит 4: хэтчи должны быть пусты") end
    state.predChance = sinksClean() and 100 or 0
    setPhase("бит 4: ничего не льём", "ok")
    return
  end

  local prog, maxp = machineState()
  if not prog or maxp == 0 then
    log("ERR", "машина остановилась — подача отменена"); stats.skipped = stats.skipped + 1
    state.predChance = 0; setPhase("машина остановилась", "err")
    return
  end
  local ticksLeft = maxp - prog
  if ticksLeft < cfg.minTicksToStart then
    log("WARN", "до конца цикла %d тиков < %d — пропуск", ticksLeft, cfg.minTicksToStart)
    stats.skipped = stats.skipped + 1
    state.predChance = 0; setPhase("пропуск: мало времени", "warn")
    return
  end

  if not sinksClean() then
    log("ERR", "в хэтчах уже есть катализатор на старте цикла — цикл испорчен, ничего не лью")
    rollbackAll("грязный хэтч")
    stats.skipped = stats.skipped + 1
    state.predChance = 0; setPhase("пропуск: грязный хэтч", "err")
    return
  end

  -- Проверка запасов ДО подачи: частичная подача = провал + потеря ресурсов
  setPhase("проверка запасов", "fg")
  local missing = false
  for _, s in ipairs(plan) do
    local r = routes[s[1]]
    local avail, loc, err = available(r)
    if err then
      log("ERR", "%s: %s", s[1], err); missing = true
    elseif avail < s[2] then
      log("ERR", "%s: доступно %d L (в источнике %d), нужно %d L", s[1], avail, loc, s[2]); missing = true
    elseif avail ~= math.huge and avail < s[2] * (1 + cfg.lowStockCycles) then
      log("WARN", "%s: запас на %d срабатываний", s[1], math.floor(avail / s[2]))
    end
  end
  if missing then
    log("ERR", "цикл #%d пропущен: ничего не залито (провал неизбежен, ресурсы сохранены)", n)
    stats.skipped = stats.skipped + 1
    state.predChance = 0; setPhase("пропуск: не хватает жидкости", "err")
    return
  end

  setPhase("подача", "acc")
  local deadline = computer.uptime() + (ticksLeft - cfg.pumpReserveTicks) / 20
  for _, s in ipairs(plan) do
    local key, need = s[1], s[2]
    local moved, err = pump(routes[key], need, deadline)
    stats.used[key] = stats.used[key] + moved
    if err then
      log("ERR", "%s: подано %d/%d L — %s", key, moved, need, err)
      stats.failed = stats.failed + 1
      rollbackAll("ошибка подачи")
      state.predChance = 0; setPhase("ошибка подачи", "err")
      return
    end
  end

  setPhase("ожидание слива", "acc")
  stats.ok = stats.ok + 1
  state.predChance = 100
  if waitDrained(plan, cfg.drainTimeout) then
    log("OK", "цикл #%d: подано и слито машиной", n)
    setPhase("готово: всё залито точно", "ok")
  else
    log("WARN", "цикл #%d: подано, но хэтч не слит за %d с (проверю перед концом цикла)", n, cfg.drainTimeout)
    setPhase("подано, хэтч ещё не слит", "warn")
  end
end

-- Перед концом цикла: подтверждение от машины + защита следующего цикла.
local function endOfCycleGuard()
  if state.known then
    local sen = readSensor()
    if sen and sen.chance then
      if sen.chance >= 99.9 then
        stats.mOk = stats.mOk + 1
        local tier = scTier()
        local m = sen.mult or ((state.sig and bit(state.sig, 1) and not bit(state.sig, 3) and tier) and tier[2] or 1.0)
        stats.multSum = stats.multSum + m
      else
        stats.mFail = stats.mFail + 1
        log("ERR", "цикл #%d: машина сообщает шанс %s%% (сигнал %s)", state.cycle, tostring(sen.chance),
          state.sig and bin4(state.sig) or "?")
      end
    end
  end
  if not sinksClean() then rollbackAll("конец цикла") end
end

---------------------------------------------------------------- scan
local function scan()
  print("gt_machine:")
  for a in component.list("gt_machine", true) do
    local ok, info = pcall(component.invoke, a, "getSensorInformation")
    print("  " .. a)
    if ok and type(info) == "table" then
      for i = 1, math.min(info.n or #info, 12) do
        print("      " .. tostring(info[i]):gsub("§.", ""))
      end
    end
  end
  print("redstone:")
  for a in component.list("redstone", true) do
    local ok, all = pcall(component.invoke, a, "getInput")
    local t = {}
    if ok and type(all) == "table" then
      for s = 0, 5 do t[#t + 1] = sides[s] .. "=" .. int(all[s]) end
    end
    print("  " .. a .. "  " .. table.concat(t, " "))
  end
  print("ME (для cfg.me):")
  for _, t in ipairs({ "me_interface", "me_controller", "me_dual_interface" }) do
    for a in component.list(t, true) do
      local ok, list = pcall(component.invoke, a, "getFluidsInNetwork")
      local n = ok and type(list) == "table" and (list.n or #list) or nil
      print(string.format("  %s  %s  жидкостей в сети: %s", a, t, n and tostring(n) or "нет getFluidsInNetwork"))
    end
  end
  print("transposer:")
  for a in component.list("transposer", true) do
    local p = component.proxy(a)
    print("  " .. a)
    for s = 0, 5 do
      local ok, cnt = pcall(p.getTankCount, s)
      if ok and int(cnt) > 0 then
        local t = {}
        for _, f in ipairs(tanksOf(p, s)) do
          t[#t + 1] = string.format("%s %d/%d", f.name, int(f.amount), int(f.capacity))
        end
        print(string.format("    %-6s танков %d: %s", sides[s], int(cnt), #t > 0 and table.concat(t, ", ") or "пусто"))
      end
    end
  end
end

---------------------------------------------------------------- main
local function loadConfig()
  local chunk, err = loadfile(CFG_PATH)
  if not chunk then error("конфиг " .. CFG_PATH .. ": " .. tostring(err), 0) end
  local c = chunk()
  local defaults = {
    pollInterval = 0.25, signalDelay = 0.25, minTicksToStart = 300, pumpReserveTicks = 100,
    guardTicks = 60, drainTimeout = 4, lowStockCycles = 5,
    logFile = "/home/degasser.log", logMaxBytes = 64 * 1024,
    ui = true, uiInterval = 0.5,
    refillSources = false, stallTimeout = 15,
  }
  for k, v in pairs(defaults) do if c[k] == nil then c[k] = v end end
  return bindings.apply(c, bindings.load(BIND_PATH))
end

local ME_TYPES = { "me_interface", "me_controller", "me_dual_interface" }

-- ME-компонент для запаса сети: из конфига или единственный найденный.
local function resolveME()
  if cfg.me == false then return nil end
  local addr
  if cfg.me then
    addr = component.get(cfg.me)
    if not addr then log("WARN", "ME-компонент %s не найден — работаю без данных сети", tostring(cfg.me)); return nil end
  else
    local found = {}
    for _, t in ipairs(ME_TYPES) do
      for a in component.list(t, true) do found[#found + 1] = a end
    end
    if #found == 0 then return nil end
    if #found > 1 then
      log("WARN", "найдено %d ME-компонентов — укажи cfg.me, пока работаю без данных сети", #found)
      return nil
    end
    addr = found[1]
  end
  return component.proxy(addr)
end

local function init()
  machine = resolve(cfg.machine, "gt_machine")
  rs = resolve(cfg.redstone, "redstone")
  if cfg.refillSources or cfg.me then
    me = resolveME()
    local net = me and networkFluids()
    if net then
      log("INFO", "ME-сеть: %s (%s), жидкостей в сети: %s", me.address:sub(1, 8), me.type,
        tostring((function() local n = 0 for _ in pairs(net) do n = n + 1 end return n end)()))
    else
      if me then
        log("WARN", "%s (%s) не отдаёт данные getFluidsInNetwork — работаю без данных сети", me.address:sub(1, 8), me.type)
        me = nil
      end
      log("WARN", "запас ME-сети не виден: предпроверка по заполненности интерфейсов (возможна частичная подача, если сеть пуста)")
    end
  end
  local seen = {}
  for _, key in ipairs(KEYS) do
    local rc = cfg.routes and cfg.routes[key]
    if not rc then error("в конфиге нет маршрута '" .. key .. "'", 0) end
    local r = { key = key, t = resolve(rc.transposer, "transposer"), from = rc.from, to = rc.to, fluid = rc.fluid }
    if rc.refill ~= nil then r.refill = rc.refill else r.refill = cfg.refillSources end
    local id = r.t.address .. ":" .. tostring(r.from)
    if seen[id] then error("маршруты '" .. seen[id] .. "' и '" .. key .. "' берут из одного буфера", 0) end
    seen[id] = key
    local ok, cnt = pcall(r.t.getTankCount, r.to)
    if not ok or int(cnt) == 0 then error(key .. ": на стороне 'to' нет хэтча/танка", 0) end
    routes[key] = r
    local amt, err = sourceStock(r)
    if err then log("WARN", "%s: %s", key, err)
    else log("INFO", "%-14s буфер %7d L  %s", key, amt, fluidName(r) or "(пусто, имя узнаю позже)") end
  end
  -- одинаковые имена жидкостей в разных маршрутах = ошибка разводки
  local names = {}
  for _, key in ipairs(KEYS) do
    local nm = fluidName(routes[key])
    if nm then
      if names[nm] then error("жидкость '" .. nm .. "' в маршрутах '" .. names[nm] .. "' и '" .. key .. "'", 0) end
      names[nm] = key
    end
  end
  local tier = scTier()
  if not tier and fluidName(routes.superconductor) then
    error("неизвестная SC base: " .. tostring(fluidName(routes.superconductor)), 0)
  end
  if tier then log("INFO", "SC base: %s (множитель ×%.2f, в среднем ×%.2f)", tier[3], tier[2], 1 + P_SC_BIT * (tier[2] - 1)) end
end

local function run(opts)
  state.startedAt = computer.uptime()
  log("INFO", "degasser v%s запущен", VERSION)
  init()
  startUI()
  local lastProg, lastMax = nil, 0
  local guarded = false
  while true do
    local prog, maxp = machineState()
    if not prog then
      if state.online then log("ERR", "нет связи с контроллером (adapter?)") end
      state.online = false
    else
      state.online = true
      state.prog, state.maxp = prog, maxp
      if lastProg == nil and maxp > 0 then
        log("INFO", "старт посреди цикла (%d/%d) — жду следующий", prog, maxp)
        state.known = false
      end
      local started = maxp > 0 and lastProg ~= nil and (lastMax == 0 or prog < lastProg)
      lastProg, lastMax = prog, maxp
      if started then
        guarded = false
        handleCycle()
        if stats.cycles % 30 == 0 then printStats() end
        prog, maxp = machineState()
        if prog then lastProg, lastMax, state.prog, state.maxp = prog, maxp, prog, maxp end
      end
      if prog and maxp > 0 and not guarded and maxp - prog <= cfg.guardTicks then
        guarded = true
        endOfCycleGuard()
      end
      if maxp == 0 and state.phase ~= "ожидание старта цикла" and not started then
        setPhase("ожидание старта цикла", "dim")
      end
    end
    if bindRequested and (not prog or maxp == 0 or guarded) then
      bindRequested = false
      stopUI()
      local saved = bindings.run("G7 Degasser", cfg, BIND_PATH, KEYS, "fluid")
      if saved then
        cfg = loadConfig()
        routes, me = {}, nil
        meCache = { at = -100, map = nil }
        init()
      end
      startUI()
      lastProg, lastMax, guarded = nil, 0, false
    end
    if opts and opts.onStatus then
      if computer.uptime() - state.sensorAt >= 5 then
        state.sensorAt = computer.uptime()
        state.sensor = state.online and readSensor() or nil
      end
      opts.onStatus({
        online = state.online, cycle = state.cycle, phase = state.phase,
        progress = state.prog, maxProgress = state.maxp, signal = state.sig,
        success = stats.mOk, failed = stats.mFail,
        parallel = state.sensor and state.sensor.parallel,
      })
    end
    if opts and opts.shouldStop and opts.shouldStop() and (not prog or maxp == 0 or guarded) then
      break
    end
    os.sleep(cfg.pollInterval)
  end
end

local function main(args, opts)
  logSink = opts and opts.onLog or nil
  if args[1] == "scan" then scan(); return end
  cfg = loadConfig()
  if args[1] == "bind" then
    return bindings.run("G7 Degasser", cfg, BIND_PATH, KEYS, "fluid")
  end
  if opts and opts.headless then cfg.ui = false end
  routes, me = {}, nil
  meCache = { at = -100, map = nil }
  local ok, err = xpcall(function() run(opts) end, function(e) return e end)
  stopUI()
  printStats()
  if not ok and not tostring(err):find("interrupted") then log("ERR", "%s", tostring(err)) end
  return ok, err
end

return { main = main }
-- END waterline/g7.lua
