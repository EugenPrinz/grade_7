local plan = require("waterline.parallel").plan
local p = plan(7, 10)
assert(p[7] == 10 and p[6] == 12 and p[5] == 14 and p[8] == 9,
  "lower grades must have enough output to feed the next grade")
assert(plan(8, 1)[7] == 2, "one G8 parallel needs two G7 parallels")
assert(plan(7, 1)[8] == 0, "one G7 parallel cannot sustain one G8 parallel")
print("water throughput plan: OK")
