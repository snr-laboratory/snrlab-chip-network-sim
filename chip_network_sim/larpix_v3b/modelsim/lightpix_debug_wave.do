onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:fifo_top_inst:fifo_ram_inst:data_out
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:fifo_top_inst:fifo_ram_inst:fifo_counter
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:fifo_top_inst:fifo_ram_inst:fifo_full
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:fifo_top_inst:fifo_ram_inst:fifo_half
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:fifo_top_inst:fifo_ram_inst:fifo_empty
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:fifo_top_inst:fifo_ram_inst:data_in
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:fifo_top_inst:fifo_ram_inst:read_n
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:fifo_top_inst:fifo_ram_inst:write_n
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:fifo_top_inst:fifo_ram_inst:clk
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:fifo_top_inst:fifo_ram_inst:reset_n
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:fifo_top_inst:fifo_ram_inst:read_pointer
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:fifo_top_inst:fifo_ram_inst:write_pointer
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:fifo_top_inst:fifo_ram_inst:clk_read
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:fifo_top_inst:fifo_ram_inst:clk_write
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:fifo_top_inst:fifo_ram_inst:data_out_0
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:fifo_top_inst:fifo_ram_inst:data_out_1
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:fifo_top_inst:fifo_ram_inst:data_out_2
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:fifo_top_inst:fifo_ram_inst:data_out_3
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:fifo_top_inst:fifo_ram_inst:module_select_read
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:fifo_top_inst:fifo_ram_inst:module_select_write
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:fifo_top_inst:fifo_ram_inst:data_in_falling_edge
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:fifo_top_inst:fifo_ram_inst:enable_write_pointer
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:fifo_top_inst:fifo_ram_inst:enable_read_pointer
add wave -noupdate -expand :larpix_single_tb:larpix_v2_inst:digital_core_inst:fifo_top_inst:fifo_ram_inst:rf2p_512x64_4_50_inst_0:mem
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:fifo_top_inst:fifo_ram_inst:rf2p_512x64_4_50_inst_1:mem
add wave -noupdate :larpix_single_tb:external_trigger
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:external_trigger
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:external_trigger_mask
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:hit
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:clk
add wave -noupdate {:larpix_single_tb:larpix_v2_inst:digital_core_inst:CHANNELS[48]:channel_ctrl_inst:triggered_channel}
add wave -noupdate {:larpix_single_tb:larpix_v2_inst:digital_core_inst:CHANNELS[48]:channel_ctrl_inst:triggered_cross}
add wave -noupdate {:larpix_single_tb:larpix_v2_inst:digital_core_inst:CHANNELS[48]:channel_ctrl_inst:triggered_external}
add wave -noupdate {:larpix_single_tb:larpix_v2_inst:digital_core_inst:CHANNELS[48]:channel_ctrl_inst:triggered_natural}
add wave -noupdate {:larpix_single_tb:larpix_v2_inst:digital_core_inst:CHANNELS[48]:channel_ctrl_inst:triggered_periodic}
add wave -noupdate {:larpix_single_tb:larpix_v2_inst:digital_core_inst:CHANNELS[48]:channel_ctrl_inst:write_local_fifo_n}
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:lightpix_mode
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:event_router_inst:channel_event_out
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:event_router_inst:read_local_fifo_n
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:event_router_inst:load_event
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:event_router_inst:local_fifo_empty
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:event_router_inst:lightpix_mode
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:event_router_inst:hit_threshold
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:event_router_inst:timeout
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:event_router_inst:clk
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:event_router_inst:reset_n
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:event_router_inst:channel_waiting
add wave -noupdate -radix unsigned :larpix_single_tb:larpix_v2_inst:digital_core_inst:event_router_inst:total_hits
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:event_router_inst:event_timer
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:event_router_inst:event_accepted
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:event_router_inst:event_rejected
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:event_router_inst:event_decided
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:event_router_inst:State
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:event_router_inst:Next
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {598927250 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 841
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
WaveRestoreZoom {0 ps} {945 us}
