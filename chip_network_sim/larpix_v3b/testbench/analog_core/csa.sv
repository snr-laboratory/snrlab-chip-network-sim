///////////////////////////////////////////////////////////////////
// File Name: csa.sv
// Engineer:  Carl Grace (crgrace@lbl.gov)
// Description: SystemVerilog model of LArPix-v2 charge sensitive amp
//
//              input is *charge*
//              output is voltage
//
///////////////////////////////////////////////////////////////////

module csa 
    #(parameter CFB_CSA = 40e-15,
    parameter VOUT_DC_CSA = 0.5)
    (output real csa_vout_r,    // csa output voltage
    input real charge_in_r,     // input signal
    input logic csa_reset       // csa_vout = VOUT_DC when high
    );


// CSA. Note charge is in columbs. Charge deposited on input makes input 
// voltage decrease. Since CSA is inverting, CSA output increases as 
// electrons are added.

always @(*) begin
    if (csa_reset)
        csa_vout_r = VOUT_DC_CSA;
    else
        csa_vout_r = csa_vout_r + -(charge_in_r/CFB_CSA);
end

endmodule
