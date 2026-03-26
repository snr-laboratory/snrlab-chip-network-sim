// File Name: reset_sync.sv
// Engineer:  Carl Grace (crgrace@lbl.gov)
// Description: Synchronizes an asynchronous reset
//              to the different "clk" domains
//
//              if reset_n is held low for more than 4 clk cycles
//              then timestamp sync will be asserted.
//              if reset_n is held low for more than 32 clk cycles
//              then the config register reset will be asserted
/////////////////////////////////////////////////////////////////////

module reset_sync
    (output logic reset_n_sync,          //synchronized reset
    output logic reset_n_config_sync,   // reset config registers
    input clk,                          // master clk
    input reset_n);                     // asynchronous external reset

// local registers
logic [15:0] srg_clk;
logic [31:0] srg_config;
logic all_0;
logic all_0_config;

always_comb begin
    reset_n_sync = ~all_0;
    reset_n_config_sync = ~all_0_config;
end

// only change sync_timestamp value when the input is identical
// for 4 consecutive clock clk cycles
// this should filter out all meta stable states
// only sync reset when input is identical for another 12 clk cycles
// only sync reset_clk when input is identical for another 8 clk cycles
// this should make it easy to use the sync_timestamp function

// shift register for clk
always_ff @(negedge clk) begin
    srg_clk <= {srg_clk[14:0],reset_n};
    if (srg_clk [15:1] == 15'h0000) all_0 <= 1'b1;
    else all_0 <= 1'b0;

    srg_config <= {srg_config[30:0],reset_n};
    if (srg_config [31:1] == 31'h000000) all_0_config <= 1'b1;
    else all_0_config <= 1'b0;
end // always_ff
/*
//shift register for sync_config
always_ff @(negedge clk) begin
    srg_config <= {srg_config[30:0],reset_n};
    if (srg_config [31:1] == 31'h000000) all_0_config <= 1'b1;
    else all_0_config <= 1'b0;
end // always_ff
*/
endmodule

