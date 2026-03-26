`timescale 1ns/1ps
`default_nettype none

//--------------------------------------------------------------
//  Testbench for the top‑level digital_core
//--------------------------------------------------------------
module digital_core_tb;

  //  Parameters
  localparam int WIDTH        = 64;        // packet width (no start/stop)
  localparam int NUM_UARTS    = 4;         // number of UARTs
  localparam int NUMCHANNELS = 64;        // analog channels
  localparam int ADCBITS     = 10;
  localparam int IDLE_CYCLES = 3;         // UART idle cycles before a word
  localparam real CLK_PERIOD = 200.0;     // 5 MHz → 200 ns period
  localparam int PIXEL_TRIM_DAC_BITS = 5;
  localparam int GLOBAL_DAC_BITS = 8;
  localparam int TESTPULSE_DAC_BITS = 8;
  localparam int REGNUM    = 256;

//  Clock & reset
logic clk;
logic reset_n;
bit verbose;

  //  -----  Outputs that we will *observe*  -----
logic [NUM_UARTS-1:0] piso;               // serial TX (parallel)
logic digital_monitor;    // not used in TB
logic [NUMCHANNELS-1:0] sample;             // channel‑sample pulse
logic [WIDTH-1:0]            tx_data_uart [NUM_UARTS];
logic [NUM_UARTS-1:0]        tx_enable;
logic [NUM_UARTS-1:0]        uld_rx_data_uart;

logic [WIDTH-1:0]   rx_data_tb      [NUM_UARTS];
logic rx_empty_tb     [NUM_UARTS];
//logic [WIDTH-1:0] uld_rx_data_tb;

