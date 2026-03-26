///////////////////////////////////////////////////////////////////
// File Name: channel_ctrl.sv
// Engineer:  Carl Grace (crgrace@lbl.gov)
//
// Description: Simplified Channel Controller with 4 states
//              (including wait state) – now also supports a
//              “min‑delta‑ADC” reset condition, a 2‑bit event tally,
//              Correlated‑Double‑Sampling (cds_mode), and a hit‑veto.
//
// The CDS changes below implement the required behaviour:
//   * When `cds_mode` is high a *reset* packet is emitted immediately
//     after the controller returns to IDLE.
//   * The reset packet does **not** count toward `adc_burst_length`.
//   * The reset packet has both the CDS‑mode bit (45) and the CDS‑reset
//     marker bit (44) set.
//   * `enable_hit_veto` does not abort the reset packet.
//   * `mark_first_packet` applies only to the first *data* packet of a
//     burst, not to the reset packet.
///////////////////////////////////////////////////////////////////

module channel_ctrl
    #(parameter int unsigned WIDTH = 64,               // 64‑bit packet (no parity)
      parameter int unsigned LOCAL_FIFO_DEPTH = 8,      // per‑channel FIFO depth
      parameter int unsigned TS_LENGTH = 28)           // timestamp length
    // ------------------- Outputs -------------------
    (output logic [WIDTH-2:0] channel_event,        // packet presented to the FIFO
     output logic csa_reset,        // active‑high CSA reset pulse
     output logic fifo_empty,       // FIFO empty flag (placeholder)
     output logic triggered_natural,    // high to indicate valid hit
     output logic sample,               // pulse / hold to start ADC

    // ------------------- Inputs --------------------
     input logic clk,
     input logic reset_n,              // async active‑low
     input logic channel_enabled,
     input logic hit,                  // discriminator fire
     input logic read_local_fifo_n,
     input logic external_trigger,
     input logic cross_trigger,
     input logic periodic_trigger,
     input logic periodic_reset,
     input logic channel_mask,
     input logic external_trigger_mask,
     input logic adc_wait,
     input logic cross_trigger_mask,
     input logic periodic_trigger_mask,
     input logic enable_periodic_trigger_veto,
     input logic enable_hit_veto,      // NEW: enable hit‑veto
     input logic [TS_LENGTH-1:0] timestamp,          // timestamp captured on hit
     input logic [9:0] dout,                // ADC result
     input logic done, // ADC conversion complete (high when idle)
     input logic [2:0] reset_length,        // CSA‑reset length (cycles)
     input logic [7:0] chip_id,             // identifier of the chip
     input logic [5:0] channel_id,          // identifier of the channel

    // ----- Configuration inputs -----------------------------------------
     input logic [9:0] digital_threshold,   // digital‑threshold for FIFO write
     input logic threshold_polarity,  // 1 = >threshold, 0 = <threshold
     input logic enable_dynamic_reset,
     input logic [9:0] dynamic_reset_threshold,
     input logic [7:0] adc_burst_length,    // number of conversions per hit
     input logic mark_first_packet,   // flag marks the first burst packet
     input logic [7:0] adc_hold_delay,      // sampling‑hold length (0‑255 cycles)

    // ----- min‑delta‑ADC ------------------------------------
     input logic enable_min_delta_adc,
     input logic [9:0] min_delta_adc,
    // ----- event‑tally ---------------------------------------
     input logic enable_tally,        // packet bits [61:60] carry tally

    // ----- CDS mode --------------------------------------------
     input logic cds_mode,            // 1 = Correlated‑Double‑Sampling

    // ----- local fifo diagnostics -------------------------------
     input logic enable_local_fifo_diagnostics);

