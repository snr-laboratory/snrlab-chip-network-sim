`timescale 1ns/1ps
`default_nettype none
//
module lightpix_single_tb();

//`include "larpix_tasks_top.v"

// parameters

parameter E_CHARGE = 1.6e-19;   // electronic charge in Columbs
parameter NUM_E = 100e3;      // number of electrons in charge packet
parameter NUM_E_10 = 75e3;      // number of electrons in charge packet
parameter VREF = 1.0;       // top end of ADC range
parameter VCM = 0.5;        // bottom end of ADC range
parameter WIDTH = 64;       // width of packet (w/o start & stop bits) 
parameter WORDWIDTH = 8;    // width of programming registers
parameter NUMCHANNELS = 64; // number of analog channels
parameter ADCBITS = 8;      // number of bits in ADC
parameter PIXEL_TRIM_DAC_BITS = 5;  // number of bits in pixel trim DAC
parameter GLOBAL_DAC_BITS = 8;  // number of bits in global threshold DAC
parameter TESTPULSE_DAC_BITS = 8;  // number of bits in testpulse DAC
parameter CFB_CSA = 50e-15;         // feedback capacitor in CSA
parameter VOUT_DC_CSA = 0.5;        // nominal dc output voltage of CSA
parameter REGNUM = 256;     // number of programming registers
parameter FIFO_DEPTH = 512;  // number of FIFO memory locations
parameter FIFO_BITS = 9;    // # of bits to describe fifo addr range
parameter MIP = -2.8e-15;  // electron MIP gives 70 mV at CSA output
parameter QRAMPTIME_IN_US = 10; // risetime of charge ramp in microsec
parameter QIN_START = 0.0; // where charge ramp begins
parameter QIN_STEP = (5*MIP)/(QRAMPTIME_IN_US*10);

logic miso [3:0];  // MASTER-IN-SLAVE-OUT TX UART output bit
logic miso_bar [3:0];
logic mosi [3:0];  // MASTER-OUT-SLAVE-IN RX UART output bit

logic clk, clk_delay;
logic reset_n;
logic restart_ramp;
logic disable_ramp;
logic digital_monitor;
real monitor_out_r;

logic external_trigger;
// real number arrays are not allowed, so we have to do this the hard way 
real charge_in_r [NUMCHANNELS-1:0];
real q_ramp_r;
real q_ramp_old_r;
real q_in_r;
//real charge_in_chan1_r;
//real charge_in_chan10_r;
logic [63:0] sentTag;

always
    clk_delay = #12 clk;

initial begin
    restart_ramp = 0;
    disable_ramp = 1;
    external_trigger = 0;
    mosi[1] = 1;
    mosi[2] = 1;
    mosi[3] = 1;
end



// MCP goes here
mcp_lightpix_single
    #(.WIDTH(WIDTH),
    .WORDWIDTH(WORDWIDTH),
    .REGNUM(REGNUM),
    .FIFO_DEPTH(FIFO_DEPTH) 
    ) mcp_inst (
    .mosi           (mosi[0]),
    .charge_in_r    (charge_in_r),
    .clk            (clk),
    .reset_n        (reset_n),
    .miso           (miso[0])
);

// single LightPix
// DUT (LightPix full-chip model) is connected to FPGA
lightpix
    lightpix_inst (
    .miso               (miso),
    .miso_bar           (miso_bar),
    .digital_monitor    (digital_monitor),
    .monitor_out_r      (monitor_out_r),
    .charge_in_r        (charge_in_r),
    .external_trigger   (external_trigger),
    .mosi               (mosi),
    .clk                (clk_delay),
    .reset_n            (reset_n)   
    );


endmodule
