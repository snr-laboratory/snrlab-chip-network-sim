onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate {:larpix_single_tb:larpix_v3b_inst:digital_core_inst:CHANNELS[0]:channel_ctrl_inst:clk}
add wave -noupdate {:larpix_single_tb:larpix_v3b_inst:digital_core_inst:CHANNELS[0]:channel_ctrl_inst:channel_event}
add wave -noupdate {:larpix_single_tb:larpix_v3b_inst:digital_core_inst:CHANNELS[0]:channel_ctrl_inst:done}
add wave -noupdate {:larpix_single_tb:larpix_v3b_inst:digital_core_inst:CHANNELS[0]:channel_ctrl_inst:dout}
add wave -noupdate {:larpix_single_tb:larpix_v3b_inst:digital_core_inst:CHANNELS[0]:channel_ctrl_inst:hit}
add wave -noupdate {:larpix_single_tb:larpix_v3b_inst:digital_core_inst:CHANNELS[0]:channel_ctrl_inst:sample}
add wave -noupdate {:larpix_single_tb:larpix_v3b_inst:digital_core_inst:CHANNELS[0]:channel_ctrl_inst:State}
add wave -noupdate {:larpix_single_tb:larpix_v3b_inst:digital_core_inst:CHANNELS[0]:channel_ctrl_inst:write_local_fifo_n}
add wave -noupdate {:larpix_single_tb:larpix_v3b_inst:digital_core_inst:CHANNELS[0]:channel_ctrl_inst:read_local_fifo_n}
add wave -noupdate :larpix_single_tb:larpix_v3b_inst:digital_core_inst:external_interface_inst:hydra_ctrl_inst:fifo_write_n
add wave -noupdate :larpix_single_tb:larpix_v3b_inst:digital_core_inst:external_interface_inst:hydra_ctrl_inst:fifo_read_n
add wave -noupdate {:larpix_single_tb:larpix_v3b_inst:digital_core_inst:external_interface_inst:UART[0]:uart_inst:uart_tx_inst:ld_tx_data}
add wave -noupdate {:larpix_single_tb:piso[0]}
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {136106 ns} 0} {{Cursor 2} {135401 ns} 0} {{Cursor 3} {133599 ns} 0}
quietly wave cursor active 2
configure wave -namecolwidth 525
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
configure wave -timelineunits ns
update
WaveRestoreZoom {132970 ns} {136317 ns}
