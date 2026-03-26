#
# Create work library
#
vlib work

#
# Map libraries
#
vmap work  

#
# Design sources
#
vlog -incr "../src/register_map.v" 
vlog -incr "../src/fifo.v" 
vlog -incr "../src/fifo_async.v" 
vlog -incr "../src/uart_rx.v" 
vlog -incr "../src/uart_tx.v" 
vlog -incr "../src/event_builder.v" 
vlog -incr "../src/comms_ctrl.v" 
vlog -incr "../src/fifo_rd_ctrl.v" 
vlog -incr "../src/fifo_rd_ctrl_async.v" 
vlog -incr "../src/sar_ctrl.v"
vlog -incr "../src/sar_ctrl_rev1.v"
vlog -incr "../src/channel_id_encoder.v"
vlog -incr "../src/channel_ctrl.v"
vlog -incr "../src/external_interface.v"
vlog -incr "../src/time_stamp_gen.v"
vlog -incr "../src/periodic_reset.v"
vlog -incr "../src/clk_div.v"
vlog -incr "../src/dff.v"
vlog -incr "../src/digital_core.v"
vlog -incr "../src/synchronizer.v"
vlog -incr "../src/reset_sync.v"
vlog -incr "../src/reset_mux.v"

#
# Testbenches
#
vlog -incr "../testbench/unit_tests/spi_tb.v" 
vlog -incr "../testbench/unit_tests/fifo_tb.v" 
vlog -incr "../testbench/unit_tests/uart_tb.v" 
vlog -incr "../testbench/unit_tests/event_builder_tb.v" 
vlog -incr "../testbench/unit_tests/comms_ctrl_tb.v" 
vlog -incr "../testbench/unit_tests/sar_ctrl_tb.v" 
vlog -incr "../testbench/unit_tests/sar_ctrl_rev1_tb.v" 
vlog -incr "../testbench/unit_tests/channel_ctrl_tb.v" 
vlog -incr "../testbench/unit_tests/external_interface_tb.v" 
vlog -incr "../testbench/unit_tests/analog_core_tb.v" 
vlog -incr "../testbench/digital_core_tb.v" 
vlog +incdir+../testbench/larpix_tasks/ -incr "../testbench/larpix_tb.v" 

#
# analog behavioral models
#
vlog -incr "../testbench/analog_core/sar_adc.v" 
vlog -incr "../testbench/analog_core/sar_adc_core.v" 
vlog -incr "../testbench/analog_core/discriminator.v" 
vlog -incr "../testbench/analog_core/csa.v" 
vlog -incr "../testbench/analog_core/analog_channel.v" 
vlog -incr "../testbench/analog_core/analog_core.v" 

#
# full chip model
#
vlog -incr "../testbench/larpix/larpix.v" 

#
# MCP
#

#vlog +incdir+../testbench/larpix_tasks/ -incr "../testbench/mcp/mcp_spi.v"
vlog +incdir+../testbench/larpix_tasks/ -incr "../testbench/mcp/mcp_regmap.v"
vlog +incdir+../testbench/larpix_tasks/ -incr "../testbench/mcp/mcp_analog.v"
vlog +incdir+../testbench/larpix_tasks/ -incr "../testbench/mcp/mcp_external_interface.v"
#vlog -incr "../testbench/mcp/mcp_regmap.v"
