///////////////////////////////////////////////////////////////////
// File Name: hydra_ctrl.sv
// Engineer:  Carl Grace (crgrace@lbl.gov)
// Description: Routes packets to appropriate UART based on 
//              Hydra configuration settings
//              Also routes RX inputs
//
///////////////////////////////////////////////////////////////////

module hydra_ctrl
    #(parameter WIDTH = 64,  // width of packet (w/o start & stop bits) 
    parameter int FIFO_DEPTH   = 2048,
    parameter int NUM_UARTS    = 4,
    parameter logic [7:0] GLOBAL_ID = 8'hFF)
    (output logic [WIDTH-1:0] tx_data_uart [NUM_UARTS],// data to send out UARTs
    output logic [NUM_UARTS-1:0] uld_rx_data_uart, // distributed unload command
    output logic [NUM_UARTS-1:0] ld_tx_data_uart, // distributed load command
    output logic rx_data_flag,    // tells comms_ctrl there is data
    output logic [NUM_UARTS-1:0] rx_enable,    // high to enable rx UART
    output logic [NUM_UARTS-1:0] tx_enable,    // high to enable tx UART
    output logic ready_for_event,   // back‑pressure to event source
    output logic ready_for_pkt,      // back‑pressure to config source
    output logic [15:0] fifo_counter_out, // zero padded fifo usage
    output logic [WIDTH-1:0] rx_data, // packet to put into the FIFO
    input logic [NUM_UARTS-1:0] rx_empty_uart, // high if UART has no rx data
    input logic [WIDTH-1:0] rx_data_uart [NUM_UARTS], // rx data from UARTs
    input logic [NUM_UARTS-1:0] enable_posi, // high to enable rx ports
    input logic [NUM_UARTS-1:0] enable_piso_upstream, // high to enable upstream uart
    input logic [NUM_UARTS-1:0] enable_piso_downstream, // high to enable downstream
    input logic enable_fifo_diagnostics,
    input logic comms_busy,         // high if comms_ctrl processing a pkt
    input logic [NUM_UARTS-1:0] tx_busy, // high for each UART busy
    input logic [7:0] chip_id,          // this chip's ID
    input logic [WIDTH-1:0] event_data,
    input logic event_valid,
    input logic [WIDTH-1:0] pkt_data,
    input logic pkt_valid,
    input logic clk,                // master clock
    input logic reset_n);      // asynchronous digital reset (active low)

