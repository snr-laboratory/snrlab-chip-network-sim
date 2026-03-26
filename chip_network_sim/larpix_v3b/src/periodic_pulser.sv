///////////////////////////////////////////////////////////////////
// File Name: periodic_pulser.sv
// Engineer:  Carl Grace (crgrace@lbl.gov)
// Description: Counter to generate periodic signal after
//              specified number of clock pulses are counted.
//              Can be configured to reset / trigger one channel
//              per cycle or all the channels in the cycle
//
//              Used to generate periodic reset and periodic trigger
//
///////////////////////////////////////////////////////////////////

module periodic_pulser
    #(parameter int PERIODIC_PULSER_W = 32,
    parameter int NUMCHANNELS = 64)
    (output logic [NUMCHANNELS-1:0] periodic_pulse,  // periodic pulse out
    input logic [PERIODIC_PULSER_W-1:0] pulse_cycles,  // number of clocks
                                                     //  to count
    input logic enable,           // high to enable periodic reset
    input logic enable_rolling_pulse, // if high, then only one output
                                // goes high at a time, otherwise they
                                // all do
    input logic clk,              // master clock
    input logic reset_n);         // asynchronous digital reset (active low)

localparam int PULSE_COUNT_W = $clog2(NUMCHANNELS);
// internal registers
logic [PERIODIC_PULSER_W-1:0] clk_counter;  // number of pulses counted
logic [PULSE_COUNT_W-1:0] rolling_pulse_counter; // which output goes high?

always_ff @ (posedge clk or negedge reset_n)
    if (!reset_n) begin
        periodic_pulse<= 64'b0;
        clk_counter <= '0;
        rolling_pulse_counter <= '0;
    end else if (enable == 1'b1) begin
        if (clk_counter == pulse_cycles) begin
            if (enable_rolling_pulse) begin
                periodic_pulse[rolling_pulse_counter] <= 1'b1;
                clk_counter <= '0;
                rolling_pulse_counter <= rolling_pulse_counter + 1'b1;
            end else begin
                periodic_pulse <= '1;
                clk_counter <= '0;
            end
        end else begin
            periodic_pulse <= '0;
            clk_counter <= clk_counter + 1'b1;
        end // if
    end // if
endmodule
