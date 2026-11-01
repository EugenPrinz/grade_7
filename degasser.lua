-- Grade 7 entry point. Modules live in /home/lib/waterline after installation.
local VERSION = "2.0.0"
package.path = package.path .. ";/home/lib/?.lua"
require("waterline.g7").main({...})
-- END degasser.lua
