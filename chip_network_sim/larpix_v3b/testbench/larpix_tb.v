`timescale 1ns/1ps
`default_nettype none
//
module larpix_tb();

//`include "larpix_tasks_top.v"

// parameters

parameter E_CHARGE = 1.6e-19;   // electronic charge in Columbs
parameter NUM_E = 100e3;      // number of electrons in charge packet
parameter NUM_E_10 = 75e3;      // number of electrons in charge packet
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
parameter REGMAP_ADDR_WIDTH = 7; // bits to describe regmap addr range
parameter REGNUM = 63;     // number of programming registers
parameter CHIP_ID_W = 8;    // width of chip ID
parameter CHANNEL_ID_W = 5; // width of channel ID
parameter TIME_STAMP_W = 24;// number of bits in time stamp
parameter PERIODIC_RESET_W = 24; // number of bits for reset counter
parameter FIFO_DEPTH = 512;  // number of FIFO memory locations
parameter FIFO_BITS = 9;    // # of bits to describe fifo addr range
parameter CONFIG_DEFAULTS = {504'h00_01_00_FF_FF_FF_FF_00_00_00_00_00_00_FF_01_00_00_FF_FF_FF_FF_00_00_00_00_00_00_00_00_07_10,{32{8'h10}}};

wire mosi;
wire miso1;
wire miso2;
wire miso3;
wire clk2x;
wire reset_n;
wire monitor_out;
wire monitor_out2;
wire monitor_out3;

wire [NUMCHANNELS*64-1:0] charge_in_b;
wire [NUMCHANNELS*64-1:0] charge_in_b2;
wire [NUMCHANNELS*64-1:0] charge_in_b3;
reg [CHIP_ID_W-1:0] chip_id1;
reg [CHIP_ID_W-1:0] chip_id2;
reg [CHIP_ID_W-1:0] chip_id3;
reg external_trigger;
// real number arrays are not allowed, so we have to do this the hard way 
real charge_in_chan0_r;
real charge_in_chan1_r;
real charge_in_chan10_r;
reg [63:0] sentTag;


initial begin

    chip_id1 = 8'b00000100; // chip 1 ID is 4
    chip_id2 = 8'b00000001; // chip 2 ID is 1
    chip_id3 = 8'b00001111; // chip 3 ID is 15
    external_trigger = 0;

    charge_in_chan0_r = 0;
    charge_in_chan10_r = 0;

    #449.862

    #19649.95
    $display("SWITCHING INPUT CHARGE");
    $display("CHANNEL 0 HOT");
    charge_in_chan0_r = NUM_E*E_CHARGE;  
    charge_in_chan1_r = NUM_E_10*E_CHARGE;
    charge_in_chan10_r = 0.5*NUM_E_10*E_CHARGE;
    #3
    charge_in_chan0_r = 0;
    charge_in_chan1_r = 0;
    charge_in_chan10_r = 0;
    $display("INPUT CHARGE RTZ");

    #100000
    $display("EXTERNAL TRIGGER ENGAGED");
    external_trigger = 1;
    #100
    external_trigger = 0;

end


assign charge_in_b2 = 0;
assign charge_in_b2 = 0;
assign charge_in_b[63:0] = $realtobits(charge_in_chan0_r);
assign charge_in_b3[127:64] = $realtobits(charge_in_chan1_r);

assign charge_in_b[((11*64)-1):10*64] = $realtobits(charge_in_chan10_r);

// MCP goes here
mcp_analog
//mcp_regmap
    #(.WIDTH(WIDTH),
    .WORDWIDTH(WORDWIDTH),
    .REGNUM(REGNUM),
    .FIFO_DEPTH(FIFO_DEPTH) 
    ) mcp_inst (
    .mosi       (mosi),
    .clk2x      (clk2x),
    .reset_n    (reset_n),
    .miso       (miso3)
);

// 3 LArPix chips in series
// DUT (LARPIX full-chip model) LArPix1 is connected to FPGA
larpix
    larpix_inst (
    .miso           (miso1),
    .monitor_out    (monitor_out),
    .charge_in_b    (charge_in_b),
    .chip_id        (chip_id1),
    .external_trigger   (external_trigger),
    .mosi           (mosi),
    .clk2x          (clk2x),
    .reset_n        (reset_n)   
    );

larpix
    larpix_inst_2 (
    .miso           (miso2),
    .monitor_out    (monitor_out2),
    .charge_in_b    (charge_in_b2),
    .chip_id        (chip_id2),
    .external_trigger   (external_trigger),
    .mosi           (miso1),
    .clk2x          (clk2x),
    .reset_n        (reset_n)   
    );

larpix
    larpix_inst_3 (
    .miso           (miso3),
    .monitor_out    (monitor_out3),
    .charge_in_b    (charge_in_b3),
    .chip_id        (chip_id3),
    .external_trigger   (external_trigger),
    .mosi           (miso2),
    .clk2x          (clk2x),
    .reset_n        (reset_n)   
    );

endmodule
