
`timescale 1ns/10ps

module fifo_latch_tb();


parameter FIFO_WIDTH = 8;
parameter FIFO_DEPTH = 8;  // number of memory locations
parameter FIFO_BITS = 4;     // number of bits to describe fifo addr range

// FIFO signals
wire    [FIFO_WIDTH-1:0] data_out;
wire    full;
wire    empty;
reg     [FIFO_WIDTH-1:0] data_in;
reg     read_n;
reg     write_n;
reg     clk;
reg     reset_n;

integer index;
integer fifo_count;         // number of bytes in fifo
reg [FIFO_WIDTH-1:0] expected_data; // expected fifo data (for scoreboard)
reg     fast_read;          // read fast
reg     fast_write;         // write fast
reg     filled_flag;        // set high when fifo has been filled
reg     cycle_count;        // count number of cycles
// ---- DUT -----

fifo_latch
    #(.FIFO_WIDTH(FIFO_WIDTH),
    .FIFO_DEPTH(FIFO_DEPTH),
    .FIFO_BITS(FIFO_BITS)
     ) fifo_inst (
    .data_out       (data_out),
    .full           (full),
    .empty          (empty),
    .data_in        (data_in),
    .read_n         (read_n),
    .write_n        (write_n),
    .clk            (clk),
    );

initial begin
    data_in = 0;
    expected_data = 0;
    fifo_count = 0;
    read_n = 1;
    write_n = 1;
    filled_flag = 0;
    cycle_count = 0;
    fast_write = 1;
    fast_read = 0;
    reset_n = 1;

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

write_n = 0;

    for (index = 0; index < FIFO_DEPTH; index = index + 1) begin
        data_in = 8'hfa;
        #200 write_n = 0;
    end

// check FIFO outputs

    write_n = 1;
    read_n = 0;
    for (index = 0; index < FIFO_DEPTH; index = index + 1) begin
        #200 read_n = 0;
        if (data_out != data_in) begin
            $display("ERROR at time %0t:", $time);
            $display("Expected data out = %h", data_in);
            $display("actual data out = %h", data_out);
        end
    end
    read_n = 1;

end // initial

// clock


//simulate fifo
/*
always @(posedge clk) begin

// update count (if read and no write, or write and no read)

    if (!write_n && read_n)
        fifo_count = fifo_count + 1;
    else if (!read_n && write_n)
        fifo_count = fifo_count - 1;

end

always @(negedge clk) begin
    if (!read_n && (data_out != expected_data)) begin
        $display("ERROR at time %0t:", $time);
        $display("Expected data out = %h", expected_data);
        $display("actual data out = %h", data_out);
    end

// check whether to assert write_n
// don't write the fifo if it is already full

    if ((fast_write || (cycle_count & 1'b1)) && ~full) begin
        write_n = 0;
        data_in = data_in + 1;
    end else
        write_n = 1;

// check whether to assert read_n
// don't read the fifo if it is already empty

    if ((fast_write || (cycle_count & 1'b1)) && ~empty) begin
        read_n = 0;
        expected_data = expected_data + 1;
    end else
        read_n = 1;

// when fifo is full, begin reading faster than writing to empty it
    if (full) begin
        fast_read = 1;
        fast_write = 0;
        filled_flag = 1;
    end

// when the fifo has been filled and then empty, simulation done
    if (filled_flag && empty) begin
        $display("Simulation complete. No errors");
        $finish;
    end

    cycle_count = cycle_count + 1;
end

always @(fifo_count) begin
    #1
    case (fifo_count)
        0: begin
            if ((empty !== 1) || (half !== 0) || (full !== 0)) begin
                $display("ERROR at time %0t:", $time);
                $display("fifo_count = %h", fifo_count);
                $display("empty = %b", empty);
                $display("half = %b", half);
                $display("full = %b", full);
            end

            if (filled_flag === 1) begin
                // FIFO filled and emptied
                $display("Simulation complete. No errors");
            end
        end
        FIFO_HALF: begin
            if ((empty !== 0) || (half !== 1) || (full !== 0)) begin
                $display("ERROR at time %0t:", $time);
                $display("fifo_count = %h", fifo_count);
                $display("empty = %b", empty);
                $display("half = %b", half);
                $display("full = %b", full);
            end
        end
        FIFO_DEPTH: begin
            if ((empty !== 0) || (half !== 0) || (full !== 1)) begin
                $display("ERROR at time %0t:", $time);
                $display("fifo_count = %h", fifo_count);
                $display("empty = %b", empty);
                $display("half = %b", half);
                $display("full = %b", full);
            end
            
            // fifo is filled so set flag
            filled_flag = 1;
            // once filled empty it
            fast_write = 0;
            fast_read = 1;
         end

        default: begin
            if ((empty !== 0) || (full !== 0)) begin
                $display("ERROR at time %0t:", $time);
                $display("fifo_count = %h", fifo_count);
                $display("empty = %b", empty);
                $display("half = %b", half);
                $display("full = %b", full);
            end

            if (((fifo_count < FIFO_HALF) && (half === 1)) || ((fifo_count >= FIFO_HALF) && (half === 0))) begin
                $display("ERROR at time %0t:", $time);
                $display("fifo_count = %h", fifo_count);
                $display("empty = %b", empty);
                $display("half = %b", half);
                $display("full = %b", full);
            end
        end
    endcase
end
 */             
endmodule // spi_tb
