///////////////////////////////////////////////////////////////////
// File Name: larpix_v3.sv
// Engineer:  Carl Grace (crgrace@lbl.gov)
// Description: Full-chip behavioral model for LArPix_v3.  
//              Uses production synthesziable RTL.
//              Uses real-value modeling analog circuits.
//
///////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module larpix_v3
    #(parameter FIFO_DEPTH = 2048,
    LOCAL_FIFO_DEPTH = 4)
    (output logic [3:0] piso,// PRIMARY-IN-SECONDARY-OUT TX UART output bit
    output logic digital_monitor, // digital test port
    output real monitor_out_r, // analog bias monitor
    input real charge_in_r [63:0],     // analog input signal
    input logic external_trigger,      // high to trigger channels
    input logic [3:0] posi,    // PRIMARY-OUT-SECONDARY-IN RX UART input bit
    input logic clk,                  // master clk
    input logic reset_n);      // asynchronous digital reset (active low)

// instantiation parameters

parameter VREF = 1.3;       // top end of ADC range
parameter VCM = 0.3;        // bottom end of ADC range
parameter WIDTH = 64;       // width of packet (w/o start & stop bits) 
parameter WORDWIDTH = 8;    // width of programming registers
parameter NUMCHANNELS = 64; // number of analog channels
parameter ADCBITS = 10;      // number of bits in ADC
parameter PIXEL_TRIM_DAC_BITS = 5;  // number of bits in pixel trim DAC
parameter GLOBAL_DAC_BITS = 8;  // number of bits in global threshold DAC
parameter TESTPULSE_DAC_BITS = 8;  // number of bits in testpulse DAC
parameter CFB_CSA = 40e-15;         // feedback capacitor in CSA
parameter VOUT_DC_CSA = 0.5;        // nominal dc output voltage of CSA
parameter REGNUM = 256;         // number of programming registers
parameter CHIP_ID_W = 8;    // width of chip ID
parameter VDDA = 1.8;              // nominal analog supply
parameter VOFFSET = 0.47;         // discriminator threshold offset

logic [ADCBITS*NUMCHANNELS-1:0] dout;           // bits from ADC
// control signals
//logic sample [NUMCHANNELS-1:0]; 
logic [NUMCHANNELS-1:0] sample; 
//logic csa_reset [NUMCHANNELS-1:0]; 
logic [NUMCHANNELS-1:0] csa_reset; 
logic [NUMCHANNELS-1:0] hit; 
logic [3:0] tx_enable;  // high to enable TX PHY

