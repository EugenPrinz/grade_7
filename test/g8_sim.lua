-- Check every possible hidden pair against the Grade 8 injection sequence.
local now, pending, history, secret, success, counts
local names = { "up", "down", "strange", "charm", "bottom", "top" }
local damage = { up = 32235, down = 32236, strange = 32237, charm = 32238, bottom = 32239, top = 32240 }
package.loaded.component = {}
package.loaded.computer = { uptime = function() return now end }
package.loaded.filesystem = {}
package.loaded.sides = {}
package.loaded.event = {}
package.loaded.unicode = {}
package.loaded["waterline.bindings"] = {}
os.sleep = function(dt)
  now = now + dt
  if pending and now >= pending.at then
    history[#history + 1] = pending.key
    if #history > 1 then
      local a, b = history[#history - 1], history[#history]
      if (a == secret[1] and b == secret[2]) or (a == secret[2] and b == secret[1]) then success = true end
    end
    pending = nil
  end
end
local machine = {
  getWorkProgress = function() return 20 + math.floor(now * 20) end,
  getWorkMaxProgress = function() return 2400 end,
  getSensorInformation = function()
    local info = { "История добавления катализаторов за этот цикл рецептов" }
    for i, key in ipairs(history) do info[#info + 1] = i .. ": " .. key end
    info[#info + 1] = "Правильно идентифицированая кварковая комбинация: " .. (success and "Yes" or "No")
    return info
  end,
}
local transposer = {
  getStackInSlot = function(_, slot)
    local key = names[slot]
    return { name = "gregtech:gt.metaitem.03", damage = damage[key], label = key, size = counts[key] }
  end,
  transferItem = function(_, _, amount, slot)
    assert(amount == 1 and not pending, "controller sent items before previous item was consumed")
    local key = names[slot]
    assert(counts[key] > 0, "source ran out")
    counts[key] = counts[key] - 1
    pending = { key = key, at = now + 1 }
    return 1
  end,
}
local routes = {}
for slot, key in ipairs(names) do routes[key] = { proxy = transposer, from = 2, to = 1, slot = slot } end
local g8 = require("waterline.g8")
local pairsSeen = {}
for i = 2, #g8.order do
  local a, b = g8.order[i - 1], g8.order[i]
  if a > b then a, b = b, a end
  pairsSeen[a .. ":" .. b] = true
end
local unique = 0
for _ in pairs(pairsSeen) do unique = unique + 1 end
assert(#g8.order == 18 and unique == 15, "Grade 8 plan must cover all 15 pairs in 18 insertions")
local realPrint = print
print = function() end
for i = 1, #names do
  for j = i + 1, #names do
    now, pending, history, secret, success = 0, nil, {}, { names[i], names[j] }, false
    counts = {}
    for _, key in ipairs(names) do counts[key] = 3 end
    assert(g8.runCycle(machine, routes, { pollInterval = 0.25, consumeTimeout = 5 }, 1),
      "hidden pair " .. names[i] .. "+" .. names[j] .. " was not found")
    assert(success, "machine did not confirm success")
    assert(#history <= 18, "too many catalysts injected")
  end
end
print = realPrint
print("G8 all 15 hidden pairs: OK")
