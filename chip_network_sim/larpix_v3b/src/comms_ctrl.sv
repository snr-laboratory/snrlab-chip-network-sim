/////////////////////////////////////////////////////////////////////
// File Name: comms_ctrl.sv
// Engineer:  Carl Grace (crgrace@lbl.gov)
// Description: Minimal configuration controller.
//
//  * Decodes CONFIG_WRITE and CONFIG_READ packets.
//  * Performs a single‑cycle write or read on the external register file.
//  * For a read, builds the reply packet (same format as the request)
//    and forwards it directly to the Hydra controller.
//  * Builds statistics packets
/////////////////////////////////////////////////////////////////////

module comms_ctrl
    #(parameter int WIDTH      = 64,
    parameter int GLOBAL_ID  = 8'hFF)          // broadcast ID
    (output logic [WIDTH-1:0] pkt_data,      // packet that will be sent to Hydra
    output logic pkt_valid,// high for one cycle when config_data valid
    output logic [7:0] regmap_write_data, // data to write
    output logic [7:0] regmap_address,    // address for the reg‑file
    output logic comms_busy,              // high if processing pkt
    output logic write_regmap,      // pulse to write regmap
    output logic read_regmap,       // pulse read regmap
    input logic [WIDTH-1:0] rx_data,          // raw packet from UART
    input logic [7:0] chip_id,          // this chip's ID
    input logic [7:0] regmap_read_data,  // data returned from the regmap
    input logic rx_data_flag,     // high when rx_data is valid
    input logic ready_for_pkt, // hydra fifo is ready for more data
    input logic event_valid,     // new data packet from event_router
    input logic [15:0] fifo_counter_out, // current value
    input logic clk,
    input logic reset_n);

    //  Include the LArPix packet constants (CONFIG_WRITE_OP, etc.)
