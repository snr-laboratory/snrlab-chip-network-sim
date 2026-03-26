onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -radix unsigned :channel_ctrl_tb:dynamic_reset_threshold
add wave -noupdate -radix unsigned :channel_ctrl_tb:dout
add wave -noupdate :channel_ctrl_tb:fifo_ack
add wave -noupdate :channel_ctrl_tb:hit
add wave -noupdate -radix unsigned :channel_ctrl_tb:min_delta_adc
add wave -noupdate -radix unsigned :channel_ctrl_tb:channel_ctrl_inst:delta_adc
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {562059 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 333
configure wave -valuecolwidth 40
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
WaveRestoreZoom {0 ps} {2100 ns}
