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

vlog +incdir+../testbench/larpix_tasks/ -incr -sv -L tsmc_tcb013ghp "../par/digital_core.signoff.v"

#
# Testbenches
#

vlog -incr -sv "../src/uart_rx.sv" 
vlog -incr -sv "../src/uart_tx.sv" 
vlog -incr -sv "../testbench/unit_tests/uart_rx_fpga.sv" 
vlog -incr -sv "../testbench/unit_tests/uart_tx_fpga.sv" 


vlog +incdir+../testbench/larpix_tasks/ -incr -sv "../testbench/unit_tests/larpix_single_tb.sv" 
vlog +incdir+../testbench/larpix_tasks/ -incr -sv "../testbench/unit_tests/larpix_hydra_tb.sv" 

#
# analog behavioral models
#
vlog -incr -vopt -sv "../testbench/analog_core/sar_async_adc.sv" 
vlog -incr -vopt -sv "../testbench/analog_core/discriminator.sv" 
vlog -incr -vopt -sv "../testbench/analog_core/csa.sv" 
vlog -incr -vopt -sv "../testbench/analog_core/analog_channel.sv" 
vlog -incr -vopt -sv "../testbench/analog_core/analog_core.sv" 

#
# full chip model
#
vlog -incr -vopt -sv "../testbench/larpix_v3/larpix_v3b.sv" 

#
# MCP
#

#vlog +incdir+../testbench/larpix_tasks/ -incr "../testbench/mcp/mcp_spi.v"
#vlog +incdir+../testbench/larpix_tasks/ -incr "../testbench/mcp/mcp_regmap.v"
#vlog +incdir+../testbench/larpix_tasks/ -incr "../testbench/mcp/mcp_analog.v"
#vlog +incdir+../testbench/larpix_tasks/ -incr "../testbench/mcp/mcp_external_interface.sv"
vlog +incdir+../testbench/larpix_tasks/ -incr "../testbench/mcp/mcp_larpix_single.sv"
#vlog +incdir+../testbench/larpix_tasks/ -incr "../testbench/mcp/mcp_larpix_hydra.sv"
