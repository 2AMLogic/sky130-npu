read_liberty <pdk-root>/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_liberty <repo>/layout/sta/build/inputs/macro_tt.lib
read_lef <pdk-root>/sky130A/libs.ref/sky130_fd_sc_hd/techlef/sky130_fd_sc_hd__nom.tlef
read_lef <pdk-root>/sky130A/libs.ref/sky130_fd_sc_hd/lef/sky130_fd_sc_hd.lef
read_lef <repo>/layout/sta/build/inputs/macro.lef
read_verilog <repo>/layout/sta/build/inputs/npu_top_synth.v
link_design npu_top
set_cmd_units -time ns -capacitance pF
create_clock -name clk -period 20.0 [get_ports clk]
report_worst_slack_metric -setup
report_worst_slack_metric -hold
report_tns_metric -setup
report_tns_metric -hold
report_fmax_metric
report_power_metric
report_clock_skew_metric -setup
puts "===KLT_STA_SETUP_VIOLATIONS_BEGIN==="
report_check_types -max_delay -recovery -clock_gating_setup -violators -format end
puts "===KLT_STA_SETUP_VIOLATIONS_END==="
puts "===KLT_STA_HOLD_VIOLATIONS_BEGIN==="
report_check_types -min_delay -removal -clock_gating_hold -violators -format end
puts "===KLT_STA_HOLD_VIOLATIONS_END==="
puts "===KLT_STA_WORST_PATHS_BEGIN==="
if {[catch {
    foreach klt_path_side {max min} {
        foreach klt_pe [find_timing_paths -path_delay $klt_path_side -group_path_count 1 -endpoint_path_count 1] {
            puts "PATH\t$klt_path_side\t[$klt_pe check_role]\t[$klt_pe slack]\t[get_full_name [get_property $klt_pe startpoint]]\t[get_full_name [get_property $klt_pe endpoint]]"
        }
    }
} klt_worst_path_error]} {
    puts "ERROR\t[string map [list \n { } \t { }] $klt_worst_path_error]"
}
puts "===KLT_STA_WORST_PATHS_END==="
puts "===KLT_STA_CONSTRAINT_COMPLETENESS_BEGIN==="
foreach {klt_cc_check klt_cc_flags} {unconstrained_endpoints {0 0 0 0 1 0 0} unclocked_registers {0 0 0 1 0 0 0}} {
    if {[catch {
        set klt_cc_pins {}
        foreach klt_cc_record [sta::check_timing_cmd {*}$klt_cc_flags] {
            lappend klt_cc_pins {*}[lrange $klt_cc_record 1 end]
        }
        puts "CHECK\t$klt_cc_check\t[llength $klt_cc_pins]"
        foreach klt_cc_pin [lrange $klt_cc_pins 0 19] {
            puts "ITEM\t$klt_cc_check\t[string map [list \n { } \t { }] $klt_cc_pin]"
        }
    } klt_cc_error]} {
        puts "ERROR\t$klt_cc_check\t[string map [list \n { } \t { }] $klt_cc_error]"
    }
}
puts "===KLT_STA_CONSTRAINT_COMPLETENESS_END==="
