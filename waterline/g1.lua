-- Grade 1 · Clarifier (GTNH 2.9). Nothing to regulate: the Activated Carbon Filter Mesh is
-- consumed with a 20% chance per cycle, base success 70% (+15% water boost).
-- The module only reports the machine's chance and parallel.
local core = require("waterline.core")
local spec = require("waterline.registry").byId.g1

local impl = { defaults = { pollInterval = 1 }, fields = {} }

function impl.onCycle(ctx)
  os.sleep(1)
  local s = ctx.sensor()
  ctx.data.base = s and s.chance
  ctx.phase(s and s.chance and string.format("пассивный · шанс %s%%", s.chance) or "пассивный юнит",
    { chance = s and s.chance })
end

function impl.expectChance(ctx) return ctx.data.base or 70 end

local M = { impl = impl }
function M.main(args, opts) return core.main(spec, impl, args, opts) end
return M
-- END waterline/g1.lua