logic [NUM_UARTS-1:0]        enable_posi;
logic [NUM_UARTS-1:0]        enable_piso_upstream;
logic [NUM_UARTS-1:0]        enable_piso_downstream;
// constants (e.g. register definitions)
`include "larpix_constants.sv"

logic [WIDTH-1:0] receivedData;
logic [63:0] packetNumber;     // tagged input signal to scoreboard
// parse rx data
logic [1:0] rcvd_packet_declare;
logic [7:0] rcvd_chip_id;
logic [5:0] rcvd_channel_id;
logic [27:0] rcvd_time_stamp;
logic [9:0] rcvd_data_word;
logic [1:0] rcvd_trigger_type;
logic [7:0] rcvd_regmap_data;
logic [7:0] rcvd_regmap_addr;
logic [10:0] rcvd_fifo_cnt;
logic [2:0] rcvd_local_fifo_cnt;
logic rcvd_reset_sample_flag;
logic rcvd_cds_flag;
logic rcvd_downstream_marker_bit;
logic rcvd_fifo_half_bit;
logic rcvd_fifo_full_bit;
logic rcvd_local_fifo_half_bit;
logic rcvd_local_fifo_full_bit;
logic [1:0] rcvd_tally;
logic [31:0] rcvd_magic_number;
logic rcvd_parity_bit;
logic expected_parity_bit;

  //  -----  All of the other configuration‑bit outputs  -----
  logic [PIXEL_TRIM_DAC_BITS*NUMCHANNELS-1:0] pixel_trim_dac;
  logic [GLOBAL_DAC_BITS-1:0]                threshold_global;
  logic [NUMCHANNELS-1:0]                    gated_reset;
  logic [NUMCHANNELS-1:0]                    csa_reset;
  logic [NUMCHANNELS-1:0]                    bypass_caps_enable;
  logic [15:0]                               ibias_tdac;
  logic [15:0]                               ibias_comp;
  logic [15:0]                               ibias_buffer;
  logic [15:0]                               ibias_csa;
  logic [3:0]                                ibias_vref_buffer;
  logic [3:0]                                ibias_vcm_buffer;
  logic [3:0]                                ibias_tpulse;
  logic [15:0]                               adc_ibias_delay;
  logic [4:0]                                ref_current_trim;
  logic [1:0]                                adc_comp_trim;
  logic [7:0]                                vref_dac;
  logic [7:0]                                vcm_dac;
  logic [NUMCHANNELS-1:0]                    csa_bypass_enable;
  logic [NUMCHANNELS-1:0]                    csa_bypass_select;
  logic [NUMCHANNELS-1:0]                    csa_monitor_select;
  logic [NUMCHANNELS-1:0]                    csa_testpulse_enable;
  logic [TESTPULSE_DAC_BITS-1:0]            csa_testpulse_dac;
  logic [3:0]                               adc_ibias_delay_monitor;
  logic [3:0]                               current_monitor_bank0;
  logic [3:0]                               current_monitor_bank1;
  logic [3:0]                               current_monitor_bank2;
  logic [3:0]                               current_monitor_bank3;
  logic [2:0]                               voltage_monitor_bank0;
  logic [2:0]                               voltage_monitor_bank1;
  logic [2:0]                               voltage_monitor_bank2;
  logic [2:0]                               voltage_monitor_bank3;
  logic [7:0]                               voltage_monitor_refgen;
  logic                                      en_analog_monitor;
  logic [3:0]                                tx_slices0;
  logic [3:0]                                tx_slices1;
  logic [3:0]                                tx_slices2;
  logic [3:0]                                tx_slices3;
  logic [3:0]                                i_tx_diff0;
  logic [3:0]                                i_tx_diff1;
  logic [3:0]                                i_tx_diff2;
  logic [3:0]                                i_tx_diff3;
  logic [3:0]                                i_rx0;
  logic [3:0]                                i_rx1;
  logic [3:0]                                i_rx2;
  logic [3:0]                                i_rx3;
  logic [3:0]                                i_rx_clk;
  logic [3:0]                                i_rx_rst;
  logic [3:0]                                i_rx_ext_trig;
  logic [4:0]                                r_term0;
  logic [4:0]                                r_term1;
  logic [4:0]                                r_term2;
  logic [4:0]                                r_term3;
  logic [4:0]                                r_term_clk;
  logic [4:0]                                r_term_rst;
  logic [4:0]                                r_term_ext_trig;
  logic [3:0]                                v_cm_lvds_tx0;
  logic [3:0]                                v_cm_lvds_tx1;
  logic [3:0]                                v_cm_lvds_tx2;
  logic [3:0]                                v_cm_lvds_tx3;

  //  -----  Inputs that the TB *drives*  -----
  logic [ADCBITS*NUMCHANNELS-1:0]   dout;                // ADC results
  logic [NUMCHANNELS-1:0]           done;                // conversion‑done flag
  logic [NUMCHANNELS-1:0]           hit;                 // discriminator fire
  logic                             external_trigger;    // not used in current tests
  logic [3:0]                       posi;                // parallel UART‑RX lines


  //--------------------------------------------------------------
  //  DUT instantiation – connect the ports one‑by‑one
  //--------------------------------------------------------------
  digital_core #(
    .WIDTH        (WIDTH),
    .NUMCHANNELS  (NUMCHANNELS),
    .ADCBITS      (ADCBITS)
  ) dut (
    //  -----  Outputs  -----
    .piso                     (piso),
    .digital_monitor          (digital_monitor),
    .sample                   (sample),
    .tx_enable                (tx_enable),
    .pixel_trim_dac           (pixel_trim_dac),
    .threshold_global         (threshold_global),
    .gated_reset              (gated_reset),
    .csa_reset                (csa_reset),
    .bypass_caps_enable       (bypass_caps_enable),
    .ibias_tdac               (ibias_tdac),
    .ibias_comp               (ibias_comp),
    .ibias_buffer             (ibias_buffer),
    .ibias_csa                (ibias_csa),
    .ibias_vref_buffer        (ibias_vref_buffer),
    .ibias_vcm_buffer         (ibias_vcm_buffer),
    .ibias_tpulse             (ibias_tpulse),
    .adc_ibias_delay          (adc_ibias_delay),
    .ref_current_trim         (ref_current_trim),
    .adc_comp_trim            (adc_comp_trim),
    .vref_dac                 (vref_dac),
    .vcm_dac                  (vcm_dac),
    .csa_bypass_enable        (csa_bypass_enable),
    .csa_bypass_select        (csa_bypass_select),
    .csa_monitor_select       (csa_monitor_select),
    .csa_testpulse_enable     (csa_testpulse_enable),
    .csa_testpulse_dac        (csa_testpulse_dac),
    .adc_ibias_delay_monitor  (adc_ibias_delay_monitor),
    .current_monitor_bank0    (current_monitor_bank0),
    .current_monitor_bank1    (current_monitor_bank1),
    .current_monitor_bank2    (current_monitor_bank2),
    .current_monitor_bank3    (current_monitor_bank3),
    .voltage_monitor_bank0    (voltage_monitor_bank0),
    .voltage_monitor_bank1    (voltage_monitor_bank1),
    .voltage_monitor_bank2    (voltage_monitor_bank2),
    .voltage_monitor_bank3    (voltage_monitor_bank3),
    .voltage_monitor_refgen   (voltage_monitor_refgen),
    .en_analog_monitor        (en_analog_monitor),
    .tx_slices0               (tx_slices0),
    .tx_slices1               (tx_slices1),
    .tx_slices2               (tx_slices2),
    .tx_slices3               (tx_slices3),
    .i_tx_diff0               (i_tx_diff0),
    .i_tx_diff1               (i_tx_diff1),
    .i_tx_diff2               (i_tx_diff2),
    .i_tx_diff3               (i_tx_diff3),
    .i_rx0                    (i_rx0),
    .i_rx1                    (i_rx1),
    .i_rx2                    (i_rx2),
    .i_rx3                    (i_rx3),
    .i_rx_clk                 (i_rx_clk),
    .i_rx_rst                 (i_rx_rst),
    .i_rx_ext_trig            (i_rx_ext_trig),
    .r_term0                  (r_term0),
    .r_term1                  (r_term1),
    .r_term2                  (r_term2),
    .r_term3                  (r_term3),
    .r_term_clk               (r_term_clk),
    .r_term_rst               (r_term_rst),
    .r_term_ext_trig          (r_term_ext_trig),
    .v_cm_lvds_tx0            (v_cm_lvds_tx0),
    .v_cm_lvds_tx1            (v_cm_lvds_tx1),
    .v_cm_lvds_tx2            (v_cm_lvds_tx2),
    .v_cm_lvds_tx3            (v_cm_lvds_tx3),

    //  -----  Inputs  -----
    .dout                     (dout),
    .done                     (done),
    .hit                      (hit),
    .external_trigger         (external_trigger),
    .posi                     (posi),

    .clk                      (clk),
    .reset_n                  (reset_n)
  );

  //  Capture UART‑RX output (the deserialized packets)
logic [NUM_UARTS-1:0] rx_empty_tb_last; // used for edge detection
always @(posedge clk) begin

    uld_rx_data_uart <= '0;
    for (int i=0; i<NUM_UARTS; i++) begin
        rx_empty_tb_last[i] <= rx_empty_tb[i];
        if (!rx_empty_tb[i] & rx_empty_tb_last[i]) begin
            uld_rx_data_uart[i] <= 1'b1;               // read the packet
            sb.capture(i,rx_data_tb[i]);
        end
    end
end


//    UART‑RX model – deserialize the TX streams on the `piso` bus


  generate
    genvar i;
    for (i=0; i<NUM_UARTS; i++) begin : gen_uart_rx
      uart_rx #(.WIDTH(WIDTH)) urx (
        .rx_data    (rx_data_tb[i]),
        .rx_empty   (rx_empty_tb[i]),
        .rx_in      (piso[i]),          // serial line from the DUT
        .uld_rx_data (uld_rx_data_uart[i]),
        .clk        (clk),
        .reset_n    (reset_n)
      );
    end
  endgenerate

always @(posedge |uld_rx_data_uart) begin
    for (int i=0; i < NUM_UARTS; i++) begin
        if (uld_rx_data_uart[i]) begin
            receivedData = rx_data_tb[i];
            packetNumber++;
        end
    end
end 


  //  Scoreboard – queues of structs (identical to the hydra_ctrl TB)
  typedef struct packed {
    int                 which_piso;      // UART index that transmitted it
    logic [WIDTH-1:0]   packet;          // full 64‑bit packet
  } pkt_t;

  class scoreboard #(int WIDTH = 64, int NUM_UARTS = 4);
    pkt_t   expected_queue[$];
    pkt_t   received_queue[$];
    int     err_cnt = 0;

   //  push_expected packet into queue – called from the test stimulus
task push_exp (int which_piso, logic [WIDTH-1:0] pkt);
    pkt_t entry;
    entry.which_piso   = which_piso;
    entry.packet        = pkt;
    if (verbose) begin
        $display("in push_exp: pkt = %h, entry.packet = %h",pkt,entry.packet);
    end
    expected_queue.push_back(entry);
endtask


//  capture – called from the DUT‑monitor (ld_tx_data_uart)
task capture (int which_piso, logic [WIDTH-1:0] pkt);
    pkt_t entry;
    entry.which_piso   = which_piso;
    entry.packet        = pkt;
    if (verbose) begin
        $display("packet captured! which_piso = %d, pkt = %h",which_piso, pkt);
    end
    received_queue.push_back(entry);
endtask

task compare ();
    pkt_t exp_entry, rcv_entry;
    int i, j;
    bit found;
    assert( expected_queue.size() == received_queue.size() )
        else begin
            $error("%m: error. Recevied %0d pkts, expected %0d",
                received_queue.size(),expected_queue.size());
            err_cnt++;
        end
    foreach (expected_queue[i]) begin
        foreach (received_queue[j]) begin
            if (verbose) begin
                $display("\n******* sb.compare  ***********");
                $display("expected_queue[%0d].which_piso = %0d, pkt = %h",
                    i,expected_queue[i].which_piso,expected_queue[i].packet);
                $display("received_queue[%0d].which_piso = %0d, pkt = %h",
                    j,received_queue[j].which_piso,received_queue[j].packet);
            end
            if ((expected_queue[i].packet == received_queue[j].packet) &&
               (expected_queue[i].which_piso == received_queue[j].which_piso)) begin
                found = 1;
                received_queue.delete(j); 
            end
        end
    end
    // any leftovers are *unexpected* packets
    if (received_queue.size() != 0) begin
        foreach (received_queue[j]) begin
            rcv_entry = received_queue[j];
            $error("%0t: SCOREBOARD UNEXPECTED -- UART%0d  pkt %h",
                $time, rcv_entry.which_piso, rcv_entry.packet);
                err_cnt++;
        end
    end
endtask


    function void reset ();
      expected_queue.delete();
      received_queue.delete();
      err_cnt = 0;
    endfunction
    function int total_errors (); return err_cnt; endfunction
  endclass

  scoreboard sb = new();   // global scoreboard instance


//    Shadow register file (TB copy of config bits)
logic [7:0] shadow_regfile [REGNUM];   // TB's view of the config registers

// initialise the shadow after reset (defaults are loaded inside the DUT)
task automatic init_shadow_regfile;
    repeat (5) @(posedge clk);

    `include "shadow_regfile_assign.sv"
    $display("%0t: Shadow register file initialized (size %0d)", $time, REGNUM);
