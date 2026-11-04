-- Every waterline module, registry entry and launcher is installed; every file ends with its END marker.
package.path = "./?.lua;" .. package.path
local function read(p) local f = assert(io.open(p)); local d = f:read("*a"); f:close(); return d end
local install = read("install.lua")
local listed = {}
for name in install:gmatch('name = "([^"]+)"') do listed[name] = true end

local p = io.popen("ls waterline")
for file in p:lines() do
  if file:match("%.lua$") then
    assert(listed["waterline/" .. file], "install.lua does not install waterline/" .. file)
  end
end
p:close()

local registry = require("waterline.registry")
for _, spec in ipairs(registry.grades) do
  local file = spec.module:gsub("%.", "/") .. ".lua"
  assert(listed[file], "registry module " .. spec.module .. " is not installed")
  assert(io.open(file), "registry module file missing: " .. file)
  assert(registry.find(spec.grade) == spec and registry.find("G" .. spec.grade) == spec, "find() for " .. spec.id)
end
for name in pairs(listed) do
  local src = read(name)
  assert(src:find("%-%- END " .. name:gsub("%p", "%%%0") .. "%s*$"), name .. " has no END marker")
end
print("install manifest: OK")
