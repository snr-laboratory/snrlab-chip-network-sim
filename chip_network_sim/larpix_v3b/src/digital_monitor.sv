///////////////////////////////////////////////////////////////////
// File Name: digital_monitor.sv
// Engineer:  Carl Grace (crgrace@lbl.gov)
//
// Description: Muxes various digital outputs and triggers
//              to the digital monitor port for debugging and
//              chip characterization purposes
///////////////////////////////////////////////////////////////////

module digital_monitor
    (output logic digital_monitor,      // monitor port
    input logic digital_monitor_enable, // high to enable output
    input logic [3:0] digital_monitor_select, // choose output
    input logic [5:0] digital_monitor_chan, // which channel to monitor
    input logic [63:0] hit,   // all hits
    input logic [63:0] sample, // packing mismatch with digital_core
    input logic [63:0] csa_reset,  // TP:packing mismatch with digital_core
    input logic [63:0] triggered_natural,
    input logic [63:0] periodic_trigger,
    input logic [63:0] periodic_reset,
    input logic external_trigger,
    input logic cross_trigger,
    input logic reset_n_config_sync,
    input logic sync_timestamp);

// logic signals

logic hit_selected; // hit of selected channel
logic sample_selected; // sample of selected channel
logic csa_reset_selected; // csa_reset of selected channel
logic triggered_natural_selected; // triggered_natural of selected channel
logic periodic_trigger_selected; // periodic_trigger of selected channel
logic periodic_reset_selected; // periodic_reset of selected channel

// output mux
always_comb begin
    if (digital_monitor_enable) begin
        case (digital_monitor_select)
            4'b0000 : digital_monitor = hit_selected;
            4'b0001 : digital_monitor = 1'b1;
            4'b0010 : digital_monitor = sample_selected;
            4'b0011 : digital_monitor = csa_reset_selected;
            4'b0100 : digital_monitor = triggered_natural_selected;
            4'b0101 : digital_monitor = periodic_trigger_selected;
            4'b0110 : digital_monitor = periodic_reset_selected;
            4'b0111 : digital_monitor = external_trigger;
            4'b1000 : digital_monitor = cross_trigger;
            4'b1001 : digital_monitor = reset_n_config_sync;
            4'b1010 : digital_monitor = sync_timestamp;
            default : digital_monitor = 1'b0;
        endcase
    end
    else begin
        digital_monitor = 1'b0;
    end
end // always_comb
// decoders
always_comb begin
    hit_selected = hit[digital_monitor_chan];
    sample_selected = sample[digital_monitor_chan];
    csa_reset_selected = csa_reset[digital_monitor_chan];
    triggered_natural_selected = triggered_natural[digital_monitor_chan];
    periodic_trigger_selected = periodic_trigger[digital_monitor_chan];
    periodic_reset_selected = periodic_reset[digital_monitor_chan];
end // always_comb
endmodule
