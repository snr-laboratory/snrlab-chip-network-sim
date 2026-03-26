# compile source
do {compile_src.do}


# run vsim
vsim -suppress 12110 channel_ctrl_tb

#
# Source wave do file
#
do {channel_ctrl_tb_wave.do}

#
# Set the window types
#
view wave
view structure
view signals

#
# End
#
