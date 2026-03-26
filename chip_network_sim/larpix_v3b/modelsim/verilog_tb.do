
set SIM_LEVEL rtl ;# rtl|post_syn|post_par|libprep
#set SIM_LEVEL post_syn ;# rtl|post_syn|post_par|libprep
#set SIM_LEVEL post_par ;# rtl|post_syn|post_par|libprep
#set SIM_LEVEL libprep
variable SIM_CORNER min ;# min|max

switch $SIM_LEVEL {

  rtl      {
  # compile source
    do {compile_src.do}
    #do {compile_src_coverage.do}
# run vsim
    vsim -L tsmc_tcb013ghp channel_ctrl_tb -coverage -voptargs="+cover=bcfst" -vopt -voptargs="+acc=npr" 
#    vsim -L tsmc_tcb013ghp digital_core_tb -voptargs="+cover=bcfst" -t ns -vopt -voptargs="+acc=npr"  
#    vsim -L tsmc_tcb013ghp hydra_ctrl_tb -coverage -voptargs="+cover=bcfst" -vopt -voptargs="+acc=npr" 
#    vsim -L tsmc_tcb013ghp external_interface_tb -coverage -voptargs="+cover=bcfst" -vopt -voptargs="+acc=npr" 

   vsim -L tsmc_tcb013ghp larpix_single_tb  -t ns -vopt -voptargs="+acc=npr" 
#   vsim -L tsmc_tcb013ghp larpix_hydra_tb  -t ns -vopt -voptargs="+acc=npr" 
# vsim uart_rx_tb -coverage -voptargs="+cover=bcfst" -t ns -vopt -voptargs="+acc=npr" 
#    vsim -L tsmc_tcb013ghp larpix_hydra_tb  -vopt -voptargs="+acc=npr" 
    
#   vsim -L rf2p_512x64_4_50 -L tsmc_cl018g_rvt_neg -L tsmc18_cg_neg -suppress 12027 larpix_single_tb  -vopt -voptargs="+acc -xprop,mode=resolve" 
  }

  post_syn      {
  # compile source
    do {compile_syn.do}
# run vsim
    vsim -L tsmc_tcb013ghp -suppress 12027 larpix_single_tb  -vopt -voptargs="+acc -xprop,mode=resolve" -sdftyp :larpix_single_tb:larpix_v2c_inst:digital_core_inst=[pwd]/../par/r2g.sdf

    
#   vsim -L rf2p_512x64_4_50 -L tsmc_cl018g_rvt_neg -L tsmc18_cg_neg -suppress 12027 larpix_hydra_tb  -vopt -voptargs="+acc -xprop,mode=resolve" 
  }
  post_par {
    do {compile_postpar.do}

 #   vsim -L tsmc_tcb013ghp -suppress 12027 larpix_single_tb  -vopt -voptargs="+acc -xprop,mode=resolve" 
   vsim   -L tsmc_tcb013ghp -suppress 12027 larpix_single_tb \
        -vopt -voptargs="+acc -xprop,mode=resolve" -sdfmin :larpix_single_tb:larpix_v2c_inst:digital_core_inst=[pwd]/../par/digital_core_av_hold_bc_tempus_signoff.sdf
#   vsim   -L tsmc_tcb013ghp -suppress 12027 larpix_single_tb \
#        -sdfnoerror -vopt -voptargs="+acc -xprop,mode=resolve" -sdfmin :larpix_single_tb:larpix_v2c_inst:digital_core_inst=[pwd]/../par/digital_core_av_hold_bc_tempus_signoff.sdf \
# -sdfmin :larpix_single_tb:larpix_v2c_inst:digital_core_inst=[pwd]/../par/digital_core_av_setup_wc_tempus_signoff.sdf 

#   vsim   -L rf2p_512x64_4_50 -L tsmc_cl018g_rvt_neg -L tsmc18_cg_neg -suppress 12027 larpix_hydra_tb \
        -sdfnoerror -vopt -voptargs="+acc -xprop,mode=resolve" -sdftyp :larpix_hydra_tb:larpix_v2c_inst0:digital_core_inst=[pwd]/../par/digital_core.signoff.sdf -sdftyp :larpix_hydra_tb:larpix_v2c_inst1:digital_core_inst=[pwd]/../par/digital_core.signoff.sdf -sdftyp :larpix_hydra_tb:larpix_v2c_inst2:digital_core_inst=[pwd]/../par/digital_core.signoff.sdf -sdftyp :larpix_hydra_tb:larpix_v2c_inst3:digital_core_inst=[pwd]/../par/digital_core.signoff.sdf \




    #add wave -group fpga_rx sim/:larpix_tb:mcp_inst:rx:*
    #force -deposit sim/:larpix_tb:larpix_inst:digital_core_inst:regmap_bits_376 St0 0
    #noforce sim/:larpix_tb:larpix_inst:digital_core_inst:regmap_bits_376
#    run 750us
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
