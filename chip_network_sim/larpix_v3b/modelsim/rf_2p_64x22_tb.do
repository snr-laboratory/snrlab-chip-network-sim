# compile source
do {compile_src.do}


# run vsim
vsim rf_2p_64x22_tb

#
# Source wave do file
#
do {rf_2p_64x22_tb_wave.do}

#
# Set the window types
#
view wave
view structure
view signals

#
# End
#
