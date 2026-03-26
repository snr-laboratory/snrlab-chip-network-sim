`timescale 1ns/1ps
`default_nettype none

//  Minimal larpix_constants.sv  
//---------------------------------------------------------------
module larpix_constants; endmodule
`define CONFIG_WRITE_OP 2'b01
`define CONFIG_READ_OP  2'b10
`define MAGIC_NUMBER    32'hDEADBEEF
//`define IDLE            2'b00
//  Testbench for channel_ctrl
module channel_ctrl_tb;

// parameters
localparam logic[1:0] IDLE = 2'b0;
//  Clock & reset
logic clk;
logic reset_n;
logic verbose; // set to 1 for debug data

initial begin
    clk = 0;
    forever #100 clk = ~clk;       // 5 MHz clock
end

initial begin
    verbose = 0;
    reset_n = 0;
    #200 reset_n = 1;            // release reset after 200 ns
end

//  DUT‑side signals
// Outputs
logic [62:0] channel_event;
logic        csa_reset;
logic        fifo_empty;
logic        triggered_natural;
logic        sample;

// Inputs (driven by the testbench)
logic                channel_enabled;
logic                hit;
logic                read_local_fifo_n;
logic                external_trigger;
logic                cross_trigger;
logic                periodic_trigger;
logic                periodic_reset;
logic                channel_mask;
logic                external_trigger_mask;
logic                adc_wait;
logic                cross_trigger_mask;
logic                periodic_trigger_mask;
logic                enable_periodic_trigger_veto;
logic                enable_hit_veto;
logic [27:0]         timestamp;
logic [9:0]          dout;
logic                done;
logic [2:0]          reset_length;
logic [7:0]          chip_id;
logic [5:0]          channel_id;

// Configuration inputs
logic [9:0]  digital_threshold;
logic        threshold_polarity;
logic        enable_dynamic_reset;
logic [9:0]  dynamic_reset_threshold;
logic [7:0]  adc_burst_length;
logic        mark_first_packet;
logic [7:0]  adc_hold_delay;
logic        enable_min_delta_adc;
logic [9:0]  min_delta_adc;
logic        enable_tally;
logic        cds_mode;
logic        enable_local_fifo_diagnostics;


// temp variables
logic [3:0] diag_cnt; 
logic [62:0] channel_event_last;
logic channel_event_changed;
logic [1:0] tally;
int expected;
int read_raw, read_delay;
logic new_pkt;
int pkt_cnt;
int errors;
logic test_failed;
logic fifo_drain_en;
logic read_local_fifo;
logic fail_test; // set high to test the test (we want it to fail)
int tests_passed;

    // initialize variables
initial begin
    basic_cfg();
    diag_cnt = 0;
    test_failed= 0;
    tests_passed = 0;
    fifo_drain_en = 1;
    errors = 0;
    new_pkt = 0;
    pkt_cnt = 0;
    tally = 0;
    external_trigger = 0;
    cross_trigger = 0;
    periodic_trigger = 0;
    periodic_reset = 0;
    channel_event_last = 0;
    channel_event_changed = 0;
    hit             = 0;
    done            = 1;
    dout            = '0;
end // initial


//  DUT instantiation
channel_ctrl #(
    .WIDTH          (64),
    .LOCAL_FIFO_DEPTH(8),
    .TS_LENGTH      (28)
) channel_ctrl_inst (
    .channel_event          (channel_event),
    .csa_reset              (csa_reset),
    .fifo_empty             (fifo_empty),
    .triggered_natural      (triggered_natural),
    .sample                 (sample),
    .clk                    (clk),
    .reset_n                (reset_n),
    .channel_enabled        (channel_enabled),
    .hit                    (hit),
    .read_local_fifo_n      (read_local_fifo_n),
    .external_trigger       (external_trigger),
    .cross_trigger          (cross_trigger),
    .periodic_trigger       (periodic_trigger),
    .periodic_reset         (periodic_reset),
    .channel_mask           (channel_mask),
    .external_trigger_mask  (external_trigger_mask),
    .adc_wait               (adc_wait),
    .cross_trigger_mask     (cross_trigger_mask),
    .periodic_trigger_mask  (periodic_trigger_mask),
    .enable_periodic_trigger_veto (enable_periodic_trigger_veto),
    .enable_hit_veto        (enable_hit_veto),
    .timestamp              (timestamp),
    .dout                   (dout),
    .done                   (done),
    .reset_length           (reset_length),
    .chip_id                (chip_id),
    .channel_id             (channel_id),
    .digital_threshold      (digital_threshold),
    .threshold_polarity     (threshold_polarity),
    .enable_dynamic_reset   (enable_dynamic_reset),
    .dynamic_reset_threshold (dynamic_reset_threshold),
    .adc_burst_length       (adc_burst_length),
    .mark_first_packet      (mark_first_packet),
    .adc_hold_delay         (adc_hold_delay),
    .enable_min_delta_adc   (enable_min_delta_adc),
    .min_delta_adc          (min_delta_adc),
    .enable_tally           (enable_tally),
    .cds_mode               (cds_mode),
    .enable_local_fifo_diagnostics (enable_local_fifo_diagnostics)
);

