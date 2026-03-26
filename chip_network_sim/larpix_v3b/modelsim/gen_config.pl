# generates config assignments for digital_core.sv
# crg 1/15/2019

#for (my $i=0; $i < 64; $i++) {
for (my $i=0; $i < 8; $i++) {
    $top_range = $i*8+7;
    $bottom_range = $i*8;
#    print "    pixel_trim_dac[$top_range:$bottom_range] = config_bits[PIXEL_TRIM+$i][7:0];\n";
    print "    csa_reset[$top_range:$bottom_range] = config_bits[CSA_RESET+$i][7:0];\n";
    print "    csa_bypass_select[$top_range:$bottom_range] = config_bits[BYPASS_SELECT+$i][7:0];\n";
    print "    csa_monitor_select[$top_range:$bottom_range] = config_bits[CSA_MONITOR_SELECT+$i][7:0];\n";
    print "    csa_test_enable[$top_range:$bottom_range] = config_bits[CSA_TEST_ENABLE+$i][7:0];\n";

}
