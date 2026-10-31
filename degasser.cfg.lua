-- degasser.cfg.lua — конфиг для degasser.lua (GTNH, Grade 7 water)
-- Положить в /home/degasser.cfg.lua. Адреса/стороны смотреть через: degasser scan
local sides = require("sides")

return {
  -- Adapter на контроллере Residual Decontaminant Degasser (компонент gt_machine).
  -- nil = автопоиск, работает только если gt_machine в сети ровно один.
  machine = "c8eac84a-dedc-4087-8d28-73e1da9e42bc",

  -- Redstone I/O, стоящий вплотную к Degasser Control Hatch.
  redstone = "ca0e9e93-871a-4222-a588-2e0b161778d2",
  -- Сторона Redstone I/O, смотрящая на Control Hatch. nil = максимум по всем сторонам
  -- (только если рядом нет других источников редстоуна).
  redstoneSide = nil,

  -- Источники = ME Dual Interface (AE доливает их на ходу). false = обычные буферные танки.
  -- Можно переопределить для отдельного маршрута: routes.X.refill = true/false.
  refillSources = true,
  -- ME-компонент для чтения запаса сети (Adapter вплотную к любому Dual Interface этой сети).
  -- nil = автопоиск (если ME-компонент в сети OC один), false = не использовать.
  -- Без него предпроверка мягче: «интерфейс заполнен => AE дольёт».
  me = "de1db373-33dd-4104-b6bb-53dcc2840b80",
  -- Если за столько секунд ни один мБ не пришёл — подача прерывается и откатывается.
  stallTimeout = 15,

  -- Маршруты подачи: источник (from) -> input hatch Degasser'а (to) через transposer.
  -- Dual Interface: ровно ОДНА жидкость в конфиге, без патернов, интерфейс не касается хэтча.
  -- fluid = внутреннее имя жидкости в буфере (необязательно; scan покажет имена).
  --   Если задано — программа откажется лить, если в буфере что-то другое.
  -- SC base — ровно ОДИН тир (два разных SC в одном цикле = провал).
  -- Перед запуском замени ic2coolant на molten.superconductoruvbase в верхнем интерфейсе первого transposer.
  -- Хэтчи под катализаторы лучше отдельные от G6-воды (или Quad Input Hatch).
  routes = {
    coolant        = { transposer = "a8f23c4e-66cd-411b-b11d-4f67c4f61ce2", from = sides.front, to = sides.back, fluid = "supercoolant" },
    helium         = { transposer = "667217cc-2ee1-4bf4-b8f1-c6fc147f2363", from = sides.left,  to = sides.back, fluid = "helium" },
    neon           = { transposer = "667217cc-2ee1-4bf4-b8f1-c6fc147f2363", from = sides.front, to = sides.back, fluid = "neon" },
    krypton        = { transposer = "667217cc-2ee1-4bf4-b8f1-c6fc147f2363", from = sides.right, to = sides.back, fluid = "krypton" },
    xenon          = { transposer = "a8f23c4e-66cd-411b-b11d-4f67c4f61ce2", from = sides.right, to = sides.back, fluid = "xenon" },
    superconductor = { transposer = "667217cc-2ee1-4bf4-b8f1-c6fc147f2363", from = sides.up,    to = sides.back, fluid = "molten.superconductoruvbase" },
    neutronium     = { transposer = "a8f23c4e-66cd-411b-b11d-4f67c4f61ce2", from = sides.left,  to = sides.back, fluid = "molten.neutronium" },
  },

  pollInterval    = 0.25, -- с, опрос прогресса машины
  signalDelay     = 0.25, -- с, пауза после старта цикла перед чтением сигнала
  minTicksToStart = 300,  -- если до конца цикла меньше — цикл пропускается (ничего не льём)
  pumpReserveTicks = 100, -- сколько тиков до конца цикла оставить на слив (подача должна закончиться раньше)
  guardTicks      = 60,   -- за столько тиков до конца цикла хэтчи проверяются и откачиваются
  drainTimeout    = 4,    -- с, ожидание слива хэтча машиной после подачи
  lowStockCycles  = 5,    -- предупреждать, если буфера хватит меньше чем на N срабатываний

  -- Экран (GPU + монитор T3, 160x50). false = только текстовый лог.
  ui          = true,
  uiInterval  = 0.5,   -- с, частота перерисовки
  -- Выход G7 на 1 параллель при успехе, L (посмотри в NEI рецепт Degasser'а).
  -- Нужен только для строки «ожидаемо G7 ≈ N L»; nil = строка скрыта.
  outputPerParallel = nil,

  logFile     = "/home/degasser.log",
  logMaxBytes = 64 * 1024,
}
-- END degasser.cfg.lua
