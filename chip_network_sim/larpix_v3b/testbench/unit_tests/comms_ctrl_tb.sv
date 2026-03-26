`timescale 1ns/10ps
//
module comms_ctrl_tb();

// parameters
parameter WIDTH = 54;

reg     reset_n;
reg     ld_tx_data;
reg     [51:0] tx_data;
reg     [51:0] sent_data;
reg     tx_enable;
wire    tx_out;
wire    tx_busy;
wire    uld_rx_data;
wire    [WIDTH-1:0] rx_data;
reg     rx_enable;
wire    rx_in;
wire    rx_empty;
reg     txclk;
reg     rxclk;

reg     [7:0] chip_id;      // unique id for each chip
wire    [53:0] finished_event; // event to put into fifo
wire    write_fifo_n;
wire    write_regmap;
reg     [52:0] pre_event;
reg     load_event;

reg     [7:0] addr;
reg     [7:0] data;

wire [7:0] regmap_write_data;
wire [7:0] regmap_address;
wire [7:0] regmap_read_data;
wire [63:0] regmap_bits;

initial begin
    txclk = 0;
    rxclk = 0;
    reset_n = 1;
    tx_enable = 1;
    rx_enable = 1;
    ld_tx_data = 0;
    load_event = 0;
    pre_event = 0;
    addr = 8'h03;
    data = 8'h01;
    chip_id = 5'b00100;
    tx_data = {52{1'b0}};
    tx_data[1:0] = 2'b10;  // register write
    tx_data[7:2] = chip_id;
    tx_data[15:8] = addr;
    tx_data[23:16] = data;
//    tx_data[51] = 0;
   tx_data[51] = ~^tx_data[50:0];
    #40 reset_n = 0;
    sent_data = tx_data;
    #40 reset_n = 1;
    #20 ld_tx_data = 1;
    #20 ld_tx_data = 0;
    wait (!rx_empty);
        #100 if (rx_data != sent_data)
        $display ("ERROR: rx data different from tx data\n");
    else
        $display ("rx data matches tx data\n");

// now simulate an event waiting to be loaded into the fifo

    
end

// connect output of DUT to testbench RX
assign rx_in = tx_out;

// RX and TX Clock generation
always #1 rxclk = ~rxclk;
always #4 txclk = ~txclk;


// DUT Connected here
uart_tx 
    #(.WIDTH(WIDTH)
    ) tx (
    .reset_n    (reset_n),
    .txclk      (txclk),
    .ld_tx_data (ld_tx_data),
    .tx_data    (tx_data),
    .tx_enable  (tx_enable),
    .tx_out     (tx_out),
    .tx_busy    (tx_busy)
);

// UART RX for testing TX here
uart_rx
    #(.WIDTH(WIDTH)
    ) rx (
    .reset_n      (reset_n),
    .rxclk        (rxclk),
    .uld_rx_data  (uld_rx_data ),
    .rx_data      (rx_data),
    .rx_enable    (rx_enable),
    .rx_in        (rx_in),
    .rx_empty     (rx_empty)
);

comms_ctrl
    comms (
    .finished_event (finished_event),
    .regmap_write_data  (regmap_write_data),
    .regmap_address (regmap_address),
    .write_fifo_n   (write_fifo_n),
    .read_fifo_n    (read_fifo_n),
    .ld_tx_data     (ld_tx_data),
    .uld_rx_data    (uld_rx_data),
    .write_regmap   (write_regmap),
    .rx_data        (rx_data),
    .pre_event      (pre_event),
    .chip_id        (chip_id),
    .regmap_read_data   (regmap_read_data),
    .fifo_empty     (fifo_empty),
    .rx_empty       (rx_empty),
    .tx_empty       (tx_empty),
    .load_event     (load_event),
    .clk            (txclk),
    .reset_n        (reset_n)
);

// spi register map
spi_regmap#(
    .WORDWIDTH(8),
    .REGMAP_ADDR_WIDTH(8),
    .REGNUM(8))
    REGMAP (
    .spi_read_data      (regmap_read_data),
    .spi_bits           (regmap_bits),
    .spi_write_data     (regmap_write_data),
    .spi_addr           (regmap_address),
    .write              (write_regmap),
    .reset_n            (reset_n)
);


endmodule