// CONFIG BITS
logic [PIXEL_TRIM_DAC_BITS*NUMCHANNELS-1:0] pixel_trim_dac; 
logic [GLOBAL_DAC_BITS-1:0] threshold_global;  
logic [NUMCHANNELS-1:0] csa_gain;
logic [NUMCHANNELS-1:0] bypass_caps_enable;
logic [15:0] ibias_tdac; // threshold dac ibias
logic [15:0] ibias_comp; // discriminator ibias
logic [15:0] ibias_buffer; // ab buffer ibias
logic [15:0] ibias_csa; // csa ibia
logic [3:0] ibias_vref_buffer; // vref buffer ibias
logic [3:0] ibias_vcm_buffer; // vcm buffer bias
logic [3:0] ibias_tpulse; // tpulse DAC bias
logic [15:0] adc_ibias_delay; // ADC delay line
logic [4:0] ref_current_trim; // trims ref voltage
logic [1:0] adc_comp_trim; // trims ref of delay generator in ADC
//logic ref_kickstart; // kickstart bit
//logic override_ref; // override reference generator
logic [7:0] vref_dac; // sets vref for adc
logic [7:0] vcm_dac; // sets vcm for adc
logic [NUMCHANNELS-1:0] csa_bypass_enable; // inject into adc from test pin
logic [NUMCHANNELS-1:0] csa_bypass_select; // adc channels(s)
logic [NUMCHANNELS-1:0] csa_monitor_select; // monitor channels 
logic [NUMCHANNELS-1:0] csa_testpulse_enable;
logic [NUMCHANNELS-1:0] done;                 // high when ADC conversion finished
logic [TESTPULSE_DAC_BITS-1:0] csa_testpulse_dac;
logic [3:0] adc_ibias_delay_monitor; // one hot monitor (see docs)
logic [3:0] current_monitor_bank0; // one hot monitor (see docs)
logic [3:0] current_monitor_bank1; // one hot monitor (see docs)
logic [3:0] current_monitor_bank2; // one hot monitor (see docs)
logic [3:0] current_monitor_bank3; // one hot monitor (see docs)
logic [2:0] voltage_monitor_bank0; // one hot monitor (see docs)
logic [2:0] voltage_monitor_bank1; // one hot monitor (see docs)
logic [2:0] voltage_monitor_bank2; // one hot monitor (see docs)
logic [2:0] voltage_monitor_bank3; // one hot monitor (see docs)
logic [7:0] voltage_monitor_refgen; // one hot monitor (see docs)
logic en_analog_monitor; // high to enable analog monitor buffer
logic [3:0] tx_slices0; // number of LVDS slices for POSI0 link
logic [3:0] tx_slices1; // number of LVDS slices for POSI1 link
logic [3:0] tx_slices2; // number of LVDS slices for POSI2 link
logic [3:0] tx_slices3; // number of LVDS slices for POSI3 link
logic [3:0] i_tx_diff0; // TX0 bias current (diff)
logic [3:0] i_tx_diff1; // TX1 bias current (diff)
logic [3:0] i_tx_diff2; // TX2 bias current (diff)
logic [3:0] i_tx_diff3; // TX3 bias current (diff)
logic [3:0] i_rx0; // RX0 bias current (lvds mode)
logic [3:0] i_rx1; // RX1 bias current (lvds mode)
logic [3:0] i_rx2; // RX2 bias current (lvds mode)
logic [3:0] i_rx3; // RX3 bias current (lvds mode)
logic [3:0] i_rx_clk; // RX_CLK bias current (lvds mode)
logic [3:0] i_rx_rst; // RX_RST bias current (lvds mode)
logic [3:0] i_rx_ext_trig; // RX_EXT_TRIG bias current 
logic [4:0] r_term0; // RX0 termination resistor
logic [4:0] r_term1; // RX1 termination resistor
logic [4:0] r_term2; // RX2 termination resistor
logic [4:0] r_term3; // RX3 termination resistor
logic [4:0] r_term_clk; // RX_CLK termination resistor
logic [4:0] r_term_rst; // RX_RST termination resistor
logic [4:0] r_term_ext_trig; // RX_EXT_TRIG termination resistor
logic [3:0] v_cm_lvds_tx0;   // TX0 CM output voltage (lvds mode)
logic [3:0] v_cm_lvds_tx1;   // TX1 CM output voltage (lvds mode)
logic [3:0] v_cm_lvds_tx2;   // TX2 CM output voltage (lvds mode)
logic [3:0] v_cm_lvds_tx3;   // TX3 CM output voltage (lvds mode)


// real-number modeled analog circuits
analog_core
    #(.NUMCHANNELS(NUMCHANNELS),
    .VREF(VREF),
    .VCM(VCM),
    .ADCBITS(ADCBITS),
    .PIXEL_TRIM_DAC_BITS(PIXEL_TRIM_DAC_BITS),
    .GLOBAL_DAC_BITS(GLOBAL_DAC_BITS),
    .CFB_CSA(CFB_CSA),
    .VOUT_DC_CSA(VOUT_DC_CSA),
    .VDDA(VDDA),
    .VOFFSET(VOFFSET)
    ) analog_core_inst (
    .dout                   (dout),
    .hit                    (hit),
    .done                   (done),
    .pixel_trim_dac         (pixel_trim_dac),
    .threshold_global       (threshold_global),
    .csa_gain               (csa_gain),
    .csa_bypass_enable      (csa_bypass_enable),
    .csa_monitor_select     (csa_monitor_select),
    .csa_bypass_select      (csa_bypass_select),
    .sample                 (sample),
    .csa_reset              (csa_reset),   
    .charge_in_r            (charge_in_r)
    );

