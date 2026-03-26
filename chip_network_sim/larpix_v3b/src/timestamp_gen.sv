///////////////////////////////////////////////////////////////////
// File Name: timestamp_gen.sv
// Engineer:  Carl Grace (crgrace@lbl.gov)
// Description: N-bit Time Stamp Counter
//
///////////////////////////////////////////////////////////////////

module timestamp_gen
    #(parameter int unsigned TS_LENGTH = 28)
    (output logic [TS_LENGTH-1:0] timestamp,  // time stamp for event builder
    input logic sync_timestamp, // timestamp set to 0 when high
    input logic clk,             // master clock
    input logic reset_n);         // digital reset (active low)

always_ff @ (posedge clk or negedge reset_n)
    if (!reset_n) timestamp <= '0;
    else
        if (sync_timestamp) timestamp <= '0;
        else timestamp <= timestamp + 1'b1;
endmodule
