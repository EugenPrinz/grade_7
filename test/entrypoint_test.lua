-- A program started after an upgrade must use the files on disk, not cached modules.
local cachedMain = package.loaded["waterline.main"]
local cachedDisplay = package.loaded["waterline.display"]
local preloadMain = package.preload["waterline.main"]
local preloadDisplay = package.preload["waterline.display"]
local called = false

package.loaded["waterline.main"] = {
  main = function() error("stale main module was used") end,
}
package.loaded["waterline.display"] = { version = 1 }
package.preload["waterline.display"] = function() return { version = 2 } end
package.preload["waterline.main"] = function()
  return {
    main = function(args)
      assert(args[1] == "screens", "screens argument was lost")
      assert(require("waterline.display").version == 2, "stale display module was used")
      called = true
    end,
  }
end

local ok, err = pcall(function() assert(loadfile("WaterLineProgram.lua"))("screens") end)
package.loaded["waterline.main"] = cachedMain
package.loaded["waterline.display"] = cachedDisplay
package.preload["waterline.main"] = preloadMain
package.preload["waterline.display"] = preloadDisplay
assert(ok, tostring(err))
assert(called, "new main module was not called")
print("entrypoint refresh after upgrade: OK")
