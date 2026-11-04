-- End-to-end binding test with a fake OC screen and components.
local path = "test/bindings-test-output.lua"
os.remove(path); os.remove(path .. ".bak"); os.remove(path .. ".tmp")

local sides = { down = 0, up = 1, north = 2, south = 3, west = 4, east = 5 }
for name, id in pairs(sides) do sides[id] = name end
local keys = {
  { "key_down", "kb", 0, 28 }, -- controller
  { "key_down", "kb", 0, 28 }, -- gt_machine
  { "touch", "screen", 4, 7, 0 }, -- coolant route
  { "key_down", "kb", 0, 28 }, -- transposer
  { "key_down", "kb", 0, 208 }, -- north source
  { "key_down", "kb", 0, 28 },
  { "key_down", "kb", 0, 28 }, -- up destination
  { "key_down", "kb", 115, 31 }, -- save
  { "key_down", "kb", 0, 1 }, -- exit
}
local gt = { address = "gt-machine", type = "gt_machine" }
local trans = {
  address = "transposer-a", type = "transposer",
  getTankCount = function(side) return (side == sides.up or side == sides.north) and 1 or 0 end,
  getFluidInTank = function(side)
    if side == sides.north then return { { name = "supercoolant", amount = 16000 } } end
    return {}
  end,
  getInventorySize = function(side) return (side == sides.up or side == sides.north) and 4 or 0 end,
  getStackInSlot = function(side, slot)
    if side == sides.north and slot == 1 then
      return { name = "gregtech:gt.metaitem.03", label = "Up Quark", damage = 32235, size = 3 }
    end
  end,
}
local gpu = {
  maxResolution = function() return 160, 50 end,
  getResolution = function() return 80, 25 end,
  setResolution = function() end, setBackground = function() end,
  setForeground = function() end, fill = function() end, set = function() end,
  getScreen = function() return "screen" end,
}
package.loaded.component = {
  gpu = gpu,
  isAvailable = function(t) return t == "gpu" end,
  list = function(t)
    local items = t == "gt_machine" and { gt.address } or (t == "transposer" and { trans.address } or {})
    local i = 0
    return function() i = i + 1; return items[i] end
  end,
  get = function(a) return a end,
  proxy = function(a) return a == gt.address and gt or trans end,
  invoke = function() return { "Grade 7 Degasser" } end,
}
package.loaded.event = { pull = function() local k = table.remove(keys, 1); assert(k, "UI waited for extra event"); return table.unpack(k) end }
package.loaded.sides = sides
package.loaded.unicode = { sub = function(s, i, j) return s:sub(i, j) end }
package.loaded.filesystem = {
  exists = function(p) local f = io.open(p, "r"); if f then f:close(); return true end return false end,
  remove = os.remove, rename = os.rename,
}
package.loaded.serialization = {
  serialize = function(t)
    local parts = {}
    for k, v in pairs(t) do
      local key = "[" .. string.format("%q", k) .. "]"
      if type(v) == "table" then
        local fields = {}
        for fk, fv in pairs(v) do
          if type(fv) == "table" then
            local inner = {}
            for ik, iv in pairs(fv) do inner[#inner + 1] = "[" .. string.format("%q", ik) .. "]=" ..
              (type(iv) == "string" and string.format("%q", iv) or tostring(iv)) end
            fields[#fields + 1] = "[" .. string.format("%q", fk) .. "]={" .. table.concat(inner, ",") .. "}"
          else fields[#fields + 1] = "[" .. string.format("%q", fk) .. "]=" ..
            (type(fv) == "string" and string.format("%q", fv) or tostring(fv)) end
        end
        parts[#parts + 1] = key .. "={" .. table.concat(fields, ",") .. "}"
      else parts[#parts + 1] = key .. "=" .. string.format("%q", v) end
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end,
}

local binding = require("waterline.bindings")
local original = { machine = "old-machine", routes = { coolant = { fluid = "old", transposer = "old-transposer" } } }
binding.run("G7", original, path, { "coolant" }, "fluid")
local saved = binding.load(path)
local cfg = binding.apply(original, saved)
assert(cfg.machine == gt.address, "controller binding was not saved")
assert(cfg.routes.coolant.transposer == trans.address, "transposer binding was not saved")
assert(cfg.routes.coolant.from == sides.north and cfg.routes.coolant.to == sides.up, "sides were not saved")
assert(cfg.routes.coolant.fluid == "supercoolant", "detected fluid was not saved")
assert(original.machine == "old-machine", "applying bindings changed original config")
os.remove(path)
keys = {
  { "touch", "screen", 4, 4, 0 }, -- up catalyst
  { "key_down", "kb", 0, 28 }, -- transposer
  { "key_down", "kb", 0, 208 }, -- north source
  { "key_down", "kb", 0, 28 },
  { "key_down", "kb", 0, 28 }, -- matching source slot
  { "key_down", "kb", 0, 28 }, -- up destination
  { "key_down", "kb", 115, 31 }, -- save
  { "key_down", "kb", 0, 1 }, -- exit
}
binding.run("G8", { routes = { up = {} } }, path, { "up" }, "item", { up = { damage = 32235 } })
local item = binding.load(path).routes.up
assert(item.transposer == trans.address and item.from == sides.north and item.to == sides.up
  and item.slot == 1, "G8 item source/slot binding was not saved")
os.remove(path)

-- New role form (G4 / G6): per-role kind, identity item without a slot, whole-inventory source.
local function ser(v)
  if type(v) == "table" then
    local parts = {}
    for k, x in pairs(v) do parts[#parts + 1] = "[" .. ser(k) .. "]=" .. ser(x) end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return type(v) == "string" and string.format("%q", v) or tostring(v)
end
package.loaded.serialization = { serialize = ser }
keys = {
  { "touch", "screen", 4, 5, 0 }, -- role 3: naoh (after controller, ME)
  { "key_down", "kb", 0, 28 }, -- transposer
  { "key_down", "kb", 0, 208 }, -- north source
  { "key_down", "kb", 0, 28 },
  { "key_down", "kb", 0, 28 }, -- slot 1 defines the item identity
  { "key_down", "kb", 0, 28 }, -- up destination
  { "touch", "screen", 4, 6, 0 }, -- role 4: lens chest
  { "key_down", "kb", 0, 28 }, -- transposer
  { "key_down", "kb", 0, 208 }, -- north source, no slot question
  { "key_down", "kb", 0, 28 },
  { "key_down", "kb", 0, 28 }, -- up destination
  { "key_down", "kb", 115, 31 }, -- save
  { "key_down", "kb", 0, 1 }, -- exit
}
local roles = {
  { id = "naoh", kind = "item", slot = "identity", label = "Sodium Hydroxide Dust" },
  { id = "lens", kind = "item", slot = "any", label = "Линзы" },
  { id = "hcl", kind = "fluid", label = "HCl" },
}
binding.run("G4", { routes = {} }, path, roles, { me = true })
local r = binding.load(path).routes
assert(r.naoh and r.naoh.from == sides.north and r.naoh.to == sides.up and r.naoh.slot == nil,
  "identity item route was not saved")
assert(r.naoh.item and r.naoh.item.damage == 32235 and r.naoh.item.label == "Up Quark",
  "item identity was not captured from the chosen slot")
assert(r.lens and r.lens.from == sides.north and r.lens.slot == nil and r.lens.item == nil,
  "whole-inventory route must not store a slot or identity")
assert(#keys == 0, "binding UI asked for unexpected input")
os.remove(path); os.remove(path .. ".bak")
print("binding UI: OK")
