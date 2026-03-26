///////////////////////////////////////////////////////////////////
// File Name: uart_tests.sv
// Engineer:  Carl Grace (crgrace@lbl.gov)
// Description: Tests for verifying the Larpix uart and test modes
//          
///////////////////////////////////////////////////////////////////

`ifndef _uart_tests_
`define _uart_tests_

`include "larpix_constants.v"  // all sim constants defined here
`include "larpix_utilities.v" // needed for verification tasks

task uart_raw_test;
// this task commands the uart to send alternating 01 data to tune the
// receiving FPGA

input Verbose;
input WriteToLog;
input [15:0] BurstSize;
input [7:0] chip_id;
reg[24*8:1] block_name;
reg [7:0] recoveredWord;
integer test,addr;


begin

    block_name = "uart";
    if (WriteToLog == 1) initFile(block_name);

// return Larpix to normal mode
    sendWordToLarpix(CONFIG_WRITE_OP,chip_id,CONFIG_CTRL,8'b00000000); 

// configure Larpix for burst size
    sendWordToLarpix(CONFIG_WRITE_OP,chip_id,BURST_LENGTH,BurstSize[7:0]);      
    sendWordToLarpix(CONFIG_WRITE_OP,chip_id,(BURST_LENGTH+1),BurstSize[15:8]);  

// put into UART test mode
    sendWordToLarpix(CONFIG_WRITE_OP,chip_id,CONFIG_CTRL,8'b00000001);   
    #10000            
    wait (uld_rx_data);
    #100
    recoveredWord = receivedData[25:18];
    $display("RECEIVED DATA = %h",receivedData);
    checkFault(block_log,block_name,"UART raw test",receivedData,{27{2'b01}},recoveredWord,WriteToLog,Verbose,FALSE);

// return Larpix to normal mode
    //wait (larpix_tb.larpix_inst.digital_core_inst.fifo_empty); 
    sendWordToLarpix(CONFIG_WRITE_OP,chip_id,CONFIG_CTRL,8'b00000000); 

    reportResults(block_name,WriteToLog);
end
endtask


task uart_burst_test;
// this task commands the uart to send alternating 01 data to tune the
// receiving FPGA
// assumes we are NOT overflowing the FIFO. That is another test.

input Verbose;
input WriteToLog;
input [15:0] BurstSize;
input [7:0] chip_id;
reg[24*8:1] block_name;
reg [7:0] recoveredWord;
integer i;


begin

    block_name = "uart_burst";
    if (WriteToLog == 1) initFile(block_name);

// return Larpix to normal mode
//    sendWordToLarpix(CONFIG_WRITE_OP,chip_id,CONFIG_CTRL,8'b00000000); 

// configure Larpix for burst size
    sendWordToLarpix(CONFIG_WRITE_OP,chip_id,BURST_LENGTH,BurstSize[7:0]);      
#1000
    sendWordToLarpix(CONFIG_WRITE_OP,chip_id,(BURST_LENGTH+1),BurstSize[15:8]); 
#1000     
// put UART into burst test mode
    // wait until FIFO is empty to start test
    $display("WAITING FOR FIFO TO EMPTY TO START PANIC TEST");
//    wait (larpix_tb.larpix_inst.digital_core_inst.fifo_empty);
    $display("FIFO EMPTY, STARTING PANIC TEST");
 
    // configure FIFO diagnostics
    $display("CONFIGURE FIFO DIAGNOSTICS");
    sendWordToLarpix(CONFIG_WRITE_OP,chip_id,CONFIG_CTRL,8'b0001_0010);  
//    @(posedge uld_rx_data); // account for tx_data delay 
/*
    for (i = 0; i < BurstSize; i = i + 1) begin            
        @(posedge uld_rx_data);
        #100
        recoveredWord = receivedData[50:41];
        $display("UART BURST: RECEIVED DATA = %h",recoveredWord);     // 
        checkFault(block_log,block_name,"UART burst test",recoveredWord,i,recoveredWord,WriteToLog,Verbose,FALSE);
 
    end 
*/  
 //return Larpix to normal mode
//   sendWordToLarpix(CONFIG_WRITE_OP,chip_id,CONFIG_CTRL,8'b0010_0000); 
//   reportResults(block_name,WriteToLog);
end
endtask

task fifo_panic_test;
// this task makes sure when the fifo is overrun on purpose we can detect

input Verbose;
input WriteToLog;
input [15:0] FifoDepth;
input [7:0] chip_id;
reg[24*8:1] block_name;
reg [8:0] recoveredWord;
reg [15:0] BurstSize;
integer Panic;
reg [15:0] i;

begin
    Panic = 0;  // panic == 1 when fifo has overflowed
    block_name = "fifo_overflow";
    if (WriteToLog == 1) initFile(block_name);

// configure Larpix for burst size
    BurstSize = 10;
    sendWordToLarpix(CONFIG_WRITE_OP,chip_id,BURST_LENGTH,BurstSize[7:0]);      
    sendWordToLarpix(CONFIG_WRITE_OP,chip_id,(BURST_LENGTH+1),BurstSize[15:8]);      

// wait until FIFO is empty to start test
    $display("WAITING FOR FIFO TO EMPTY TO START PANIC TEST");
    //wait (larpix_tb.larpix_inst.digital_core_inst.fifo_empty); 

// first make sure test can fail
// put UART into burst test mode
    
    sendWordToLarpix(CONFIG_WRITE_OP,chip_id,CONFIG_CTRL,8'b00000010);
    sendWordToLarpix(CONFIG_WRITE_OP,chip_id,CONFIG_CTRL,8'b00000000);
   
    for (i = 0; i < 10; i = i + 1) begin            
        @(posedge uld_rx_data);
        #10
        recoveredWord = receivedData[52:41];
        if (receivedData[52] == 1'b1)
            Panic = 1;
    end
    // we only read out 10 words so we expect the FIFO has NOT overflowed
    checkFault(block_log,block_name,"FIFO panic test",Panic,0,recoveredWord,WriteToLog,Verbose,FALSE);


    Panic = 0;
// configure Larpix for burst size
    BurstSize = FifoDepth + 1'b1;
    sendWordToLarpix(CONFIG_WRITE_OP,chip_id,BURST_LENGTH,BurstSize[7:0]);      
    sendWordToLarpix(CONFIG_WRITE_OP,chip_id,(BURST_LENGTH+1),BurstSize[15:8]);    
// put UART into burst test mode
    sendWordToLarpix(CONFIG_WRITE_OP,chip_id,CONFIG_CTRL,8'b00000010);   
    for (i = 0; i <= FifoDepth; i = i + 1) begin
        // if FIFO isn't empty, wait for next read...
        //if (!larpix_tb.larpix_inst.digital_core_inst.fifo_empty) 
            @(posedge uld_rx_data);
        #10
        recoveredWord = receivedData[52:41];
        if (receivedData[52] == 1'b1)
            Panic = 1;
    end
    checkFault(block_log,block_name,"FIFO panic test",Panic,1,recoveredWord,WriteToLog,Verbose,FALSE);

// return Larpix to normal mode
   sendWordToLarpix(CONFIG_WRITE_OP,chip_id,CONFIG_CTRL,8'b00000000); 
 
   reportResults(block_name,WriteToLog);
end
endtask

`endif // _uart_tests_