`include "larpix_constants.sv"

    //  Extract the fields we need from the incoming packet
    //  Bits [1:0]   : packet type (00‑11) -- 00 is an error
    //  Bits [9:2]   : destination chip ID
    //  Bits [17:10] : register address (for config ops)
    //  Bits [25:18] : register data   (for config writes)
    //  Bits [57:26] : magic number (used for validation)
    //  Bit  [63]    : odd parity (MSB)

logic [1:0] pkt_type;
logic [7:0] pkt_chip;
logic [7:0] pkt_addr;
logic [7:0] pkt_payload;
logic [31:0] pkt_magic;
logic [3:0] pkt_stats;
logic [WIDTH-1:0] rcvd_pkt; // packet containing request
logic [WIDTH-2:0] read_pkt; // packet to send back with config or pass along data
logic pkt_malformed;
logic [15:0] dropped_packets;
logic [31:0] total_packets;
logic [15:0] local_data_packets;
logic [15:0] local_config_reads;
logic [15:0] local_config_writes;
logic [15:0] hydra_fifo_high_water;
logic [15:0] stats_payload;
logic local_event_flag; // high if event has been captured

int num_ones;
// packet builder
always_comb begin
    pkt_type   = rx_data[1:0];
    pkt_chip   = rx_data[9:2];
    pkt_addr   = rx_data[17:10];
    pkt_payload= rx_data[25:18];
    pkt_magic  = rx_data[57:26];
    pkt_stats  = rx_data[61:58];
    num_ones = $countones(rx_data);
    // malformed if type not recognized or magic number wrong
    case(pkt_type) 
        2'b00 : pkt_malformed = 1'b1;
        2'b01 : pkt_malformed = 1'b0;
        2'b10 : pkt_malformed = (pkt_magic != MAGIC_NUMBER);
        2'b11 : pkt_malformed = (pkt_magic != MAGIC_NUMBER);
        default : pkt_malformed = 1'b0;
    endcase
    
end

// stats_payload mux
always_comb
    case (pkt_stats)
        4'h0: stats_payload = '0;
        4'h1: stats_payload = local_data_packets;
        4'h2: stats_payload = local_config_reads;
        4'h3: stats_payload = local_config_writes;
        4'h4: stats_payload = dropped_packets;
        4'h5: stats_payload = total_packets[15:0];
        4'h6: stats_payload = total_packets[31:16];
        4'h7: stats_payload = fifo_counter_out;
        4'h8: stats_payload = hydra_fifo_high_water;
        default: stats_payload = 16'hff;
    endcase

// stats counters
always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        local_data_packets <= '0;
        hydra_fifo_high_water <= '0;
        local_event_flag <= 1'b0;
    end else begin
        if (event_valid) begin
            if (local_event_flag == 1'b0) begin
                local_data_packets <= local_data_packets + 1'b1;
                local_event_flag <= 1'b1;
            end
        end else begin // event_valid is low
            if (local_event_flag == 1'b1) begin
                local_event_flag <= 1'b0;
            end
        end 
        if (hydra_fifo_high_water <= fifo_counter_out)
            hydra_fifo_high_water <= fifo_counter_out;
    end // if
end // always_ff

// define states
typedef enum logic [1:0] {
    IDLE      = 2'h0,
    WRITE_CFG = 2'h1,
    READ_REQ  = 2'h2, 
    LOAD_FIFO = 2'h3} state_e;

state_e State, Next;

    // calculate parity
always_comb 
    pkt_data = (pkt_chip == chip_id) ? {~^read_pkt,read_pkt} : rx_data;

//  State register
always_ff @(posedge clk or negedge reset_n)
    if (!reset_n) State <= IDLE;
    else         State <= Next;

//  Next‑state combinatorial logic
always_comb begin    
    Next = State;
    case (State)
        IDLE: begin
            if (rx_data_flag) begin
                //  Reject malformed packets first
                if (pkt_malformed) Next = IDLE;       // drop it (stay)
                //  Valid CONFIG_WRITE intended for us (or broadcast)
                else if (pkt_type == CONFIG_WRITE_OP)
                    Next = WRITE_CFG;
                //  Valid CONFIG_READ intended to us (or broadcast)
                else if ( (pkt_type == CONFIG_READ_OP) && (pkt_chip == chip_id) ) 
                    Next = READ_REQ;
                else 
                    Next = LOAD_FIFO;
            end
        end
        WRITE_CFG: Next = IDLE;     // single‑cycle write
        READ_REQ : Next = LOAD_FIFO; // wait one cycle for the reg‑file data
        LOAD_FIFO : if (ready_for_pkt) Next = IDLE;  // reply packet built & sent
                      else Next = LOAD_FIFO; // retry
        default  : Next = IDLE;
    endcase
end // always_comb

// All outputs are cleared each cycle; the state‑specific blocks
// override the ones they need.
always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin 
        comms_busy        <= 1'b1;
        write_regmap      <= 1'b0;
        read_regmap       <= 1'b0;
        regmap_address    <= 8'b0;
        regmap_write_data <= 8'b0;
        read_pkt          <= '0;
        rcvd_pkt          <= '0;
        pkt_valid      <= 1'b0;
        dropped_packets   <= '0;
        local_config_reads <= '0;
        local_config_writes <= '0;
        total_packets     <= '0;
    end else begin
        // default (cleared) assignments each cycle
        write_regmap      <= 1'b0;
        read_regmap       <= 1'b0;
        read_pkt          <= {(WIDTH-1){1'b0}};
        pkt_valid      <= 1'b0;

        case (State)
            IDLE: begin
                comms_busy <= 1'b0;
                if (rx_data_flag) begin // there is data ready, grab it!
                    total_packets <= total_packets + 1'b1;
                    rcvd_pkt <= rx_data;

                    if (pkt_malformed) dropped_packets <= dropped_packets + 1'b1;
                    else begin
                        // valid packet – proceed with normal handling
                        regmap_address    <= pkt_addr;
                        read_regmap       <= 1'b1; // speculative read
                        regmap_write_data <= pkt_payload;
                    end
                end
            end
            WRITE_CFG: begin
                write_regmap <= 1'b1; // pulse the reg‑file
                local_config_writes <= local_config_writes + 1'b1;
            end
            READ_REQ:;
                // (the data will appear on regmap_read_data this cycle)
            LOAD_FIFO: begin
                // Build the reply: if this is a data packet for another chip,
                // or a downstream data packet, send it on, or
                //if this is a config read, then copy the
                //original request, replace the
                // payload with the value we just read and set downstream
                // flag (bit 62).
                ////read_pkt <= rcvd_pkt[WIDTH-2:0]; // start with the request
                ////read_pkt[62] <= 1'b1;    // downstream flag (reply)
                // if stats are requested, overwrite config addr and data
                // NB, if pkt_stats is nonzero, then stats are requested
                ////if (|pkt_stats) read_pkt[25:10] <= stats_payload;
                // otherwise we want to send back pkt data
                ////else read_pkt[25:18] <= regmap_read_data; // read‑back value
                ////read_pkt[9:2] <= chip_id;        // source = this chip
                ////read_pkt[1:0] <= CONFIG_READ_OP; // set pkt id
                //// Build 63-bit packet in one assignment, 
                //// to avoid synthesis warning: Variable/signal is assigned by multiple non-blocking assignments
                if ((rx_data[9:2] != chip_id) || 
                        (rx_data[9:2] == GLOBAL_ID) ||
                        pkt_type == DATA_OP) begin
                        read_pkt <= rx_data;
                end else begin
                    read_pkt <= {
                        1'b1,  // bit 62 = downstream flag
                        rcvd_pkt[61:26],  // bits 61:26 unchanged
                        (|pkt_stats) ? stats_payload : 
                        {regmap_read_data, rcvd_pkt[17:10]},  // stats payload
                        chip_id,  // bits 9:2
                        CONFIG_READ_OP  // bits 1:0
                         };
                end
                pkt_valid  <= 1'b1;   // one‑cycle strobe
                if (pkt_type == CONFIG_READ_OP)
                    local_config_reads <= local_config_reads + 1'b1;
            end
            default: ; // should never happen
        endcase
    end
end
endmodule
