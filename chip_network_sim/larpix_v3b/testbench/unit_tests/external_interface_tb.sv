`timescale 1ns / 10ps
module external_interface_tb;

  //  Parameters
localparam int WIDTH       = 64;
localparam int NUM_UARTS   = 4;
localparam int REGNUM    = 256;
localparam int IDLE_CYCLES = 2;   // UART‑idle cycles before a word
localparam int MAX_JITTER  = 0;   // not used in this TB
localparam int GLOBAL_ID   = 255;
localparam int TESTPULSE_DAC_BITS = 8;  //  Clock & reset
localparam int ADCBITS     = 10;  
localparam real CLK_PERIOD = 200.0;     // 5 MHz → 200 ns period
localparam int FIFO_DEPTH = 16;    // # of bits to describe fifo addr range
localparam FIFO_BITS = $clog2(FIFO_DEPTH);//bits in fifo addr range
logic clk;
logic reset_n_sync;
logic reset_n_config_sync;
bit verbose;
int pkt_cnt;
  // helpers
// constants (e.g. register definitions)
`include "larpix_constants.sv"

initial begin
    pkt_cnt = 0;
    reset_n_sync = 1'b1;
    reset_n_config_sync = 1'b1;
    apply_reset(40);
end
// reset
task apply_reset(input int reset_length = 10);
    reset_n_sync = 1'b0;
    reset_n_config_sync = 1'b0;
//    #500 reset_n_sync = 1'b0;
//    #500 reset_n_config_sync = 1'b0;
    wait_clocks(reset_length);
    #2000 reset_n_sync = 1'b1;
    wait_clocks(reset_length);
    reset_n_config_sync = 1'b1;
    wait_clocks(reset_length);
endtask

  //  DUT interface
// Outputs from DUT
logic [WIDTH-1:0]            tx_data_uart [NUM_UARTS];
logic [NUM_UARTS-1:0]        tx_enable;
logic [NUM_UARTS-1:0]        uld_rx_data_uart;

// Inputs to DUT
logic [NUM_UARTS-1:0]        enable_posi;
logic [NUM_UARTS-1:0]        enable_piso_upstream;
logic [NUM_UARTS-1:0]        enable_piso_downstream;
logic                        enable_fifo_diagnostics;
logic [WIDTH-1:0]            event_data;
logic                        event_valid;
logic [7:0]                  chip_id;
logic [7:0] config_bits [REGNUM];// regmap config bit outputs
logic [NUM_UARTS-1:0] posi;             // parallel UART‑RX lines
logic [NUM_UARTS-1:0] piso;             // serial TX (parallel)
logic load_config_defaults;// reset
logic [NUM_UARTS-1:0] rx_empty_tb_last; // used for edge detection
  //  Default stimulus values
initial begin
    chip_id                 = 8'h55;                // local chip id
    enable_posi             = 4'b0001;
    enable_piso_upstream    = 4'b0000;
    enable_piso_downstream  = 4'b0001;
    enable_fifo_diagnostics = 1'b0;
    event_data              = '0;
    event_valid             = 1'b0;
    load_config_defaults    = 1'b0;
    posi                    = 4'b1111;
end

external_interface
    #(.WIDTH(WIDTH),
    .FIFO_DEPTH(FIFO_DEPTH),
    .GLOBAL_ID(255),
    .REGNUM(REGNUM),
    .FIFO_BITS(FIFO_BITS)
    ) dut (
    .tx_out                     (piso),
    .config_bits                (config_bits),
    .tx_enable                  (tx_enable),
    .ready_for_event            (ready_for_event),
    .event_data                 (event_data),
    .event_valid                (event_valid),
    .chip_id                    (chip_id),
    .load_config_defaults       (load_config_defaults),
    .enable_piso_upstream       (enable_piso_upstream),
    .enable_piso_downstream     (enable_piso_downstream),
    .enable_posi                (enable_posi),
    .rx_in                      (posi),
    .enable_fifo_diagnostics    (enable_fifo_diagnostics),
    .clk                        (clk),
    .reset_n_clk                (reset_n_sync),
    .reset_n_config             (reset_n_config_sync)
    );

  //================================================================
  //  UART‑RX models – deserialize the TX streams on the `piso` bus
  //================================================================
  logic [WIDTH-1:0]   rx_data_tb      [NUM_UARTS];
  logic               rx_empty_tb     [NUM_UARTS];

