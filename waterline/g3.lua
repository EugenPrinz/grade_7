-- Grade 3 · Flocculation (GTNH 2.9, MTEPurificationUnitFlocculation).
-- Polyaluminium Chloride is drained from the hatch every second while running. Each full
-- 100 000 L consumed this cycle adds +10% (base 10%, +15% water boost). A remainder that is
-- not a multiple of 100 000 L multiplies the chance by 2^(-10 * remainder/100000).
-- The module reads the chance at cycle start and doses exactly k * 100 000 L.
local core = require("waterline.core")
local spec = require("waterline.registry").byId.g3

local PER_LEVEL = 100000

local impl = {
  defaults = { pollInterval = 0.5, stallTimeout = 15, reserveTicks = 200, drainTimeout = 6,
    refillSources = true },
  fields = {
    { field = "consumed", key = "purification_unit_flocculation.consumed",
      words = { "consumed", "израсход", "потреблен" }, type = "number" },
  },
}

-- levels needed to reach 100% from `chance`
local function levelsFor(chance)
  if not chance then return 9 end
  return math.max(0, math.ceil((100 - chance) / 10 - 1e-6))
end
impl.levelsFor = levelsFor

function impl.onCycle(ctx)
  local r = ctx.routes.pac
  os.sleep(0.5)
  local s = ctx.sensor() or {}
  local inHatch = r:sink()
  local consumed = core.int(s.consumed)
  -- the start chance is base (+boost) only while nothing was consumed; otherwise assume base 10%
  local chance0 = consumed == 0 and s.chance or nil
  local levels = levelsFor(chance0)
  local total = math.max(levels, math.ceil((consumed + inHatch) / PER_LEVEL)) * PER_LEVEL
  local need = total - consumed - inHatch
  ctx.data.target, ctx.data.chance0 = total, chance0
  if need <= 0 then ctx.phase("PAC не нужен"); return end
  local avail, _, err = r:available(ctx.me)
  if err then ctx.log("ERR", "PAC: %s", err); ctx.phase("ошибка источника PAC"); return end
  if avail < need then
    -- partial levels still help, but only whole multiples of 100 000 L
    local whole = math.floor(avail / PER_LEVEL) * PER_LEVEL
    ctx.log("WARN", "PAC: доступно %d L, нужно %d L — лью %d L", avail, need, whole)
    need = whole
    ctx.data.target = consumed + inHatch + need
    if need == 0 then ctx.phase("нет PAC"); return end
  end
  ctx.phase(string.format("PAC: %d уровней, лью %d L", levels, need))
  local moved, why = r:pump(need, { stall = ctx.cfg.stallTimeout, abort = ctx.abortIfLate(ctx.cfg.reserveTicks),
    onProgress = function(m) ctx.phase(string.format("PAC %d / %d L", m, need)) end })
  if why then
    ctx.log("ERR", "PAC: подано %d / %d L — %s; возвращаю остаток из хэтча", moved, need, why)
    r:rollback()
    return
  end
  local deadline = require("computer").uptime() + ctx.cfg.drainTimeout + need / 20000
  repeat
    os.sleep(0.5)
    s = ctx.sensor() or {}
  until (r:sink() == 0 and core.int(s.consumed) >= ctx.data.target) or require("computer").uptime() > deadline
  local got = core.int(s.consumed)
  if got == ctx.data.target then
    ctx.phase(string.format("PAC %d L ✓ · шанс %s%%", got, tostring(s.chance)))
  else
    ctx.log("WARN", "PAC: машина насчитала %d L, ожидалось %d L", got, ctx.data.target)
    ctx.phase(string.format("PAC %d / %d L", got, ctx.data.target))
  end
end

function impl.onGuard(ctx)
  local back, left = ctx.routes.pac:rollback()
  if back > 0 then ctx.log("WARN", "PAC: %d L возвращено из хэтча перед концом цикла", back) end
  if left > 0 then ctx.log("ERR", "PAC: %d L осталось в хэтче — испортит следующий цикл", left) end
end

function impl.expectChance(ctx)
  local c0 = ctx.data.chance0 or 10
  return math.min(100, c0 + 10 * math.floor((ctx.data.target or 0) / PER_LEVEL))
end

local M = { impl = impl }
function M.main(args, opts) return core.main(spec, impl, args, opts) end
return M
-- END waterline/g3.lua
