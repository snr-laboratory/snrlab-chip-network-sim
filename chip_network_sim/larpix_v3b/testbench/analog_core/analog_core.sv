///////////////////////////////////////////////////////////////////
// File Name: analog_core.sv
// Engineer:  Carl Grace (crgrace@lbl.gov)
// Description: SystemVerilog model of analog core of LArPix-v2 
//              Analog core comprises 64 channels of Charge-Sensitive
//              amplifiers, discriminator and 10-bit async SAR ADC
//          
///////////////////////////////////////////////////////////////////

module analog_core 
    #(parameter NUMCHANNELS = 64,       // number of ADC channels
    parameter VREF = 1.6,               // top end of ADC range
    parameter VCM = 0.8,                // bottom end of ADC range
    parameter ADCBITS = 10,              // number of bits in ADC
    parameter PIXEL_TRIM_DAC_BITS = 6,  // number of bits in pixel trim DAC
    parameter GLOBAL_DAC_BITS = 8, // number of bits in global threshold DAC
    parameter DACBITS = 6,              // number of bits in threshold DAC
    parameter CFB_CSA = 40e-15,         // feedback capacitor in CSA
    parameter VOUT_DC_CSA = 0.5,        // nominal dc output voltage of CSA
    parameter VDDA = 1.8,              // nominal analog supply
    parameter VOFFSET = 0.47)         // discriminator threshold offset
    (output logic [ADCBITS*NUMCHANNELS-1:0] dout,             // digital bits from ADC
    output logic [NUMCHANNELS-1:0] hit,  // high when discriminator fires
    output logic [NUMCHANNELS-1:0] done,  // high when ADC conversion finished
    input logic [PIXEL_TRIM_DAC_BITS*NUMCHANNELS-1:0] pixel_trim_dac,
    input logic [GLOBAL_DAC_BITS-1:0] threshold_global,
    input logic [NUMCHANNELS-1:0] gated_reset,
    input logic [NUMCHANNELS-1:0] csa_bypass_enable,
    input logic [NUMCHANNELS-1:0] csa_monitor_select,
    input logic [NUMCHANNELS-1:0] csa_bypass_select,
    input logic [NUMCHANNELS-1:0] sample,      // high to sample CSA output
    input logic [NUMCHANNELS-1:0] csa_reset,   // arming signal
    input real charge_in_r [NUMCHANNELS-1:0]);  // input  signal


genvar i;
generate
    for (i=0; i<NUMCHANNELS; i=i+1) begin : CHANNELS

        analog_channel 
        #(.VREF(VREF),
        .VCM(VCM),
        .ADCBITS(ADCBITS),
        .PIXEL_TRIM_DAC_BITS(PIXEL_TRIM_DAC_BITS),
        .GLOBAL_DAC_BITS(GLOBAL_DAC_BITS),
        .CFB_CSA(CFB_CSA),
        .VOUT_DC_CSA(VOUT_DC_CSA),
        .VDDA(VDDA),
        .VOFFSET(VOFFSET)
        ) analog_channel_inst (
        .dout               (dout[ADCBITS*(i+1)-1:ADCBITS*i]), 
        .hit                (hit[i]),
        .done               (done[i]),
        .charge_in_r        (charge_in_r[i]),
        .sample             (sample[i]),
        .threshold_global   (threshold_global),
        .pixel_trim_dac     (pixel_trim_dac[PIXEL_TRIM_DAC_BITS*(i+1)-1:PIXEL_TRIM_DAC_BITS*i]),
        .csa_reset      (csa_reset[i])
        );
    end
endgenerate

endmodule
