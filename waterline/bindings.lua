-- Shared component binding UI for water-line grade controllers.
local component = require("component")
local event = require("event")
local fs = require("filesystem")
local sides = require("sides")
local unicode = require("unicode")
local display = require("waterline.display")

local M = {}
local SIDE_NAMES = { "down", "up", "north", "south", "west", "east" }

local function copy(t)
  local out = {}
  for k, v in pairs(t or {}) do out[k] = type(v) == "table" and copy(v) or v end
  return out
end

function M.load(path)
  if not fs.exists(path) then return {} end
  local chunk, err = loadfile(path)
  if not chunk then error("привязки " .. path .. ": " .. tostring(err), 0) end
  local ok, data = pcall(chunk)
  if not ok or type(data) ~= "table" then error("неверный файл привязок " .. path, 0) end
  return data
end

function M.apply(cfg, saved)
  cfg = copy(cfg)
  for _, key in ipairs({ "machine", "redstone", "redstoneSide", "me" }) do
    if saved[key] ~= nil then cfg[key] = saved[key] end
  end
  cfg.routes = cfg.routes or {}
  for key, route in pairs(saved.routes or {}) do
    local current = copy(cfg.routes[key])
    for field, value in pairs(route) do
      if value == false and field == "fluid" then current.fluid = nil
      else current[field] = value end
    end
    cfg.routes[key] = current
  end
  return cfg
end

function M.save(path, data)
  local serialized = require("serialization").serialize(data)
  local tmp = path .. ".tmp"
  local f, err = io.open(tmp, "w")
  if not f then return nil, err end
  f:write("return ", serialized, "\n")
  f:close()
  if fs.exists(path) then
    local bak = path .. ".bak"
    if fs.exists(bak) then fs.remove(bak) end
    local ok, moveErr = fs.rename(path, bak)
    if not ok then fs.remove(tmp); return nil, moveErr end
  end
  local ok, moveErr = fs.rename(tmp, path)
  if not ok then
    if fs.exists(path .. ".bak") then fs.rename(path .. ".bak", path) end
    return nil, moveErr
  end
  return true
end

local function short(addr)
  return type(addr) == "string" and addr:sub(1, 8) or tostring(addr or "не привязан")
end

local function sideName(n)
  return type(n) == "number" and (sides[n] or tostring(n)) or "?"
end

