///////////////////////////////////////////////////////////////////
// File Name: analog_tasks.sv
// Engineer:  Carl Grace (crgrace@lbl.gov)
// Description:     Tasks for generating analog data
//          
///////////////////////////////////////////////////////////////////

`ifndef _analog_tasks_
`define _analog_tasks_

`include "larpix_constants.sv"  // all sim constants defined here

task genDataHit;

input numChips;
input numChannels;
input maxE;
input debug;
output sentTag;
output chargeSignal;

integer numChips;
integer numChannels;
integer maxE;
integer debug;

logic [7:0] whichChip;
logic [7:0] whichChannel;
logic [31:0] numE;
logic [63:0] sentTag;
logic [63:0] chargeSignal_hit;
logic [63:0] chargeSignal; // vector for all 64 channels
begin
    chargeSignal = 0;
    getSeed;
    numE = $urandom%maxE;
    whichChip = $urandom%numChips;
    whichChannel = $urandom_range(numChannels-1);
    sentTag = (whichChip << (48) | (whichChannel << 32) | numE);
    chargeSignal_hit = $realtobits(1.6e-19*numE);
    chargeSignal = chargeSignal_hit << (64*whichChannel);

    if (debug) begin
        $display("whichChip = %0d, = %h (hex)",whichChip,whichChip);
        $display("whichChannel = %0d, = %h (hex)",whichChannel,whichChannel);
        $display("sentTag = %h\n",sentTag);
        $display("chargeSignal(real) = %0f",1.6e-19*numE);
        $display("CSA output (real) = %0f",(1.6e-19*numE)/20e-15);
    end // if    
end
endtask

`endif // _analog_tasks_
