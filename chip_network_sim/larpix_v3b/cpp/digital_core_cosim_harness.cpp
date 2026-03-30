#include <bitset>
#include <array>
#include <cstdint>
#include <cstdlib>
#include <exception>
#include <iostream>
#include <stdexcept>
#include <sstream>
#include <string>

#include "analog_core_model.h"
#include "Vdigital_core.h"
#include "Vdigital_core___024root.h"
#include "verilated.h"

namespace {

using larpix::AnalogCoreModel;

constexpr vluint64_t kHalfPeriodTicks = 5;
constexpr uint8_t kDefaultChipId = 0x01;

// Config register addresses used by this co-simulation test.
enum ConfigAddr : std::size_t {
    CSA_ENABLE = 66,
    CHIP_ID = 122,
    DIGITAL = 123,
    ENABLE_PISO_DOWN = 125,
    ENABLE_POSI = 126,
    ENABLE_TRIG_MODES = 128,
    CHANNEL_MASK = 131,
};

struct HarnessConfig {
    uint64_t max_cycles = 400;
    uint64_t inject_cycle = 120;
    uint32_t inject_channel = 0;
    double inject_charge = -5.0e-15;
    uint8_t posi_idle = 0xF;
    bool verbose = false;
    bool inject_all_channels = false;
};

class DigitalCoreCosimHarness {
public:
    explicit DigitalCoreCosimHarness(const HarnessConfig& cfg)
        : cfg_(cfg) {
        Verilated::traceEverOn(false);
        dut_.clk = 0;
        dut_.reset_n = 0;
        dut_.external_trigger = 0;
        dut_.posi = cfg_.posi_idle & 0xF;
        clear_input_buses();
        analog_.reset();
    }

    int run() {
        try {
            for (uint64_t cycle = 0; cycle < cfg_.max_cycles; ++cycle) {
                step_cycle(cycle);
            }

            check_observed_event();
            expect(event_seen_, "no event packet observed after charge injection");
            if (cfg_.inject_all_channels) {
                expect(all_channel_hits_seen_,
                    "not all analog channels asserted hit after all-channels injection");
                if (!all_channel_packets_seen()) {
                    throw std::runtime_error(all_channel_packet_error());
                }
            }
            expect(hydra_fifo_loaded_, "Hydra FIFO never observed the local event");
            expect(tx_started_, "UART0 never asserted tx_busy after the local event");
            expect(uart_left_idle_, "UART0 never left the idle state after tx_busy asserted");

            std::cout
                << "PASS: digital_core_cosim_harness injected charge on "
                << (cfg_.inject_all_channels ? "all channels" : ("channel " + std::to_string(cfg_.inject_channel)))
                << " and observed a packet generated and launched toward TX"
                << '\n';
            if (cfg_.inject_all_channels) {
                std::cout << "seen_channels=" << seen_channels_summary() << '\n';
            }
            std::cout
                << "packet=0x" << std::hex << observed_event_ << std::dec << '\n'
                << "packet_type=" << (observed_event_ & 0x3u)
                << " chip_id=" << ((observed_event_ >> 2U) & 0xffU)
                << " channel_id=" << ((observed_event_ >> 10U) & 0x3fU)
                << " timestamp=" << ((observed_event_ >> 16U) & 0x0fffffffU)
                << " adc=" << ((observed_event_ >> 46U) & 0x3ffU)
                << " trigger_type=" << ((observed_event_ >> 56U) & 0x3U)
                << " downstream=" << ((observed_event_ >> 62U) & 0x1U)
                << " parity=" << ((observed_event_ >> 63U) & 0x1U)
                << '\n';
        } catch (const std::exception& ex) {
            std::cerr << "harness error: " << ex.what() << '\n';
            return 1;
        }
        return 0;
    }

private:
    // PASS requires all of the following:
    // 1. Reset/default config comes up correctly:
    //    - config_bits[CHIP_ID] == 0x01
    //    - config_bits[ENABLE_POSI][3:0] == 0xF
    //    - tx_enable remains 0 by default
    //    - sample returns high after reset on the monitored channel
    //      (channel 0 in all-channels mode)
    // 2. Direct config pokes must:
    //    - enable the injected channel, or all channels in all-channels mode
    //    - unmask the injected channel, or all channels in all-channels mode
    //    - disable trigger-mode modifiers that would interfere
    //    - enable downstream TX lane 0
    // 3. A charge pulse into the software analog model must:
    //    - produce a discriminator hit on the injected channel
    //      (or on all 64 channels in all-channels mode)
    //    - lead to a local event packet in digital_core.event_data/event_valid
    // 4. The observed event must satisfy packet checks:
    //    - packet type = data
    //    - chip ID = 0x01
    //    - channel ID = injected channel
    //      (or any valid channel ID when all channels are injected together)
    //    - ADC field = analog model ADC code captured for the emitted event
    //    - trigger type = natural
    //    - downstream bit set
    //    - parity bit matches payload parity
    // 5. The event must progress into the TX path:
    //    - Hydra FIFO / event buffer activity must be observed
    //    - UART0 tx_busy must assert
    //    - UART0 must leave idle on piso[0] or load a TX word