local function objects(types)
  local out, seen = {}, {}
  for _, t in ipairs(types) do
    for addr in component.list(t, true) do
      if not seen[addr] then
        local label = addr .. "  (" .. t .. ")"
        if t == "gt_machine" then
          local named, machineName = pcall(component.invoke, addr, "getName")
          if named and machineName then label = label .. "  " .. tostring(machineName) end
          local ok, info = pcall(component.invoke, addr, "getSensorInformation")
          if ok and type(info) == "table" and type(info[1]) == "string" then
            label = label .. "  " .. info[1]:gsub("§.", "")
          end
        end
        out[#out + 1] = { value = addr, label = label }
        seen[addr] = true
      end
    end
  end
  table.sort(out, function(a, b) return a.label < b.label end)
  return out
end

local function tankLabel(proxy, side)
  local ok, tanks = pcall(proxy.getFluidInTank, side)
  if not ok or type(tanks) ~= "table" then return "пусто" end
  local names = {}
  for i = 1, (tanks.n or #tanks) do
    local f = tanks[i]
    if f and f.name and (tonumber(f.amount) or 0) > 0 then
      names[#names + 1] = f.name .. " " .. tostring(f.amount) .. " L"
    end
  end
  return #names > 0 and table.concat(names, ", ") or "пусто"
end

local function sideOptions(proxy, kind, source)
  local out = {}
  for _, name in ipairs(SIDE_NAMES) do
    local side = sides[name]
    if kind == "item" then
      local ok, size = pcall(proxy.getInventorySize, side)
      if ok and type(size) == "number" and size > 0 then
        out[#out + 1] = { value = side, label = name .. "  инвентарь " .. size .. " слотов" }
      end
    else
      local ok, count = pcall(proxy.getTankCount, side)
      if ok and type(count) == "number" and count > 0 then
        out[#out + 1] = { value = side, label = name .. "  " .. (source and "источник: " or "хэтч: ") .. tankLabel(proxy, side) }
      end
    end
  end
  return out
end

local function slotOptions(proxy, side, expected)
  local out = {}
  local ok, size = pcall(proxy.getInventorySize, side)
  if not ok or type(size) ~= "number" then return out end
  for slot = 1, size do
    local got, stack = pcall(proxy.getStackInSlot, side, slot)
    if got and stack and (stack.size or 0) > 0 then
      local label = stack.label or stack.name or "?"
      local matches = not expected or
        (type(expected) == "table" and tonumber(stack.damage) == expected.damage) or
        (type(expected) == "string" and label:lower():find(expected:lower(), 1, true))
      if matches then
        out[#out + 1] = { value = slot, label = string.format("%d  %s ×%d", slot, label, stack.size) }
      end
    end
  end
  return out
end

local function fluidAt(proxy, side)
  local ok, tanks = pcall(proxy.getFluidInTank, side)
  if not ok or type(tanks) ~= "table" then return false end
  local name
  for i = 1, (tanks.n or #tanks) do
    local f = tanks[i]
    if f and f.name and (tonumber(f.amount) or 0) > 0 then
      if name and name ~= f.name then return false end
      name = f.name
    end
  end
  return name or false -- false clears a stale fluid from an older config
end

function M.run(title, original, path, keys, kind, labels)
  if not component.isAvailable("gpu") then error("для привязки нужен GPU и монитор", 0) end
  local gpu = component.gpu
  local saved = M.load(path)
  local cfg = M.apply(original, saved)
  local session, problem = display.select(component, gpu, { width = 100, height = 30 })
  if not session then error("для привязки нужны GPU и экран T3: " .. tostring(problem), 0) end
  local w, h = session.width, session.height
  local notice = "Выбери роль. Enter/клик — выбор, S — сохранить, Esc — выход."
  local screen = gpu.getScreen and gpu.getScreen() or nil

  local function line(y, value, color)
    gpu.setBackground(0x17202B)
    gpu.setForeground(color or 0xDAE3ED)
    gpu.fill(1, y, w, 1, " ")
    gpu.set(2, y, unicode.sub(tostring(value), 1, w - 3))
  end
  local function frame(caption)
    gpu.setBackground(0x0E141C); gpu.fill(1, 1, w, h, " ")
    line(1, title .. "  /  " .. caption, 0x64BAFF)
    line(h - 2, notice, 0xE6C36B)
    line(h, "[S] Сохранить       [Esc] Назад / выход       ↑↓ и Enter или клик", 0x69D899)
  end
  local function choose(caption, options, allowSave)
    local pos, offset = 1, 0
    if #options == 0 then notice = "Ничего не найдено. Проверь кабель и соседние блоки."; return nil end
    while true do
      frame(caption)
      local page = h - 6
      if pos <= offset then offset = pos - 1 end
      if pos > offset + page then offset = pos - page end
      for i = 1, page do
        local item = options[offset + i]
        if item then
          line(i + 2, (offset + i == pos and "▶ " or "  ") .. item.label,
            offset + i == pos and 0x64BAFF or 0xDAE3ED)
        end
      end
      line(h - 3, string.format("%d / %d", pos, #options), 0x8495A8)
      local name, a, b, c, d = event.pull()
      if name == "touch" and (not screen or a == screen) then
        local x, y = b, c
        if y >= 3 and y < 3 + page and options[offset + y - 2] then
          pos = offset + y - 2
          return options[pos].value
        end
        if y == h then return allowSave and x < 30 and "__save" or nil end
      elseif name == "scroll" and (not screen or a == screen) then
        pos = math.max(1, math.min(#options, pos - (d or 0)))
      elseif name == "key_down" then
        if c == 200 then pos = math.max(1, pos - 1)
        elseif c == 208 then pos = math.min(#options, pos + 1)
        elseif c == 28 then return options[pos].value
        elseif c == 1 then return nil
        elseif allowSave and (b == 115 or b == 83) then return "__save" end
      elseif name == "interrupted" then return nil end
    end
  end

  local function bind(role)
    if role == "redstoneSide" then
      local opts = { { value = false, label = "Все стороны (максимальный сигнал)" } }
      local rs = cfg.redstone and component.get(cfg.redstone, "redstone")
      local proxy = rs and component.proxy(rs)
      for _, name in ipairs(SIDE_NAMES) do
        local side = sides[name]
        local ok, value = proxy and pcall(proxy.getInput, side)
        opts[#opts + 1] = { value = side, label = name .. (ok and ("  сигнал " .. tostring(value)) or "") }
      end
      local value = choose("Сторона Redstone I/O", opts)
      if value ~= nil then saved.redstoneSide = value; cfg.redstoneSide = value end
      return
    end
    if role == "machine" or role == "redstone" or role == "me" then
      local types = role == "machine" and { "gt_machine" } or
        (role == "redstone" and { "redstone" } or { "me_interface", "me_controller", "me_dual_interface" })
      local opts = objects(types)
      if role == "me" then table.insert(opts, 1, { value = false, label = "Без чтения ME-сети" }) end
      local value = choose(role .. " — компонент", opts)
      if value ~= nil then saved[role] = value; cfg[role] = value end
      return
    end
    local addr = choose(role .. " — transposer", objects({ "transposer" }))
    if not addr then return end
    local proxy = component.proxy(addr)
    local from = choose(role .. " — источник", sideOptions(proxy, kind, true))
    if from == nil then return end
    local slot
    if kind == "item" then
      slot = choose(role .. " — слот катализатора", slotOptions(proxy, from, labels and labels[role]))
      if slot == nil then return end
    end
    local to = choose(role .. " — входной хэтч/бас", sideOptions(proxy, kind, false))
    if to == nil then return end
    if from == to then notice = "Источник и вход машины не могут быть с одной стороны."; return end
    local route = { transposer = addr, from = from, to = to }
    if kind == "item" then route.slot = slot else route.fluid = fluidAt(proxy, from) end
    saved.routes = saved.routes or {}
    saved.routes[role] = route
    cfg.routes[role] = M.apply({ routes = { [role] = cfg.routes[role] } }, { routes = { [role] = route } }).routes[role]
    notice = role .. " привязан. Нажми S, чтобы сохранить."
  end

  local function main()
    local didSave = false
    local roles = {
      { id = "machine", label = "Контроллер" },
    }
    if kind == "fluid" then
      roles[#roles + 1] = { id = "redstone", label = "Redstone I/O" }
      roles[#roles + 1] = { id = "redstoneSide", label = "Сторона сигнала" }
      roles[#roles + 1] = { id = "me", label = "ME-сеть" }
    end
    for _, key in ipairs(keys) do roles[#roles + 1] = { id = key, label = key } end
    while true do
      local options = {}
      for _, r in ipairs(roles) do
        local value
        if r.id == "redstoneSide" then value = sideName(cfg.redstoneSide)
        elseif r.id == "machine" or r.id == "redstone" or r.id == "me" then value = short(cfg[r.id])
        else
          local route = cfg.routes and cfg.routes[r.id] or {}
          value = short(route.transposer) .. " " .. sideName(route.from) .. " → " .. sideName(route.to)
          if route.slot then value = value .. " slot " .. route.slot end
        end
        options[#options + 1] = { value = r.id, label = string.format("%-18s %s", r.label, value) }
      end
      options[#options + 1] = { value = "__save", label = "СОХРАНИТЬ ПРИВЯЗКИ" }
      options[#options + 1] = { value = "__exit", label = "ВЫХОД" }
      local chosen = choose("Роли компонентов", options, true)
      if chosen == nil or chosen == "__exit" then return didSave end
      if chosen == "__save" then
        local ok, err = M.save(path, saved)
        if ok then didSave = true; notice = "Сохранено: " .. path
        else notice = "Ошибка сохранения: " .. tostring(err) end
      else bind(chosen) end
    end
  end
  local ok, result = xpcall(main, function(err) return tostring(err) end)
  display.restore(session)
  if not ok then error(result, 0) end
  return result
end

return M
-- END waterline/bindings.lua
