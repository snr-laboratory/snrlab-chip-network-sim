///////////////////////////////////////////////////////////////////
// File Name: larpix.v
// Author:  Carl Grace (crgrace@lbl.gov)
// Description: Full-chip behavioral model for LArPix.  
//              Uses production synthesziable RTL.
//              Uses real-value modeling analog circuits.
//
///////////////////////////////////////////////////////////////////

module larpix
    (output miso,     // MASTER-IN-SLAVE-OUT TX UART output bit
    output monitor_out, // analog bias monitor
    input [32*64-1:0] charge_in_b,     // analog input signal
    input [7:0] chip_id, // unique id for each chip
    input external_trigger,      // high to trigger channels
    input mosi,                  // MASTER-OUT-SLAVE-IN: RX UART input bit  
    input clk2x,                // 2X oversampling RX UART clk
    input reset_n);             // asynchronous digital reset (active low)

// instantiation parameters

parameter VREF = 1.0;       // top end of ADC range
parameter VCM = 0.5;        // bottom end of ADC range
parameter WIDTH = 54;       // width of packet (w/o start & stop bits) 
parameter WORDWIDTH = 8;    // width of programming registers
parameter NUMCHANNELS = 32; // number of analog channels
parameter ADCBITS = 8;      // number of bits in ADC
parameter PIXEL_TRIM_DAC_BITS = 5;  // number of bits in pixel trim DAC
parameter GLOBAL_DAC_BITS = 8;  // number of bits in global threshold DAC
parameter TESTPULSE_DAC_BITS = 8;  // number of bits in testpulse DAC
parameter CFB_CSA = 50e-15;         // feedback capacitor in CSA
parameter VOUT_DC_CSA = 0.5;        // nominal dc output voltage of CSA
parameter REGNUM = 63;         // number of programming registers
parameter CHIP_ID_W = 8;    // width of chip ID
parameter CHANNEL_ID_W = 5; // width of channel ID
parameter TIME_STAMP_W = 24;    // number of bits in time stamp
parameter PERIODIC_RESET_W = 24;    // number of bits for reset counter
parameter ADC_BURST_SIZE = 8;   // width of ADC burst register
parameter FIFO_DEPTH = 16;      // number of FIFO memory locations
parameter CONFIG_DEFAULTS = {504'h00_01_00_FF_FF_FF_FF_00_00_00_00_00_00_FF_01_00_00_FF_FF_FF_FF_00_00_00_00_00_00_00_00_07_10,{32{8'h10}}};


wire [NUMCHANNELS*ADCBITS-1:0] dac_word;  
wire [NUMCHANNELS-1:0] sample; 
wire [NUMCHANNELS-1:0] strobe; 
wire [NUMCHANNELS-1:0] reset_csa; 
wire [NUMCHANNELS-1:0] hit; 
wire [NUMCHANNELS-1:0] comp; 

