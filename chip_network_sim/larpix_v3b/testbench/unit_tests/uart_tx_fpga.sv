///////////////////////////////////////////////////////////////////
// File Name: uart_tx.sv
// Engineer:  Carl Grace (crgrace@lbl.gov)
// Description: Simple UART transmitter.
//              Adapted from orignal design by Deepak Tala
//              UART word width is 64 bits.
//
//    Packet Definition
//
//  bit range     | contents
//  --------------------------
//     1:0        | packet declaration (00: unused, 01: data,
//                    10: configuration write, 11: configuration read)
//     9:2        | chip id
//   15:10        | channel id
//   43:16        | 28-bit time stamp
//   44           | reset sample flag
//   45           | cds flag
//   55:46        | 10-bit ADC data word
//   57:56        | trigger type (00: normal, 01: external, 10: cross, 
//                    11: periodic)
//   59:58        | local FIFO status (58: fifo half full,59: fifo full)
//   61:60        | shared FIFO status (60: fifo half full, 61: fifo full)
//   62           | downstream marker bit (1 if packet is downstream)
//   63           | odd parity bit
//
//  In configuration mode:  [17:10] is register address
//                          [25:18] is register data
//                          [57:26] is magic number (0x89_50_4E_47)

//  Output format: packet is sent LSB-first, preceded by a start bit = 0
//  and ended by a stop bit = 1          
///////////////////////////////////////////////////////////////////

module uart_tx_fpga
    #(parameter WIDTH = 64)
    (output logic tx_out,           // tx bit
    output logic tx_busy,           // high when transmitter sending data
    input logic [WIDTH-1:0] tx_data,     // data to be sent by uart
    input logic ld_tx_data,         // high to transfer data word to uart tx
    input logic tx_enable,          // clock-gating: enable clock
    input logic clk,              // baud-rate clock for tx
    input logic reset_n);           // digital reset (active low) 

// Internal Variables 
logic [WIDTH-1:0] tx_reg;
logic [7:0] tx_cnt;

// UART TX Logic
always_ff @(negedge clk or negedge reset_n) begin
    if (!reset_n) begin
        tx_reg <= 0;
        tx_busy <= 1'b0;
        tx_out <= 1'b1;
        tx_cnt <= 8'b0;
    end 
    else if (tx_enable) begin
        if (ld_tx_data) begin
            tx_reg   <= tx_data;
            tx_busy <= 1'b1;
        end
        if (tx_busy) begin
            tx_cnt <= tx_cnt + 1'b1;
            if (tx_cnt == 8'b0) begin
                tx_out <= 1'b0;
            end
            if (tx_cnt > 8'b0 && tx_cnt <= WIDTH) begin
                tx_out <= tx_reg[tx_cnt - 1'b1];
            end
            if (tx_cnt > WIDTH) begin
                tx_out <= 1'b1;
                tx_cnt <= 8'b0;
                tx_busy <= 1'b0;
            end
        end
    end 
    else begin
        tx_reg  <= tx_reg;
        tx_busy <= tx_busy;
        tx_out  <= tx_out;
        tx_cnt  <= tx_cnt;
    end
end // always_ff
endmodule


