// File Name: config_regfile_assign.sv
// Engineer:  Carl Grace (crgrace@lbl.gov)
// Description:  Code used in config_regfile.sv for assignment
//          
///////////////////////////////////////////////////////////////////

        for (int i = 0; i < 64; i++) config_bits[PIXEL_TRIM + i] <= 8'h10;
        config_bits[GLOBAL_THRESH] <= 8'hFF;
        config_bits[CSA_CTRL] <= 8'h04;
        for (int i = 0; i < 8; i++) config_bits[CSA_ENABLE + i] <= 8'h00;
        config_bits[IBIAS_TDAC] <= 8'h08;
        config_bits[IBIAS_COMP] <= 8'h08;
        config_bits[IBIAS_BUFFER] <= 8'h08;
        config_bits[IBIAS_CSA] <= 8'h08;
        config_bits[IBIAS_VREF] <= 8'h08;
        config_bits[IBIAS_VCM] <= 8'h08;
        config_bits[IBIAS_TPULSE] <= 8'h05;
        config_bits[REFGEN] <= 8'h50;
        config_bits[DAC_VREF] <= 8'hDE;
        config_bits[ADC_IBIAS_DELAY] <= 8'h08;
        for (int i = 0; i < 8; i++) config_bits[BYPASS_SELECT + i] <= 8'h00;
        for (int i = 0; i < 8; i++) config_bits[CSA_MONITOR_SEL + i] <= 8'h00;
        for (int i = 0; i < 8; i++) config_bits[CSA_TEST_ENABLE + i] <= 8'hFF;
        config_bits[CSA_TEST_DAC] <= 8'h00;
        config_bits[IMONITOR0] <= 8'h00;
        config_bits[IMONITOR1] <= 8'h00;
        config_bits[VMONITOR0] <= 8'h00;
        config_bits[VMONITOR1] <= 8'h00;
        config_bits[VMONITOR2] <= 8'h00;
        config_bits[DMONITOR0] <= 8'h00;
        config_bits[DMONITOR1] <= 8'h00;
        config_bits[FIFO_HW_LSB] <= 8'h00;
        config_bits[FIFO_HW_MSB] <= 8'h00;
        config_bits[TOTAL_PACKETS_LSB] <= 8'h00;
        config_bits[TOTAL_PACKETS_MSB] <= 8'h00;
        config_bits[DROPPED_PACKETS] <= 8'h00;
        for (int i = 0; i < 2; i++) config_bits[ADC_HOLD_DELAY + i] <= 8'h00;
        config_bits[CHIP_ID] <= 8'h01;
        config_bits[DIGITAL] <= 8'h90;
        config_bits[ENABLE_PISO_UP] <= 8'h00;
        config_bits[ENABLE_PISO_DOWN] <= 8'h00;
        config_bits[ENABLE_POSI] <= 8'h0F;
        config_bits[ANALOG_MONITOR] <= 8'h00;
        config_bits[ENABLE_TRIG_MODES] <= 8'h60;
        config_bits[SHADOW_RESET_LENGTH] <= 8'h00;
        config_bits[ADC_BURST] <= 8'h00;
        for (int i = 0; i< 8; i++) config_bits[CHANNEL_MASK + i] <= 8'hFF;
        for (int i = 0; i < 8; i++) config_bits[EXTERN_TRIG_MASK + i] <= 8'hFF;
        for (int i = 0; i < 8; i++) config_bits[CROSS_TRIG_MASK + i] <= 8'hFF;
        for (int i = 0; i < 8; i++) config_bits[PER_TRIG_MASK + i] <= 8'hFF;
        for (int i = 0; i < 3; i++) 
            if (i == 1) config_bits[RESET_CYCLES + i] <= 8'h10;
            else config_bits[RESET_CYCLES + i] <= 8'h00;
        for (int i = 0; i < 4; i++) config_bits[PER_TRIG_CYC + i] <= 8'h0;
        config_bits[ENABLE_ADC_MODES] <= 8'h4C;
        config_bits[MIN_DELTA_ADC] <= 8'b00;
        config_bits[RESET_THRESHOLD] <= 8'hFF;
        for (int i = 0; i< 2; i++) config_bits[DIGITAL_THRESHOLD_MSB + i] <= 8'h00;
        
        for (int i = 0; i < 64; i++) config_bits[DIGITAL_THRESHOLD_LSB + i] <= 8'b00;
        config_bits[TRX0] <= 8'h88;
        config_bits[TRX1] <= 8'h88;
        config_bits[TRX2] <= 8'h88;
        config_bits[TRX3] <= 8'h88;
        config_bits[TRX4] <= 8'h00;
        config_bits[TRX5] <= 8'h00;
        config_bits[TRX6] <= 8'h00;
        config_bits[TRX7] <= 8'h00;
        config_bits[TRX8] <= 8'h02;
        config_bits[TRX9] <= 8'h02;
        config_bits[TRX10] <= 8'h02;
        config_bits[TRX11] <= 8'h02;
        config_bits[TRX12] <= 8'h00;
        config_bits[TRX13] <= 8'h00;
        config_bits[TRX14] <= 8'h00;
        config_bits[TRX15] <= 8'h55;
        config_bits[TRX16] <= 8'h55;

