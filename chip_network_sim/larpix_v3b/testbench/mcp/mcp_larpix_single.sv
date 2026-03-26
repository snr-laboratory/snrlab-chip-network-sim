///////////////////////////////////////////////////////////////////
// File Name: mcp_larpix_single.sv
// Engineer:  Carl Grace (crgrace@lbl.gov)
// Description:     LArPix Master Control Program
//                  Captures functionality of FPGA-based master interface
//                  Programs LArPix and reads out data
//                  This version is to simulate a single LArPix.
//
///////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

module mcp_larpix_single
    #(parameter WIDTH = 64,
    parameter WORDWIDTH = 8,
    parameter REGNUM = 256,
    parameter FIFO_DEPTH = 512
    ) 
    (output logic posi,       // PRIMARY OUT, SECONDARY IN (input of larpix from FPGA)
    output real charge_in_r [63:0], 
    output logic clk,       // clock sent to larpix 
    output logic reset_n,     // digital reset (active low)
    input piso);            // PRIMARY IN, SECONDARY OUT (output of larpix to FPGA) 

`ifndef XCELIUM_RUN
`include "larpix_constants.sv"
`endif


// scoreboard
localparam SCOREBOARDSIZE = 100;
integer debug;
integer eventCount; // number of events digitized and written to scoreboard
integer scoreBoardCount; // number of events currently unmatched in scoreboard
logic [63:0] scoreBoard [SCOREBOARDSIZE-1:0]; // elements in scoreboard
                                // this should be linked list

logic ld_tx_data;
logic [WIDTH-1:0] data_to_larpix; // sent to DUT from FPGA
logic [WIDTH-1:0] data_from_larpix; // received by FPGA from DUT
logic [WIDTH-1:0] sent_data;
logic [WIDTH-1:0] receivedData;

logic posi_predelay;
//logic [1:0] clk_ctrl; // clock config
logic [7:0] chip_id;      // unique id for each chip
logic [7:0] chip_id1;      // unique id for each chip
logic [7:0] chip_id2;      // unique id for each chip
//logic [7:0] chip_id3;      // unique id for each chip
logic [63:0] sentTag;     // tagged input signal to scoreboard
logic [63:0] packetNumber;     // tagged input signal to scoreboard
//logic [63:0] chargeSignal;
logic local_reset_n;
// control FPGA rx uart
logic uld_rx_data;
//logic [1:0] uart_op;
logic rx_empty;
logic tx_busy;

// parse rx data
logic [1:0] rcvd_packet_declare;
logic [7:0] rcvd_chip_id;
logic [5:0] rcvd_channel_id;
logic [27:0] rcvd_time_stamp;
logic [9:0] rcvd_data_word;
logic [1:0] rcvd_trigger_type;
logic [7:0] rcvd_regmap_data;
logic [7:0] rcvd_regmap_addr;
logic [10:0] rcvd_fifo_cnt;
logic [2:0] rcvd_local_fifo_cnt;
logic [3:0] rcvd_pkt_stats;
logic [15:0] rcvd_stats_payload;
logic rcvd_reset_sample_flag;
logic rcvd_cds_flag;
logic rcvd_downstream_marker_bit;
logic rcvd_fifo_half_bit;
logic rcvd_fifo_full_bit;
logic rcvd_local_fifo_half_bit;
logic rcvd_local_fifo_full_bit;
logic [1:0] rcvd_tally;
logic [31:0] rcvd_magic_number;
logic rcvd_parity_bit;
logic parity_error;
logic expected_parity_bit;
logic [1:0] local_clk_ctrl; // keep track of what LArPix clock is doing
string s_rcvd_pkt_stats;


always_comb begin
    rcvd_packet_declare         = receivedData[1:0];
    rcvd_chip_id                = receivedData[9:2];
    rcvd_channel_id             = receivedData[15:10];
    rcvd_time_stamp             = receivedData[43:16];
    rcvd_stats_payload          = receivedData[25:10];
    rcvd_local_fifo_cnt         = receivedData[31:28];
    rcvd_reset_sample_flag      = receivedData[44];
    rcvd_cds_flag               = receivedData[45];
    rcvd_fifo_cnt               = receivedData[43:32];
    rcvd_data_word              = receivedData[55:46];
    rcvd_trigger_type           = receivedData[57:56];
    rcvd_fifo_half_bit          = receivedData[58];
    rcvd_fifo_full_bit          = receivedData[59];
    rcvd_local_fifo_half_bit    = receivedData[60];
    rcvd_local_fifo_full_bit    = receivedData[61];
    rcvd_tally                  = receivedData[61:60];
    rcvd_downstream_marker_bit  = receivedData[62];
    rcvd_parity_bit             = receivedData[63];
    rcvd_regmap_addr            = receivedData[17:10];
    rcvd_regmap_data            = receivedData[25:18];
    rcvd_magic_number           = receivedData[57:26];
    rcvd_pkt_stats              = receivedData[61:58];
    expected_parity_bit = ~^receivedData[62:0];
end

// make the stat request a bit more readable
always_comb
    case (rcvd_pkt_stats) 
        STATS_NONE:                 s_rcvd_pkt_stats = "None";
        STATS_LOCAL_DATA_PACKETS:   s_rcvd_pkt_stats = "Local Data Packets";
        STATS_LOCAL_CONFIG_READS:   s_rcvd_pkt_stats = "Local Config Reads";
        STATS_LOCAL_CONFIG_WRITES:  s_rcvd_pkt_stats = "Local Config Writes";
        STATS_DROPPED_PACKETS:      s_rcvd_pkt_stats = "Local Config Writes";
        STATS_TOTAL_PACKETS_LSB:    s_rcvd_pkt_stats = "Local Total Packets (LSB)";
        STATS_TOTAL_PACKETS_MSB:    s_rcvd_pkt_stats = "Local Total Packets (MSB)";
        STATS_FIFO_COUNTER_OUT:     s_rcvd_pkt_stats = "Local Total Packets (MSB)";
        STATS_HYDRA_FIFO_HIGH_WATER:s_rcvd_pkt_stats = "Local Total Packets (MSB)";
        default:                    s_rcvd_pkt_stats = "None";
    endcase
        

parameter WRITE_TO_LOG = 0;  // high to write verification results to file
parameter NUMTRIALS_REGMAP = 100; // number of random REGMAP trials to run
parameter TEST_BURST_SIZE = 20;     // number of values to load into fifo
parameter GLOBAL_ID = 255;          // global broadcast ID
                                // during uart burst test
`include "uart_tasks.sv"

