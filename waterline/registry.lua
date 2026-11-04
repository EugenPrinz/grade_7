-- Single list of water-line grades. main, bindings, install and commands read it;
-- adding a grade means adding a row here and a module file.
--
-- roles: what "bind" asks for besides the controller.
--   kind = "fluid" | "item"
--   slot = "fixed"    one chosen source slot (G8 catalysts)
--          "identity" any source slot holding the same item as the one chosen at bind time (NaOH)
--          "any"      source inventory as a whole, items are picked by name at run time (UV lenses)
--   optional = true   the grade works without this role
local M = {}

M.grades = {
  { id = "g1", grade = 1, short = "Clarifier", name = "Grade 1 · Clarifier",
    module = "waterline.g1", roles = {} },
  { id = "g2", grade = 2, short = "Ozonation", name = "Grade 2 · Ozonation",
    module = "waterline.g2", me = true,
    roles = { { id = "ozone", kind = "fluid", label = "Ozone" } } },
  { id = "g3", grade = 3, short = "Flocculation", name = "Grade 3 · Flocculation",
    module = "waterline.g3", me = true,
    roles = { { id = "pac", kind = "fluid", label = "Polyaluminium Chloride" } } },
  { id = "g4", grade = 4, short = "pH", name = "Grade 4 · pH Neutralization",
    module = "waterline.g4", me = true,
    roles = {
      { id = "naoh", kind = "item", slot = "identity", label = "Sodium Hydroxide Dust" },
      { id = "hcl", kind = "fluid", label = "Hydrochloric Acid" },
    } },
  { id = "g5", grade = 5, short = "Plasma Heater", name = "Grade 5 · Plasma Heater",
    module = "waterline.g5", me = true,
    roles = {
      { id = "plasma", kind = "fluid", label = "Helium Plasma" },
      { id = "coolant", kind = "fluid", label = "Super Coolant" },
    } },
  { id = "g6", grade = 6, short = "UV Treatment", name = "Grade 6 · UV Treatment",
    module = "waterline.g6",
    roles = { { id = "lens", kind = "item", slot = "any", label = "Сундук с 9 линзами → Lens Housing" } } },
  { id = "g7", grade = 7, short = "Degasser", name = "Grade 7 · Degasser",
    module = "waterline.g7", legacy = true },
  { id = "g8", grade = 8, short = "Baryonic", name = "Grade 8 · Baryonic Perfection",
    module = "waterline.g8", legacy = true },
}

M.byId = {}
for i, spec in ipairs(M.grades) do
  spec.index = i
  M.byId[spec.id] = spec
end

-- "g4", "G4", "4", 4 -> spec
function M.find(value)
  if value == nil then return nil end
  local s = tostring(value):lower()
  local n = tonumber(s:match("^g?(%d)$"))
  if n then s = "g" .. n end
  return M.byId[s]
end

function M.ids()
  local out = {}
  for _, spec in ipairs(M.grades) do out[#out + 1] = spec.id end
  return table.concat(out, "|")
end

return M
-- END waterline/registry.lua