// synthesizable RTL
digital_core
/*    #(.WIDTH(WIDTH),
    .NUMCHANNELS(NUMCHANNELS),
    .ADCBITS(ADCBITS),
    .PIXEL_TRIM_DAC_BITS(PIXEL_TRIM_DAC_BITS),
    .GLOBAL_DAC_BITS(GLOBAL_DAC_BITS),
    .WORDWIDTH(WORDWIDTH),
    .REGNUM(REGNUM),
    .CHIP_ID_W(CHIP_ID_W),
    .FIFO_DEPTH(FIFO_DEPTH)
    ) 
*/    digital_core_inst (
    .piso                           (piso),
    .digital_monitor                (digital_monitor),
    .sample                         (sample),
    .tx_enable                      (tx_enable),
    .pixel_trim_dac                 (pixel_trim_dac),
    .threshold_global               (threshold_global),
    .csa_gain                       (csa_gain),
    .csa_reset                      (csa_reset),
    .bypass_caps_enable             (bypass_caps_enable),
    .ibias_tdac                     (ibias_tdac),
    .ibias_comp                     (ibias_comp),
    .ibias_buffer                   (ibias_buffer),
    .ibias_csa                      (ibias_csa),
    .ibias_vref_buffer              (ibias_vref_buffer),
    .ibias_vcm_buffer               (ibias_vcm_buffer),
    .ibias_tpulse                   (ibias_tpulse),
    .adc_ibias_delay                (adc_ibias_delay),
    .ref_current_trim               (ref_current_trim),
    .adc_comp_trim                  (adc_comp_trim),
//    .override_ref                   (override_ref),
//    .ref_kickstart                  (ref_kickstart),
    .vref_dac                       (vref_dac),
    .vcm_dac                        (vcm_dac),
    .csa_bypass_enable              (csa_bypass_enable),
    .csa_bypass_select              (csa_bypass_select),
    .csa_monitor_select             (csa_monitor_select),
    .csa_testpulse_enable           (csa_testpulse_enable),
    .csa_testpulse_dac              (csa_testpulse_dac),
    .adc_ibias_delay_monitor        (adc_ibias_delay_monitor),
    .current_monitor_bank0          (current_monitor_bank0),
    .current_monitor_bank1          (current_monitor_bank1),
    .current_monitor_bank2          (current_monitor_bank2),
    .current_monitor_bank3          (current_monitor_bank3),
    .voltage_monitor_bank0          (voltage_monitor_bank0),
    .voltage_monitor_bank1          (voltage_monitor_bank1),
    .voltage_monitor_bank2          (voltage_monitor_bank2),
    .voltage_monitor_bank3          (voltage_monitor_bank3),
    .voltage_monitor_refgen         (voltage_monitor_refgen),
    .en_analog_monitor              (en_analog_monitor),
    .tx_slices0                     (tx_slices0),
    .tx_slices1                     (tx_slices1),
    .tx_slices2                     (tx_slices2),
    .tx_slices3                     (tx_slices3),
    .i_tx_diff0                     (i_tx_diff0),
    .i_tx_diff1                     (i_tx_diff1),
    .i_tx_diff2                     (i_tx_diff2),
    .i_tx_diff3                     (i_tx_diff3),
    .i_rx0                          (i_rx0),
    .i_rx1                          (i_rx1),
    .i_rx2                          (i_rx2),
    .i_rx3                          (i_rx3),
    .i_rx_clk                       (i_rx_clk),
    .i_rx_rst                       (i_rx_rst),
    .i_rx_ext_trig                  (i_rx_ext_trig),
    .r_term0                        (r_term0),
    .r_term1                        (r_term1),
    .r_term2                        (r_term2),
    .r_term3                        (r_term3),
    .r_term_clk                     (r_term_clk),
    .r_term_rst                     (r_term_rst),
    .r_term_ext_trig                (r_term_ext_trig),
    .v_cm_lvds_tx0                  (v_cm_lvds_tx0),
    .v_cm_lvds_tx1                  (v_cm_lvds_tx1),
    .v_cm_lvds_tx2                  (v_cm_lvds_tx2),
    .v_cm_lvds_tx3                  (v_cm_lvds_tx3),
    .dout                           (dout),
    .done                           (done),
    .hit                            (hit),
    .external_trigger               (external_trigger),
    .posi                           (posi),
    .clk                            (clk),
    .reset_n                        (reset_n)
    );
    
endmodule
