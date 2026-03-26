# compile source
do {compile_src.do}


# run vsim
vsim fifo_burst_tb

#
# Source wave do file
#
do {fifo_burst_tb_wave.do}

#
# Set the window types
#
view wave
view structure
view signals

#
# End
#
