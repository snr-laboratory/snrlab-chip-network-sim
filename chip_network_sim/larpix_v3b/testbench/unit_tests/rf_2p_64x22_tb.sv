
`timescale 1ns/1ps

module rf_2p_64x22_tb();

// test the operation generated dual-port SRAM
// this version is 22 bits wide and 64 words deeps
// used to implement the FIFO
// A is the read port
// B is the write port
// NOTE: according to RAM datasheet, chip enable must be low
// on rising edge of clock for chip reads or writes to be successful

// local signals
logic verbose;  // high for tasks to print results
logic [21:0] read_data; // read data from port A
logic [5:0] read_address; // read address for port A
logic [21:0] write_data; // write data from port B
logic [5:0] write_address; // write address for port B
logic chip_enable_read_n; // active low chip enable for read port
logic chip_enable_write_n; // active low chip enable for write port
logic clk; // master clock (used for port RAM ports)
logic clk_read; // derived clock for read 
logic clk_write; // derived clock for write

task writeWord;
input [5:0] addr;
input [21:0] data;
begin
    #100 write_data = data;
    write_address = addr;
    @(posedge clk) ;
    #10 chip_enable_write_n = 0;
    @(posedge clk);
    @(posedge clk);
    #10 chip_enable_write_n = 1;
    if (verbose)
        $display("%m: Time = %04t: write %h to address %d",$realtime,data,addr);
end
endtask;

task readWord;
input [5:0] addr;
begin
    read_address = addr;
    @(posedge clk); 
    #10 chip_enable_read_n = 0;
    @(posedge clk);
    @(posedge clk); 
    #10 chip_enable_read_n = 1;
    if (verbose)
        $display("%m: Time = %04tns: %h read from address %d",$realtime,read_data,addr);
end
endtask;

always_comb begin
    clk_read = clk & !chip_enable_read_n;
    clk_write = clk & !chip_enable_write_n;
end

initial begin

    verbose = 1;
    clk = 0;
    chip_enable_read_n = 1;
    chip_enable_write_n = 1;
    read_address = 0;
    write_address = 0;
    read_address = 0;
    write_data = 0;
    writeWord(0,22'h00000F);
    writeWord(1,22'h00ABCD);
    readWord(0);
    readWord(1);
    
end // initial

always #10 clk = ~clk;

    
// Dual-Port SRAM model    
rf_2p_64x22
    rf_2p_62x22t_inst (
    .QA         (read_data),
    .AA         (read_address),
    .CLKA       (clk_read),
    .CENA       (chip_enable_read_n),
    .DB         (write_data),
    .AB         (write_address),
    .CLKB       (clk_write),
    .CENB       (chip_enable_write_n)
    );

  endmodule // rf_2p_64x22_tb