always begin
    posi = #1 posi_predelay;
end


initial begin
    for (int i = 0; i < 64; i++) begin
        charge_in_r[i] = 0.0;
    end
    local_clk_ctrl = 0;
    debug = TRUE;
    sentTag = 0;
    packetNumber = 0;
    //clk_ctrl = 2'b00;
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
    
    reset_n = 1;
    local_reset_n = 1;
    repeat(80) @(posedge clk);
    #1500
    @(negedge clk) 
    #1 reset_n = 0;
    local_reset_n = 0;
    repeat(80) @(posedge clk);
    #2   reset_n = 1;
    local_reset_n = 1;
    repeat(80) @(negedge clk);
    $display("SECOND RESET:");
    #1 reset_n = 0;
    local_reset_n = 0;
    repeat(80) @(posedge clk);
    #2   reset_n = 1;
    local_reset_n = 1;
	#100
    repeat(18) @(megedge clk);
    $display("THIRD RESET:");
    #1 reset_n = 0;
    local_reset_n = 0;
    repeat(80) @(negedge clk);
    #2   reset_n = 1;
    local_reset_n = 1;
	#100
    repeat(10) @(negedge clk);
    $display("FOURTH RESET:");
    #1 reset_n = 0;
    local_reset_n = 0;
    repeat(80) @(posedge clk);
    #2   reset_n = 1;
    local_reset_n = 1;
	#100
    repeat(10) @(negedge clk);
    $display("FIFTH RESET:");
    #1 reset_n = 0;
    local_reset_n = 0;
    repeat(80) @(negedge clk);
    #2   reset_n = 1;
    local_reset_n = 1;
	#100

    $display("RESET COMPLETE");
//    #1000

    @(negedge clk)
    //@(posedge clk)