// CONFIG BITS
wire [PIXEL_TRIM_DAC_BITS-1:0] pixel_trim_dac_0; 
wire [PIXEL_TRIM_DAC_BITS-1:0] pixel_trim_dac_1; 
wire [PIXEL_TRIM_DAC_BITS-1:0] pixel_trim_dac_2; 
wire [PIXEL_TRIM_DAC_BITS-1:0] pixel_trim_dac_3; 
wire [PIXEL_TRIM_DAC_BITS-1:0] pixel_trim_dac_4; 
wire [PIXEL_TRIM_DAC_BITS-1:0] pixel_trim_dac_5; 
wire [PIXEL_TRIM_DAC_BITS-1:0] pixel_trim_dac_6; 
wire [PIXEL_TRIM_DAC_BITS-1:0] pixel_trim_dac_7; 
wire [PIXEL_TRIM_DAC_BITS-1:0] pixel_trim_dac_8; 
wire [PIXEL_TRIM_DAC_BITS-1:0] pixel_trim_dac_9; 
wire [PIXEL_TRIM_DAC_BITS-1:0] pixel_trim_dac_10; 
wire [PIXEL_TRIM_DAC_BITS-1:0] pixel_trim_dac_11; 
wire [PIXEL_TRIM_DAC_BITS-1:0] pixel_trim_dac_12; 
wire [PIXEL_TRIM_DAC_BITS-1:0] pixel_trim_dac_13; 
wire [PIXEL_TRIM_DAC_BITS-1:0] pixel_trim_dac_14; 
wire [PIXEL_TRIM_DAC_BITS-1:0] pixel_trim_dac_15; 
wire [PIXEL_TRIM_DAC_BITS-1:0] pixel_trim_dac_16; 
wire [PIXEL_TRIM_DAC_BITS-1:0] pixel_trim_dac_17; 
wire [PIXEL_TRIM_DAC_BITS-1:0] pixel_trim_dac_18; 
wire [PIXEL_TRIM_DAC_BITS-1:0] pixel_trim_dac_19; 
wire [PIXEL_TRIM_DAC_BITS-1:0] pixel_trim_dac_20; 
wire [PIXEL_TRIM_DAC_BITS-1:0] pixel_trim_dac_21; 
wire [PIXEL_TRIM_DAC_BITS-1:0] pixel_trim_dac_22; 
wire [PIXEL_TRIM_DAC_BITS-1:0] pixel_trim_dac_23; 
wire [PIXEL_TRIM_DAC_BITS-1:0] pixel_trim_dac_24; 
wire [PIXEL_TRIM_DAC_BITS-1:0] pixel_trim_dac_25; 
wire [PIXEL_TRIM_DAC_BITS-1:0] pixel_trim_dac_26; 
wire [PIXEL_TRIM_DAC_BITS-1:0] pixel_trim_dac_27; 
wire [PIXEL_TRIM_DAC_BITS-1:0] pixel_trim_dac_28; 
wire [PIXEL_TRIM_DAC_BITS-1:0] pixel_trim_dac_29; 
wire [PIXEL_TRIM_DAC_BITS-1:0] pixel_trim_dac_30; 
wire [PIXEL_TRIM_DAC_BITS-1:0] pixel_trim_dac_31; 
wire [GLOBAL_DAC_BITS-1:0] threshold_global;  
wire [NUMCHANNELS-1:0] csa_gain;
wire [NUMCHANNELS-1:0] csa_bypass_enable;
wire [NUMCHANNELS-1:0] csa_testpulse_enable;
wire [NUMCHANNELS-1:0] csa_bypass_select;
wire [NUMCHANNELS-1:0] csa_monitor_select;
wire [TESTPULSE_DAC_BITS-1:0] csa_testpulse_dac;
wire [1:0] internal_bias;
wire [1:0] internal_bypass;

// real-number modeled analog circuits
analog_core
    #(.NUMCHANNELS(NUMCHANNELS),
    .VREF(VREF),
    .VCM(VCM),
    .ADCBITS(ADCBITS),
    .PIXEL_TRIM_DAC_BITS(PIXEL_TRIM_DAC_BITS),
    .GLOBAL_DAC_BITS(GLOBAL_DAC_BITS),
    .CFB_CSA(CFB_CSA),
    .VOUT_DC_CSA(VOUT_DC_CSA)
    ) analog_core_inst (
    .comp           (comp),
    .hit            (hit),
    .pixel_trim_dac_0   (pixel_trim_dac_0),
    .pixel_trim_dac_1   (pixel_trim_dac_1),
    .pixel_trim_dac_2   (pixel_trim_dac_2),
    .pixel_trim_dac_3   (pixel_trim_dac_3),
    .pixel_trim_dac_4   (pixel_trim_dac_4),
    .pixel_trim_dac_5   (pixel_trim_dac_5),
    .pixel_trim_dac_6   (pixel_trim_dac_6),
    .pixel_trim_dac_7   (pixel_trim_dac_7),
    .pixel_trim_dac_8   (pixel_trim_dac_8),
    .pixel_trim_dac_9   (pixel_trim_dac_9),
    .pixel_trim_dac_10  (pixel_trim_dac_10),
    .pixel_trim_dac_11  (pixel_trim_dac_11),
    .pixel_trim_dac_12  (pixel_trim_dac_12),
    .pixel_trim_dac_13  (pixel_trim_dac_13),
    .pixel_trim_dac_14  (pixel_trim_dac_14),
    .pixel_trim_dac_15  (pixel_trim_dac_15),
    .pixel_trim_dac_16  (pixel_trim_dac_16),
    .pixel_trim_dac_17  (pixel_trim_dac_17),
    .pixel_trim_dac_18  (pixel_trim_dac_18),
    .pixel_trim_dac_19  (pixel_trim_dac_19),
    .pixel_trim_dac_20  (pixel_trim_dac_20),
    .pixel_trim_dac_21  (pixel_trim_dac_21),
    .pixel_trim_dac_22  (pixel_trim_dac_22),
    .pixel_trim_dac_23  (pixel_trim_dac_23),
    .pixel_trim_dac_24  (pixel_trim_dac_24),
    .pixel_trim_dac_25  (pixel_trim_dac_25),
    .pixel_trim_dac_26  (pixel_trim_dac_26),
    .pixel_trim_dac_27  (pixel_trim_dac_27),
    .pixel_trim_dac_28  (pixel_trim_dac_28),
    .pixel_trim_dac_29  (pixel_trim_dac_29),
    .pixel_trim_dac_30  (pixel_trim_dac_30),
    .pixel_trim_dac_31  (pixel_trim_dac_31),
    .threshold_global   (threshold_global),
    .csa_gain           (csa_gain),
    .csa_bypass_enable         (csa_bypass_enable),
    .csa_monitor_select (csa_monitor_select),
    .csa_bypass_select (csa_bypass_select),
    .charge_in_b    (charge_in_b),
    .dac_word       (dac_word),
    .sample         (sample),
    .strobe         (strobe),
    .reset_csa      (reset_csa)   
    );