genvar i;
    for (i=0; i<NUM_UARTS; i++) begin : gen_uart_rx
      uart_rx #(.WIDTH(WIDTH)) urx (
        .rx_data    (rx_data_tb[i]),
        .rx_empty   (rx_empty_tb[i]),
        .rx_in      (piso[i]),          // serial line from the DUT
        .uld_rx_data(uld_rx_data_uart[i]),
        .clk        (clk),
        .reset_n    (reset_n_sync)
      );
    end

// define the data structure
  typedef struct packed {
    int   which_piso;         // UART index that will transmit it
    logic [WIDTH-1:0]   packet;            // full 64‑bit packet
  } pkt_t;

//  Scoreboard – queues of structs
class scoreboard #(int WIDTH = 64, int NUM_UARTS = 4);

  //  Packet description used by the scoreboard
  //  Queues – dynamic arrays used as FIFO‑like queues
pkt_t   expected_queue[$];   // packets we *expect* the DUT to emit
pkt_t   received_queue[$];   // packets we actually captured from the DUT
int err_cnt = 0;         // error counter

  //  Constructor – nothing special
function new(); endfunction

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

  //  compare – match every expected entry with *any* received entry
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
                $time/1e6, rcv_entry.which_piso, rcv_entry.packet);
                err_cnt++;
        end
    end
endtask

  //  reset -- clear both queues and the error counter
function void reset ();
    expected_queue.delete();
    received_queue.delete();
    err_cnt = 0;
endfunction

function int total_errors (); return err_cnt; endfunction
endclass

// instantiate scoreboard
scoreboard sb = new();

//  Assertions (sanity checks)
// hydra_ctrl token_onehot must stay one‑hot
property p_token_onehot;
  @(posedge clk) disable iff (!reset_n_sync)
    ($countones(dut.hydra_ctrl_inst.token_onehot) == 1);
endproperty
assert property (p_token_onehot) else
  $error("%0t: hydra_ctrl token_onehot not one-hot", $time/1e6);

// ld_tx_data_uart must be a one‑cycle pulse
property p_ld_one_cycle;
    @(posedge clk) disable iff (!reset_n_sync)
    (|dut.hydra_ctrl_inst.ld_tx_data_uart) |-> ##1
    ((|dut.hydra_ctrl_inst.ld_tx_data_uart) == 0);
endproperty

assert property (p_ld_one_cycle) else
    $error("%0t: ld_tx_data_uart held >1 cycle", $time/1e6);

//    Shadow register file (TB copy of config bits)
logic [7:0] shadow_regfile [REGNUM];   // TB's view of the config registers

