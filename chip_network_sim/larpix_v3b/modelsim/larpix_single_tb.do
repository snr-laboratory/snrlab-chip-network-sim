# compile source
#do {compile_reflibs.do}
do {compile_src.do}


# run vsim
#vsim larpix_single_tb -vopt -voptargs="+acc -xprop,mode=resolve"
vsim -L rf2p_512x64_4_50 -L tsmc_cl018g_rvt_neg -L tsmc18_cg_neg -suppress 12027 larpix_single_tb  -vopt -voptargs="+acc -xprop,mode=resolve" 

#
# Source wave do file
#
do {larpix_single_tb_wave.do}

#
# Set the window types
#
view wave
view structure
view signals

#
# End
#
