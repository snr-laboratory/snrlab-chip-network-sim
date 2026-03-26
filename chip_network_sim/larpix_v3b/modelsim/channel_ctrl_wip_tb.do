# compile source
do {compile_src.do}


# run vsim
vsim channel_ctrl_wip_tb

#
# Source wave do file
#
do {channel_ctrl_wip_tb_wave.do}

#
# Set the window types
#
view wave
view structure
view signals

#
# End
#
