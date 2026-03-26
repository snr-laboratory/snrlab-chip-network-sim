# compile source
do {compile_src.do}


# run vsim
vsim uart_tb

#
# Source wave do file
#
do {uart_tb_wave.do}

#
# Set the window types
#
view wave
view structure
view signals

#
# End
#
