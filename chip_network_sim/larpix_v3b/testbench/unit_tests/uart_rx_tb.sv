`timescale 1ns/1ps
module uart_rx_tb;

    // ----------------------------------------------------------------
    // 1.  Declarations – everything is placed here, before any code
    // ----------------------------------------------------------------
    // ----------------------------------------------------------------
    // Parameters
    // ----------------------------------------------------------------
    localparam int WIDTH= 64;          // payload width of the DUT
    localparam real CLK_PERIOD = 200.0;        // 5 MHz system clock (200 ns)
    localparam int  MAX_JITTER = 50;          // max skew for the “skew” test (ns)

    // ----------------------------------------------------------------
    // DUT interface signals
    // ----------------------------------------------------------------
    logic                     clk;
    logic                     reset_n;
    logic                     rx_in;           // asynchronous serial line
    logic                     uld_rx_data;     // host‑read pulse
    logic [WIDTH-1:0]        rx_data;          // word presented by DUT
    logic                     rx_empty;        // 1 = buffer empty, 0 = data ready

    // ----------------------------------------------------------------
    // Test‑bench internal variables
    // ----------------------------------------------------------------
    int                       test_err_cnt;    // counts failures

    // ----------------------------------------------------------------
    // 2.  Helper tasks – each stimulus scenario is a separate task
    // ----------------------------------------------------------------

    // Pulse the host‑read signal for exactly one clock cycle
    task automatic pulse_uld();
        @(posedge clk);
        uld_rx_data = 1'b1;
        @(posedge clk);
        uld_rx_data = 1'b0;
    endtask

// Wait for N clock cycles
task automatic wait_clocks (input int n);
    repeat (n) @(posedge clk);
endtask

    // Transmit a word LSB‑first, start = 0, stop = 1.
    // idle_cycles : number of full clock periods the line stays high
    // before the start bit.
    // max_jitter  : max extra delay (in ns) added after each negative‑edge transition
    //               to model skew/skew between the TX and the RX clocks.
    task automatic tx_word(
        input logic [WIDTH-1:0] word,
        input int               idle_cycles = 5,
        input int               max_jitter  = 0
    );
        // --- idle (line high) -----------------------------------------
        repeat (idle_cycles) @(posedge clk) rx_in <= 1'b1;

        // --- start bit (0) -------------------------------------------
        @(negedge clk) begin
            if (max_jitter) #($urandom_range(0, max_jitter)) ;
            rx_in <= 1'b0;
        end

        // --- data bits, LSB first ------------------------------------
        for (int i = 0; i < WIDTH; i++) begin
            @(negedge clk) begin
                if (max_jitter) #($urandom_range(0, max_jitter)) ;
                rx_in <= word[i];
            end
        end

        // --- stop bit (1) -------------------------------------------
        @(negedge clk) begin
            if (max_jitter) #($urandom_range(0, max_jitter)) ;
            rx_in <= 1'b1;
        end

        // Hold the line high for at least one full clock after the stop bit
        @(posedge clk);
    endtask

    // Create a short‑duration low glitch while the line is idle.
    // The glitch is shorter than a full clock period and should be filtered out.
    task automatic tx_glitch();
        // make sure we start from idle high
        @(posedge clk) rx_in <= 1'b1;
        // low pulse lasting half a clock (or shorter)
        # (CLK_PERIOD/4) rx_in <= 1'b0;
        # (CLK_PERIOD/4) rx_in <= 1'b1;
        // keep high for a full clock before leaving the task
        @(posedge clk);
    endtask

    // ----------------------------------------------------------------
    // 3.  Individual test cases
    // ----------------------------------------------------------------

    // 3.1  Normal single packet
    task automatic test_normal_packet();
        logic [WIDTH-1:0] payload;
        payload = {$urandom, $urandom};        // 64‑bit random word
        tx_word(payload);                      // default idle & no jitter

        // Wait until the DUT flags a word as ready
        wait (!rx_empty);
        assert (rx_data == payload) 
            $display("%m: NORMAL PACKET expected %h, got %h PASS", payload, rx_data);
        else begin
            $error("%m: NORMAL PACKET expected %h, got %h FAIL", payload, rx_data);
            test_err_cnt++;
        end 

        // Host reads the word
        pulse_uld();
        // After the read the buffer must be empty again
        wait (rx_empty);
    endtask

    // 3.2  Double‑buffering test – second packet arrives before the first is read
    task automatic test_double_buffer();
        logic [WIDTH-1:0] pkt1, pkt2;
        pkt1 = {$urandom, $urandom};
        pkt2 = {$urandom, $urandom};

        // Send first packet
        tx_word(pkt1);
        wait (!rx_empty);                     // primary buffer now holds pkt1

        // Immediately send second packet (no read yet)
        tx_word(pkt2);
        // Primary should still contain pkt1; hold buffer now contains pkt2
        assert (rx_data == pkt1) 
            $display("%m:DOUBLE BUFFER: after read, expected %h, got %h PASS",
                pkt1, rx_data); 
        else begin
            $error("%m:DOUBLE BUFFER  primary corrupted, got %h, expected %h FAIL", 
            rx_data, pkt1);
            test_err_cnt++;
        end
        wait_clocks(2);
        // Read first packet – hold buffer should move to primary
        pulse_uld();
        wait_clocks(1);
        assert (rx_data == pkt2)
            $display("%m:DOUBLE BUFFER: after read, expected %h, got %h PASS",
                pkt2, rx_data); 
        else begin
            $error("%m:DOUBLE BUFFER after read, expected %h, got %h FAIL",
            pkt2, rx_data);
            test_err_cnt++;
        end

        // Read second packet
        pulse_uld();
        wait (rx_empty);
    endtask

    // 3.3  Back‑to‑back packets with zero idle time between them
    task automatic test_back_to_back_no_idle();
        logic [WIDTH-1:0] p1, p2;
        p1 = {$urandom, $urandom};
        p2 = {$urandom, $urandom};

        // Send first packet, then immediately the second one
        tx_word(p1, 0);   // idle_cycles = 0
        tx_word(p2, 0);
        // First packet should be available first
        wait (!rx_empty);
        assert (rx_data == p1) 
            $display("%m:Back2Back (No idle): 1st packet got %h, expected %h", 
                rx_data, p1);
        else begin
            $error("%m:B2B NO IDLE: first packet mismatch, got %h, expected %h", 
            rx_data, p1);
            test_err_cnt++;
        end
        pulse_uld();       // read first
        // Second packet should appear next
        wait_clocks(1);
        wait (!rx_empty);
        assert (rx_data == p2) 
            $display("%m: Back2Back (No idle): \
                got %h as expected PASS", rx_data);
        else begin
            $error("%m: Back2Back NO IDLE: second packet mismatch, got %h,\
                 expected %h FAIL", rx_data, p2);
            test_err_cnt++;
        end
        pulse_uld();
        wait (rx_empty);
    endtask

    // 3.4  Glitch on the line – should not be interpreted as a start bit
    task automatic test_glitch_start();
        tx_glitch();                     // short low pulse while line is idle
        // Wait a few cycles – the DUT must still indicate empty
        repeat (5) @(posedge clk);
        assert (uart_rx_inst.rx_empty) 
            $display("%m: GLITCH TEST OK no false start detected PASS");
        else begin   
                $error("%m: GLITCH: receiver falsely detected a packet FAIL");
                test_err_cnt++;
        end 
    endtask

    // 3.5  Skewed transmission – random jitter (up to MAX_JITTER ns) on each bit
    task automatic test_skewed_transmission();
        logic [WIDTH-1:0] payload;
        payload = {$urandom, $urandom};
        tx_word(payload, 5, MAX_JITTER);   // idle = 5 cycles, jitter = MAX_JITTER ns
        wait (!rx_empty);
        assert (rx_data == payload)
                $display("%m: SKEWED TRANSMISSION PASS:  expected %h, got %h",
                     payload, rx_data);  
            else begin
                $error("%m: SKEWED TRANSMISSION FAIL:  expected %h, got %h",
                    payload, rx_data);
                test_err_cnt++;
            end 
        pulse_uld();
        wait (rx_empty);
    endtask

    // 4.  Clock generation and reset
    // Simple free‑running clock
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // Reset sequence
    initial begin
        reset_n   = 1'b1;
        wait_clocks(2);
        reset_n     = 1'b0;
        rx_in     = 1'b1;       // line idle high
        uld_rx_data = 1'b0;
        test_err_cnt = 0;
        wait_clocks(100);
        reset_n   = 1'b1;
    end

    // 5.  DUT instantiation
    uart_rx #(.WIDTH(WIDTH)) uart_rx_inst (
        .rx_data    (rx_data),
        .rx_empty   (rx_empty),
        .rx_in      (rx_in),
        .uld_rx_data(uld_rx_data),
        .clk        (clk),
        .reset_n    (reset_n)
    );

    // ----------------------------------------------------------------
    // 6.  Main test sequence 
    // ----------------------------------------------------------------
    initial begin
        // Wait until reset is de‑asserted
        @(negedge reset_n);
        @(posedge reset_n);
        // Give the DUT a few extra clocks after reset
        repeat (5) @(posedge clk);

        // Run the individual tests
        test_normal_packet();
        test_double_buffer();
        test_back_to_back_no_idle();
        test_glitch_start();
        test_skewed_transmission();

        // ----------------------------------------------------------------
        // Summary
        // ----------------------------------------------------------------
        if (test_err_cnt == 0) begin
            $display("\n********** ALL UART RX TESTS PASSED **********\n");
        end else begin
            $error("\n********** %0d TEST(S) FAILED **********\n", test_err_cnt);
        end
    end

endmodule
