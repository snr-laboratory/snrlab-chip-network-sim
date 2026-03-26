///////////////////////////////////////////////////////////////////
// File Name: uart_rx.sv
// Engineer:  Carl Grace (crgrace@lbl.gov)
// Description: Simple UART receiver
//              Adapted from orignal design by Deepak Tala
//
//              in v2 mode:
//              RX should use a 2X oversampled clock relative to TX
//              in v3 mode:
//              RX should use same clock as TX
//
// If rx_empty is low then data is waiting. It should be read and then
// uld_rx_data should be asserted to enable rx for another reception.
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
//
//  Output format: packet is sent LSB-first, preceded by a start bit = 0
//  and ended by a stop bit = 1       
///////////////////////////////////////////////////////////////////

module uart_rx_fpga
    #(parameter WIDTH = 64)
    (output logic [WIDTH-1:0] rx_data,    // data received by UART
    output logic rx_empty,          // high if no data in rx
    output logic parity_error,      // high if last word has bad parity
    input logic rx_in,              // input bit
    input logic uld_rx_data,        // transfer data to output (rx_data)
    input logic clk,             // receive clock
    input logic reset_n);           // digital reset (active low) 

// Internal Variables 
logic [WIDTH-1:0] rx_reg;
logic rx_sample_cnt;
logic [7:0] rx_cnt;  
logic rx_d1;
logic rx_d2;
logic rx_busy;

// UART RX Logic
always_ff @ (posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        rx_reg <= 0; 
        rx_data <= 0;
        rx_sample_cnt <= 1'b0;
        rx_cnt <= 8'b0;
        rx_empty <= 1'b1;
        rx_d1 <= 1'b1;
        rx_d2 <= 1'b1;
        rx_busy <= 1'b0;
        parity_error <= 1'b0;
    end else begin
        rx_sample_cnt <= 1'b1;
        // Synchronize the asynch signal
        rx_d1 <= rx_in;
        rx_d2 <= rx_d1;
        // Unload the rx data
        if (uld_rx_data) begin
            rx_data  <= rx_reg[WIDTH-1:0];
            rx_empty <= 1'b1;
        end
        // Check if just received start of frame
        if (!rx_busy && !rx_d2) begin
            rx_busy <= 1'b1;
            rx_sample_cnt <= 1'b1;
            rx_cnt <= 8'h01;
        end
        // Start of frame detected, Proceed with rest of data
        if (rx_busy) begin
            rx_cnt <= rx_cnt + 1'b1; 
               // Start storing the rx data
            if ((rx_cnt >= 8'd1) && (rx_cnt <= WIDTH)) begin
                rx_reg[rx_cnt - 1'b1] <= rx_d2;
            end
                if (rx_cnt > WIDTH) begin
                    rx_busy <= 1'b0;
                    rx_empty <= 1'b0;
                    rx_data <= rx_reg[WIDTH-1:0];
                    if ( (rx_reg[WIDTH-1]) != (~^rx_reg[WIDTH-2:0]))
                        parity_error <= 1'b1;
                    else
                        parity_error <= 1'b0;
                end
        end 
    end
end // always_ff
endmodule


