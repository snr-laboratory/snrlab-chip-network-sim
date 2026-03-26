///////////////////////////////////////////////////////////////////
// File Name: sar_adc_cdc.sv
// Engineer:  Tarun Prakash (tprakash@lbl.gov)
// Description: Synchronizes a asynchronous dout and done signals to the "clk" domain
/////////////////////////////////////////////////////////////////

module sar_adc_cdc
    (input logic clk,   // core clock
    input logic reset_n,         // active-low reset
    input logic done_async,    // async done from ADC
    input logic [9:0] dout_async,    // async dout bus from ADC
    output logic done_sync,     // synchronized done
    output logic [9:0] dout_sync      // registered dout
);
// Stage 1: Double-flop synchronizer for 'done'
logic done_meta; // first stage
logic done_prev; // for edge detect
logic done_samp; // used to sample dout
 
always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        done_meta <= 1'b0;
        done_samp <= 1'b0;
        done_sync <= 1'b0;
        done_prev <= 1'b0;
    end else begin
        done_meta <= done_async;  // first sync stage
        done_samp <= done_meta;   // second sync stage
        done_prev <= done_samp; //store previous value for edge detect
        done_sync <= done_prev;
    end
end

// Stage 2: Capture dout only when done_sync rises
always_ff @(posedge clk or negedge reset_n)
    if (!reset_n)
        dout_sync <= '0;
    else if (done_samp && !done_prev)
        dout_sync <= dout_async;  // capture async bus when done is stable
endmodule
