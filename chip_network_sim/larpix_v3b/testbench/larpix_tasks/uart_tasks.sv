///////////////////////////////////////////////////////////////////
// File Name: uart_tasks.sv
// Engineer:  Carl Grace (crgrace@lbl.gov)
// Description:     Tasks for operating the LArPix UART 
//          
///////////////////////////////////////////////////////////////////

`ifndef _uart_tasks_
`define _uart_tasks_

`include "larpix_constants.sv"  // all sim constants defined here


task sendWordToLarpix;
input logic [1:0] op;
input logic [7:0] chip_id;
input logic [7:0] addr;
input logic [7:0] data;
logic debug;
logic use_magic_number;
logic use_correct_parity;
bit parity_bit_sent;
int num_ones;
begin
    debug = 0;

// NOTE: normal operation: 
//  use_magic_number = 1;
//  use_correct_parity = 1;
//
// only modify if you are intending to inject errors into packet
    parity_bit_sent = 0;
    num_ones = 0;
    use_magic_number = 1;
    use_correct_parity = 1;
    if (debug) $display("in task: sending word to LArPix");
    #10000
    @(negedge clk)
//    #100 
    @(negedge clk)
    ld_tx_data = 0;
    data_to_larpix= {(WIDTH-1){1'b0}};
    data_to_larpix[1:0] = op;  
    data_to_larpix[9:2] = chip_id;
    data_to_larpix[17:10] = addr;
    data_to_larpix[25:18] = data;

    if (use_magic_number) begin
        data_to_larpix[57:26] = MAGIC_NUMBER;
    end
    else begin
        data_to_larpix[57:26] = $urandom;
        $display("%m: intentionally adding incorrect magic number");
        $display("%m: magic number used = %h",data_to_larpix[57:26]);
    end // if

    if (debug) begin
        $display("\n%m :sending work to LArPix");
        $display("op = %d",op);
        $display("chip_id = %d", chip_id);
        $display("addr = %d", addr);
        $display("data = %d", data);
    end
     if (use_correct_parity) begin    
        data_to_larpix[WIDTH-1] = ~^data_to_larpix[WIDTH-2:0];
    end else begin
        $display("uart_task.sv: intentionally injecting incorrect parity");
        data_to_larpix[WIDTH-1] = ^data_to_larpix[WIDTH-2:0];
    end
    if (debug) begin
        parity_bit_sent = data_to_larpix[WIDTH-1];
        num_ones = $countones(data_to_larpix);
        $display("%m: parity_bit_sent = %b",parity_bit_sent);
        $display("%m: total number of ones (should be odd) = %0d",num_ones);
    end
    sent_data = data_to_larpix;
    if (debug) $display("word sent (hex) = %h\n",data_to_larpix);
//    #150 
    if (debug) $display("waiting for clk");
    @(negedge clk) 
    if (debug) $display("set ld_tx_data = 1");
    ld_tx_data = 1;
//    #150 
    if (debug) $display("waiting for clk");
    @(negedge clk)
    ld_tx_data = 0;
    wait (!tx_busy);
end
endtask

task sendDataToLarpix;
input logic [9:0] adc_word;
input logic [7:0] chip_id;
input logic [5:0] chan_id;
input logic [28:0] ts;
bit debug;
logic use_correct_parity;
bit parity_bit_sent;
int num_ones;
begin
    debug = 0;

// NOTE: normal operation: 
//  use_magic_number = 1;
//  use_correct_parity = 1;
//
// only modify if you are intending to inject errors into packet
    parity_bit_sent = 0;
    num_ones = 0;
    use_correct_parity = 1;
    if (debug) $display("in task: sending data to LArPix");
    #10000
    @(negedge clk)
//    #100 
    @(negedge clk)
    ld_tx_data = 0;

    data_to_larpix= {(WIDTH-1){1'b0}};
    data_to_larpix[1:0] = DATA_OP;
    data_to_larpix[9:2] = chip_id;
    data_to_larpix[15:10] = chan_id;
    data_to_larpix[43:16] = ts;
    data_to_larpix[55:46] = adc_word;
    data_to_larpix[62] = DOWNSTREAM;

        if (debug) begin
        $display("\n,%m: sending data to LArPix");
        $display("chip_id = %d", chip_id);
        $display("chan_id = %d", chan_id);
        $display("ts = %h", ts);
        $display("adc_word = %d", adc_word);
    end
     if (use_correct_parity) begin    
        data_to_larpix[WIDTH-1] = ~^data_to_larpix[WIDTH-2:0];
    end else begin
        $display("uart_task.sv: intentionally injecting incorrect parity");
        data_to_larpix[WIDTH-1] = ^data_to_larpix[WIDTH-2:0];
    end
    if (debug) begin
        parity_bit_sent = data_to_larpix[WIDTH-1];
        num_ones = $countones(data_to_larpix);
        $display("%m: parity_bit_sent = %b",parity_bit_sent);
        $display("%m: total number of ones (should be odd) = %0d",num_ones);
    end
    sent_data = data_to_larpix;
    if (debug) $display("word sent (hex) = %h\n",data_to_larpix);
//    #150 
    if (debug) $display("waiting for clk");
    @(negedge clk) 
    if (debug) $display("set ld_tx_data = 1");
    ld_tx_data = 1;
//    #150 
    if (debug) $display("waiting for clk");
    @(negedge clk)
    ld_tx_data = 0;
    wait (!tx_busy);
end
endtask

task sendMalformedPacketToLarpix;

bit debug;
begin
    debug = 0;

    if (debug) $display("%m: sending malformed packet to LArPix");
    #10000
    @(negedge clk)
    @(negedge clk)
    ld_tx_data = 0;
    // make a random packet with OP = 00 to ensure it is malformed
    data_to_larpix = $urandom;
    data_to_larpix[1:0] = 2'b00;

    sent_data = data_to_larpix;
    if (debug) $display("word sent (hex) = %h\n",data_to_larpix);
    if (debug) $display("waiting for clk");
    @(negedge clk) 
    if (debug) $display("set ld_tx_data = 1");
    ld_tx_data = 1;
    if (debug) $display("waiting for clk");
    @(negedge clk)
    ld_tx_data = 0;
    wait (!tx_busy);
end
endtask

`endif // _uart_tasks_
