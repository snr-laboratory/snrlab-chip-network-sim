
#set SIM_LEVEL rtl ;# rtl|post_syn|post_par|libprep
set SIM_LEVEL post_par ;# rtl|post_syn|post_par|libprep

variable SIM_CORNER min ;# min|max

switch $SIM_LEVEL {

  rtl      {
# compile source
    do {compile_src.do}
# run vsim
    vsim -L rf2p_512x64_4_50 -L tsmc_cl018g_rvt_neg -L tsmc18_cg_neg -suppress 12027 larpix_hydra_tb  -vopt -voptargs="+acc -xprop,mode=resolve" 
# Source wave do file
    do {wave.rtl.do}
    #force -freeze {sim/:larpix_single_tb:larpix_v2_inst:digital_core_inst:external_trigger_mask[63]} 0 0
    #force -freeze {sim/:larpix_single_tb:larpix_v2_inst:digital_core_inst:channel_mask[63]}          0 0
    #force -freeze  sim/:larpix_single_tb:larpix_v2_inst:digital_core_inst:threshold_global    00000100 0  
    #force -freeze  sim/:larpix_single_tb:larpix_v2_inst:digital_core_inst:reset_length             000 0
    #force -freeze  sim/:larpix_single_tb:larpix_v2_inst:digital_core_inst:adc_hold_delay          0100 0
    #force -freeze sim/:larpix_single_tb:larpix_v2_inst:digital_core_inst:select_fifo_latch 0 0

    #force -freeze sim/:larpix_single_tb:larpix_v2_inst:digital_core_inst:reset_n St0 0 -cancel 200ns
    ##force -deposit sim/:larpix_single_tb:larpix_inst:digital_core_inst:regmap_bits\[376\] St0 0
    #add wave -group top_dut sim/:larpix_single_tb:larpix_v2_inst:digital_core_inst:*
    power add -ports -internal -r :larpix_single_tb:larpix_v2_inst:digital_core_inst:*
    run 750us
  }

  post_syn { ;# DO NOT USE
    do {compile_postsyn.do}
    vsim  -L rf2p_512x64_4_50 -L tsmc_cl018g_rvt_neg -L tsmc18_cg_neg  -suppress 3584,3722,3017 larpix_tb  \
                 -sdfmin sim/:larpix_tb:larpix_inst:digital_core_inst=[pwd]/../larpix_digital_core/digital_core.mapped_ideal.sdf \
#                 -sdfmin sim/:larpix_tb:larpix_inst_2:digital_core_inst=[pwd]/../larpix_digital_core/digital_core.mapped_ideal.sdf \
                 -sdfmin sim/:larpix_tb:larpix_inst_3:digital_core_inst=[pwd]/../larpix_digital_core/digital_core.mapped_ideal.sdf 
  }

  post_par {
    do {compile_postpar.do}

    vsim   -L rf2p_512x64_4_50 -L tsmc_cl018g_rvt_neg -L tsmc18_cg_neg  -suppress 3584,3722,3017,2732,2685,2718,12027 larpix_hydra_tb \
                +notiftoggle01 -vopt -voptargs="+acc -xprop,mode=resolve  -sdfmin :larpix_hydra_tb:larpix_v2_inst0:digital_core_inst=[pwd]/../par/digital_core.output.sdf" \ 
                -sdfmin :larpix_hydra_tb:larpix_v2_inst0:digital_core_inst=[pwd]/../par/digital_core.output.sdf 
#   add wave -group top_dut sim/:larpix_hydra_tb:larpix_v2_inst0:digital_core_inst:*
    #add wave -group fpga_rx sim/:larpix_tb:mcp_inst:rx:*
    #force -deposit sim/:larpix_tb:larpix_inst:digital_core_inst:regmap_bits_376 St0 0
    #noforce sim/:larpix_tb:larpix_inst:digital_core_inst:regmap_bits_376
  }

  libprep {
    do {compile_reflibs.do}
    exit 
  }
} ;#-sdfreport=digital_core.sdf.report

#
#
#do {wave.gate.do}
#
# Set the window types
#
#view wave
#view structure
#view signals

#
# Source user do file (UDO)
#
#run 3us
#do {verilog_tb.udo}

#
# End
#
