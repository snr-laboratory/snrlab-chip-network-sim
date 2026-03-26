///////////////////////////////////////////////////////////////////
// File Name: mcp_external_interface.sv
// Engineer:  Carl Grace (crgrace@lbl.gov)
// Description:     LArPix Master Control Program
//                  Captures functionality of FPGA-based master interface
//                  Programs LArPix and reads out data
//                  This version is to simulate external digital interface.
//
///////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

module mcp_external_interface
    #(parameter WIDTH = 64,
    parameter WORDWIDTH = 8,
    parameter REGNUM = 182,
    parameter FIFO_DEPTH = 512
    )
    
(output mosi,       // MASTER OUT, SLAVE IN (input of larpix from FPGA)
    output logic clk,       // 4x oversampled clock sent to larpix 
    output logic reset_n,     // digital reset (active low)
    input miso);            // MASTER IN, SLAVE OUT (output of larpix to FPGA) 


// scoreboard
localparam SCOREBOARDSIZE = 100;
integer debug;
integer eventCount; // number of events digitized and written to scoreboard
integer scoreBoardCount; // number of events currently unmatched in scoreboard
logic [63:0] scoreBoard [SCOREBOARDSIZE-1:0]; // elements in scoreboard
                                // this should be linked list

logic ld_tx_data;
logic [WIDTH-1:0] data_to_larpix; // sent to DUT from FPGA
logic [WIDTH-2:0] data_from_larpix; // received by FPGA from DUT
logic [WIDTH-2:0] sent_data;
logic [WIDTH-2:0] receivedData;

logic [7:0] chip_id;      // unique id for each chip
logic [7:0] chip_id1;      // unique id for each chip
logic [7:0] chip_id2;      // unique id for each chip
//logic [7:0] chip_id3;      // unique id for each chip
logic [63:0] sentTag;     // tagged input signal to scoreboard
//logic [63:0] chargeSignal;

// control FPGA rx uart
logic uld_rx_data;
//logic [1:0] uart_op;
logic rx_empty;
logic tx_busy;

// parse rx data
logic [1:0] rcvd_packet_declare;
logic [7:0] rcvd_chip_id;
logic [5:0] rcvd_channel_id;
logic [31:0] rcvd_time_stamp;
logic [7:0] rcvd_data_word;
logic [1:0] rcvd_trigger_type;
logic [7:0] rcvd_regmap_data;
logic [7:0] rcvd_regmap_addr;
logic [10:0] rcvd_fifo_cnt;
logic rcvd_downstream_marker_bit;
logic rcvd_fifo_half_bit;
logic rcvd_fifo_full_bit;
logic rcvd_local_fifo_half_bit;
logic rcvd_local_fifo_full_bit;
logic parity_error;

always_comb begin
    rcvd_packet_declare = receivedData[1:0];
    rcvd_chip_id = receivedData[9:2];
    rcvd_channel_id = receivedData[15:10];
    rcvd_time_stamp = receivedData[47:16];
    rcvd_fifo_cnt = receivedData[47:38];

    rcvd_data_word = receivedData[55:48];
    rcvd_trigger_type = receivedData[57:56];
    rcvd_fifo_half_bit = receivedData[58];
    rcvd_fifo_full_bit = receivedData[59];
    rcvd_local_fifo_half_bit = receivedData[60];
    rcvd_local_fifo_full_bit = receivedData[61];
    rcvd_downstream_marker_bit = receivedData[62];

    rcvd_regmap_addr = receivedData[17:10];
    rcvd_regmap_data = receivedData[25:18];
end


parameter WRITE_TO_LOG = 0;     // high to write verification results to file
parameter NUMTRIALS_REGMAP = 100; // number of random REGMAP trials to run
parameter TEST_BURST_SIZE = 20;     // number of values to load into fifo
parameter GLOBAL_ID = 255;          // global broadcast ID
                                // during uart burst test
