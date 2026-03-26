# compile source
do {compile_src.do}


# run vsim
vsim sar_ctrl_rev1_tb

#
# Source wave do file
#
do {sar_ctrl_rev1_tb_wave.do}

#
# Set the window types
#
view wave
view structure
view signals

#
# End
#
