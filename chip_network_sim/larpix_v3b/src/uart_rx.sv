///////////////////////////////////////////////////////////////////
//  File Name : uart_rx.sv
//  Engineer  : Carl Grace
//  Description: Simple UART receiver with double‑buffering.
//               - LSB‑first, start‑bit = 0, stop‑bit is ignored.
//               - Two‑flop synchronizer for the asynchronous line.
//               - When a packet completes it is placed in rx_data.
//               - If the previous packet has not been read, the new
//                 packet is stored in a second buffer (hold_reg).
//               - Host reads by pulsing uld_rx_data; rx_empty is
//                 high when no data is waiting.
///////////////////////////////////////////////////////////////////

module uart_rx
#(parameter int unsigned WIDTH = 64)          // payload width
    (output logic [WIDTH-1:0] rx_data,   // last valid packet
    output logic            rx_empty,  // 1 = no data waiting, 0 = data ready
    input  logic            rx_in,     // asynchronous serial line (idle = 1)
    input  logic            uld_rx_data,// pulse: host has read rx_data
    input  logic            clk,
    input  logic            reset_n);    // async active‑low

// local variable
logic sync_0;
logic rx_sync;            // clean, synchronous version of rx_in
logic busy;               // true while a packet is being received
logic [$clog2(WIDTH)-1:0] bit_cnt;            // counts 0 … WIDTH‑1
logic [WIDTH-1:0] shift_reg;           // builds the incoming word
logic [WIDTH-1:0] hold_reg;            // second buffer
logic hold_valid;          // 1 = hold_reg contains a word
logic                     busy_next;
logic [$clog2(WIDTH)-1:0] bit_cnt_next;
logic [WIDTH-1:0]         shift_reg_next;
logic                     packet_ready;

always_ff @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        sync_0 <= 1'b1;
        rx_sync <= 1'b1;
    end else begin
        sync_0 <= rx_in;
        rx_sync <= sync_0;
    end

// Combinatorial next‑state / next‑value logic
// The combinatorial block decides what the next values will be.
// It also raises a one‑cycle flag (packet_ready) when the last
// data bit has been captured.
always_comb begin : nxt
    // defaults – hold current values
    busy_next      = busy;
    bit_cnt_next   = bit_cnt;
    shift_reg_next = shift_reg;
    packet_ready   = 1'b0;

    if (!busy) begin
    // IDLE – wait for a start bit (line goes low)
        if (!rx_sync) begin
            busy_next      = 1'b1;   // start receiving
            bit_cnt_next   = '0;     // first data bit will be index 0
            shift_reg_next = '0;     // clear accumulator
        end
    end else begin
           // RECEIVING – capture one data bit each clock (LSB‑first)
        shift_reg_next[bit_cnt] = rx_sync;

        if (bit_cnt == WIDTH-1) begin
         // All data bits have been captured
            packet_ready = 1'b1;
            busy_next    = 1'b0;       // return to IDLE
        end else
            bit_cnt_next = bit_cnt + 1'b1;
    end // if

end // always_comb

always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        // Reset all state
        busy       <= 1'b0;
        bit_cnt    <= '0;
        shift_reg  <= '0;
        hold_reg   <= '0;
        hold_valid <= 1'b0;
        rx_data    <= '0;
        rx_empty   <= 1'b1;               // empty after reset
    end else begin
        // Host read request (uld_rx_data pulse)
        if (uld_rx_data) begin
            if (hold_valid) begin
                // Move buffered word to primary output
                rx_data    <= hold_reg;
                hold_valid <= 1'b0;
                // rx_empty stays low because we still have a word
                rx_empty   <= 1'b0;
            end else begin
                // No buffered word – indicate empty state
                rx_empty   <= 1'b1;
            end
        end
        // Reception registers
        busy       <= busy_next;
        bit_cnt    <= bit_cnt_next;
        shift_reg  <= shift_reg_next;

        // Word completed – double‑buffer handling
        if (packet_ready) begin
            if (rx_empty) begin
                // Primary buffer is free – deliver immediately
                rx_data  <= shift_reg_next;
                rx_empty <= 1'b0;
            end else begin
                // Primary buffer still occupied – store in hold register
                hold_reg   <= shift_reg_next;
                hold_valid <= 1'b1;
            end
        end
    end
end

endmodule

