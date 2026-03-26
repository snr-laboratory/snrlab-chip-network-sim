# compile source
do {compile_src.do}


# run vsim
vsim event_builder_tb

#
# Source wave do file
#
do {event_builder_tb_wave.do}

#
# Set the window types
#
view wave
view structure
view signals

#
# End
#
