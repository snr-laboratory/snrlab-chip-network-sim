`timescale 1ns / 1ps

module digital_core_smoke_tb;

localparam int NUMCHANNELS = 64;
localparam int ADCBITS = 10;

logic [3:0] piso;
logic digital_monitor;
logic [NUMCHANNELS-1:0] sample;
logic [3:0] tx_enable;
logic [5*NUMCHANNELS-1:0] pixel_trim_dac;
logic [7:0] threshold_global;
logic [NUMCHANNELS-1:0] gated_reset;
logic [NUMCHANNELS-1:0] csa_reset;
logic [NUMCHANNELS-1:0] bypass_caps_enable;
logic [15:0] ibias_tdac;
logic [15:0] ibias_comp;
logic [15:0] ibias_buffer;
logic [15:0] ibias_csa;
logic [3:0] ibias_vref_buffer;
logic [3:0] ibias_vcm_buffer;
logic [3:0] ibias_tpulse;
logic [15:0] adc_ibias_delay;
logic [4:0] ref_current_trim;
logic [1:0] adc_comp_trim;
logic [7:0] vref_dac;
logic [7:0] vcm_dac;
logic [NUMCHANNELS-1:0] csa_bypass_enable;
logic [NUMCHANNELS-1:0] csa_bypass_select;
logic [NUMCHANNELS-1:0] csa_monitor_select;
logic [NUMCHANNELS-1:0] csa_testpulse_enable;
logic [7:0] csa_testpulse_dac;
logic [3:0] adc_ibias_delay_monitor;
logic [3:0] current_monitor_bank0;
logic [3:0] current_monitor_bank1;
logic [3:0] current_monitor_bank2;
logic [3:0] current_monitor_bank3;
logic [2:0] voltage_monitor_bank0;
logic [2:0] voltage_monitor_bank1;
logic [2:0] voltage_monitor_bank2;
logic [2:0] voltage_monitor_bank3;
logic [7:0] voltage_monitor_refgen;
logic en_analog_monitor;
logic [3:0] tx_slices0;
logic [3:0] tx_slices1;
logic [3:0] tx_slices2;
logic [3:0] tx_slices3;
logic [3:0] i_tx_diff0;
logic [3:0] i_tx_diff1;
logic [3:0] i_tx_diff2;
logic [3:0] i_tx_diff3;
logic [3:0] i_rx0;
logic [3:0] i_rx1;
logic [3:0] i_rx2;
logic [3:0] i_rx3;
logic [3:0] i_rx_clk;
logic [3:0] i_rx_rst;
logic [3:0] i_rx_ext_trig;
logic [4:0] r_term0;
logic [4:0] r_term1;
logic [4:0] r_term2;
logic [4:0] r_term3;
logic [4:0] r_term_clk;
logic [4:0] r_term_rst;
logic [4:0] r_term_ext_trig;
logic [3:0] v_cm_lvds_tx0;
logic [3:0] v_cm_lvds_tx1;
logic [3:0] v_cm_lvds_tx2;
logic [3:0] v_cm_lvds_tx3;
logic [ADCBITS*NUMCHANNELS-1:0] dout;
logic [NUMCHANNELS-1:0] done;
logic [NUMCHANNELS-1:0] hit;
logic external_trigger;
logic [3:0] posi;
logic clk;
logic reset_n;

logic [63:0] observed_event;

`include "larpix_constants.sv"