// define states for RX state machine
typedef enum logic [2:0] // explicit state definitions
            {IDLE = 3'h0,
            RX_CAPTURE = 3'h1,
            RX_PROCESS = 3'h2,
            TX_UPSTREAM = 3'h3,
            TX_GET_FIFO = 3'h4,
            TX_SEND = 3'h5} state_e;
state_e State, Next;

// internal nets
localparam FIFO_BITS = $clog2(FIFO_DEPTH);//bits in fifo addr range
logic [WIDTH-1:0] tx_data;           // data sent to UARTs (pre-FIFO) 
logic [3:0] uart_has_data;  // one-hot data present & port enabled flag
logic [3:0] token_onehot;   // internal one-hot version of token
logic [3:0] arb_mask;       // arbitration mask (token combined with data ready)
logic [3:0] sel_onehot;     
// one‑hot UART that will be served this cycle
logic fifo_half;
logic fifo_empty;
logic [WIDTH-1:0] fifo_rd_data;
logic [WIDTH-1:0] event_data_arb;
logic [FIFO_BITS:0] fifo_counter; // number of events in Hydra FIFO
logic fifo_read_n;      // active low read signal for hydra FIFO

    //  Include packet constants (opcodes, etc.)
`include "larpix_constants.sv"

    //  Priority‑one‑hot function 
localparam int PL = 4;
`include "priority_onehot.sv"

//  function to splice the counter and recompute the parity bit.
//  Returns a full WIDTH-bit packet with a correct parity.
function automatic logic [WIDTH-1:0] embed_fc_in_pkt(
    input  logic [WIDTH-1:0]  raw_pkt,      // packet *before* diagnostics
    input  logic [FIFO_BITS:0] fifo_counter);  // wide enough for the counter
    // 63‑bit payload without parity
    logic [WIDTH-2:0] payload;

    //  Insert the fifo counter into the event packet.
    //  The counter occupies bits [43:16] (the same place the timestamp
    //  lives in a normal data packet).  The packet format here 
    //  uses bits [WIDTH-1:44] unchanged, then the counter, then the
    //  low‑order 32‑bits of the original payload.
    // -----------------------------------------------------------------
    // Preserve the upper bits that are not part of the counter
    //   raw_pkt[63:44]  -- bits above the counter field
    //   raw_pkt[31:0]   -- low 32‑bits of the original payload
    payload = { raw_pkt[WIDTH-1:44],       // 20 bits  (63‑44)
        fifo_counter,              // FIFO counter (FIFO_BITS+1 bits)
        raw_pkt[31:0] };          // 32 bits
        // recalculate parity
    return {~^payload, payload };   // {parity, payload}
endfunction

    always_comb begin
    // zero pad fifo counter for diagnostics
    fifo_counter_out = '0;
    fifo_counter_out[FIFO_BITS:0] = fifo_counter;
    event_data_arb = (enable_fifo_diagnostics) ? 
                embed_fc_in_pkt(event_data,fifo_counter) : event_data;
end // always_comb


// Token update (round‑robin)
// shift token only when a packet was actually taken (load_pkt).
always_ff @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        token_onehot <= 4'b0001;
    end else begin
        if (rx_data_flag) begin
            if (token_onehot == 4'b1000)
                token_onehot <= 4'b0001;
        else 
            token_onehot <= token_onehot << 1;   
    end // if
end



//  Data‑ready mask (purely physical – no back‑pressure)
always_comb begin
    for (int i = 0; i < NUM_UARTS; i++) begin
        uart_has_data[i] = ~rx_empty_uart[i] & enable_posi[i];
    end
end

    //  Arbitration mask (token + ready)
    always_comb begin
        arb_mask = token_onehot & uart_has_data;
        if (|arb_mask)        sel_onehot = priority_onehot(arb_mask);
        else if (|uart_has_data) sel_onehot = priority_onehot(uart_has_data);
        else                  sel_onehot = {NUM_UARTS{1'b0}};
    end


always_comb begin
    rx_enable = enable_posi;
    tx_enable = enable_piso_upstream | enable_piso_downstream;
end
                                                                              
// RX state machine
always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n)
        State <= IDLE;
    else
        State <= Next;
end // always_ff

always_comb begin
    Next = State; 
    case (State)
        IDLE: 
            if (|uart_has_data)             Next = RX_CAPTURE;
            else if (!fifo_empty)            Next = TX_GET_FIFO;
        RX_CAPTURE:                         
            if ( ((rx_data[9:2] != chip_id) || (rx_data[9:2] == GLOBAL_ID)) 
                && (rx_data[62] == 0) )     Next = TX_UPSTREAM; 
            else if (|uart_has_data)        Next = RX_PROCESS;
            else                            Next = IDLE;
        TX_UPSTREAM:
            if ((tx_busy & enable_piso_upstream)  != '0) Next = TX_UPSTREAM;
            else if (rx_data[9:2] == GLOBAL_ID) Next = RX_PROCESS;
            else                            Next = IDLE;
        RX_PROCESS:
            begin
                if (comms_busy)             Next = RX_PROCESS;
                else if (|uart_has_data)    Next = RX_CAPTURE;
            else                            Next = IDLE;
            end
        TX_GET_FIFO: 
            if ((tx_busy & enable_piso_downstream) != '0) Next = TX_GET_FIFO; 
            else                            Next = TX_SEND;   
        TX_SEND:                            Next = IDLE;
    
        default: Next = IDLE;
    endcase
end


// registered outputs
always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        rx_data <= 64'b0;
        rx_data_flag <= 1'b0;
        ld_tx_data_uart <= 4'h0;
        fifo_read_n <= 1'b1;
        uld_rx_data_uart <= 4'b0;
    end
    else begin
        rx_data_flag <= 1'b0;
        ld_tx_data_uart <= 4'h0;
        fifo_read_n <= 1'b1;
        uld_rx_data_uart <=4'h0;
        case (State)
            IDLE: 
                if (|uart_has_data)
                    case (sel_onehot)
                        4'b0001 : rx_data <= rx_data_uart[2'b00]; 
                        4'b0010 : rx_data <= rx_data_uart[2'b01]; 
                        4'b0100 : rx_data <= rx_data_uart[2'b10]; 
                        4'b1000 : rx_data <= rx_data_uart[2'b11]; 
                        default : rx_data <= '0;
                    endcase


            RX_CAPTURE:  
                begin
                    uld_rx_data_uart <= sel_onehot;

                end
            TX_UPSTREAM:
                begin
                  //  uld_rx_data_uart <= sel_onehot;
                    for (int i=0; i<NUM_UARTS; i++) begin
                        tx_data_uart[i] <= rx_data;
                    end
                    if ( (tx_busy & enable_piso_upstream)  == '0) 
                        ld_tx_data_uart <= enable_piso_upstream;
                end   
            RX_PROCESS: 
                begin
                    uld_rx_data_uart <= sel_onehot;
                    // check to see if this is an upstream packet
                    // otherwise process it
                    rx_data_flag <= comms_busy ? 1'b0 : 1'b1;            
                end
            TX_GET_FIFO:
                begin
                    uld_rx_data_uart <= sel_onehot;
                    // check to see if FIFOs busy (0 == not busy)
                    if ((tx_busy & enable_piso_downstream) == 4'b0000)
                        fifo_read_n <= 1'b0;
                end
            TX_SEND:
                begin
                    for (int i=0; i<NUM_UARTS; i++) begin
                        tx_data_uart[i] <= fifo_rd_data;
                    end
                    ld_tx_data_uart <= enable_piso_downstream;
                end
             default: ;
        endcase
    end
end // always_ff

// instantiate submodules
priority_fifo_arbiter #(
    .WIDTH(WIDTH))
    priority_fifo_arbiter_inst(
    .fifo_data_in       (tx_data),
    .fifo_write_n       (fifo_write_n),
    .ready_for_event    (ready_for_event),
    .ready_for_pkt      (ready_for_pkt),
    .event_valid        (event_valid),
    .event_data         (event_data),
    .pkt_valid          (pkt_valid),
    .pkt_data           (pkt_data),
    .fifo_full          (fifo_full),
    .clk                (clk),
    .reset_n            (reset_n));

fifo_latch #(
    .FIFO_WIDTH(WIDTH),
    .FIFO_DEPTH(FIFO_DEPTH),            
    .FIFO_BITS(FIFO_BITS)) 
    hydra_fifo_inst(
    .data_out       (fifo_rd_data),
    .fifo_counter   (fifo_counter),
    .fifo_full      (fifo_full),
    .fifo_half      (fifo_half),
    .fifo_empty     (fifo_empty),
    .data_in        (tx_data),
    .read_n         (fifo_read_n),
    .write_n        (fifo_write_n),
    .clk            (clk),
    .reset_n        (reset_n));
endmodule // hydra_ctrl
                   
   
