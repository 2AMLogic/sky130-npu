# 20261111-klt091-halo-15 -- lever 3 (halo 15 um): klt macro PDN grid fails

Result: failed at the floorplan stage, `PDN-0217: No grid found with name:
macro_u_banks/g_bank\[0\].u_bank/u_macro` (preceded by `PDN-0231`, the macro is
not connected to any power/ground nets). Not evidence about routing.

Request differs from the baseline by `halo: 15` on all four macros, and by
macro positions moved inward so the halo blockages fit in the die: A at x=16,
y=16 / 698, B at y=698 (die and B x unchanged). With `halo` set, klt 0.9.1
emits `define_pdn_grid -macro -instances {<glob>} -halo ...`; the `-instances`
glob does not match the bracketed hierarchical instance name, so the grid is
never created. Without `halo` the same instance names place fine (baseline
record). The halo lever is therefore not reachable on this netlist until klt
is fixed. Gap filed: 2AMLogic/klayout-tools#5302 (generic reproducer).
Related, closed: klayout-tools#4715, whose fix was not verified live.
