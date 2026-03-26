
`timescale 1ns/10ps

module fifo_tb();


parameter FIFO_WIDTH = 63;
parameter integer unsigned FIFO_DEPTH = 2048;   // FIFO memory size (RAM) -- hardwired
parameter FIFO_BITS = 11;
parameter NUMTESTS = 2000;

// FIFO signals
logic    [FIFO_WIDTH-1:0] data_out;
logic [15:0] number_of_tests;
logic   debug;
logic    full;
logic   half;
logic    empty;
logic     [FIFO_WIDTH-1:0] data_in;
logic     read_n;
logic     write_n;
logic   [FIFO_BITS:0] fifo_counter;
logic     clk;
logic     reset_n;
logic fifo_burst_test;
logic [7:0] chip_id;
logic [31:0] timestamp_32b;
logic [31:0] write_count;
logic [31:0] read_count;
logic select_fifo_latch;
integer index;
integer fifo_count;         // number of bytes in fifo
integer errors;
logic [FIFO_WIDTH-1:0] data_expected; // expected fifo data (for scoreboard)
logic     fast_read;          // read fast
logic     fast_write;         // write fast
logic     filled_flag;        // set high when fifo has been filled
logic     cycle_count;        // count number of cycles
// ---- DUT -----

fifo_top 
    #(.FIFO_WIDTH(FIFO_WIDTH),
    .FIFO_DEPTH(FIFO_DEPTH),
    .FIFO_BITS(FIFO_BITS)
     ) fifo_top_inst (
    .data_out           (data_out),
    .fifo_counter       (fifo_counter),
    .fifo_full           (full),
    .fifo_half           (half),
    .fifo_empty          (empty),
    .data_in            (data_in),
    .read_n             (read_n),
    .write_n            (write_n),
    .chip_id            (chip_id),
    .timestamp_32b      (timestamp_32b),
    .clk                (clk),
    .reset_n            (reset_n)
    );

initial begin
    number_of_tests = NUMTESTS;
    clk = 0;
    chip_id = 8'h0f;
    timestamp_32b = 32'h0f00;
    fifo_burst_test = 0;
    forever #50 clk = ~clk;
end

initial begin
    debug = 1;
    write_count = 0;
    read_count = 0;
    select_fifo_latch = 1; // 0 = latch, 1 = RAM
    data_in = 0;
    data_expected = 0;
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

// verify status outputs

    if (empty !== 1) begin
        $display("ERROR at time %0t:", $time);
        $display("After reset, empty status not asserted");
    end

    if (full !== 0) begin
        $display("ERROR at time %0t:", $time);
        $display("After reset, full status asserted");
    end
// load FIFO with initial values

//    #7 write_n = 0;

    for (index = 0; index < NUMTESTS; index = index + 1) begin
        data_in = write_count;
        write_count = write_count + 1;
        @(posedge clk);
        if (debug) begin
            $display("write %d to FIFO at time %0t:",write_count, $time);
        end
        @(posedge clk);
       
        write_n = 0;
        @(posedge clk);
        write_n = 1;
    end

// check FIFO outputs

    write_n = 1;
    read_n = 1;
    for (index = 0; index < NUMTESTS/2; index = index + 1) begin
        data_expected = read_count;
        read_count = read_count + 1;
        @(posedge clk);
        read_n = 0;
        @(posedge clk);
        read_n = 1;
        @(posedge clk);
        if (data_out != data_expected) begin
            $display("ERROR at time %0t:", $time);
            $display("Expected data out = %d", data_expected);
            $display("actual data out = %d", data_out);
            errors = errors + 1;
        end
        if (debug) begin
            $display("FIFO read #%d)",index);
//            $display("Expected data out = %d", data_expected);
            $display("actual data out = %d", data_out);
        end            

    end

// load some more (and check wraparound)
    
    for (index = 0; index < NUMTESTS/2; index = index + 1) begin
        data_in = write_count;
        write_count = write_count + 1;
        @(posedge clk);
        if (debug) begin
            $display("write %d to FIFO at time %0t:",write_count, $time);
        end
        @(posedge clk);        
        write_n = 0;
        @(posedge clk);        
        write_n = 1;
    end

    write_n = 1;
    read_n = 1;
    for (index = 0; index < NUMTESTS/2; index = index + 1) begin
        data_expected = read_count;
        read_count = read_count + 1;
        @(posedge clk);
         read_n = 0;
        @(posedge clk);
        read_n = 1;
        @(posedge clk);
        if (data_out != data_expected) begin
            $display("ERROR at time %0t:", $time);
            $display("Expected data out = %d", data_expected);
            $display("actual data out = %d", data_out);
            errors = errors + 1;
        end
        if (debug) begin
            $display("FIFO read #%d)",index);
//            $display("Expected data out = %d", data_expected);
            $display("actual data out = %d", data_out);
        end            

    end

    if (errors == 0) begin
        $display("FIFO_TEST PASSED: no errors");
    end
    else begin
        $display("FIFO_TEST FAILED: %d errors",errors);
    end
  
end // initial

endmodule

