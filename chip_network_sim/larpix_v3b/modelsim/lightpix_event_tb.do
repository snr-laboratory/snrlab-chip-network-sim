onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:event_router_inst:channel_event_out
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:event_router_inst:read_local_fifo_n
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:event_router_inst:load_event
add wave -noupdate -radix hexadecimal :larpix_single_tb:larpix_v2_inst:digital_core_inst:event_router_inst:local_fifo_empty
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:event_router_inst:clk
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:event_router_inst:reset_n
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:event_router_inst:timeout
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:event_router_inst:hit_threshold
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:event_router_inst:channel_waiting
add wave -noupdate -radix unsigned :larpix_single_tb:larpix_v2_inst:digital_core_inst:event_router_inst:total_hits
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:event_router_inst:event_timer
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:event_router_inst:event_accepted
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:event_router_inst:lightpix_mode
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:event_router_inst:State
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:event_router_inst:Next
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:event_router_inst:local_fifo_empty_latched
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:external_trigger
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:external_trigger_mask
add wave -noupdate -radix binary {:larpix_single_tb:larpix_v2_inst:digital_core_inst:CHANNELS[63]:channel_ctrl_inst:local_fifo_counter}
add wave -noupdate {:larpix_single_tb:larpix_v2_inst:digital_core_inst:CHANNELS[63]:channel_ctrl_inst:local_fifo_full}
add wave -noupdate {:larpix_single_tb:larpix_v2_inst:digital_core_inst:CHANNELS[63]:channel_ctrl_inst:local_fifo_half}
add wave -noupdate -radix unsigned {:larpix_single_tb:larpix_v2_inst:digital_core_inst:CHANNELS[63]:channel_ctrl_inst:fifo_inst:read_n}
add wave -noupdate -radix unsigned {:larpix_single_tb:larpix_v2_inst:digital_core_inst:CHANNELS[63]:channel_ctrl_inst:fifo_inst:read_pointer}
add wave -noupdate {:larpix_single_tb:larpix_v2_inst:digital_core_inst:CHANNELS[63]:channel_ctrl_inst:fifo_inst:reset_n}
add wave -noupdate {:larpix_single_tb:larpix_v2_inst:digital_core_inst:CHANNELS[63]:channel_ctrl_inst:fifo_inst:write_n}
add wave -noupdate -radix unsigned {:larpix_single_tb:larpix_v2_inst:digital_core_inst:CHANNELS[63]:channel_ctrl_inst:fifo_inst:write_pointer}
add wave -noupdate {:larpix_single_tb:larpix_v2_inst:digital_core_inst:CHANNELS[63]:channel_ctrl_inst:fifo_inst:fifo_mem}
add wave -noupdate {:larpix_single_tb:larpix_v2_inst:digital_core_inst:CHANNELS[63]:channel_ctrl_inst:fifo_inst:FIFO_DEPTH}
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:event_router_inst:event_complete
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:event_router_inst:fifo_empty_frozen
add wave -noupdate -radix hexadecimal :larpix_single_tb:larpix_v2_inst:digital_core_inst:event_router_inst:input_event
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:fifo_top_inst:chip_id
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:fifo_top_inst:clk
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:fifo_top_inst:data_in
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:fifo_top_inst:data_out
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:fifo_top_inst:FIFO_BITS
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:fifo_top_inst:fifo_counter
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:fifo_top_inst:FIFO_DEPTH
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:fifo_top_inst:fifo_empty
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:fifo_top_inst:fifo_full
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:fifo_top_inst:fifo_half
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:fifo_top_inst:FIFO_WIDTH
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:fifo_top_inst:read_n
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:fifo_top_inst:reset_n
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:fifo_top_inst:timestamp_32b
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:fifo_top_inst:write_n
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:external_interface_inst:comms_ctrl_inst:State
add wave -noupdate :larpix_single_tb:larpix_v2_inst:digital_core_inst:external_interface_inst:comms_ctrl_inst:load_event
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {607902609 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 784
configure wave -valuecolwidth 518
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
WaveRestoreZoom {607359304 ps} {608384696 ps}
