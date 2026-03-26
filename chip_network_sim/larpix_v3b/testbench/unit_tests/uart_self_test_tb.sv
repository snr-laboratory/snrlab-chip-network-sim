`timescale 1ns/10ps
//
module uart_tb();

// parameters
parameter WIDTH = 64;
localparam PRBS5 = 31'h6B3E3750;

logic reset_n;
logic ld_tx_data;
logic tx_out;
logic tx_out_comp;
logic tx_busy;
logic uld_rx_data;
logic [WIDTH-2:0] rx_data;
logic differential_uart;
logic rx_enable;
logic tx_enable;
logic rx_empty;
logic txclk;
logic rxclk;
logic sync_timestamp;
logic [31:0] timestamp_32b;
logic [WIDTH-2:0] fifo_data;
logic [WIDTH-2:0] expected_data;
logic [1:0] test_mode;

//logic[7:0] i;
integer errors;

initial begin
// $dumpfile("uart.vcd");
//  $dumpvars();
    tx_enable = 1;
    rx_enable = 1; 
    differential_uart = 1; 
    txclk = 0;
    rxclk = 0;
    reset_n= 1;
    ld_tx_data = 0;
    uld_rx_data = 0;
    test_mode = 0;
    errors = 0;
    sync_timestamp = 0;
    #40 reset_n= 0;
    #40 reset_n= 1;

    fifo_data = {{15{4'hA}}};
//    fifo_data[WIDTH-1] = ~^fifo_data[WIDTH-2:0];
//    $display("fifo_data[WIDTH-2] = %b",fifo_data[WIDTH-2]);
    if (test_mode == 0) begin
        expected_data = fifo_data;
        $display("FIFO TEST: sent data = %h",expected_data);
    end else if (test_mode == 1) begin
        expected_data = {2'b00,{PRBS5},{PRBS5}};
        $display("FIFO TEST: PRBS5 test");
    end else if (test_mode == 2) begin
        expected_data = 0;
        $display("FIFO TEST: timestamp dump");
    end
        #20 ld_tx_data = 1;
        #20 ld_tx_data = 0;
        wait (!rx_empty);
        #100 $display("FIFO TEST: received data = %h", rx_data);
        if (rx_data[WIDTH-2:0] != expected_data[WIDTH-2:0]) begin
            $display ("ERROR: rx data different from tx data\n");
            $display ("rx_data = %h, fifo_data = %h",rx_data,expected_data);
            errors = errors + 1;
        end else begin
            $display ("rx data matches expected_data\n");
            $display ("rx_data = %h, expected_data = %h",rx_data,expected_data);        end
        // check parity
        if (rx_data[WIDTH-1] != ~^rx_data[WIDTH-2:0]) begin
            $display ("FIFO TEST: parity error!");
            $display ("Expected parity = %b",~^rx_data[WIDTH-2]);
            $display ("Received parity = %b",rx_data[WIDTH-1]);
        
//  #100 tx_data = {{53{2'b11}},8'b1110_0111};
   
//  #20 ld_tx_data = 1; 
//  #20 ld_tx_data = 0;
    end // for
    $display("UART TEST: All tests complete with %1d errors",errors);
end // always

// RX and master Clock generation
// // rx clock is 4x tx clock (clk goes through div4 to generate tx_clk)
always #1 rxclk = ~rxclk;
always #2 txclk = ~txclk;

// read RX data when done to allow another read
always @ (negedge rx_empty)
begin
  #20 uld_rx_data = 1;
  #20 uld_rx_data = 0;
end // always block

// DUT Connected here
//
uart
    #(.WIDTH(WIDTH)
    ) uart (
    .rx_data        (rx_data),
    .rx_empty       (rx_empty),
    .tx_out         (tx_out),
    .tx_out_comp    (tx_out_comp),
    .tx_busy        (tx_busy),
    .rx_in          (tx_out),  // loopback
    .uld_rx_data    (uld_rx_data),
    .test_mode      (test_mode),
    .fifo_data      (fifo_data),
    .timestamp_32b  (timestamp_32b),
    .ld_tx_data     (ld_tx_data),
    .differential_uart (differential_uart),
    .rx_enable      (rx_enable),
    .tx_enable      (tx_enable),
    .txclk          (txclk),
    .rxclk          (rxclk),
    .reset_n        (reset_n),
    .reset_n_clk2x  (reset_n)
);

timestamp_gen
    timestamp_gen_inst (
    .timestamp_32b(timestamp_32b),
    .sync_timestamp(sync_timestamp),
    .clk    (txclk),
    .reset_n (reset_n)
    );

endmodule
