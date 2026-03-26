///////////////////////////////////////////////////////////////////
// File Name: gate_negedge_clk.sv
// Engineer:  Dario Gnani (dgnani@lbl.gov)
// Description: Clock gating logic for negedge-sensitive seq logic.
//              Basic description of integrated clock gating (ICG) cell.
//
///////////////////////////////////////////////////////////////////
`timescale 1ns / 10ps
module gate_negedge_clk
    (output logic ENCLK,           // gated negedge clock
    input logic EN,                // clock-gating: enable clock (active high)
    input logic CLK);             // negedge clock

logic EN_dly;
always EN_dly = #0.5 EN; // avoid (false) hold violations


 CKLHQD4
    mapped_ICGN(
    .Q(ENCLK),
    .E(EN_dly),
    .TE(1'b0),
    .CPN(CLK));


endmodule

