-- Single OpenOS entry point for all water-line grade modules.
local VERSION = "2.1.0"
package.path = package.path .. ";/home/lib/?.lua"
-- OpenOS shares package.loaded across programs, so reload updated modules after install.
for name in pairs(package.loaded) do
  if name:match("^waterline%.") then package.loaded[name] = nil end
end
require("waterline.main").main({...})
-- END WaterLineProgram.lua
