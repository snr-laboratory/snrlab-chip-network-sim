///////////////////////////////////////////////////////////////////
// File Name: event_router.sv
// Engineer:  Carl Grace (crgrace@lbl.gov)
//
// Description: Routes event from one of 64 channels to shared FIFO.
// Includes a 1‑cycle‑per‑packet, round‑robin arbiter for 64 local FIFOs.
// Uses a token passing approach for arbitration to ensure fairness
///////////////////////////////////////////////////////////////////
module event_router
    #(parameter int WIDTH = 64,
    parameter int NUMCHANNELS = 64)
    (output logic [WIDTH-1:0] event_data,   // packet (incl. parity)
    output logic event_valid,    // active‑high write pulse to shared FIFO
    output logic [NUMCHANNELS-1:0] read_local_fifo_n, //  read pulse
    input logic [WIDTH-2:0] input_events [NUMCHANNELS],// 63‑bit input
    input logic [NUMCHANNELS-1:0] local_fifo_empty, // 0 = data ready
    input logic ready_for_event,    // back‑pressure from shared FIFO
    input logic clk,
    input logic reset_n);

// local variables
localparam int PRIORITY_LENGTH = NUMCHANNELS-1;
logic [NUMCHANNELS-1:0] token, token_next; // token holds search channel
logic any_data; // high if data avaiable in local FIFOs
logic [NUMCHANNELS-1:0] mask, mask_wrap; // masks channels against token
logic [NUMCHANNELS-1:0] sel_onehot; // selected channels
logic [WIDTH-1:0] event_data_next; // next event data

// priority encoder – returns one‑hot one-hot_sel and its index
localparam integer PL = NUMCHANNELS-1; // # of bits of priority encoder
`include "priority_onehot.sv"

    // One‑hot channel select (round‑robin token)
    // Token gives each channel a chance; after a successful read the token
    // moves to the next channel. If the current token points to an empty
    // FIFO we skip it and keep rotating.
    // any_data = at least one FIFO has a packet and Hydra FIFO is ready for it
always_comb
    any_data = |(~local_fifo_empty);

    // rotate token (simple circular shift)
always_ff @(posedge clk or negedge reset_n)
    if (!reset_n) token <= {NUMCHANNELS{1'b0}};  // start at channel 0
    else if (any_data) token <= token_next; // keep rotating even if stalled

always_comb begin
    event_data_next = '0; // default value
    for (int i = 0; i < NUMCHANNELS; i++) 
        if (sel_onehot[i]) 
            event_data_next = {~^input_events[i], input_events[i]};
end //always_comb

always_ff @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        event_valid<= 1'b0;
        event_data <= '0;
    end else begin
        event_valid <= |sel_onehot;
        event_data <= event_data_next;
    end // if

// generate the next token value (one‑hot rotate)
always_comb
    token_next =  ( token == 0 ) ? (1'b1) :
        ( token[NUMCHANNELS-1] ) ? (1'b1) :
        ( token << 1 );

// Find the first channel that is (token AND not empty)
// 2‑stage: first compute mask = token & ~local_fifo_empty,
// then priority‑encode it. If the mask is zero we look at the
// whole set (wrap‑around) to ensure fairness.
always_comb begin
    mask       = token & ~local_fifo_empty & ready_for_event;
    mask_wrap  = ~local_fifo_empty; // set when token misses
    if (mask != '0)    sel_onehot = priority_onehot(mask);
    else if (any_data) sel_onehot = priority_onehot(mask_wrap);
    else               sel_onehot = '0;
  // Schedule write: we have a selected channel AND FIFO is not full
    read_local_fifo_n = ~sel_onehot; // active‑low pulse
end
endmodule
