`timescale 1ns / 10ps
module hydra_ctrl_tb;

  //  Parameters
parameter logic [31:0] MAGIC_NUMBER = 32'h89504E47; 
parameter int WIDTH       = 64;
parameter int NUM_UARTS   = 4;
parameter int IDLE_CYCLES = 2;   // UART‑idle cycles before a word
parameter int MAX_JITTER  = 0;   // not used in this TB
parameter int GLOBAL_ID   = 255;
  //  Clock & reset
logic clk;
logic reset_n;

  // helpers
int pkt_cnt;
bit verbose;
// define clock
initial begin
    clk = 0;
    forever #100 clk = ~clk;                     // 5 MHz
end

initial begin
    pkt_cnt = 0;
    reset_n = 1'b1;
    apply_reset();
end

task apply_reset();
    reset_n = 1'b1;
    #500 reset_n = 1'b0;
    #2000 reset_n = 1'b1;
endtask

  //  DUT interface
// Outputs from DUT
logic [WIDTH-1:0]            tx_data_uart [NUM_UARTS];
logic [NUM_UARTS-1:0]        ld_tx_data_uart;
logic [NUM_UARTS-1:0]        rx_enable;
logic [NUM_UARTS-1:0]        tx_enable;
logic                        rx_data_flag;
logic [WIDTH-1:0]            rx_data;
logic [NUM_UARTS-1:0]        uld_rx_data_uart;
logic                        ready_for_event;
logic                        ready_for_pkt;
logic [15:0]                 fifo_counter_out;

// Inputs to DUT
logic [NUM_UARTS-1:0]        rx_empty_uart;
logic [WIDTH-1:0]            rx_data_uart [NUM_UARTS];
logic [NUM_UARTS-1:0]        enable_posi;
logic [NUM_UARTS-1:0]        enable_piso_upstream;
logic [NUM_UARTS-1:0]        enable_piso_downstream;
logic                        enable_fifo_diagnostics;
logic [WIDTH-1:0]            event_data;
logic                        event_valid;
logic [WIDTH-1:0]            pkt_data;
logic                        pkt_valid;
logic [NUM_UARTS-1:0]        tx_busy;
logic [7:0]                  chip_id;

// for comms_ctrl
logic [7:0] regmap_write_data,regmap_address;
logic [7:0] regmap_read_data;
logic comms_busy, write_regmap, read_regmap;

  //  Default stimulus values
initial begin
    chip_id                 = 8'h55;                // local chip id
    enable_posi             = 4'b1;
    enable_piso_upstream    = 4'b0000;
    enable_piso_downstream  = 4'b0001;
    enable_fifo_diagnostics = 1'b0;
    event_data              = '0;
    event_valid             = 1'b0;
    tx_busy                 = 4'b0000;
    rx_empty_uart           = 4'hF;
    regmap_read_data        = '0;
    for (int i=0;i<NUM_UARTS;i++) rx_data_uart[i] = '0;
end



  //  DUT instantiation
hydra_ctrl #(
    .WIDTH      (WIDTH),
    .FIFO_DEPTH (16),
    .NUM_UARTS  (NUM_UARTS)
    ) dut (
    .tx_data_uart           (tx_data_uart),
    .uld_rx_data_uart       (uld_rx_data_uart),
    .ld_tx_data_uart        (ld_tx_data_uart),
    .rx_data_flag           (rx_data_flag),
    .rx_enable              (rx_enable),
    .tx_enable              (tx_enable),
    .ready_for_event        (ready_for_event),
    .ready_for_pkt          (ready_for_pkt),
    .fifo_counter_out       (fifo_counter_out),
    .rx_data                (rx_data),
    .rx_empty_uart          (rx_empty_uart),
    .rx_data_uart           (rx_data_uart),
    .enable_posi            (enable_posi),
    .enable_piso_upstream   (enable_piso_upstream),
    .enable_piso_downstream (enable_piso_downstream),       
    .enable_fifo_diagnostics(enable_fifo_diagnostics),
    .comms_busy             (comms_busy),
    .tx_busy                (tx_busy),
    .chip_id                (chip_id),
    .event_data             (event_data),
    .event_valid            (event_valid),
    .pkt_data               (pkt_data),
    .pkt_valid              (pkt_valid),
    .clk                    (clk),
    .reset_n                (reset_n));


// easier to just use comms_ctrl for interfacing than modeling it
comms_ctrl #(
    .WIDTH      (WIDTH),
    .GLOBAL_ID  (GLOBAL_ID)
    )
    comms_ctrl_inst (
    .pkt_data               (pkt_data),    
    .pkt_valid              (pkt_valid),
    .regmap_write_data      (regmap_write_data),
    .regmap_address         (regmap_address),
    .comms_busy             (comms_busy),
    .write_regmap           (write_regmap),
    .read_regmap            (read_regmap),
    .rx_data                (rx_data),
    .chip_id                (chip_id),
    .regmap_read_data       (regmap_read_data),
    .rx_data_flag           (rx_data_flag),
    .ready_for_pkt          (ready_for_pkt),
    .event_valid            (event_valid),
    .fifo_counter_out       (fifo_counter_out),
    .clk                    (clk),
    .reset_n                (reset_n));
   
   


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
            $error("%m: error. Receivied %0d pkts, expected %0d",
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

//  Push all expected copies of a packet (one per enabled PISO)
task automatic push_expected (logic [WIDTH-1:0] pkt);
  
for (int i = 0; i < NUM_UARTS; i++) begin  
    if (enable_piso_upstream[i] == 1) begin
        if (pkt[62] == 1'b0) begin
            if (verbose) begin
                $display("%m: i = %d",i);
                $display("%m: expecting an upstream packet");
            end
            sb.push_exp(i,pkt);
        end
    end else if (enable_piso_downstream[i] == 1) begin
        if (pkt[62] == 1'b1) begin
            if (verbose) begin 
                $display("%m: i = %d, enable_piso_downstream = %b",
                    i,enable_piso_downstream);
                $display("%m: expecting a downstream packet: %h",pkt);
            end
            sb.push_exp(i,pkt); 
           end
        end
    end
endtask

  //  Capture DUT transmission
always @(posedge clk) begin
    if (reset_n) begin
        for (int i=0;i<NUM_UARTS;i++) begin
            if (ld_tx_data_uart[i]) begin
                sb.capture(i,tx_data_uart[i]);
                if (verbose) begin
                    $display("pkt %0d captured. pkt = %h",pkt_cnt++,tx_data_uart[i]);
                end
            end
        end
    end
end

always @(posedge clk) begin
    if (ld_tx_data_uart) tx_busy_handler();
end

  //  Error handling
int  errors = 0;
bit  test_failed = 1'b0;

task automatic process_error;
    errors++;
    test_failed = 1'b1;
endtask

  //  Packet builders
function automatic pkt_t build_data_pkt(
    input logic [7:0] chip_id_fld,
    input logic [5:0] chan_id,
    input logic [27:0] stamp,
    input logic        reset_smpl,
    input logic        cds,
    input logic [9:0]  adc,
    input logic [1:0]  trig,
    input logic [3:0]  seq,
    input logic        downstream);
    pkt_t pkt;
    pkt = '0;
    pkt[1:0]   = 2'b01;
    pkt[9:2]   = chip_id_fld;
    pkt[15:10] = chan_id;
    pkt[43:16] = stamp;
    pkt[44]    = reset_smpl;
    pkt[45]    = cds;
    pkt[55:46] = adc;
    pkt[57:56] = trig;
    pkt[61:58] = seq;
    pkt[62]    = downstream;
    pkt[63]    = ~^pkt[62:0];
    return pkt;
endfunction

function automatic pkt_t build_cfg_write(
    input logic [7:0] chip_id_fld,
    input logic [5:0] chan_id,
    input logic [7:0] reg_addr,
    input logic [7:0] reg_data);
    pkt_t pkt;
    pkt = '0;
    pkt[1:0]   = 2'b10;
    pkt[9:2]   = chip_id_fld;
    pkt[15:10] = chan_id;
    pkt[17:10] = reg_addr;
    pkt[25:18] = reg_data;
    pkt[57:26] = MAGIC_NUMBER;
    pkt[62]    = 1'b0;  // config writes always upstream
    pkt[63]    = ~^pkt[62:0];
    return pkt;
endfunction

function automatic pkt_t build_cfg_read(
    input logic [7:0] chip_id_fld,
    input logic [5:0] chan_id,
    input logic [7:0] reg_addr);
    pkt_t pkt;
    pkt = '0;
    pkt[1:0]   = 2'b11;
    pkt[9:2]   = chip_id_fld;
    pkt[15:10] = chan_id;
    pkt[17:10] = reg_addr;
    pkt[57:26] = MAGIC_NUMBER;
    pkt[62]    = 1'b1;  // config reads always downstream
    pkt[63]    = ~^pkt[62:0];
    return pkt;
endfunction

  //  Event stub – drives event_data / event_valid when ready
task automatic drive_event(input pkt_t pkt);
    @(posedge clk);
    while (!ready_for_event) @(posedge clk);
    event_data  = pkt.packet;
    event_valid = 1'b1;
    @(posedge clk);
    event_valid = 1'b0;
    event_data  = '0;
endtask


  //  Config stub – drives pkt_data / pkt_valid when ready
task automatic drive_config(input pkt_t pkt);
    @(posedge clk);
    while (!ready_for_pkt) @(posedge clk);
    force pkt_data  = 64'hDEAD_BEEF_DEAD_BEEF;
    force pkt_valid = 1'b1;
    @(posedge clk)//Show the the FIFO can read and write simultaneously;
    force pkt_valid = 1'b0;
    force pkt_data  = '0;
    release pkt_data;
    release pkt_valid;
endtask


  //  UART RX driver – models a UART delivering a packet to the DUT
task automatic drive_rx_uart(input logic [3:0] posi_mask, input pkt_t pkt);
    // Initially set all specified UARTs to have data
    // Keep track of which UARTs have been processed
    logic [3:0] processed_uarts = 4'b0000;
    rx_empty_uart = ~posi_mask;  // 0 = has data, 1 = empty
    
    for (int i = 0; i < NUM_UARTS; i++) begin
        if (posi_mask[i]) begin
            rx_data_uart[i] = pkt;
        end
    end
    if (verbose) 
        $display("%m: Drive started at %0t - rx_empty_uart = %b", 
                $time, rx_empty_uart);
    

    
    // Wait for DUT to process each UART one by one
    while (processed_uarts != posi_mask) begin
        // Wait for any UART to be unloaded
        wait(uld_rx_data_uart != 4'b0000);
        
        // Process the UARTs that were just unloaded
        for (int i = 0; i < NUM_UARTS; i++) begin
            if (uld_rx_data_uart[i] && !processed_uarts[i]) begin
                if (verbose) begin
                    $display("%m: uld_rx_data_uart[%b] = %b",i,uld_rx_data_uart[i]);
                    $display("%m: UART %0d processed at time %0t", i, $time);
                end
                rx_empty_uart[i] = 1'b1;  // Mark as empty
                rx_data_uart[i] = '0;     // Clear data
                processed_uarts[i] = 1'b1; // Mark as processed
            end
        end
        
        @(posedge clk);
        if (verbose)
        $display("%m: %0t: Progress - processed: %b, remaining: %b", 
                 $time,processed_uarts, posi_mask & ~processed_uarts);
    end
    if (verbose)
        $display("%m: All UARTs processed at time %0t", $time);
endtask

task automatic tx_busy_handler;
    if (ld_tx_data_uart)  
        @(posedge clk) tx_busy = '0;
    if (tx_busy == 4'b1111) begin
        repeat(64) @(posedge clk); 
        tx_busy = '0;
    end
endtask

  //  Assertions
/*property p_tok_onehot;
    @(posedge clk) disable iff (!reset_n)
    ($countones(token_onehot) == 1);
endproperty

assert property (p_tok_onehot) else
    $error("%0t: token_onehot not one‑hot", $time);
*/
property p_ld_one_cycle;
    @(posedge clk) disable iff (!reset_n)
        (ld_tx_data_uart != 0) |-> ##1 (ld_tx_data_uart == 0);
endproperty
  
assert property (p_ld_one_cycle) else
    $error("%0t: ld_tx_data_uart held >1 cycle", $time);

  //  Test 1 – normal event packet
task automatic t_event_normal();
logic [WIDTH-1:0] current_pkt;
string test_name = "t_event_normal";

begin
    $display("%0t: Test %s", $time/1e6, test_name);



    // Force routing to UART0 only for deterministic checking
    enable_posi            = 4'b0001;
    enable_piso_upstream   = 4'b0010;
    enable_piso_downstream = 4'b0101;
    current_pkt = build_data_pkt(
            .chip_id_fld (8'hAA),
            .chan_id     (6'd0),
            .stamp       (28'd100),
            .reset_smpl  (1'b0),
            .cds         (1'b0),
            .adc         (10'd123),
            .trig        (2'b00),
            .seq         (4'd0),
            .downstream  (1'b1) );

    push_expected(current_pkt);
    drive_event(current_pkt);
    repeat (200) @(posedge clk);
    sb.compare();
    if (sb.total_errors()!=0) begin
        $error("%0t: Test %s FAILED", $time/1e6,test_name);
        process_error();
    end else begin
        $display("%0t: Test %s PASSED", $time/1e6,test_name);
    end

end
endtask

///  Test 1b – normal config‑read packet
task automatic t_config_normal();
pkt_t current_pkt;
string test_name = "t_config_normal";

begin
    $display("%0t: Test %s", $time/1e6, test_name);

    // Keep single‑UART routing
    enable_posi            = 4'b0001;
    enable_piso_upstream   = 4'b0000;
    enable_piso_downstream = 4'b0001;

    assert(enable_piso_upstream != enable_piso_downstream)
        else $error("PISO can only be upstream or downstream, not both");

//    current_pkt = build_cfg_read(
//        .chip_id_fld (8'h55),
//        .chan_id    (6'd0),
//        .reg_addr   (8'h10) );
    current_pkt = 64'hDEAD_BEEF_DEAD_BEEF;
    push_expected(current_pkt); 
    drive_config(current_pkt);
    repeat (200) @(posedge clk);
    sb.compare();
    if (sb.total_errors()!=0) begin
        $error("%0t: Test %s FAILED", $time/1e6,test_name);
        process_error();
    end else begin
        $display("%0t: Test %s PASSED", $time/1e6,test_name);
    end

end
endtask

  //  Test 2 – concurrent Rx on all UARTs
task automatic t_rx_concurrent();
pkt_t pkt;
int i;
string test_name = "t_rx_concurrent";

begin
    $display("%0t: Test %s", $time/1e6, test_name);
    enable_posi            = 4'b1111;
    enable_piso_upstream   = 4'b0010;
    enable_piso_downstream = 4'b1001;


    assert(enable_piso_upstream != enable_piso_downstream)
        else $error("PISO can only be upstream or downstream, not both");


    pkt = build_data_pkt(
                .chip_id_fld (6'd1),
                .chan_id    (6'd1),
                .stamp      (28'd200),
                .reset_smpl (1'b0),
                .cds        (1'b0),
                .adc        (10'd321),
                .trig       (2'b00),
                .seq        (4'd0),
                .downstream (1'b1) );
    for (i=0;i<NUM_UARTS;i++) begin
        if (enable_posi[i]) begin
            if (verbose)
                $display("%m: time = %0t, push rx packet[%0d]\n",$time/1e6,i);           
            push_expected(pkt);
        end
    end

    drive_rx_uart(enable_posi,pkt);

    repeat (1000) @(posedge clk);
    sb.compare();
    if (sb.total_errors()!=0) begin
        $error("%0t: Test %s FAILED", $time/1e6,test_name);
        process_error();
    end else begin
        $display("%0t: Test %s PASSED", $time/1e6,test_name);
    end
end
endtask

  //  Test 3 – upstream pass‑through
task automatic t_pass_through_upstream();
pkt_t pkt;
string test_name = "t_pass_through_upstream";
begin
    $display("%0t: %s", $time/1e6,test_name);
    // Only UART1 enabled for upstream traffic
    enable_posi            = 4'b0001;
    enable_piso_upstream   = 4'b0010;
    enable_piso_downstream = 4'b1000;


    pkt = build_cfg_write(
                .chip_id_fld (8'hAB),
                .chan_id    (6'd0),
                .reg_addr   (8'h10),
                .reg_data   (8'hFF) );

    push_expected(pkt);
    drive_rx_uart(enable_posi,pkt);                    // inject on UART0
    repeat (300) @(posedge clk);
    sb.compare();
    if (sb.total_errors()!=0) begin
        $error("%0t: Test %s FAILED", $time/1e6,test_name);
        process_error();
    end else begin
        $display("%0t: Test %s PASSED", $time/1e6,test_name);
    end

       
end
endtask

//  Test 4 -- config‑read and event in the same cycle
task automatic t_cfg_event_simultaneous();
pkt_t cfg_pkt, evt_pkt;
string test_name = "t_cfg_event_simultaneous";

begin
    $display("%0t: Test %s", $time/1e6,test_name);
    enable_posi            = 4'b0001;
    enable_piso_upstream   = 4'b0100;
    enable_piso_downstream = 4'b0001;

    cfg_pkt = build_cfg_read(
                    .chip_id_fld (chip_id),
                    .chan_id    (6'd0),
                    .reg_addr   (8'h20));

    evt_pkt = build_data_pkt(
                    .chip_id_fld (chip_id),
                    .chan_id    (6'd0),
                    .stamp      (28'd400),
                    .reset_smpl (1'b0),
                    .cds        (1'b0),
                    .adc        (10'd250),
                    .trig       (2'b00),
                    .seq        (4'd0),
                    .downstream (1'b1) );

      // order does not matter – push both expectations
    push_expected(64'hDEAD_BEEF_DEAD_BEEF);
    push_expected(evt_pkt);
    // raise both sources together when both are ready
    @(posedge clk);
    fork
        drive_event(evt_pkt);
        drive_config(64'hDEAD_BEEF_DEAD_BEFF);
    join


    repeat (1000) @(posedge clk);
    sb.compare();
    if (sb.total_errors()!=0) begin
        $error("%0t: Test %s FAILED", $time/1e6,test_name);
        process_error();
    end else begin
        $display("%0t: Test %s PASSED", $time/1e6,test_name);
    end
end
endtask

  //  Test 5 -- token rotation sanity check

task automatic t_token_rotation();
logic [WIDTH-1:0] current_pkt;
int i;
    string test_name = "t_token_rotation";

logic [3:0] token_start;
begin
    $display("%0t: Test %s", $time/1e6,test_name);
    // Use only UART0 so token progression is easy to follow
    enable_posi            = 4'b0001;
    enable_piso_upstream   = 4'b0010;
    enable_piso_downstream = 4'b0001;
    token_start = dut.token_onehot; // get a baseline
    for (i=0;i<8;i++) begin
        current_pkt = build_data_pkt(
                    .chip_id_fld (8'hFF),          // different chip → pass‑along
                    .chan_id    (6'd0),
                    .stamp      (28'd500+i),
                    .reset_smpl (1'b0),
                    .cds        (1'b0),
                    .adc        (10'd0),
                    .trig       (2'b00),
                    .seq        (4'd0),
                    .downstream (1'b1) );           // downstream
       push_expected(current_pkt);
       drive_event(current_pkt);
             
//drive_rx_uart(enable_posi,pkt);

        repeat (4) @(posedge clk);
    end
    @(posedge clk);
    assert (dut.token_onehot == token_start) 
        else $error("%0t: token did not return to %b after 8 packets (got %b)", 
                $time/1e6, token_start, dut.token_onehot);
      sb.compare();
    if (sb.total_errors()!=0) begin
        $error("%0t: Test %s FAILED", $time/1e6,test_name);
        process_error();
    end else begin
        $display("%0t: Test %s PASSED", $time/1e6,test_name);
    end  

end
endtask

  //  Main stimulus
initial begin
    // Wait for reset to be released
    verbose = 0;
    
    @(negedge reset_n);
    @(posedge reset_n);
    repeat (5) @(posedge clk);
    $display("%0t: reset released -- starting tests", $time/1e6);
    t_event_normal();   sb.reset();
    t_config_normal();   sb.reset();
    t_rx_concurrent();  sb.reset();
    t_pass_through_upstream(); sb.reset();
    t_cfg_event_simultaneous(); sb.reset();
    t_token_rotation();

    if (errors == 0)
        $display("\n*** ALL TESTS PASSED *** at %0tus\n",$time/1e6);
    else
        $display("\n*** TESTS FAILED -- %0d errors ***\n", errors);
end

endmodule : hydra_ctrl_tb