// initialise the shadow after reset (defaults are loaded inside the DUT)
task automatic init_shadow_regfile;
    repeat (5) @(posedge clk);

    `include "shadow_regfile_assign.sv"
    $display("%0t: Shadow register file initialized (size %0d)", $time/1e6, REGNUM);
endtask

//  Helper tasks
// Wait for N clock cycles
task automatic wait_clocks (input int n);
    repeat (n) @(posedge clk);
endtask




  //  Error handling
int  errors = 0;
bit  test_failed = 1'b0;

task automatic process_error;
    errors++;
    test_failed = 1'b1;
endtask

  //  Packet builders
function automatic pkt_t build_data_pkt(
    input logic [7:0] chip_id,
    input logic [5:0] chan_id,
    input logic [27:0] ts,
    input logic reset_sample,
    input logic  cds,
    input logic [9:0]  adc);
    pkt_t pkt;
    pkt = '0;
    pkt[1:0]   = 2'b01;
    pkt[9:2]   = chip_id;
    pkt[15:10] = chan_id;
    pkt[43:16] = ts;
    pkt[44]    = reset_sample;
    pkt[45]    = cds;
    pkt[55:46] = adc;
    pkt[62]    = 1'b1;      //data packets always downstream
    pkt[63]    = ~^pkt[62:0];
    //$display("m: pkt (object) = %p, pkt = %h",pkt,pkt);
    return pkt;
endfunction

function automatic pkt_t build_cfg_write(
    input logic [7:0] chip_id,
    input logic [7:0] reg_addr,
    input logic [7:0] reg_data);
    pkt_t pkt;
    pkt = '0;
    pkt[1:0]   = 2'b10;
    pkt[9:2]   = chip_id;
    pkt[17:10] = reg_addr;
    pkt[25:18] = reg_data;
    pkt[57:26] = MAGIC_NUMBER;
    pkt[62]    = 1'b0;  // config writes always upstream
    pkt[63]    = ~^pkt[62:0];
    return pkt;
endfunction

function automatic pkt_t build_cfg_read(
    input logic [7:0] chip_id,
    input logic [7:0] reg_addr,
    input bit   downstream = 0);  // cfg_reads are upstream, except for return data
    pkt_t pkt;
    pkt = '0;
    pkt[1:0]   = 2'b11;
    pkt[9:2]   = chip_id;
    pkt[17:10] = reg_addr;
    pkt[57:26] = MAGIC_NUMBER;
    pkt[62]    = downstream;  
    pkt[63]    = ~^pkt[62:0];
    return pkt;
endfunction


task automatic verify_shadow_regfile;
    int regfile_errors;
    regfile_errors = 0;
    for (int i = 0; i < REGNUM; i++) begin
        assert (shadow_regfile[i] == dut.config_regfile_inst.config_bits[i]) 
        else begin $error("%0t: Shadow mismatch at reg %0h: TB=%0d DUT=%0d",
                    $time/1e6, i, shadow_regfile[i],dut.config_regfile_inst.config_bits[i]);
            process_error();
            regfile_errors++;
        end

    end
        assert (regfile_errors == 0) $display("Shadow identical to regfile");
        else    $error("verify_shadow_regfile test failed");
endtask



  // High‑level config‑write / config‑read tasks
  // packet builders (reuse the helpers already in the TB)
function automatic logic [WIDTH-1:0] mk_cfg_write (
    input logic [7:0] chip,
    input logic [7:0] addr,
    input logic [7:0] data);
    return build_cfg_write(chip,addr,data);
endfunction

function automatic pkt_t mk_cfg_read  (
    logic [7:0] chip,
    logic [7:0] addr,
    bit downstream = 0);
    return build_cfg_read(chip,addr,downstream);
endfunction

//  CONFIG_WRITE – send the packet and update shadow after it
task automatic cfg_write
    (int chip, 
    int which_uart,
    logic [7:0] addr, 
    logic [7:0] val);

    logic [WIDTH-1:0] pkt;
    pkt = mk_cfg_write(chip, addr, val);
    drive_rx_uart(which_uart, pkt);

    // the register write takes a few cycles inside comms_ctrl
    repeat (8) @(posedge clk);
    if (chip == dut.chip_id) begin // we expect the config registers to be updated
        shadow_regfile[addr] =val;

        // sanity‑check that the shadow really matches
        if (shadow_regfile[addr] !== dut.config_regfile_inst.config_bits[addr]) begin
            $error("%0t:shadow reg mismatch after write reg %0h -- TB=%0h DUT=%0h",
                $time/1e6, addr, shadow_regfile[addr],
                dut.config_regfile_inst.config_bits[addr]);
            process_error();
        end
    end
endtask



//  CONFIG_READ – send the packet; reply will be captured by the
//                normal UART‑RX capture logic (downstream packet)
task automatic cfg_read 
    (logic[1:0] which_uart,
    logic [7:0] chip,
    logic [7:0] addr,
    bit downstream = 0);  // default is upstream
    logic [WIDTH-1:0] pkt;
    pkt = mk_cfg_read(chip, addr,downstream);
    if (verbose) $display("%m: pkt = %h sent at t=%0t",pkt,$time/1e6);
    drive_rx_uart(which_uart, pkt);
    // give the DUT time to answer (the scoreboard will later compare)
    repeat (20) @(posedge clk);
endtask

 

  //  UART‑RX driver – delivers a packet to one of the parallel RX ports
  task automatic drive_rx_uart (logic [1:0] which_uart, logic [WIDTH-1:0] pkt);
    if (verbose) 
        $display("%m: which_uart = %0b, pkt = %h, at time = %0t",which_uart,pkt,$time/1e6);
    // idle -->  start -->  payload-->  stop --> back to idle
    repeat (IDLE_CYCLES) @(negedge clk) posi[which_uart] = 1'b1;   // idle high

    // start bit (0)
    @(negedge clk) posi[which_uart] = 1'b0;

    // payload (LSB first)
    for (int i=0; i<WIDTH; i++) begin
      @(negedge clk) posi[which_uart] = pkt[i];
      // if (verbose) $display("%0t putting %b on posi[%0d]",$time/1e6,pkt[i],i);
    end

    // stop bit (1) and return to idle
    @(negedge clk) posi[which_uart] = 1'b1;
    @(posedge clk);
    posi[which_uart] = 1'b1;
    // setting posi to 1
    //if (verbose) $display("%t setting posi to 1",$time/1e6);
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

  //  Helper – push all expected copies of a packet (up‑ or down‑stream)
  task automatic push_expected (pkt_t pkt);
    bit is_downstream = pkt.packet[62];
    logic [7:0] pkt_id = pkt.packet[9:2];
    logic [1:0] pkt_type = pkt.packet[1:0];
    if (verbose) $display ("%m: pkt = %h, pkt.packet = %h",pkt,pkt.packet);
    for (int i=0; i<NUM_UARTS; i++) begin
        if (verbose) $display("%m: is_downstream = %0b",is_downstream);
        if (enable_piso_upstream[i] & !is_downstream)
            // check to see if wrong chip or config_write OP
            if (pkt_id != dut.chip_id || pkt_type != CONFIG_WRITE_OP ) begin
                sb.push_exp(i,pkt);
        end
        if (enable_piso_downstream[i] & is_downstream) begin
            sb.push_exp(i,pkt);
        end
    end
  endtask

 //  Test 1 – normal event packet passthrough
 task automatic t_normal_event_packet_passthrough;
    string test_name = "t_normal_event_packet_passthrough";
    logic [WIDTH-1:0] pkt;
    begin
      $display("%0t: Test %s", $time/1e6,test_name);
    
    enable_posi = 4'b0001  ;
    enable_piso_downstream = 4'b0010;
    enable_piso_upstream = 4'b1000;
    pkt = build_data_pkt(
               .chip_id (8'h55),            // different from local chip
               .chan_id    (6'd2),
               .ts          (28'd432340),
               .reset_sample (1'b0),
               .cds        (1'b0),
               .adc        (10'd777));
   // $display("pkt sent to push mkt is %h",pkt);

      push_expected(pkt);

      drive_rx_uart(0,pkt);                // inject on UART0 only
      wait_clocks(100);
      sb.compare();
      if (sb.total_errors()!=0) begin
        $error("%0t: %s FAILED",$time/1e6,test_name);
        process_error();
      end else
        $display("%0t: %s  PASSED",$time/1e6,test_name);
    end
  endtask

  //  Test 2 -- upstream pass‑through (packet addressed to another chip)
task automatic t_pass_through_upstream;
    logic [7:0] chip;
    logic [1:0] which_uart;
    logic [7:0] addr;
    logic [7:0] val;
    string test_name = "t_pass_through_upstream";
    logic [WIDTH-1:0] pkt;
    begin
      $display("%0t: Test %s",$time/1e6,test_name);
    
    chip = 8'h02; which_uart = 2'b00; addr = 8'd23; val = 8'd77;
    enable_posi = 4'b0001;
    enable_piso_upstream = 4'b1000;
    cfg_write(
               .chip(chip),            // different from local chip
               .which_uart(which_uart),
               .addr(addr),
               .val(val));

      push_expected(mk_cfg_write(chip, addr, val));

  //    drive_rx_uart(0,pkt);                // inject on UART0 only
      wait_clocks(100);
      sb.compare();
      if (sb.total_errors()!=0) begin
        $error("%0t: %s FAILED", $time/1e6,test_name);
        process_error();
      end else
        $display("%0t: %s PASSED", $time/1e6,test_name);
    end
  endtask

task automatic t_pass_through_config_read();
begin
    logic [WIDTH-1:0] exp_pkt;
    logic [7:0] chip;
    logic [1:0] which_uart;
    logic [7:0] addr;
    logic [7:0] val;
    bit downstream;
    string test_name = "t_pass_through_config_read";
    $display("%0t: Test %s",$time/1e6,test_name);
    enable_posi = 4'b0001;
    enable_piso_upstream = 4'b1000;
    enable_piso_downstream = 4'b0001;
    chip = 8'd12;
    addr = 8'd25;
    downstream = 1'b1;

    cfg_read(  .which_uart(2'b00),
               .chip(8'd12),  // wrong local chip           
               .addr(8'd25),
               .downstream(downstream));  // this is returned from somewhere upstream
 

    exp_pkt = mk_cfg_read(chip, addr, downstream);
    if (verbose) $display("original pkt = %h",exp_pkt);
    push_expected(mk_cfg_read(chip,addr,downstream));
    wait_clocks(100);
    sb.compare();
    if (sb.total_errors()!=0) begin
        $error("%0t: %s FAILED", $time/1e6,test_name);
        process_error();
      end else
        $display("%0t: %s PASSED", $time/1e6,test_name);
    end
endtask
    


 //  Test 3 --  config write
task automatic t_config_write();

string test_name = "t_config_write";
pkt_t pkt;
begin
      $display("%0t: Test - %s",$time/1e6,test_name);
    
    enable_posi = 4'b0001;
    enable_piso_upstream = 4'b1000;
    cfg_write(
               .chip(dut.chip_id),  // send for local chip           
               .which_uart(1'b0),
               .addr(8'd25),
               .val(8'd123));

   //   push_expected(pkt);

//      drive_rx_uart(0,pkt);                // inject on UART0 only
      wait_clocks(100);
      // chip config map vs shadow map
      verify_shadow_regfile();
      sb.compare();
      if (sb.total_errors()!=0) begin
        $error("%0t: %s FAILED", $time/1e6,test_name);
        process_error();
      end else
        $display("%0t: %s PASSED", $time/1e6,test_name);
    end
  endtask

  //  Test 2 – concurrent RX on all UARTs
task automatic t_rx_concurrent();
pkt_t pkt;
int i;
    string test_name = "t_rx_concurrent";
begin
    $display("%0t: Test %s",$time/1e6,test_name);

    enable_posi            = 4'b1111;
    enable_piso_upstream   = 4'b0010;
    enable_piso_downstream = 4'b1001;
    

    wait_clocks(10);
    assert((enable_piso_upstream & enable_piso_downstream) == '0)
        else $error("%m: PISO can only be upstream or downstream, not both");


    pkt = build_data_pkt(
                .chip_id (6'd1),
                .chan_id    (6'd1),
                .ts      (28'd200),
                .reset_sample (1'b0),
                .cds        (1'b0),
                .adc        (10'd321));
    for (i=0;i<NUM_UARTS;i++) begin
        if (enable_posi[i]) begin
            if (verbose)
                $display("%m: time = %0t, push rx packet[%0d]\n",$time/1e6,i);           
            push_expected(pkt);
        end
    end
// create new process for launching data. Allow testbench to continue (outer
// fork/join). Inner fork_join allows each task to be launched at the same 
// simulation time. idx is a private variable that is independent for each process

    drive_rx_uart_all(enable_posi,pkt);


    repeat (1000) @(posedge clk);
      sb.compare();
    if (sb.total_errors()!=0) begin
        $error("%0t: %s FAILED", $time/1e6,test_name);
        process_error();
    end else
        $display("%0t: %s PASSED", $time/1e6,test_name);
  


end
endtask



  //  Test 5 -- token rotation sanity check

task automatic t_token_rotation();
pkt_t pkt;
string test_name = "t_token_rotation";

int i;
logic [3:0] token_start;
begin
    $display("%0t: Test %s", $time/1e6,test_name);
    // Use only UART0 so token progression is easy to follow
    enable_posi            = 4'b0001;
    enable_piso_upstream   = 4'b0010;
    enable_piso_downstream = 4'b0001;
    token_start = dut.hydra_ctrl_inst.token_onehot; // get a baseline
    for (i=0;i<8;i++) begin
        pkt = build_data_pkt(
                    .chip_id (8'hFF),          // different chip → pass‑along
                    .chan_id    (6'd0),
                    .ts      (28'd500+i),
                    .reset_sample (1'b0),
                    .cds        (1'b0),
                    .adc        (10'd0));
        drive_rx_uart(enable_posi,pkt);

        repeat (4) @(posedge clk);
    end
    @(posedge clk);
    assert (dut.hydra_ctrl_inst.token_onehot == token_start) 
      //  $display("token_expected = %b,\
      //  token_observed = %b",token_start, dut.hydra_ctrl_inst.token_onehot);
    else $error("%0t: token did not return to %b after 8 packets (got %b)", 
                $time/1e6, token_start, dut.hydra_ctrl_inst.token_onehot);
    if (sb.total_errors()!=0) begin
        $error("%0t: %s FAILED", $time/1e6,test_name);
        process_error();
    end else
        $display("%0t: %s PASSED", $time/1e6,test_name);
  

end
endtask


  //  Clock & reset generation
  initial begin
    clk = 1'b0;
    forever #100 clk = ~clk;   // free‑running clock (5 MHz)
  end


initial begin
    verbose = 1;
    reset_n_sync = 0;
   // initialize the TB shadow register file
    apply_reset(60);  
    init_shadow_regfile();
    verify_shadow_regfile();

    t_rx_concurrent();              sb.reset();
    t_normal_event_packet_passthrough;   sb.reset(); 
    t_pass_through_upstream();      sb.reset();
    t_config_write();     sb.reset();
    t_pass_through_config_read(); sb.reset();
    t_token_rotation();             sb.reset();

    if (errors == 0)
      $display("\n*** ALL EXTERNAL_INTERFACE TESTS PASSED ***  time=%0t\n",$time/1e6);
    else
      $display("\n*** EXTERNAL INTERFACE TESTS FAILED -- %0d error(s) ***\
            time=%0tus\n",errors, $time/1e6);
 //   $finish;
  end




endmodule : external_interface_tb
