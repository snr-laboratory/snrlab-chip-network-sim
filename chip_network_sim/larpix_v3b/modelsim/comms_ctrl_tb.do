# compile source
do {compile_src.do}


# run vsim
vsim comms_ctrl_tb

#
# Source wave do file
#
do {comms_ctrl_tb_wave.do}

#
# Set the window types
#
view wave
view structure
view signals

#
# End
#
