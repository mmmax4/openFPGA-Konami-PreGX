# Run from projects via scripts/build.sh audit-sdram. This reports the existing
# fitted netlist without replacing the full compile's .sta.rpt/.summary/RBF.
package require ::quartus::project
package require ::quartus::sta
project_open gaia_pocket
create_timing_netlist
read_sdc
update_timing_netlist
set dest [file normalize ../build/verification/sdram-timing]
file mkdir $dest
set regs [get_registers {*|sdram_ctrl:*|dq_in[*]}]
set count 0
foreach_in_collection r $regs { incr count }
if {$count != 16} { error "Expected 16 fitted SDRAM capture registers; found $count" }
set summary [open [file join $dest paths.tsv] w]
puts $summary "corner\tmodel\tvoltage\ttemperature\tbit\tcheck\tpaths\tslack_ns"
set corners 0
foreach_in_collection op [get_available_operating_conditions] {
    set_operating_conditions $op
    update_timing_netlist
    set model [get_operating_conditions_info -model $op]
    set voltage [get_operating_conditions_info -voltage $op]
    set temperature [get_operating_conditions_info -temperature $op]
    for {set bit 0} {$bit < 16} {incr bit} {
        set from [get_ports [format {dram_dq[%d]} $bit]]
        foreach check {setup hold} {
            set out [file join $dest [format {corner%d-dq%02d-%s.rpt} $corners $bit $check]]
            set result [report_timing -$check -from $from -to $regs -npaths 1 -detail full_path -file $out]
            set n [lindex $result 0]
            if {$n != 1} { error "Expected one $check path for DQ$bit at corner$corners; found $n" }
            puts $summary "$corners\t$model\t$voltage\t$temperature\t$bit\t$check\t$n\t[lindex $result 1]"
            flush $summary
        }
    }
    incr corners
}
close $summary
if {$corners < 3} { error "Insufficient operating conditions: $corners" }
delete_timing_netlist
project_close
puts "SDRAM_TIMING_REPORTED corners=$corners bits=16 checks=setup,hold"
