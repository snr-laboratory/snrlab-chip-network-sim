///////////////////////////////////////////////////////////////////
//  File Name: priority_fifo_arbiter.sv
//  Engineer: Carl Grace (crgrace@lbl.gov)
//  Description:   Simple fixed‑priority arbiter for Hydra FIFO.
//                 Config (high‑priority) wins over Event on simultaneous
//                 writes. Provides ready/valid handshake to the sources.
///////////////////////////////////////////////////////////////////

module priority_fifo_arbiter
    #(parameter int WIDTH = 64)
    (output logic [WIDTH-1:0] fifo_data_in,
    output logic fifo_write_n,  // active‑low write request to FIFO
    output logic ready_for_event,   // de‑asserted when pkt wins
    output logic ready_for_pkt,  // always 1 unless FIFO full
    input logic event_valid,   // asserted when event_data is valid
    input logic [WIDTH-1:0] event_data,
    // ----- pkt side -----------------------------------------------
    input logic pkt_valid,  // asserted when pkt_data is valid
    input logic [WIDTH-1:0] pkt_data,

    // ----- FIFO side -------------------------------------------------
    input logic fifo_full,     // from fifo_latch
    input logic clk,
    input logic reset_n
);

// Determine which source gets the grant this cycle
// Priority:  CONFIG > EVENT, but only if FIFO is not full
logic grant_pkt, grant_event, event_valid_buffer;
logic [WIDTH-1:0] event_data_buffer;
always_comb begin
    // Default: nothing granted
    grant_pkt = 1'b0;
    grant_event  = 1'b0;
    fifo_data_in = '0; //TP: resolving timing lint. latch was being inferred

    if (!fifo_full) begin
        if (pkt_valid) grant_pkt = 1'b1; 
        else if ((event_valid & !event_valid_buffer) || 
            (~event_valid & event_valid_buffer)) grant_event  = 1'b1;
    end 
    // Multiplex data and generate FIFO control signals
    if (grant_pkt) fifo_data_in = pkt_data;
    else if (grant_event ) 
        fifo_data_in = event_valid ? event_data : event_data_buffer;

    // write_n is active‑low: 0 = write, 1 = idle
    fifo_write_n = !(grant_pkt || grant_event);

    // Apply backpressure to the sources
    // Config can always assert next cycle unless FIFO is full.
    ready_for_pkt = !fifo_full;
   // Event may proceed only when (a) FIFO not full AND (b) pkt not taking the bus
    ready_for_event = !fifo_full && !pkt_valid;
end // always_comb

// buffer event 1 clock cycle if config and event hit at the same time
always_ff @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        event_valid_buffer <= 1'b0;
        event_data_buffer <= '0;
    end else begin
        if (pkt_valid) begin
            event_valid_buffer <= event_valid;
            event_data_buffer <= event_data;
        end else begin
            event_valid_buffer <= 1'b0;
        end
    end
endmodule // priority_fifo_arbiter
