# grade_7 — OpenComputers-контроллер Degasser (GTNH, Grade 7 water)

Автоматизирует **Residual Decontaminant Degasser Purification Unit**. Программа читает сигнал Degasser Control Hatch и заливает точное количество нужных жидкостей. Экран T3 показывает прогресс цикла и шанс на выход.

Механика взята из исходника [`MTEPurificationUnitDegasser.java`](https://github.com/GTNewHorizons/GT5-Unofficial/blob/master/src/main/java/gregtech/common/tileentities/machines/multi/purification/MTEPurificationUnitDegasser.java). Подробности, решения и проверки — в [CHANGELOG.md](CHANGELOG.md).

| Сигнал | Вероятность | Залить |
|---|---|---|
| 0 | 10% | 10 000 L Super Coolant |
| 1 / 3 / 5 / 7, бит 1 | — | газ по битам 2–3: He 10 000 / Ne 7 500 / Kr 5 000 / Xe 2 500 L |
| бит 2 | 50% от циклов без бита 4 | 1 440 L SC base, множитель выхода UV×1.0 … UMV×2.0 |
| бит 3 | 50% от циклов без бита 4 | 4 608 L Molten Neutronium |
| 8–15, бит 4 | 20% | **ничего** |

Количество должно совпасть **точно**. Любая лишняя жидкость из этого списка даёт провал (0%).

## Железо

| Что | Кол-во | Куда |
|---|---|---|
| Computer Case T2+/T3, CPU T2+, 2× RAM T2+, HDD с OpenOS, клавиатура | 1 | куда угодно, кабель OC |
| GPU T3 + Screen T3 (нужно разрешение 160×50) | 1 | к компьютеру |
| Adapter | 1 | вплотную к **контроллеру** Degasser |
| Redstone I/O | 1 | вплотную к **лицевой грани** Degasser Control Hatch |
| Transposer, **UV** (в GTNH 2.8+ нужен тир не ниже LuV) | 2 | вплотную к input hatch'ам катализаторов |
| Input Hatch под катализаторы (отдельно от G6-воды) | 2 | на корпусе Degasser |
| **ME Dual Interface** | 7 | вокруг transposer'ов, по одному на жидкость |
| Adapter для ME (необязательно, но рекомендую) | 1 | вплотную к **любому** из этих Dual Interface |
| Кабель OC | — | компьютер, оба Adapter, Redstone I/O, оба transposer'а (длина любая) |

## Сборка у хэтча

```
 Transposer A (вид сверху)                Transposer B (вид сверху)
           [DI: Coolant]                            [DI: Xenon]
                 N                                       N
 [DI: Krypton] W [TA] E [DI: Neon]    [Adapter ME] ─ W [TB] E [DI: Neutronium]
                 S                                       S
           [DI: Helium]                             [DI: SC base]
   UP   = Input Hatch #1                  UP   = Input Hatch #2
   DOWN = кабель OC                       DOWN = кабель OC
```
*DI = ME Dual Interface. Adapter для ME ставится вплотную к любому DI своей гранью, на схеме он условно показан слева от TB.*

Правила:
- **В каждом Dual Interface ровно одна жидкость в конфиге, без патернов.** Если программа увидит в интерфейсе две жидкости, она откажется из него качать.
- **Dual Interface не касается хэтча Degasser'а**, только своего transposer'а.
- **SC base — один тир.** Два разных тира в одном цикле дают провал.
- В хэтчи катализаторов не идёт ничего, кроме transposer'ов. G6-вода подаётся в третий, отдельный хэтч.
- Хэтч касается transposer'а лицевой гранью.
- Стороны можно выбрать любые: `degasser scan` их покажет. Если повторить схему, в конфиге поменяются только адреса.

Интерфейс может держать меньше, чем нужно за одну подачу: например 10 000 L coolant при ёмкости танка интерфейса меньше этого. Программа качает порциями, пока AE доливает. Если поступления нет `stallTimeout` секунд, подача прерывается и откатывается.

## Установка

1. Поставь OpenOS (`install` с дискеты).
2. Скопируй файлы:
   - `degasser.lua` → `/home/bin/degasser.lua`
   - `degasser.cfg.lua` → `/home/degasser.cfg.lua` (этот путь зашит в программе)

   Через Internet Card:
   ```
   mkdir /home/bin
   wget https://raw.githubusercontent.com/EugenPrinz/grade_7/main/degasser.lua /home/bin/degasser.lua
   wget https://raw.githubusercontent.com/EugenPrinz/grade_7/main/degasser.cfg.lua /home/degasser.cfg.lua
   ```
   Репозиторий должен быть публичным, иначе raw-ссылки не откроются.
3. Запусти `degasser scan` и заполни конфиг:
   - **gt_machine.** Degasser узнаётся по строкам *control signal* и *Bit*. Его адрес → `machine`.
   - **redstone.** Адрес → `redstone`. Дождись цикла с ненулевым сигналом: сторона с числом 1–15 → `redstoneSide`.
   - **ME.** Адрес → `me`. Нужно, чтобы был виден запас сети; в выводе должно быть «жидкостей в сети: N».
   - **transposer.** Стороны с жидкостями → `from`, пустая сторона с ёмкостью хэтча → `to`.
   - **outputPerParallel.** Выход G7 на 1 параллель из NEI.
4. Запусти `degasser`. Для автозапуска добавь строку `degasser` в `/home/.shrc`.

## Проверка после запуска

- Фаза к середине цикла: «готово: всё залито точно».
- Большой шанс к концу цикла: **100%**. Это live-значение из сканера машины.
- Статистика: растёт «подтверждено машиной ✓».

| Симптом | Причина |
|---|---|
| `не найден компонент 'gt_machine'` | Adapter не касается контроллера |
| `в сети несколько 'gt_machine'` | не задан `machine` |
| сигнал всегда 0, каждый цикл льётся coolant | неверный `redstoneSide` или Redstone I/O не на лице хэтча |
| `на стороне 'to' нет хэтча` | неверный `to` |
| «запас ME-сети не виден» | нет Adapter у DI, или `me` указан неверно, или найдено несколько ME-компонентов |
| «нет поступления N с» | AE не доливает интерфейс: кончилась жидкость или интерфейс не в сети |
| шанс 0% после слива | в хэтч льёт кто-то ещё, или в интерфейсе не та жидкость или не тот тир SC |

## Тесты

`test/sim.lua` — модель Degasser по исходнику GT плюс моки OC API (component, transposer, gpu, event.timer). Запуск: `test/run.sh [циклов] [seed]`, нужен Lua 5.3 (`lua5.3` или `texlua`).

Сценарии:

| Сценарий | Что проверяет |
|---|---|
| `normal` | обычная работа |
| `rawkeys` | сканер отдаёт ключи вместо перевода |
| `smallhatch` | хэтч на 2000 L |
| `midstart` | старт программы посреди цикла |
| `noise` | посторонний редстоун |
| `t2screen` | экран меньше 160×50, фолбэк на лог |
| `lowstock` | кончаются буферы |
| `iface` | Dual Interface + ME |
| `iface-nome` | Dual Interface без ME |
| `iface-dry` | сеть кончается |