// synthesizable RTL
digital_core
    #(.WIDTH(WIDTH),
    .NUMCHANNELS(NUMCHANNELS),
    .ADCBITS(ADCBITS),
    .PIXEL_TRIM_DAC_BITS(PIXEL_TRIM_DAC_BITS),
    .GLOBAL_DAC_BITS(GLOBAL_DAC_BITS),
    .WORDWIDTH(WORDWIDTH),
    .REGNUM(REGNUM),
    .CHIP_ID_W(CHIP_ID_W),
    .CHANNEL_ID_W(CHANNEL_ID_W),
    .TIME_STAMP_W(TIME_STAMP_W),
    .PERIODIC_RESET_W(PERIODIC_RESET_W),
    .ADC_BURST_SIZE(ADC_BURST_SIZE),
    .FIFO_DEPTH(FIFO_DEPTH),
    .CONFIG_DEFAULTS(CONFIG_DEFAULTS)
    ) digital_core_inst (
    .miso               (miso),
    .dac_word           (dac_word),
    .reset_csa          (reset_csa),
    .sample             (sample),
    .strobe             (strobe),
    .pixel_trim_dac_0   (pixel_trim_dac_0),
    .pixel_trim_dac_1   (pixel_trim_dac_1),
    .pixel_trim_dac_2   (pixel_trim_dac_2),
    .pixel_trim_dac_3   (pixel_trim_dac_3),
    .pixel_trim_dac_4   (pixel_trim_dac_4),
    .pixel_trim_dac_5   (pixel_trim_dac_5),
    .pixel_trim_dac_6   (pixel_trim_dac_6),
    .pixel_trim_dac_7   (pixel_trim_dac_7),
    .pixel_trim_dac_8   (pixel_trim_dac_8),
    .pixel_trim_dac_9   (pixel_trim_dac_9),
    .pixel_trim_dac_10  (pixel_trim_dac_10),
    .pixel_trim_dac_11  (pixel_trim_dac_11),
    .pixel_trim_dac_12  (pixel_trim_dac_12),
    .pixel_trim_dac_13  (pixel_trim_dac_13),
    .pixel_trim_dac_14  (pixel_trim_dac_14),
    .pixel_trim_dac_15  (pixel_trim_dac_15),
    .pixel_trim_dac_16  (pixel_trim_dac_16),
    .pixel_trim_dac_17  (pixel_trim_dac_17),
    .pixel_trim_dac_18  (pixel_trim_dac_18),
    .pixel_trim_dac_19  (pixel_trim_dac_19),
    .pixel_trim_dac_20  (pixel_trim_dac_20),
    .pixel_trim_dac_21  (pixel_trim_dac_21),
    .pixel_trim_dac_22  (pixel_trim_dac_22),
    .pixel_trim_dac_23  (pixel_trim_dac_23),
    .pixel_trim_dac_24  (pixel_trim_dac_24),
    .pixel_trim_dac_25  (pixel_trim_dac_25),
    .pixel_trim_dac_26  (pixel_trim_dac_26),
    .pixel_trim_dac_27  (pixel_trim_dac_27),
    .pixel_trim_dac_28  (pixel_trim_dac_28),
    .pixel_trim_dac_29  (pixel_trim_dac_29),
    .pixel_trim_dac_30  (pixel_trim_dac_30),
    .pixel_trim_dac_31  (pixel_trim_dac_31),
    .threshold_global   (threshold_global),
    .csa_gain           (csa_gain),
    .csa_bypass_enable  (csa_bypass_enable),
    .csa_testpulse_enable (csa_testpulse_enable),
    .csa_monitor_select (csa_monitor_select),
    .csa_bypass_select (csa_bypass_select),
    .csa_testpulse_dac  (csa_testpulse_dac),
    .internal_bias      (internal_bias),
    .internal_bypass    (internal_bypass),
    .comp               (comp),
    .hit                (hit),
    .chip_id            (chip_id),
    .external_trigger   (external_trigger),
    .mosi               (mosi),
    .clk2x              (clk2x),
    .reset_n            (reset_n)
);


endmodule
