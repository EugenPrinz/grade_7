-- Grade 8 entry point. Configure in-game with: grade8 bind
local VERSION = "2.0.0"
package.path = package.path .. ";/home/lib/?.lua"
require("waterline.g8").main({...})
-- END grade8.lua
