# Vivado (xsim) project for the FIFO UVM testbench
# copied from Project/fifo_UVM, tb patched for xsim 2020.2
# usage: vivado -mode batch -source scripts/create_project.tcl
set root [file normalize [file dirname [info script]]/..]

create_project fifo_uvm $root -part xc7a35tcpg236-1 -force
set_property target_language Verilog [current_project]

add_files -fileset sources_1 -norecurse $root/src/fifo_sv.sv
add_files -fileset sim_1     -norecurse $root/sim/tb_fifo_uvm.sv
set_property top fifo_sv [get_filesets sources_1]
set_property top tb_fifo_uvm [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]

set_property -name {xsim.compile.xvlog.more_options}   -value {-L uvm} -objects [get_filesets sim_1]
set_property -name {xsim.elaborate.xelab.more_options} -value {-L uvm} -objects [get_filesets sim_1]
set_property -name {xsim.elaborate.debug_level}        -value {all}    -objects [get_filesets sim_1]
set_property -name {xsim.simulate.runtime}             -value {all}    -objects [get_filesets sim_1]
set_property -name {xsim.simulate.xsim.more_options}   -value {-testplusarg UVM_VERBOSITY=UVM_LOW} -objects [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
close_project