// function def:
//    sendWordToLarpix(op,chip_id,register,value
// 5 Mhz system clock);

`ifdef XCELIUM_RUN
//`include "./testbench/mcp/config_test.mcp"
//`include "./testbench/mcp/single_larpix.mcp" 
//`include "./testbench/mcp/larpix_minimal.mcp" 
//`include "./testbench/mcp/larpix_mailbox.mcp" 
//`include "./testbench/mcp/verification/ver_config_test.mcp"
//`include "./testbench/mcp/verification/ver_config_magic_number.mcp"
//`include "./testbench/mcp/verification/ver_cds_minimal.mcp"
//`include "./testbench/mcp/verification/ver_hydra_config.mcp"

`else
`include "./verification/ver_config_test.mcp"
//`include "./verification/ver_global_test.mcp"
//`include "./verification/ver_normal_trigger.mcp"
//`include "./verification/ver_pass_data.mcp"
//`include "./verification/ver_config_parity_error.mcp"
//`include "./verification/ver_digital_threshold_test.mcp"
//`include "./verification/ver_dynamic_reset.mcp"
//`include "./verification/ver_config_magic_number.mcp"
//`include "./verification/ver_ext_trig.mcp"
//`include "./verification/ver_per_rst.mcp"
//`include "./verification/ver_ext_sync.mcp"
//`include "./verification/ver_bad_packets.mcp"
//`include "./verification/ver_multi_hit.mcp"
//`include "./verification/ver_burst.mcp"
//`include "./verification/ver_stats.mcp"
//`include "./verification/ver_per_trig.mcp"
//`include "./verification/ver_cross_trig.mcp"
//`include "./verification/ver_burst_cds.mcp"
//`include "./verification/ver_cds_minimal.mcp"
//`include "./verification/ver_fifo_drain.mcp"
//`include "./verification/ver_hydra_debug.mcp"
//`include "./verification/ver_hydra_config.mcp"
//`include "./verification/ver_hydra_storm.mcp"
//`include "./verification/ver_hydra_ext_trig.mcp"
//`include "./verification/ver_hydra_storm_cds.mcp"
//`include "./verification/ver_single_larpix.mcp" 

//`include "lightpix_debug.mcp"
//`include "hydra_broadcast_read.mcp"
//`include "config_test.mcp"
//`include "hardwired_test.mcp"
//`include "ext_trig.mcp"
//`include "ext_trig_short.mcp"
//`include "ext_trig_debug.mcp"
//`include "fifo_debug.mcp"
//`include "per_trig_debug.mcp"
//`include "burst_debug.mcp"
//`include "sanity_check.mcp"
//`include "config_path.mcp"
//`include "single_larpix.mcp" 
//`include "larpix_minimal.mcp" 
//`include "larpix_tally.mcp" 
//`include "larpix_wait.mcp" 
//`include "larpix_mailbox.mcp" 
//`include "cds_minimal.mcp"    
//`include "hydra_larpix.mcp"