    void step_cycle(uint64_t cycle) {
        if (cycle == 40) {
            dut_.reset_n = 1;
        }

        prepare_analog_inputs(cycle);
        drive_digital_inputs_from_analog();
        tick();
        post_tick_checks(cycle);

        if (cfg_.verbose && (cycle % 25 == 0)) {
            std::cout << "cycle=" << cycle
                      << " sample=" << static_cast<int>((dut_.sample >> monitor_channel()) & 0x1u)
                      << " hit=" << static_cast<int>(analog_.outputs().hit.test(monitor_channel()))
                      << " done=" << static_cast<int>(analog_.outputs().done.test(monitor_channel()))
                      << " event_valid=" << static_cast<int>(root().digital_core__DOT__event_valid)
                      << " tx_busy0="
                      << static_cast<int>(root().digital_core__DOT__external_interface_inst__DOT____Vcellout__g_uart__BRA__0__KET____DOT__uart_inst__tx_busy)
                      << '\n';
        }
    }

    void clear_input_buses() {
        for (std::size_t i = 0; i < AnalogCoreModel::kDoutWordCount; ++i) {
            dut_.dout[i] = 0;
        }
        dut_.done = 0;
        dut_.hit = 0;
    }

    void prepare_analog_inputs(uint64_t cycle) {
        AnalogCoreModel::Inputs in{};
        in.threshold_global = static_cast<uint8_t>(dut_.threshold_global & 0xFFu);
        in.sample = qdata_to_bitset(dut_.sample);
        in.csa_reset = qdata_to_bitset(dut_.csa_reset);
        in.gated_reset = qdata_to_bitset(dut_.gated_reset);
        in.csa_bypass_enable = qdata_to_bitset(dut_.csa_bypass_enable);
        in.csa_bypass_select = qdata_to_bitset(dut_.csa_bypass_select);
        in.csa_monitor_select = qdata_to_bitset(dut_.csa_monitor_select);
        in.pixel_trim_dac = AnalogCoreModel::unpack_pixel_trim_words(
            &dut_.pixel_trim_dac[0],
            AnalogCoreModel::kPixelTrimWordCount);

        if (cycle == cfg_.inject_cycle) {
            if (cfg_.inject_all_channels) {
                for (std::size_t ch = 0; ch < AnalogCoreModel::kNumChannels; ++ch) {
                    in.charge_in_r[ch] = cfg_.inject_charge;
                }
            } else {
                if (cfg_.inject_channel >= AnalogCoreModel::kNumChannels) {
                    throw std::out_of_range("inject_channel out of range");
                }
                in.charge_in_r[cfg_.inject_channel] = cfg_.inject_charge;
            }
        }

        analog_.step(in);
        if (cycle >= cfg_.inject_cycle) {
            if (cfg_.inject_all_channels) {
                all_channel_hits_seen_ = all_channel_hits_seen_ || analog_.outputs().hit.all();
                analog_hit_seen_ = analog_hit_seen_ || analog_.outputs().hit.any();
            } else if (analog_.outputs().hit.test(cfg_.inject_channel)) {
                analog_hit_seen_ = true;
            }
        }
    }

    void drive_digital_inputs_from_analog() {
        const auto& out = analog_.outputs();
        const auto dout_words = out.pack_dout_words();
        for (std::size_t i = 0; i < dout_words.size(); ++i) {
            dut_.dout[i] = dout_words[i];
        }
        dut_.hit = out.pack_hit_bits();
        dut_.done = out.pack_done_bits();
    }

    static std::bitset<AnalogCoreModel::kNumChannels> qdata_to_bitset(uint64_t value) {
        return std::bitset<AnalogCoreModel::kNumChannels>(value);
    }

    Vdigital_core___024root& root() {
        return *dut_.rootp;
    }