digital_core dut (
    .piso(piso),
    .digital_monitor(digital_monitor),
    .sample(sample),
    .tx_enable(tx_enable),
    .pixel_trim_dac(pixel_trim_dac),
    .threshold_global(threshold_global),
    .gated_reset(gated_reset),
    .csa_reset(csa_reset),
    .bypass_caps_enable(bypass_caps_enable),
    .ibias_tdac(ibias_tdac),
    .ibias_comp(ibias_comp),
    .ibias_buffer(ibias_buffer),
    .ibias_csa(ibias_csa),
    .ibias_vref_buffer(ibias_vref_buffer),
    .ibias_vcm_buffer(ibias_vcm_buffer),
    .ibias_tpulse(ibias_tpulse),
    .adc_ibias_delay(adc_ibias_delay),
    .ref_current_trim(ref_current_trim),
    .adc_comp_trim(adc_comp_trim),
    .vref_dac(vref_dac),
    .vcm_dac(vcm_dac),
    .csa_bypass_enable(csa_bypass_enable),
    .csa_bypass_select(csa_bypass_select),
    .csa_monitor_select(csa_monitor_select),
    .csa_testpulse_enable(csa_testpulse_enable),
    .csa_testpulse_dac(csa_testpulse_dac),
    .adc_ibias_delay_monitor(adc_ibias_delay_monitor),
    .current_monitor_bank0(current_monitor_bank0),
    .current_monitor_bank1(current_monitor_bank1),
    .current_monitor_bank2(current_monitor_bank2),
    .current_monitor_bank3(current_monitor_bank3),
    .voltage_monitor_bank0(voltage_monitor_bank0),
    .voltage_monitor_bank1(voltage_monitor_bank1),
    .voltage_monitor_bank2(voltage_monitor_bank2),
    .voltage_monitor_bank3(voltage_monitor_bank3),
    .voltage_monitor_refgen(voltage_monitor_refgen),
    .en_analog_monitor(en_analog_monitor),
    .tx_slices0(tx_slices0),
    .tx_slices1(tx_slices1),
    .tx_slices2(tx_slices2),
    .tx_slices3(tx_slices3),
    .i_tx_diff0(i_tx_diff0),
    .i_tx_diff1(i_tx_diff1),
    .i_tx_diff2(i_tx_diff2),
    .i_tx_diff3(i_tx_diff3),
    .i_rx0(i_rx0),
    .i_rx1(i_rx1),
    .i_rx2(i_rx2),
    .i_rx3(i_rx3),
    .i_rx_clk(i_rx_clk),
    .i_rx_rst(i_rx_rst),
    .i_rx_ext_trig(i_rx_ext_trig),
    .r_term0(r_term0),
    .r_term1(r_term1),
    .r_term2(r_term2),
    .r_term3(r_term3),
    .r_term_clk(r_term_clk),
    .r_term_rst(r_term_rst),
    .r_term_ext_trig(r_term_ext_trig),
    .v_cm_lvds_tx0(v_cm_lvds_tx0),
    .v_cm_lvds_tx1(v_cm_lvds_tx1),
    .v_cm_lvds_tx2(v_cm_lvds_tx2),
    .v_cm_lvds_tx3(v_cm_lvds_tx3),
    .dout(dout),
    .done(done),
    .hit(hit),
    .external_trigger(external_trigger),
    .posi(posi),
    .clk(clk),
    .reset_n(reset_n)
);

always #5 clk = ~clk;

function automatic [63:0] expected_packet(
    input [27:0] ts,
    input [9:0] adc
);
    logic [62:0] payload;
    begin
        payload = '0;
        payload[1:0] = 2'b01;
        payload[9:2] = 8'h01;
        payload[15:10] = 6'd0;
        payload[43:16] = ts;
        payload[55:46] = adc;
        payload[57:56] = 2'b00;
        payload[62] = 1'b1;
        expected_packet = {~^payload, payload};
    end
endfunction

