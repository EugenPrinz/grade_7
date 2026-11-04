-- Grade 2 · Ozonation (GTNH 2.9, MTEPurificationUnitOzonation).
-- The recipe is picked at cycle start by the ozone stored: 128k / 256k / 512k / 1 024k L
-- give 20 / 40 / 60 / 80% (+15% water boost). Ozone above 1 024 000 L in one hatch explodes
-- the multiblock. The module keeps the ozone hatch topped up to exactly `ozoneTarget`
-- at any time and never above it; an over-full hatch is drained back immediately.
local core = require("waterline.core")
local spec = require("waterline.registry").byId.g2

local MAX_OZONE = 1024000 -- MAX_OZONE_GAS_FOR_EXPLOSION; "amount > MAX" explodes
local TIERS = { 128000, 256000, 512000, 1024000 }

local impl = {
  defaults = { ozoneTarget = MAX_OZONE, minTopUp = 1000, pollInterval = 0.5, stallTimeout = 15,
    refillSources = true },
  fields = {},
}

local function chanceFor(target)
  local best = 0
  for i, t in ipairs(TIERS) do if target >= t then best = i * 20 end end
  return best
end
impl.chanceFor = chanceFor

function impl.init(ctx)
  local cfg, r = ctx.cfg, ctx.routes.ozone
  local target = tonumber(cfg.ozoneTarget) or MAX_OZONE
  local valid = false
  for _, t in ipairs(TIERS) do if t == target then valid = true end end
  if not valid then error("ozoneTarget должен быть одним из 128000/256000/512000/1024000", 0) end
  local _, _, cap = r:sink()
  if cap and cap < target then
    local fit = 0
    for _, t in ipairs(TIERS) do if t <= cap then fit = t end end
    if fit == 0 then error(string.format("ёмкость хэтча озона %d L меньше 128 000 L", cap), 0) end
    ctx.log("WARN", "хэтч озона вмещает %d L < %d L — цель снижена до %d L (%d%%)", cap, target, fit, chanceFor(fit))
    target = fit
  end
  ctx.target = target
  ctx.log("INFO", "цель озона %d L → базовый шанс %d%%", target, chanceFor(target))
end

-- Called on every poll, in and between cycles.
function impl.onIdle(ctx)
  local r = ctx.routes.ozone
  local mine, foreign = r:sink()
  if mine > MAX_OZONE then
    local _, back = r.t.transferFluid(r.to, r.from, mine - ctx.target)
    local after = r:sink()
    ctx.log("ERR", "в хэтче %d L озона > %d — слито %s L обратно, осталось %d", mine, MAX_OZONE, tostring(back), after)
    if after > MAX_OZONE and ctx.machine.setWorkAllowed then
      pcall(ctx.machine.setWorkAllowed, false)
      ctx.log("ERR", "G2 остановлен: убери лишний озон вручную")
    end
    return
  end
  if foreign > 0 then
    ctx.phase("в хэтче озона чужая жидкость — подача остановлена")
    return
  end
  local need = ctx.target - mine
  if need < ctx.cfg.minTopUp then
    ctx.phase(string.format("озон %d / %d L · готов (%d%%)", mine, ctx.target, chanceFor(mine)))
    return
  end
  local avail, _, err = r:available(ctx.me)
  if err then ctx.phase("источник: " .. err); return end
  if avail < need then
    ctx.phase(string.format("мало озона: доступно %d L, нужно %d L", avail == math.huge and -1 or avail, need))
    return
  end
  ctx.phase(string.format("долив озона %d → %d L", mine, ctx.target))
  local moved, why = r:pump(need, { stall = ctx.cfg.stallTimeout,
    abort = function()
      if r:sink() > ctx.target then return "уровень в хэтче выше цели" end
      return nil
    end })
  if why then ctx.log("WARN", "озон: долито %d / %d L — %s", moved, need, why) end
end

function impl.expectChance(ctx) return chanceFor(ctx.target or MAX_OZONE) end

local M = { impl = impl }
function M.main(args, opts) return core.main(spec, impl, args, opts) end
return M
-- END waterline/g2.lua
