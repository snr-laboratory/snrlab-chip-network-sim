///////////////////////////////////////////////////////////////////
// File Name: fifo_latch.sv
// Engineer:  Carl Grace (crgrace@lbl.gov) and
// Description: Asynchronous FIFO (controlled by read and write pulses).
//              Temporarily stores data until it can be
//              processed or sent off chip.
//              Parity of word is stored in FIFO
///////////////////////////////////////////////////////////////////

module fifo_latch
    #(parameter integer FIFO_WIDTH = 64, // width of each FIFO word
    parameter integer unsigned FIFO_DEPTH = 256,   // number of FIFO memory locations
    parameter integer unsigned FIFO_BITS = 8)
    (output logic [FIFO_WIDTH-1:0] data_out, // FIFO output data
    output logic [FIFO_BITS:0] fifo_counter, // how many fifo locations used
    output logic fifo_full,         // high when fifo is in overflow
    output logic fifo_half,         // high when fifo is half full
    output logic fifo_empty,        // high when fifo is in underflow
    input logic [FIFO_WIDTH-1:0] data_in, // fifo input data
    input logic read_n,                // read data from fifo (active low)
    input logic write_n,               // write data to fifo (active low)
    input logic clk,
    input logic reset_n);             // digital reset (active low)

// fifo memory array (latches)
logic [FIFO_WIDTH-1:0] fifo_mem [FIFO_DEPTH];
//internal signals
logic [FIFO_BITS-1:0] write_pointer, read_pointer;
logic [FIFO_DEPTH-1:0] gatedWrClk;

`ifdef  INITIALIZE_MEMORY
//integer i;
initial
    for(int i =  0;i<FIFO_DEPTH;i =  i+1)
    fifo_mem[i] = {FIFO_WIDTH{1'b0}};
`endif

// write logic
always_ff @ (posedge clk or negedge reset_n)
    if (!reset_n)
        write_pointer <= '0;
    else if (!write_n && !fifo_full)
            write_pointer <= write_pointer + 1'b1;

// read logic
always_ff @ (posedge clk or negedge reset_n)
    if (!reset_n)
        read_pointer <= '0;
    else if (!read_n && !fifo_empty)
        read_pointer <= read_pointer + 1'b1;

// latch fifo output on negedge of clock (so only 100ns)
always_ff  @(negedge clk or negedge reset_n)
    if (!reset_n)
        data_out <= '0;
    else if (!read_n)
        data_out <= fifo_mem[read_pointer];

//  Counter / status flags
always_ff @(posedge clk or negedge reset_n)
    if (!reset_n)
        fifo_counter <= '0;
    else
        case ({!write_n && !fifo_full, !read_n && !fifo_empty})
            2'b10: fifo_counter <= fifo_counter + 1'b1;   // write only
            2'b01: fifo_counter <= fifo_counter - 1'b1;   // read only
            default: fifo_counter <= fifo_counter;// no change or simultaneous r/w
        endcase

always_comb begin
    fifo_full  = (fifo_counter == FIFO_DEPTH);
    fifo_half  = (fifo_counter >= FIFO_DEPTH/2);
    fifo_empty = (fifo_counter == 0);
end // always_comb

// implement memory as latches to save die area
genvar g_j;
for(g_j=0; g_j < FIFO_DEPTH; g_j++) begin : g_fifo_latches
    gate_negedge_clk write_en_gatedclk(
        .CLK(clk),
        .EN((!write_n) & (write_pointer == g_j)),
        .ENCLK(gatedWrClk[g_j]));

    always_latch
        if (!gatedWrClk[g_j])
            fifo_mem[g_j] <= data_in;
end
endmodule // fifo_latch


