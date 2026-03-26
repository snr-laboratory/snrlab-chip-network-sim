# compile source
do {compile_src.do}


# run vsim
vsim processor_bugs_tb

#
# Source wave do file
#
do {processor_bugs_tb_wave.do}

#
# Set the window types
#
view wave
view structure
view signals

#
# End
#
