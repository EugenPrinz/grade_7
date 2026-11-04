-- Grade 6 · High Energy Laser / UV Treatment (GTNH 2.9, MTEPurificationUnitUVTreatment).
-- The machine requests 9 lenses in a fixed order (Orundum, Amber, Infused Air, Emerald,
-- Mana Diamond, Blue Topaz, Amethyst, Fluor-Buergerite, Dilithium). After a requested lens is
-- inserted it must stay 3.75–15 s; each accepted swap is +10%, removing it early fails the batch.
-- The module reads the requested lens from the scanner and swaps it from a chest into the
-- Lens Housing. It only swaps when the requested name matches a lens it can see, so a
-- misread never pulls the current lens out during its countdown.
local core = require("waterline.core")
local spec = require("waterline.registry").byId.g6

local impl = {
  defaults = { pollInterval = 0.25 },
  fields = {
    { field = "requested", key = "purification_unit_uv_treatment.lens_requested",
      words = { "lens requested", "requested", "запрош", "требуется" }, type = "text" },
    { field = "swaps", key = "purification_unit_uv_treatment.lens_swaps", type = "number" },
    { field = "early", key = "purification_unit_uv_treatment.removed_too_early",
      words = { "too early", "слишком рано" }, type = "flag" },
  },
}

local function norm(s) return (core.lower(core.clean(s)):gsub("^%s+", ""):gsub("%s+$", "")) end
impl.norm = norm

-- 1-slot lens housing content
local function housing(r)
  local ok, st = pcall(r.t.getStackInSlot, r.to, 1)
  if ok and st and core.int(st.size) > 0 then return st end
  return nil
end

function impl.onCycle(ctx)
  local r = ctx.routes.lens
  ctx.data.swaps = 0
  ctx.data.start = (ctx.sensor() or {}).chance or 0
  while true do
    local left = ctx.ticksLeft()
    if not left or left <= ctx.cfg.guardTicks + 10 then break end
    local s = ctx.sensor()
    if s and s.early then
      ctx.log("ERR", "цикл %d: машина сообщает, что линзу вынули рано", ctx.cycle)
      ctx.phase("линза вынута рано — цикл потерян")
      return
    end
    local want = s and s.requested and norm(s.requested)
    if want and want ~= "" then
      local cur = housing(r)
      local curName = cur and norm(cur.label or cur.name)
      if curName ~= want then
        -- find the requested lens in the chest; act only on an exact name match
        local slot
        for _, e in ipairs(r:stacks(r.from)) do
          if norm(e.stack.label or e.stack.name) == want then slot = e.slot; break end
        end
        if not slot then
          if ctx.data.missing ~= want then
            ctx.log("ERR", "в сундуке нет линзы «%s»", s.requested)
            ctx.data.missing = want
          end
          ctx.phase("нет линзы: " .. s.requested)
        else
          if cur then
            local ok, back = pcall(r.t.transferItem, r.to, r.from, 1, 1)
            if not ok or core.int(back) ~= 1 then
              ctx.log("ERR", "не удалось вынуть линзу из housing (сундук полон?)")
              ctx.phase("ошибка: housing не освобождается")
              os.sleep(1)
              cur = false
            end
          end
          local ok, put = false, 0
          if cur ~= false then ok, put = pcall(r.t.transferItem, r.from, r.to, 1, slot)
          end
          if cur == false then
            -- housing is still occupied; retry on the next poll
          elseif ok and core.int(put) == 1 then
            ctx.data.swaps = ctx.data.swaps + 1
            ctx.data.missing = nil
            ctx.phase(string.format("линза %d: %s", ctx.data.swaps, s.requested), { lens = s.requested })
          else
            ctx.log("ERR", "не удалось вставить «%s»", s.requested)
          end
        end
      end
    end
    os.sleep(ctx.cfg.pollInterval)
  end
  local s = ctx.sensor() or {}
  ctx.phase(string.format("замен %d · шанс %s%%", ctx.data.swaps, tostring(s.chance)))
end

function impl.expectChance(ctx) return (ctx.data.start or 0) + 10 * math.min(9, ctx.data.swaps or 0) end

local M = { impl = impl }
function M.main(args, opts) return core.main(spec, impl, args, opts) end
return M
-- END waterline/g6.lua
