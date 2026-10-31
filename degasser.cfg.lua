-- degasser.cfg.lua — конфиг для degasser.lua (GTNH, Grade 7 water)
-- Положить в /home/degasser.cfg.lua. Адреса/стороны смотреть через: degasser scan
local sides = require("sides")

return {
  -- Adapter на контроллере Residual Decontaminant Degasser (компонент gt_machine).
  -- nil = автопоиск, работает только если gt_machine в сети ровно один.
  machine = nil,

  -- Redstone I/O, стоящий вплотную к Degasser Control Hatch.
  redstone = nil,
  -- Сторона Redstone I/O, смотрящая на Control Hatch. nil = максимум по всем сторонам
  -- (только если рядом нет других источников редстоуна).
  redstoneSide = nil,

  -- Маршруты подачи: буфер (from) -> input hatch Degasser'а (to) через transposer.
  -- fluid = внутреннее имя жидкости в буфере (необязательно; scan покажет имена).
  --   Если задано — программа откажется лить, если в буфере что-то другое.
  -- SC base — ровно ОДИН тир (два разных SC в одном цикле = провал).
  -- Хэтчи под катализаторы лучше отдельные от G6-воды (или Quad Input Hatch).
  routes = {
    coolant        = { transposer = "xxxxxxxx", from = sides.north, to = sides.up, fluid = nil },
    helium         = { transposer = "xxxxxxxx", from = sides.south, to = sides.up, fluid = nil },
    neon           = { transposer = "xxxxxxxx", from = sides.east,  to = sides.up, fluid = nil },
    krypton        = { transposer = "xxxxxxxx", from = sides.west,  to = sides.up, fluid = nil },
    xenon          = { transposer = "yyyyyyyy", from = sides.north, to = sides.up, fluid = nil },
    superconductor = { transposer = "yyyyyyyy", from = sides.south, to = sides.up, fluid = nil },
    neutronium     = { transposer = "yyyyyyyy", from = sides.east,  to = sides.up, fluid = nil },
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
