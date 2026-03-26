onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:periodic_trigger_cycles
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:external_interface_inst:comms_ctrl_inst_fifo_rd_ctrl_async_inst_State_0_
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:external_interface_inst:comms_ctrl_inst_fifo_rd_ctrl_async_inst_State_1_
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:external_interface_inst:comms_ctrl_inst_fifo_rd_ctrl_async_inst_ld_counter_2_
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:external_interface_inst:comms_ctrl_inst_fifo_rd_ctrl_async_inst_ld_counter_3_
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:external_interface_inst:tx_busy
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:external_interface_inst:read_fifo_n
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:external_interface_inst:write_fifo_n
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:periodic_trigger
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:external_interface_inst:fifo_empty
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {360050811 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 850
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 0
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ps
update
WaveRestoreZoom {225480088 ps} {527847 ns}
