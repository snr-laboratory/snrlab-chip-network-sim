onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate :fifo_tb:fifo_top_inst:fifo_ram_inst:clk
add wave -noupdate :fifo_tb:fifo_top_inst:fifo_ram_inst:clk_read
add wave -noupdate :fifo_tb:fifo_top_inst:fifo_ram_inst:clk_write
add wave -noupdate :fifo_tb:fifo_top_inst:fifo_ram_inst:data_in
add wave -noupdate :fifo_tb:fifo_top_inst:fifo_ram_inst:data_in_falling_edge
add wave -noupdate :fifo_tb:fifo_top_inst:fifo_ram_inst:data_out
add wave -noupdate :fifo_tb:fifo_top_inst:fifo_ram_inst:data_out_0
add wave -noupdate :fifo_tb:fifo_top_inst:fifo_ram_inst:data_out_1
add wave -noupdate :fifo_tb:fifo_top_inst:fifo_ram_inst:data_out_2
add wave -noupdate :fifo_tb:fifo_top_inst:fifo_ram_inst:data_out_3
add wave -noupdate :fifo_tb:fifo_top_inst:fifo_ram_inst:enable_read_pointer
add wave -noupdate :fifo_tb:fifo_top_inst:fifo_ram_inst:enable_write_pointer
add wave -noupdate :fifo_tb:fifo_top_inst:fifo_ram_inst:FIFO_BITS
add wave -noupdate :fifo_tb:fifo_top_inst:fifo_ram_inst:fifo_counter
add wave -noupdate :fifo_tb:fifo_top_inst:fifo_ram_inst:FIFO_DEPTH
add wave -noupdate :fifo_tb:fifo_top_inst:fifo_ram_inst:fifo_empty
add wave -noupdate :fifo_tb:fifo_top_inst:fifo_ram_inst:fifo_empty_counter
add wave -noupdate :fifo_tb:fifo_top_inst:fifo_ram_inst:fifo_empty_internal
add wave -noupdate :fifo_tb:fifo_top_inst:fifo_ram_inst:fifo_empty_sch
add wave -noupdate :fifo_tb:fifo_top_inst:fifo_ram_inst:fifo_full
add wave -noupdate :fifo_tb:fifo_top_inst:fifo_ram_inst:fifo_half
add wave -noupdate :fifo_tb:fifo_top_inst:fifo_ram_inst:FIFO_WIDTH
add wave -noupdate :fifo_tb:fifo_top_inst:fifo_ram_inst:module_select_read
add wave -noupdate :fifo_tb:fifo_top_inst:fifo_ram_inst:module_select_write
add wave -noupdate :fifo_tb:fifo_top_inst:fifo_ram_inst:read_n
add wave -noupdate :fifo_tb:fifo_top_inst:fifo_ram_inst:read_pointer
add wave -noupdate :fifo_tb:fifo_top_inst:fifo_ram_inst:reset_n
add wave -noupdate :fifo_tb:fifo_top_inst:fifo_ram_inst:write_n
add wave -noupdate :fifo_tb:fifo_top_inst:fifo_ram_inst:write_pointer
add wave -noupdate :fifo_tb:fifo_top_inst:fifo_ram_inst:rf2p_512x64_4_50_inst_0:mem
add wave -noupdate :fifo_tb:fifo_top_inst:fifo_ram_inst:rf2p_512x64_4_50_inst_1:mem
add wave -noupdate :fifo_tb:fifo_top_inst:fifo_ram_inst:rf2p_512x64_4_50_inst_2:mem
add wave -noupdate :fifo_tb:fifo_top_inst:fifo_ram_inst:rf2p_512x64_4_50_inst_3:mem
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ps} 0}
quietly wave cursor active 0
configure wave -namecolwidth 150
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
WaveRestoreZoom {0 ps} {1 ns}