    void post_tick_checks(uint64_t cycle) {
        if (!defaults_checked_ && cycle >= 80) {
            check_defaults();
            apply_test_config();
            defaults_checked_ = true;
        }

        if (defaults_checked_ && !config_checked_ && cycle >= 83) {
            check_test_config();
            config_checked_ = true;
        }

        if (root().digital_core__DOT__event_valid) {
            event_seen_ = true;
            observed_event_ = root().digital_core__DOT__event_data;
            const auto observed_channel = static_cast<std::size_t>((observed_event_ >> 10U) & 0x3fU);
            if (observed_channel < channel_packet_seen_.size()) {
                channel_packet_seen_.set(observed_channel);
            }
            expected_adc_ = analog_.outputs().dout[observed_channel];
        }

        if (root().digital_core__DOT__external_interface_inst__DOT__hydra_ctrl_inst__DOT__fifo_counter != 0
            || root().digital_core__DOT__external_interface_inst__DOT__hydra_ctrl_inst__DOT__priority_fifo_arbiter_inst__DOT__event_valid_buffer) {
            hydra_fifo_loaded_ = true;
        }

        if (root().digital_core__DOT__external_interface_inst__DOT____Vcellout__g_uart__BRA__0__KET____DOT__uart_inst__tx_busy) {
            tx_started_ = true;
        }

        if (tx_started_
            && (((dut_.piso & 0x1u) == 0u)
                || ((root().digital_core__DOT__external_interface_inst__DOT__ld_tx_data_uart & 0x1u) != 0u))) {
            uart_left_idle_ = true;
        }
    }

    void check_defaults() {
        expect(cfg_.inject_all_channels || cfg_.inject_channel < AnalogCoreModel::kNumChannels,
            "inject_channel out of range");
        expect(root().digital_core__DOT__config_bits[CHIP_ID] == kDefaultChipId,
            "default chip ID should load as 0x01");
        expect((root().digital_core__DOT__config_bits[ENABLE_POSI] & 0x0Fu) == 0x0Fu,
            "default POSI enables should load as 0xF");
        expect((dut_.tx_enable & 0x0Fu) == 0u,
            "TX lanes should be disabled by default");
        expect(((dut_.sample >> monitor_channel()) & 0x1u) == 1u,
            "sample should idle high after reset");
    }

    void apply_test_config() {
        auto& cfg_bits = root().digital_core__DOT__config_bits;
        if (cfg_.inject_all_channels) {
            for (std::size_t byte = 0; byte < 8; ++byte) {
                cfg_bits[CSA_ENABLE + byte] = 0xffu;
                cfg_bits[CHANNEL_MASK + byte] = 0x00u;
            }
        } else {
            cfg_bits[CSA_ENABLE + channel_byte_index()] = channel_bit_mask();
            cfg_bits[CHANNEL_MASK + channel_byte_index()] =
                static_cast<uint8_t>(0xffu & ~channel_bit_mask());
        }
        cfg_bits[ENABLE_TRIG_MODES] = 0x00;
        cfg_bits[DIGITAL] = 0x00;
        cfg_bits[ENABLE_PISO_DOWN] = 0x01;
    }

    void check_test_config() {
        expect((dut_.tx_enable & 0x0Fu) == 0x1u,
            "TX lane 0 should enable after config poke");
        if (cfg_.inject_all_channels) {
            for (std::size_t byte = 0; byte < 8; ++byte) {
                expect(root().digital_core__DOT__config_bits[CSA_ENABLE + byte] == 0xffu,
                    "all channels should be enabled after config poke");
                expect(root().digital_core__DOT__config_bits[CHANNEL_MASK + byte] == 0x00u,
                    "all channels should be unmasked after config poke");
            }
        } else {
            expect(((root().digital_core__DOT__config_bits[CSA_ENABLE + channel_byte_index()] >> channel_bit_index()) & 0x1u) == 1u,
                "injected channel should be enabled after config poke");
            expect(((root().digital_core__DOT__config_bits[CHANNEL_MASK + channel_byte_index()] >> channel_bit_index()) & 0x1u) == 0u,
                "injected channel should be unmasked after config poke");
        }
    }

    void check_observed_event() {
        expect(defaults_checked_, "default checks never ran");
        expect(config_checked_, "config checks never ran");
        expect(analog_hit_seen_, "software analog model never asserted a hit after charge injection");
        expect(event_seen_, "no local event packet observed");
        expect((observed_event_ & 0x3u) == 0x1u,
            "packet type should be DATA_OP");
        expect(((observed_event_ >> 2U) & 0xffU) == kDefaultChipId,
            "packet chip ID should match the default chip ID");
        if (cfg_.inject_all_channels) {
            expect(((observed_event_ >> 10U) & 0x3fU) < AnalogCoreModel::kNumChannels,
                "packet channel ID should be a valid channel when all channels are injected");
        } else {
            expect(((observed_event_ >> 10U) & 0x3fU) == cfg_.inject_channel,
                "packet channel ID should match the injected channel");
        }
        expect(((observed_event_ >> 46U) & 0x3ffU) == expected_adc_,
            "packet ADC field should match the analog model ADC code");
        expect(((observed_event_ >> 56U) & 0x3u) == 0u,
            "packet trigger type should be natural");
        expect(((observed_event_ >> 62U) & 0x1u) == 1u,
            "packet downstream flag should be set");
        expect(check_parity(observed_event_),
            "packet parity bit does not match payload parity");
    }

