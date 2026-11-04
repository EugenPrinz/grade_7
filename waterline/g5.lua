-- Grade 5 · Extreme Temperature Fluctuation / Plasma Heater (GTNH 2.9, MTEPurificationUnitPlasmaHeater).
-- Every second: up to 10 L Helium Plasma from the plasma hatch (+100 K/L) and up to 100 L
-- Super Coolant from the coolant hatch (-5 K/L), temperature floored at 0 K.
-- A heating cycle is 0 K -> >= 10 000 K -> 0 K and adds +33%; above 12 500 K the batch is ruined.
-- Minimum 10 s heating + 20 s cooling, so 3 cycles (99%) fit into 120 s; water boost gives 100%.
local core = require("waterline.core")
local computer = require("computer")
local spec = require("waterline.registry").byId.g5

local HEAT_POINT, MAX_TEMP = 10000, 12500
local PLASMA_K, COOLANT_K = 100, 5

local impl = {
  defaults = { pollInterval = 0.25, cycleSeconds = 31, maxCycles = 4, safetyMargin = 500,
    stallTimeout = 10, refillSources = true },
  fields = {
    { field = "temp", key = "purification_unit_plasma_heater.temperature",
      words = { "temperature", "температур" }, type = "number" },
    { field = "heated", key = "purification_unit_plasma_heater.heating_cycles",
      words = { "heating cycles", "цикл.*нагрев", "нагрев.*цикл" }, type = "number" },
  },
}

function impl.plasmaFor(temp) return math.max(0, math.ceil((HEAT_POINT - temp) / PLASMA_K)) end
function impl.coolantFor(temp) return math.max(0, math.ceil(temp / COOLANT_K)) end

-- wait until predicate(sensor) or timeout; returns last sensor reading
local function waitFor(ctx, seconds, pred)
  local deadline = computer.uptime() + seconds
  local s
  repeat
    os.sleep(ctx.cfg.pollInterval)
    s = ctx.sensor()
    if s and s.temp then ctx.phase(ctx.data.label .. string.format(" · %d K", s.temp), { temp = s.temp }) end
    if s and pred(s) then return s, true end
  until computer.uptime() > deadline
  return s, false
end

function impl.onCycle(ctx)
  local plasma, coolant = ctx.routes.plasma, ctx.routes.coolant
  local s = ctx.sensor() or {}
  local start = s.chance or 0
  local needed = math.min(ctx.cfg.maxCycles, math.max(0, math.ceil((100 - start) / 33 - 1e-6)))
  ctx.data.start, ctx.data.done = start, 0
  for n = 1, needed do
    local left = ctx.ticksLeft()
    if not left or left < ctx.cfg.cycleSeconds * 20 then
      if n <= 3 then ctx.log("WARN", "цикл %d: на нагрев %d не хватает времени", ctx.cycle, n) end
      break
    end
    s = ctx.sensor() or {}
    local temp = core.int(s.temp)
    if temp ~= 0 or plasma:sink() > 0 or coolant:sink() > 0 then
      ctx.log("ERR", "нагрев %d: старт не с 0 K (%d K) или хэтчи не пусты", n, temp); return
    end
    -- heat
    ctx.data.label = string.format("нагрев %d/%d", n, needed)
    local liters = impl.plasmaFor(temp)
    local avail, _, err = plasma:available(ctx.me)
    if err or avail < liters then ctx.log("ERR", "плазма: %s", err or ("доступно " .. avail .. " L")); return end
    local moved, why = plasma:pump(liters, { stall = ctx.cfg.stallTimeout })
    if why then ctx.log("ERR", "плазма: %d / %d L — %s", moved, liters, why); plasma:rollback(); return end
    local ok
    s, ok = waitFor(ctx, liters / 10 + 4, function(x)
      return core.int(x.temp) >= HEAT_POINT and plasma:sink() == 0
    end)
    temp = s and core.int(s.temp) or 0
    if not ok then
      -- plasma fully drained but short of 10 000 K: top up, never past MAX_TEMP - margin
      if plasma:sink() == 0 and temp < HEAT_POINT then
        local extra = impl.plasmaFor(temp)
        if temp + extra * PLASMA_K <= MAX_TEMP - ctx.cfg.safetyMargin then
          plasma:pump(extra, { stall = ctx.cfg.stallTimeout })
          s, ok = waitFor(ctx, extra / 10 + 4, function(x) return core.int(x.temp) >= HEAT_POINT and plasma:sink() == 0 end)
          temp = s and core.int(s.temp) or temp
        end
      end
      if not ok then ctx.log("ERR", "нагрев %d: %d K, порог 10 000 K не достигнут", n, temp); plasma:rollback(); return end
    end
    if temp > MAX_TEMP then ctx.log("ERR", "перегрев %d K — цикл испорчен", temp); return end
    -- cool
    ctx.data.label = string.format("охлаждение %d/%d", n, needed)
    local cool = impl.coolantFor(temp)
    avail, _, err = coolant:available(ctx.me)
    if err or avail < cool then ctx.log("ERR", "coolant: %s", err or ("доступно " .. avail .. " L")); return end
    moved, why = coolant:pump(cool, { stall = ctx.cfg.stallTimeout })
    if why then ctx.log("ERR", "coolant: %d / %d L — %s", moved, cool, why); coolant:rollback(); return end
    s, ok = waitFor(ctx, cool / 100 + 4, function(x) return core.int(x.temp) == 0 and coolant:sink() == 0 end)
    if not ok then ctx.log("ERR", "охлаждение %d не дошло до 0 K", n); coolant:rollback(); return end
    ctx.data.done = n
    if s.heated and core.int(s.heated) ~= n then
      ctx.log("WARN", "машина насчитала %s циклов нагрева, программа %d", tostring(s.heated), n)
    end
  end
  ctx.phase(string.format("циклов нагрева %d · шанс %s%%", ctx.data.done, tostring((ctx.sensor() or {}).chance)))
end

function impl.onGuard(ctx)
  local p = ctx.routes.plasma:rollback()
  local c = ctx.routes.coolant:rollback()
  if p > 0 or c > 0 then ctx.log("WARN", "возвращено перед концом цикла: плазма %d L, coolant %d L", p, c) end
end

function impl.expectChance(ctx) return (ctx.data.start or 0) + 33 * (ctx.data.done or 0) end

local M = { impl = impl }
function M.main(args, opts) return core.main(spec, impl, args, opts) end
return M
-- END waterline/g5.lua