function automatic bit has_unknown64(input [63:0] value);
    begin
        has_unknown64 = (^value === 1'bx);
    end
endfunction

task automatic expect_true(input bit condition, input [255:0] msg);
    begin
        if (!condition) begin
            $display("FAIL: %0s", msg);
            $fatal(1);
        end
    end
endtask

task automatic expect_eq8(input [7:0] actual, input [7:0] expected, input [255:0] msg);
    begin
        if (actual !== expected) begin
            $display("FAIL: %0s actual=%0h expected=%0h", msg, actual, expected);
            $fatal(1);
        end
    end
endtask

task automatic expect_eq4(input [3:0] actual, input [3:0] expected, input [255:0] msg);
    begin
        if (actual !== expected) begin
            $display("FAIL: %0s actual=%0h expected=%0h", msg, actual, expected);
            $fatal(1);
        end
    end
endtask

task automatic wait_cycles(input int count);
    begin
        repeat (count) @(posedge clk);
    end
endtask

// PASS requires all of the following to hold:
// 1. Reset/default config comes up correctly:
//    - config_bits[CHIP_ID] must be 8'h01
//    - config_bits[ENABLE_POSI][3:0] must be 4'hF
//    - tx_enable must remain 4'h0 by default
//    - sample[0] must return high after reset completes
// 2. Hierarchical config pokes must take effect:
//    - channel 0 becomes enabled
//    - channel 0 becomes unmasked
//    - downstream TX lane 0 becomes enabled
// 3. One injected natural hit plus ADC done pulse must produce a local
//    event visible at event_router.
// 4. The observed event packet must contain no X/Z bits when sampled.
// 5. The observed event packet fields must match the expected local-data
//    packet format:
//    - packet type = data
//    - chip ID = 0x01
//    - channel ID = 0
//    - ADC field = 42
//    - trigger type = natural
//    - downstream marker bit set
// 6. The packet parity and fixed fields must match the reconstructed
//    expected local event packet.
// 7. The event must enter the TX path and assert UART0 tx_busy.
// 8. UART0 must leave the idle state after transmission starts.
// Any failed check triggers $fatal(1), so the test only prints PASS if
// every condition above succeeds.
initial begin
    clk = 1'b0;
    reset_n = 1'b0;
    external_trigger = 1'b0;
    posi = 4'hF;
    dout = '0;
    done = '0;
    hit = '0;
    observed_event = '0;

    // Hold reset long enough for reset_sync to drive both synchronized resets low.
    wait_cycles(40);
    reset_n = 1'b1;

    // Wait long enough for reset_sync to release the core and config domains.
    wait_cycles(40);

    expect_eq8(dut.external_interface_inst.config_regfile_inst.config_bits[CHIP_ID], 8'h01,
        "default chip ID should load from config defaults");
    expect_eq4(dut.external_interface_inst.config_regfile_inst.config_bits[ENABLE_POSI][3:0], 4'hF,
        "default POSI enables should load from config defaults");
    expect_eq4(tx_enable, 4'h0,
        "TX lanes should be disabled by default");
    expect_true(sample[0] === 1'b1,
        "channel sample should idle high once reset completes");

    // Reconfigure one channel and one downstream TX lane directly through the regfile.
    @(posedge clk);
    dut.external_interface_inst.config_regfile_inst.config_bits[CSA_ENABLE] = 8'h01;
    dut.external_interface_inst.config_regfile_inst.config_bits[CHANNEL_MASK] = 8'hFE;
    dut.external_interface_inst.config_regfile_inst.config_bits[ENABLE_TRIG_MODES] = 8'h00;
    dut.external_interface_inst.config_regfile_inst.config_bits[DIGITAL] = 8'h00;
    dut.external_interface_inst.config_regfile_inst.config_bits[ENABLE_PISO_DOWN] = 8'h01;

    wait_cycles(2);
    expect_eq4(tx_enable, 4'h1,
        "TX lane 0 should enable after config poke");
    expect_true(dut.csa_enable[0] === 1'b1,
        "channel 0 should be enabled after config poke");
    expect_true(dut.channel_mask[0] === 1'b0,
        "channel 0 should be unmasked after config poke");

    // Inject one natural trigger on channel 0 and a completed ADC sample.
    dout[9:0] = 10'd42;
    hit[0] = 1'b1;
    @(posedge clk);
    hit[0] = 1'b0;

    // The CDC path needs several cycles of asserted done to create a done_sync rising edge.
    wait_cycles(3);
    done[0] = 1'b1;
    wait_cycles(4);
    done[0] = 1'b0;

    // Wait for event_router to present the event packet.
    repeat (80) begin
        @(posedge clk);
        if (dut.event_router_inst.event_valid) begin
            observed_event = dut.event_router_inst.event_data;
            break;
        end
    end

    expect_true(!has_unknown64(observed_event),
        "observed event packet should not contain unknown bits");
    expect_true(dut.event_router_inst.event_valid === 1'b1,
        "event_router should assert event_valid for the injected hit");
    expect_true(observed_event[1:0] === 2'b01,
        "packet type should be data");
    expect_eq8(observed_event[9:2], 8'h01,
        "packet chip ID should match default chip ID");
    expect_true(observed_event[15:10] === 6'd0,
        "packet channel ID should be channel 0");
    expect_true(observed_event[55:46] === 10'd42,
        "packet ADC field should match injected ADC value");
    expect_true(observed_event[57:56] === 2'b00,
        "packet trigger type should be natural");
    expect_true(observed_event[62] === 1'b1,
        "packet downstream marker should be set");
    expect_true(observed_event === expected_packet(observed_event[43:16], 10'd42),
        "packet parity and fixed fields should match the expected local event format");

    // The packet should reach the Hydra/TX path and start transmission on lane 0.
    repeat (120) begin
        @(posedge clk);
        if (dut.external_interface_inst.g_uart[0].uart_inst.tx_busy)
            break;
    end

    expect_true(dut.external_interface_inst.g_uart[0].uart_inst.tx_busy === 1'b1,
        "UART0 should begin transmitting the event packet");
    wait_cycles(2);
    expect_true(piso[0] === 1'b0 || dut.external_interface_inst.g_uart[0].uart_inst.uart_tx_inst.tx_cnt != 8'd0,
        "UART0 should leave the idle state after transmission starts");

    $display("PASS: digital_core_smoke_tb completed successfully");
    $finish;
end

endmodule
