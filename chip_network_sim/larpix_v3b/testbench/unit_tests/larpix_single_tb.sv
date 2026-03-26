`timescale 1ns/1ps
`default_nettype wire
//`default_nettype none
//
module larpix_single_tb();

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

//logic piso [3:0];  // PRIMARY-IN-SECONDARY-OUT TX UART output bit
//logic posi [3:0];  // PRIMARY-OUT-SECONDARY-IN RX UART output bit
logic [3:0] piso;  // PRIMARY-IN-SECONDARY-OUT TX UART output bit
logic [3:0] posi;  // PRIMARY-OUT-SECONDARY-IN RX UART output bit

logic clk, clk_delay;
logic reset_n, reset_n_delay;
logic restart_ramp;
logic disable_ramp;
logic digital_monitor;
real monitor_out_r;
logic posi_to_larpix;
logic torture; // set = 1 when you want to hit LArPix with 4 posi words at same time
logic external_trigger;
// real number arrays are not allowed, so we have to do this the hard way 
real charge_in_r [NUMCHANNELS-1:0];
real q_ramp_r;
real q_ramp_old_r;
real q_in_r;

always begin
    clk_delay = #12 clk;
    //clk_delay = #5 clk;
end

`ifdef SDF
    initial 
		    $sdf_annotate(`SDF_FILE, `SDF_SCOPE, ,"sdf_boc.log", ,,);
`endif

initial begin
    restart_ramp = 0;
    disable_ramp = 1;
    external_trigger = 0;
    //posi = 4'b1111;
    torture = 0;
    if (torture) $display("Torture setting ON! (send words to all POSIs)");

// uncomment for ver_ext_trig.mcp
/*
#40000
$display("issue external_trigger (expected to be ignored)");
external_trigger = 1;
#200
external_trigger = 0;

#200000
$display("issue external_trigger (expected to work)");
external_trigger = 1;
#200
external_trigger = 0;
*/

// uncomment for ver_ext_sync.mcp
/*
#40000
$display("issue external_sync (expected to be ignored)");
external_trigger = 1;
#200
external_trigger = 0;

#200000
$display("issue external_sync (expected to work)");
external_trigger = 1;
#200
external_trigger = 0;
*/

/*
#10000

    for (int trigNum = 0; trigNum < 20; trigNum++) begin
        #20000 
        @(posedge clk)
        #1 external_trigger = 1;
        #200 
        @(posedge clk)
        #1 external_trigger = 0;
        $display("EXTERNAL TRIGGER number %0d",trigNum);
    end // for
*/

/*
#300000

    for (int trigNum = 0; trigNum < 20; trigNum++) begin
        #100000 
        @(posedge clk)
        #1 external_trigger = 1;
        #200 
        @(posedge clk)
        #1 external_trigger = 0;
        $display("EXTERNAL TRIGGER number %0d",trigNum);
    end // for

*/

end // begin

// set torture=0 when you don't want the same word going to all four posi ports)

always_comb begin
    posi = 4'h0;
    if (torture == 1) begin
        for (int i=0; i < 4; i++) begin
            posi[i] = posi_to_larpix;
        end
    end else begin
        for (int i=0; i < 4; i++) begin
            if (i==1)
                posi[i] = posi_to_larpix;
            else 
                posi[i] = 1'b1;
        end
    end
end // always_comb
            
        

// MCP goes here
mcp_larpix_single
    #(.WIDTH(WIDTH),
    .WORDWIDTH(WORDWIDTH),
    .REGNUM(REGNUM),
    .FIFO_DEPTH(FIFO_DEPTH) 
    ) mcp_inst (
    .posi           (posi_to_larpix),
    .charge_in_r    (charge_in_r),
    .clk            (clk),
    .reset_n        (reset_n),
    .piso           (piso[0])
);

// single LArPix
// DUT (LArPix full-chip model) LArPix is connected to FPGA
larpix_v3b
    larpix_v3b_inst (
    .piso               (piso),
    .digital_monitor    (digital_monitor),
    .monitor_out_r      (monitor_out_r),
    .charge_in_r        (charge_in_r),
    .external_trigger   (external_trigger),
    .posi               (posi),
    .clk                (clk),
    .reset_n            (reset_n)   
    );


endmodule
