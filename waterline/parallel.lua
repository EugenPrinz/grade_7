-- The 2.9 water recipes use 1000 L input and yield 900 L output per parallel.
-- These are theoretical throughput minima at 100% success, not machine settings.
local M = {}
function M.plan(grade, parallels)
  grade, parallels = tonumber(grade), tonumber(parallels)
  if not grade or grade % 1 ~= 0 or grade < 1 or grade > 8 then error("grade должен быть 1..8", 0) end
  if not parallels or parallels % 1 ~= 0 or parallels < 1 then error("параллели должны быть >= 1", 0) end
  local result = { [grade] = parallels }
  for g = grade - 1, 1, -1 do
    result[g] = math.ceil(result[g + 1] * 1000 / 900)
  end
  for g = grade + 1, 8 do
    result[g] = math.floor(result[g - 1] * 900 / 1000)
  end
  return result
end
return M
-- END waterline/parallel.lua