`include "../larpix_tasks/larpix_tasks_top.sv"

initial begin
    debug = TRUE;
    sentTag = 0;
//  debug = FALSE;
    ld_tx_data = 0;
    data_to_larpix = 0;
    eventCount = 0;
    scoreBoardCount = 0;
    chip_id = 8'b0000_0000; // chip ID is 0
    chip_id1 = 8'b0001_0000; // chip ID is 16
    chip_id2 = 8'b0001_1111; // chip ID is 31
    receivedData = 0;
    uld_rx_data = 0;
    clk = 0;
    reset_n = 1;
    #45 reset_n = 0;
    #100
    @(negedge clk) 
        reset_n = 1;
    $display("RESET COMPLETE");
    
/*
    $display("MCP_ANALOG running");
    genDataHit(1,32,2000,TRUE,sentTag,chargeSignal);
    #10
    genDataHit(1,32,2000,TRUE,sentTag,chargeSignal);
    #10    
    genDataHit(1,32,2000,TRUE,sentTag,chargeSignal);
    #10
    genDataHit(1,32,2000,TRUE,sentTag,chargeSignal);
*/

//#10000

// send word to register 1 of chip 1
    @(posedge clk)
//    sendWordToLarpix(CONFIG_WRITE_OP,8'h00,CHIP_ID,8'h01);
//    $display("EXTERNAL CONFIG WRITE TO larpix, chip = %h, register=0 DATA = 0x01",chip_id);
#10000
  $display("write value 8'hfe to IBIAS_TDAC"); 
  sendWordToLarpix(CONFIG_WRITE_OP,8'h00,IBIAS_TDAC,8'hfe);

#10000
  $display("read out IBIAS_TDAC0"); 
  sendWordToLarpix(CONFIG_READ_OP,8'h00,IBIAS_TDAC,0);

#10000
  $display("send data to wrong chip (pass along)"); 
  sendWordToLarpix(CONFIG_READ_OP,8'h01,IBIAS_TDAC,0);


/*



    sendWordToLarpix(CONFIG_WRITE_OP,chip_id2,0,8'hf0);
    $display("EXTERNAL CONFIG WRITE TO larpix, chip = %h, register=0 DATA = 0xf0",chip_id2);

#10000



   sendWordToLarpix(CONFIG_WRITE_OP,GLOBAL_ID,1,8'h0f);


#10000

#10000
  $display("read out logic 1 of chip 2"); 
  sendWordToLarpix(CONFIG_READ_OP,chip_id,1,0);


#10000

//  write word to logic 5 of chip 1 

    sendWordToLarpix(CONFIG_WRITE_OP,chip_id,5,8'h0F);
#10000

//  pass packet along (not meant for this chip)
    sendWordToLarpix(CONFIG_WRITE_OP,chip_id1,5,0);

// global read
#10000
   sendWordToLarpix(CONFIG_READ_OP,GLOBAL_ID,1,8'h0f);

*/


// enable fifo diagnostics
//    $display("FIFO DIAGNOSTICS ENABLED (CHIP 3)");
//    sendWordToLarpix(CONFIG_WRITE_OP,chip_id3,47,8'h10);


/*
// enable external trigger for channels 8 through 15 (CHIP 3)
    $display("EXTERNAL TRIGGER ENABLED, CHANNEL 24 through 31, CHIP 3");
    sendWordToLarpix(CONFIG_WRITE_OP,chip_id3,59,8'h00);
    $display("EXTERNAL TRIGGER ENABLED, CHANNEL 16 through 23, CHIP 3");
    sendWordToLarpix(CONFIG_WRITE_OP,chip_id3,58,8'h00);
    $display("EXTERNAL TRIGGER ENABLED, CHANNEL 8 through 15, CHIP 3");
    sendWordToLarpix(CONFIG_WRITE_OP,chip_id3,57,8'h00);
    $display("EXTERNAL TRIGGER ENABLED, CHANNEL 0 through 7, CHIP 3");
    sendWordToLarpix(CONFIG_WRITE_OP,chip_id3,56,8'h00);
*/
/*#1000

// enable fifo diagnostics
    $display("FIFO DIAGNOSTICS ENABLED");
    sendWordToLarpix(CONFIG_WRITE_OP,chip_id3,47,8'h10);
#1000
// mask out channel 0 of chip 1
    $display("MASK OUT CHANNEL 0, CHIP 1");
    sendWordToLarpix(CONFIG_WRITE_OP,chip_id1,52,8'h01);

// send cross trigger of chip 1
    $display("CROSS TRIGGER ENABLED, CHIP 1");
    sendWordToLarpix(CONFIG_WRITE_OP,chip_id1,47,8'h04);
#1000
// send word to register 38 of chip 1
    $display("MONITOR SELECT ENABLED, CHANNEL 0, CHIP 1");
    sendWordToLarpix(CONFIG_WRITE_OP,chip_id1,38,8'h01);
#1000
// send word to register 4 of chip 3
    sendWordToLarpix(CONFIG_WRITE_OP,chip_id3,4,8'hFE);
#1000
//  read out logic 0 of chip 1 
    sendWordToLarpix(CONFIG_READ_OP,chip_id1,0,0);
#1000
//  read out logic 4 of chip 3 
    sendWordToLarpix(CONFIG_READ_OP,chip_id3,4,0);
#1000
// send word to register 34 of chip 1
    $display("CSA BYPASS ENABLED, CHANNEL 0 through 3, CHIP 1");
    sendWordToLarpix(CONFIG_WRITE_OP,chip_id1,34,8'h0F);
*/
// test periodic reset
//    $display("ENABLE PERIODIC RESET");
//    sendWordToLarpix(CONFIG_WRITE_OP,chip_id1,47,8'h18);
//#10000
//     $display("DISABLE PERIODIC RESET");
//    sendWordToLarpix(CONFIG_WRITE_OP,chip_id1,47,8'h10);
   

//    #4000
// write a word to chip 2 (pixel trim 1) 
//   sendWordToLarpix(CONFIG_WRITE_OP,chip_id2,0,8'hFF);
// write a word to chip 1 to mask hot channel
//   sendWordToLarpix(CONFIG_WRITE_OP,chip_id1,51,8'h01);

//#1000
//    $display("config_test");   
//    config_test(VERBOSE,WRITE_TO_LOG,chip_id1);
//    #1000

// test defaults. first load_defaults, then soft_reset
//    defaults_test(VERBOSE,WRITE_TO_LOG,chip_id,0);
//    defaults_test(VERBOSE,WRITE_TO_LOG,chip_id,1);

// check raw test mode for uart (alternating 0s and 1s)
//    uart_raw_test(VERBOSE,WRITE_TO_LOG,TEST_BURST_SIZE,chip_id1);
 // allow rx to calm down
//    $display("UART_RAW_TEST_COMPLETE");

// check burst test
//    uart_burst_test(VERBOSE,WRITE_TO_LOG,TEST_BURST_SIZE,chip_id1);

// verify we can detect fifo overflow
 //  fifo_panic_test(VERBOSE,WRITE_TO_LOG,FIFO_DEPTH,chip_id1);
    
end //initial

initial begin
    clk = 0;
    #100 clk = 1;
    forever #100 clk = ~clk;
end 

initial begin
    clk = 0;
    #50 clk = 1;
    forever #50 clk = ~clk;
end 

// read out FPGA received UART
always @(negedge rx_empty) begin
//    #20
    @(posedge clk);
    uld_rx_data = 1;
    @(posedge clk);
    //#100
    receivedData = data_from_larpix;
//    #20 
    @(posedge clk);
    uld_rx_data = 0;
end

always @(receivedData) begin
    #10
    $display("\nData Received: %h",receivedData);
    if (parity_error) $display("ERROR: PARITY BAD");
    else $display("Parity good.");
    case(rcvd_packet_declare)
        0 : begin
                $display("data packet");
                $display("Chip ID = %d",rcvd_chip_id);
                $display("Channel ID = %d",rcvd_channel_id);
                $display("time stamp (hex) = %h",rcvd_time_stamp);
                $display("fifo counter (if configured) = %d",rcvd_fifo_cnt);
                $display("data word = %d",rcvd_data_word);
                $display("trigger_type = %d", rcvd_trigger_type);
                $display("shared fifo half bit = %d",rcvd_fifo_half_bit);
                $display("shared fifo full bit = %d",rcvd_fifo_full_bit);
                $display("local fifo half bit = %d",rcvd_local_fifo_half_bit);
                $display("local fifo full bit = %d",rcvd_local_fifo_full_bit);
                $display("downstream marker bit = %d",rcvd_downstream_marker_bit);
            end
        1 : begin
                $display("test packet");
                $display("Chip ID = %d",rcvd_chip_id);
                $display("Channel ID = %d",rcvd_channel_id);
                $display("time stamp (hex) = %h",rcvd_time_stamp);
                $display("fifo counter (if configured) = %d",rcvd_fifo_cnt);
                $display("data word = %d",rcvd_data_word);
                $display("trigger_type = %d", rcvd_trigger_type);
                $display("fifo half bit = %d",rcvd_fifo_half_bit);
                $display("fifo full bit = %d",rcvd_fifo_full_bit);
                $display("local fifo half bit = %d",rcvd_local_fifo_half_bit);
                $display("local fifo full bit = %d",rcvd_local_fifo_full_bit);
                $display("marker bit = %d",rcvd_downstream_marker_bit);
            end
        2 : begin
                $display("configuration write");
                $display("Chip ID = %d",rcvd_chip_id);
                $display("register map address = %d",rcvd_regmap_addr);
                $display("register map data = %d",rcvd_regmap_data);
                $display("fifo half bit = %d",rcvd_fifo_half_bit);
                $display("fifo full bit = %d",rcvd_fifo_full_bit);
                $display("local fifo half bit = %d",rcvd_local_fifo_half_bit);
                $display("local fifo full bit = %d",rcvd_local_fifo_full_bit);
               $display("marker bit = %d",rcvd_downstream_marker_bit);
            end
        3 : begin
                $display("configuration read");
                $display("Chip ID = %d",rcvd_chip_id);
                $display("register map address = %d",rcvd_regmap_addr);
                $display("register map data = %d",rcvd_regmap_data);
                $display("fifo half bit = %d",rcvd_fifo_half_bit);
                $display("fifo full bit = %d",rcvd_fifo_full_bit);
                $display("local fifo half bit = %d",rcvd_local_fifo_half_bit);
                $display("local fifo full bit = %d",rcvd_local_fifo_full_bit);
               $display("marker bit = %d",rcvd_downstream_marker_bit);
            end
    endcase
end // always



// add to scoreboard when new data generated

always @(sentTag) begin
    scoreBoard[eventCount] = sentTag;
    eventCount = eventCount + 1;
    scoreBoardCount = scoreBoardCount + 1;
    if (debug) begin
        $display("event %h written to scoreboard at time %0d",sentTag,$time);
        $display("currently %0d events digitized",eventCount);
        $display("currently %0d events in scoreboard",scoreBoardCount);
    end
end // always

// check scoreboard when new data packet is received
always @(receivedData) begin
    // make sure this is a data packet, otherwise ignore
    if (debug) $display("PACKET RECEIVED");
    if (rcvd_packet_declare == 0) begin
        // make tag to compare with data in scoreboard
 //       for (i = 0; i < eventCount; eventCount = eventCount + 1) begin
 //       $display("DATA RECEIVED");
 //       end // for
    end // if
end // always
 
// This UART instance models the programming FPGA
uart_tx 
    #(.WIDTH(WIDTH)
    ) tx (
    .reset_n    (reset_n),
    .txclk      (clk),
    .ld_tx_data (ld_tx_data),
    .tx_data    (data_to_larpix),
    .tx_out     (mosi),
    .tx_busy    (tx_busy)
);

// UART RX for testing TX here (this is in the receive FPGA)
uart_rx
    #(.WIDTH(WIDTH)
    ) rx (
    .reset_n      (reset_n),
    .rxclk        (clk),
    .uld_rx_data  (uld_rx_data),
    .rx_data      (data_from_larpix),
    .rx_in        (miso),
    .rx_empty     (rx_empty),
    .parity_error   (parity_error)
);

endmodule   
