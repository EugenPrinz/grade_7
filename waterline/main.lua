-- One program supervises the independent grade controllers on one OpenOS machine.
local component = require("component")
local event = require("event")
local bindings = require("waterline.bindings")
local parallel = require("waterline.parallel")
local unicode = require("unicode")

local M = {}
local CFG_PATH = "/home/waterline.cfg.lua"
local STATE_PATH = "/home/waterline.state.lua"
local GRADES = {
  { id = "g7", name = "Grade 7 · Degasser", module = "waterline.g7" },
  { id = "g8", name = "Grade 8 · Baryonic Perfection", module = "waterline.g8" },
}
local COLORS = { bg = 0x0F141B, panel = 0x1A2430, head = 0x123A5A,
  fg = 0xD8E2ED, dim = 0x8495A8, blue = 0x64BAFF, green = 0x66DE91,
  yellow = 0xE6C36B, red = 0xFC7272 }

local function loadConfig()
  local chunk, err = loadfile(CFG_PATH)
  if not chunk then error("конфиг " .. CFG_PATH .. ": " .. tostring(err), 0) end
  local cfg = chunk()
  if type(cfg) ~= "table" then error("waterline.cfg.lua должен возвращать таблицу", 0) end
  local state = bindings.load(STATE_PATH)
  cfg.enabled = cfg.enabled or {}
  for _, spec in ipairs(GRADES) do
    if state.enabled and state.enabled[spec.id] ~= nil then cfg.enabled[spec.id] = state.enabled[spec.id] end
  end
  cfg.baseGrade = state.baseGrade or cfg.baseGrade or 7
  cfg.baseParallel = state.baseParallel or cfg.baseParallel or 1
  return cfg
end

local function command(verb, grade)
  local id = grade and grade:lower()
  if id == "7" then id = "g7" elseif id == "8" then id = "g8" end
  if id ~= "g7" and id ~= "g8" then
    error("укажи grade: WaterLineProgram " .. verb .. " g7|g8", 0)
  end
  require("waterline." .. id).main({ verb })
end

