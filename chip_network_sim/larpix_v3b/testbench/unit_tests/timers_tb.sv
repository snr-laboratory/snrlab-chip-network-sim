
`timescale 1ns/10ps

module timers_tb();

// test the operation of all the timers:
// such as: reset_pulse
//      reset_trigger
//      clk_manager
//      timestamp_32b sync
//      reset_sync
//   and hard reset

//localparam FIFO_WIDTH = 8;

// local signals
logic [31:0] timestamp_32b; // current timestamp value

logic sync_timestamp; // active high to reset timestamp
logic clk_master;        // master clock    
logic clk_core;        // core clock
logic clk_rx;        // rx clock
logic clk_tx;        // tx clock
logic [1:0] clk_ctrl; // clock configuration
logic reset_n_sync; // synchronized reset_n (active low)   
logic reset_n_config_sync; // synchronized reset_n (active low)   
logic reset_n;   // asynchronous digital reset (active low) (EXTERNAL)
logic [63:0] periodic_trigger;
logic [63:0] periodic_reset;
logic [31:0] periodic_trigger_cycles;
logic [23:0] periodic_reset_cycles;
logic enable_periodic_trigger;
logic enable_periodic_rolling_trigger;
logic enable_periodic_reset;
logic enable_periodic_rolling_reset;



initial begin

    periodic_trigger_cycles = 4;
    periodic_reset_cycles = 400;
    enable_periodic_trigger = 0;
    enable_periodic_rolling_trigger = 0;
    enable_periodic_reset = 0;
    enable_periodic_rolling_reset = 0;
    reset_n = 1;
    clk_master = 0;
    clk_ctrl = 0;
    // hard reset
    #1 reset_n = 0;
    #3000 reset_n = 1;

    #1000 clk_ctrl = 1;
    #1000 clk_ctrl = 2;
    #1000 clk_ctrl = 3;
/*
    // only do a timestamp sync
    #2000 reset_n = 0;
    #162 reset_n = 1;

    // only do a non-config and timestamp reset
    #2000 reset_n = 0;
    #582 reset_n = 1;
*/


end // initial

always #10 clk_master = ~clk_master;


// this module generates the 32b timestamp
timestamp_gen
    timestamp_gen_inst (
        .timestamp_32b  (timestamp_32b),
        .sync_timestamp (sync_timestamp),
        .clk            (clk_core),
        .reset_n        (reset_n_sync)
    );

// this module does clock domain crossing for the reset_n pulse and
// also generates the timestamp sync
reset_sync
    reset_sync_inst (
        .reset_n_sync           (reset_n_sync),
        .sync_timestamp         (sync_timestamp),
        .reset_n_config_sync    (reset_n_config_sync),
        .clk                    (clk_master),
        .reset_n                (reset_n)
    );

// this module sets the relationship between core and tx clock
clk_manager
    clk_manager_inst (
        .clk_core       (clk_core),
        .clk_rx         (clk_rx),
        .clk_tx         (clk_tx),
        .clk_ctrl       (clk_ctrl),
        .clk            (clk_master),
        .reset_n        (reset_n_sync)
    );

// this pulser generates the periodic trigger pulse    
periodic_pulser
    #(.PERIODIC_PULSER_W(32),
    .NUMCHANNELS(64))
    periodic_trigger_inst (
    .periodic_pulse     (periodic_trigger),
    .pulse_cycles       (periodic_trigger_cycles),
    .enable             (enable_periodic_trigger),
    .enable_rolling_pulse   (enable_periodic_rolling_trigger),
    .clk                (clk_core),
    .reset_n            (reset_n_sync)
    );
    
// this pulser generates the periodic reset pulse    
periodic_pulser
    #(.PERIODIC_PULSER_W(24),
    .NUMCHANNELS(64))
    periodic_reset_inst (
    .periodic_pulse     (periodic_reset),
    .pulse_cycles       (periodic_reset_cycles),
    .enable             (enable_periodic_reset),
    .enable_rolling_pulse   (enable_periodic_rolling_reset),
    .clk                (clk_core),
    .reset_n            (reset_n_sync)
    );
    
endmodule // timers_tb
