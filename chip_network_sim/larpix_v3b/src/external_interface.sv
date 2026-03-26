///////////////////////////////////////////////////////////////////
// File Name: external_interface.sv
// Engineer:  Carl Grace (crgrace@lbl.gov)
// Description: LArPix external interface.
//              Includes UART for chip-to-chip communications.
//              Includes 255 byte register file for configuration bits.
//              Includes Hydra controller.
//
///////////////////////////////////////////////////////////////////

module external_interface
    #(parameter int WIDTH = 64, // width of packet (w/o start & stop bits)
    parameter int FIFO_DEPTH = 2048,         // depth of Hydra FIFO
    parameter int GLOBAL_ID = 255,      // global broadcast ID
    parameter int REGNUM = 256,
    parameter int NUM_UARTS = 4,
    parameter int FIFO_BITS = 11)
    (output logic [3:0] tx_out ,// LArPix TX UART output bits
    output logic [7:0] config_bits [REGNUM],// regmap config bit outputs
    output logic [3:0] tx_enable,         // high to enable TX
    output logic ready_for_event,    // back‑pressure to local FIFO from shared FIFO
    input logic [WIDTH-1:0] event_data,// event data to be transmitted off-chip
    input logic event_valid,           // high to load event from event router
    input logic [7:0] chip_id,      // unique id for each chip
    input logic load_config_defaults, // high for soft reset
    input logic [3:0] enable_piso_upstream, // high to enable upstream uart
    input logic [3:0] enable_piso_downstream, // high to enable downstream
    input logic [3:0] enable_posi, // high to enable rx ports
    input logic [3:0] rx_in, // rx UART input bit
    input logic enable_fifo_diagnostics, // high to embed fifo counts
    input logic clk,                  // master clock
    input logic reset_n_clk, // digital reset on clk domain (active low)
    input logic reset_n_config); // digital reset for config regs (low)

// internal nets
logic [3:0] rx_empty_uart;
logic [3:0] uld_rx_data_uart;
logic [3:0] ld_tx_data_uart;
logic [3:0] rx_enable;
logic [3:0] tx_busy;
logic [WIDTH-1:0] rx_data_uart [NUM_UARTS];
logic [WIDTH-1:0] tx_data_uart [NUM_UARTS];
logic [WIDTH-1:0] rx_data;
logic [WIDTH-1:0] pkt_data;
logic pkt_valid;
logic [7:0] regmap_write_data;
logic [7:0] regmap_read_data;
logic [7:0] regmap_address;
logic write_regmap;
logic read_regmap;
logic [15:0] fifo_counter_out; // current value of Hydra FIFO


// declare four UARTs for Hydra I/O
genvar i;
    for (i = 0; i < 4; i++) begin : g_uart
        uart
            #(.WIDTH(WIDTH),
            .FIFO_BITS(FIFO_BITS))
            uart_inst (
                .rx_data                (rx_data_uart[i]),
                .rx_empty               (rx_empty_uart[i]),
                .tx_out                 (tx_out[i]),
                .tx_busy                (tx_busy[i]),
                .rx_in                  (rx_in[i]),
                .uld_rx_data            (uld_rx_data_uart[i]),
                .fifo_data              (tx_data_uart[i]),
                .ld_tx_data             (ld_tx_data_uart[i]),
                .rx_enable              (rx_enable[i]),
                .tx_enable              (tx_enable[i]),
                .clk                    (clk),
                .reset_n                (reset_n_clk));
    end // for

// controller for HYDRA I/O
hydra_ctrl
    #(.WIDTH(WIDTH),
    .FIFO_DEPTH(FIFO_DEPTH),
    .GLOBAL_ID(GLOBAL_ID))
    hydra_ctrl_inst (
    .tx_data_uart           (tx_data_uart),
    .uld_rx_data_uart       (uld_rx_data_uart),
    .ld_tx_data_uart        (ld_tx_data_uart),
    .rx_data_flag           (rx_data_flag),
    .rx_enable              (rx_enable),
    .tx_enable              (tx_enable),
    .ready_for_event        (ready_for_event),
    .ready_for_pkt          (ready_for_pkt),
    .fifo_counter_out       (fifo_counter_out),
    .rx_data                (rx_data),
    .rx_empty_uart          (rx_empty_uart),
    .rx_data_uart           (rx_data_uart),
    .enable_posi            (enable_posi),
    .enable_piso_upstream   (enable_piso_upstream),
    .enable_piso_downstream (enable_piso_downstream),
    .enable_fifo_diagnostics(enable_fifo_diagnostics),
    .comms_busy             (comms_busy),
    .tx_busy                (tx_busy),
    .chip_id                (chip_id),
    .event_data             (event_data),
    .event_valid            (event_valid),
    .pkt_data               (pkt_data),
    .pkt_valid              (pkt_valid),
    .clk                    (clk),
    .reset_n                (reset_n_clk));

// communication controller
comms_ctrl
    #(.WIDTH(WIDTH),
    .GLOBAL_ID(GLOBAL_ID)
    ) comms_ctrl_inst (
    .pkt_data        (pkt_data),
    .pkt_valid       (pkt_valid),
    .regmap_write_data  (regmap_write_data),
    .regmap_address     (regmap_address),
    .comms_busy         (comms_busy),
    .write_regmap       (write_regmap),
    .read_regmap        (read_regmap),
    .rx_data            (rx_data),
    .chip_id            (chip_id),
    .regmap_read_data   (regmap_read_data),
    .rx_data_flag       (rx_data_flag),
    .ready_for_pkt   (ready_for_pkt),
    .event_valid        (event_valid),
    .fifo_counter_out   (fifo_counter_out),
    .clk                (clk),
    .reset_n            (reset_n_clk));

// register map
config_regfile
    #(.REGNUM(REGNUM)
     ) config_regfile_inst (
    .config_bits           (config_bits),
    .read_data             (regmap_read_data),
    .write_addr            (regmap_address),
    .write_data            (regmap_write_data),
    .read_addr             (regmap_address),
    .write                 (write_regmap),
    .read                  (read_regmap),
    .load_config_defaults  (load_config_defaults),
    .clk                   (clk),
    .reset_n               (reset_n_config));

endmodule
