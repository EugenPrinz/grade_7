-- install.lua — установщик/обновлятор WaterLineProgram (GTNH 2.9, Grade 1–8) для OpenComputers
-- Запуск:
--   wget -f https://raw.githubusercontent.com/EugenPrinz/grade_7/main/install.lua /tmp/install.lua
--   /tmp/install.lua [--autostart] [--force-config] [--ref <ветка|тег|коммит>]
--
--   --autostart     добавить запуск WaterLineProgram в /home/.shrc
--   --force-config  перезаписать конфиг (старый сохранится как .bak)
--   --ref X         ставить из ветки/тега/коммита X (по умолчанию main)
--
-- Повторный запуск обновляет программы и модули. Конфиги и привязки сохраняются.
local component = require("component")
local fs        = require("filesystem")
local shell     = require("shell")

local REPO    = "EugenPrinz/grade_7"
local PROG    = "/home/bin/degasser.lua"
local MAIN    = "/home/bin/WaterLineProgram.lua"
local CFG     = "/home/degasser.cfg.lua"
local SHRC    = "/home/.shrc"
-- Every waterline/*.lua must be listed here (test/manifest_test.lua checks it).
local PROGRAMS = {
  { name = "waterline/registry.lua", target = "/home/lib/waterline/registry.lua" },
  { name = "waterline/core.lua", target = "/home/lib/waterline/core.lua" },
  { name = "waterline/bindings.lua", target = "/home/lib/waterline/bindings.lua" },
  { name = "waterline/display.lua", target = "/home/lib/waterline/display.lua" },
  { name = "waterline/parallel.lua", target = "/home/lib/waterline/parallel.lua" },
  { name = "waterline/g1.lua", target = "/home/lib/waterline/g1.lua" },
  { name = "waterline/g2.lua", target = "/home/lib/waterline/g2.lua" },
  { name = "waterline/g3.lua", target = "/home/lib/waterline/g3.lua" },
  { name = "waterline/g4.lua", target = "/home/lib/waterline/g4.lua" },
  { name = "waterline/g5.lua", target = "/home/lib/waterline/g5.lua" },
  { name = "waterline/g6.lua", target = "/home/lib/waterline/g6.lua" },
  { name = "waterline/g7.lua", target = "/home/lib/waterline/g7.lua" },
  { name = "waterline/g8.lua", target = "/home/lib/waterline/g8.lua" },
  { name = "waterline/main.lua", target = "/home/lib/waterline/main.lua" },
  { name = "degasser.lua", target = PROG },
  { name = "grade8.lua", target = "/home/bin/grade8.lua" },
  { name = "WaterLineProgram.lua", target = MAIN },
}
local CONFIGS = {
  { name = "degasser.cfg.lua", target = CFG },
  { name = "grade8.cfg.lua", target = "/home/grade8.cfg.lua" },
  { name = "waterline.cfg.lua", target = "/home/waterline.cfg.lua" },
}

local args, opts = shell.parse(...)
local ref = opts.ref or "main"
if opts.ref == true then ref = args[1] or "main" end -- "--ref X" парсится как флаг + аргумент

local function die(msg)
  io.stderr:write("ОШИБКА: " .. msg .. "\n")
  os.exit(1)
end

if not component.isAvailable("internet") then die("нужна Internet Card") end
local internet = require("internet")

local function url(file)
  return string.format("https://raw.githubusercontent.com/%s/%s/%s", REPO, ref, file)
end

local function fetch(file)
  local ok, res = pcall(function()
    local parts = {}
    for chunk in internet.request(url(file)) do parts[#parts + 1] = chunk end
    return table.concat(parts)
  end)
  if not ok then return nil, tostring(res) end
  if res == "" then return nil, "пустой ответ" end
  return res
end

-- Скачанный код должен компилироваться: защита от 404-страниц и оборванной загрузки.
local function checkLua(name, src)
  if src:sub(1, 3) == "404" or src:find("^%s*<") then
    return false, "сервер вернул не Lua (репозиторий приватный или неверный --ref?)"
  end
  local f, err = load(src, "=" .. name)
  if not f then return false, "не компилируется: " .. tostring(err) end
  -- обрыв загрузки на границе строки может всё равно скомпилироваться — нужен маркер конца
  if not src:find("%-%- END " .. name:gsub("%p", "%%%0") .. "%s*$") then
    return false, "файл неполный (нет маркера конца) — повтори установку"
  end
  return true
end

-- Атомарная запись: во временный файл, затем rename.
local function writeFile(path, data)
  local dir = fs.path(path)
  if dir and not fs.exists(dir) then fs.makeDirectory(dir) end
  local tmp = path .. ".tmp"
  local f, err = io.open(tmp, "w")
  if not f then return false, err end
  f:write(data)
  f:close()
  if fs.exists(path) then fs.remove(path) end
  local ok, rerr = fs.rename(tmp, path)
  if not ok then return false, rerr end
  return true
end

local function copyFile(src, dst)
  local fi = io.open(src, "r"); if not fi then return false end
  local data = fi:read("*a"); fi:close()
  return writeFile(dst, data)
end

print(string.format("waterline: установка из %s@%s", REPO, ref))

-- Download and validate everything before replacing the installed programs.
local downloaded = {}
for _, file in ipairs(PROGRAMS) do
  io.write("  " .. file.name .. " ... ")
  local src, err = fetch(file.name)
  if not src then die(file.name .. ": не скачалось: " .. err) end
  local ok, why = checkLua(file.name, src)
  if not ok then die(file.name .. ": " .. why) end
  downloaded[file.name] = src
  print("OK")
end
for _, file in ipairs(CONFIGS) do
  io.write("  " .. file.name .. " ... ")
  local src, err = fetch(file.name)
  if not src then die(file.name .. ": не скачалось: " .. err) end
  local ok, why = checkLua(file.name, src)
  if not ok then die(file.name .. ": " .. why) end
  downloaded[file.name] = src
  print("OK")
end

-- Modules first, launchers last.
for _, file in ipairs(PROGRAMS) do
  local ok, err = writeFile(file.target, downloaded[file.name])
  if not ok then die("не записалось " .. file.target .. ": " .. tostring(err)) end
  print("  установлен " .. file.target)
end
for _, file in ipairs(CONFIGS) do
  local target = file.target
  if not fs.exists(target) then
    local ok, err = writeFile(target, downloaded[file.name])
    if not ok then die("не записалось " .. target .. ": " .. tostring(err)) end
    print("  создан " .. target)
  elseif opts["force-config"] then
    if not copyFile(target, target .. ".bak") then die("не удалось сохранить " .. target .. ".bak") end
    local ok, err = writeFile(target, downloaded[file.name])
    if not ok then die("не записалось " .. target .. ": " .. tostring(err)) end
    print("  перезаписан " .. target .. " (старый -> .bak)")
  else
    local ok, err = writeFile(target .. ".new", downloaded[file.name])
    if not ok then die("не записалось " .. target .. ".new: " .. tostring(err)) end
    print("  оставлен " .. target .. "; свежий шаблон -> .new")
  end
end

-- 3. автозапуск
if opts.autostart then
  local lines, has, migrated = {}, false, false
  local f = io.open(SHRC, "r")
  if f then
    for line in f:lines() do
      if line:match("^%s*WaterLineProgram%s*$")
        or line:match("^%s*" .. MAIN:gsub("%p", "%%%0") .. "%s*$") then
        if not has then lines[#lines + 1] = "WaterLineProgram" end
        has = true
      elseif line:match("^%s*degasser%s*$")
        or line:match("^%s*" .. PROG:gsub("%p", "%%%0") .. "%s*$") then
        migrated = true -- old standalone autostart is replaced by the shared program
      else lines[#lines + 1] = line end
    end
    f:close()
  end
  if not has then lines[#lines + 1] = "WaterLineProgram" end
  if migrated and not copyFile(SHRC, SHRC .. ".bak") then die("не удалось сохранить " .. SHRC .. ".bak") end
  local ok, err = writeFile(SHRC, table.concat(lines, "\n") .. "\n")
  if not ok then die("не записалось " .. SHRC .. ": " .. tostring(err)) end
  print("  автозапуск: " .. (migrated and "старый degasser заменён" or (has and "уже настроен" or "добавлен")))
end

print("")
print("Дальше:")
print("  WaterLineProgram bind g1..g8 — привязать компоненты grade через экран")
print("  WaterLineProgram scan g4     — показать компоненты, стороны, жидкости и сканер")
print("  WaterLineProgram             — общая панель; Space включает выбранный grade")
print("  WaterLineProgram plan g7 10  — рассчитать минимум параллелей по воде")
print("  degasser и grade8 оставлены для отдельного запуска/диагностики.")
print("  Привязки сохраняются отдельно от конфигов.")
print("  Повторный запуск установщика обновляет код, сохраняя настройки.")
