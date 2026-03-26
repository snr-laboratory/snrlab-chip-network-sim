///////////////////////////////////////////////////////////////////
// File Name: async2sync.sv
// Engineer:  Carl Grace (crgrace@lbl.gov)
// Description: Synchronizes a asynchronous signal to the "clk" domain
/////////////////////////////////////////////////////////////////

module async2sync
    (output logic sync,
    input logic async,
    input logic clk);

logic delay;

always_ff @(posedge clk)
    if (async)
        {sync,delay} <= 2'b01;
    else
        {sync,delay} <= {delay,1'b0};
endmodule // async2sync


