onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate :larpix_single_tb:charge_in_r
add wave -noupdate :larpix_single_tb:clk
add wave -noupdate :larpix_single_tb:piso
add wave -noupdate :larpix_single_tb:posi
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ps} 0}
quietly wave cursor active 0
configure wave -namecolwidth 363
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
WaveRestoreZoom {0 ps} {10837 ps}
