onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate :channel_ctrl_tb:clk
add wave -noupdate :channel_ctrl_tb:csa_reset
add wave -noupdate :channel_ctrl_tb:hit
add wave -noupdate -radix unsigned :channel_ctrl_tb:reset_length
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ps} 0}
quietly wave cursor active 0
configure wave -namecolwidth 231
configure wave -valuecolwidth 133
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
WaveRestoreZoom {0 ps} {4305054 ps}
