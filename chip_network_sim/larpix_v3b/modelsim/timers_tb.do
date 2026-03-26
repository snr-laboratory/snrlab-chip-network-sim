# compile source
do {compile_src.do}


# run vsim
vsim timers_tb

#
# Source wave do file
#
do {timers_tb_wave.do}

#
# Set the window types
#
view wave
view structure
view signals

#
# End
#
