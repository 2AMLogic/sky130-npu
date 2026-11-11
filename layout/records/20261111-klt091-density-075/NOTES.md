# 20261111-klt091-density-075 -- lever 4 (placement_density 0.6 -> 0.75): worse

Result: NOT routed (`GRT-0116`). Sourced from the committed log. Request =
baseline + `placement_density: 0.75`.

Final GRT congestion: Total **6096** cells (baseline 3229), max H/V 3/3, 19.94%
usage. Denser clusters raise local demand at the macro pin edges.

Density sweep, same floorplan: 0.45 -> 4383, 0.60 (default) -> 3229, 0.75 ->
6096. The default is the minimum of the three; density alone does not close.
