///////////////////////////////////////////////////////////////////
// File Name: larpix_constants.sv
// Engineer:  Carl Grace (crgrace@lbl.gov)
// Description:  Constants for LArPix operation and simulation
//
///////////////////////////////////////////////////////////////////

`ifndef _larpix_constants_
`ifndef SYNTHESIS 
`define _larpix_constants_
`endif

// declare needed variables
localparam bit TRUE = 1;
localparam bit FALSE = 0;
localparam bit UPSTREAM = 0;
localparam bit DOWNSTREAM = 1;

// define stats interface
localparam int STATS_NONE                   = 0;
localparam int STATS_LOCAL_DATA_PACKETS     = 1;
localparam int STATS_LOCAL_CONFIG_READS     = 2;
localparam int STATS_LOCAL_CONFIG_WRITES    = 3;
localparam int STATS_DROPPED_PACKETS        = 4;
localparam int STATS_TOTAL_PACKETS_LSB      = 5;
localparam int STATS_TOTAL_PACKETS_MSB      = 6;
localparam int STATS_FIFO_COUNTER_OUT       = 7;
localparam int STATS_HYDRA_FIFO_HIGH_WATER  = 8;

localparam bit SILENT = 0;
localparam bit VERBOSE = 1;          // high to print out verification results
localparam int MAGIC_NUMBER = 32'h89_50_4E_47;
//localparam int REGNUM = 256;

// localparams to define config registers
// configuration word definitions
localparam int PIXEL_TRIM = 0;
localparam int GLOBAL_THRESH = 64;
localparam int CSA_CTRL = 65;
localparam int CSA_ENABLE = 66;
localparam int IBIAS_TDAC = 74;
localparam int IBIAS_COMP = 75;
localparam int IBIAS_BUFFER = 76;
localparam int IBIAS_CSA = 77;
localparam int IBIAS_VREF= 78;
localparam int IBIAS_VCM = 79;
localparam int IBIAS_TPULSE = 80;
localparam int REFGEN = 81;
localparam int DAC_VREF = 82;
localparam int ADC_IBIAS_DELAY = 83;
localparam int BYPASS_SELECT = 84;
localparam int CSA_MONITOR_SEL = 92;
localparam int CSA_TEST_ENABLE = 100;   
localparam int CSA_TEST_DAC = 108;
localparam int IMONITOR0 = 109;
localparam int IMONITOR1 = 110;
localparam int VMONITOR0 = 111;
localparam int VMONITOR1 = 112;
localparam int VMONITOR2 = 113;
localparam int DMONITOR0 = 114;
localparam int DMONITOR1 = 115;
localparam int FIFO_HW_LSB = 116;
localparam int FIFO_HW_MSB = 117;
localparam int TOTAL_PACKETS_LSB = 118;
localparam int TOTAL_PACKETS_MSB = 119;
localparam int DROPPED_PACKETS = 120;
localparam int ADC_HOLD_DELAY = 121;
localparam int CHIP_ID = 122;
localparam int DIGITAL = 123;
localparam int ENABLE_PISO_UP = 124;
localparam int ENABLE_PISO_DOWN = 125;
localparam int ENABLE_POSI = 126;
localparam int ANALOG_MONITOR = 127;
localparam int ENABLE_TRIG_MODES = 128;
localparam int SHADOW_RESET_LENGTH = 129;
localparam int ADC_BURST = 130;
localparam int CHANNEL_MASK = 131;
localparam int EXTERN_TRIG_MASK = 139;
localparam int CROSS_TRIG_MASK = 147;
localparam int PER_TRIG_MASK = 155;
localparam int RESET_CYCLES = 163;
localparam int PER_TRIG_CYC = 166;
localparam int ENABLE_ADC_MODES = 170;
localparam int RESET_THRESHOLD = 171;
localparam int MIN_DELTA_ADC = 172;
localparam int DIGITAL_THRESHOLD_MSB = 173;
localparam int DIGITAL_THRESHOLD_LSB = 175;
localparam int LIGHTPIX0 = 237;
localparam int LIGHTPIX1 = 238;
localparam int TRX0 = 239;
localparam int TRX1 = 240;
localparam int TRX2 = 241;
localparam int TRX3 = 242;
localparam int TRX4 = 243;
localparam int TRX5 = 244;
localparam int TRX6 = 245;
localparam int TRX7 = 246;
localparam int TRX8 = 247;
localparam int TRX9 = 248;
localparam int TRX10 = 249;
localparam int TRX11 = 250;
localparam int TRX12 = 251;
localparam int TRX13 = 252;
localparam int TRX14 = 253;
localparam int TRX15 = 254;
localparam int TRX16 = 255;


// UART ops
localparam logic[1:0] DATA_OP = 2'b01;
localparam logic[1:0] CONFIG_WRITE_OP = 2'b10;
localparam logic[1:0] CONFIG_READ_OP = 2'b11;

// SPI ops
localparam bit WRITE = 1;
localparam bit READ = 0;


`endif // _larpix_constants_
