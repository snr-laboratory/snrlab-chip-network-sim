
#exec "rm -rf [pwd]/tsmc_cl018g_rvt_neg"
#vdel -all -lib [pwd]/tsmc_cl018g_rvt_neg
vlib tsmc_tcb013ghp
vmap tsmc_tcb013ghp    [pwd]/tsmc_tcb013ghp

#vlog -work tsmc_tcb013ghp "/eda/foundry/TSMC/TSMC130_v2.6B_CERN_v3.1/digital/Front_End/verilog/tcb013ghp_220a/tcb013ghp.v"
vlog -work tsmc_tcb013ghp "/home/lxusers/t/tprakash/LARPIX/TSMC13/verlog/larpix_v2c_xcelium/input/tcb013ghp.v"