// Event-router behavioral model (read out channel_controller)
always_comb begin
    if (fifo_drain_en) begin
        read_raw = fifo_empty;
        read_local_fifo_n = (!read_raw & ~read_delay)? 1'b0 : 1'b1;
    end
end    


always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) read_delay <= 1'b1;
    else read_delay <= read_raw;
end // always_ff
     

//  Helper tasks
// Wait for N clock cycles
task automatic wait_clocks (input int n);
    repeat (n) @(posedge clk);
endtask

// ADC model
task automatic sim_adc(input [9:0] value = 512);
// ADC takes 850 ns or so for a conversion
// LArPix clock is 5 MHz (or 200 ns clock period)
// so ADC takes 4 clock cycles
    begin
        // simulate ADC conversion:
        //   - pull DONE low for four cycles (conversion)
        //   - raise DONE high again (conversion finished)
        done = 1;
        @(posedge clk); done = 1'b0;   // start conversion
        wait_clocks(4);                // ADC takes about 4 cycles to convert
        dout = value;
        @(posedge clk); done = 1'b1;   // conversion complete
    end
endtask 

//  N‑cycle pulse 
task automatic pulse (ref sig,input int cycles=1);   
    begin
        @(posedge clk);

        // raise the pulse
        sig = 1'b1;
        // wait for the *next* rising edge of the clock
        wait_clocks(cycles);
        //   repeat (cycles) @(posedge clk);
        // lower the pulse again
        sig = 1'b0;
   end
endtask

// simple error handler
task automatic process_error;
    begin
        errors++;
        test_failed= 1;
    end
endtask

//  Capture packets written to the FIFO
typedef struct packed {
    logic [63:0] pkt;
} pkt_t;

pkt_t pkt_queue[$];   // dynamic queue

