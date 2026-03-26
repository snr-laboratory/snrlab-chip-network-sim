///////////////////////////////////////////////////////////////////
// File Name: larpix_v2.sv
// Engineer:  Carl Grace (crgrace@lbl.gov)
// Description: Full-chip behavioral model for LArPix.  
//              Uses production synthesziable RTL.
//              Uses real-value modeling analog circuits.
//
///////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module larpix_v2
    #(parameter FIFO_DEPTH = 2048,
    LOCAL_FIFO_DEPTH = 4)
    (output logic [3:0] miso ,     // MASTER-IN-SLAVE-OUT TX UART output bit
    output logic [3:0] miso_bar , // MASTER-IN-SLAVE-OUT TX UART output bit
    output logic digital_monitor, // digital test port
    output real monitor_out_r, // analog bias monitor
    input real charge_in_r [63:0],     // analog input signal
    input logic external_trigger,      // high to trigger channels
    input logic [3:0] mosi,    // MASTER-OUT-SLAVE-IN: RX UART input bit  
    input logic clk,                  // master clk
    input logic reset_n);      // asynchronous digital reset (active low)

// instantiation parameters

parameter VREF = 1.3;       // top end of ADC range
parameter VCM = 0.3;        // bottom end of ADC range
parameter WIDTH = 64;       // width of packet (w/o start & stop bits) 
parameter WORDWIDTH = 8;    // width of programming registers
parameter NUMCHANNELS = 64; // number of analog channels
parameter ADCBITS = 8;      // number of bits in ADC
parameter PIXEL_TRIM_DAC_BITS = 5;  // number of bits in pixel trim DAC
parameter GLOBAL_DAC_BITS = 8;  // number of bits in global threshold DAC
parameter TESTPULSE_DAC_BITS = 8;  // number of bits in testpulse DAC
parameter CFB_CSA = 40e-15;         // feedback capacitor in CSA
parameter VOUT_DC_CSA = 0.5;        // nominal dc output voltage of CSA
parameter REGNUM = 256;         // number of programming registers
parameter CHIP_ID_W = 8;    // width of chip ID
parameter VDDA = 1.8;              // nominal analog supply
parameter VOFFSET = 0.47;         // discriminator threshold offset

// analog signals
logic [NUMCHANNELS*ADCBITS-1:0] dac_word;  
logic sample [NUMCHANNELS-1:0]; 
logic strobe [NUMCHANNELS-1:0]; 
logic csa_reset [NUMCHANNELS-1:0]; 
logic [NUMCHANNELS-1:0] hit; 
logic [NUMCHANNELS-1:0] comp; 

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
logic [4:0] ref_current_trim; // trims ref voltage
logic [7:0] vref_dac; // sets vref for adc
logic [7:0] vcm_dac; // sets vcm for adc
logic [NUMCHANNELS-1:0] csa_bypass_enable; // inject into adc from test pin
logic [NUMCHANNELS-1:0] csa_bypass_select; // adc channels(s)
logic [NUMCHANNELS-1:0] csa_monitor_select; // monitor channels 
logic [NUMCHANNELS-1:0] csa_testpulse_enable;
logic [TESTPULSE_DAC_BITS-1:0] csa_testpulse_dac;
logic [3:0] current_monitor_bank0; // one hot monitor (see docs)
logic [3:0] current_monitor_bank1; // one hot monitor (see docs)
logic [3:0] current_monitor_bank2; // one hot monitor (see docs)
logic [3:0] current_monitor_bank3; // one hot monitor (see docs)
logic [2:0] voltage_monitor_bank0; // one hot monitor (see docs)
logic [2:0] voltage_monitor_bank1; // one hot monitor (see docs)
logic [2:0] voltage_monitor_bank2; // one hot monitor (see docs)
logic [2:0] voltage_monitor_bank3; // one hot monitor (see docs)
logic [7:0] voltage_monitor_refgen; // one hot monitor (see docs)
logic [3:0] slope_control0;  // slope control for MISO0
logic [3:0] slope_control1;  // slope control for MISO1
logic [3:0] slope_control2;  // slope control for MISO2
logic [3:0] slope_control3;  // slope control for MISO3
logic ref_kickstart; // kickstart bit
logic override_ref; // override reference generator

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
    .comp                   (comp),
    .hit                    (hit),
    .pixel_trim_dac         (pixel_trim_dac),
    .threshold_global       (threshold_global),
    .csa_gain               (csa_gain),
    .csa_bypass_enable      (csa_bypass_enable),
    .csa_monitor_select     (csa_monitor_select),
    .csa_bypass_select      (csa_bypass_select),
    .dac_word               (dac_word),
    .sample                 (sample),
    .strobe                 (strobe),
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
    .miso                           (miso),
    .miso_bar                       (miso_bar),
    .digital_monitor                (digital_monitor),
    .dac_word                       (dac_word),
    .sample                         (sample),
    .strobe                         (strobe),
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
    .ref_current_trim               (ref_current_trim),
    .override_ref                   (override_ref),
    .ref_kickstart                  (ref_kickstart),
    .vref_dac                       (vref_dac),
    .vcm_dac                        (vcm_dac),
    .csa_bypass_enable              (csa_bypass_enable),
    .csa_bypass_select              (csa_bypass_select),
    .csa_monitor_select             (csa_monitor_select),
    .csa_testpulse_enable           (csa_testpulse_enable),
    .csa_testpulse_dac              (csa_testpulse_dac),
    .current_monitor_bank0          (current_monitor_bank0),
    .current_monitor_bank1          (current_monitor_bank1),
    .current_monitor_bank2          (current_monitor_bank2),
    .current_monitor_bank3          (current_monitor_bank3),
    .voltage_monitor_bank0          (voltage_monitor_bank0),
    .voltage_monitor_bank1          (voltage_monitor_bank1),
    .voltage_monitor_bank2          (voltage_monitor_bank2),
    .voltage_monitor_bank3          (voltage_monitor_bank3),
    .voltage_monitor_refgen         (voltage_monitor_refgen),
    .slope_control0                 (slope_control0),
    .slope_control1                 (slope_control1),
    .slope_control2                 (slope_control2),
    .slope_control3                 (slope_control3),
    .comp                           (comp),
    .hit                            (hit),
    .external_trigger               (external_trigger),
    .mosi                           (mosi),
    .clk                            (clk),
    .reset_n                        (reset_n)
    );
    
endmodule
