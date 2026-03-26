`timescale 1ns/10ps
//
module digital_core_tb();

// parameters

parameter VREF = 1.0;       // top end of ADC range
parameter VCM = 0.5;        // bottom end of ADC range
parameter WIDTH = 54;       // width of packet (w/o start & stop bits) 
parameter WORDWIDTH = 8;    // width of programming registers
parameter NUMCHANNELS = 32; // number of analog channels
parameter ADCBITS = 6;      // number of bits in ADC
parameter REGMAP_ADDR_WIDTH = 7; // bits to describe regmap addr range
parameter REGNUM = 128;     // number of programming registers
parameter CHIP_ID_W = 8;    // width of chip ID
parameter CHANNEL_ID_W = 7; // width of channel ID
parameter TIME_STAMP_W = 24;// number of bits in time stamp
parameter FIFO_DEPTH = 64;  // number of FIFO memory locations
parameter FIFO_BITS = 6;    // # of bits to describe fifo addr range

reg reset_n;
reg ld_tx_data;
reg [WIDTH-1:0] tx_data; // sent to DUT from FPGA
wire [WIDTH-1:0] rx_data; // received by FPGA from DUT
reg [WIDTH-1:0] sent_data;
reg tx_enable;
wire mosi;
wire miso;
wire tx_busy;
reg clk4x;
reg clktx;

reg [CHIP_ID_W-1:0] chip_id;      // unique id for each chip
wire [NUMCHANNELS*ADCBITS-1:0] dac_word;  
wire [NUMCHANNELS-1:0] sample; 
wire [NUMCHANNELS-1:0] strobe; 
wire [NUMCHANNELS-1:0] arm; 
wire [NUMCHANNELS-1:0] comp; 

reg [NUMCHANNELS-1:0] hit; 
reg [WORDWIDTH-1:0] addr;
reg [WORDWIDTH-1:0] data;

// control FPGA rx uart
reg uld_rx_data;

wire [REGNUM*WORDWIDTH-1:0] regmap_bits;

wire [63:0] vi_b;
real vi_r;

assign vi_b = $realtobits(vi_r);

initial begin
    vi_r = 0.76;
    uld_rx_data = 0;
    clk4x = 0;
    clktx = 0;
    hit = 0;
    reset_n = 1;
    tx_enable = 1;
    ld_tx_data = 0;
    addr = 8'h03;
    data = 8'h01;
    chip_id = 8'b00000100;
    tx_data = {(WIDTH-2){1'b0}};
    tx_data[1:0] = 2'b10;  // register write
    tx_data[9:2] = chip_id;
    tx_data[17:10] = addr;
    tx_data[25:18] = data;
//    tx_data[51] = 0;
   tx_data[WIDTH-1] = ~^tx_data[WIDTH-2:0];
    #40 reset_n = 0;
    sent_data = tx_data;
    #40 reset_n = 1;
    #20 ld_tx_data = 1;
    #20 ld_tx_data = 0;
    #100 hit = 1 << 4;
    #100 hit = 0;
    #2000 hit = 1;
    #100 hit = 0;
    #2000 uld_rx_data = 1;

/*    wait (!rx_empty);
        #100 if (rx_data != sent_data)
        $display ("ERROR: rx data different from tx data\n");
    else
        $display ("rx data matches tx data\n");
*/
// now simulate an event waiting to be loaded into the fifo

    
end


// Clock generation
always #1 clk4x = ~clk4x;
always #4 clktx = ~clktx;

// This UART instance models the programming FPGA
uart_tx 
    #(.WIDTH(WIDTH)
    ) tx (
    .reset_n    (reset_n),
    .txclk      (clktx),
    .ld_tx_data (ld_tx_data),
    .tx_data    (tx_data),
    .tx_enable  (tx_enable),
    .tx_out     (mosi),
    .tx_busy    (tx_busy)
);

// UART RX for testing TX here (this is in the receive FPGA)
uart_rx
    #(.WIDTH(WIDTH)
    ) rx (
    .reset_n      (reset_n),
    .rxclk        (clk4x),
    .uld_rx_data  (uld_rx_data),
    .rx_data      (rx_data),
    .rx_enable    (1'b1),
    .rx_in        (miso),
    .rx_empty     (rx_empty)
);

// These SAR ADC cores model the analog blocks in the 32 SAR ADCs
genvar i;
generate
    for (i=0; i<NUMCHANNELS; i=i+1) begin : CHANNELS

        // analog model of SAR core
        sar_adc_core
        #(.VREF(VREF),
        .VCM(VCM),
        .ADCBITS(ADCBITS)
        ) sar_adc_core_inst (
        .comp       (comp[i]),
        .sample     (sample[i]),
        .strobe     (strobe[i]),
        .dac_word   (dac_word[ADCBITS*(i+1)-1:ADCBITS*i]),
        .vi_b       (vi_b)
        );

    end
endgenerate

// DUT Connected here
digital_core
    #(.WIDTH(WIDTH),
    .NUMCHANNELS(NUMCHANNELS),
    .ADCBITS(ADCBITS),
    .WORDWIDTH(WORDWIDTH),
    .REGMAP_ADDR_WIDTH(REGMAP_ADDR_WIDTH),
    .REGNUM(REGNUM),
    .CHIP_ID_W(CHIP_ID_W),
    .TIME_STAMP_W(TIME_STAMP_W),
    .FIFO_DEPTH(FIFO_DEPTH),
    .FIFO_BITS(FIFO_BITS)
    ) digital_core_inst (
    .miso           (miso),
    .regmap_bits    (regmap_bits),
    .dac_word       (dac_word),
    .sample         (sample),
    .strobe         (strobe),
    .fifo_full      (fifo_full),
    .arm_channel    (arm),
    .comp           (comp),
    .hit            (hit),
    .chip_id        (chip_id),
    .mosi           (mosi),
    .clk4x          (clk4x),
    .reset_n        (reset_n)
);


endmodule
