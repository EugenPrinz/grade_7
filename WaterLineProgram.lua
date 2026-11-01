-- Single OpenOS entry point for all water-line grade modules.
local VERSION = "2.0.1"
package.path = package.path .. ";/home/lib/?.lua"
require("waterline.main").main({...})
-- END WaterLineProgram.lua
