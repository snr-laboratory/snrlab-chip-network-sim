///////////////////////////////////////////////////////////////////
// File Name: msg_logic.sv
// Description: Receive-side handling for neighbor-generated MSG_OP.
//              Stores the most recent remembered FIFO state per RX lane
//              together with a valid bit and receive timestamp.
//              When a received neighbor state of 11 arrives on a direction
//              that is currently selected for downstream TX, this block
//              requests a register update to change ENABLE_PISO_DOWN.
///////////////////////////////////////////////////////////////////

module msg_logic
    #(parameter int WIDTH = 64,
      parameter int TS_LENGTH = 28)
    (output logic write_downstream_enable,
     output logic [7:0] downstream_enable_addr,
     output logic [7:0] downstream_enable_data,
     input logic [WIDTH-1:0] msg_data_in,
     input logic msg_valid_in,
     input logic [3:0] enable_piso_upstream,
     input logic [3:0] enable_piso_downstream,
     input logic [TS_LENGTH-1:0] timestamp,
     input logic clk,
     input logic reset_n);

`include "larpix_constants.sv"

localparam int LANE_NORTH = 2'd0;
localparam int LANE_EAST  = 2'd1;
localparam int LANE_SOUTH = 2'd2;
localparam int LANE_WEST  = 2'd3;

logic [1:0] remembered_state [4];
logic [TS_LENGTH-1:0] remembered_timestamp [4];
logic [3:0] remembered_valid;

logic [1:0] rx_lane;
logic [1:0] rx_fifo_state;
logic [3:0] rx_lane_mask;
logic [3:0] candidate_downstream_mask;
logic [1:0] best_lane;
logic [1:0] best_state;
logic [TS_LENGTH-1:0] best_timestamp;
logic best_found;

function automatic logic [1:0] tag_to_rx_lane(
    input logic [1:0] tx_tag);
    case (tx_tag)
        MSG_TAG_NORTH: return LANE_SOUTH;
        MSG_TAG_EAST : return LANE_WEST;
        MSG_TAG_SOUTH: return LANE_NORTH;
        default      : return LANE_EAST;
    endcase
endfunction

function automatic logic [3:0] lane_mask_from_id(
    input logic [1:0] lane_id);
    case (lane_id)
        LANE_NORTH: return 4'b0001;
        LANE_EAST : return 4'b0010;
        LANE_SOUTH: return 4'b0100;
        default   : return 4'b1000;
    endcase
endfunction

always_comb begin
    rx_lane = tag_to_rx_lane(msg_data_in[MSG_TX_TAG_MSB:MSG_TX_TAG_LSB]);
    rx_fifo_state = msg_data_in[MSG_FIFO_STATE_MSB:MSG_FIFO_STATE_LSB];
    rx_lane_mask = lane_mask_from_id(rx_lane);

    candidate_downstream_mask = enable_piso_downstream & ~rx_lane_mask;

    best_found = 1'b0;
    best_lane = 2'b00;
    best_state = 2'b11;
    best_timestamp = '0;

    for (int i = 0; i < 4; i++) begin
        if (remembered_valid[i] && !enable_piso_upstream[i] && (i != rx_lane)) begin
            if (!best_found ||
                (remembered_state[i] < best_state) ||
                ((remembered_state[i] == best_state) &&
                 (remembered_timestamp[i] > best_timestamp))) begin
                best_found = 1'b1;
                best_lane = i[1:0];
                best_state = remembered_state[i];
                best_timestamp = remembered_timestamp[i];
            end
        end
    end
end

always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        write_downstream_enable <= 1'b0;
        downstream_enable_addr <= '0;
        downstream_enable_data <= '0;
        remembered_valid <= 4'b0000;
        for (int i = 0; i < 4; i++) begin
            remembered_state[i] <= 2'b00;
            remembered_timestamp[i] <= '0;
        end
    end else begin
        write_downstream_enable <= 1'b0;
        downstream_enable_addr <= ENABLE_PISO_DOWN[7:0];
        downstream_enable_data <= '0;

        if (msg_valid_in) begin
            remembered_valid[rx_lane] <= 1'b1;
            remembered_state[rx_lane] <= rx_fifo_state;
            remembered_timestamp[rx_lane] <= timestamp;

            if ((rx_fifo_state == 2'b11) && ((enable_piso_downstream & rx_lane_mask) != 4'b0000)) begin
                if (candidate_downstream_mask != 4'b0000) begin
                    write_downstream_enable <= 1'b1;
                    downstream_enable_data <= {4'b0000, candidate_downstream_mask};
                end else if (best_found) begin
                    write_downstream_enable <= 1'b1;
                    downstream_enable_data <= {4'b0000, lane_mask_from_id(best_lane)};
                end
            end
        end
    end
end

endmodule
