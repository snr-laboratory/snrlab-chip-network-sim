# compile source
do {compile_src.do}
#do {compile_src_coverage.do}


# run vsim
#vsim -coverage external_interface_tb
vsim external_interface_tb

#
# Source wave do file
#
do {external_interface_tb_wave.do}

#
# Set the window types
#
view wave
view structure
view signals

#
# End
#
