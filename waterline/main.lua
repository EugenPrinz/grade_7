-- One program supervises the independent grade controllers on one OpenOS machine.
local component = require("component")
local event = require("event")
local bindings = require("waterline.bindings")
local display = require("waterline.display")
local parallel = require("waterline.parallel")
local unicode = require("unicode")
local registry = require("waterline.registry")

local M = {}
local CFG_PATH = "/home/waterline.cfg.lua"
local STATE_PATH = "/home/waterline.state.lua"
local GRADES = registry.grades
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
  cfg.screen = state.screen or cfg.screen
  return cfg
end

local function command(verb, grade)
  local spec = registry.find(grade)
  if not spec then error("укажи grade: WaterLineProgram " .. verb .. " " .. registry.ids(), 0) end
  if verb == "run" then
    local ok, err = require(spec.module).main({}, nil)
    if ok == false then error(tostring(err), 0) end
    return
  end
  return require(spec.module).main({ verb })
end

function M.main(args)
  if args[1] == "bind" or args[1] == "scan" or args[1] == "run" then return command(args[1], args[2]) end
  if args[1] == "screens" then
    if not component.isAvailable("gpu") then error("GPU не найден", 0) end
    for _, screen in ipairs(display.probe(component, component.gpu)) do
      print(string.format("%s  %dx%d блоков  максимум %dx%d",
        screen.address, screen.blocksW, screen.blocksH, screen.maxW, screen.maxH))
    end
    return
  end
  if args[1] == "screen" then
    local address = args[2] and component.get(args[2], "screen")
    if not address then error("экран не найден; см. WaterLineProgram screens", 0) end
    local state = bindings.load(STATE_PATH)
    state.screen = address
    local ok, err = bindings.save(STATE_PATH, state)
    if not ok then error(tostring(err), 0) end
    print("Выбран экран " .. address)
    return
  end
  if args[1] == "plan" then
    local spec = registry.find(args[2])
    local grade = spec and spec.grade
    local plan = parallel.plan(grade, tonumber(args[3]))
    for g = 1, 8 do print(string.format("G%d: %d параллелей", g, plan[g])) end
    print("Теоретический минимум по воде при 100% успехе; выставь значения в GUI машин.")
    return
  end
  if args[1] == "help" then
    print("WaterLineProgram                 — панель всех grade")
    print("WaterLineProgram bind|scan|run gN — привязка / компоненты / один grade в текстовом режиме")
    print("WaterLineProgram plan gN P       — план параллелей от grade N")
    print("WaterLineProgram screens | screen ADDRESS")
    print("grade: " .. registry.ids())
    return
  end
  if args[1] then error("неизвестная команда: " .. tostring(args[1]), 0) end

  local cfg = loadConfig()
  local thread = require("thread")
  local gpu, displaySession
  if cfg.ui ~= false and component.isAvailable("gpu") then
    gpu = component.gpu
    local problem
    displaySession, problem = display.select(component, gpu,
      { width = 100, height = 30, preferred = cfg.screen })
    if not displaySession then
      print("Экран недоступен: " .. tostring(problem) .. ". Работаю в текстовом режиме.")
      gpu = nil
    end
  end
  local w, h = 100, 30
  local selected = 1
  local slots = {}
  for _, spec in ipairs(GRADES) do
    slots[spec.id] = { spec = spec, enabled = cfg.enabled[spec.id] == true,
      stop = false, status = { phase = "не запущен" }, events = {} }
  end
  local notice = "1–8 / ↑↓ — grade · Space — вкл/выкл · B — привязка · P — план · M — экран · Q — выход"

  local function addLog(slot, level, message)
    local entry = string.format("%s %-4s %s", os.date("%H:%M:%S"), level, message)
    table.insert(slot.events, 1, entry)
    if #slot.events > 12 then slot.events[#slot.events] = nil end
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
    local enabled = {}
    for _, spec in ipairs(GRADES) do enabled[spec.id] = slots[spec.id].enabled end
    local ok, err = bindings.save(STATE_PATH, { enabled = enabled,
      baseGrade = cfg.baseGrade, baseParallel = cfg.baseParallel, screen = cfg.screen })
    if not ok then notice = "Не удалось сохранить включённые модули: " .. tostring(err) end
  end

  local function line(y, value, color, bg)
    gpu.setBackground(bg or COLORS.panel)
    gpu.setForeground(color or COLORS.fg)
    gpu.fill(1, y, w, 1, " ")
    gpu.set(2, y, unicode.sub(tostring(value), 1, w - 3))
  end
  local ROW0, ROWH = 5, 2 -- grade rows start at y=5, two lines per grade
  local function rowOf(index) return ROW0 + (index - 1) * ROWH end
  local function indexAt(y)
    if y < ROW0 or y >= ROW0 + #GRADES * ROWH then return nil end
    return math.floor((y - ROW0) / ROWH) + 1
  end
  local function stateOf(slot)
    if active(slot) then return slot.stop and "СТОП…" or "РАБОТАЕТ", COLORS.green end
    if slot.error then return "ОШИБКА", COLORS.red end
    if slot.enabled then return "ЗАПУСК", COLORS.yellow end
    return "выкл", COLORS.dim
  end
  local function chanceText(st)
    local c = st.lastChance or st.chance
    return c and string.format("%3d%%", math.floor(c + 0.5)) or "  —"
  end
  local function draw()
    if not gpu then return end
    gpu.setBackground(COLORS.bg); gpu.fill(1, 1, w, h, " ")
    local screenName = displaySession and displaySession.selected.address:sub(1, 8) or "—"
    line(1, "WaterLineProgram · GTNH 2.9 · G1–G8 · экран " .. screenName, COLORS.blue, COLORS.head)
    local plan = parallel.plan(cfg.baseGrade, cfg.baseParallel)
    local values = {}
    for g = 1, 8 do values[#values + 1] = "G" .. g .. "×" .. plan[g] end
    line(2, "План от G" .. cfg.baseGrade .. " ×" .. cfg.baseParallel .. ": " .. table.concat(values, "  "), COLORS.blue)
    line(3, "Минимум по воде при 100% успехе. Параллели выставляются в GUI машин.", COLORS.dim)
    line(4, "   grade              состояние  цикл  шанс   ✓/✗     фаза", COLORS.dim, COLORS.bg)
    for i, spec in ipairs(GRADES) do
      local slot = slots[spec.id]
      local st = slot.status
      local y = rowOf(i)
      local label, color = stateOf(slot)
      local bg = selected == i and 0x23364A or COLORS.panel
      line(y, string.format("%s%d %-16s %-9s %5s %5s %4s/%-4s %s", selected == i and "▶" or " ", spec.grade,
        spec.short, label, tostring(st.cycle or "—"), chanceText(st), tostring(st.success or 0),
        tostring(st.failed or 0), tostring(st.phase or "")), color, bg)
      local p, maxp = tonumber(st.progress) or 0, tonumber(st.maxProgress) or 0
      gpu.setBackground(bg); gpu.fill(1, y + 1, w, 1, " ")
      if maxp > 0 then
        gpu.setBackground(0x2A323C); gpu.fill(4, y + 1, 30, 1, " ")
        gpu.setBackground(COLORS.blue)
        gpu.fill(4, y + 1, math.max(1, math.floor(30 * math.min(1, p / maxp))), 1, " ")
      end
      gpu.setBackground(bg); gpu.setForeground(COLORS.dim)
      gpu.set(36, y + 1, unicode.sub(slot.error or slot.events[1] or "", 1, w - 37))
    end
    local sel = slots[GRADES[selected].id]
    local y0 = rowOf(#GRADES) + 3
    line(y0, "События · " .. sel.spec.name, COLORS.blue)
    for n = 1, h - 3 - y0 do line(y0 + n, sel.events[n] or "", COLORS.dim) end
    line(h - 2, notice, COLORS.yellow)
    line(h, "[Space] ВКЛ/ВЫКЛ  [B] ПРИВЯЗКА  [P] ПЛАН  [M] ЭКРАН  [Q] ВЫХОД", COLORS.green)
  end

  local function cycleScreen()
    if not gpu or not displaySession then return end
    local available = {}
    for _, screen in ipairs(displaySession.screens) do
      if screen.maxW >= w and screen.maxH >= h then available[#available + 1] = screen end
    end
    if #available < 2 then notice = "Подключён только один экран"; return end
    local index = 1
    for i, screen in ipairs(available) do
      if screen.address == displaySession.selected.address then index = i; break end
    end
    local address = available[index % #available + 1].address
    display.restore(displaySession)
    local nextSession, err = display.select(component, gpu,
      { width = 100, height = 30, preferred = address })
    if not nextSession then
      displaySession = display.select(component, gpu,
        { width = w, height = h, preferred = displaySession.selected.address })
      notice = "Не удалось выбрать экран: " .. tostring(err)
      return
    end
    displaySession = nextSession
    cfg.screen = address
    saveState()
    notice = "Экран " .. address:sub(1, 8) .. " выбран"
  end

  local function editParallel()
    if not gpu then notice = "Для ввода плана параллелей нужен монитор"; return end
    local grade = GRADES[selected].grade
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
        if b and b >= 49 and b < 49 + #GRADES then selected = b - 48
        elseif c == 200 then selected = math.max(1, selected - 1)
        elseif c == 208 then selected = math.min(#GRADES, selected + 1)
        elseif b == 32 then toggleSelected()
        elseif b == 98 or b == 66 then bindSelected()
        elseif b == 112 or b == 80 then editParallel()
        elseif b == 109 or b == 77 then cycleScreen()
        elseif b == 113 or b == 81 or c == 1 then break end
      elseif name == "touch" and gpu and (not gpu.getScreen or a == gpu.getScreen()) then
        local x, y = b, c
        local index = indexAt(y)
        if index then selected = index
        elseif y == h then
          if x < 20 then toggleSelected()
          elseif x < 40 then bindSelected()
          elseif x < 56 then editParallel()
          elseif x < 70 then cycleScreen()
          else break end
        end
      end
    end
    for _, spec in ipairs(GRADES) do slots[spec.id].stop = true end
    notice = "Останавливаю модули после безопасной точки цикла"
    local function anyActive()
      for _, spec in ipairs(GRADES) do if active(slots[spec.id]) then return true end end
      return false
    end
    while anyActive() do draw(); event.pull(0.5) end
  end
  local ok, err = xpcall(run, function(e) return tostring(e) end)
  if displaySession then display.restore(displaySession) end
  if not ok then error(err, 0) end
end

return M
-- END waterline/main.lua
