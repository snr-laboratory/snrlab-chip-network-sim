#include <bitset>
#include <cstdint>
#include <cstdlib>
#include <exception>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

#include "analog_core_model.h"
#include "Vdigital_core.h"
#include "Vdigital_core___024root.h"
#include "verilated.h"

namespace {

using larpix::AnalogCoreModel;

constexpr vluint64_t kHalfPeriodTicks = 5;
constexpr uint8_t kDefaultChipId = 0x01;
constexpr std::size_t kNumChannels = AnalogCoreModel::kNumChannels;
constexpr std::size_t kHalfChannels = kNumChannels / 2;

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
    uint64_t max_cycles = 6000;
    uint64_t first_inject_cycle = 120;
    uint64_t second_inject_cycle = 240; // 120 cycles after the first injection.
    double inject_charge = -5.0e-15;
    uint8_t posi_idle = 0xF;
    bool verbose = false;
};

class DigitalCoreCosimOrderHarness {
public:
    explicit DigitalCoreCosimOrderHarness(const HarnessConfig& cfg)
        : cfg_(cfg) {
        Verilated::traceEverOn(false);
        dut_.clk = 0;
        dut_.reset_n = 0;
        dut_.external_trigger = 0;
        dut_.posi = cfg_.posi_idle & 0xF;
        clear_input_buses();
        analog_.reset();
        expected_order_.reserve(kNumChannels);
        for (std::size_t ch = kHalfChannels; ch < kNumChannels; ++ch) {
            expected_order_.push_back(ch);
        }
        for (std::size_t ch = 0; ch < kHalfChannels; ++ch) {
            expected_order_.push_back(ch);
        }
    }

    int run() {
        try {
            for (uint64_t cycle = 0; cycle < cfg_.max_cycles; ++cycle) {
                step_cycle(cycle);
            }

            check_final_state();

            std::cout
                << "PASS: digital_core_cosim_order_tb observed the expected event order for staggered half-chip injections"
                << '\n'
                << "observed_order=" << format_sequence(first_seen_order_) << '\n'
                << "expected_order=" << format_sequence(expected_order_) << '\n'
                << "tx_started=" << static_cast<int>(tx_started_) << '\n';
        } catch (const std::exception& ex) {
            std::cerr << "harness error: " << ex.what() << '\n';
            return 1;
        }
        return 0;
    }

private:
    // PASS requires all of the following:
    // 1. Reset/default config must come up correctly and the harness must
    //    enable all channels, unmask all channels, disable interfering trigger
    //    modifiers, and enable downstream TX lane 0.
    // 2. The software analog model must observe threshold-crossing hits for
    //    channels 32-63 after the first injection and channels 0-31 after the
    //    second injection 10 cycles later.
    // 3. With the 120-cycle gap, the first 64 observed packets on
    //    digital_core.event_data/event_valid must have channel IDs in this exact order:
    //    32,33,...,63,0,1,...,31
    // 4. Every observed packet in that sequence must decode as a natural data
    //    packet for chip ID 0x01 with downstream set and valid parity.
    // 5. TX launch activity must be observed on UART0.