    static bool check_parity(uint64_t packet) {
        const uint64_t payload = packet & ((1ULL << 63U) - 1ULL);
        const bool parity_bit = ((packet >> 63U) & 0x1u) != 0;
        return parity_bit == !has_odd_parity(payload);
    }

    bool all_channel_packets_seen() const {
        return channel_packet_seen_.all();
    }

    std::string all_channel_packet_error() const {
        std::ostringstream oss;
        oss << "not all channels produced observed event packets in all-channels mode; seen="
            << channel_packet_seen_.count() << "/" << AnalogCoreModel::kNumChannels
            << " missing=";
        bool first = true;
        for (std::size_t ch = 0; ch < AnalogCoreModel::kNumChannels; ++ch) {
            if (!channel_packet_seen_.test(ch)) {
                if (!first) oss << ',';
                oss << ch;
                first = false;
            }
        }
        return oss.str();
    }

    std::string seen_channels_summary() const {
        std::ostringstream oss;
        bool first = true;
        for (std::size_t ch = 0; ch < AnalogCoreModel::kNumChannels; ++ch) {
            if (channel_packet_seen_.test(ch)) {
                if (!first) oss << ',';
                oss << ch;
                first = false;
            }
        }
        return oss.str();
    }

    std::size_t monitor_channel() const {
        return cfg_.inject_all_channels ? 0u : static_cast<std::size_t>(cfg_.inject_channel);
    }

    static bool has_odd_parity(uint64_t value) {
        bool parity = false;
        while (value != 0) {
            parity = !parity;
            value &= (value - 1ULL);
        }
        return parity;
    }

    static void expect(bool condition, const std::string& message) {
        if (!condition) {
            throw std::runtime_error(message);
        }
    }

    uint8_t channel_bit_mask() const {
        return static_cast<uint8_t>(1u << channel_bit_index());
    }

    uint8_t channel_bit_index() const {
        return static_cast<uint8_t>(cfg_.inject_channel % 8u);
    }

    std::size_t channel_byte_index() const {
        return cfg_.inject_channel / 8u;
    }

    void tick() {
        main_time_ += kHalfPeriodTicks;
        dut_.clk = 0;
        dut_.eval();
        main_time_ += kHalfPeriodTicks;
        dut_.clk = 1;
        dut_.eval();
    }

    HarnessConfig cfg_;
    Vdigital_core dut_{};
    AnalogCoreModel analog_{};
    vluint64_t main_time_ = 0;
    bool defaults_checked_ = false;
    bool config_checked_ = false;
    bool analog_hit_seen_ = false;
    bool all_channel_hits_seen_ = false;
    bool event_seen_ = false;
    bool hydra_fifo_loaded_ = false;
    bool tx_started_ = false;
    bool uart_left_idle_ = false;
    std::bitset<AnalogCoreModel::kNumChannels> channel_packet_seen_{};
    uint64_t observed_event_ = 0;
    uint16_t expected_adc_ = 0;
};

HarnessConfig parse_args(int argc, char** argv) {
    HarnessConfig cfg;
    bool cycles_set = false;
    for (int i = 1; i < argc; ++i) {
        const std::string arg = argv[i];
        if (arg == "--cycles" && i + 1 < argc) {
            cfg.max_cycles = std::strtoull(argv[++i], nullptr, 0);
            cycles_set = true;
        } else if (arg == "--inject-cycle" && i + 1 < argc) {
            cfg.inject_cycle = std::strtoull(argv[++i], nullptr, 0);
        } else if (arg == "--inject-channel" && i + 1 < argc) {
            cfg.inject_channel = static_cast<uint32_t>(std::strtoul(argv[++i], nullptr, 0));
        } else if (arg == "--inject-charge" && i + 1 < argc) {
            cfg.inject_charge = std::strtod(argv[++i], nullptr);
        } else if (arg == "--posi-idle" && i + 1 < argc) {
            cfg.posi_idle = static_cast<uint8_t>(std::strtoul(argv[++i], nullptr, 0));
        } else if (arg == "--inject-all-channels") {
            cfg.inject_all_channels = true;
        } else if (arg == "--verbose") {
            cfg.verbose = true;
        } else {
            throw std::invalid_argument("unknown argument: " + arg);
        }
    }
    if (cfg.inject_all_channels && !cycles_set && cfg.max_cycles < 5000) {
        cfg.max_cycles = 5000;
    }
    return cfg;
}

} // namespace

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    try {
        const HarnessConfig cfg = parse_args(argc, argv);
        DigitalCoreCosimHarness harness(cfg);
        return harness.run();
    } catch (const std::exception& ex) {
        std::cerr << "fatal: " << ex.what() << '\n';
        return 1;
    }
}
