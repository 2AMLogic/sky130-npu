# Auxiliary OpenROAD probe for the pre-route STA read (layout/sta).
#
# `klt sta` reports exactly one worst path per check type -- the global worst
# (its generated Tcl calls find_timing_paths with group_path_count 1) -- and
# its only path selector, constraints.report_ports, takes top-level design
# ports. A caller therefore cannot ask it for the worst path through a named
# internal instance pin, which is the common need when timing a hard macro.
# This probe re-runs the same deck preamble the generated klt sta Tcl uses
# (same Liberty, LEF, netlist, clock) and asks report_checks directly for the
# macro-pin paths:
#
#   -to   <macro input pins>   worst setup path INTO a macro pin
#   -from <macro output pins>  worst setup path OUT of a macro pin (the read
#                              access path; the clk0 -> dout arc delay in the
#                              path table is the macro read access time, and
#                              the clock row names the launch edge)
#
# plus the full setup-violator listing, to show which endpoints actually
# violate at this clock period.
#
# This file is a TEMPLATE, committed free of host paths: layout/sta/run.sh
# substitutes the @STA_*@ placeholders into the scratch directory and runs
# the generated script there, so what is committed runs byte-for-byte
# unchanged. openroad runs in a container (the PATH wrapper mounts $PWD and
# $PDK_ROOT), so no environment crosses the boundary -- the paths have to be
# written into the script.

read_liberty @STA_STD_LIB@
read_liberty inputs/macro_tt.lib
read_lef @STA_STD_TLEF@
read_lef @STA_STD_LEF@
read_lef inputs/macro.lef
read_verilog inputs/npu_top_synth.v
link_design npu_top
set_cmd_units -time ns -capacitance pF
create_clock -name clk -period @STA_CLK_PERIOD@ [get_ports @STA_CLK_PORT@]

# The macro master this issue reads (one master, four bank instances); pin
# selection is by cell object, never by name pattern -- the hierarchical
# instance names contain brackets.
set sta_probe_macros [get_cells -hierarchical -filter {ref_name == sky130_sram_4kbyte_1rw1r_32x1024_8}]
puts "PROBE macro instances found: [llength $sta_probe_macros]"
set sta_probe_in [get_pins -quiet -of_objects $sta_probe_macros -filter {direction == input}]
set sta_probe_out [get_pins -quiet -of_objects $sta_probe_macros -filter {direction == output}]
puts "PROBE macro input pins: [llength $sta_probe_in]; macro output pins: [llength $sta_probe_out]"

puts "===PROBE_SETUP_INTO_MACRO_BEGIN==="
report_checks -to $sta_probe_in -path_delay max -group_count 1 -endpoint_count 1 -digits 3
puts "===PROBE_SETUP_INTO_MACRO_END==="

puts "===PROBE_SETUP_OUT_OF_MACRO_BEGIN==="
report_checks -from $sta_probe_out -path_delay max -group_count 1 -endpoint_count 1 -digits 3
puts "===PROBE_SETUP_OUT_OF_MACRO_END==="

puts "===PROBE_SETUP_VIOLATORS_BEGIN==="
report_check_types -max_delay -recovery -clock_gating_setup -violators -format end
puts "===PROBE_SETUP_VIOLATORS_END==="
