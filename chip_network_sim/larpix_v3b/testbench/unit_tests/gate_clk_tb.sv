`timescale 1ns/1ps
`default_nettype none

// Pass criteria for this testbench:
// 1. With both gates disabled initially, gated_pos must be 0 and gated_neg must be 1.
// 2. While disabled, the positive-edge gate must propagate zero rising edges.
// 3. While disabled, the negative-edge gate must propagate zero falling edges.
// 4. Enabling the positive-edge gate while CLK is low must allow the next rising edge through.
// 5. Disabling the positive-edge gate while CLK is high must let the current pulse finish but block future rising edges.
// 6. A short enable glitch on the positive-edge gate while CLK is high must not create a pulse.
// 7. Enabling the negative-edge gate while CLK is high must allow the next falling edge through.
// 8. Disabling the negative-edge gate while CLK is low must let the current low phase finish but block future falling edges.
// 9. A short enable glitch on the negative-edge gate while CLK is low must not create a falling edge.
// Every check below must pass. Any failure calls $fatal(1), so PASS is only printed if all conditions are met.

module gate_clk_tb;

logic clk;
logic en_pos;
logic en_neg;
logic gated_pos;
logic gated_neg;
integer pos_edges_seen;
integer neg_edges_seen;

initial clk = 1'b0;
always #5 clk = ~clk;

// Count propagated edges.
always @(posedge gated_pos)
    pos_edges_seen <= pos_edges_seen + 1;

always @(negedge gated_neg)
    neg_edges_seen <= neg_edges_seen + 1;

// DUTs under the Verilator-friendly branch.
gate_posedge_clk pos_dut (
    .ENCLK(gated_pos),
    .EN   (en_pos),
    .CLK  (clk)
);

gate_negedge_clk neg_dut (
    .ENCLK(gated_neg),
    .EN   (en_neg),
    .CLK  (clk)
);

task automatic expect_equal_int;
    input integer got;
    input integer exp;
    input [255:0] msg;
    begin
        if (got !== exp) begin
            $display("FAIL: %0s got=%0d exp=%0d at t=%0t", msg, got, exp, $time);
            $fatal(1);
        end
    end
endtask

task automatic expect_equal_bit;
    input logic got;
    input logic exp;
    input [255:0] msg;
    begin
        if (got !== exp) begin
            $display("FAIL: %0s got=%0b exp=%0b at t=%0t", msg, got, exp, $time);
            $fatal(1);
        end
    end
endtask

initial begin
    en_pos = 1'b0;
    en_neg = 1'b0;
    pos_edges_seen = 0;
    neg_edges_seen = 0;

    // Let initial values settle.
    #1;
    expect_equal_bit(gated_pos, 1'b0, "posedge gate disabled output low");
    expect_equal_bit(gated_neg, 1'b1, "negedge gate disabled output high");

    // Disabled gates should block their active edges.
    repeat (2) @(posedge clk);
    expect_equal_int(pos_edges_seen, 0, "disabled posedge gate blocks edges");
    repeat (2) @(negedge clk);
    expect_equal_int(neg_edges_seen, 0, "disabled negedge gate blocks edges");

    // Enable the posedge gate while CLK is low. The next rising edge should pass.
    @(negedge clk);
    en_pos = 1'b1;
    @(posedge clk);
    #1;
    expect_equal_int(pos_edges_seen, 1, "enabled posedge gate propagates next rising edge");
    expect_equal_bit(gated_pos, 1'b1, "enabled posedge gate follows high phase");

    // Disable the posedge gate while CLK is high. Current pulse completes, next one is blocked.
    en_pos = 1'b0;
    @(negedge clk);
    #1;
    expect_equal_bit(gated_pos, 1'b0, "posedge gate drops after source clock falls");
    @(posedge clk);
    #1;
    expect_equal_int(pos_edges_seen, 1, "disabling posedge gate during high blocks future rising edges only");

    // Glitch test: toggling enable while CLK is high must not create a pulse.
    en_pos = 1'b1;
    #1;
    en_pos = 1'b0;
    @(negedge clk);
    @(posedge clk);
    #1;
    expect_equal_int(pos_edges_seen, 1, "posedge gate ignores high-phase enable glitch");

    // Enable the negedge gate while CLK is high. The next falling edge should pass.
    @(posedge clk);
    en_neg = 1'b1;
    @(negedge clk);
    #1;
    expect_equal_int(neg_edges_seen, 1, "enabled negedge gate propagates next falling edge");
    expect_equal_bit(gated_neg, 1'b0, "enabled negedge gate follows low phase");

    // Disable the negedge gate while CLK is low. Current low phase completes, next falling edge is blocked.
    en_neg = 1'b0;
    @(posedge clk);
    #1;
    expect_equal_bit(gated_neg, 1'b1, "negedge gate returns high after source clock rises");
    @(negedge clk);
    #1;
    expect_equal_int(neg_edges_seen, 1, "disabling negedge gate during low blocks future falling edges only");

    // Glitch test: toggling enable while CLK is low must not create a falling edge.
    en_neg = 1'b1;
    #1;
    en_neg = 1'b0;
    @(posedge clk);
    @(negedge clk);
    #1;
    expect_equal_int(neg_edges_seen, 1, "negedge gate ignores low-phase enable glitch");

    $display("PASS: gate_clk_tb completed successfully");
    $finish;
end

endmodule

`default_nettype wire