function M.main(args)
  if args[1] == "bind" or args[1] == "scan" then return command(args[1], args[2]) end
  if args[1] == "plan" then
    local grade = tonumber(tostring(args[2] or ""):match("%d+"))
    local plan = parallel.plan(grade, tonumber(args[3]))
    for g = 1, 8 do print(string.format("G%d: %d параллелей", g, plan[g])) end
    print("Теоретический минимум по воде при 100% успехе; выставь значения в GUI машин.")
    return
  end
  if args[1] == "help" then
    print("WaterLineProgram [bind|scan g7|g8] | plan g7|g8 N")
    return
  end
  if args[1] then error("неизвестная команда: " .. tostring(args[1]), 0) end

  local cfg = loadConfig()
  local thread = require("thread")
  local gpu
  if cfg.ui ~= false and component.isAvailable("gpu") then
    gpu = component.gpu
    local w, h = gpu.maxResolution()
    if w < 80 or h < 25 then gpu = nil end
  end
  local oldW, oldH, w, h
  if gpu then
    oldW, oldH = gpu.getResolution()
    local maxW, maxH = gpu.maxResolution()
    w, h = math.min(maxW, 100), math.min(maxH, 30)
    gpu.setResolution(w, h)
  end
  local selected = 1
  local slots = {}
  for _, spec in ipairs(GRADES) do
    slots[spec.id] = { spec = spec, enabled = cfg.enabled[spec.id] == true,
      stop = false, status = { phase = "не запущен" }, events = {} }
  end
  local notice = "1/2 — grade · Space — вкл/выкл · B — привязка · P — план параллелей · Q — выход"

  local function addLog(slot, level, message)
    local entry = string.format("%s %-4s %s", os.date("%H:%M:%S"), level, message)
    table.insert(slot.events, 1, entry)
    if #slot.events > 8 then slot.events[#slot.events] = nil end
    if not gpu then print("[" .. slot.spec.id .. "] " .. entry) end
  end
  local function active(slot)
    return slot.thread and slot.thread:status() == "running"
  end
  local function start(slot)
    if active(slot) then return end
    slot.stop = false
    slot.status = { phase = "запуск" }
    slot.error = nil
    slot.thread = thread.create(function()
      local opts = {
        headless = true,
        shouldStop = function() return slot.stop end,
        onStatus = function(status) slot.status = status end,
        onLog = function(level, message) addLog(slot, level, message) end,
      }
      local ok, result, err = pcall(require(slot.spec.module).main, {}, opts)
      if not ok then
        slot.error = tostring(result)
        addLog(slot, "ERR", slot.error)
      elseif result == false then
        slot.error = tostring(err)
        addLog(slot, "ERR", slot.error)
      else
        addLog(slot, "INFO", "модуль остановлен")
      end
    end)
  end
  local function saveState()
    local ok, err = bindings.save(STATE_PATH, { enabled = {
      g7 = slots.g7.enabled, g8 = slots.g8.enabled,
    }, baseGrade = cfg.baseGrade, baseParallel = cfg.baseParallel })
    if not ok then notice = "Не удалось сохранить включённые модули: " .. tostring(err) end
  end

  local function line(y, value, color, bg)
    gpu.setBackground(bg or COLORS.panel)
    gpu.setForeground(color or COLORS.fg)
    gpu.fill(1, y, w, 1, " ")
    gpu.set(2, y, unicode.sub(tostring(value), 1, w - 3))
  end
  local function draw()
    if not gpu then return end
    gpu.setBackground(COLORS.bg); gpu.fill(1, 1, w, h, " ")
    line(1, "WaterLineProgram · GTNH 2.9 · G7 + G8", COLORS.blue, COLORS.head)
    local plan = parallel.plan(cfg.baseGrade, cfg.baseParallel)
    local values = {}
    for g = 1, 8 do values[#values + 1] = "G" .. g .. "×" .. plan[g] end
    line(2, "План от G" .. cfg.baseGrade .. " ×" .. cfg.baseParallel .. ": " .. table.concat(values, "  "), COLORS.blue)
    line(3, "Минимум по воде при 100% успехе. Параллели машин выставляются в их GUI.", COLORS.dim)
    for i, spec in ipairs(GRADES) do
      local slot = slots[spec.id]
      local y = 5 + (i - 1) * 9
      local mark = selected == i and "▶ " or "  "
      local state = active(slot) and (slot.stop and "ОСТАНАВЛИВАЕТСЯ" or "РАБОТАЕТ")
        or (slot.error and "ОШИБКА" or (slot.enabled and "ЗАПУСК" or "ВЫКЛЮЧЕН"))
      line(y, mark .. spec.name .. "  [" .. state .. "]",
        slot.error and COLORS.red or (active(slot) and COLORS.green or COLORS.yellow))
      local st = slot.status
      line(y + 1, "Цикл " .. tostring(st.cycle or "—") .. " · " .. tostring(st.phase or "ожидание") ..
        (st.parallel and (" · факт ×" .. st.parallel) or ""),
        COLORS.fg)
      local p, maxp = tonumber(st.progress) or 0, tonumber(st.maxProgress) or 0
      if maxp > 0 then
        gpu.setBackground(COLORS.panel); gpu.fill(2, y + 2, w - 4, 1, " ")
        gpu.setBackground(COLORS.blue)
        gpu.fill(2, y + 2, math.max(1, math.floor((w - 4) * math.min(1, p / maxp))), 1, " ")
      else line(y + 2, "Машина ожидает цикл", COLORS.dim) end
      for n = 1, 3 do line(y + 2 + n, slot.events[n] or "", COLORS.dim) end
    end
    line(h - 2, notice, COLORS.yellow)
    line(h, "[Space] ВКЛ/ВЫКЛ   [B] ПРИВЯЗКА   [P] ПЛАН ПАРАЛЛЕЛЕЙ   [Q] ВЫХОД", COLORS.green)
  end

  local function editParallel()
    if not gpu then notice = "Для ввода плана параллелей нужен монитор"; return end
    local grade = selected + 6
    local digits = ""
    while true do
      draw()
      line(math.floor(h / 2) - 1, "План от G" .. grade .. ": введи число параллелей (1..1000000)", COLORS.blue)
      line(math.floor(h / 2), "> " .. (digits ~= "" and digits or ("[сейчас " .. cfg.baseParallel .. "]")) .. "█", COLORS.fg)
      line(math.floor(h / 2) + 1, "Enter — сохранить · Backspace — удалить · Esc — отмена", COLORS.dim)
      local name, _, char, code = event.pull()
      if name == "key_down" then
        if char >= 48 and char <= 57 and #digits < 7 then digits = digits .. string.char(char)
        elseif code == 14 then digits = digits:sub(1, -2)
        elseif code == 1 then return
        elseif code == 28 then
          local value = tonumber(digits)
          if value and value >= 1 and value <= 1000000 then
            cfg.baseGrade, cfg.baseParallel = grade, value
            saveState()
            notice = "План сохранён. Настрой параллели вручную в GUI каждой машины."
            return
          end
          notice = "Введи целое число от 1 до 1000000"
        end
      elseif name == "interrupted" then return end
    end
  end

  local function bindSelected()
    local slot = slots[GRADES[selected].id]
    local wasRunning = active(slot)
    if wasRunning then
      slot.stop = true
      notice = "Жду безопасной точки цикла перед привязкой " .. slot.spec.name
      while active(slot) do draw(); event.pull(0.5) end
    end
    local ok, savedOrErr = pcall(require(slot.spec.module).main, { "bind" })
    if not ok then
      slot.error = tostring(savedOrErr)
      addLog(slot, "ERR", slot.error)
    end
    notice = ok and (savedOrErr and ("Привязки " .. slot.spec.id .. " сохранены") or "Привязка закрыта без сохранения")
      or ("Ошибка привязки " .. slot.spec.id .. ": " .. tostring(savedOrErr))
    if slot.enabled then start(slot) end
  end
  local function toggleSelected()
    local slot = slots[GRADES[selected].id]
    slot.enabled = not slot.enabled
    if slot.enabled then start(slot)
    elseif active(slot) then slot.stop = true end
    saveState()
  end

  local function run()
    for _, spec in ipairs(GRADES) do
      local slot = slots[spec.id]
      if slot.enabled then start(slot) end
    end
    while true do
      draw()
      local name, a, b, c = event.pull(0.5)
      if name == "interrupted" then break end
      if name == "key_down" then
        if b == 49 or c == 200 then selected = 1
        elseif b == 50 or c == 208 then selected = 2
        elseif b == 32 then toggleSelected()
        elseif b == 98 or b == 66 then bindSelected()
        elseif b == 112 or b == 80 then editParallel()
        elseif b == 113 or b == 81 or c == 1 then break end
      elseif name == "touch" and gpu and (not gpu.getScreen or a == gpu.getScreen()) then
        local x, y = b, c
        if y >= 5 and y <= 10 then selected = 1
        elseif y >= 14 and y <= 19 then selected = 2
        elseif y == h then
          if x < 29 then toggleSelected()
          elseif x < 54 then bindSelected()
          else break end
        end
      end
    end
    for _, spec in ipairs(GRADES) do slots[spec.id].stop = true end
    notice = "Останавливаю модули после безопасной точки цикла"
    while active(slots.g7) or active(slots.g8) do draw(); event.pull(0.5) end
  end
  local ok, err = xpcall(run, function(e) return tostring(e) end)
  if gpu then
    gpu.setBackground(0x000000); gpu.setForeground(0xFFFFFF)
    gpu.setResolution(oldW, oldH); gpu.fill(1, 1, oldW, oldH, " ")
  end
  if not ok then error(err, 0) end
end

return M
-- END waterline/main.lua
