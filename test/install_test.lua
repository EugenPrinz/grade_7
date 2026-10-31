-- Тест install.lua на моках OpenOS (internet/filesystem/shell), корень ФС — временная папка.
-- usage: texlua install_test.lua <repo_dir> <tmp_root>
local REPO_DIR, ROOT = arg[1], arg[2]
local realOpen = io.open
local function real(p) return ROOT .. p end
os.execute("rm -rf '" .. ROOT .. "' && mkdir -p '" .. ROOT .. "/home'")

local MODE = "ok" -- ok | 404 | broken
local function readLocal(name)
  local f = realOpen(REPO_DIR .. "/" .. name); local d = f:read("*a"); f:close(); return d
end

local mocks = {
  component = { isAvailable = function(t) return t == "internet" end },
  internet = {
    request = function(url)
      local name = url:match("/([^/]+)$")
      local body
      if MODE == "404" then body = "404: Not Found"
      elseif MODE == "broken" then body = readLocal(name):sub(1, 500)
      else body = readLocal(name) end
      local done = false
      return function() if done then return nil end done = true return body end
    end,
  },
  filesystem = {
    exists = function(p) local f = realOpen(real(p)) if f then f:close() return true end
      return os.execute("test -d '" .. real(p) .. "'") == true end,
    makeDirectory = function(p) return os.execute("mkdir -p '" .. real(p) .. "'") end,
    remove = function(p) return os.remove(real(p)) end,
    rename = function(a, b) return os.rename(real(a), real(b)) end,
    path = function(p) return p:match("^(.*/)[^/]*$") end,
  },
  shell = {
    parse = function(...)
      local a, o = {}, {}
      for _, v in ipairs({ ... }) do
        local k, val = v:match("^%-%-([^=]+)=(.*)$")
        if k then o[k] = val elseif v:match("^%-%-") then o[v:sub(3)] = true else a[#a + 1] = v end
      end
      return a, o
    end,
  },
}
for k, v in pairs(mocks) do package.loaded[k] = v end
io.open = function(p, m) return realOpen(real(p), m) end

local quiet = true
local realPrint, realWrite = print, io.write
local out = {}
print = function(...) local t = {} for _, v in ipairs({ ... }) do t[#t + 1] = tostring(v) end out[#out + 1] = table.concat(t, "\t") end
io.write = function(...) for _, v in ipairs({ ... }) do out[#out + 1] = tostring(v) end end

local function run(...)
  out = {}
  local chunk = assert(loadfile(REPO_DIR .. "/install.lua"))
  local ok, err = pcall(chunk, ...)
  return ok, err
end
local function exists(p) local f = realOpen(real(p)) if f then f:close() return true end return false end
local function read(p) local f = realOpen(real(p)) local d = f:read("*a") f:close() return d end
local fails = 0
local function check(cond, msg) if not cond then fails = fails + 1; realPrint("FAIL: " .. msg) else realPrint("ok:   " .. msg) end end

os.exit = function(code) error("EXIT " .. tostring(code), 0) end
io.stderr = { write = function(_, s) out[#out + 1] = s end }

-- 1. чистая установка + автозапуск
local ok, e1 = run("--autostart"); if not ok then realPrint("ERR:", e1, table.concat(out, " | ")) end
check(ok, "чистая установка без ошибок")
check(exists("/home/bin/degasser.lua") and read("/home/bin/degasser.lua") == readLocal("degasser.lua"), "программа записана целиком")
check(exists("/home/degasser.cfg.lua"), "конфиг создан")
check(read("/home/.shrc") == "degasser\n", "автозапуск добавлен")

-- 2. повтор: конфиг пользователя не трогается, автозапуск не дублируется
local f = realOpen(real("/home/degasser.cfg.lua"), "w"); f:write("-- мой конфиг\nreturn {}\n"); f:close()
ok = run("--autostart")
check(ok, "повторная установка без ошибок")
check(read("/home/degasser.cfg.lua") == "-- мой конфиг\nreturn {}\n", "пользовательский конфиг сохранён")
check(exists("/home/degasser.cfg.lua.new"), "свежий шаблон в .new")
check(read("/home/.shrc") == "degasser\n", "автозапуск не задублирован")

-- 3. --force-config
ok = run("--force-config")
check(ok and read("/home/degasser.cfg.lua.bak") == "-- мой конфиг\nreturn {}\n", "force-config: бэкап .bak")
check(read("/home/degasser.cfg.lua") == readLocal("degasser.cfg.lua"), "force-config: конфиг перезаписан")

-- 4. 404 и оборванная загрузка: рабочая программа не портится
local before = read("/home/bin/degasser.lua")
MODE = "404"; ok = run()
check(not ok and read("/home/bin/degasser.lua") == before, "404: ошибка, программа не тронута")
MODE = "broken"; ok = run()
check(not ok and read("/home/bin/degasser.lua") == before, "обрыв: ошибка компиляции, программа не тронута")
check(not exists("/home/bin/degasser.lua.tmp"), "временных файлов не осталось")

realPrint(fails == 0 and "ALL OK" or (fails .. " FAILED"))
