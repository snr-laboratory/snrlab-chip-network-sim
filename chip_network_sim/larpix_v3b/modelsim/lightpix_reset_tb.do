onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:reset_sync_inst:clk
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:reset_sync_inst:reset_n
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:reset_sync_inst:sync_timestamp
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:timestamp_gen_inst:clk
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:timestamp_gen_inst:reset_n
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:timestamp_gen_inst:sync_timestamp
add wave -noupdate -radix hexadecimal :larpix_single_tb:larpix_v2_inst:digital_core_inst:timestamp_gen_inst:timestamp_32b
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {18996927 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 621
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
WaveRestoreZoom {11860875 ps} {23779701 ps}
