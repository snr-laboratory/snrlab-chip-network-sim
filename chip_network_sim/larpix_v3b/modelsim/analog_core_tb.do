# compile source
do {compile_src.do}


# run vsim
vsim analog_core_tb

#
# Source wave do file
#
do {analog_core_tb_wave.do}

#
# Set the window types
#
view wave
view structure
view signals

#
# End
#
