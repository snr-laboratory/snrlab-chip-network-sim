///////////////////////////////////////////////////////////////////
// File Name: analog_channel.sv
// Engineer:  Carl Grace (crgrace@lbl.gov)
// Description: SystemVerilog model of LArPix-v2 analog channel
//
//              input is *charge*. LArPix-v2 detects electrons, so
//              adding charge packets reduces input voltage
//
///////////////////////////////////////////////////////////////////

module analog_channel 
    #(parameter VREF = 1.0,
    parameter VCM = 0.5,                 // top end of ADC range
    parameter ADCBITS = 10,              // number of bits in ADC
    parameter PIXEL_TRIM_DAC_BITS = 5,  // number of bits in pixel trim DAC
    parameter GLOBAL_DAC_BITS = 8, // number of bits in global threshold DAC
    parameter CFB_CSA = 40e-15,     // feedback capacitor in CSA
    parameter VOUT_DC_CSA = 0.5,   // nominal dc output voltage of CSA
    parameter VDDA = 1.8,           // nominal analog supply
    parameter VOFFSET = 0.47)       // discriminator threshold offset
    (output logic [ADCBITS-1:0] dout,             // digital bits from ADC
    output logic hit,               // high when discriminator fires
    output logic done,                 // high when ADC conversion finished
    input real charge_in_r,           // input signal
    input logic sample,                       // high to sample CSA output
    input logic [7:0] threshold_global,   // threshold DAC setting
    input logic [4:0] pixel_trim_dac, // threshold trim    
    input logic csa_reset);       // arming signal from master control
   

// internal nets

real csa_vout_r;
real vref_r, vcm_r, vin_r; 
// instantiate channel components

initial begin
    vref_r = VREF;
    vcm_r = VCM;
end // initial

// CSA
csa
    #(.CFB_CSA(CFB_CSA),
    .VOUT_DC_CSA(VOUT_DC_CSA)
    ) csa_inst (
    .csa_vout_r     (csa_vout_r),
    .charge_in_r    (charge_in_r),
    .csa_reset      (csa_reset)
    );

// discriminator
discriminator
    #(.VDDA(VDDA),
    .VOFFSET(VOFFSET)
    ) discriminator_inst (
    .hit                (hit),
    .signal_r           (csa_vout_r),
    .threshold_global   (threshold_global),
    .pixel_trim_dac     (pixel_trim_dac[4:0])
    );

// analog model of SAR ADC
sar_async_adc
    #(
    .ADCBITS(ADCBITS)
    ) sar_async_adc_inst( 
        .dout           (dout),
        .done           (done),
        .sample         (sample),
        .vref_r         (vref_r),
        .vcm_r          (vcm_r),
        .vin_r          (csa_vout_r)
    );// SAR ADC

endmodule
