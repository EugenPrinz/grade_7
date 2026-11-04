-- Grade 4 · pH Neutralization (GTNH 2.9, MTEPurificationUnitPhAdjustment).
-- At cycle start pH = 7 ± 2.5 (two decimals). Every second the machine consumes all
-- Sodium Hydroxide dust in its alkaline bus (+0.01 pH each) and all Hydrochloric Acid in its
-- acid hatch (-0.01 pH per full 10 L; the remainder is wasted). Success is 100% when
-- |pH - 7| <= 0.05 at cycle end, otherwise 0%. Closed loop: read pH, dose, settle, re-read.
local core = require("waterline.core")
local computer = require("computer")
local spec = require("waterline.registry").byId.g4

local impl = {
  defaults = { pollInterval = 0.5, tolerance = 0.02, settle = 2.5, maxRounds = 8,
    reserveTicks = 100, stallTimeout = 15, refillSources = true },
  fields = {
    { field = "ph", key = "purification_unit_ph_adjustment.ph", words = { "%f[%a]ph%f[%A]" }, type = "number" },
  },
}

local function round(x) return math.floor(x + 0.5) end

-- dose for a measured pH: { kind = "naoh"|"hcl"|nil, amount }
function impl.doseFor(ph, tolerance)
  local dev = ph - 7
  if math.abs(dev) <= (tolerance or 0.02) + 1e-9 then return nil, 0 end
  if dev < 0 then return "naoh", round(-dev * 100) end
  return "hcl", round(dev * 100) * 10
end

-- pH once the bus and hatch are empty and two readings a second apart agree
local function stablePh(ctx)
  local naoh, hcl = ctx.routes.naoh, ctx.routes.hcl
  local deadline = computer.uptime() + 8
  local prev, busy
  while computer.uptime() < deadline do
    busy = naoh:count(naoh.to) > 0 or hcl:sink() > 0
    if not busy then
      local s = ctx.sensor()
      local ph = s and s.ph
      if ph and prev and math.abs(ph - prev) < 1e-6 then return ph end
      prev = ph
    end
    os.sleep(1.1)
  end
  if busy then return nil, "реагент не уходит из баса/хэтча — машина его не принимает" end
  return prev, prev == nil and "pH не читается со сканера" or nil
end

function impl.onCycle(ctx)
  local naoh, hcl = ctx.routes.naoh, ctx.routes.hcl
  os.sleep(ctx.cfg.settle)
  for round_ = 1, ctx.cfg.maxRounds do
    local ph, why = stablePh(ctx)
    if not ph then ctx.log("ERR", "%s", why); ctx.phase(why); return end
    ctx.data.ph = ph
    local kind, amount = impl.doseFor(ph, ctx.cfg.tolerance)
    if not kind then
      ctx.phase(string.format("pH %.2f ✓", ph), { ph = ph })
      if round_ > 1 then ctx.log("OK", "цикл %d: pH %.2f за %d шаг(а)", ctx.cycle, ph, round_ - 1) end
      return
    end
    ctx.phase(string.format("pH %.2f → %s %d", ph, kind == "naoh" and "NaOH ×" or "HCl L", amount), { ph = ph })
    -- A partial dose is safe here: the next round re-reads pH and doses the rest,
    -- so a Dual Interface that holds less than one full correction still works.
    local moved, why
    local abort = ctx.abortIfLate(ctx.cfg.reserveTicks)
    if kind == "naoh" then
      if naoh:count() == 0 and ctx.cfg.refillSources == false then
        ctx.log("ERR", "NaOH: источник пуст"); ctx.phase("нет NaOH"); return
      end
      moved, why = naoh:move(amount, nil, { stall = ctx.cfg.stallTimeout, abort = abort })
    else
      local avail, _, err = hcl:available(ctx.me)
      if err or avail == 0 then
        ctx.log("ERR", "HCl: %s", err or "источник пуст"); ctx.phase("нет HCl"); return
      end
      -- whole multiples of 10 L only: the remainder is drained without effect
      moved, why = hcl:pump(math.min(amount, math.floor(math.min(avail, amount) / 10) * 10),
        { stall = ctx.cfg.stallTimeout, abort = abort })
    end
    if why then
      if moved == 0 then ctx.log("ERR", "%s: ничего не подано — %s", kind, why); ctx.phase(kind .. ": " .. why); return end
      ctx.log("WARN", "%s: подано %d из %d — %s, доберу на следующем шаге", kind, moved, amount, why)
    end
    os.sleep(ctx.cfg.settle)
  end
  ctx.log("ERR", "цикл %d: pH не сошёлся за %d шагов (%.2f)", ctx.cycle, ctx.cfg.maxRounds, ctx.data.ph or -1)
end

function impl.onGuard(ctx)
  local back = ctx.routes.hcl:rollback()
  local items = ctx.routes.naoh:rollback()
  if back > 0 or items > 0 then ctx.log("WARN", "возвращено перед концом цикла: HCl %d L, NaOH %d", back, items) end
end

function impl.expectChance() return 100 end

local M = { impl = impl }
function M.main(args, opts) return core.main(spec, impl, args, opts) end
return M
-- END waterline/g4.lua
