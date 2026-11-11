# 20261111-klt091-density-045 -- lever 4 (placement_density 0.6 -> 0.45): worse

Result: NOT routed (`GRT-0116`). Sourced from the committed log. Request =
baseline + `placement_density: 0.45` (klt default 0.6).

Final GRT congestion: met1 1873, met2 2321, met3 132, met4 57; Total **4383**
cells (baseline 3229), max H/V 3/3, 21.93% usage. Lower density spreads cells
and lengthens wires; congestion rises.