    void step_cycle(uint64_t cycle) {
        if (cycle == 40) {
            dut_.reset_n = 1;
        }

        prepare_analog_inputs(cycle);
        drive_digital_inputs_from_analog();
        tick();
        post_tick_checks(cycle);

        if (cfg_.verbose && (cycle % 50 == 0)) {
            std::cout << "cycle=" << cycle
                      << " event_count=" << first_seen_order_.size()
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

        if (cycle == cfg_.first_inject_cycle) {
            for (std::size_t ch = kHalfChannels; ch < kNumChannels; ++ch) {
                in.charge_in_r[ch] = cfg_.inject_charge;
            }
        }
        if (cycle == cfg_.second_inject_cycle) {
            for (std::size_t ch = 0; ch < kHalfChannels; ++ch) {
                in.charge_in_r[ch] = cfg_.inject_charge;
            }
        }

        analog_.step(in);

        if (cycle >= cfg_.first_inject_cycle) {
            upper_hits_seen_ = upper_hits_seen_ || range_all_set(analog_.outputs().hit, kHalfChannels, kNumChannels);
        }
        if (cycle >= cfg_.second_inject_cycle) {
            lower_hits_seen_ = lower_hits_seen_ || range_all_set(analog_.outputs().hit, 0, kHalfChannels);
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

    static std::bitset<kNumChannels> qdata_to_bitset(uint64_t value) {
        return std::bitset<kNumChannels>(value);
    }

    static bool range_all_set(const std::bitset<kNumChannels>& bits, std::size_t begin, std::size_t end) {
        for (std::size_t ch = begin; ch < end; ++ch) {
            if (!bits.test(ch)) {
                return false;
            }
        }
        return true;
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
            const uint64_t packet = root().digital_core__DOT__event_data;
            const std::size_t channel = static_cast<std::size_t>((packet >> 10U) & 0x3fU);
            validate_packet(packet, channel);
            observed_packets_.push_back(packet);
            if (!channel_seen_.test(channel)) {
                channel_seen_.set(channel);
                first_seen_order_.push_back(channel);
            }
        }

        if (root().digital_core__DOT__external_interface_inst__DOT____Vcellout__g_uart__BRA__0__KET____DOT__uart_inst__tx_busy) {
            tx_started_ = true;
        }
    }

    void check_defaults() {
        expect(root().digital_core__DOT__config_bits[CHIP_ID] == kDefaultChipId,
            "default chip ID should load as 0x01");
        expect((root().digital_core__DOT__config_bits[ENABLE_POSI] & 0x0Fu) == 0x0Fu,
            "default POSI enables should load as 0xF");
        expect((dut_.tx_enable & 0x0Fu) == 0u,
            "TX lanes should be disabled by default");
        expect((dut_.sample & 0x1u) == 1u,
            "sample should idle high after reset");
    }

    void apply_test_config() {
        auto& cfg_bits = root().digital_core__DOT__config_bits;
        for (std::size_t byte = 0; byte < 8; ++byte) {
            cfg_bits[CSA_ENABLE + byte] = 0xffu;
            cfg_bits[CHANNEL_MASK + byte] = 0x00u;
        }
        cfg_bits[ENABLE_TRIG_MODES] = 0x00;
        cfg_bits[DIGITAL] = 0x00;
        cfg_bits[ENABLE_PISO_DOWN] = 0x01;
    }

    void check_test_config() {
        expect((dut_.tx_enable & 0x0Fu) == 0x1u,
            "TX lane 0 should enable after config poke");
        for (std::size_t byte = 0; byte < 8; ++byte) {
            expect(root().digital_core__DOT__config_bits[CSA_ENABLE + byte] == 0xffu,
                "all channels should be enabled after config poke");
            expect(root().digital_core__DOT__config_bits[CHANNEL_MASK + byte] == 0x00u,
                "all channels should be unmasked after config poke");
        }
    }

    void validate_packet(uint64_t packet, std::size_t channel) {
        expect((packet & 0x3u) == 0x1u,
            "observed packet type should be DATA_OP");
        expect(((packet >> 2U) & 0xffU) == kDefaultChipId,
            "observed packet chip ID should be 0x01");
        expect(channel < kNumChannels,
            "observed packet channel ID should be valid");
        expect(((packet >> 56U) & 0x3u) == 0u,
            "observed packet trigger type should be natural");
        expect(((packet >> 62U) & 0x1u) == 1u,
            "observed packet downstream flag should be set");
        expect(check_parity(packet),
            "observed packet parity should be valid");
    }

    void check_final_state() {
        expect(defaults_checked_, "default checks never ran");
        expect(config_checked_, "config checks never ran");
        expect(upper_hits_seen_, "channels 32-63 never all asserted hit after the first injection");
        expect(lower_hits_seen_, "channels 0-31 never all asserted hit after the second injection");
        expect(first_seen_order_.size() == kNumChannels,
            (std::string("expected 64 unique event channels, saw ") + std::to_string(first_seen_order_.size())
                + ": " + format_sequence(first_seen_order_)).c_str());
        expect(first_seen_order_ == expected_order_,
            (std::string("unexpected first-seen order: observed=") + format_sequence(first_seen_order_)
                + " expected=" + format_sequence(expected_order_)).c_str());
        expect(tx_started_, "UART0 never asserted tx_busy during the ordered-injection test");
    }

    static bool check_parity(uint64_t packet) {
        const uint64_t payload = packet & ((1ULL << 63U) - 1ULL);
        const bool parity_bit = ((packet >> 63U) & 0x1u) != 0;
        return parity_bit == !has_odd_parity(payload);
    }

    static bool has_odd_parity(uint64_t value) {
        bool parity = false;
        while (value != 0) {
            parity = !parity;
            value &= (value - 1ULL);
        }
        return parity;
    }

    static std::string format_sequence(const std::vector<std::size_t>& seq) {
        std::ostringstream oss;
        for (std::size_t i = 0; i < seq.size(); ++i) {
            if (i != 0) {
                oss << ',';
            }
            oss << seq[i];
        }
        return oss.str();
    }

    static void expect(bool condition, const std::string& message) {
        if (!condition) {
            throw std::runtime_error(message);
        }
    }

    HarnessConfig cfg_;
    Vdigital_core dut_{};
    AnalogCoreModel analog_{};
    vluint64_t main_time_ = 0;
    bool defaults_checked_ = false;
    bool config_checked_ = false;
    bool upper_hits_seen_ = false;
    bool lower_hits_seen_ = false;
    bool tx_started_ = false;
    std::bitset<kNumChannels> channel_seen_{};
    std::vector<uint64_t> observed_packets_{};
    std::vector<std::size_t> first_seen_order_{};
    std::vector<std::size_t> expected_order_{};

    void tick() {
        main_time_ += kHalfPeriodTicks;
        dut_.clk = 0;
        dut_.eval();
        main_time_ += kHalfPeriodTicks;
        dut_.clk = 1;
        dut_.eval();
    }
};

HarnessConfig parse_args(int argc, char** argv) {
    HarnessConfig cfg;
    for (int i = 1; i < argc; ++i) {
        const std::string arg = argv[i];
        if (arg == "--cycles" && i + 1 < argc) {
            cfg.max_cycles = std::strtoull(argv[++i], nullptr, 0);
        } else if (arg == "--first-inject-cycle" && i + 1 < argc) {
            cfg.first_inject_cycle = std::strtoull(argv[++i], nullptr, 0);
        } else if (arg == "--second-inject-cycle" && i + 1 < argc) {
            cfg.second_inject_cycle = std::strtoull(argv[++i], nullptr, 0);
        } else if (arg == "--inject-charge" && i + 1 < argc) {
            cfg.inject_charge = std::strtod(argv[++i], nullptr);
        } else if (arg == "--posi-idle" && i + 1 < argc) {
            cfg.posi_idle = static_cast<uint8_t>(std::strtoul(argv[++i], nullptr, 0));
        } else if (arg == "--verbose") {
            cfg.verbose = true;
        } else {
            throw std::invalid_argument("unknown argument: " + arg);
        }
    }
    if (cfg.second_inject_cycle <= cfg.first_inject_cycle) {
        throw std::invalid_argument("second-inject-cycle must be greater than first-inject-cycle");
    }
    return cfg;
}

} // namespace

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    try {
        const HarnessConfig cfg = parse_args(argc, argv);
        DigitalCoreCosimOrderHarness harness(cfg);
        return harness.run();
    } catch (const std::exception& ex) {
        std::cerr << "fatal: " << ex.what() << '\n';
        return 1;
    }
}