// ----------------------------------------------------------------
// State machine (3 states – WAIT_STATE removed)
// ----------------------------------------------------------------
typedef enum logic [1:0] {
    IDLE           = 2'b00,         // waiting for trigger (or CDS reset)
    SAMPLE         = 2'b01,         // hold `sample` then wait for `done`
    SAMPLE_CONVERT = 2'b10} state_e; // build packet / write FIFO

state_e State, Next; // define state machine

// ----------------------------------------------------------------
// Trigger signals
// ----------------------------------------------------------------
logic triggered_external;
logic triggered_cross;
logic triggered_periodic;
logic triggered_channel;
logic [1:0] trigger_type;       // 00:natural, 01:ext, 10:cross, 11:periodic
logic [1:0] trigger_type_latched, trigger_type_latched_next;

// ----------------------------------------------------------------
// Registers / next‑value declarations
// ----------------------------------------------------------------
logic [7:0]  reset_counter, reset_counter_next;
logic [WIDTH-2:0] event_word, event_word_next;

// packet building
logic [TS_LENGTH-1:0] timestamp_reg, timestamp_next, ts_for_pkt;
logic first_packet;

// burst‑mode counter
logic [7:0] burst_counter, burst_counter_next;
logic [7:0] burst_limit;

// hold‑delay logic (sample pulse stretching)
logic sample_load, sample_load_next; // request to start a new sample (conversion)
logic [7:0] sample_hold_len;     // calculated hold length (0‑255)
logic [7:0] sample_hold_counter, sample_hold_counter_next;

// previous ADC word (needed for min‑delta detection)
logic [9:0] prev_adc, prev_adc_next;
logic delta_condition;

// 2‑bit event tally
logic [1:0] event_tally, event_tally_next;

// dynamic‑reset helpers
logic dyn_reset_ok;
logic finished_burst;

// periodic‑reset helper
logic periodic_reset_triggered, periodic_reset_next;

// CDS helpers / flags
logic is_reset_packet;   // true for the *reset* packet
logic cds_reset_pending, cds_reset_pending_next; // next is reset packet
logic cds_reset_captured, cds_reset_captured_next; //reset packet been scheduled?

// output registers (registered outputs)
logic write_local_fifo_n, write_local_fifo_n_next;  // active‑low FIFO write
logic csa_reset_next;

// Edge‑detect registers for `done`
logic done_prev, done_prev_next;           // previous value of `done`
logic done_rise_flag, done_rise_flag_next; // extra‑wait cycle when adc_wait=1

// Local derandomising FIFO diagnostics
logic local_fifo_half;
logic local_fifo_full;
logic [3:0] local_fifo_counter;

// Packet builder (no parity, no thresholds)
function automatic logic [WIDTH-2:0] build_packet(
    input logic [TS_LENGTH-1:0] ts,
    input logic [9:0]           adc);
    logic [WIDTH-2:0] pkt;
    pkt = '0;
    pkt[1:0]    = 2'b01;                // data‑packet identifier
    pkt[9:2]    = chip_id;              // 8‑bit chip ID
    pkt[15:10]  = channel_id;           // 6‑bit channel ID
    pkt[43:16]  = ts[27:0];             // 28 LSBs of timestamp
    pkt[55:46]  = adc;                  // 10‑bit ADC word
    pkt[57:56]  = trigger_type_latched; // trigger type
    // embed local‑fifo diagnostics
    pkt[58] = local_fifo_half;
    pkt[59] = local_fifo_full;
    if (enable_local_fifo_diagnostics) pkt[31:28] = local_fifo_counter;
    // embed event‑tally (if enabled)
    if (enable_tally) pkt[61:60] = event_tally_next;
        pkt[62]     = 1'b1;                 // downstream = TRUE
        return pkt;
endfunction

// ----------------------------------------------------------------
// Trigger logic (combinational)
// ----------------------------------------------------------------
always_comb begin
    triggered_natural   = channel_enabled & hit & ~channel_mask;
    triggered_external  = (external_trigger & ~external_trigger_mask);
    triggered_cross     = (cross_trigger & ~cross_trigger_mask);
    triggered_periodic  = (periodic_trigger & ~periodic_trigger_mask
                           & ~(hit & enable_periodic_trigger_veto)
                           & (State == IDLE));
    triggered_channel   = channel_enabled &
                          (triggered_natural | triggered_external |
                           triggered_cross | triggered_periodic);

    // Encode trigger type (2‑bit)
    case ({triggered_natural,triggered_external,
           triggered_cross,triggered_periodic})
        4'b1000: trigger_type = 2'b00; // natural
        4'b0100: trigger_type = 2'b01; // external
        4'b0010: trigger_type = 2'b10; // cross
        4'b0001: trigger_type = 2'b11; // periodic
        default: trigger_type = 2'b00;
    endcase
end

// Combinational next‑state / next‑value logic
always_comb begin
    // Default assignments – hold current values
    Next                       = State;
    sample_load_next           = 1'b0;
    write_local_fifo_n_next    = 1'b1;                // inactive (active‑low)
    reset_counter_next         = reset_counter;        // may be decremented later
    event_word_next            = event_word;
    timestamp_next             = timestamp_reg;
    trigger_type_latched_next  = trigger_type_latched;
    burst_counter_next         = burst_counter;
    sample_hold_counter_next   = sample_hold_counter;
    prev_adc_next              = prev_adc;
    event_tally_next           = event_tally;
    cds_reset_pending_next     = cds_reset_pending;
    cds_reset_captured_next    = cds_reset_captured;
    is_reset_packet            = cds_mode && cds_reset_pending;
    dyn_reset_ok               = 1'b0;
    finished_burst             = 1'b0;
    delta_condition            = 1'b0;
    ts_for_pkt                 = '0;
    first_packet               = 1'b0;
    periodic_reset_next        = periodic_reset_triggered;

    // Preserve edge‑detect registers unless we explicitly change them
    done_prev_next             = done;                 // capture current `done`
    done_rise_flag_next        = done_rise_flag;       // hold unless we set it

    // Compute hold length (0 - 255 cycles)
    sample_hold_len = (adc_hold_delay == 0) ? 8'd1 : adc_hold_delay;

    // Burst limit (minimum 1 conversion)
    burst_limit = (adc_burst_length <= 8'd1) ? 8'd1 : adc_burst_length;


    // CSA‑reset counter (count‑down)
    if (reset_counter != 0)
        reset_counter_next = reset_counter - 1'b1;

    // FSM
    case (State)

        // IDLE – `sample` line is HIGH, waiting for a trigger.
        //        In CDS mode we first emit a *reset* packet.
        IDLE: begin
            // Clear counters that are only used while sampling
            burst_counter_next      = 8'd0;
            sample_hold_counter_next = 8'd0;

            //  CDS‑reset packet has priority ***
            if (cds_mode && !cds_reset_captured) begin
                // Schedule the reset packet
                Next                     = SAMPLE;
                sample_load_next         = 1'b1;    // start conversion
                cds_reset_pending_next   = 1'b1; // this will be the reset packet
                cds_reset_captured_next  = 1'b1; // remember reset scheduled it
                // No trigger type is latched for a reset packet
            end
            //  Normal trigger (hit or external) ***
            else if (triggered_channel) begin
                Next                     = SAMPLE;
                sample_load_next         = 1'b1;      // start conversion
                trigger_type_latched_next = trigger_type; // capture trigger type
                // Ensure any previous CDS‑reset flags are cleared
                cds_reset_pending_next   = 1'b0;
            end
            //  Periodic reset 
            else if (periodic_reset)
                periodic_reset_next = 1'b1;
        end

        // SAMPLE – hold `sample` for the programmed delay,
        //          then wait for ADC `done`.  Hit‑veto is ignored
        //          for CDS-reset packets.
        SAMPLE: begin
            // ---- Hit-veto handling (only for normal data packets) ----
                if (enable_hit_veto && !hit && 
                        !cds_mode && (trigger_type_latched == 2'b00)) begin
                // Abort the acquisition – go back to IDLE
                Next                     = IDLE;
                sample_load_next         = 1'b0;
                sample_hold_counter_next = 8'd0;
                cds_reset_pending_next   = 1'b0;
                end else begin
                    // ---- Hold period (sample stays asserted) ----
                    if (sample_hold_counter != 8'd0)
                        // Still within the hold window
                        Next = SAMPLE;
                    else begin
                        // Hold finished – now monitor `done`
                        if (!done_rise_flag) begin
                            // Waiting for the rising edge of `done`
                            if (done && !done_prev) begin
                                // Rising edge detected
                                if (adc_wait) begin
                  //need one extra cycle before conversion is considered finished
                                    done_rise_flag_next = 1'b1;
                                    Next = SAMPLE;          // stay one more cycle
                                end else
                       // No extra wait – move straight to conversion handling
                                    Next = SAMPLE_CONVERT;
                            end else
                                // Still waiting for the rising edge
                                Next = SAMPLE;
                        end else begin
                      // Extra‑wait cycle finished – now go to conversion handling
                            Next = SAMPLE_CONVERT;
                            done_rise_flag_next = 1'b0; // clear flag for next conv
                        end
                    end
                end
            end

        // SAMPLE_CONVERT – build packet, write FIFO, handle burst logic
        SAMPLE_CONVERT: begin
            // ----- first‑packet detection (timestamp‑MSB) -----
            // The timestamp MSB is set only for the first *data* packet,
            // not for the CDS‑reset packet.
            first_packet = mark_first_packet &&
                           (!is_reset_packet) && (burst_counter == 8'd0);

            // ----- Timestamp for the packet -------------------
            ts_for_pkt = timestamp_reg;
            if (first_packet)
                ts_for_pkt[TS_LENGTH-1] = 1'b1;   // set MSB of timestamp

            // ----- Event tally (increment for every packet) ------------
            if (enable_tally)
                event_tally_next = event_tally + 2'b01;

            // ----- Digital‑threshold / forced‑write for reset packet -----
            if (is_reset_packet) begin
                // Reset packet is always written, regardless of threshold
                event_word_next = build_packet(ts_for_pkt, dout);
                write_local_fifo_n_next = 1'b0;
            end else begin
                // Normal threshold‑gated write
                if (threshold_polarity) begin
                    if (dout > digital_threshold) begin
                        event_word_next = build_packet(ts_for_pkt, dout);
                        write_local_fifo_n_next = 1'b0;
                    end
                end else begin
                    if (dout <= digital_threshold) begin
                        event_word_next = build_packet(ts_for_pkt, dout);
                        write_local_fifo_n_next = 1'b0;
                    end
                end
            end

            // ----- CDS flag bits ------------------------------------------------
            if (cds_mode) begin
                event_word_next[45] = 1'b1;               // “CDS” indicator
                event_word_next[44] = is_reset_packet;   // reset‑packet marker
            end

            // ----- Dynamic‑reset condition (data packets only) ----------
            if (!is_reset_packet) begin
                if (threshold_polarity)
                    dyn_reset_ok = (dout > dynamic_reset_threshold) ? 1'b1 : 1'b0;
                else
                    dyn_reset_ok = (dout < dynamic_reset_threshold) ? 1'b1 : 1'b0;
            end

            // ----- Min‑delta‑ADC condition (data packets only) ---------
            if (!is_reset_packet && enable_min_delta_adc &&
                 !enable_dynamic_reset) begin
                if (burst_counter != 8'd0) begin
                    if (threshold_polarity) begin
                        if (dout >= prev_adc)
                            delta_condition = ((dout - prev_adc) < min_delta_adc);
                    end else
                        if (dout <= prev_adc)
                                delta_condition = ((prev_adc - dout) < min_delta_adc);
                end
            end

            // ----- Increment burst counter (data packets only) ----------
            if (is_reset_packet) begin
                // The reset packet does not count toward the burst length.
                burst_counter_next = 8'd0;   // start a fresh burst afterwards
                 // clear the “next‑conversion‑is‑reset” flag
                //and  allow a new reset packet after the next burst
                cds_reset_pending_next = 1'b0;
                cds_reset_captured_next = 1'b0;
            end else
                burst_counter_next = burst_counter + 8'd1;

            // ----- Store previous ADC (data packets only) ---------------
            prev_adc_next = (is_reset_packet) ? prev_adc : dout;

            // ----- Determine if the burst is finished --------------------
            finished_burst = (enable_dynamic_reset && dyn_reset_ok) ||
                             (enable_min_delta_adc && delta_condition) ||
                             (burst_counter_next >= burst_limit);

            if (finished_burst) begin
                // Initiate CSA reset and go back to IDLE
                reset_counter_next = reset_length;
                Next               = IDLE;
            end else begin
   // Need another conversion – go back to SAMPLE and request a new sample pulse
                Next               = SAMPLE;
                sample_load_next   = 1'b1;
            end
        end

    default: Next = IDLE;
    endcase

    // Latch timestamp on every new sample request
    if (sample_load_next)
        timestamp_next      = timestamp;   // capture current timestamp

    // Hold‑counter handling (stretch sample pulse)
    if (sample_load_next)
    sample_hold_counter_next = sample_hold_len; // load programmed length
    else if (sample_hold_counter != 8'd0)
        sample_hold_counter_next = sample_hold_counter - 1'b1;// count down
    // CSA‑reset output (derived from the *next* counter)
    csa_reset_next = (reset_counter_next != 0) || periodic_reset_triggered;
end // always_comb

// Sequential (clocked) block – registers update
always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        State                     <= IDLE;
        write_local_fifo_n        <= 1'b1;
        reset_counter             <= '0;
        event_word                <= '0;
        timestamp_reg             <= '0;
        trigger_type_latched      <= '0;
        burst_counter             <= '0;
        sample_load               <= 1'b0;
        sample_hold_counter       <= 8'd0;
        prev_adc                  <= 10'd0;
        periodic_reset_triggered  <= 1'b0;
        event_tally               <= 2'b00;
        cds_reset_pending         <= 1'b0;
        cds_reset_captured        <= 1'b0;
        done_prev                 <= 1'b0;
        done_rise_flag            <= 1'b0;
        sample                    <= 1'b0; //TP: sample low on reset
        csa_reset                 <= 1'b0; //TP: csa_reset low on reset
    end else begin
        State                     <= Next;
        // `sample` is high in IDLE (required by ADC) or
        // while the hold counter is non‑zero.
        sample       <= (Next == IDLE) || (sample_hold_counter_next != 8'd0);
        write_local_fifo_n        <= write_local_fifo_n_next;
        csa_reset                 <= csa_reset_next;
        reset_counter             <= reset_counter_next;
        event_word                <= event_word_next;
        timestamp_reg             <= timestamp_next;
        trigger_type_latched      <= trigger_type_latched_next;
        burst_counter             <= burst_counter_next;
        sample_load               <= sample_load_next;
        sample_hold_counter       <= sample_hold_counter_next;
        prev_adc                  <= prev_adc_next;
        periodic_reset_triggered  <= periodic_reset_next;
        event_tally               <= event_tally_next;
        cds_reset_pending         <= cds_reset_pending_next;
        cds_reset_captured        <= cds_reset_captured_next;
        done_prev                 <= done_prev_next;
        done_rise_flag            <= done_rise_flag_next;
    end
end // always_ff

// Local derandomising FIFO 
fifo_latch #(
    .FIFO_WIDTH (WIDTH-1),                 // parity bit stripped
    .FIFO_DEPTH (LOCAL_FIFO_DEPTH),
    .FIFO_BITS  ($clog2(LOCAL_FIFO_DEPTH)))
fifo_inst (
    .data_out       (channel_event),           // to the shared FIFO
    .fifo_counter   (local_fifo_counter),
    .fifo_full      (local_fifo_full),
    .fifo_half      (local_fifo_half),
    .fifo_empty     (fifo_empty),              // output port of this module
    .data_in        (event_word),   
    .read_n         (read_local_fifo_n),       // active‑low read request
    .write_n        (write_local_fifo_n),      // active‑low write request
    .clk            (clk),
    .reset_n        (reset_n));
endmodule
