
`timescale 1ns/10ps

module fifo_burst_tb();


parameter FIFO_WIDTH = 63;
parameter FIFO_DEPTH_RAM = 2048;  // number of memory locations
parameter FIFO_DEPTH_LATCH = 512;  // number of memory locations
parameter FIFO_BITS_RAM = $clog2(FIFO_DEPTH_RAM);     // number of bits to describe fifo addr range
parameter FIFO_BITS_LATCH = $clog2(FIFO_DEPTH_LATCH);     // number of bits to describe fifo addr range

// FIFO signals
logic    [FIFO_WIDTH-1:0] data_out;
logic    full;
logic   half;
logic    empty;
logic     [FIFO_WIDTH-1:0] data_in;
logic     read_n;
logic     write_n;
logic   [FIFO_BITS_RAM:0] fifo_counter;
logic     clk;
logic     reset_n;
logic fifo_burst_test;
logic [7:0] chip_id;
logic [31:0] timestamp_32b;
logic select_fifo_latch;
integer index;
integer fifo_count;         // number of bytes in fifo
integer errors;
logic [FIFO_WIDTH-1:0] expected_data; // expected fifo data (for scoreboard)
logic     fast_read;          // read fast
logic     fast_write;         // write fast
logic     filled_flag;        // set high when fifo has been filled
logic     cycle_count;        // count number of cycles

logic [1:0] rcvd_packet_type;
logic [7:0] rcvd_chip_id;
logic [18:0] rcvd_timestamp_32b;
logic [12:0] rcvd_fifo_burst_counter;
logic rcvd_fifo_full;
logic rcvd_fifo_half;
logic rcvd_downstream_marker;


// ---- DUT -----

fifo_top 
    #(.FIFO_WIDTH(FIFO_WIDTH),
    .FIFO_DEPTH_LATCH(FIFO_DEPTH_LATCH),
    .FIFO_BITS_LATCH(FIFO_BITS_LATCH),
    .FIFO_DEPTH_RAM(FIFO_DEPTH_RAM),
    .FIFO_BITS_RAM(FIFO_BITS_RAM)
     ) fifo_top_inst (
    .data_out           (data_out),
    .fifo_counter       (fifo_counter),
    .fifo_full           (full),
    .fifo_half           (half),
    .fifo_empty          (empty),
    .data_in            (data_in),
    .read_n             (read_n),
    .write_n            (write_n),
    .select_fifo_latch  (select_fifo_latch),
    .fifo_burst_test    (fifo_burst_test),
    .chip_id            (chip_id),
    .timestamp_32b      (timestamp_32b),
    .clk                (clk),
    .reset_n            (reset_n)
    );

always_ff @(posedge clk) begin
    rcvd_packet_type = data_out[1:0];
    rcvd_chip_id = data_out[9:2];
    rcvd_timestamp_32b = data_out[34:16];
    rcvd_fifo_burst_counter = data_out[47:35];
    rcvd_fifo_full = data_out[60];
    rcvd_fifo_half = data_out[61];
    rcvd_downstream_marker = data_out[62];
end // always_ff


initial begin
    clk = 0;
    forever #50 clk = ~clk;
end // initial

initial begin
    chip_id = 8'h0f;
    timestamp_32b = 32'h00000f00;
    fifo_burst_test = 0;
    select_fifo_latch = 0;
    data_in = 0;
    expected_data = 0;
    fifo_count = 0;
    read_n = 1;
    write_n = 1;
    filled_flag = 0;
    cycle_count = 0;
    clk = 1;
    fast_write = 1;
    fast_read = 0;
    reset_n = 1;
    errors = 0;
// reset fifo
    #20 reset_n = 0;
    #20 reset_n = 1;
// start burst test
    #100 fifo_burst_test = 1;
    #3000000 fifo_burst_test = 0;
    $display("BURST TEST FINISHED");
// read out FIFO
    #20 write_n = 1;
    read_n = 0;
    for (index = 0; index < FIFO_DEPTH_RAM; index = index + 1) begin
        @(posedge clk);
        read_n = 0;
        #150 read_n = 1;
    end
    #10000 fifo_burst_test = 1;
    #3000000 fifo_burst_test = 0;
    $display("BURST TEST FINISHED AGAIN");
// read out FIFO
    #20 write_n = 1;
    read_n = 0;
    for (index = 0; index < FIFO_DEPTH_RAM; index = index + 1) begin
        @(posedge clk);
        read_n = 0;
        #150 read_n = 1;
    end
      
end // initial

endmodule
