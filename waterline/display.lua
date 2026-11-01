-- Pick the physically largest connected screen and keep its terminal state.
local M = { preferredScreen = nil }

local function current(gpu)
  local screen = gpu.getScreen and gpu.getScreen() or nil
  local w, h = gpu.getResolution()
  return { address = screen, width = w, height = h }
end

local function screenSize(component, gpu, address)
  if gpu.getSize then
    local ok, w, h = pcall(gpu.getSize)
    if ok and tonumber(w) and tonumber(h) then return tonumber(w), tonumber(h) end
  end
  if component.invoke then
    local ok, w, h = pcall(component.invoke, address, "getAspectRatio")
    if ok and tonumber(w) and tonumber(h) then return tonumber(w), tonumber(h) end
  end
  return 1, 1
end

function M.probe(component, gpu)
  local original = current(gpu)
  local screens = {}
  if component.list and gpu.bind then
    for address in component.list("screen", true) do
      local ok, bound = pcall(gpu.bind, address, false)
      if ok and bound ~= false then
        local maxW, maxH = gpu.maxResolution()
        local w, h = gpu.getResolution()
        local blocksW, blocksH = screenSize(component, gpu, address)
        screens[#screens + 1] = {
          address = address, width = w, height = h,
          maxW = maxW, maxH = maxH, blocksW = blocksW, blocksH = blocksH,
        }
      end
    end
    if original.address then pcall(gpu.bind, original.address, false) end
  end
  if #screens == 0 and original.address then
    local maxW, maxH = gpu.maxResolution()
    local blocksW, blocksH = screenSize(component, gpu, original.address)
    screens[1] = {
      address = original.address, width = original.width, height = original.height,
      maxW = maxW, maxH = maxH, blocksW = blocksW, blocksH = blocksH,
    }
  end
  table.sort(screens, function(a, b) return a.address < b.address end)
  return screens
end

function M.select(component, gpu, options)
  options = options or {}
  local width, height = options.width or 100, options.height or 30
  local original = current(gpu)
  local screens = M.probe(component, gpu)
  local chosen
  local preferred = options.preferred or M.preferredScreen
  local preferredFound = false
  for _, screen in ipairs(screens) do
    if screen.maxW >= width and screen.maxH >= height then
      local area = screen.blocksW * screen.blocksH
      local bestArea = chosen and chosen.blocksW * chosen.blocksH or -1
      if preferred and screen.address == preferred then
        chosen, preferredFound = screen, true
      elseif not preferredFound and (not chosen or area > bestArea) then
        chosen = screen
      end
    end
  end
  if not chosen then return nil, "нет экрана T3 с разрешением " .. width .. "x" .. height end
  if gpu.bind and chosen.address ~= original.address then
    local ok, bound, why = pcall(gpu.bind, chosen.address, false)
    if not ok or bound == false then return nil, "не удалось подключить экран: " .. tostring(why or bound) end
  end
  local ok, set = pcall(gpu.setResolution, width, height)
  if not ok or set == false then
    if gpu.bind and original.address then pcall(gpu.bind, original.address, false) end
    return nil, "не удалось установить разрешение " .. width .. "x" .. height
  end
  M.preferredScreen = chosen.address
  return { gpu = gpu, original = original, selected = chosen, screens = screens,
    width = width, height = height }
end

function M.restore(session)
  if not session then return end
  local gpu = session.gpu
  pcall(function()
    gpu.setBackground(0x000000); gpu.setForeground(0xFFFFFF)
    if gpu.bind and session.selected.address then gpu.bind(session.selected.address, false) end
    gpu.setResolution(session.selected.width, session.selected.height)
    gpu.fill(1, 1, session.selected.width, session.selected.height, " ")
    if gpu.bind and session.original.address then gpu.bind(session.original.address, false) end
    gpu.setResolution(session.original.width, session.original.height)
  end)
end

return M
-- END waterline/display.lua