endtask

task automatic verify_shadow_regfile;
    int regfile_errors;
    regfile_errors = 0;
    for (int i = 0; i < REGNUM; i++) begin
        assert (shadow_regfile[i] == dut.external_interface_inst.config_regfile_inst.config_bits[i]) 
        else begin $error("%0t: Shadow mismatch at reg %0h: TB=%0h DUT=%0h",
                    $time, i, shadow_regfile[i],dut.external_interface_inst.config_regfile_inst.config_bits[i]);
            process_error();
            regfile_errors++;
        end

    end

        assert (regfile_errors == 0) $display("Shadow identical to regfile");
        else    $error("verify_shadow_regfile test failed");
endtask
  //================================================================
  //  Helper – packet builders (data, cfg‑write, cfg‑read)
  //================================================================
function automatic logic [WIDTH-1:0] build_data_pkt(
    input logic [7:0] chip_id,
    input logic [5:0] chan_id,
    input logic [27:0] ts,
    input logic reset_sample,
    input logic cds,
    input logic [9:0]  adc,
    input logic [1:0] trig = 2'b00);
    logic [WIDTH-1:0] pkt;
    pkt = '0;
    pkt[1:0]   = 2'b01;                 // data packet
    pkt[9:2]   = chip_id;
    pkt[15:10] = chan_id;
    pkt[43:16] = ts;
    pkt[44]    = reset_sample;
    pkt[45]    = cds;
    pkt[55:46] = adc;
    pkt[57:56] = trig;
    pkt[61:58] = 4'b0000;
    pkt[62]    = 1'b1;      // all data packets are downstream
    pkt[63]    = ~^pkt[62:0];           // odd parity
    return pkt;
endfunction

  function automatic logic [WIDTH-1:0] build_cfg_write(
    input logic [7:0] chip_id,
    input logic [7:0] reg_addr,
    input logic [7:0] reg_data);
    logic [WIDTH-1:0] pkt;
    pkt = '0;
    pkt[1:0]   = 2'b10;                 // CONFIG_WRITE
    pkt[9:2]   = chip_id;
    pkt[17:10] = reg_addr;
    pkt[25:18] = reg_data;
    pkt[57:26] = MAGIC_NUMBER;          // magic number
    pkt[62]    = 1'b0;                  // always upstream
    pkt[63]    = ~^pkt[62:0];
    return pkt;
  endfunction

  function automatic logic [WIDTH-1:0] build_cfg_read(
    input logic [7:0] chip_id,
    input logic [7:0] reg_addr,
    input bit downstream = 0);  // most config reads are upstream
    logic [WIDTH-1:0] pkt;
    pkt = '0;
    pkt[1:0]   = 2'b11;                 // CONFIG_READ
    pkt[9:2]   = chip_id;
    pkt[17:10] = reg_addr;
    pkt[57:26] = MAGIC_NUMBER;
    pkt[62]    = downstream;                  // read request upsteam (reply is ds)
    pkt[63]    = ~^pkt[62:0];
    return pkt;
  endfunction




//  UART‑RX driver – delivers a packet to one of the parallel RX ports
task automatic drive_rx_uart (int which_uart, logic [WIDTH-1:0] pkt);
    // idle -->  start -->  payload-->  stop --> back to idle
    repeat (IDLE_CYCLES) @(negedge clk) posi[which_uart] = 1'b1;   // idle high

    // start bit (0)
    @(negedge clk) posi[which_uart] = 1'b0;

    // payload (LSB first)
    for (int i=0; i<WIDTH; i++) begin
      @(negedge clk) posi[which_uart] = pkt[i];
    end

    // stop bit (1) and return to idle
    @(negedge clk) posi[which_uart] = 1'b1;
    @(posedge clk);
    posi[which_uart] = 1'b1;
endtask 

 //  UART‑RX driver – delivers a packet to one of the parallel RX ports
  task automatic drive_rx_uart_all (logic[NUM_UARTS-1:0] posi_mask, logic [WIDTH-1:0] pkt);
  logic [NUM_UARTS-1:0] selected_posi;
    selected_posi = enable_posi & posi_mask;  
    // idle -->  start -->  payload-->  stop --> back to idle
    repeat (IDLE_CYCLES) 
    for (int i = 0; i < NUM_UARTS; i++) begin
    fork
        automatic int which_uart = i;
        if (selected_posi[which_uart]) begin
            @(negedge clk) posi[which_uart] = 1'b1;   // idle high

        // start bit (0)
            @(negedge clk) posi[which_uart] = 1'b0;

        // payload (LSB first)
            for (int i=0; i<WIDTH; i++) begin
                @(negedge clk) posi[which_uart] = pkt[i];
                if (verbose) $display("%0t putting %b on posi[%0d]",$time/1e6,pkt[i],which_uart);
            end

        // stop bit (1) and return to idle
            @(negedge clk) posi[which_uart] = 1'b1;
            @(posedge clk);
            posi[which_uart] = 1'b1;
            // setting posi to 1
            if (verbose) $display("%t setting posi to 1",$time/1e6);
        end // if
    join_none
    end // for loop
  endtask 

  //================================================================
  //  Analog channel stub – generate a hit and present an ADC result
  //================================================================
  task automatic fire_analog (int chan, logic [ADCBITS-1:0] value);
    // raise hit for one clock
    hit[chan] = 1'b1;
    @(posedge clk);
    hit[chan] = 1'b0;

    // start conversion → done low for 4 cycles
    @(posedge clk);
    done[chan] = 1'b0;
    repeat (4) @(posedge clk);
    dout[chan*ADCBITS +: ADCBITS] = value;
    done[chan] = 1'b1;
  endtask
/*
  //  Capture UART‑RX output (the deserialized packets)
  always @(posedge clk) begin

    uld_rx_data_uart <= '0;
    for (int i=0; i<NUM_UARTS; i++) begin
        rx_empty_tb_last[i] <= rx_empty_tb[i];
        if (!rx_empty_tb[i] & rx_empty_tb_last[i]) begin
            uld_rx_data_uart[i] <= 1'b1;               // read the packet
            sb.capture(i,rx_data_tb[i]);
        end
    end
  end
*/
  //  Helper – push all expected copies of a packet (up‑ or down‑stream)
task automatic push_expected (logic [WIDTH-1:0] pkt);
    bit is_downstream = pkt[62];
    for (int i=0; i<NUM_UARTS; i++) begin
     
        if (enable_piso_upstream[i] & !is_downstream)
            sb.push_exp(i,pkt);
        if (enable_piso_downstream[i] & is_downstream)
            sb.push_exp(i,pkt);
    end
endtask

// Wait for N clock cycles
task automatic wait_clocks (input int n);
    repeat (n) @(posedge clk);
endtask

task apply_reset(input int reset_length);
    reset_n = 1'b0;
    #500 reset_n = 1'b0;
    wait_clocks(reset_length);
    #2000 reset_n = 1'b1;
endtask


  //================================================================
  //  Assertions (sanity checks)
  //================================================================
  // hydra_ctrl token_onehot must stay one‑hot
  property p_token_onehot;
    @(posedge clk) disable iff (!reset_n)
      ($countones(dut.external_interface_inst.hydra_ctrl_inst.token_onehot) == 1);
  endproperty
  assert property (p_token_onehot) else
    $error("%0t: hydra_ctrl token_onehot not one‑hot", $time);

  // ld_tx_data_uart must be a one‑cycle pulse
  property p_ld_one_cycle;
    @(posedge clk) disable iff (!reset_n)
      (|dut.external_interface_inst.hydra_ctrl_inst.ld_tx_data_uart) |-> ##1
      ((|dut.external_interface_inst.hydra_ctrl_inst.ld_tx_data_uart) == 0);
  endproperty
  assert property (p_ld_one_cycle) else
    $error("%0t: ld_tx_data_uart held >1 cycle", $time);


/*
task automatic verify_config_defaults;
logic [7:0] default_regfile [REGNUM];
bit input load_config_defaults;
repeat (5) @(posedge clk);


`include "shadow_regfile_assign.sv"
    int regfile_errors;
    regfile_errors = 0;
    for (int i = 0; i < REGNUM; i++) begin
        assert (default_regfile[i] == dut.external_interface_inst.
                               config_regfile_inst.config_bits[i]) 
        else begin $error("%0t: default incorrect at reg %0h: TB=%0h DUT=%0h",
                    $time, i, default_regfile[i],
                    dut.external_interface_inst.config_regfile_inst.config_bits[i]);
            process_error();
            regfile_errors++;
        end

    end
        assert (regfile_errors == 0) $display("LArPix regfile is in default setting");
        else    $error("verify_config_defaults test failed");
endtask
*/


  //    High‑level config‑write / config‑read tasks
  // packet builders (reuse the helpers already in the TB)
function automatic logic [WIDTH-1:0] mk_cfg_write (
    input logic [7:0] chip_id,
    input logic [7:0] addr,
    input logic [7:0] data);
    return build_cfg_write(chip_id,addr,data);
endfunction

function automatic logic [WIDTH-1:0] mk_cfg_read  (
    logic [7:0] chip_id,
    logic [7:0] addr,
    bit downstream=0);
    return build_cfg_read(chip_id,addr,downstream);
endfunction

//  CONFIG_WRITE – send the packet and update shadow after it
task automatic cfg_write (int which_uart,logic [7:0] chip_id, logic [7:0] addr, logic [7:0] data);
    logic [WIDTH-1:0] pkt;
    pkt = mk_cfg_write(chip_id, addr, data);
    drive_rx_uart(which_uart, pkt);

    // the register write takes a few cycles inside comms_ctrl
    repeat (3) @(posedge clk);
    shadow_regfile[addr] = dut.external_interface_inst.
                           config_regfile_inst.config_bits[addr];

    // sanity‑check that the shadow really matches
    if (shadow_regfile[addr] !== dut.external_interface_inst.
                               config_regfile_inst.config_bits[addr]) begin
      $error("%0t: SHADOW mismatch after write reg %0h – TB=%0h DUT=%0h",
             $time, addr, shadow_regfile[addr],
             dut.external_interface_inst.
                 config_regfile_inst.config_bits[addr]);
      process_error();
    end
endtask

//  CONFIG_READ – send the packet; reply will be captured by the
//                normal UART‑RX capture logic (downstream packet)
task automatic cfg_read (int which_uart, logic[7:0] chip_id, logic [7:0] addr);
    logic [WIDTH-1:0] pkt;
    pkt = mk_cfg_read(chip_id,addr);
    drive_rx_uart(which_uart, pkt);
    // give the DUT time to answer (the scoreboard will later compare)
    repeat (20) @(posedge clk);
endtask

always_comb begin
    rcvd_packet_declare         = receivedData[1:0];
    rcvd_chip_id                = receivedData[9:2];
    rcvd_channel_id             = receivedData[15:10];
    rcvd_time_stamp             = receivedData[43:16];
    rcvd_local_fifo_cnt         = receivedData[31:28];
    rcvd_reset_sample_flag      = receivedData[44];
    rcvd_cds_flag               = receivedData[45];
    rcvd_fifo_cnt               = receivedData[43:32];
    rcvd_data_word              = receivedData[55:46];
    rcvd_trigger_type           = receivedData[57:56];
    rcvd_fifo_half_bit          = receivedData[58];
    rcvd_fifo_full_bit          = receivedData[59];
    rcvd_local_fifo_half_bit    = receivedData[60];
    rcvd_local_fifo_full_bit    = receivedData[61];
    rcvd_tally                  = receivedData[61:60];
    rcvd_downstream_marker_bit  = receivedData[62];
    rcvd_parity_bit             = receivedData[63];
    rcvd_regmap_addr            = receivedData[17:10];
    rcvd_regmap_data            = receivedData[25:18];
    rcvd_magic_number           = receivedData[57:26];
    expected_parity_bit = ~^receivedData[62:0];
end



 //  Test 1 – Simple Config read/write 
 task automatic t_simple_config_rd_wr;
    string test_name = "t_simple_config_rd_wr";
// event variables
logic [7:0] chip_id;
logic [5:0] chan_id;
logic [27:0] ts;
logic reset_sample;
logic  cds;
logic [9:0]  adc;
logic [WIDTH-1:0] pkt;

enable_posi = 4'b0001;
enable_piso_upstream = 4'b0010;
enable_piso_downstream = 4'b0001;
    begin
        $display("%0t: Test %s",$time/1e6,test_name);
        chip_id = 8'd15;
        chan_id = 6'd32;
        ts = 28'd450321;
        reset_sample = 1'd0;
        cds = 1'b0;
        adc = 10'd299;

// configure_chip 

$display("Turn off unused POSIs");
cfg_write(.which_uart(0),.chip_id(dut.chip_id),.addr(ENABLE_POSI),.data(8'h01));
wait_clocks(20);
 

$display("Enable Downstream PISO0 (for returning data to FPGA)");
cfg_write(.which_uart(0),.chip_id(dut.chip_id),.addr(ENABLE_PISO_DOWN),.data(8'h01));
wait_clocks(20);
$display("Enable upstream PISO1 (for testing pass along)");  
cfg_write(.which_uart(0),.chip_id(dut.chip_id),.addr(ENABLE_PISO_UP),.data(8'h02));
wait_clocks(20);

$display("pass along test (config read for chip 2!)");
pkt = mk_cfg_read(.chip_id(2),.addr(GLOBAL_THRESH));
cfg_write(.which_uart(0),.chip_id(8'h02),.addr(GLOBAL_THRESH),.data(8'h01));
push_expected(pkt);
wait_clocks(20);

$display("Read Back test: 255d/0xFF expected");
pkt = mk_cfg_read(.chip_id(dut.chip_id),.addr(CSA_ENABLE));
cfg_read(.which_uart(0),.chip_id(dut.chip_id),.addr(CSA_ENABLE));
      $display("%0t: Test %s", $time/1e6,test_name);
      push_expected(pkt);

$display("\nnow send a data packet");    
     pkt = build_data_pkt(
               .chip_id     (chip_id),            // different from local chip
               .chan_id     (chan_id),
               .ts          (ts),
               .reset_sample(reset_sample),
               .cds         (cds),
               .adc         (adc));
   // $display("pkt sent to push mkt is %h",pkt);

      push_expected(pkt);

      drive_rx_uart(0,pkt);                // inject on UART0 only
      wait_clocks(1000);
      sb.compare();
      if (sb.total_errors()!=0) begin
        $error("%0t: %s FAILED",$time/1e6,test_name);
        process_error();
      end else
        $display("%0t: %s PASSED",$time/1e6,test_name);
    end
  endtask



  //================================================================
  //  Test 1 – single analog hit → downstream data packet
  //================================================================
task automatic t_analog_event;
    string test_name = "t_analog";
    int    chan = 5;                     // any enabled channel
    logic [ADCBITS-1:0] adc = 10'd210;
    logic [WIDTH-1:0]   pkt;
    begin
      $display("%0t: TEST %s", $time,test_name);
      // enable all upstream UARTs, disable downstream UARTs
      //dut.external_interface_inst.enable_piso_upstream   = 4'b1111;
      //dut.external_interface_inst.enable_piso_downstream = 4'b0000;
      //dut.external_interface_inst.enable_posi           = 4'b1111;

      // expected packet (downstream flag = 0 for an internal event)
      pkt = build_data_pkt(
               .chip_id        (dut.chip_id),       // local chip id
               .chan_id       (chan[5:0]),
               .ts          (28'd0),              // timestamp ignored here
               .reset_sample(1'b0),
               .cds         (1'b0),
               .adc         (adc));

      // one expected copy per enabled upstream UART
      for (int i=0; i<NUM_UARTS; i++) 
        push_expected(pkt);

      // fire the analog hit
      fire_analog(chan, adc);
      // give the FSM time to generate the packet and send it out
      repeat (30) @(posedge clk);

      sb.compare();
      if (sb.total_errors()!=0) begin
        $error("%0t: %s FAILED",$time/1e6,test_name);
        process_error();
      end else
        $display("%0t: %s  PASSED",$time/1e6,test_name);
    end

endtask


  //  Test 2 – concurrent RX on all UARTs (up‑stream packets)
task automatic t_rx_concurrent;
string test_name = "t_rx_concurrent";
logic [WIDTH-1:0] pkt;
begin
    $display("%0t: TEST %s", $time/1e6,test_name);
      //dut.external_interface_inst.enable_posi           = 4'b1111;
      //dut.external_interface_inst.enable_piso_upstream = 4'b1111;
      //dut.external_interface_inst.enable_piso_downstream = 4'b0000;

      pkt = build_data_pkt(
               .chip_id     (8'hAA),            // different chip ⇒ pass‑along
               .chan_id     (6'd1),
               .ts          (28'd0),
               .reset_sample(1'b0),
               .cds         (1'b0),
               .adc         (10'd321));

      // each upstream UART should emit a copy
      for (int i=0; i<NUM_UARTS; i++) push_expected(pkt);

      // drive the same packet into *all* UARTs in the same cycle
        for (int i=0; i<NUM_UARTS; i++) drive_rx_uart(i,pkt);

      repeat (30) @(posedge clk);
      sb.compare();
      if (sb.total_errors()!=0) begin
        $error("%0t: %s FAILED",$time/1e6,test_name);
        process_error();
      end else begin
        $display("%0t: %s  PASSED",$time/1e6,test_name);
      end
end
endtask

  //================================================================
  //  Test 3 – upstream pass‑through (packet addressed to another chip)
  //================================================================
task automatic t_pass_through_upstream;
string test_name = "t_pass_through_upstream";

logic [WIDTH-1:0] pkt;
begin
      $display("%0t: TEST %s", $time, test_name);
      //dut.external_interface_inst.enable_posi           = 4'b0001; // only UART0 receives
      //dut.external_interface_inst.enable_piso_upstream = 4'b0011; // UART0 & UART1 transmit
      //dut.external_interface_inst.enable_piso_downstream = 4'b0000;

      pkt = build_data_pkt(
               .chip_id    (8'h55),            // different from local chip
               .chan_id    (6'd2),
               .ts         (28'd0),
               .reset_sample (1'b0),
               .cds        (1'b0),
               .adc        (10'd777));

      // expected on two upstream UARTs
      push_expected(pkt);

      drive_rx_uart(0,pkt);                // inject on UART0 only
      repeat (30) @(posedge clk);
      sb.compare();
      if (sb.total_errors()!=0) begin
        $error("%0t: %s FAILED",$time/1e6,test_name);
        process_error();
      end else begin
        $display("%0t: %s  PASSED",$time/1e6,test_name);
      end
end

endtask

/*
  //================================================================
  //  Test 4 – simultaneous CONFIG_READ and EVENT packet
  //================================================================
  task automatic test_cfg_event_simultaneous;
    logic [WIDTH-1:0] cfg_pkt, evt_pkt;
    begin
      $display("%0t: TEST 4 – cfg‑read & event together", $time);
      // use UART0 only for both directions
      //dut.external_interface_inst.enable_posi           = 4'b0001;
      //dut.external_interface_inst.enable_piso_upstream = 4'b0001;
      //dut.external_interface_inst.enable_piso_downstream = 4'b0001;

      cfg_pkt = build_cfg_read(
                  .chip_id_fld (dut.chip_id),
                  .chan_id    (6'd0),
                  .reg_addr   (8'h20) );

      evt_pkt = build_data_pkt(
                  .chip_id_fld (dut.chip_id),
                  .chan_id    (6'd0),
                  .stamp      (28'd400),
                  .reset_smpl (1'b0),
                  .cds        (1'b0),
                  .adc        (10'd250),
                  .trig       (2'b00),
                  .seq        (4'd0));

      // both packets will be sent downstream on UART0
      sb.push_exp(0,1'b1,cfg_pkt);
      sb.push_exp(0,1'b1,evt_pkt);

      // drive the two packets into the same RX port (they will be buffered)
      fork
        drive_rx_uart(0,cfg_pkt);
        drive_rx_uart(1,evt_pkt);
      join

      repeat (50) @(posedge clk);
      sb.compare();
      if (sb.total_errors()!=0) begin
        $error("%0t: CFG/EVENT SIMULTANEOUS TEST FAILED", $time);
        process_error();
      end else
        $display("%0t: CFG/EVENT SIMULTANEOUS TEST PASSED", $time);

      // sanity‑check the whole reg‑file after the read
      verify_shadow_regfile();
    end
  endtask


  //================================================================
  //  Test 5 – token rotation sanity check (4‑UART round‑robin)
  //================================================================
  task automatic test_token_rotation;
    logic [WIDTH-1:0] pkt;
    begin
      $display("%0t: TEST 5 – token rotation", $time);
      // enable only UART0 so we can watch the token advance
      //dut.external_interface_inst.enable_posi           = 4'b0001;
      //dut.external_interface_inst.enable_piso_upstream = 4'b0001;
      //dut.external_interface_inst.enable_piso_downstream = 4'b0001;

      // send eight pass‑along packets (different chip ⇒ pass‑through)
      for (int i=0; i<8; i++) begin
        pkt = build_data_pkt(
                .chip_id_fld (8'hFF),            // different chip
                .chan_id    (6'd0),
                .stamp      (28'd500+i),
                .reset_smpl (1'b0),
                .cds        (1'b0),
                .adc        (10'd0),
                .trig       (2'b00),
                .seq        (4'd0));

        drive_rx_uart(0,pkt);
        repeat (4) @(posedge clk);
      end

      // after eight passes the token should be back to its initial state
      if (dut.external_interface_inst.hydra_ctrl_inst.token !== 2'b00) begin
        $error("%0t: token did not wrap to 00 after 8 passes (got %b)",
               $time, dut.external_interface_inst.hydra_ctrl_inst.token);
        process_error();
      end else
        $display("%0t: TOKEN ROTATION PASSED", $time);
    end
  endtask

*/
  //================================================================
  //  Error handling
  //================================================================
  int  errors = 0;
  bit test_failed = 1'b0;

  task automatic process_error;
    errors++;
    test_failed = 1'b1;
  endtask


always @(negedge |uld_rx_data_uart) begin
    #10
//    if (packetNumber != 0) begin
        $display("\n--------------------");
        $display("\nData Received: %h",receivedData);
        $display("Packet Number: %0d",packetNumber);
        $display("Parity Bit = %0d",rcvd_parity_bit);
        $display("Expected Parity Bit = %0d",expected_parity_bit);
        if (expected_parity_bit != rcvd_parity_bit) 
            $display("ERROR: PARITY BAD");
        else 
            $display("Parity good.");
//    end
    case(rcvd_packet_declare)
        0 : begin
             //   if (packetNumber != 0) begin
                    $display("ERROR: BAD PACKET. 2'b00 INVALID DECLARATION");
             //   end
             end
        1 : begin
                $display("data packet");
                $display("Chip ID = %d",rcvd_chip_id);
                $display("Channel ID = %d",rcvd_channel_id);
                $display("time stamp (hex) = %h",rcvd_time_stamp);
                $display("local fifo counter (if configured) = %d",rcvd_local_fifo_cnt);
                $display("fifo counter (if configured) = %d",rcvd_fifo_cnt);
                $display("reset_sample_flag = %d",rcvd_reset_sample_flag);
                $display("cds_mode_flag = %d",rcvd_cds_flag);
                $display("data word = %d",rcvd_data_word);
                case(rcvd_trigger_type) 
                    2'b00 : $display("trigger_type = NATURAL");
                    2'b01 : $display("trigger_type = EXTERNAL");
                    2'b10 : $display("trigger_type = CROSS");
                    2'b11 : $display("trigger_type = PERIODIC");
                endcase 
                $display("packet tally (if configured) = %d",rcvd_tally);
                $display("downstream marker bit = %d",rcvd_downstream_marker_bit);
           end
        2 : begin
                $display("configuration write");
                $display("Chip ID = %d",rcvd_chip_id);
                $display("register map address = %d",rcvd_regmap_addr);
                $display("register map data = %d",rcvd_regmap_data);
                $display("fifo half bit = %d",rcvd_fifo_half_bit);
                $display("fifo full bit = %d",rcvd_fifo_full_bit);
                $display("local fifo half bit = %d",rcvd_local_fifo_half_bit);
                $display("local fifo full bit = %d",rcvd_local_fifo_full_bit);
                $display("magic number = %h",rcvd_magic_number);
                $display("marker bit = %d",rcvd_downstream_marker_bit);
            end
        3 : begin
                $display("configuration read");
                $display("Chip ID = %d",rcvd_chip_id);
                $display("register map address = %d",rcvd_regmap_addr);
                $display("register map data = %d",rcvd_regmap_data);
                $display("fifo half bit = %d",rcvd_fifo_half_bit);
                $display("fifo full bit = %d",rcvd_fifo_full_bit);
                $display("local fifo half bit = %d",rcvd_local_fifo_half_bit);
                $display("local fifo full bit = %d",rcvd_local_fifo_full_bit);
                $display("magic number = %h",rcvd_magic_number);
                $display("marker bit = %d",rcvd_downstream_marker_bit);
            end
    endcase
    $display("\n--------------------\n");
end // always



  //================================================================
  //  Main stimulus – run all tests sequentially
  //================================================================
  initial begin
    verbose = 1;
    posi = 4'b1111;
    done = 0;
    hit = 0;
    dout = 10'h000;
    external_trigger = 0;
    packetNumber = 0;
    receivedData = 0;
    
    // wait for reset de‑assertion and a few idle clocks
    @(negedge reset_n);
    @(posedge reset_n);
    repeat (10) @(posedge clk);

    // *** NEW *** initialise the TB shadow register file
    init_shadow_regfile();
    verify_shadow_regfile();
    t_simple_config_rd_wr();
//      t_normal_event_packet_passthrough; sb.reset();
//    test_analog_event();               sb.reset();
//    t_rx_concurrent();              sb.reset();
//   t_pass_through_upstream();      sb.reset();
//    test_cfg_event_simultaneous();     sb.reset();
//    test_token_rotation();             sb.reset();

    if (errors == 0)
      $display("\n*** ALL DIGITAL_CORE TESTS PASSED ***\n");
    else
      $display("\n*** DIGITAL_CORE TEST FAILED -- %0d error(s) ***\n", errors);
 //   $finish;
  end


  //================================================================
  //  Clock & reset generation
  //================================================================
  initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD/2) clk = ~clk;   // free‑running clock
  end

  // reset is asserted for ~2.5 µs after time‑0
initial begin
    apply_reset(40);
end

endmodule : digital_core_tb