`endif // ifdef XCELIUM_RUN

//#20000000 
//$finish;

end //initial


// 5 Mhz system clock
initial begin
    clk = 0;
    #2 clk = 1;
    forever #100 clk = ~clk;
end 



// read out FPGA received UART
always @(negedge rx_empty) begin
//    #20
    @(posedge clk);
    uld_rx_data = 1;
    @(posedge clk);
    //#100
    receivedData = data_from_larpix;
    packetNumber++;
//    #20 
    @(posedge clk);
    uld_rx_data = 0;
end

always @(negedge uld_rx_data) begin
    #10
    if (packetNumber != 0) begin
        $display("\n--------------------");
        $display("\nData Received: %h",receivedData);
        $display("Packet Number: %0d",packetNumber);
        $display("Parity Bit = %0d",rcvd_parity_bit);
        $display("Expected Parity Bit = %0d",expected_parity_bit);
        if (expected_parity_bit != rcvd_parity_bit) 
            $display("ERROR: PARITY BAD");
        else 
            $display("Parity good.");
    end
    case(rcvd_packet_declare)
        0 : begin
                if (packetNumber != 0) begin
                    $display("ERROR: BAD PACKET. 2'b00 INVALID DECLARATION");
                end
             end
        1 : begin
                $display("data packet");
                $display("Chip ID = %d",rcvd_chip_id);
                $display("Channel ID = %d",rcvd_channel_id);
                $display("time stamp (hex) = %h",rcvd_time_stamp);
                $display("local fifo counter (if configured) = %d",rcvd_local_fifo_cnt);
                $display("fifo counter (if configured) = %d",rcvd_fifo_cnt);
                $display("reset_sample_flag = %d",rcvd_reset_sample_flag);
                $display("cds_mode_flag = %d",rcvd_cds_flag);
                $display("data word = %d",rcvd_data_word);
                case(rcvd_trigger_type) 
                    2'b00 : $display("trigger_type = NATURAL");
                    2'b01 : $display("trigger_type = EXTERNAL");
                    2'b10 : $display("trigger_type = CROSS");
                    2'b11 : $display("trigger_type = PERIODIC");
                endcase 
                $display("packet tally (if configured) = %d",rcvd_tally);
                $display("downstream marker bit = %d",rcvd_downstream_marker_bit);
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
                $display("magic number = %h",rcvd_magic_number);
                $display("marker bit = %d",rcvd_downstream_marker_bit);
            end
        3 : begin
                if (rcvd_pkt_stats != 4'h0) begin  // this is a statistics packet
                    $display("configuration read");
                    $display("stats_request = %s",s_rcvd_pkt_stats);
                    $display("Chip ID = %d",rcvd_chip_id);
                    $display("stats value = %d",rcvd_stats_payload);
                    $display("magic number = %h",rcvd_magic_number);
                    $display("marker bit = %d",rcvd_downstream_marker_bit);
                end else begin
                    $display("configuration read");
                    $display("Chip ID = %d",rcvd_chip_id);
                    $display("register map address = %d",rcvd_regmap_addr);
                    $display("register map data = %d",rcvd_regmap_data);
                    $display("fifo half bit = %d",rcvd_fifo_half_bit);
                    $display("fifo full bit = %d",rcvd_fifo_full_bit);
                    $display("local fifo half bit = %d",rcvd_local_fifo_half_bit);
                    $display("local fifo full bit = %d",rcvd_local_fifo_full_bit);
                    $display("magic number = %h",rcvd_magic_number);
                    $display("marker bit = %d",rcvd_downstream_marker_bit);
                end
            end
    endcase
    $display("\n--------------------\n");
end // always



// add to scoreboard when new data generated

always @(sentTag) begin
    scoreBoard[eventCount] = sentTag;
    eventCount = eventCount + 1;
    scoreBoardCount = scoreBoardCount + 1;
    if (debug) begin
        if (packetNumber != 0) begin
            $display("event %h written to scoreboard at time %0d",sentTag,$time);
            $display("currently %0d events digitized",eventCount);
            $display("currently %0d events in scoreboard",scoreBoardCount);
        end
    end
end // always

// check scoreboard when new data packet is received
always @(receivedData) begin
    // make sure this is a data packet, otherwise ignore
//    if (debug) $display("PACKET RECEIVED");
    if (rcvd_packet_declare == 0) begin
        // make tag to compare with data in scoreboard
 //       for (i = 0; i < eventCount; eventCount = eventCount + 1) begin
 //       $display("DATA RECEIVED");
 //       end // for
    end // if
end // always
 
// This UART instance models the programming FPGA
uart_tx_fpga 
    #(.WIDTH(WIDTH)
    ) uart_tx_inst (
    .tx_out         (posi_predelay),
    .tx_busy        (tx_busy),
    .tx_data        (data_to_larpix),
    .ld_tx_data     (ld_tx_data),
    .clk            (clk),
    .tx_enable      (1'b1),
    .reset_n        (local_reset_n)
);

// UART RX for testing TX here (this is in the receive FPGA)
uart_rx_fpga
    #(.WIDTH(WIDTH)
    ) uart_rx_inst  (
    .rx_data        (data_from_larpix),
    .rx_empty       (rx_empty),
    .parity_error   (parity_error),
    .rx_in          (piso),
    .uld_rx_data    (uld_rx_data),
    .clk            (clk),
    .reset_n        (local_reset_n)
);



endmodule   
