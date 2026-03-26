# compile source
do {compile_src.do}


# run vsim
vsim larpix_tb

#
# Source wave do file
#
do {larpix_tb_wave.do}

#
# Set the window types
#
view wave
view structure
view signals

#
# End
#
