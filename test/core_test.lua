-- core.parseSensor / number parsing and the dose formulas of G2–G5.
package.path = "./?.lua;" .. package.path
package.loaded.component = {}
package.loaded.computer = { uptime = function() return 0 end }
package.loaded.sides = {}
local core = require("waterline.core")

local function eq(a, b, msg) assert(a == b, string.format("%s: %s ~= %s", msg, tostring(a), tostring(b))) end

eq(core.lastNumber("Current Parallel: 1,024"), 1024, "thousands")
eq(core.lastNumber("Current pH Value: 7.03 pH"), 7.03, "decimal")
eq(core.lastNumber("множитель 1,5"), 1.5, "comma decimal")
eq(core.lastNumber("Current temperature: 10000K"), 10000, "unit suffix")

local fields = {
  { field = "ph", key = "purification_unit_ph_adjustment.ph", words = { "%f[%a]ph%f[%A]" }, type = "number" },
  { field = "temp", key = "purification_unit_plasma_heater.temperature", words = { "temperature", "температур" }, type = "number" },
  { field = "requested", key = "purification_unit_uv_treatment.lens_requested", words = { "lens requested", "запрош" }, type = "text" },
  { field = "early", key = "purification_unit_uv_treatment.removed_too_early", words = { "too early" }, type = "flag" },
  { field = "consumed", key = "purification_unit_flocculation.consumed", words = { "consumed" }, type = "number" },
}
local raw = core.parseSensor({
  "GT5U.infodata.purification_unit_base.linked_at\\\\1\\\\2\\\\3",
  "GT5U.infodata.purification_unit_base.success_chance\\\\§e99.0%§r",
  "GT5U.infodata.parallel.current\\\\§e1,024",
  "GT5U.infodata.purification_unit_ph_adjustment.ph\\\\§e6.87",
  "GT5U.infodata.purification_unit_plasma_heater.temperature\\\\§e12000",
  "GT5U.infodata.purification_unit_uv_treatment.lens_requested\\\\§aBlue Topaz Lens",
  "GT5U.infodata.purification_unit_uv_treatment.removed_too_early",
  "GT5U.infodata.purification_unit_flocculation.consumed\\\\Polyaluminium Chloride\\\\§c900000",
  n = 8 }, fields)
eq(raw.chance, 99, "raw chance"); eq(raw.parallel, 1024, "raw parallel"); eq(raw.ph, 6.87, "raw ph")
eq(raw.temp, 12000, "raw temp"); eq(raw.requested, "Blue Topaz Lens", "raw lens"); eq(raw.early, true, "raw flag")
eq(raw.consumed, 900000, "raw consumed (last arg, not the fluid name)")

local en = core.parseSensor({
  "This Purification Unit is linked to the Water Purification Plant at 1, 2, 3.",
  "Success chance: §e66.0%§r", "Current Parallel: §e64",
  "Current pH Value: §e7.0 pH", "Current temperature: §e5000K",
  "Current lens requested: §aOrundum Lens", "Polyaluminium Chloride consumed this cycle: §c100000L",
  n = 7 }, fields)
eq(en.chance, 66, "en chance"); eq(en.parallel, 64, "en parallel"); eq(en.ph, 7, "en ph")
eq(en.temp, 5000, "en temp"); eq(en.requested, "Orundum Lens", "en lens"); eq(en.early, nil, "no flag")
eq(en.consumed, 100000, "en consumed")

local ru = core.parseSensor({ "Шанс успеха: 33%", "Текущая температура: 10000K", "Запрошенная линза: Линза из янтаря",
  "Текущее значение pH: 8.12 pH", n = 4 }, fields)
eq(ru.chance, 33, "ru chance"); eq(ru.temp, 10000, "ru temp"); eq(ru.requested, "Линза из янтаря", "ru lens")
eq(ru.ph, 8.12, "ru ph")

-- dose formulas
for k in pairs(package.loaded) do if k:match("^waterline%.g") then package.loaded[k] = nil end end
package.loaded.event, package.loaded.unicode, package.loaded.filesystem = {}, {}, {}
local g2 = require("waterline.g2").impl
eq(g2.chanceFor(1024000), 80, "ozone 1024k"); eq(g2.chanceFor(600000), 60, "ozone 600k"); eq(g2.chanceFor(100000), 0, "ozone <128k")
local g3 = require("waterline.g3").impl
eq(g3.levelsFor(10), 9, "PAC base 10%"); eq(g3.levelsFor(25), 8, "PAC with boost"); eq(g3.levelsFor(100), 0, "PAC at 100%")
local g4 = require("waterline.g4").impl
local kind, n = g4.doseFor(4.5); eq(kind, "naoh", "low pH → NaOH"); eq(n, 250, "NaOH count")
kind, n = g4.doseFor(9.5); eq(kind, "hcl", "high pH → HCl"); eq(n, 2500, "HCl liters, multiple of 10")
kind, n = g4.doseFor(7.29); eq(n, 290, "7.29 → 290 L")
kind = g4.doseFor(7.02); eq(kind, nil, "within tolerance")
local g5 = require("waterline.g5").impl
eq(g5.plasmaFor(0), 100, "plasma from 0 K"); eq(g5.plasmaFor(9950), 1, "plasma top-up"); eq(g5.coolantFor(10000), 2000, "coolant")
print("core sensor parsing and dose formulas: OK")