// Monitor the channel_event output – a new packet appears each time the
// FIFO writes (the stub updates data_out on the same cycle).
always @(posedge clk) begin
    new_pkt <= 1'b0;
    channel_event_last <= channel_event;
    channel_event_changed = (channel_event_last != channel_event);
    if (reset_n && channel_event_changed !== 0) begin
        pkt_queue.push_back('{pkt:channel_event});
        new_pkt <= 1'b1;
        pkt_cnt++;
        if (verbose) 
            $display("\n%0t: PACKET CAPTURED  = %h", $time, channel_event);
    end
end

//  Basic configuration (used by most tests)
task automatic basic_cfg;
    begin
        // generic defaults
        chip_id                     = 8'hAB;
        channel_id                  = 6'd5;
        channel_enabled             = 1'b1;
        channel_mask                = 1'b0;
        external_trigger_mask       = 1'b1;
        cross_trigger_mask          = 1'b0;
        periodic_trigger_mask       = 1'b0;
        enable_periodic_trigger_veto= 1'b0;
        enable_hit_veto             = 1'b0;
        adc_wait                    = 1'b0;   
        reset_length                = 8'd1;   
        timestamp                   = 28'h0AA55; 
        digital_threshold           = 10'd0;
        threshold_polarity          = 1'b1; 
        enable_dynamic_reset        = 1'b0;
        dynamic_reset_threshold     = 10'd0;
        adc_burst_length            = 8'd0; 
        mark_first_packet           = 1'b0;
        adc_hold_delay              = 8'd1;
        enable_min_delta_adc        = 1'b0;
        min_delta_adc               = 10'd0;
        enable_tally                = 1'b0;
        cds_mode                    = 1'b0;
        enable_local_fifo_diagnostics = 1'b0;
        done                        = 1'b1;
        test_failed                = 1'b0;
    end
endtask
        

//  1) Natural trigger
task automatic test_natural_trigger;
    begin
        $display("\n--- TEST 1 : NATURAL TRIGGER ---");
        basic_cfg();
        wait_clocks(100);
        // make threshold pass
        // issue a hit (natural trigger)
        pulse(hit);
        // adc conversion
        sim_adc(250);
        // wait for the packet to be written
        wait (pkt_queue.size() == 1);
        // check trigger_type == 00 (natural)
        assert(pkt_queue[0].pkt[57:56] == 2'b00) 
            $display("%m packet generated with correct trigger type");
            else begin
                $error("%m: wrong trigger_type. Expected 00, received %h",
                    pkt_queue[0].pkt[57:56]);
                process_error();
            end
        if (test_failed) $display("%m:Natural trigger test FAILED");
        else begin
            tests_passed++;
            $display("%m:Natural trigger test PASS");
        end
    end
endtask

//  2) External trigger
task automatic test_external_trigger;
    begin
        $display("\n--- TEST 2 : EXTERNAL TRIGGER ---");
        basic_cfg();
         // pulse external trigger (channel mask disabled)
        // simulate conversion
        sim_adc(250);
        wait_clocks(10);
        assert(pkt_queue.size() == 0) 
            $display("%m: no trigger when masked. Passed");
        else begin
            $error("%m: trigger detected when masked. Failed.");
            process_error();
        end
        external_trigger_mask = 0;
        pulse(external_trigger,1);
       // simulate conversion
        sim_adc(250);
        wait (pkt_queue.size() == 1);
        // trigger_type should be 01
        assert(pkt_queue[0].pkt[57:56] == 2'b01)
             $display("%m: packet generated when unmasked\
                     with correct trigger type. Passed");
        else begin
            $error("%m: wrong trigger_type %b", pkt_queue[0].pkt[57:56]);
            process_error();
        end
        if (test_failed) $display("%m: Periodic trigger test FAILED");
        else begin
            tests_passed++;
            $display("%m: Periodic trigger test PASS");
        end
    end
endtask

//  3) Periodic trigger
task automatic test_periodic_trigger;
    begin
        $display("\n--- TEST 3 : PERIODIC TRIGGER ---");
        basic_cfg();
        // enable the periodic trigger source
        periodic_trigger_mask = 1;
        pulse(periodic_trigger);
        // enable the periodic trigger source
        wait_clocks(10);
        sim_adc(250);
        assert(pkt_queue.size() == 0) $display("%m: no trigger when masked. Passed");
        else begin 
            $error("%m: trigger accepted when masked");
            process_error();
        end
        periodic_trigger_mask = 0;
        pulse(periodic_trigger);
       // simulate conversion
        sim_adc(275);
        wait (pkt_queue.size() == 1);
        // trigger_type == 11 for periodic
        assert(pkt_queue[0].pkt[57:56] == 2'b11) 
            $display("%m:trigger detected when not masked. Passed.");
        else begin 
            $error("%m: wrong trigger_type %b", pkt_queue[0].pkt[57:56]);
            process_error();
        end
        if (test_failed) $display("%m: Periodic trigger test FAILED");
        else begin
            tests_passed++;
            $display("%m: Periodic trigger test PASS");
        end
    end
endtask

//  4) Periodic‑trigger veto (hit present blocks periodic)
task automatic test_periodic_veto;
    begin
        $display("\n--- TEST 4 : PERIODIC TRIGGER VETO ---");
        basic_cfg();

        // enable veto
        enable_periodic_trigger_veto = 1'b1;
        // provide a hit at the same time – this must suppress the
        // periodic trigger packet.
        pulse(hit); 
        #7 pulse(periodic_trigger); // 7ns after natural hit
        // conversion still occurs because hit generated a natural trigger
        sim_adc(250);
        // we expect ONE packet (the natural one), not a second periodic one
        wait_clocks(10);
        assert (pkt_queue.size() == 1)
            $display("Received one packet, as expected");
        else begin
            $error("Received %h packets, too many",pkt_queue.size());
            process_error();
        end
    // check trigger type
        assert(pkt_queue[0].pkt[57:56] == 2'b00) 
            $display("%m: natural packet detected and periodic trigger suppressed.\
                 Passed."); 
            else begin
                $error("%m:: unexpected packet type %b", pkt_queue[0].pkt[57:56]);
                process_error();
            end
        if (test_failed) $display("%m: Periodic trigger veto test FAILED");
        else begin
            tests_passed++;
            $display("%m: Periodic trigger veto test PASS");
        end
    end
endtask

//  5) Hit-veto (channel aborts when hit disappears before conversion)
task automatic test_hit_veto;
    begin
        $display("\n--- TEST 5 : HIT VETO ---");
        basic_cfg();

        enable_hit_veto = 1'b1;   // enable the feature
        hit = 1'b1;               // start with a valid hit
        @(posedge clk);
        // immediately drop the hit – the controller should abort
        hit = 1'b0;

        @(posedge clk);

        // after a few cycles there must be NO packet
        wait (pkt_queue.size() == 0);
        // give the FSM some time to settle
        wait_clocks(10);
        assert(pkt_queue.size() == 0) begin
            if (verbose) 
                $display("%m:HIT_VETO: packet generation suppressed when\
                    hit goes low before CSA reset. Passed");
            end else $error("%m:Hit veto failed --\
                a packet was generated despite hit loss");
    if (test_failed) $display("%m: Dynamic reset test FAILED");
    else begin
        tests_passed++;
        $display("%m: Dynamic reset test PASS");
    end

end
endtask

//  6) Dynamic reset (CSA reset when dout exceeds dyn-threshold)
task automatic test_dynamic_reset;
    begin
        $display("\n--- TEST 6 : DYNAMIC RESET ---");
        basic_cfg();
        adc_burst_length = 4; // maximum number of samples before reset
        enable_dynamic_reset   = 1'b1;
        dynamic_reset_threshold = 10'd180; // lower than our first sample
        // first sample will be below the threshold immediate reset
        pulse(hit);   // natural trigger
        repeat (adc_burst_length) begin
            assert(randomize(timestamp)==1)
                else $error("%m:randomize function failed");
            sim_adc(100);
        end
        // we expect adc_burst_length packets (the data packets) 
        wait_clocks(adc_burst_length*8);
        assert(pkt_queue.size() == adc_burst_length)
        $display("%m: received %h packets, as expected",pkt_queue.size());
        else begin
            $error("%m: received %h packets,  expected %h",
                pkt_queue.size(), adc_burst_length);
            process_error();
         end
        wait_clocks(10);
        // second sample will be above the threshold immediate reset
        // dump queue for next test
        pkt_queue.delete();
        pulse(hit);
        repeat (adc_burst_length) begin
            assert(randomize(timestamp)==1)
                else $error("%m:randomize function failed");
            sim_adc(200);
        end
        // we expect ONE packet (the data packet) and a CSA reset pulse
        wait_clocks(adc_burst_length*8);
        assert(pkt_queue.size() == 1) 
            $display("%m: got %h packets as expected", pkt_queue.size());
        else begin
            $error("%m: got %h packet, expected 1", pkt_queue.size());
            process_error();
        end
    if (test_failed) $display("%m: Dynamic reset test FAILED");
    else begin
        tests_passed++;
        $display("%m: Dynamic reset test PASS");
    end
    end
endtask

//  7) Digital threshold – both polarities
task automatic test_digital_threshold;
begin
    $display("\n--- TEST 7 : DIGITAL THRESHOLD (POS & NEG) ---");
    basic_cfg();

    //  Positive polarity (> threshold)
    threshold_polarity = 1'b1;
    digital_threshold  = 10'd250;
    dout = 10'd240; // below. should NOT generate a packet
    done = 1'b1;
    pulse(hit);
    sim_adc(dout);
    wait_clocks(5);
    assert(pkt_queue.size() == 0) 
        $display("%m:No packet rcvd. Correct for below-threshold");
    else begin 
        $error("%m:Packet generated when dout < threshold (pos polarity)");
        process_error();
    end

    //  Negative polarity (< threshold)
    pkt_queue.delete(); // clear previous entries
    threshold_polarity = 1'b0;
    digital_threshold  = 10'd250;
    dout = 10'd260; // above. should NOT generate a packet
    pulse(hit);
    sim_adc(dout);
    wait_clocks(5);
    assert(pkt_queue.size() == 0) 
        $display("%m:No packet rcvd. Correct for above-threshold");
    else begin 
        $error("%m:Packet generated when dout > threshold (neg polarity)");
        process_error();
    end

    //  Positive polarity again – now above threshold
    pkt_queue.delete();
    threshold_polarity = 1'b1;
    dout = 10'd260; // above. packet should appear
    pulse(hit);
    sim_adc(dout);
    wait_clocks(5);
    assert (pkt_queue.size() == 1)
        $display("%m:Digital threshold (+) packet generated as expected.");
    else begin
        $error("%m:No packet generated for (+) packet as expected (dout > threshold).");
        process_error();
    end    
    threshold_polarity = 1'b0;
    dout = 10'd240;
    pulse(hit);
    sim_adc(dout);
    wait_clocks(5);
    assert (pkt_queue.size() == 2)
        $display("%m:Digital threshold (-) packet generated as expected.");
    else begin
        $error("%m:No packet generated for (-) packet as expected (dout < threshold).");
        process_error();
    end    

    if (test_failed) $display("%m:ADC hold delay test FAILED");
    else begin
        tests_passed++;
        $display("%m:ADC hold delay test PASS");
    end
end
endtask

//  8) ADC hold‑delay (sample pulse stretching)
task automatic test_adc_hold_delay (input int hold_delay = 4);
int cnt;
begin
    $display("\n--- TEST 8 : ADC HOLD DELAY ---");
    basic_cfg();

    // Hold for hold_delay cycles 
    adc_hold_delay = 8'd4;
    wait_clocks(5);
    dout = 10'd210;
    done = 1'b1;
    pulse(hit);

    // check that the sample output stayed high for hold_delay cycles
    // (we can simply count the number of cycles where sample is high)
    cnt = 0;
    repeat (10) begin
        @(posedge clk);
        if (sample) cnt++;
    end
    assert(cnt==4) 
        $display("%m:Sample stretch width = %0d cycles (expect 4)", cnt);
    
    else begin 
        $error("%m:Sample stretch width %0d != 4", cnt);
        process_error();
    end

    // conversion
    sim_adc(dout);

    if (test_failed) $display("%m:ADC hold delay test FAILED");
    else begin
        tests_passed++;
        $display("%m:ADC hold delay test PASS");
    end

end
endtask

//  9) ADC burst – number of data samples after the (optional) reset
task automatic test_adc_burst (input int burst_size = 12);
int packets_received;
begin
    $display("\n--- TEST 9 : ADC BURST ---");
    basic_cfg();
    packets_received = 0;
    adc_burst_length = burst_size;  // three data samples per hit
    mark_first_packet = 1'b1;
    dout = 10'd210;
    wait_clocks(5);
    // start a natural trigger
    pulse(hit);

    // ---------- conversions (burst) ----------
    repeat (burst_size) begin
        assert(randomize(timestamp)==1)
           else $error("%m:randomize function failed");

        // request next sample automatically by the FSM
        sim_adc(dout);
        packets_received++;
        wait (pkt_queue.size() == packets_received)
        wait_clocks(5);
    end

    // After the whole burst the controller should have
    // returned to IDLE – we can check that the FSM is in the IDLE state.
    // need to wait for all the packets to percolate
    wait_clocks(10*burst_size);

    assert(channel_ctrl_inst.State == 2'b00)
        $display("%m: channel FSM is back in IDLE");
    else begin
        $error("%m: Channel Controller state != IDLE. (burst is complete)");
        process_error();
    end
    // total packets should be burst_size
    assert(pkt_queue.size() == burst_size) $display("%m: %0d packets received,\ 
        %0d expected",pkt_queue.size(),burst_size);
    else begin 
        $error("%m:Burst length mismatch: expected %0d packets, got %0d",
            burst_size, pkt_queue.size());
        process_error();
    end
    if (test_failed) $display("%m:ADC burst test FAILED");
    else begin
        tests_passed++;
        $display("%m:ADC burst test PASS");
    end

end
endtask

// 10) Min‑delta‑ADC (reset when successive samples are too close)
task automatic test_min_delta_adc;
begin
    $display("\n--- TEST 10 : MIN-DELTA ADC ---");
    basic_cfg();

    enable_min_delta_adc = 1'b1;
    min_delta_adc        = 10'd5;   // “small” delta threshold
    adc_burst_length     = 8'd5;   // allow several samples
    reset_length         = 3'd5;
    // First sample – any value
    dout = 10'd200;
    pulse(hit);
    assert(randomize(timestamp)==1)
        else $error("%m:randomize function failed");

    timestamp[27] = 0; 
    sim_adc(dout);
    wait (pkt_queue.size() == 1);

    // Second sample - difference = 13 (>5) so should trigger reset
    dout = 10'd213;
    pulse(hit);
    assert(randomize(timestamp)==1)
      else $error("%m:randomize function failed");

    timestamp[27] = 0; 
    sim_adc(dout);
    wait_clocks(10);
    assert(csa_reset == 1'b0) $display("%m:CSA reset not asserted\ 
        when min-delta condition not met");
    else begin 
        $error("%m:CSA reset asserted on min-delta condition");
        process_error();
    end

    // Third sample - difference = 3 (<5) so should trigger reset
    dout = 10'd216;
    pulse(hit);
    assert(randomize(timestamp)==1)
        else $error("%m:randomize function failed");

    timestamp[27] = 0; 
    sim_adc(dout);

    // The reset happens after the packet is written, so we should see
    // a third packet and then the CSA reset pulse.
    wait (pkt_queue.size() == 3);
    assert(csa_reset == 1'b1) $display("%m: CSA reset asserted\
        on min-delta condition");
    else begin 
        $error("%m:CSA reset NOT asserted on min-delta condition");
        process_error();
    end
    if (test_failed) $display("%m: Min delta ADC test FAILED");
    else begin
        tests_passed++;
        $display("%m:Min delta ADC test PASS");
    end
    
    // clean up
    reset_length = '0;
end
endtask

// 11) Mark first packet (timestamp MSB)
task automatic test_mark_first_packet(input int burst_size = 10);
begin
    $display("\n--- TEST 11 : MARK FIRST PACKET ---");
    basic_cfg();

    adc_burst_length = burst_size;  // data samples per hit
    mark_first_packet = 1'b1;
    dout = 10'd210;
    wait_clocks(5);
    // start a natural trigger
    pulse(hit);
    assert(randomize(timestamp)==1)
        else $error("%m:randomize function failed");

    timestamp[27] = 0; 
    // ---------- first conversion (reset packet not used here) ----------
    sim_adc(dout);
    // The MSB of the timestamp field (bit 43 of the packet) should be 1
    wait (pkt_queue.size() == 1); // first data packet
    assert(pkt_queue[0].pkt[43]) 
        $display("%m:first packet timestamp MSB is set as expected");
    else begin 
        $error("%m:First packet timestamp MSB not set (pkt = %h)", pkt_queue[0].pkt);
        process_error();
    end


    // ---------- subsequent conversions (burst) ----------
    repeat (adc_burst_length - 1) begin
        assert(randomize(timestamp)==1)            
            else $error("%m:randomize function failed");

        timestamp[27] = 0; 
        // request next sample automatically by the FSM
        sim_adc(dout);
        wait_clocks(5);
    end

    // After the whole burst the controller should have issued a CSA reset
    // and returned to IDLE – we can check that csa_reset goes high.
    wait_clocks(10);
    // total packets should be 3 (burst_length)
    assert(pkt_queue.size() == adc_burst_length) 
        $display("%m: %d packets received, as expected", pkt_queue.size());
    else begin
        $error("%m:Error: %d packets, received, 3 expected",pkt_queue.size());
        process_error();
    end

   // The MSB of the timestamp field (bit 43 of the packet) should be 0
    assert(!pkt_queue[1].pkt[43]) 
        $display("%m:first packet timestamp MSB is not set (as expected)");

    else begin
        $error("%m: First packet timestamp MSB set (pkt = %h) - not first packet"
            , pkt_queue[0].pkt);
        process_error();
    end

    if (test_failed) $display("%m:Mark-first-packet test FAILED");
    else begin
        tests_passed++;
        $display("%m:Mark-first-packet test PASS");
    end

end
endtask

// 12) Event tally (bits 61:60)
task automatic test_event_tally;
begin
    $display("\n--- TEST 12 : EVENT TALLY ---");
    basic_cfg();
    enable_tally = 1'b1;
    adc_burst_length = 8'd9;   // generate a few packets
    assert(randomize(dout)==1)
        else $error("%m:randomize function failed");
    pulse(hit);
    // generate packets (burst)
    repeat (adc_burst_length) sim_adc(dout);
    wait (pkt_queue.size() == adc_burst_length);
    // Verify that bits 61:60 increment modulo-4
    foreach (pkt_queue[i]) begin
        tally = pkt_queue[i].pkt[61:60];
        // tally is incremented while packet is built, so starts at one
        expected = (i+1) % 4;
        assert(tally == expected) $display("%m:Packet %0d tally = %0d,\
            expected %0d",i,tally,expected);
         else begin
            $error("%m:Packet %0d tally = %0d, expected %0d",i,tally,expected);
            process_error();
         end
    end
    if (test_failed) $display("%m:Event tally test FAILED");
    else begin 
        $display("%m:Event tally test PASS");
        tests_passed++;
    end
    wait_clocks(40);

end
endtask

// 13) Correlated‑Double‑Sampling (CDS)
task test_cds (bit fail_test = 0);
logic cds_mode_bit;
logic cds_reset_bit; 
logic cds_reset_expected;

begin
    $display("\n--- TEST 13 : CORRELATED DOUBLE SAMPLING (CDS) ---");
    basic_cfg();
    cds_mode          = 1'b1;       // enable CDS
    adc_burst_length  = 8'd2;       // two data samples after reset
    mark_first_packet = 1'b1;      // set the MSB on both packets
    dout = 10'd210;
    sim_adc(dout);  // read out reset sample
    wait_clocks(40);
    pulse(hit);
    adc_wait = 0;
    repeat (adc_burst_length+1) begin
        assert(randomize(timestamp)==1)
            else $error("%m:randomize function failed");
        sim_adc(dout);
    end
    // We expect adc_burst_length packets: reset + burst data + next_reset
    wait (pkt_queue.size() == adc_burst_length+2);
    wait_clocks(1);
    // example packet stream: adc_burst_length = 2
    // packet 0,3 => bit[45]= 1, [44]=1;
    // packets 1‑2 =>  bit[45]=1, [44]=0
    for (int i = 0; i < adc_burst_length + 2; i++) begin 
        cds_mode_bit = (fail_test) ? 1'b0 : pkt_queue[i].pkt[45];
        cds_reset_bit = pkt_queue[i].pkt[44];
        cds_reset_expected = ((i == 0) || ( i == adc_burst_length + 1)) ? 1'b1 : 1'b0;
        if (fail_test) begin 
            assert(!cds_mode_bit & (cds_reset_bit == cds_reset_expected))
                $display("%m: packet[%2d] test failed as expected \
                    (testing the test)",i);
            else begin
                $error("%m: Test did not fail as expected \
                        rcvd packet %2d CDS bits correct : cds_mode = %h, \
                        cds_reset = %b, expected cds_mode = 1, cds_reset = %h",
                        i,cds_mode_bit, cds_reset_bit,cds_reset_expected);
                process_error();
            end
        end else assert(cds_mode_bit & (cds_reset_bit == cds_reset_expected))
                $display("%m: rcvd packet %d CDS bits correct : cds_mode = %h, \
                    cds_reset = %h, expected cds_mode = 1, cds_reset = %h",
                    i,cds_mode_bit, cds_reset_bit,cds_reset_expected);
        else begin
            process_error(); 
            $error("%m:rcvd packet %d CDS bits incorrect : cds_mode = %h, \
                cds_reset = %h, expected cds_mode = 1, cds_reset = %h",
                i,cds_mode_bit,cds_reset_bit,cds_reset_expected);
        end // else
    end // end

    // Verify timestamp MSB set on reset and first data packet (packet 0 & 1)
    assert(pkt_queue[0].pkt[44] == 1'b1 && pkt_queue[1].pkt[44] == 1'b0)
        $display("%m:Timestamp bit set correctly on first CDS reset packet");
    else begin
        process_error();
        $error("%m:Timestamp MSB not set on reset/first data packet");
    end
    if (test_failed) $display("CDS test FAILED");
    else begin
        tests_passed++;
        $display("%m:CDS test PASS");
    end
    // clean up for next test
    cds_mode = 0;
    adc_burst_length = 0;
    repeat(4) sim_adc(dout); // clock out last packets (reset + data)
    wait_clocks(40);
  //  sim_adc(dout); // clock out last packets (reset + data)
end
endtask

// 15) FIFO diagnostics (bits 58,59 and optional counter[31:28])
task automatic test_fifo_diagnostics(input int burst_size = 12);
bit is_fifo_half;
bit is_fifo_full;
logic [3:0] local_fifo_counter_val;
begin
    $display("\n--- TEST 15 : FIFO DIAGNOSTICS ---");
    basic_cfg();
    // disable FIFO readout
    fifo_drain_en = 0;
    enable_local_fifo_diagnostics = 1'b1;
    // Force the FIFO to become half‑full and then full by writing
    // more packets than the depth.
    // We will generate 10 packets (depth = 8) after 8 packets
    // fifo_half should be 1, after 8 packets fifo_full should be 1.
    adc_burst_length = burst_size;   // allow many packets
    dout = 10'd210;

    // fire a hit that will generate a long burst
    pulse(hit);
    // Let the FSM produce the rest of the burst automatically.
    repeat(8) sim_adc(dout);      
    is_fifo_half = channel_ctrl_inst.event_word_next[58];      
    is_fifo_full = channel_ctrl_inst.event_word_next[59];    
    local_fifo_counter_val = channel_ctrl_inst.event_word_next[31:28] + 1;  
    $display("%m:local FIFO half full...");
    assert(channel_ctrl_inst.local_fifo_half == is_fifo_half) 
        $display("%m:Local FIFO half correctly captured in packet");
    else begin
        $error("%m:Local FIFO half incorrectly captured in packet");
        process_error();
    end
    assert(channel_ctrl_inst.local_fifo_full == is_fifo_full) 
        $display("%m:Local FIFO full correctly captured in packet");
    else begin
        $error("%m:Local FIFO full incorrectly captured in packet");
        process_error();
    end
    assert(channel_ctrl_inst.local_fifo_counter== local_fifo_counter_val) 
        $display("%m:Local FIFO counter correctly captured in packet");
    else begin
        $error("%m:Local FIFO counter incorrectly captured in packet");
        process_error();
    end
    $display("%m:local_fifo_half = %h, is_fifo_half = %h"
        ,channel_ctrl_inst.local_fifo_half, is_fifo_half);
    $display("%m:local_fifo_counter = %h, local_fifo_counter_val = %h",
        channel_ctrl_inst.local_fifo_counter, local_fifo_counter_val);
    repeat(burst_size - 5) sim_adc(dout);  
    is_fifo_half = channel_ctrl_inst.event_word_next[58];      
    is_fifo_full = channel_ctrl_inst.event_word_next[59];    
    local_fifo_counter_val = channel_ctrl_inst.event_word_next[31:28];   
    $display("%m:local FIFO full...");
    assert(channel_ctrl_inst.local_fifo_half == is_fifo_half) 
        $display("%m:Local FIFO half correctly captured in packet");
    else begin
        $error("%m:Local FIFO half incorrectly captured in packet");
        process_error();
    end
    assert(channel_ctrl_inst.local_fifo_full == is_fifo_full) 
        $display("%m:Local FIFO full correctly captured in packet");
    else begin 
        $error("%m:Local FIFO full incorrectly captured in packet");
        process_error();
    end
    assert(channel_ctrl_inst.local_fifo_counter== local_fifo_counter_val) 
        $display("%m:Local FIFO counter correctly captured in packet");
    else begin 
        $error("%m:Local FIFO counter incorrectly captured in packet");
        process_error();
    end
    $display("%m:local_fifo_half = %h, is_fifo_half = %h",
    channel_ctrl_inst.local_fifo_half, is_fifo_half);
    $display("%m:local_fifo_counter = %h, local_fifo_counter_val = %h",
    channel_ctrl_inst.local_fifo_counter, local_fifo_counter_val);
    if (test_failed) $display("FIFO diagnostics FAILED");
    else begin
        tests_passed++;
        $display("FIFO diagnostics test PASS");
    end
    // clean up
    fifo_drain_en = 1;
    $display("%m: FIFO needs to drain");
    repeat(4) sim_adc(250);
    end
endtask

//  Main stimulus – run all tests sequentially
initial begin
    // Give the design time to settle after reset
    wait (reset_n == 1);
    wait_clocks(25);

    // Run each test, clearing the packet queue before the next one
    test_natural_trigger();        pkt_queue.delete();
    test_external_trigger();       pkt_queue.delete();
    test_periodic_trigger();       pkt_queue.delete();
    test_periodic_veto();          pkt_queue.delete();
    test_hit_veto();               pkt_queue.delete();
    test_dynamic_reset();          pkt_queue.delete();
    test_digital_threshold();      pkt_queue.delete();
    test_adc_hold_delay();         pkt_queue.delete();
    test_adc_burst();              pkt_queue.delete();
    test_min_delta_adc();          pkt_queue.delete();
    test_mark_first_packet(.burst_size(12));  pkt_queue.delete();
    test_event_tally();            pkt_queue.delete();
    test_cds(.fail_test(1));       pkt_queue.delete();
    test_cds(.fail_test(0));       pkt_queue.delete();
    test_fifo_diagnostics();       pkt_queue.delete();

    $display("------- TESTING COMPLETE ----------");
    if (errors == 0)
        $display("\n%0d tests PASSED.\
        Time used = %0t us",tests_passed, $time/1e6);
    else
        $display("\nDUT failed test suite. %2d tests \
        passed. %0d errors detected. Time used = %0t us",
        tests_passed,errors,$time/1e6);
    end // begin

endmodule

