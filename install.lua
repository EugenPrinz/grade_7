-- install.lua — установщик/обновлятор degasser (GTNH Grade 7) для OpenComputers
-- Запуск:
--   wget -f https://raw.githubusercontent.com/EugenPrinz/grade_7/main/install.lua /tmp/install.lua
--   /tmp/install.lua [--autostart] [--force-config] [--ref <ветка|тег|коммит>]
--
--   --autostart     добавить запуск degasser в /home/.shrc
--   --force-config  перезаписать конфиг (старый сохранится как .bak)
--   --ref X         ставить из ветки/тега/коммита X (по умолчанию main)
--
-- Повторный запуск = обновление: программа перезаписывается, конфиг остаётся
-- (свежий шаблон кладётся рядом как degasser.cfg.lua.new).
local component = require("component")
local fs        = require("filesystem")
local shell     = require("shell")

local REPO    = "EugenPrinz/grade_7"
local PROG    = "/home/bin/degasser.lua"
local CFG     = "/home/degasser.cfg.lua"
local SHRC    = "/home/.shrc"

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

print(string.format("degasser: установка из %s@%s", REPO, ref))

-- 1. программа
io.write("  degasser.lua ... ")
local prog, err = fetch("degasser.lua")
if not prog then die("не скачалось: " .. err) end
local ok, cerr = checkLua("degasser.lua", prog)
if not ok then die(cerr) end
local version = prog:match('local VERSION%s*=%s*"([^"]+)"') or "?"
local wok, werr = writeFile(PROG, prog)
if not wok then die("не записалось " .. PROG .. ": " .. tostring(werr)) end
print("v" .. version .. " -> " .. PROG)

-- 2. конфиг
io.write("  degasser.cfg.lua ... ")
local cfg, ferr = fetch("degasser.cfg.lua")
if not cfg then die("не скачалось: " .. ferr) end
ok, cerr = checkLua("degasser.cfg.lua", cfg)
if not ok then die(cerr) end
if not fs.exists(CFG) then
  writeFile(CFG, cfg)
  print("создан " .. CFG)
elseif opts["force-config"] then
  copyFile(CFG, CFG .. ".bak")
  writeFile(CFG, cfg)
  print("перезаписан (старый -> " .. CFG .. ".bak)")
else
  writeFile(CFG .. ".new", cfg)
  print("оставлен твой; свежий шаблон -> " .. CFG .. ".new")
end

-- 3. автозапуск
if opts.autostart then
  local has = false
  local f = io.open(SHRC, "r")
  if f then
    for line in f:lines() do
      if line:match("^%s*degasser%s*$") or line:match("^%s*" .. PROG:gsub("%p", "%%%0") .. "%s*$") then has = true end
    end
    f:close()
  end
  if has then
    print("  автозапуск: уже есть в " .. SHRC)
  else
    local a = io.open(SHRC, "a")
    a:write("degasser\n")
    a:close()
    print("  автозапуск: добавлен в " .. SHRC)
  end
end

print("")
print("Дальше:")
print("  1. degasser scan                 — адреса, стороны, жидкости")
print("  2. edit " .. CFG .. "  — заполнить machine / redstone / me / routes")
print("  3. degasser                      — запуск")
print("Обновление: повтори установщик (конфиг не трогается).")
