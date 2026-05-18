///////////////////////////////////////////////////////////////////
// File Name: msg_generator.sv
// Description: Local MSG_OP generation for congestion broadcast.
//              Holds at most one pending generated message.  The pending
//              message always reflects the newest local FIFO-state
//              advertisement, overwriting any older unsent generated msg.
///////////////////////////////////////////////////////////////////

module msg_generator
    #(parameter int WIDTH = 64,
      parameter int FIFO_DEPTH = 64)
    (output logic [WIDTH-1:0] msg_data_out,
     output logic msg_pending,
     input logic [15:0] fifo_counter_out,
     input logic msg_enable,
     input logic msg_read_n,
     input logic clk,
     input logic reset_n);

`include "larpix_constants.sv"

localparam int FIFO_25_THRESHOLD = FIFO_DEPTH / 4;
localparam int FIFO_50_THRESHOLD = FIFO_DEPTH / 2;
localparam int FIFO_90_THRESHOLD = (FIFO_DEPTH * 9) / 10;

logic [1:0] current_state;
logic [1:0] pending_state;
logic [1:0] last_sent_state;
logic last_sent_valid;
logic prev_msg_enable;

function automatic logic [1:0] encode_fifo_state(
    input logic [15:0] fifo_count);
    if (fifo_count <= FIFO_25_THRESHOLD[15:0])
        return 2'b00;
    else if (fifo_count <= FIFO_50_THRESHOLD[15:0])
        return 2'b01;
    else if (fifo_count <= FIFO_90_THRESHOLD[15:0])
        return 2'b10;
    else
        return 2'b11;
endfunction

function automatic logic [WIDTH-1:0] build_msg_packet(
    input logic [1:0] fifo_state);
    logic [MSG_WIDTH-2:0] body;
    logic [WIDTH-1:0] packet;
    begin
        body = {MSG_TAG_NORTH, fifo_state, MSG_OP};
        packet = '0;
        packet[MSG_WIDTH-1:0] = {~^body, body};
        return packet;
    end
endfunction

always_comb begin
    current_state = encode_fifo_state(fifo_counter_out);
end

always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        msg_data_out <= '0;
        msg_pending <= 1'b0;
        pending_state <= 2'b00;
        last_sent_state <= 2'b00;
        last_sent_valid <= 1'b0;
        prev_msg_enable <= 1'b0;
    end else begin
        prev_msg_enable <= msg_enable;

        if (!msg_read_n && msg_pending) begin
            last_sent_state <= pending_state;
            last_sent_valid <= 1'b1;
            msg_pending <= 1'b0;
        end

        if (msg_enable && !prev_msg_enable) begin
            pending_state <= current_state;
            msg_data_out <= build_msg_packet(current_state);
            msg_pending <= 1'b1;
        end else if (msg_enable &&
                    (!last_sent_valid || (current_state != last_sent_state)) &&
                    (!msg_pending || (current_state != pending_state))) begin
            pending_state <= current_state;
            msg_data_out <= build_msg_packet(current_state);
            msg_pending <= 1'b1;
        end
    end
end

endmodule
